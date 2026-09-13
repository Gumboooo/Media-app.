use crate::VlcError;
use libloading::Library;
use std::env;
use std::ffi::{c_char, c_int, c_uint, c_void, CStr};
use std::path::{Path, PathBuf};

#[repr(C)]
pub struct Instance {
    _private: [u8; 0],
}
#[repr(C)]
pub struct MediaPlayer {
    _private: [u8; 0],
}
#[repr(C)]
pub struct Media {
    _private: [u8; 0],
}

/// ABI layout from libvlc_media_player.h in LibVLC 3.x.
#[repr(C)]
pub struct TrackDescription {
    pub id: c_int,
    pub name: *mut c_char,
    pub next: *mut TrackDescription,
}

type NewFn = unsafe extern "C" fn(c_int, *const *const c_char) -> *mut Instance;
type ReleaseFn = unsafe extern "C" fn(*mut Instance);
type GetVersionFn = unsafe extern "C" fn() -> *const c_char;
type ErrmsgFn = unsafe extern "C" fn() -> *const c_char;
type MediaNewPathFn = unsafe extern "C" fn(*mut Instance, *const c_char) -> *mut Media;
type MediaReleaseFn = unsafe extern "C" fn(*mut Media);
type MediaPlayerNewFn = unsafe extern "C" fn(*mut Instance) -> *mut MediaPlayer;
type MediaPlayerReleaseFn = unsafe extern "C" fn(*mut MediaPlayer);
type MediaPlayerSetMediaFn = unsafe extern "C" fn(*mut MediaPlayer, *mut Media);
type MediaPlayerPlayFn = unsafe extern "C" fn(*mut MediaPlayer) -> c_int;
type MediaPlayerPauseFn = unsafe extern "C" fn(*mut MediaPlayer, c_int);
type MediaPlayerStopFn = unsafe extern "C" fn(*mut MediaPlayer);
type MediaPlayerGetStateFn = unsafe extern "C" fn(*mut MediaPlayer) -> c_int;
type MediaPlayerGetTimeFn = unsafe extern "C" fn(*mut MediaPlayer) -> i64;
type MediaPlayerSetTimeFn = unsafe extern "C" fn(*mut MediaPlayer, i64);
type MediaPlayerGetLengthFn = unsafe extern "C" fn(*mut MediaPlayer) -> i64;
type AudioGetVolumeFn = unsafe extern "C" fn(*mut MediaPlayer) -> c_int;
type AudioSetVolumeFn = unsafe extern "C" fn(*mut MediaPlayer, c_int) -> c_int;
type AudioGetMuteFn = unsafe extern "C" fn(*mut MediaPlayer) -> c_int;
type AudioSetMuteFn = unsafe extern "C" fn(*mut MediaPlayer, c_int);
type TrackDescriptionFn = unsafe extern "C" fn(*mut MediaPlayer) -> *mut TrackDescription;
type TrackGetFn = unsafe extern "C" fn(*mut MediaPlayer) -> c_int;
type TrackSetFn = unsafe extern "C" fn(*mut MediaPlayer, c_int) -> c_int;
type TrackDescriptionReleaseFn = unsafe extern "C" fn(*mut TrackDescription);
type VideoGetSizeFn = unsafe extern "C" fn(*mut MediaPlayer, c_uint, *mut c_uint, *mut c_uint) -> c_int;
type VideoSetInputFn = unsafe extern "C" fn(*mut MediaPlayer, c_uint);

#[cfg(target_os = "windows")]
type MediaPlayerSetHwndFn = unsafe extern "C" fn(*mut MediaPlayer, *mut c_void);
#[cfg(target_os = "linux")]
type MediaPlayerSetXwindowFn = unsafe extern "C" fn(*mut MediaPlayer, u32);
#[cfg(target_os = "macos")]
type MediaPlayerSetNsobjectFn = unsafe extern "C" fn(*mut MediaPlayer, *mut c_void);

