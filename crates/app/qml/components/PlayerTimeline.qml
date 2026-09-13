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
            color: root.player.hasMedia ? Theme.textMuted : Theme.textDim
            font.pixelSize: Theme.textSmall
            font.family: "Segoe UI"
            horizontalAlignment: Text.AlignLeft
        }

        AppSlider {
            id: seekSlider
            width: Math.max(Theme.timelineMinSliderWidth,
                            root.width - (Theme.timelineTimeWidth * 2) - (Theme.space3 * 2))
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
                if (!pressed)
                    root.player.seekTo(value)
            }

            onPressedChanged: {
                if (!pressed)
                    root.player.seekTo(value)
            }

            ToolTip.visible: hovered && enabled
            ToolTip.delay: 350
            ToolTip.text: Format.time(value)
        }

        Label {
            width: Theme.timelineTimeWidth
            anchors.verticalCenter: parent.verticalCenter
            text: Format.time(root.player.durationMs)
            color: root.player.hasMedia ? Theme.textMuted : Theme.textDim
            font.pixelSize: Theme.textSmall
            font.family: "Segoe UI"
            horizontalAlignment: Text.AlignRight
        }
    }
}
