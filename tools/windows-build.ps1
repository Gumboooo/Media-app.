$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
$evidence = Join-Path $projectRoot 'build/evidence'
$bundle = Join-Path $projectRoot 'build/aperture-windows-x64'

# A package build must start from an empty destination. Otherwise changing deployment flags can
# leave stale Qt/VLC files behind and make both smoke tests and size measurements misleading.
if (Test-Path $bundle) {
    Remove-Item $bundle -Recurse -Force
}
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
    # The Qt/CXX bridge dominates compile time. Test it in the same release profile used by the
    # package so Cargo can reuse those native objects instead of compiling the bridge twice.
    cargo test --release -p aperture-app
    if ($LASTEXITCODE) { throw 'Qt controller tests failed.' }
    cargo build --release -p aperture-app
    if ($LASTEXITCODE) { throw 'Release build failed.' }
    Copy-Item 'target/release/aperture.exe' $bundle -Force

    # Aperture is English-only today. Shipping Qt's complete translation catalog adds several MiB
    # without exposing any translated application UI, so omit it until localization is implemented.
    & (Join-Path $env:QT_ROOT_DIR 'bin/windeployqt.exe') --release --compiler-runtime --no-translations --qmldir 'crates/app/qml' --dir $bundle (Join-Path $bundle 'aperture.exe')
    if ($LASTEXITCODE) { throw 'Qt dependency deployment failed.' }

    # windeployqt includes the QML debugger/profiler plugins because QtQml supports them. The
    # release executable does not enable QML debugging, so these tools are not runtime dependencies.
    $qmlTooling = Join-Path $bundle 'qmltooling'
    if (Test-Path $qmlTooling) {
        Remove-Item $qmlTooling -Recurse -Force
    }

    # Official VideoLAN native package; NuGet is only a distribution format, not a .NET runtime.
    # Pin both version and bytes so a changed upstream package cannot silently enter the bundle.
    $vlcVersion = '3.0.23.1'
    $expectedVlcSha256 = '70927AFA9AD34B77E7D9A5E6D02CAE099771F6EB3114DA18111A4B76F65B836F'
    $package = Join-Path $projectRoot 'build/libvlc.zip'
    $packageRoot = Join-Path $projectRoot 'build/libvlc-package'
    Invoke-WebRequest "https://api.nuget.org/v3-flatcontainer/videolan.libvlc.windows/$vlcVersion/videolan.libvlc.windows.$vlcVersion.nupkg" -OutFile $package -TimeoutSec 180 -MaximumRetryCount 2
    $vlcHash = (Get-FileHash $package -Algorithm SHA256).Hash.ToUpperInvariant()
    "SHA256=$vlcHash" | Out-File (Join-Path $evidence 'libvlc-package-sha256.txt')
    if ($vlcHash -ne $expectedVlcSha256) {
        throw "VideoLAN package digest mismatch. Expected $expectedVlcSha256 but received $vlcHash."
    }
    Expand-Archive $package -DestinationPath $packageRoot -Force
    $vlcDlls = @(Get-ChildItem $packageRoot -Recurse -Filter libvlc.dll | Where-Object { $_.FullName.Replace('\', '/') -match '/(x64|win-x64)/' })
    if ($vlcDlls.Count -ne 1) { throw 'Cannot uniquely identify the x64 libVLC runtime.' }
    Copy-Item (Join-Path $vlcDlls[0].DirectoryName '*') $bundle -Recurse -Force
    if (!(Test-Path (Join-Path $bundle 'libvlccore.dll')) -or !(Test-Path (Join-Path $bundle 'plugins'))) { throw 'Incomplete VLC runtime bundle.' }

    # The VideoLAN native package places C headers and linker import libraries beside the runtime.
    # They are for developers linking against libVLC and are never loaded by Aperture at runtime.
    $vlcInclude = Join-Path $bundle 'include'
    if (Test-Path $vlcInclude) {
        Remove-Item $vlcInclude -Recurse -Force
    }
    Get-ChildItem $bundle -File -Filter '*.lib' | Remove-Item -Force

    if (Test-Path $vlcInclude) { throw 'Development-only libVLC headers leaked into the bundle.' }
    if (@(Get-ChildItem $bundle -File -Filter '*.lib').Count -ne 0) { throw 'Development-only libVLC import libraries leaked into the bundle.' }
    if (Test-Path $qmlTooling) { throw 'QML debugging plugins leaked into the release bundle.' }
    if (Test-Path (Join-Path $bundle 'translations')) { throw 'Qt translations leaked into the English-only bundle.' }

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

    # Test the exact pruned directory that will be uploaded. No post-smoke pruning is allowed.
    python tools/smoke_windows.py $bundle $evidence
    if ($LASTEXITCODE) { throw 'Packaged application smoke tests failed.' }

    $bundleFiles = @(Get-ChildItem $bundle -Recurse -File)
    $bundleBytes = [long](($bundleFiles | Measure-Object -Property Length -Sum).Sum)
    [PSCustomObject]@{
        Files = $bundleFiles.Count
        Bytes = $bundleBytes
        Mebibytes = [math]::Round($bundleBytes / 1MB, 2)
    } | ConvertTo-Json | Out-File (Join-Path $evidence 'bundle-metrics.json')
    "Bundle metrics: $($bundleFiles.Count) files, $bundleBytes bytes ($([math]::Round($bundleBytes / 1MB, 2)) MiB)"

    $bundleFiles | ForEach-Object {
        [PSCustomObject]@{Path=$_.FullName.Substring($bundle.Length + 1); Bytes=$_.Length; SHA256=(Get-FileHash $_.FullName).Hash}
    } | ConvertTo-Json -Depth 3 | Out-File (Join-Path $evidence 'bundle-manifest.json')
} finally {
    Stop-Transcript
}
