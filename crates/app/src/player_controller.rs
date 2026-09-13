use aperture_core::{MediaRuntimeInfo, MediaSource, MediaTrack, PlaybackState};
use aperture_vlc::{VideoTarget, VlcWorker};
use cxx_qt_lib::{QString, QUrl};
use cxx_qt::CxxQtType;
use std::path::PathBuf;
use std::pin::Pin;

#[cxx_qt::bridge(namespace = "aperture")]
pub mod qobject {
    #[namespace = ""]
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;

        include!("cxx-qt-lib/qurl.h");
        type QUrl = cxx_qt_lib::QUrl;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qproperty(bool, has_media, cxx_name = "hasMedia")]
        #[qproperty(bool, playing)]
        #[qproperty(bool, polling_active, cxx_name = "pollingActive")]
        #[qproperty(bool, muted)]
        #[qproperty(f64, position_ms, cxx_name = "positionMs")]
        #[qproperty(f64, duration_ms, cxx_name = "durationMs")]
        #[qproperty(i32, volume)]
        #[qproperty(i32, audio_track_count, cxx_name = "audioTrackCount")]
        #[qproperty(i32, subtitle_track_count, cxx_name = "subtitleTrackCount")]
        #[qproperty(QString, audio_track_label, cxx_name = "audioTrackLabel")]
        #[qproperty(QString, subtitle_track_label, cxx_name = "subtitleTrackLabel")]
        #[qproperty(QString, media_title, cxx_name = "mediaTitle")]
        #[qproperty(QString, media_path, cxx_name = "mediaPath")]
        #[qproperty(QString, media_size_text, cxx_name = "mediaSizeText")]
        #[qproperty(QString, video_dimensions_text, cxx_name = "videoDimensionsText")]
        #[qproperty(QString, status_text, cxx_name = "statusText")]
        #[qproperty(QString, error_text, cxx_name = "errorText")]
        type PlayerController = super::PlayerControllerRust;

        #[qinvokable]
        #[cxx_name = "attachVideoSurface"]
        fn attach_video_surface(self: Pin<&mut PlayerController>, native_handle: u64);

        #[qinvokable]
        #[cxx_name = "openUrl"]
        fn open_url(self: Pin<&mut PlayerController>, url: &QUrl);

        #[qinvokable]
        #[cxx_name = "playPause"]
        fn play_pause(self: Pin<&mut PlayerController>);

        #[qinvokable]
        fn stop(self: Pin<&mut PlayerController>);

        #[qinvokable]
        #[cxx_name = "seekTo"]
        fn seek_to(self: Pin<&mut PlayerController>, position_ms: f64);

        #[qinvokable]
        #[cxx_name = "seekBy"]
        fn seek_by(self: Pin<&mut PlayerController>, delta_ms: f64);

        #[qinvokable]
        #[cxx_name = "requestVolume"]
        fn set_volume_value(self: Pin<&mut PlayerController>, volume: i32);

        #[qinvokable]
        #[cxx_name = "toggleMute"]
        fn toggle_mute(self: Pin<&mut PlayerController>);

        #[qinvokable]
        #[cxx_name = "cycleAudioTrack"]
        fn cycle_audio_track(self: Pin<&mut PlayerController>);

        #[qinvokable]
        #[cxx_name = "cycleSubtitleTrack"]
        fn cycle_subtitle_track(self: Pin<&mut PlayerController>);

        #[qinvokable]
        fn refresh(self: Pin<&mut PlayerController>);

        #[qinvokable]
        #[cxx_name = "clearError"]
        fn clear_error(self: Pin<&mut PlayerController>);

        #[qinvokable]
        fn shutdown(self: Pin<&mut PlayerController>);
    }
}

