import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import org.aperture.player

Rectangle {
    id: root
    required property var player

    color: Theme.surface
    border.width: Theme.borderWidth
    border.color: Theme.border

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: details.implicitHeight + Theme.space5 * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: details
            x: Theme.space5
            y: Theme.space5
            width: root.width - Theme.space5 * 2
            spacing: Theme.space4

            Label {
                Layout.fillWidth: true
                text: "Media info"
                color: Theme.text
                font.pixelSize: Theme.textTitle
                font.weight: Font.DemiBold
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Theme.borderWidth
                color: Theme.border
            }

            InfoField {
                Layout.fillWidth: true
                label: "File"
                value: root.player.mediaTitle.length > 0 ? root.player.mediaTitle : "—"
            }

            InfoField {
                Layout.fillWidth: true
                label: "Location"
                value: root.player.mediaPath.length > 0 ? root.player.mediaPath : "—"
                wrapValue: true
            }

            InfoField {
                Layout.fillWidth: true
                label: "Size"
                value: root.player.mediaSizeText
            }

            InfoField {
                Layout.fillWidth: true
                label: "Duration"
                value: Format.time(root.player.durationMs)
            }

            InfoField {
                Layout.fillWidth: true
                label: "Video"
                value: root.player.videoDimensionsText
            }

            InfoField {
                Layout.fillWidth: true
                label: "Audio"
                value: root.player.audioTrackCount > 0
                    ? root.player.audioTrackLabel + "  (" + root.player.audioTrackCount + ")"
                    : "None"
            }

            InfoField {
                Layout.fillWidth: true
                label: "Subtitles"
                value: root.player.subtitleTrackCount > 0
                    ? root.player.subtitleTrackLabel + "  (" + root.player.subtitleTrackCount + ")"
                    : "None"
            }

            InfoField {
                Layout.fillWidth: true
                label: "State"
                value: root.player.statusText
            }
        }
    }
}
