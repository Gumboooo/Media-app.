import QtQuick
import QtQuick.Controls.Basic as Basic
import org.aperture.player

Basic.Slider {
    id: control
    implicitHeight: Theme.sliderHitHeight

    background: Rectangle {
        x: control.leftPadding
        y: control.topPadding + control.availableHeight / 2 - height / 2
        width: control.availableWidth
        height: Theme.sliderTrackHeight
        radius: height / 2
        color: control.enabled ? Theme.sliderTrack : Theme.surfaceDisabled

        Rectangle {
            width: control.visualPosition * parent.width
            height: parent.height
            radius: parent.radius
            color: control.enabled ? Theme.accent : Theme.textDisabled
        }
    }

    handle: Rectangle {
        x: control.leftPadding + control.visualPosition * (control.availableWidth - width)
        y: control.topPadding + control.availableHeight / 2 - height / 2
        implicitWidth: control.pressed ? Theme.sliderHandlePressedSize : Theme.sliderHandleSize
        implicitHeight: implicitWidth
        radius: width / 2
        color: control.enabled ? Theme.accent : Theme.textDisabled
        border.width: Theme.borderWidth
        border.color: control.activeFocus ? Theme.focusBorder : Theme.playerControlSurface

        Behavior on implicitWidth {
            NumberAnimation { duration: Theme.motionFast }
        }
    }
}
