//! UI-agnostic application domain types.
//!
//! Keep this crate free of Qt, VLC and FFmpeg dependencies. It should remain cheap to
//! compile and straightforward to unit test.

pub mod action;
pub mod media;
pub mod playback;

pub use action::ActionId;
pub use media::{MediaRuntimeInfo, MediaSource, MediaTrack};
pub use playback::{PlaybackSnapshot, PlaybackState};