pub struct LibVlc3 {
    _library: Library,
    pub new: NewFn,
    pub release: ReleaseFn,
    pub media_new_path: MediaNewPathFn,
    pub media_release: MediaReleaseFn,
    pub media_player_new: MediaPlayerNewFn,
    pub media_player_release: MediaPlayerReleaseFn,
    pub media_player_set_media: MediaPlayerSetMediaFn,
    pub media_player_play: MediaPlayerPlayFn,
    pub media_player_set_pause: MediaPlayerPauseFn,
    pub media_player_stop: MediaPlayerStopFn,
    pub media_player_get_state: MediaPlayerGetStateFn,
    pub media_player_get_time: MediaPlayerGetTimeFn,
    pub media_player_set_time: MediaPlayerSetTimeFn,
    pub media_player_get_length: MediaPlayerGetLengthFn,
    pub audio_get_volume: AudioGetVolumeFn,
    pub audio_set_volume: AudioSetVolumeFn,
    pub audio_get_mute: AudioGetMuteFn,
    pub audio_set_mute: AudioSetMuteFn,
    pub audio_get_track_description: TrackDescriptionFn,
    pub audio_get_track: TrackGetFn,
    pub audio_set_track: TrackSetFn,
    pub video_get_spu_description: TrackDescriptionFn,
    pub video_get_spu: TrackGetFn,
    pub video_set_spu: TrackSetFn,
    pub track_description_list_release: TrackDescriptionReleaseFn,
    pub video_get_size: VideoGetSizeFn,
    pub video_set_key_input: Option<VideoSetInputFn>,
    pub video_set_mouse_input: Option<VideoSetInputFn>,
    errmsg: ErrmsgFn,

    #[cfg(target_os = "windows")]
    pub media_player_set_hwnd: MediaPlayerSetHwndFn,
    #[cfg(target_os = "linux")]
    pub media_player_set_xwindow: MediaPlayerSetXwindowFn,
    #[cfg(target_os = "macos")]
    pub media_player_set_nsobject: MediaPlayerSetNsobjectFn,
}

impl LibVlc3 {
    pub fn load() -> Result<Self, VlcError> {
        let library = load_library()?;

        unsafe {
            let get_version: GetVersionFn =
                required(&library, b"libvlc_get_version\0", "libvlc_get_version")?;
            let version = c_string(get_version());
            if !version.starts_with("3.") {
                return Err(VlcError::UnsupportedVersion(version));
            }

            Ok(Self {
                new: required(&library, b"libvlc_new\0", "libvlc_new")?,
                release: required(&library, b"libvlc_release\0", "libvlc_release")?,
                media_new_path: required(
                    &library,
                    b"libvlc_media_new_path\0",
                    "libvlc_media_new_path",
                )?,
                media_release: required(
                    &library,
                    b"libvlc_media_release\0",
                    "libvlc_media_release",
                )?,
                media_player_new: required(
                    &library,
                    b"libvlc_media_player_new\0",
                    "libvlc_media_player_new",
                )?,
                media_player_release: required(
                    &library,
                    b"libvlc_media_player_release\0",
                    "libvlc_media_player_release",
                )?,
                media_player_set_media: required(
                    &library,
                    b"libvlc_media_player_set_media\0",
                    "libvlc_media_player_set_media",
                )?,
                media_player_play: required(
                    &library,
                    b"libvlc_media_player_play\0",
                    "libvlc_media_player_play",
                )?,
                media_player_set_pause: required(
                    &library,
                    b"libvlc_media_player_set_pause\0",
                    "libvlc_media_player_set_pause",
                )?,
                media_player_stop: required(
                    &library,
                    b"libvlc_media_player_stop\0",
                    "libvlc_media_player_stop",
                )?,
                media_player_get_state: required(
                    &library,
                    b"libvlc_media_player_get_state\0",
                    "libvlc_media_player_get_state",
                )?,
                media_player_get_time: required(
                    &library,
                    b"libvlc_media_player_get_time\0",
                    "libvlc_media_player_get_time",
                )?,
                media_player_set_time: required(
                    &library,
                    b"libvlc_media_player_set_time\0",
                    "libvlc_media_player_set_time",
                )?,
                media_player_get_length: required(
                    &library,
                    b"libvlc_media_player_get_length\0",
                    "libvlc_media_player_get_length",
                )?,
                audio_get_volume: required(
                    &library,
                    b"libvlc_audio_get_volume\0",
                    "libvlc_audio_get_volume",
                )?,
                audio_set_volume: required(
                    &library,
                    b"libvlc_audio_set_volume\0",
                    "libvlc_audio_set_volume",
                )?,
                audio_get_mute: required(
                    &library,
                    b"libvlc_audio_get_mute\0",
                    "libvlc_audio_get_mute",
                )?,
                audio_set_mute: required(
                    &library,
                    b"libvlc_audio_set_mute\0",
                    "libvlc_audio_set_mute",
                )?,
                audio_get_track_description: required(
                    &library,
                    b"libvlc_audio_get_track_description\0",
                    "libvlc_audio_get_track_description",
                )?,
                audio_get_track: required(
                    &library,
                    b"libvlc_audio_get_track\0",
                    "libvlc_audio_get_track",
                )?,
                audio_set_track: required(
                    &library,
                    b"libvlc_audio_set_track\0",
                    "libvlc_audio_set_track",
                )?,
                video_get_spu_description: required(
                    &library,
                    b"libvlc_video_get_spu_description\0",
                    "libvlc_video_get_spu_description",
                )?,
                video_get_spu: required(
                    &library,
                    b"libvlc_video_get_spu\0",
                    "libvlc_video_get_spu",
                )?,
                video_set_spu: required(
                    &library,
                    b"libvlc_video_set_spu\0",
                    "libvlc_video_set_spu",
                )?,
                track_description_list_release: required(
                    &library,
                    b"libvlc_track_description_list_release\0",
                    "libvlc_track_description_list_release",
                )?,
                video_get_size: required(
                    &library,
                    b"libvlc_video_get_size\0",
                    "libvlc_video_get_size",
                )?,
                video_set_key_input: optional(&library, b"libvlc_video_set_key_input\0"),
                video_set_mouse_input: optional(&library, b"libvlc_video_set_mouse_input\0"),
                errmsg: required(&library, b"libvlc_errmsg\0", "libvlc_errmsg")?,
                #[cfg(target_os = "windows")]
                media_player_set_hwnd: required(
                    &library,
                    b"libvlc_media_player_set_hwnd\0",
                    "libvlc_media_player_set_hwnd",
                )?,
                #[cfg(target_os = "linux")]
                media_player_set_xwindow: required(
                    &library,
                    b"libvlc_media_player_set_xwindow\0",
                    "libvlc_media_player_set_xwindow",
                )?,
                #[cfg(target_os = "macos")]
                media_player_set_nsobject: required(
                    &library,
                    b"libvlc_media_player_set_nsobject\0",
                    "libvlc_media_player_set_nsobject",
                )?,
                _library: library,
            })
        }
    }

