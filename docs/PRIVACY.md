# Privacy behavior — foundation milestone

This checkpoint is local-first by construction.

- No account, telemetry, analytics, advertising, update checker, cloud API, downloader, subtitle lookup, metadata service, casting discovery, or media-library scanner is implemented.
- The UI accepts local file URLs only; direct network URLs are rejected in the current milestone.
- A local playlist, manifest, subtitle, or media file can still cause libVLC or a codec/demuxer to reference external resources. `--no-metadata-network-access` disables optional metadata/artwork lookup, but it is not a general network firewall.
- libVLC is not loaded at application startup. It is created on the playback worker only after the first local file is opened.
- Filenames and playback history are not persisted or uploaded by Aperture code.
- No background service is installed or started by this project.

A future strict Offline Mode must be enforced as a central network policy rather than relying only on UI validation or libVLC metadata flags. Until that exists, this milestone should be described as local-first, not as providing a hard guarantee that opening arbitrary local media can never trigger network access through third-party media components.
