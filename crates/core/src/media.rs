use std::path::{Path, PathBuf};

/// A normalized media source accepted by the application core.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MediaSource {
    LocalFile(PathBuf),
    NetworkUrl(String),
}

impl MediaSource {
    pub fn local_file(path: impl Into<PathBuf>) -> Self {
        Self::LocalFile(path.into())
    }

    pub fn path(&self) -> Option<&Path> {
        match self {
            Self::LocalFile(path) => Some(path.as_path()),
            Self::NetworkUrl(_) => None,
        }
    }

    pub fn display_name(&self) -> String {
        match self {
            Self::LocalFile(path) => path
                .file_name()
                .and_then(|name| name.to_str())
                .map(str::to_owned)
                .unwrap_or_else(|| path.to_string_lossy().into_owned()),
            Self::NetworkUrl(url) => url.to_owned(),
        }
    }
}

/// Backend-independent selectable media track.
///
/// `id` is intentionally opaque to the UI. Backends may use sparse or negative identifiers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MediaTrack {
    pub id: i32,
    pub name: String,
}

impl MediaTrack {
    pub fn new(id: i32, name: impl Into<String>) -> Self {
        Self {
            id,
            name: name.into(),
        }
    }
}

/// Runtime information discovered after a file has been handed to the playback backend.
///
/// This is deliberately small for the first vertical slice. Deep codec/container inspection
/// belongs to the later media-inspection subsystem rather than the playback hot path.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct MediaRuntimeInfo {
    pub file_size_bytes: Option<u64>,
    pub video_width: u32,
    pub video_height: u32,
    pub audio_tracks: Vec<MediaTrack>,
    pub subtitle_tracks: Vec<MediaTrack>,
    pub selected_audio_id: Option<i32>,
    pub selected_subtitle_id: Option<i32>,
}

impl MediaRuntimeInfo {
    pub fn selected_audio_index(&self) -> Option<usize> {
        self.selected_audio_id
            .and_then(|selected| self.audio_tracks.iter().position(|track| track.id == selected))
    }

    pub fn selected_subtitle_index(&self) -> Option<usize> {
        self.selected_subtitle_id.and_then(|selected| {
            self.subtitle_tracks
                .iter()
                .position(|track| track.id == selected)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn local_file_uses_file_name_for_display() {
        let source = MediaSource::local_file("/tmp/example-video.mkv");
        assert_eq!(source.display_name(), "example-video.mkv");
    }

    #[test]
    fn selected_track_indices_handle_sparse_backend_ids() {
        let info = MediaRuntimeInfo {
            audio_tracks: vec![MediaTrack::new(2, "Stereo"), MediaTrack::new(41, "Commentary")],
            subtitle_tracks: vec![MediaTrack::new(-1, "Disable"), MediaTrack::new(7, "English")],
            selected_audio_id: Some(41),
            selected_subtitle_id: Some(-1),
            ..MediaRuntimeInfo::default()
        };

        assert_eq!(info.selected_audio_index(), Some(1));
        assert_eq!(info.selected_subtitle_index(), Some(0));
    }
}
