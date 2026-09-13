/// Player state as understood by application/UI code.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum PlaybackState {
    #[default]
    Empty,
    Opening,
    Buffering,
    Playing,
    Paused,
    Stopped,
    Ended,
    Error,
}

/// A cheap, backend-independent snapshot suitable for UI refreshes.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PlaybackSnapshot {
    pub state: PlaybackState,
    pub position_ms: i64,
    pub duration_ms: i64,
    pub volume: i32,
    pub muted: bool,
}

impl Default for PlaybackSnapshot {
    fn default() -> Self {
        Self {
            state: PlaybackState::Empty,
            position_ms: 0,
            duration_ms: 0,
            volume: 100,
            muted: false,
        }
    }
}

impl PlaybackSnapshot {
    pub fn normalized(mut self) -> Self {
        self.position_ms = self.position_ms.max(0);
        self.duration_ms = self.duration_ms.max(0);
        if self.duration_ms > 0 {
            self.position_ms = self.position_ms.min(self.duration_ms);
        }
        self.volume = self.volume.clamp(0, 125);
        self
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_is_clamped_to_sane_ui_values() {
        let snapshot = PlaybackSnapshot {
            state: PlaybackState::Playing,
            position_ms: 12_000,
            duration_ms: 10_000,
            volume: 900,
            muted: false,
        }
        .normalized();

        assert_eq!(snapshot.position_ms, 10_000);
        assert_eq!(snapshot.volume, 125);
    }
}
