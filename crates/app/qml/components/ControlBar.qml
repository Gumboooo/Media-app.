import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.aperture.player

Rectangle {
    id: root
    required property var player
    required property var actions

    color: Theme.playerControlSurface
    implicitHeight: Theme.controlBarHeight
    border.width: Theme.borderWidth
    border.color: Theme.border

    Column {
        anchors.fill: parent
        anchors.leftMargin: Theme.space4
        anchors.rightMargin: Theme.space4
        anchors.topMargin: Theme.space2
        anchors.bottomMargin: Theme.space2
        spacing: Theme.space1

        PlayerTimeline {
            width: parent.width
            player: root.player
        }

        RowLayout {
            width: parent.width
            height: Theme.transportHeight
            spacing: Theme.space2

            Item {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                height: parent.height

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space2

                    IconButton {
                        action: root.actions.open
                        iconName: "open"
                    }

                    Label {
                        width: Math.min(Theme.statusTextMaxWidth,
                                        Math.max(0, root.width / 2 - 220))
                        anchors.verticalCenter: parent.verticalCenter
                        visible: width > 70
                        text: root.player.statusText
                        color: Theme.textDim
                        font.pixelSize: Theme.textTiny
                        elide: Text.ElideRight
                    }
                }
            }

            Row {
                Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                spacing: Theme.space1

                IconButton {
                    action: root.actions.seekBackward
                    iconName: "seek-back"
                    toolTipText: "Back 5 seconds"
                }

                IconButton {
                    action: root.actions.playPause
                    iconName: root.player.playing ? "pause" : "play"
                    prominent: true
                }

                IconButton {
                    action: root.actions.stop
                    iconName: "stop"
                }

                IconButton {
                    action: root.actions.seekForward
                    iconName: "seek-forward"
                    toolTipText: "Forward 5 seconds"
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                height: parent.height

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.space1

                    IconButton {
                        visible: root.player.audioTrackCount > 1
                        action: root.actions.audioTrack
                        iconName: "audio"
                        toolTipText: root.actions.audioTrack.text
                    }

                    IconButton {
                        visible: root.player.subtitleTrackCount > 0
                        action: root.actions.subtitleTrack
                        iconName: "subtitles"
                        toolTipText: root.actions.subtitleTrack.text
                    }

                    IconButton {
                        action: root.actions.mute
                        iconName: root.player.muted || root.player.volume === 0 ? "mute" : "volume"
                    }

                    AppSlider {
                        id: volumeSlider
                        visible: root.width >= 820
                        width: Theme.volumeSliderWidth
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0
                        to: 125
                        value: root.player.volume
                        onMoved: root.player.requestVolume(Math.round(value))
                        ToolTip.visible: hovered
                        ToolTip.delay: 350
                        ToolTip.text: Math.round(value) + "%"
                    }
                }
            }
        }
    }
}
