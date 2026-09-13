import QtQuick
import org.aperture.player

// Loaded only by --smoke-test. The normal player never creates this test timer.
Main {
    id: smokeWindow
    property int ticks: 0
    property int stage: 0
    property int mediaArg: Qt.application.arguments.indexOf("--smoke-media")
    property string mediaUrl: mediaArg >= 0 ? Qt.application.arguments[mediaArg + 1] : ""
    property bool skipMixerChecks: Qt.application.arguments.indexOf("--smoke-no-mixer") >= 0

    function backendFailureCode(message) {
        if (message.indexOf("libVLC could not be found") >= 0) return 41
        if (message.indexOf("required libVLC symbol is missing") >= 0) return 42
        if (message.indexOf("supports libVLC 3.x") >= 0) return 43
        if (message.indexOf("create a player instance") >= 0) return 44
        if (message.indexOf("create a media player") >= 0) return 45
        if (message.indexOf("file could not be read") >= 0) return 46
        if (message.indexOf("path is not a regular file") >= 0) return 47
        if (message.indexOf("path cannot be represented safely") >= 0) return 48
        if (message.indexOf("could not create media") >= 0) return 49
        if (message.indexOf("could not start playback") >= 0) return 50
        if (message.indexOf("rejected the requested volume") >= 0) return 51
        if (message.indexOf("worker thread could not be started") >= 0) return 52
        if (message.indexOf("command queue is busy") >= 0) return 53
        if (message.indexOf("worker is no longer running") >= 0) return 54
        if (message.indexOf("playback backend stopped") >= 0) return 55
        if (message.indexOf("Timed out while starting playback") >= 0) return 56
        return 57
    }

    function finish(ok, message, exitCode) {
        probe.stop()
        playbackController.shutdown()
        if (ok) console.info("Aperture smoke passed: " + message)
        else console.error("Aperture smoke failed at stage " + smokeWindow.stage + ": " + message)
        // Preserve either the failing probe stage or a typed backend failure in the process exit
        // code so Windows GUI-subsystem builds remain diagnosable without stdout/stderr.
        Qt.exit(ok ? 0 : (exitCode === undefined ? 20 + smokeWindow.stage : exitCode))
    }
    Timer {
        id: probe
        interval: 200
        repeat: true
        running: true
        onTriggered: {
            smokeWindow.ticks++
            const p = smokeWindow.playbackController
            if (smokeWindow.ticks > 100) {
                smokeWindow.finish(false, "timeout / " + p.statusText)
                return
            }
            if (smokeWindow.mediaUrl.length === 0) {
                if (smokeWindow.ticks >= 3) smokeWindow.finish(true, "startup")
                return
            }
            if (p.errorText.length > 0) {
                smokeWindow.finish(false, p.errorText, smokeWindow.backendFailureCode(p.errorText))
                return
            }
            switch (smokeWindow.stage) {
            case 0:
                p.openUrl(smokeWindow.mediaUrl)
                smokeWindow.stage = 1
                break
            case 1:
                if (p.playing && p.positionMs >= 300) {
                    if (smokeWindow.skipMixerChecks) {
                        // A dummy/headless audio sink has no real mixer. Still validate that
                        // playback itself advances and can transition cleanly into pause.
                        p.playPause()
                        smokeWindow.stage = 3
                    } else {
                        p.requestVolume(65)
                        p.toggleMute()
                        smokeWindow.stage = 2
                    }
                }
                break
            case 2:
                if (p.volume === 65 && p.muted) {
                    p.playPause()
                    smokeWindow.stage = 3
                }
                break
            case 3:
                if (p.statusText === "Paused" && !p.pollingActive) {
                    p.seekTo(2000)
                    smokeWindow.stage = 4
                }
                break
            case 4:
                if (!p.pollingActive && p.positionMs >= 1900) {
                    p.playPause()
                    smokeWindow.stage = 5
                }
                break
            case 5:
                if (p.playing && p.positionMs >= 2200) {
                    p.stop()
                    smokeWindow.stage = 6
                }
                break
            case 6:
                if (p.statusText === "Stopped" && !p.pollingActive) {
                    smokeWindow.width = 800
                    smokeWindow.height = 500
                    smokeWindow.toggleFullscreen()
                    smokeWindow.stage = 7
                }
                break
            case 7:
                smokeWindow.toggleFullscreen()
                smokeWindow.stage = 8
                break
            case 8:
                smokeWindow.finish(true, "play, pause, seek, resume, stop, and window transitions")
                break
            }
        }
    }
}
