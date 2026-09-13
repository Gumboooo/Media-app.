# Architecture — foundation milestone

The working product name is **Aperture** only for source/package identifiers. Branding is not considered final.

## Runtime layers

- `aperture-core`: pure Rust domain types and stable action identifiers. No Qt, VLC, FFmpeg, network or filesystem-scanning side effects.
- `aperture-vlc`: a narrow libVLC 3.x dynamic ABI adapter plus a bounded dedicated playback worker. It loads only when media is first opened.
- `aperture-app`: Qt 6 / QML composition and the Rust CXX-Qt controller.
- `VideoSurface`: tiny C++ Qt adapter because native window embedding is a Qt/platform concern, not application business logic.

## Startup budget

Normal startup creates the Qt application, QML engine, player controller and one empty native video child window. It does **not** load libVLC or create the playback worker until the first local file is opened. It does not initialize FFmpeg, downloader tooling, a media library, scanners, subtitle providers or network services. When libVLC is created for local playback, metadata-network access is explicitly disabled rather than relying on ambient VLC preferences.

Once created, an idle playback worker blocks on its bounded command queue. It does not poll libVLC until a file is opening/buffering/playing. Filesystem metadata checks for opened media also run on the worker rather than the Qt thread.

## Rendering path

The QML `WindowContainer` embeds a native `QWindow`. libVLC receives that window handle and renders directly to it. The application does not copy decoded video frames through Rust or QML. Native-surface recreation is observed and the new handle is sent to the playback worker. Because native child windows stack above ordinary Qt Quick siblings, error UI and the media-info inspector are laid out outside the native video rectangle instead of pretending QML can reliably overlay it.

## Playback-state and media-info flow

Qt/QML sends bounded commands to the worker. The worker owns all libVLC calls and publishes a cheap shared `PlaybackSnapshot` plus an `Arc<MediaRuntimeInfo>`. Track descriptions are copied out of libVLC-owned linked lists into Rust-owned values and the native list is released immediately. Raw libVLC track IDs remain backend details; QML only receives counts and selected display labels.

After playback reaches `Playing`, media runtime information is refreshed a small bounded number of times because libVLC may expose dimensions/tracks shortly after startup. Track-change requests force an immediate refresh. There is no perpetual metadata scanner.

## Current source capabilities

- local file selection and drag/drop
- direct libVLC video output
- play/pause and stop
- timeline seek
- volume and mute
- fullscreen
- keyboard shortcuts
- audio/subtitle track cycling
- lightweight media-info inspector
- inline beginner-facing error messages

Not implemented yet: chapters, deep codec/container inspection, URL playback, conversion, FFmpeg integration, settings persistence, user themes/custom layouts, packaging, accessibility polish, or the future plugin/network/download subsystems.

## Important technical debt already identified

- The playback worker polls libVLC at 100 ms only while opening/buffering/playing; the QML side reads its cheap shared snapshot every 200 ms only while active. Paused/stopped playback blocks on the command queue. Event callbacks should replace most polling after the native slice is build-verified.
- The first track UI intentionally cycles tracks instead of opening an overlay menu on top of video. A proper selector should use a surface that respects native-child stacking, or switch to a rendering integration that allows safe Qt Quick overlays.
- Linux native rendering currently assumes X11 because libVLC 3's public embedding API exposes an X window ID. Windows is the first packaging target; Wayland needs a separately validated output path.
- libVLC 4 has incompatible public API signatures. The loader rejects non-3.x libraries instead of guessing across the ABI boundary.
- Drag/drop over the active native video child still needs platform verification; empty-player drag/drop is implemented in QML, but the embedded native child can affect input routing once video is visible.
- Graceful shutdown joins the playback thread so libVLC releases the native window before Qt destroys it. If a third-party backend call itself hangs indefinitely, process isolation is the robust future containment strategy rather than detaching a thread that still owns a window handle.

## Command completion contract

The queue's pending count and the playback snapshot share one mutex. Submission reserves a pending operation while holding that mutex; a completion guard releases the reservation only after the command's outcome is published, including early error paths. A worker-lifetime guard marks the worker unavailable and clears pending operations on exit. UI refresh must not treat an old idle snapshot as completion of a queued operation.

Shutdown sets an atomic cancellation flag before waking the receiver. The worker checks it before receiving and before processing, so queued media opens are not drained during close. This does not preempt a libVLC call already in progress. Process isolation and fully asynchronous close remain outstanding work.

`PlayerActions.qml` owns shared Qt Action objects, including their stable domain identifiers. Buttons bind to these objects; their shortcuts invoke the same handler. Parameterized seek/volume controls call controller methods. The Rust ActionId list and QML registry must stay aligned as actions are added.

## Upstream API checks

- CXX-Qt scalar property getters return references: https://kdab.github.io/cxx-qt/book/getting-started/2-our-first-cxx-qt-module.html
- Backing-state access uses CxxQtType: https://docs.rs/cxx-qt/latest/cxx_qt/trait.CxxQtType.html
- Native QWindow API: https://doc.qt.io/qt-6/qwindow.html

These documentation checks are not substitutes for compiling against the pinned dependencies.
