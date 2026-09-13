import QtQuick
import QtQuick.Controls.Basic
import org.aperture.player

Button {
    id: control
    implicitHeight: Theme.controlHeight
    padding: Theme.space3
    leftPadding: Theme.space4
    rightPadding: Theme.space4
    font.pixelSize: Theme.textBody

    contentItem: Text {
        text: control.text
        color: control.enabled ? Theme.text : Theme.textMuted
        font: control.font
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: control.down ? Theme.surfaceHover : (control.hovered ? Theme.surfaceHover : Theme.surface)
        border.width: Theme.borderWidth
        border.color: control.activeFocus ? Theme.textMuted : Theme.border

        Behavior on color {
            ColorAnimation { duration: Theme.motionFast }
        }
    }
}
