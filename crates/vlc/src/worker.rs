use crate::{VideoTarget, VlcError, VlcPlayer};
use aperture_core::{MediaRuntimeInfo, PlaybackSnapshot, PlaybackState};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, SyncSender, TrySendError};
use std::sync::{Arc, Mutex, MutexGuard};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

const COMMAND_QUEUE_CAPACITY: usize = 64;
const ACTIVE_POLL_INTERVAL: Duration = Duration::from_millis(100);
const STARTUP_TIMEOUT: Duration = Duration::from_secs(15);
const INFO_REFRESH_INTERVAL: Duration = Duration::from_millis(500);
const INFO_REFRESH_ATTEMPTS: u8 = 4;

#[derive(Debug, Clone)]
pub struct WorkerReport {
    pub snapshot: PlaybackSnapshot,
    pub media_info: Arc<MediaRuntimeInfo>,
    pub media_info_revision: u64,
    pub error: Option<String>,
    /// True until every accepted command has published its result.
    pub pending_commands: bool,
}

#[derive(Debug)]
struct SharedState {
    snapshot: PlaybackSnapshot,
    media_info: Arc<MediaRuntimeInfo>,
    media_info_revision: u64,
    pending_error: Option<String>,
    pending_commands: usize,
    alive: bool,
}

#[derive(Debug)]
enum Command {
    Open(PathBuf),
    SetVideoTarget(VideoTarget),
    Play,
    Pause,
    TogglePlayback,
    Stop,
    Seek(i64),
    SetVolume(i32),
    SetMuted(bool),
    SetAudioTrack(i32),
    SetSubtitleTrack(i32),
    Shutdown,
}

/// Owns libVLC on one dedicated native thread.
///
/// Qt/QML never calls libVLC directly. The command queue is bounded so malformed UI behavior
/// cannot grow memory without limit. While playback is paused/stopped this thread blocks on the
/// queue instead of polling.
pub struct VlcWorker {
    commands: Option<SyncSender<Command>>,
    shared: Arc<Mutex<SharedState>>,
    join: Option<JoinHandle<()>>,
    stopping: Arc<AtomicBool>,
}

impl VlcWorker {
    pub fn spawn(
        target: Option<VideoTarget>,
        volume: i32,
        muted: bool,
    ) -> Result<Self, VlcError> {
        let initial = PlaybackSnapshot {
            state: PlaybackState::Empty,
            volume: volume.clamp(0, 125),
            muted,
            ..PlaybackSnapshot::default()
        };
        let shared = Arc::new(Mutex::new(SharedState {
            snapshot: initial,
            media_info: Arc::new(MediaRuntimeInfo::default()),
            media_info_revision: 0,
            pending_error: None,
            pending_commands: 0,
            alive: true,
        }));
        let worker_shared = Arc::clone(&shared);
        let (commands, receiver) = mpsc::sync_channel(COMMAND_QUEUE_CAPACITY);

        let stopping = Arc::new(AtomicBool::new(false));
        let worker_stopping = Arc::clone(&stopping);
        let join = thread::Builder::new()
            .name("aperture-vlc".to_owned())
            .spawn(move || worker_main(receiver, worker_shared, worker_stopping, target, volume, muted))
            .map_err(|error| VlcError::WorkerSpawn(error.to_string()))?;

        Ok(Self {
            commands: Some(commands),
            shared,
            join: Some(join),
            stopping,
        })
    }

    pub fn open_local(&self, path: PathBuf) -> Result<(), VlcError> {
        self.try_command(Command::Open(path))
    }

    pub fn set_video_target(&self, target: VideoTarget) -> Result<(), VlcError> {
        self.try_command(Command::SetVideoTarget(target))
    }

    pub fn play(&self) -> Result<(), VlcError> {
        self.try_command(Command::Play)
    }

    pub fn pause(&self) -> Result<(), VlcError> {
        self.try_command(Command::Pause)
    }

    pub fn toggle_playback(&self) -> Result<(), VlcError> {
        self.try_command(Command::TogglePlayback)
    }

    pub fn stop(&self) -> Result<(), VlcError> {
        self.try_command(Command::Stop)
    }

