# Aperture (working name)

Native Rust + Qt/QML media application foundation.

This repository is the first implementation slice: a deliberately small local media player built around CXX-Qt and libVLC 3.x. It is separate from MediaShell.

## Current milestone

Implemented in source:

- Qt 6/QML desktop shell
- centralized design tokens and reusable controls
- local open-file dialog
- drag/drop
- lazy libVLC loading with metadata-network access explicitly disabled for local playback
- bounded dedicated playback worker so libVLC and filesystem media-open work stay off the QML/UI thread
- native-window video rendering (no QML frame-copy playback path)
- play/pause and stop
- seek and ±5 second shortcuts
- volume and mute
- fullscreen with restoration of the previous maximized/windowed state
- audio-track and subtitle-track discovery/selection
- lightweight media information: file path, file size, duration, video dimensions, track counts/selections and playback state
- non-blocking error strip that does not cover or tear down active video for recoverable errors
- pure-Rust action/playback/media domain types with unit tests
- distinct empty/opening/buffering/playing/paused/stopped/ended/error states

The first milestone is **not yet build-verified** in this environment; see Verification status below.

## Dependencies

- Rust 1.98.1 (pinned in `rust-toolchain.toml`)
- C++17 compiler
- Qt 6.8+ (`WindowContainer`, used for native video embedding, was introduced in Qt 6.8)
- libVLC 3.x at runtime

The libVLC loader searches:

1. `APERTURE_LIBVLC_PATH`
2. beside the executable
3. an executable-adjacent `vlc/` directory
4. standard VLC install locations on Windows
5. the OS library search path on Unix-like systems

For Windows packaging, the final bundle will include the required libVLC DLLs and plugin directory rather than depending on a separately installed VLC. The loader deliberately does not fall back to an unqualified `libvlc.dll` search on Windows.

## Build

```bash
cargo build --release
```

Run:

```bash
cargo run --release -p aperture-app
```

## Reliability update

This checkpoint continues the existing source; it is not a rewrite.

- Worker reports distinguish pending commands from completed snapshots. The UI keeps polling until paused seeks, track changes, and initial opens are acknowledged.
- Queue rejection does not create phantom pending work. Worker exit clears outstanding work.
- Shutdown bypasses a full queue and skips stale commands. It still waits for the current native call and releases libVLC before the video window is destroyed.
- Added Stop and shared QML Action objects for transport buttons and shortcuts.
- Fixed CXX-Qt scalar getter/reference handling, imported its backing-state trait, and removed an invalid QWindow method call.
- Unix backend paths preserve their original bytes at the native boundary. Qt file-dialog paths remain subject to Qt's Unicode representation.
- The controller can replace a terminated backend on a later open attempt.
- Transport and track selectors use separate rows to reduce crowding.

## Verification status

**Source checkpoint, not a release or a verified runnable player.**

The current environment has no Rust/Cargo, Qt development kit, or libVLC. The package-manager attempt failed due to container user/group restrictions; the official Rust download host timed out. No native build, Rust test, QML compile, window launch, or media playback test has completed here. No executable is included.

Seven regression tests were added for command acknowledgement, queue saturation, worker failure, shutdown signalling, and native path handling. They are written but not executed. `docs/verification.json` records the actual blocked build-gate result.

On a machine with the dependencies listed above, run the development-only gate:

```bash
python tools/verify.py --release --report docs/verification.json
```

Or run the native commands directly (Python is not an application dependency):

```bash
cargo test -p aperture-core -p aperture-vlc
cargo check -p aperture-app
cargo test -p aperture-app
cargo build --release -p aperture-app
```

A successful build still needs window, playback, seek, resize, fullscreen, track-selection and shutdown tests on Windows before packaging. A Cargo output executable is not yet a distributable application bundle.

See `docs/ARCHITECTURE.md` for boundaries and known technical debt, and `docs/PRIVACY.md` for the current network/privacy surface.

## Windows CI

The `Native Windows player` workflow builds on Windows 2022 with Qt 6.8.3/MSVC
and the pinned Rust toolchain. Successful runs attach a development folder with
Qt and libVLC plus build evidence. Startup and generated-WAV transport smoke
tests must pass before a bundle is uploaded. No release has been published.
See `tools/windows-build.ps1` and `docs/DEVELOPMENT-BUNDLE.md`.
