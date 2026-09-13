import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import org.aperture.player

Basic.Button {
    id: control
    implicitHeight: Theme.controlHeight
    implicitWidth: Math.max(Theme.buttonMinWidth, contentItem.implicitWidth + leftPadding + rightPadding)
    padding: Theme.space2
    leftPadding: Theme.space4
    rightPadding: Theme.space4
    font.pixelSize: Theme.textBody
    font.weight: Font.Medium

    contentItem: Text {
        text: control.text
        color: !control.enabled ? Theme.textDisabled
              : control.down ? Theme.text
              : Theme.text
        font: control.font
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: Theme.radiusSmall
        color: !control.enabled ? Theme.surfaceDisabled
              : control.down ? Theme.surfacePressed
              : control.hovered ? Theme.surfaceHover
              : Theme.surface
        border.width: Theme.borderWidth
        border.color: control.activeFocus ? Theme.focusBorder : Theme.border

        Behavior on color {
            ColorAnimation { duration: Theme.motionFast }
        }
    }
}