    pub fn is_finished(&self) -> bool {
        self.join.as_ref().is_none_or(|join| join.is_finished())
    }

    /// Request cancellation without joining the native thread.
    ///
    /// This is the UI-close fast path: it wakes an idle receiver and makes the worker skip stale
    /// queued work, while allowing Qt to keep pumping events until libVLC has released its native
    /// window references. `finish_shutdown()` performs the eventual non-blocking reap.
    pub fn begin_shutdown(&mut self) {
        self.stopping.store(true, Ordering::Release);
        if let Some(commands) = self.commands.take() {
            let _ = commands.try_send(Command::Shutdown);
            drop(commands);
        }
    }

    /// Reap a previously cancelled worker only after the native thread has actually exited.
    /// Returns `false` without blocking while a native call is still unwinding.
    pub fn finish_shutdown(&mut self) -> bool {
        self.begin_shutdown();
        if !self.is_finished() {
            return false;
        }
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
        true
    }

    pub fn seek_to_ms(&self, position_ms: i64) -> Result<(), VlcError> {
        self.try_command(Command::Seek(position_ms.max(0)))
    }

    pub fn set_volume(&self, volume: i32) -> Result<(), VlcError> {
        self.try_command(Command::SetVolume(volume.clamp(0, 125)))
    }

    pub fn set_muted(&self, muted: bool) -> Result<(), VlcError> {
        self.try_command(Command::SetMuted(muted))
    }

    pub fn set_audio_track(&self, id: i32) -> Result<(), VlcError> {
        self.try_command(Command::SetAudioTrack(id))
    }

    pub fn set_subtitle_track(&self, id: i32) -> Result<(), VlcError> {
        self.try_command(Command::SetSubtitleTrack(id))
    }

    pub fn report(&self) -> WorkerReport {
        let mut shared = lock_state(&self.shared);
        WorkerReport {
            snapshot: shared.snapshot,
            media_info: Arc::clone(&shared.media_info),
            media_info_revision: shared.media_info_revision,
            error: if shared.pending_commands == 0 || !shared.alive {
                shared.pending_error.take()
            } else {
                None
            },
            pending_commands: shared.pending_commands > 0 && shared.alive,
        }
    }

    fn try_command(&self, command: Command) -> Result<(), VlcError> {
        let Some(commands) = self.commands.as_ref() else {
            return Err(VlcError::WorkerDisconnected);
        };
        // Reserve while holding the same lock used to publish snapshots: a very fast worker
        // cannot acknowledge before the reservation, or expose an old snapshot as settled.
        let mut shared = lock_state(&self.shared);
        if !shared.alive || self.stopping.load(Ordering::Acquire) {
            return Err(VlcError::WorkerDisconnected);
        }
        match commands.try_send(command) {
            Ok(()) => {
                shared.pending_commands += 1;
                Ok(())
            }
            Err(TrySendError::Full(_)) => Err(VlcError::CommandQueueFull),
            Err(TrySendError::Disconnected(_)) => {
                let failure = shared.pending_error.clone();
                match failure {
                    Some(message) => Err(VlcError::WorkerFailed(message)),
                    None => Err(VlcError::WorkerDisconnected),
                }
            }
        }
    }
}

