pragma Singleton
import QtQuick

QtObject {
    function time(ms) {
        if (!Number.isFinite(ms) || ms < 0)
            return "0:00"
        const total = Math.floor(ms / 1000)
        const seconds = total % 60
        const minutes = Math.floor(total / 60) % 60
        const hours = Math.floor(total / 3600)
        if (hours > 0)
            return hours + ":" + String(minutes).padStart(2, "0") + ":" + String(seconds).padStart(2, "0")
        return minutes + ":" + String(seconds).padStart(2, "0")
    }
}