    pub fn last_error(&self) -> String {
        unsafe {
            let ptr = (self.errmsg)();
            let message = c_string(ptr);
            if message.is_empty() {
                "unknown libVLC error".to_owned()
            } else {
                message
            }
        }
    }
}

unsafe fn required<T: Copy>(
    library: &Library,
    symbol: &'static [u8],
    printable: &'static str,
) -> Result<T, VlcError> {
    library
        .get::<T>(symbol)
        .map(|symbol| *symbol)
        .map_err(|_| VlcError::MissingSymbol(printable))
}

unsafe fn optional<T: Copy>(library: &Library, symbol: &'static [u8]) -> Option<T> {
    library.get::<T>(symbol).ok().map(|symbol| *symbol)
}

pub(crate) unsafe fn c_string(ptr: *const c_char) -> String {
    if ptr.is_null() {
        return String::new();
    }
    CStr::from_ptr(ptr).to_string_lossy().into_owned()
}

fn load_library() -> Result<Library, VlcError> {
    let candidates = candidate_paths();
    for candidate in candidates {
        // Loading a native library is inherently unsafe. We only resolve known libVLC symbols and
        // validate the ABI major version before invoking version-specific functions.
        if let Ok(library) = unsafe { Library::new(&candidate) } {
            return Ok(library);
        }
    }
    Err(VlcError::LibraryNotFound)
}

fn candidate_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();

    if let Some(path) = env::var_os("APERTURE_LIBVLC_PATH") {
        let path = PathBuf::from(path);
        if path.is_dir() {
            paths.push(path.join(platform_library_name()));
        } else {
            paths.push(path);
        }
    }

    if let Ok(exe) = env::current_exe() {
        if let Some(dir) = exe.parent() {
            paths.push(dir.join(platform_library_name()));
            paths.push(dir.join("vlc").join(platform_library_name()));
        }
    }

    #[cfg(target_os = "windows")]
    {
        if let Some(program_files) = env::var_os("ProgramFiles") {
            paths.push(Path::new(&program_files).join("VideoLAN/VLC/libvlc.dll"));
        }
        if let Some(program_files_x86) = env::var_os("ProgramFiles(x86)") {
            paths.push(Path::new(&program_files_x86).join("VideoLAN/VLC/libvlc.dll"));
        }
    }

    // On Unix, permit the normal loader search path as a final fallback. On Windows we avoid
    // an unqualified DLL name so the current working directory cannot become an accidental
    // native-code search location. Packaged builds should use the executable-adjacent copy.
    #[cfg(not(target_os = "windows"))]
    paths.push(PathBuf::from(platform_library_name()));
    paths
}

#[cfg(target_os = "windows")]
const fn platform_library_name() -> &'static str {
    "libvlc.dll"
}
#[cfg(target_os = "linux")]
const fn platform_library_name() -> &'static str {
    "libvlc.so.5"
}
#[cfg(target_os = "macos")]
const fn platform_library_name() -> &'static str {
    "libvlc.dylib"
}

#[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
compile_error!("The libVLC backend currently supports Windows, Linux and macOS only.");