impl Drop for VlcWorker {
    fn drop(&mut self) {
        // Drop remains the last-resort safety net. Normal window close uses begin_shutdown() and
        // finish_shutdown() first so this join is already complete and cannot freeze the Qt UI.
        self.begin_shutdown();
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}

fn worker_main(
    receiver: Receiver<Command>,
    shared: Arc<Mutex<SharedState>>,
    stopping: Arc<AtomicBool>,
    initial_target: Option<VideoTarget>,
    initial_volume: i32,
    initial_muted: bool,
) {
    let _lifetime = WorkerLifetime(Arc::clone(&shared));
    let mut player = match VlcPlayer::new() {
        Ok(player) => player,
        Err(error) => {
            set_fatal_error(&shared, error.to_string());
            return;
        }
    };

    if let Some(target) = initial_target {
        player.set_video_target(target);
    }
    if let Err(error) = player.set_volume(initial_volume) {
        set_nonfatal_error(&shared, error.to_string());
    }
    player.set_muted(initial_muted);

    let mut poll_active = false;
    let mut waiting_for_start = false;
    let mut startup_deadline = None;
    let mut file_size_bytes = None;
    let mut next_info_refresh = None;
    let mut info_refresh_attempts = 0u8;

    loop {
        if stopping.load(Ordering::Acquire) {
            break;
        }
        let next = if poll_active {
            match receiver.recv_timeout(ACTIVE_POLL_INTERVAL) {
                Ok(command) => Some(command),
                Err(RecvTimeoutError::Timeout) => None,
                Err(RecvTimeoutError::Disconnected) => break,
            }
        } else {
            match receiver.recv() {
                Ok(command) => Some(command),
                Err(_) => break,
            }
        };

        if stopping.load(Ordering::Acquire) {
            break;
        }
        // Acknowledge even on early error/continue, but only after publishing the outcome.
        let _completion = next
            .as_ref()
            .map(|_| CommandCompletion(Arc::clone(&shared)));
        if let Some(command) = next {
            match command {
                Command::Open(path) => {
                    {
                        let mut state = lock_state(&shared);
                        state.pending_error = None;
                        state.snapshot.position_ms = 0;
                        state.snapshot.duration_ms = 0;
                        state.snapshot.state = PlaybackState::Opening;
                    }
                    set_media_info(&shared, MediaRuntimeInfo::default());
                    file_size_bytes = None;
                    info_refresh_attempts = 0;
                    next_info_refresh = None;

                    match player.open_local(&path) {
                        Ok(size) => {
                            file_size_bytes = Some(size);
                            set_media_info(
                                &shared,
                                MediaRuntimeInfo {
                                    file_size_bytes,
                                    ..MediaRuntimeInfo::default()
                                },
                            );
                            waiting_for_start = true;
                            startup_deadline = Some(Instant::now() + STARTUP_TIMEOUT);
                        }
                        Err(error) => {
                            player.stop();
                            set_fatal_error(&shared, error.to_string());
                            waiting_for_start = false;
                            startup_deadline = None;
                            poll_active = false;
                            continue;
                        }
                    }
                }
                Command::SetVideoTarget(target) => player.set_video_target(target),
                Command::Play => match player.play() {
                    Ok(()) => {
                        waiting_for_start = true;
                        startup_deadline = Some(Instant::now() + STARTUP_TIMEOUT);
                    }
                    Err(error) => {
                        set_fatal_error(&shared, error.to_string());
                        poll_active = false;
                        continue;
                    }
                },
                Command::Pause => {
                    player.pause(true);
                    waiting_for_start = false;
                    startup_deadline = None;
                }
                Command::TogglePlayback => {
                    if waiting_for_start
                        || matches!(
                            player.snapshot().state,
                            PlaybackState::Playing
                                | PlaybackState::Opening
                                | PlaybackState::Buffering
                        )
                    {
                        player.pause(true);
                        waiting_for_start = false;
                        startup_deadline = None;
                    } else {
                        if let Err(error) = player.play() {
                            set_fatal_error(&shared, error.to_string());
                            poll_active = false;
                            continue;
                        }
                        waiting_for_start = true;
                        startup_deadline = Some(Instant::now() + STARTUP_TIMEOUT);
                    }
                }
                Command::Stop => {
                    player.stop();
                    waiting_for_start = false;
                    startup_deadline = None;
                    next_info_refresh = None;
                }
                Command::Seek(position_ms) => player.seek_to_ms(position_ms),
                Command::SetVolume(volume) => {
                    if let Err(error) = player.set_volume(volume) {
                        set_nonfatal_error(&shared, error.to_string());
                    }
                }
                Command::SetMuted(muted) => player.set_muted(muted),
                Command::SetAudioTrack(id) => match player.set_audio_track(id) {
                    Ok(()) => refresh_media_info(&player, &shared, file_size_bytes),
                    Err(error) => set_nonfatal_error(&shared, error.to_string()),
                },
                Command::SetSubtitleTrack(id) => match player.set_subtitle_track(id) {
                    Ok(()) => refresh_media_info(&player, &shared, file_size_bytes),
                    Err(error) => set_nonfatal_error(&shared, error.to_string()),
                },
                Command::Shutdown => break,
            }
        }

        let mut snapshot = player.snapshot();
        if waiting_for_start {
            match snapshot.state {
                PlaybackState::Playing => {
                    waiting_for_start = false;
                    startup_deadline = None;
                    info_refresh_attempts = 0;
                    next_info_refresh = Some(Instant::now());
                }
                PlaybackState::Error | PlaybackState::Ended => {
                    waiting_for_start = false;
                    startup_deadline = None;
                }
                PlaybackState::Stopped => {
                    // Immediately after play(), libVLC can briefly report NothingSpecial/Stopped.
                    // Keep the externally visible state as Opening during that transition.
                    snapshot.state = PlaybackState::Opening;
                }
                _ => {}
            }

            if startup_deadline.is_some_and(|deadline| Instant::now() >= deadline)
                && snapshot.state != PlaybackState::Playing
            {
                player.stop();
                set_fatal_error(
                    &shared,
                    "Timed out while starting playback. The file may be damaged or unsupported."
                        .to_owned(),
                );
                waiting_for_start = false;
                startup_deadline = None;
                poll_active = false;
                continue;
            }
        }

        if snapshot.state == PlaybackState::Playing
            && info_refresh_attempts < INFO_REFRESH_ATTEMPTS
            && next_info_refresh.is_some_and(|deadline| Instant::now() >= deadline)
        {
            refresh_media_info(&player, &shared, file_size_bytes);
            info_refresh_attempts += 1;
            next_info_refresh = Some(Instant::now() + INFO_REFRESH_INTERVAL);
        }

        poll_active = should_poll(waiting_for_start, snapshot.state);
        set_snapshot(&shared, snapshot);
    }
}

fn should_poll(waiting_for_start: bool, state: PlaybackState) -> bool {
    waiting_for_start
        || matches!(
            state,
            PlaybackState::Opening | PlaybackState::Buffering | PlaybackState::Playing
        )
}

fn refresh_media_info(
    player: &VlcPlayer,
    shared: &Arc<Mutex<SharedState>>,
    file_size_bytes: Option<u64>,
) {
    set_media_info(shared, player.runtime_media_info(file_size_bytes));
}

fn lock_state(shared: &Arc<Mutex<SharedState>>) -> MutexGuard<'_, SharedState> {
    match shared.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    }
}

