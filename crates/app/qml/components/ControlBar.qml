import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import org.aperture.player

Rectangle {
    id: root
    required property var player
    required property var actions

    color: Theme.window
    implicitHeight: controlsColumn.implicitHeight + Theme.space2 + Theme.space3

    Column {
        id: controlsColumn
        anchors.fill: parent
        anchors.leftMargin: Theme.space4
        anchors.rightMargin: Theme.space4
        anchors.topMargin: Theme.space2
        anchors.bottomMargin: Theme.space3
        spacing: Theme.space2

        PlayerTimeline {
            width: parent.width
            player: root.player
        }

        RowLayout {
            width: parent.width
            height: Theme.transportHeight
            spacing: Theme.space2

            AppButton {
                action: root.actions.open
            }

            AppButton {
                action: root.actions.playPause
            }

            AppButton {
                action: root.actions.stop
            }

            AppButton {
                action: root.actions.mute
            }

            AppSlider {
                id: volumeSlider
                Layout.preferredWidth: Theme.volumeSliderWidth
                from: 0
                to: 125
                value: root.player.volume
                onMoved: root.player.requestVolume(Math.round(value))
                ToolTip.visible: hovered
                ToolTip.text: Math.round(value) + "%"
            }

            Item { Layout.fillWidth: true }

            Label {
                Layout.maximumWidth: Theme.statusTextMaxWidth
                text: root.player.statusText
                color: Theme.textMuted
                font.pixelSize: Theme.textSmall
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
            }
        }
        RowLayout {
            width: parent.width
            visible: root.player.audioTrackCount > 0 || root.player.subtitleTrackCount > 0
            spacing: Theme.space2
            AppButton {
                visible: root.player.audioTrackCount > 0
                Layout.maximumWidth: Theme.trackButtonMaxWidth
                action: root.actions.audioTrack
                ToolTip.visible: hovered
                ToolTip.text: "Switch audio track"
            }

            AppButton {
                visible: root.player.subtitleTrackCount > 0
                Layout.maximumWidth: Theme.trackButtonMaxWidth
                action: root.actions.subtitleTrack
                ToolTip.visible: hovered
                ToolTip.text: "Switch subtitle track"
            }

            Item { Layout.fillWidth: true }
        }
    }
}
