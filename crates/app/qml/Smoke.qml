import QtQuick
import org.aperture.player

// Loaded only by --smoke-test. The normal player never creates this test timer.
Main {
    id: smokeWindow
    property int ticks: 0
    property int stage: 0
    property int mediaArg: Qt.application.arguments.indexOf("--smoke-media")
    property string mediaUrl: mediaArg >= 0 ? Qt.application.arguments[mediaArg + 1] : ""

    function finish(ok, message) {
        probe.stop()
        playbackController.shutdown()
        if (ok) console.info("APERTURE_SMOKE_OK " + message)
        else console.error("APERTURE_SMOKE_FAILED " + message)
        Qt.quit()
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
                smokeWindow.finish(false, "timeout at stage " + smokeWindow.stage + " / " + p.statusText)
                return
            }
            if (smokeWindow.mediaUrl.length === 0) {
                if (smokeWindow.ticks >= 3) smokeWindow.finish(true, "startup")
                return
            }
            if (p.errorText.length > 0) {
                smokeWindow.finish(false, p.errorText)
                return
            }
            switch (smokeWindow.stage) {
            case 0:
                p.openUrl(smokeWindow.mediaUrl)
                smokeWindow.stage = 1
                break
            case 1:
                if (p.playing && p.positionMs >= 300) {
                    p.requestVolume(65)
                    p.toggleMute()
                    smokeWindow.stage = 2
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
                smokeWindow.finish(true, "audio transport and window transitions")
                break
            }
        }
    }
}