pub struct PlayerControllerRust {
    has_media: bool,
    playing: bool,
    polling_active: bool,
    muted: bool,
    position_ms: f64,
    duration_ms: f64,
    volume: i32,
    audio_track_count: i32,
    subtitle_track_count: i32,
    audio_track_label: QString,
    subtitle_track_label: QString,
    media_title: QString,
    media_path: QString,
    media_size_text: QString,
    video_dimensions_text: QString,
    status_text: QString,
    error_text: QString,
    backend: Option<VlcWorker>,
    native_video_handle: Option<u64>,
    media_info_revision: u64,
    audio_tracks: Vec<MediaTrack>,
    subtitle_tracks: Vec<MediaTrack>,
    selected_audio_index: Option<usize>,
    selected_subtitle_index: Option<usize>,
}

impl Default for PlayerControllerRust {
    fn default() -> Self {
        Self {
            has_media: false,
            playing: false,
            polling_active: false,
            muted: false,
            position_ms: 0.0,
            duration_ms: 0.0,
            volume: 100,
            audio_track_count: 0,
            subtitle_track_count: 0,
            audio_track_label: QString::from("None"),
            subtitle_track_label: QString::from("None"),
            media_title: QString::default(),
            media_path: QString::default(),
            media_size_text: QString::from("—"),
            video_dimensions_text: QString::from("—"),
            status_text: QString::from("Ready"),
            error_text: QString::default(),
            backend: None,
            native_video_handle: None,
            media_info_revision: 0,
            audio_tracks: Vec::new(),
            subtitle_tracks: Vec::new(),
            selected_audio_index: None,
            selected_subtitle_index: None,
        }
    }
}

impl qobject::PlayerController {
    pub fn attach_video_surface(mut self: Pin<&mut Self>, native_handle: u64) {
        if native_handle == 0 {
            return;
        }
        self.as_mut().rust_mut().native_video_handle = Some(native_handle);
        let result = self.rust()
            .backend
            .as_ref()
            .map(|backend| backend.set_video_target(video_target(native_handle)));
        if let Some(Err(error)) = result {
            self.set_nonfatal_error(&error.to_string());
        }
    }

    pub fn open_url(mut self: Pin<&mut Self>, url: &QUrl) {
        self.as_mut().set_error_text(QString::default());

        let Some(local_path) = url.to_local_file() else {
            self.set_nonfatal_error(
                "This milestone opens local media only. Network playback is intentionally not enabled yet.",
            );
            return;
        };

        let path = PathBuf::from(local_path.to_string());
        // A failed loader must not leave a permanently disconnected worker in the controller.
        if self.rust().backend.as_ref().is_some_and(VlcWorker::is_finished) {
            self.as_mut().rust_mut().backend.take();
        }
        if self.rust().backend.is_none() {
            let target = self.rust().native_video_handle.map(video_target);
            match VlcWorker::spawn(target, (*self.volume()), (*self.muted())) {
                Ok(backend) => {
                    self.as_mut().rust_mut().backend = Some(backend);
                }
                Err(error) => {
                    self.set_fatal_error(&error.to_string());
                    return;
                }
            }
        }

        let result = match self.rust().backend.as_ref() {
            Some(backend) => backend.open_local(path.clone()),
            None => {
                self.set_fatal_error("The playback backend was not initialized.");
                return;
            }
        };

        match result {
            Ok(()) => {
                self.as_mut().reset_media_info();
                let source = MediaSource::local_file(path.clone());
                self.as_mut()
                    .set_media_title(QString::from(&source.display_name()));
                let path_text = path.to_string_lossy().into_owned();
                self.as_mut().set_media_path(QString::from(&path_text));
                self.as_mut().set_has_media(true);
                self.as_mut().set_playing(false);
                self.as_mut().set_polling_active(true);
                self.as_mut().set_status_text(QString::from("Opening…"));
                self.as_mut().set_position_ms(0.0);
                self.as_mut().set_duration_ms(0.0);
            }
            Err(error) => self.set_fatal_error(&error.to_string()),
        }
    }

    pub fn play_pause(mut self: Pin<&mut Self>) {
        if !*self.has_media() { return; }
        let result = self.rust().backend.as_ref().map(VlcWorker::toggle_playback);
        match result {
            Some(Ok(())) => self.as_mut().set_polling_active(true),
            Some(Err(error)) => self.set_nonfatal_error(&error.to_string()),
            None => {}
        }
    }

