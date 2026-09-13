use core::fmt;

/// Stable action identifiers used by UI controls, shortcuts, menus and the future command bar.
///
/// The UI is deliberately not allowed to invent alternate names for the same behavior.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ActionId {
    PlayerPlayPause,
    PlayerStop,
    PlayerSeekForward,
    PlayerSeekBackward,
    PlayerFullscreen,
    AudioMute,
    AudioNextTrack,
    SubtitleNextTrack,
    MediaOpen,
    MediaInspect,
}

impl ActionId {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::PlayerPlayPause => "player.play_pause",
            Self::PlayerStop => "player.stop",
            Self::PlayerSeekForward => "player.seek_forward",
            Self::PlayerSeekBackward => "player.seek_backward",
            Self::PlayerFullscreen => "player.fullscreen",
            Self::AudioMute => "audio.mute",
            Self::AudioNextTrack => "audio.next_track",
            Self::SubtitleNextTrack => "subtitle.next_track",
            Self::MediaOpen => "media.open",
            Self::MediaInspect => "media.inspect",
        }
    }
}

impl fmt::Display for ActionId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.as_str())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn action_ids_are_stable() {
        assert_eq!(ActionId::PlayerPlayPause.as_str(), "player.play_pause");
        assert_eq!(ActionId::AudioMute.as_str(), "audio.mute");
        assert_eq!(ActionId::AudioNextTrack.as_str(), "audio.next_track");
        assert_eq!(ActionId::SubtitleNextTrack.as_str(), "subtitle.next_track");
    }
}
