$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
$bundle = Join-Path $projectRoot 'build/aperture-windows-x64'
$installerDir = Join-Path $projectRoot 'build/installer'
$evidence = Join-Path $projectRoot 'build/evidence'
$installerScript = Join-Path $PSScriptRoot 'windows-installer.iss'

if (!(Test-Path (Join-Path $bundle 'aperture.exe'))) {
    throw 'The tested Windows bundle must exist before building the installer.'
}

$workspaceManifest = Get-Content (Join-Path $projectRoot 'Cargo.toml') -Raw
$versionMatch = [regex]::Match($workspaceManifest, '(?ms)^\[workspace\.package\].*?^version\s*=\s*"([^"]+)"')
if (!$versionMatch.Success) {
    throw 'Could not determine the Aperture workspace version from Cargo.toml.'
}
$appVersion = $versionMatch.Groups[1].Value

$isccCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6/ISCC.exe')
)
$iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (!$iscc) {
    choco install innosetup --yes --no-progress
    if ($LASTEXITCODE) { throw 'Inno Setup installation failed.' }
    $iscc = $isccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (!$iscc) {
    throw 'Inno Setup compiler was not found after installation.'
}

if (Test-Path $installerDir) {
    Remove-Item $installerDir -Recurse -Force
}
New-Item -ItemType Directory -Force $installerDir, $evidence | Out-Null

& $iscc "/DMyAppVersion=$appVersion" $installerScript
if ($LASTEXITCODE) { throw 'Inno Setup compilation failed.' }

$setups = @(Get-ChildItem $installerDir -File -Filter 'Aperture-Setup-x64.exe')
if ($setups.Count -ne 1) {
    throw 'The installer build did not produce exactly one Aperture-Setup-x64.exe.'
}
$setup = $setups[0]
$setupHash = (Get-FileHash $setup.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
$innoVersion = (Get-Item $iscc).VersionInfo.FileVersion
[PSCustomObject]@{
    AppVersion = $appVersion
    InnoSetupVersion = $innoVersion
    File = $setup.Name
    Bytes = $setup.Length
    SHA256 = $setupHash
} | ConvertTo-Json | Out-File (Join-Path $evidence 'installer-metrics.json')

# Prove the one-file installer reconstructs the tested bundle correctly. Install per-user into a
# throwaway directory, run the same packaged playback/shutdown suite from that installed copy, and
# then exercise the generated uninstaller. Inno Setup is a GUI-subsystem executable, so invoke it
# through Start-Process -Wait instead of relying on PowerShell's native-command waiting semantics.
$installDir = Join-Path $projectRoot 'build/installer-smoke-install'
if (Test-Path $installDir) {
    Remove-Item $installDir -Recurse -Force
}
$installerLog = Join-Path $evidence 'installer-install.log'
$installArguments = @(
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/SP-',
    "/DIR=$installDir",
    "/LOG=$installerLog"
)
$installProcess = Start-Process -FilePath $setup.FullName -ArgumentList $installArguments -Wait -PassThru
if ($installProcess.ExitCode -ne 0) {
    throw "Installer smoke installation failed with exit code $($installProcess.ExitCode)."
}

$installedExe = Join-Path $installDir 'aperture.exe'
if (!(Test-Path $installedExe)) {
    throw 'Installer completed but aperture.exe was not installed.'
}

$installedEvidence = Join-Path $evidence 'installed-bundle-smoke'
python tools/smoke_windows.py $installDir $installedEvidence
if ($LASTEXITCODE) { throw 'The installed Aperture copy failed packaged playback smoke tests.' }

$uninstaller = Join-Path $installDir 'unins000.exe'
if (!(Test-Path $uninstaller)) {
    throw 'The installer did not create an uninstaller.'
}
$uninstallProcess = Start-Process -FilePath $uninstaller -ArgumentList @(
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART'
) -Wait -PassThru
if ($uninstallProcess.ExitCode -ne 0) {
    throw "Installer smoke uninstall failed with exit code $($uninstallProcess.ExitCode)."
}
Start-Sleep -Milliseconds 750
if (Test-Path $installedExe) {
    throw 'The Aperture uninstaller left the installed executable behind.'
}

"Installer PASS: $($setup.Name) / $($setup.Length) bytes / SHA256=$setupHash"
