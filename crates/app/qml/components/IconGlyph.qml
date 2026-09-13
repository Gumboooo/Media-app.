import QtQuick
import org.aperture.player

Canvas {
    id: root
    property string name: ""
    property color glyphColor: Theme.text
    property real strokeWidth: 1.7

    implicitWidth: 18
    implicitHeight: 18

    onNameChanged: requestPaint()
    onGlyphColorChanged: requestPaint()
    onStrokeWidthChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function line(ctx, x1, y1, x2, y2) {
        ctx.moveTo(x1, y1)
        ctx.lineTo(x2, y2)
    }

    onPaint: {
        const ctx = getContext("2d")
        const w = width
        const h = height
        const sx = w / 18
        const sy = h / 18
        function x(v) { return v * sx }
        function y(v) { return v * sy }

        ctx.clearRect(0, 0, w, h)
        ctx.strokeStyle = glyphColor
        ctx.fillStyle = glyphColor
        ctx.lineWidth = strokeWidth
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        ctx.beginPath()
        switch (name) {
        case "open":
            line(ctx, x(2.5), y(5), x(7.5), y(5))
            line(ctx, x(7.5), y(5), x(9), y(6.5))
            line(ctx, x(9), y(6.5), x(15.5), y(6.5))
            line(ctx, x(15.5), y(6.5), x(14.2), y(14))
            line(ctx, x(14.2), y(14), x(3.2), y(14))
            line(ctx, x(3.2), y(14), x(2.5), y(5))
            ctx.stroke()
            break
        case "play":
            ctx.moveTo(x(6.2), y(4.3))
            ctx.lineTo(x(14), y(9))
            ctx.lineTo(x(6.2), y(13.7))
            ctx.closePath()
            ctx.fill()
            break
        case "pause":
            ctx.fillRect(x(5), y(4.2), x(2.4), y(9.6))
            ctx.fillRect(x(10.6), y(4.2), x(2.4), y(9.6))
            break
        case "stop":
            ctx.fillRect(x(5), y(5), x(8), y(8))
            break
        case "mute":
        case "volume":
            ctx.moveTo(x(3), y(7))
            ctx.lineTo(x(6), y(7))
            ctx.lineTo(x(9), y(4.5))
            ctx.lineTo(x(9), y(13.5))
            ctx.lineTo(x(6), y(11))
            ctx.lineTo(x(3), y(11))
            ctx.closePath()
            ctx.stroke()
            if (name === "mute") {
                line(ctx, x(12), y(6.5), x(16), y(11.5))
                line(ctx, x(16), y(6.5), x(12), y(11.5))
                ctx.stroke()
            } else {
                ctx.beginPath()
                ctx.arc(x(10.5), y(9), x(3.2), -0.8, 0.8, false)
                ctx.stroke()
                ctx.beginPath()
                ctx.arc(x(10.5), y(9), x(5.2), -0.75, 0.75, false)
                ctx.stroke()
            }
            break
        case "info":
            ctx.arc(x(9), y(9), x(6.3), 0, Math.PI * 2, false)
            ctx.stroke()
            ctx.beginPath()
            line(ctx, x(9), y(8), x(9), y(12))
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(x(9), y(5.8), x(0.7), 0, Math.PI * 2, false)
            ctx.fill()
            break
        case "fullscreen":
            line(ctx, x(3), y(7), x(3), y(3))
            line(ctx, x(3), y(3), x(7), y(3))
            line(ctx, x(11), y(3), x(15), y(3))
            line(ctx, x(15), y(3), x(15), y(7))
            line(ctx, x(15), y(11), x(15), y(15))
            line(ctx, x(15), y(15), x(11), y(15))
            line(ctx, x(7), y(15), x(3), y(15))
            line(ctx, x(3), y(15), x(3), y(11))
            ctx.stroke()
            break
        case "seek-back":
            line(ctx, x(5), y(5), x(5), y(13))
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(x(13), y(4.8))
            ctx.lineTo(x(6.8), y(9))
            ctx.lineTo(x(13), y(13.2))
            ctx.closePath()
            ctx.fill()
            break
        case "seek-forward":
            line(ctx, x(13), y(5), x(13), y(13))
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(x(5), y(4.8))
            ctx.lineTo(x(11.2), y(9))
            ctx.lineTo(x(5), y(13.2))
            ctx.closePath()
            ctx.fill()
            break
        case "audio":
            line(ctx, x(7), y(4), x(14), y(2.8))
            line(ctx, x(7), y(4), x(7), y(12))
            line(ctx, x(14), y(2.8), x(14), y(10.7))
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(x(4.8), y(13), x(2.3), 0, Math.PI * 2, false)
            ctx.arc(x(11.8), y(11.7), x(2.3), 0, Math.PI * 2, false)
            ctx.fill()
            break
        case "subtitles":
            ctx.rect(x(2.5), y(4.5), x(13), y(9))
            ctx.stroke()
            ctx.beginPath()
            line(ctx, x(5), y(9), x(8), y(9))
            line(ctx, x(10), y(9), x(13), y(9))
            line(ctx, x(5), y(11.2), x(10), y(11.2))
            line(ctx, x(12), y(11.2), x(13), y(11.2))
            ctx.stroke()
            break
        case "more":
            ctx.arc(x(4), y(9), x(1), 0, Math.PI * 2, false)
            ctx.arc(x(9), y(9), x(1), 0, Math.PI * 2, false)
            ctx.arc(x(14), y(9), x(1), 0, Math.PI * 2, false)
            ctx.fill()
            break
        default:
            break
        }
    }
}