    pub fn stop(mut self: Pin<&mut Self>) {
        let result = self.rust().backend.as_ref().map(VlcWorker::stop);
        match result {
            Some(Ok(())) => self.as_mut().set_polling_active(true),
            Some(Err(error)) => self.set_nonfatal_error(&error.to_string()),
            None => {}
        }
    }

    pub fn seek_to(mut self: Pin<&mut Self>, position_ms: f64) {
        if !(*self.has_media()) || !position_ms.is_finite() {
            return;
        }
        let max = (*self.duration_ms()).max(0.0);
        let clamped = if max > 0.0 {
            position_ms.clamp(0.0, max)
        } else {
            position_ms.max(0.0)
        };
        if let Some(backend) = self.rust().backend.as_ref() {
            if let Err(error) = backend.seek_to_ms(clamped.round() as i64) {
                self.set_nonfatal_error(&error.to_string());
                return;
            }
            self.as_mut().set_polling_active(true);
            self.as_mut().set_position_ms(clamped);
        }
    }

    pub fn seek_by(mut self: Pin<&mut Self>, delta_ms: f64) {
        if !delta_ms.is_finite() {
            return;
        }
        let target = (*self.position_ms()) + delta_ms;
        self.as_mut().seek_to(target);
    }

    pub fn set_volume_value(mut self: Pin<&mut Self>, volume: i32) {
        let volume = volume.clamp(0, 125);
        if let Some(backend) = self.rust().backend.as_ref() {
            if let Err(error) = backend.set_volume(volume) {
                self.set_nonfatal_error(&error.to_string());
                return;
            }
        }
        if self.rust().backend.is_some() { self.as_mut().set_polling_active(true); }
        self.set_volume(volume);
    }

    pub fn toggle_mute(mut self: Pin<&mut Self>) {
        let muted = !(*self.muted());
        if let Some(backend) = self.rust().backend.as_ref() {
            if let Err(error) = backend.set_muted(muted) {
                self.set_nonfatal_error(&error.to_string());
                return;
            }
        }
        if self.rust().backend.is_some() { self.as_mut().set_polling_active(true); }
        self.set_muted(muted);
    }

    pub fn cycle_audio_track(mut self: Pin<&mut Self>) {
        let track_id = {
            let rust = self.rust();
            let Some(next_index) = next_track_index(rust.selected_audio_index, rust.audio_tracks.len())
            else {
                return;
            };
            rust.audio_tracks[next_index].id
        };

        let result = self.rust()
            .backend
            .as_ref()
            .map(|backend| backend.set_audio_track(track_id));
        match result {
            Some(Ok(())) => {
                // Do not update the visible selection optimistically. The worker refreshes
                // media info after libVLC accepts the request, and that confirmed state is the
                // single source of truth for the UI.
                self.as_mut().set_polling_active(true);
            }
            Some(Err(error)) => self.set_nonfatal_error(&error.to_string()),
            None => {}
        }
    }

    pub fn cycle_subtitle_track(mut self: Pin<&mut Self>) {
        let track_id = {
            let rust = self.rust();
            let Some(next_index) =
                next_track_index(rust.selected_subtitle_index, rust.subtitle_tracks.len())
            else {
                return;
            };
            rust.subtitle_tracks[next_index].id
        };

        let result = self.rust()
            .backend
            .as_ref()
            .map(|backend| backend.set_subtitle_track(track_id));
        match result {
            Some(Ok(())) => {
                self.as_mut().set_polling_active(true);
            }
            Some(Err(error)) => self.set_nonfatal_error(&error.to_string()),
            None => {}
        }
    }

