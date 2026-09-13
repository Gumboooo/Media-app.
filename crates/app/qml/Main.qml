import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QtQuick.Window
import org.aperture.player

ApplicationWindow {
    id: appWindow
    width: Theme.initialWindowWidth
    height: Theme.initialWindowHeight
    minimumWidth: Theme.minimumWindowWidth
    minimumHeight: Theme.minimumWindowHeight
    visible: true
    color: Theme.window
    title: player.mediaTitle.length > 0 ? player.mediaTitle + " — Aperture" : "Aperture"

    readonly property var playbackController: player
    readonly property var filePicker: openDialog

    property bool fullScreen: visibility === Window.FullScreen
    property int visibilityBeforeFullscreen: Window.Windowed
    property bool showMediaInfo: false

    onClosing: player.shutdown()

    PlayerController {
        id: player
    }

    VideoSurface {
        id: videoSurface
        // SurfaceCreated can fire inside the C++ object's constructor, before this QML signal
        // handler exists. Bind once after QML construction as well as on every later recreation.
        Component.onCompleted: player.attachVideoSurface(nativeHandle)
        onNativeHandleChanged: player.attachVideoSurface(nativeHandle)
    }

    FileDialog {
        id: openDialog
        title: "Open media"
        fileMode: FileDialog.OpenFile
        nameFilters: [
            "Media files (*.mp4 *.mkv *.webm *.mov *.avi *.m4v *.mp3 *.flac *.wav *.ogg *.m4a *.aac *.opus)",
            "All files (*)"
        ]
        onAccepted: player.openUrl(selectedFile)
    }

    PlayerActions {
        id: playerActions
        player: appWindow.playbackController
        window: appWindow
        openDialog: appWindow.filePicker
    }
    Shortcut { sequence: "Escape"; enabled: appWindow.fullScreen; onActivated: playerActions.fullscreen.trigger() }
    Shortcut { sequence: "Up"; onActivated: player.requestVolume(Math.min(125, player.volume + 5)) }
    Shortcut { sequence: "Down"; onActivated: player.requestVolume(Math.max(0, player.volume - 5)) }

    function toggleFullscreen() {
        if (!fullScreen) {
            visibilityBeforeFullscreen = visibility
            showFullScreen()
        } else if (visibilityBeforeFullscreen === Window.Maximized) {
            showMaximized()
        } else {
            showNormal()
        }
    }

    background: Rectangle { color: Theme.window }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Theme.topBarHeight
            color: Theme.panel
            border.color: Theme.border
            border.width: Theme.borderWidth

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space16
                anchors.rightMargin: Theme.space16
                spacing: Theme.space8

                Label {
                    text: player.mediaTitle.length > 0 ? player.mediaTitle : "Aperture"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontTitle
                    font.weight: Font.DemiBold
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }

                AppButton {
                    text: appWindow.showMediaInfo ? "Hide info" : "Media info"
                    enabled: player.hasMedia
                    onClicked: appWindow.showMediaInfo = !appWindow.showMediaInfo
                }
                AppButton {
                    text: "Open"
                    onClicked: openDialog.open()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            Item {
                id: mediaArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Rectangle {
                    anchors.fill: parent
                    color: Theme.player

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.space8
                        visible: !player.hasMedia

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Drop media here or open a file"
                            color: Theme.textPrimary
                            font.pixelSize: Theme.fontHeading
                        }
                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Local playback stays local-first. No account or library scan."
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontBody
                        }
                    }
                }

                WindowContainer {
                    anchors.fill: parent
                    window: videoSurface.window
                    visible: player.hasMedia && player.errorText.length === 0
                }

                DropArea {
                    anchors.fill: parent
                    onDropped: function(drop) {
                        if (drop.hasUrls && drop.urls.length > 0) {
                            player.openUrl(drop.urls[0])
                            drop.acceptProposedAction()
                        }
                    }
                }
            }

            MediaInfoPanel {
                Layout.preferredWidth: visible ? Theme.infoPanelWidth : 0
                Layout.fillHeight: true
                visible: appWindow.showMediaInfo && player.hasMedia
                player: appWindow.playbackController
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: controlColumn.implicitHeight + (Theme.space12 * 2)
            color: Theme.panel
            border.color: Theme.border
            border.width: Theme.borderWidth

            ColumnLayout {
                id: controlColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Theme.space16
                anchors.rightMargin: Theme.space16
                spacing: Theme.space8

                PlayerTimeline {
                    Layout.fillWidth: true
                    player: appWindow.playbackController
                }

                ControlBar {
                    Layout.fillWidth: true
                    player: appWindow.playbackController
                    actions: playerActions
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: errorColumn.implicitHeight + (Theme.space12 * 2)
        color: Theme.errorPanel
        visible: player.errorText.length > 0
        z: 20

        ColumnLayout {
            id: errorColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Theme.space16
            anchors.rightMargin: Theme.space16
            spacing: Theme.space4

            Label {
                Layout.fillWidth: true
                text: "This file could not be played."
                color: Theme.errorText
                font.pixelSize: Theme.fontBody
                font.weight: Font.DemiBold
            }
            Label {
                Layout.fillWidth: true
                text: player.errorText
                color: Theme.errorText
                opacity: Theme.opacitySecondary
                font.pixelSize: Theme.fontCaption
                wrapMode: Text.Wrap
            }
        }
    }
}
