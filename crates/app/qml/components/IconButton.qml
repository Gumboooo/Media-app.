import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import org.aperture.player

Basic.Button {
    id: control
    property string iconName: ""
    property string toolTipText: action ? action.text : text
    property bool prominent: false

    implicitWidth: prominent ? Theme.primaryTransportSize : Theme.iconButtonSize
    implicitHeight: implicitWidth
    padding: 0

    contentItem: Item {
        IconGlyph {
            anchors.centerIn: parent
            width: control.prominent ? 19 : 18
            height: width
            name: control.iconName
            glyphColor: !control.enabled ? Theme.textDisabled
                       : control.prominent ? Theme.accentText
                       : Theme.text
        }
    }

    background: Rectangle {
        radius: control.prominent ? width / 2 : Theme.radiusSmall
        color: !control.enabled ? "transparent"
              : control.prominent ? (control.down ? Theme.surfacePressed : Theme.accent)
              : control.down ? Theme.surfacePressed
              : control.hovered ? Theme.surfaceHover
              : "transparent"
        border.width: control.activeFocus ? Theme.borderWidth : 0
        border.color: Theme.focusBorder

        Behavior on color {
            ColorAnimation { duration: Theme.motionFast }
        }
    }

    ToolTip.visible: hovered && toolTipText.length > 0
    ToolTip.delay: 450
    ToolTip.text: toolTipText
}