fn set_snapshot(shared: &Arc<Mutex<SharedState>>, snapshot: PlaybackSnapshot) {
    lock_state(shared).snapshot = snapshot;
}

fn set_media_info(shared: &Arc<Mutex<SharedState>>, media_info: MediaRuntimeInfo) {
    let mut state = lock_state(shared);
    if state.media_info.as_ref() != &media_info {
        state.media_info = Arc::new(media_info);
        state.media_info_revision = state.media_info_revision.wrapping_add(1);
    }
}

fn set_fatal_error(shared: &Arc<Mutex<SharedState>>, message: String) {
    let mut state = lock_state(shared);
    state.snapshot.state = PlaybackState::Error;
    state.pending_error = Some(message);
}

fn set_nonfatal_error(shared: &Arc<Mutex<SharedState>>, message: String) {
    lock_state(shared).pending_error = Some(message);
}

#[cfg(test)]
mod tests {
    use super::*;

    // Exercise the actual queue/report protocol without loading libVLC or requiring Qt.
    fn harness() -> (VlcWorker, Receiver<Command>) {
        let (commands, receiver) = mpsc::sync_channel(COMMAND_QUEUE_CAPACITY);
        let shared = Arc::new(Mutex::new(SharedState {
            snapshot: PlaybackSnapshot::default(),
            media_info: Arc::new(MediaRuntimeInfo::default()),
            media_info_revision: 0,
            pending_error: None,
            pending_commands: 0,
            alive: true,
        }));
        (
            VlcWorker {
                commands: Some(commands),
                shared,
                join: None,
                stopping: Arc::new(AtomicBool::new(false)),
            },
            receiver,
        )
    }

