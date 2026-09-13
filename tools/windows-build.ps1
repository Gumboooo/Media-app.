$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
$evidence = Join-Path $projectRoot 'build/evidence'
$bundle = Join-Path $projectRoot 'build/aperture-windows-x64'
New-Item -ItemType Directory -Force $evidence, $bundle | Out-Null
Start-Transcript -Path (Join-Path $evidence 'build.txt')
try {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$vs) { throw 'MSVC x64 build tools are required.' }
    & (Join-Path $vs 'Common7/Tools/Launch-VsDevShell.ps1') -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
    cargo --version
    if ($LASTEXITCODE) { throw 'Rust toolchain setup failed.' }
    cargo test -p aperture-core -p aperture-vlc
    if ($LASTEXITCODE) { throw 'Rust core/backend tests failed.' }
    cargo test -p aperture-app
    if ($LASTEXITCODE) { throw 'Qt controller tests failed.' }
    cargo build --release -p aperture-app
    if ($LASTEXITCODE) { throw 'Release build failed.' }
    Copy-Item 'target/release/aperture.exe' $bundle -Force
    & (Join-Path $env:QT_ROOT_DIR 'bin/windeployqt.exe') --release --compiler-runtime --qmldir 'crates/app/qml' --dir $bundle (Join-Path $bundle 'aperture.exe')
    if ($LASTEXITCODE) { throw 'Qt dependency deployment failed.' }

    # Official VideoLAN native package; NuGet is only a distribution format, not a .NET runtime.
    $vlcVersion = '3.0.23.1'
    $package = Join-Path $projectRoot 'build/libvlc.zip'
    $packageRoot = Join-Path $projectRoot 'build/libvlc-package'
    Invoke-WebRequest "https://api.nuget.org/v3-flatcontainer/videolan.libvlc.windows/$vlcVersion/videolan.libvlc.windows.$vlcVersion.nupkg" -OutFile $package -TimeoutSec 180 -MaximumRetryCount 2
    Get-FileHash $package -Algorithm SHA256 | Format-List | Out-File (Join-Path $evidence 'libvlc-package-sha256.txt')
    Expand-Archive $package -DestinationPath $packageRoot -Force
    $vlcDlls = @(Get-ChildItem $packageRoot -Recurse -Filter libvlc.dll | Where-Object { $_.FullName.Replace('\', '/') -match '/(x64|win-x64)/' })
    if ($vlcDlls.Count -ne 1) { throw 'Cannot uniquely identify the x64 libVLC runtime.' }
    Copy-Item (Join-Path $vlcDlls[0].DirectoryName '*') $bundle -Recurse -Force
    if (!(Test-Path (Join-Path $bundle 'libvlccore.dll')) -or !(Test-Path (Join-Path $bundle 'plugins'))) { throw 'Incomplete VLC runtime bundle.' }
    $licenses = Join-Path $bundle 'licenses'
    New-Item -ItemType Directory -Force $licenses | Out-Null
    if (Test-Path (Join-Path $env:QT_ROOT_DIR 'licenses')) {
        Copy-Item (Join-Path $env:QT_ROOT_DIR 'licenses') (Join-Path $licenses 'Qt') -Recurse -Force
    }
    Get-ChildItem $packageRoot -Recurse -File | Where-Object { $_.Name -match '^(COPYING|LICENSE|NOTICE)' } | ForEach-Object {
        $relative = $_.FullName.Substring($packageRoot.Length).TrimStart('\', '/')
        $target = Join-Path (Join-Path $licenses 'VideoLAN') $relative
        New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
        Copy-Item $_.FullName $target -Force
    }
    Copy-Item 'docs/DEVELOPMENT-BUNDLE.md' $bundle
    python tools/smoke_windows.py $bundle $evidence
    if ($LASTEXITCODE) { throw 'Packaged application smoke tests failed.' }
    Get-ChildItem $bundle -Recurse -File | ForEach-Object {
        [PSCustomObject]@{Path=$_.FullName.Substring($bundle.Length + 1); Bytes=$_.Length; SHA256=(Get-FileHash $_.FullName).Hash}
    } | ConvertTo-Json -Depth 3 | Out-File (Join-Path $evidence 'bundle-manifest.json')
} finally {
    Stop-Transcript
}