    pub fn refresh(mut self: Pin<&mut Self>) {
        let Some(backend) = self.rust().backend.as_ref() else {
            return;
        };
        let report = backend.report();
        // An idle snapshot predating an accepted command is not its result. Keep the timer
        // alive until the worker publishes completion, including paused seeks/track changes.
        if report.pending_commands {
            self.as_mut().set_polling_active(true);
            return;
        }
        let snapshot = report.snapshot;

        if let Some(error) = report.error {
            self.as_mut().set_error_text(QString::from(&error));
        }

        if self.rust().media_info_revision != report.media_info_revision {
            self.as_mut()
                .apply_media_info(report.media_info.as_ref(), report.media_info_revision);
        }

        let position = snapshot.position_ms as f64;
        let duration = snapshot.duration_ms as f64;
        if ((*self.position_ms()) - position).abs() >= 1.0 {
            self.as_mut().set_position_ms(position);
        }
        if ((*self.duration_ms()) - duration).abs() >= 1.0 {
            self.as_mut().set_duration_ms(duration);
        }
        if (*self.volume()) != snapshot.volume {
            self.as_mut().set_volume(snapshot.volume);
        }
        if (*self.muted()) != snapshot.muted {
            self.as_mut().set_muted(snapshot.muted);
        }
        let is_playing = snapshot.state == PlaybackState::Playing;
        if (*self.playing()) != is_playing {
            self.as_mut().set_playing(is_playing);
        }

        let should_poll = matches!(
            snapshot.state,
            PlaybackState::Opening | PlaybackState::Buffering | PlaybackState::Playing
        );
        if (*self.polling_active()) != should_poll {
            self.as_mut().set_polling_active(should_poll);
        }

        let status = match snapshot.state {
            PlaybackState::Empty => "Ready",
            PlaybackState::Opening => "Opening…",
            PlaybackState::Buffering => "Buffering…",
            PlaybackState::Playing => "Playing",
            PlaybackState::Paused => "Paused",
            PlaybackState::Stopped => "Stopped",
            PlaybackState::Ended => "Ended",
            PlaybackState::Error => "Playback error",
        };
        if self.status_text().to_string() != status {
            self.as_mut().set_status_text(QString::from(status));
        }
        if snapshot.state == PlaybackState::Error && self.error_text().to_string().is_empty() {
            self.as_mut().set_error_text(QString::from(
                "Playback failed. The file may be unsupported, incomplete, or damaged.",
            ));
        }
    }

    pub fn clear_error(mut self: Pin<&mut Self>) {
        self.as_mut().set_error_text(QString::default());
    }

    pub fn shutdown(mut self: Pin<&mut Self>) {
        self.as_mut().set_polling_active(false);
        self.as_mut().set_playing(false);
        self.as_mut().set_has_media(false);
        self.as_mut().rust_mut().backend.take();
    }

    fn apply_media_info(mut self: Pin<&mut Self>, info: &MediaRuntimeInfo, revision: u64) {
        let selected_audio_index = info.selected_audio_index();
        let selected_subtitle_index = info.selected_subtitle_index();
        let audio_tracks = info.audio_tracks.clone();
        let subtitle_tracks = info.subtitle_tracks.clone();
        let size_text = info
            .file_size_bytes
            .map(format_file_size)
            .unwrap_or_else(|| "—".to_owned());
        let dimensions_text = if info.video_width > 0 && info.video_height > 0 {
            format!("{} × {}", info.video_width, info.video_height)
        } else {
            "—".to_owned()
        };

        {
            let mut rust = self.as_mut().rust_mut();
            rust.media_info_revision = revision;
            rust.audio_tracks = audio_tracks;
            rust.subtitle_tracks = subtitle_tracks;
            rust.selected_audio_index = selected_audio_index;
            rust.selected_subtitle_index = selected_subtitle_index;
        }

        let audio_count = self.rust().audio_tracks.len().min(i32::MAX as usize) as i32;
        let subtitle_count = self.rust()
            .subtitle_tracks
            .len()
            .min(i32::MAX as usize) as i32;
        self.as_mut().set_audio_track_count(audio_count);
        self.as_mut().set_subtitle_track_count(subtitle_count);
        self.as_mut().set_media_size_text(QString::from(&size_text));
        self.as_mut()
            .set_video_dimensions_text(QString::from(&dimensions_text));
        self.update_track_labels();
    }