    #[test]
    fn waiting_for_start_keeps_polling_through_transient_paused_state() {
        assert!(should_poll(true, PlaybackState::Paused));
        assert!(should_poll(true, PlaybackState::Stopped));
        assert!(!should_poll(false, PlaybackState::Paused));
        assert!(should_poll(false, PlaybackState::Playing));
    }

    #[test]
    fn begin_shutdown_disconnects_new_commands_without_joining() {
        let (mut worker, _receiver) = harness();
        worker.begin_shutdown();
        assert!(worker.stopping.load(Ordering::Acquire));
        assert!(worker.commands.is_none());
        assert!(matches!(worker.play(), Err(VlcError::WorkerDisconnected)));
        assert!(worker.finish_shutdown());
    }

    #[test]
    fn idle_report_cannot_acknowledge_an_unprocessed_open() {
        let (worker, receiver) = harness();
        worker.open_local(PathBuf::from("sample.mp4")).unwrap();
        assert!(worker.report().pending_commands);
        let _command = receiver.recv().unwrap();
        let completion = CommandCompletion(Arc::clone(&worker.shared));
        // Dequeueing alone must not stop the UI timer.
        assert!(worker.report().pending_commands);
        set_snapshot(
            &worker.shared,
            PlaybackSnapshot {
                state: PlaybackState::Opening,
                ..PlaybackSnapshot::default()
            },
        );
        drop(completion);
        let report = worker.report();
        assert!(!report.pending_commands);
        assert_eq!(report.snapshot.state, PlaybackState::Opening);
    }

    #[test]
    fn paused_track_change_keeps_error_until_completion() {
        let (worker, receiver) = harness();
        worker.set_audio_track(999).unwrap();
        let _command = receiver.recv().unwrap();
        let completion = CommandCompletion(Arc::clone(&worker.shared));
        set_nonfatal_error(&worker.shared, "Track unavailable".into());
        assert!(worker.report().error.is_none());
        drop(completion);
        assert_eq!(
            worker.report().error.as_deref(),
            Some("Track unavailable")
        );
        assert!(worker.report().error.is_none());
    }

    #[test]
    fn rejected_commands_do_not_leave_phantom_pending_work() {
        let (worker, receiver) = harness();
        for _ in 0..COMMAND_QUEUE_CAPACITY {
            worker.pause().unwrap();
        }
        assert!(matches!(worker.stop(), Err(VlcError::CommandQueueFull)));
        for _ in 0..COMMAND_QUEUE_CAPACITY {
            receiver.recv().unwrap();
            drop(CommandCompletion(Arc::clone(&worker.shared)));
        }
        assert!(!worker.report().pending_commands);
    }

    #[test]
    fn initialization_failure_releases_pending_commands() {
        let (worker, _receiver) = harness();
        worker.play().unwrap();
        let lifetime = WorkerLifetime(Arc::clone(&worker.shared));
        set_fatal_error(&worker.shared, "Missing backend".into());
        drop(lifetime);
        let report = worker.report();
        assert!(!report.pending_commands);
        assert_eq!(report.snapshot.state, PlaybackState::Error);
        assert_eq!(report.error.as_deref(), Some("Missing backend"));
        assert!(matches!(worker.play(), Err(VlcError::WorkerDisconnected)));
    }

    #[test]
    fn shutdown_signal_bypasses_a_full_queue() {
        let (worker, _receiver) = harness();
        for _ in 0..COMMAND_QUEUE_CAPACITY {
            worker.play().unwrap();
        }
        let stopping = Arc::clone(&worker.stopping);
        drop(worker);
        assert!(stopping.load(Ordering::Acquire));
    }
}

// Guards keep terminal/error branches from forgetting acknowledgement or liveness.
struct CommandCompletion(Arc<Mutex<SharedState>>);
impl Drop for CommandCompletion {
    fn drop(&mut self) {
        let mut state = lock_state(&self.0);
        state.pending_commands = state.pending_commands.saturating_sub(1);
    }
}
struct WorkerLifetime(Arc<Mutex<SharedState>>);
impl Drop for WorkerLifetime {
    fn drop(&mut self) {
        let mut state = lock_state(&self.0);
        state.alive = false;
        state.pending_commands = 0;
    }
}
