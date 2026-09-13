param(
    [string]$Bundle,
    [string]$Evidence
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path $PSScriptRoot -Parent
if ([string]::IsNullOrWhiteSpace($Bundle)) {
    $Bundle = Join-Path $projectRoot 'build/aperture-windows-x64'
}
if ([string]::IsNullOrWhiteSpace($Evidence)) {
    $Evidence = Join-Path $projectRoot 'build/evidence'
}

$Bundle = [System.IO.Path]::GetFullPath($Bundle)
$Evidence = [System.IO.Path]::GetFullPath($Evidence)
$exe = Join-Path $Bundle 'aperture.exe'
$screenshot = Join-Path $Evidence 'ui-empty-state.png'
$stdout = Join-Path $Evidence 'ui-empty-state.stdout.log'
$stderr = Join-Path $Evidence 'ui-empty-state.stderr.log'
$metadata = Join-Path $Evidence 'ui-empty-state.json'
$peHeadersLog = Join-Path $Evidence 'aperture-pe-headers.txt'

if (!(Test-Path $exe)) {
    throw "Packaged Aperture executable not found: $exe"
}
New-Item -ItemType Directory -Force $Evidence | Out-Null
Remove-Item $screenshot, $stdout, $stderr, $metadata, $peHeadersLog -Force -ErrorAction SilentlyContinue

# A release desktop application must use the GUI subsystem. A console-subsystem regression is not
# cosmetic: Windows will create the black terminal window that exposed internal Qt/VLC logs in the
# previous installer. Keep the full PE headers as build evidence and fail before launch if wrong.
$peHeaders = (& dumpbin.exe /HEADERS $exe 2>&1 | Out-String)
$dumpbinExit = $LASTEXITCODE
$peHeaders | Out-File $peHeadersLog -Encoding utf8
if ($dumpbinExit) {
    throw "dumpbin failed while validating aperture.exe (exit code $dumpbinExit)."
}
if ($peHeaders -notmatch '(?i)\bsubsystem\s+\(Windows GUI\)') {
    throw 'Release aperture.exe is not linked as a Windows GUI-subsystem application.'
}
if ($peHeaders -match '(?i)\bsubsystem\s+\(Windows CUI\)') {
    throw 'Release aperture.exe unexpectedly declares the Windows console subsystem.'
}

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class ApertureUiCaptureNative {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
Add-Type -AssemblyName System.Drawing

$process = $null
$captured = $false
try {
    $process = Start-Process `
        -FilePath $exe `
        -WorkingDirectory $Bundle `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru

    $deadline = (Get-Date).AddSeconds(20)
    $handle = [IntPtr]::Zero
    do {
        Start-Sleep -Milliseconds 100
        $process.Refresh()
        if ($process.HasExited) {
            throw "Aperture exited before exposing a main window (exit code $($process.ExitCode))."
        }
        $handle = $process.MainWindowHandle
    } while ($handle -eq [IntPtr]::Zero -and (Get-Date) -lt $deadline)

    if ($handle -eq [IntPtr]::Zero) {
        throw 'Aperture did not expose a main window within 20 seconds.'
    }

    try {
        $null = $process.WaitForInputIdle(5000)
    } catch {
        # Some Qt startup paths can report that WaitForInputIdle is unavailable even though the
        # top-level window already exists. The handle gate above is authoritative for capture.
    }

    [void][ApertureUiCaptureNative]::ShowWindow($handle, 9) # SW_RESTORE
    [void][ApertureUiCaptureNative]::SetForegroundWindow($handle)
    Start-Sleep -Milliseconds 1200

    $process.Refresh()
    if ($process.HasExited) {
        throw "Aperture exited before the UI screenshot was captured (exit code $($process.ExitCode))."
    }
    $handle = $process.MainWindowHandle
    if ($handle -eq [IntPtr]::Zero) {
        throw 'Aperture lost its main window before UI capture.'
    }

    $rect = New-Object ApertureUiCaptureNative+RECT
    if (![ApertureUiCaptureNative]::GetWindowRect($handle, [ref]$rect)) {
        throw "GetWindowRect failed with Win32 error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())."
    }

    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -lt 640 -or $height -lt 400) {
        throw "Aperture main window has an implausible capture size: ${width}x${height}."
    }

    $bitmap = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
        $bitmap.Save($screenshot, [System.Drawing.Imaging.ImageFormat]::Png)
    } finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }

    [PSCustomObject]@{
        File = [System.IO.Path]::GetFileName($screenshot)
        WindowTitle = $process.MainWindowTitle
        Left = $rect.Left
        Top = $rect.Top
        Width = $width
        Height = $height
        Bytes = (Get-Item $screenshot).Length
        GuiSubsystemVerified = $true
    } | ConvertTo-Json | Out-File $metadata -Encoding utf8
    $captured = $true
} finally {
    if ($null -ne $process -and !$process.HasExited) {
        $process.Refresh()
        $closed = $process.CloseMainWindow()
        if (!$closed -or !$process.WaitForExit(10000)) {
            $process.Kill()
            $process.WaitForExit()
        }
    }
}

if (!$captured -or !(Test-Path $screenshot) -or (Get-Item $screenshot).Length -lt 4096) {
    throw 'The packaged Aperture UI screenshot was not captured successfully.'
}

$runtimeText = ''
if (Test-Path $stdout) { $runtimeText += Get-Content $stdout -Raw }
if (Test-Path $stderr) { $runtimeText += "`n" + (Get-Content $stderr -Raw) }

$forbiddenRuntimeMarkers = @(
    'does not support customization',
    'Binding loop',
    'ReferenceError',
    'TypeError',
    'Failed to load component',
    'is not a type'
)
foreach ($marker in $forbiddenRuntimeMarkers) {
    if ($runtimeText.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
        throw "Packaged main-window launch emitted forbidden QML/runtime marker: $marker"
    }
}

"UI capture PASS: $screenshot ($((Get-Item $screenshot).Length) bytes)"
