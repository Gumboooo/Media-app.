//! Thin, dynamically-loaded libVLC 3.x playback backend.
//!
//! We intentionally do not depend on old, incomplete Rust VLC wrapper crates. This module
//! binds only the small, stable subset needed by the first playback milestone and keeps all
//! `unsafe` code inside the loader/API boundary.

mod api;
mod worker;

use aperture_core::{MediaRuntimeInfo, MediaTrack, PlaybackSnapshot, PlaybackState};
use api::{LibVlc3, Media, MediaPlayer, TrackDescription};
use std::ffi::CString;
use std::fs;
use std::path::Path;
use thiserror::Error;

pub use worker::{VlcWorker, WorkerReport};

const MAX_TRACK_DESCRIPTIONS: usize = 256;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VideoTarget {
    #[cfg(target_os = "windows")]
    WindowsHwnd(u64),
    #[cfg(target_os = "linux")]
    X11Window(u64),
    #[cfg(target_os = "macos")]
    CocoaView(u64),
}

#[derive(Debug, Error)]
pub enum VlcError {
    #[error("libVLC could not be found. Install VLC 3.x or place libVLC beside the application.")]
    LibraryNotFound,
    #[error("required libVLC symbol is missing: {0}")]
    MissingSymbol(&'static str),
    #[error("this build currently supports libVLC 3.x, but found {0}")]
    UnsupportedVersion(String),
    #[error("libVLC failed to create a player instance: {0}")]
    InstanceCreation(String),
    #[error("libVLC failed to create a media player: {0}")]
    PlayerCreation(String),
    #[error("this file could not be read: {0}")]
    FileAccess(String),
    #[error("the selected path is not a regular file")]
    NotRegularFile,
    #[error("the media path cannot be represented safely for playback")]
    InvalidPath,
    #[error("libVLC could not create media for this file")]
    MediaCreation,
    #[error("libVLC could not start playback: {0}")]
    PlaybackStart(String),
    #[error("libVLC rejected the requested volume")]
    InvalidVolume,
    #[error("libVLC rejected the requested {0} track")]
    InvalidTrack(&'static str),
    #[error("the playback worker thread could not be started: {0}")]
    WorkerSpawn(String),
    #[error("the playback command queue is busy")]
    CommandQueueFull,
    #[error("the playback worker is no longer running")]
    WorkerDisconnected,
    #[error("the playback backend stopped: {0}")]
    WorkerFailed(String),
}

pub struct VlcPlayer {
    api: LibVlc3,
    instance: *mut api::Instance,
    player: *mut MediaPlayer,
    last_volume: i32,
    last_muted: bool,
}

impl VlcPlayer {
    pub fn new() -> Result<Self, VlcError> {
        let api = LibVlc3::load()?;

        // Keep startup arguments deliberately minimal. No quality-changing flags live here.
        // Metadata network access is disabled explicitly so opening a local file cannot trigger
        // optional artwork/metadata lookups behind the user's back.
        let no_title = c"--no-video-title-show";
        let no_metadata_network = c"--no-metadata-network-access";
        let dummy_audio = c"--aout=dummy";
        let mut args = vec![no_title.as_ptr(), no_metadata_network.as_ptr()];

        // GitHub-hosted Windows runners have no default audio endpoint. VideoLAN uses the dummy
        // audio output for its own headless player tests, so our packaged smoke test can request
        // the same sink without changing normal application playback or media quality.
        if matches!(
            std::env::var("APERTURE_TEST_DUMMY_AUDIO"),
            Ok(value) if value == "1"
        ) {
            args.push(dummy_audio.as_ptr());
        }

        let instance = unsafe { (api.new)(args.len() as i32, args.as_ptr()) };
        if instance.is_null() {
            return Err(VlcError::InstanceCreation(api.last_error()));
        }

        let player = unsafe { (api.media_player_new)(instance) };
        if player.is_null() {
            unsafe { (api.release)(instance) };
            return Err(VlcError::PlayerCreation(api.last_error()));
        }

        // Embedded players should leave input handling to our Qt UI.
        unsafe {
            if let Some(set_key_input) = api.video_set_key_input {
                set_key_input(player, 0);
            }
            if let Some(set_mouse_input) = api.video_set_mouse_input {
                set_mouse_input(player, 0);
            }
        }

        Ok(Self {
            api,
            instance,
            player,
            last_volume: 100,
            last_muted: false,
        })
    }

    /// Open a local file and return its size without blocking the Qt thread.
    pub fn open_local(&mut self, path: &Path) -> Result<u64, VlcError> {
        let metadata = fs::metadata(path).map_err(|error| VlcError::FileAccess(error.to_string()))?;
        if !metadata.is_file() {
            return Err(VlcError::NotRegularFile);
        }

        let c_path = media_path(path)?;
        let media: *mut Media = unsafe { (self.api.media_new_path)(self.instance, c_path.as_ptr()) };
        if media.is_null() {
            return Err(VlcError::MediaCreation);
        }

        unsafe {
            (self.api.media_player_set_media)(self.player, media);
            (self.api.media_release)(media);
        }

        self.play()?;
        Ok(metadata.len())
    }

    pub fn set_video_target(&mut self, target: VideoTarget) {
        unsafe {
            match target {
                #[cfg(target_os = "windows")]
                VideoTarget::WindowsHwnd(handle) => {
                    (self.api.media_player_set_hwnd)(self.player, handle as usize as *mut _);
                }
                #[cfg(target_os = "linux")]
                VideoTarget::X11Window(handle) => {
                    (self.api.media_player_set_xwindow)(self.player, handle as u32);
                }
                #[cfg(target_os = "macos")]
                VideoTarget::CocoaView(handle) => {
                    (self.api.media_player_set_nsobject)(self.player, handle as usize as *mut _);
                }
            }
        }
    }

    pub fn play(&mut self) -> Result<(), VlcError> {
        let code = unsafe { (self.api.media_player_play)(self.player) };
        if code == 0 {
            Ok(())
        } else {
            Err(VlcError::PlaybackStart(self.api.last_error()))
        }
    }

    pub fn stop(&mut self) {
        unsafe { (self.api.media_player_stop)(self.player) }
    }

    pub fn pause(&mut self, paused: bool) {
        unsafe { (self.api.media_player_set_pause)(self.player, i32::from(paused)) }
    }

    pub fn seek_to_ms(&mut self, position_ms: i64) {
        unsafe { (self.api.media_player_set_time)(self.player, position_ms.max(0)) }
    }

    pub fn set_volume(&mut self, volume: i32) -> Result<(), VlcError> {
        let volume = volume.clamp(0, 125);
        let result = unsafe { (self.api.audio_set_volume)(self.player, volume) };
        if result == 0 {
            self.last_volume = volume;
            Ok(())
        } else {
            Err(VlcError::InvalidVolume)
        }
    }

    pub fn set_muted(&mut self, muted: bool) {
        unsafe { (self.api.audio_set_mute)(self.player, i32::from(muted)) }
        self.last_muted = muted;
    }

    pub fn set_audio_track(&mut self, id: i32) -> Result<(), VlcError> {
        let result = unsafe { (self.api.audio_set_track)(self.player, id) };
        if result == 0 {
            Ok(())
        } else {
            Err(VlcError::InvalidTrack("audio"))
        }
    }

    pub fn set_subtitle_track(&mut self, id: i32) -> Result<(), VlcError> {
        let result = unsafe { (self.api.video_set_spu)(self.player, id) };
        if result == 0 {
            Ok(())
        } else {
            Err(VlcError::InvalidTrack("subtitle"))
        }
    }

    pub fn runtime_media_info(&self, file_size_bytes: Option<u64>) -> MediaRuntimeInfo {
        let audio_tracks = unsafe {
            self.copy_track_descriptions((self.api.audio_get_track_description)(self.player), "Audio")
        };
        let subtitle_tracks = unsafe {
            self.copy_track_descriptions((self.api.video_get_spu_description)(self.player), "Subtitle")
        };
        let selected_audio = unsafe { (self.api.audio_get_track)(self.player) };
        let selected_subtitle = unsafe { (self.api.video_get_spu)(self.player) };

        let mut width = 0;
        let mut height = 0;
        let size_result = unsafe { (self.api.video_get_size)(self.player, 0, &mut width, &mut height) };
        if size_result != 0 {
            width = 0;
            height = 0;
        }

        MediaRuntimeInfo {
            file_size_bytes,
            video_width: width,
            video_height: height,
            selected_audio_id: audio_tracks
                .iter()
                .any(|track| track.id == selected_audio)
                .then_some(selected_audio),
            selected_subtitle_id: subtitle_tracks
                .iter()
                .any(|track| track.id == selected_subtitle)
                .then_some(selected_subtitle),
            audio_tracks,
            subtitle_tracks,
        }
    }

    /// Copy a LibVLC linked track-description list into owned Rust values, then release it.
    /// The traversal cap is defensive; a native library should never return a cyclic list.
    unsafe fn copy_track_descriptions(
        &self,
        head: *mut TrackDescription,
        fallback_prefix: &str,
    ) -> Vec<MediaTrack> {
        if head.is_null() {
            return Vec::new();
        }

        let mut tracks = Vec::new();
        let mut current = head;
        let mut visited = 0usize;

        while !current.is_null() && visited < MAX_TRACK_DESCRIPTIONS {
            let description = &*current;
            let mut name = api::c_string(description.name);
            if name.trim().is_empty() {
                name = if description.id == -1 {
                    "Disable".to_owned()
                } else {
                    format!("{fallback_prefix} {}", visited + 1)
                };
            }
            tracks.push(MediaTrack::new(description.id, name));
            current = description.next;
            visited += 1;
        }

        (self.api.track_description_list_release)(head);
        tracks
    }

    pub fn snapshot(&self) -> PlaybackSnapshot {
        let position_ms = unsafe { (self.api.media_player_get_time)(self.player) };
        let duration_ms = unsafe { (self.api.media_player_get_length)(self.player) };
        let raw_volume = unsafe { (self.api.audio_get_volume)(self.player) };
        let volume = if raw_volume >= 0 {
            raw_volume
        } else {
            self.last_volume
        };
        let raw_muted = unsafe { (self.api.audio_get_mute)(self.player) };
        let muted = match raw_muted {
            0 => false,
            1 => true,
            _ => self.last_muted,
        };
        let raw_state = unsafe { (self.api.media_player_get_state)(self.player) };
        let state = playback_state_from_libvlc(raw_state);

        PlaybackSnapshot {
            state,
            position_ms,
            duration_ms,
            volume,
            muted,
        }
        .normalized()
    }
}

impl Drop for VlcPlayer {
    fn drop(&mut self) {
        // The function pointers are valid until `self.api` drops, which happens after this method.
        unsafe {
            (self.api.media_player_stop)(self.player);
            (self.api.media_player_release)(self.player);
            (self.api.release)(self.instance);
        }
    }
}

fn playback_state_from_libvlc(raw_state: i32) -> PlaybackState {
    match raw_state {
        0 => PlaybackState::Stopped, // libvlc_NothingSpecial
        1 => PlaybackState::Opening,
        2 => PlaybackState::Buffering,
        3 => PlaybackState::Playing,
        4 => PlaybackState::Paused,
        5 => PlaybackState::Stopped,
        6 => PlaybackState::Ended,
        7 => PlaybackState::Error,
        _ => PlaybackState::Error,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn maps_libvlc_states_without_collapsing_terminal_states() {
        assert_eq!(playback_state_from_libvlc(1), PlaybackState::Opening);
        assert_eq!(playback_state_from_libvlc(2), PlaybackState::Buffering);
        assert_eq!(playback_state_from_libvlc(3), PlaybackState::Playing);
        assert_eq!(playback_state_from_libvlc(4), PlaybackState::Paused);
        assert_eq!(playback_state_from_libvlc(6), PlaybackState::Ended);
        assert_eq!(playback_state_from_libvlc(7), PlaybackState::Error);
        assert_eq!(playback_state_from_libvlc(999), PlaybackState::Error);
    }
}

#[cfg(all(test, unix))]
mod path_tests {
    use super::*;
    use std::os::unix::ffi::OsStrExt;

    #[test]
    fn native_path_bytes_are_not_replaced_by_unicode_placeholders() {
        let raw = b"/tmp/video-\xff.mp4";
        let path = Path::new(std::ffi::OsStr::from_bytes(raw));
        assert_eq!(media_path(path).unwrap().as_bytes(), raw);
    }

    #[test]
    fn nul_paths_are_rejected_at_the_ffi_boundary() {
        let path = Path::new(std::ffi::OsStr::from_bytes(b"/tmp/a\0b"));
        assert!(matches!(media_path(path), Err(VlcError::InvalidPath)));
    }
}

#[cfg(all(test, target_os = "windows"))]
mod windows_path_tests {
    use super::*;

    #[test]
    fn libvlc3_receives_native_drive_separators() {
        let path = Path::new("C:/Temp/generated audio.wav");
        assert_eq!(
            media_path(path).unwrap().as_bytes(),
            br"C:\Temp\generated audio.wav"
        );
    }

    #[test]
    fn libvlc3_receives_native_unc_separators() {
        let path = Path::new("//server/share/video.mp4");
        assert_eq!(media_path(path).unwrap().as_bytes(), br"\\server\share\video.mp4");
    }
}

// Unix filenames are byte strings. Lossy UTF-8 conversion can silently open the wrong file.
// On Windows, Qt commonly supplies local file paths with forward slashes. libVLC 3's
// vlc_path2uri() recognizes a drive prefix but requires the following separator to be the native
// Windows separator, so normalize only at this FFI boundary. Windows does not permit '/' inside a
// filename, making this conversion unambiguous.
fn media_path(path: &Path) -> Result<CString, VlcError> {
    #[cfg(unix)]
    {
        use std::os::unix::ffi::OsStrExt;
        CString::new(path.as_os_str().as_bytes()).map_err(|_| VlcError::InvalidPath)
    }
    #[cfg(target_os = "windows")]
    {
        let text = path.to_str().ok_or(VlcError::InvalidPath)?;
        CString::new(text.replace('/', "\\")).map_err(|_| VlcError::InvalidPath)
    }
    #[cfg(all(not(unix), not(target_os = "windows")))]
    {
        let text = path.to_str().ok_or(VlcError::InvalidPath)?;
        CString::new(text).map_err(|_| VlcError::InvalidPath)
    }
}
