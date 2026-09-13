# Aperture (working name)

Native Rust + Qt/QML media application foundation. This project is separate from MediaShell.

Aperture is currently a small, local-first player foundation built around CXX-Qt and libVLC 3.x. It is a **CI-verified development milestone, not a production release**.

## Current milestone

Implemented in source:

- Qt 6/QML desktop shell with centralized design tokens and reusable controls
- local open-file dialog and drag/drop
- lazy libVLC loading; the playback backend is created only when media is opened
- bounded dedicated playback worker so native playback/filesystem open work stays off the QML UI thread
- native-window video target through Qt `WindowContainer` (no decoded-frame copy path through QML)
- play/pause, stop, seeking, volume, mute and fullscreen
- ±5 second and basic playback shortcuts
- audio/subtitle track discovery and selection
- media information: path, size, duration, video dimensions, track counts/selections and playback state
- transactional media-open state so a requested file is not published as loaded until playback reaches a confirmed playable state
- two-phase window shutdown that keeps the native video surface alive while libVLC unwinds
- non-blocking recoverable-error strip
- distinct empty/opening/buffering/playing/paused/stopped/ended/error states
- pure-Rust action/playback/media domain types with unit tests

## Dependencies

- Rust 1.98.1 (pinned in `rust-toolchain.toml`)
- C++17 compiler
- Qt 6.8+ (`WindowContainer` was introduced in Qt 6.8)
- libVLC 3.x at runtime

The libVLC loader searches:

1. `APERTURE_LIBVLC_PATH`
2. beside the executable
3. an executable-adjacent `vlc/` directory
4. standard VLC install locations on Windows
5. the OS library search path on Unix-like systems

The Windows development bundle includes the required libVLC DLLs/plugins and Qt runtime rather than requiring a separate VLC installation. The VideoLAN runtime package is pinned by version and SHA-256 in `tools/windows-build.ps1`.

## Build

```bash
cargo build --release
```

Run:

```bash
cargo run --release -p aperture-app
```

## Reliability behavior

- Worker reports distinguish queued work from completed snapshots, so stale state cannot acknowledge an unprocessed command.
- Queue rejection does not create phantom pending work; worker exit clears outstanding work.
- Media identity is committed only after libVLC reaches a confirmed playable state. Failed or rapid replacement opens do not publish the wrong title/path as loaded.
- Playback startup/resume keeps polling across libVLC's transient idle states.
- Normal window close requests worker cancellation without blocking Qt, polls for native shutdown completion, then destroys the Qt window.
- Qt platform-surface destruction invalidates the cached native video handle and recreation publishes the replacement handle for rebinding.
- A zero native handle is forwarded to the backend as a detach request rather than silently ignored.
- The controller can replace a terminated backend on a later open attempt.
- Unix backend paths preserve their original bytes at the native boundary. Windows paths are normalized only at the libVLC 3 path boundary.

Native-surface detachment is currently delivered through the playback worker queue. This substantially hardens surface recreation, but it is not yet a strict synchronization guarantee that libVLC processes the detach before Qt finishes destroying a platform surface. That remains lifecycle debt to address before calling the player production-ready.

## Verification status

The `Native Windows player` GitHub Actions gate has verified the packaged application on **Windows Server 2022**, **Qt 6.8.3 / MSVC 2022**, **Rust 1.98.1**, and the pinned bundled **libVLC 3.x** runtime.

The verified gate currently includes:

- 4 `aperture-core` unit tests
- 10 `aperture-vlc` unit tests
- 3 `aperture-app` / controller tests
- optimized release compilation
- Qt runtime deployment and bundled libVLC packaging
- packaged-process startup
- generated WAV playback: play, pause, seek, resume and stop
- resize/fullscreen transition smoke coverage
- close while audio playback is active
- generated 64×64 BGR24 AVI playback reaching `Playing`, advancing its clock and reporting video dimensions
- close while video playback is active
- checks for QML binding loops, `ReferenceError` and `TypeError` in smoke output

All smoke media is generated locally by the test harness. The test suite does not download third-party sample media, and Python remains development tooling rather than an application runtime dependency.

This evidence does **not** yet prove:

- a broad real-world codec/container compatibility matrix
- subtitle rendering correctness on representative fixtures
- pixel-level visual correctness of rendered video frames
- hardware-decoding paths or GPU-vendor coverage
- behavior with a physical audio device/mixer (CI uses libVLC's dummy audio sink)
- production installer/signing/upgrades
- strict offline/network isolation
- production readiness

`docs/verification.json` records the current machine-readable verification checkpoint. See `docs/ARCHITECTURE.md` for boundaries/technical debt and `docs/PRIVACY.md` for the current network/privacy surface.

## Development verification

Run the local development gate:

```bash
python tools/verify.py --release --report docs/verification.json
```

Or run the native commands directly:

```bash
cargo test -p aperture-core -p aperture-vlc
cargo test --release -p aperture-app
cargo build --release -p aperture-app
```

## Windows CI

The `Native Windows player` workflow builds on Windows 2022 with Qt 6.8.3/MSVC and the pinned Rust toolchain. A successful run uploads build evidence and a tested development folder containing the application, Qt runtime and libVLC runtime.

The uploaded folder is a **development bundle**, not a release installer. No production release has been published. See `tools/windows-build.ps1` and `docs/DEVELOPMENT-BUNDLE.md`.