    fn update_track_labels(mut self: Pin<&mut Self>) {
        let (audio, subtitle) = {
            let rust = self.rust();
            (
                selected_track_label(&rust.audio_tracks, rust.selected_audio_index),
                selected_track_label(&rust.subtitle_tracks, rust.selected_subtitle_index),
            )
        };
        self.as_mut().set_audio_track_label(QString::from(&audio));
        self.as_mut()
            .set_subtitle_track_label(QString::from(&subtitle));
    }

    fn reset_media_info(mut self: Pin<&mut Self>) {
        {
            let mut rust = self.as_mut().rust_mut();
            rust.media_info_revision = 0;
            rust.audio_tracks.clear();
            rust.subtitle_tracks.clear();
            rust.selected_audio_index = None;
            rust.selected_subtitle_index = None;
        }
        self.as_mut().set_audio_track_count(0);
        self.as_mut().set_subtitle_track_count(0);
        self.as_mut().set_audio_track_label(QString::from("None"));
        self.as_mut().set_subtitle_track_label(QString::from("None"));
        self.as_mut().set_media_size_text(QString::from("—"));
        self.as_mut().set_video_dimensions_text(QString::from("—"));
    }

    fn set_fatal_error(mut self: Pin<&mut Self>, message: &str) {
        self.as_mut().set_error_text(QString::from(message));
        self.as_mut().set_status_text(QString::from("Playback error"));
    }

    fn set_nonfatal_error(mut self: Pin<&mut Self>, message: &str) {
        self.as_mut().set_error_text(QString::from(message));
    }
}

fn next_track_index(selected: Option<usize>, len: usize) -> Option<usize> {
    if len == 0 {
        return None;
    }
    Some(match selected {
        Some(index) if index + 1 < len => index + 1,
        _ => 0,
    })
}

fn selected_track_label(tracks: &[MediaTrack], selected: Option<usize>) -> String {
    let Some(track) = selected.and_then(|index| tracks.get(index)) else {
        return "None".to_owned();
    };
    if track.id == -1 {
        "Off".to_owned()
    } else {
        track.name.clone()
    }
}

fn format_file_size(bytes: u64) -> String {
    const UNITS: [&str; 5] = ["B", "KB", "MB", "GB", "TB"];
    let mut value = bytes as f64;
    let mut unit = 0usize;
    while value >= 1024.0 && unit + 1 < UNITS.len() {
        value /= 1024.0;
        unit += 1;
    }
    if unit == 0 {
        format!("{bytes} {}", UNITS[unit])
    } else if value >= 100.0 {
        format!("{value:.0} {}", UNITS[unit])
    } else if value >= 10.0 {
        format!("{value:.1} {}", UNITS[unit])
    } else {
        format!("{value:.2} {}", UNITS[unit])
    }
}

fn video_target(native_handle: u64) -> VideoTarget {
    #[cfg(target_os = "windows")]
    {
        VideoTarget::WindowsHwnd(native_handle)
    }
    #[cfg(target_os = "linux")]
    {
        VideoTarget::X11Window(native_handle)
    }
    #[cfg(target_os = "macos")]
    {
        VideoTarget::CocoaView(native_handle)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cycling_wraps_and_handles_empty_track_lists() {
        assert_eq!(next_track_index(None, 0), None);
        assert_eq!(next_track_index(None, 3), Some(0));
        assert_eq!(next_track_index(Some(0), 3), Some(1));
        assert_eq!(next_track_index(Some(2), 3), Some(0));
    }

    #[test]
    fn file_sizes_are_human_readable() {
        assert_eq!(format_file_size(512), "512 B");
        assert_eq!(format_file_size(1024), "1.00 KB");
        assert_eq!(format_file_size(10 * 1024 * 1024), "10.0 MB");
    }
}
