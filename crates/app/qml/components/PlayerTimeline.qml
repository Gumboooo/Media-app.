import QtQuick
import QtQuick.Controls
import org.aperture.player

Item {
    id: root
    required property var player
    implicitHeight: Theme.timelineHeight

    Row {
        anchors.fill: parent
        spacing: Theme.space3

        Label {
            width: Theme.timelineTimeWidth
            anchors.verticalCenter: parent.verticalCenter
            text: Format.time(root.player.positionMs)
            color: Theme.textMuted
            font.pixelSize: Theme.textSmall
            horizontalAlignment: Text.AlignRight
        }

        Slider {
            id: seekSlider
            width: Math.max(Theme.timelineMinSliderWidth, root.width - (Theme.timelineTimeWidth * 2) - (Theme.space3 * 2))
            anchors.verticalCenter: parent.verticalCenter
            from: 0
            to: Math.max(root.player.durationMs, 1)
            enabled: root.player.hasMedia && root.player.durationMs > 0

            Binding on value {
                when: !seekSlider.pressed
                value: root.player.positionMs
                restoreMode: Binding.RestoreBindingOrValue
            }

            onMoved: {
                if (!pressed) root.player.seekTo(value)
            }

            onPressedChanged: {
                if (!pressed)
                    root.player.seekTo(value)
            }

            background: Rectangle {
                x: seekSlider.leftPadding
                y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                width: seekSlider.availableWidth
                height: Theme.sliderTrackHeight
                radius: height / 2
                color: Theme.border

                Rectangle {
                    width: seekSlider.visualPosition * parent.width
                    height: parent.height
                    radius: parent.radius
                    color: Theme.accent
                }
            }

            handle: Rectangle {
                x: seekSlider.leftPadding + seekSlider.visualPosition * (seekSlider.availableWidth - width)
                y: seekSlider.topPadding + seekSlider.availableHeight / 2 - height / 2
                implicitWidth: seekSlider.pressed ? Theme.sliderHandlePressedSize : Theme.sliderHandleSize
                implicitHeight: implicitWidth
                radius: width / 2
                color: Theme.accent
                border.width: Theme.borderWidth
                border.color: Theme.window

                Behavior on implicitWidth {
                    NumberAnimation { duration: Theme.motionFast }
                }
            }
        }

        Label {
            width: Theme.timelineTimeWidth
            anchors.verticalCenter: parent.verticalCenter
            text: Format.time(root.player.durationMs)
            color: Theme.textMuted
            font.pixelSize: Theme.textSmall
        }
    }
}
