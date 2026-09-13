# Privacy behavior — foundation milestone

This checkpoint is local-first by construction.

- No account, telemetry, analytics, advertising, update checker, cloud API, downloader, subtitle lookup, metadata service, casting discovery, or media-library scanner is implemented.
- The UI accepts local file URLs only. Network playback is deliberately rejected in the current milestone.
- libVLC is not loaded at application startup. It is created on the playback worker only after the first local file is opened.
- libVLC is started with `--no-metadata-network-access` so optional artwork/metadata lookup is disabled explicitly for local playback.
- Filenames and playback history are not persisted or uploaded by this code.
- No background service is installed or started by this project.

A strict offline-mode switch will become meaningful when intentional network features are added. It should then gate those capabilities centrally rather than relying on every UI surface to remember the preference independently.
