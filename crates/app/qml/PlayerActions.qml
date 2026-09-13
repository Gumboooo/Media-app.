import QtQuick
import QtQuick.Controls.Basic

// One Action instance per command, shared by controls and shortcuts.
QtObject {
    id: root
    required property var player
    required property var window
    required property var openDialog

    readonly property Action open: Action {
        objectName: "media.open"
        text: "Open"
        shortcut: StandardKey.Open
        onTriggered: root.openDialog.open()
    }
    readonly property Action playPause: Action {
        objectName: "player.play_pause"
        text: root.player.playing ? "Pause" : "Play"
        enabled: root.player.hasMedia
        shortcut: "Space"
        onTriggered: root.player.playPause()
    }
    readonly property Action stop: Action {
        objectName: "player.stop"
        text: "Stop"
        enabled: root.player.hasMedia
        shortcut: "S"
        onTriggered: root.player.stop()
    }
    readonly property Action mute: Action {
        objectName: "audio.mute"
        text: root.player.muted ? "Unmute" : "Mute"
        shortcut: "M"
        onTriggered: root.player.toggleMute()
    }
    readonly property Action fullscreen: Action {
        objectName: "player.fullscreen"
        text: root.window.fullScreen ? "Exit fullscreen" : "Fullscreen"
        shortcut: "F"
        onTriggered: root.window.toggleFullscreen()
    }
    readonly property Action inspect: Action {
        objectName: "media.inspect"
        text: root.window.showMediaInfo ? "Hide info" : "Info"
        enabled: root.player.hasMedia
        shortcut: "Ctrl+I"
        onTriggered: root.window.showMediaInfo = !root.window.showMediaInfo
    }
    readonly property Action seekBackward: Action {
        objectName: "player.seek_backward"
        enabled: root.player.hasMedia
        shortcut: "Left"
        onTriggered: root.player.seekBy(-5000)
    }
    readonly property Action seekForward: Action {
        objectName: "player.seek_forward"
        enabled: root.player.hasMedia
        shortcut: "Right"
        onTriggered: root.player.seekBy(5000)
    }
    readonly property Action audioTrack: Action {
        objectName: "audio.next_track"
        text: "Audio · " + root.player.audioTrackLabel
        enabled: root.player.audioTrackCount > 0
        onTriggered: root.player.cycleAudioTrack()
    }
    readonly property Action subtitleTrack: Action {
        objectName: "subtitle.next_track"
        text: "Subs · " + root.player.subtitleTrackLabel
        enabled: root.player.subtitleTrackCount > 0
        onTriggered: root.player.cycleSubtitleTrack()
    }
}
