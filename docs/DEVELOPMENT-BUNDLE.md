# Aperture development bundle

Extract the complete folder before running aperture.exe. Keep the Qt DLLs, VLC DLLs,
plugins and QML modules beside it. The name is provisional.

This is an unsigned development build, not a finished installer. Core playback is
still under validation. Automated CI exercises startup, a generated WAV file,
play/pause, seek, volume, mute, stop and basic window transitions. Those checks do
not establish video quality, hardware decoding, HDR correctness or device compatibility.

Local playback requires no account. No app telemetry, update service or downloader
is enabled. Native media parsers are not process-isolated yet.

Third-party native libraries remain dynamically replaceable. Upstream license
files included with the distributions are in licenses/. Qt: https://www.qt.io/
VideoLAN libVLC package: https://www.nuget.org/packages/VideoLAN.LibVLC.Windows/3.0.23.1
A release still requires a complete redistribution and license inventory.
