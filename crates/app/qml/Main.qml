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
    property bool closeAfterShutdown: false

    onClosing: function(close) {
        if (appWindow.closeAfterShutdown)
            return

        // Keep the QWindow/WindowContainer alive while libVLC unwinds on its worker thread.
        // This avoids both a UI-thread join and destruction of a native target still in use.
        close.accepted = false
        player.beginShutdown()
        if (player.shutdownComplete) {
            appWindow.closeAfterShutdown = true
            Qt.callLater(appWindow.close)
        } else {
            shutdownTimer.start()
        }
    }

    PlayerController {
        id: player
    }

    VideoSurface {
        id: videoSurface
        // Forward both creation and destruction. A zero handle tells the backend to detach from
        // the old native surface before Qt destroys/recreates it.
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
        if (fullScreen) {
            visibility = visibilityBeforeFullscreen
            return
        }
        visibilityBeforeFullscreen = visibility === Window.Maximized ? Window.Maximized : Window.Windowed
        visibility = Window.FullScreen
    }

    Timer {
        interval: 200
        repeat: true
        running: player.pollingActive && appWindow.visible
        onTriggered: player.refresh()
    }

    Timer {
        id: shutdownTimer
        interval: 50
        repeat: true
        onTriggered: {
            player.pollShutdown()
            if (player.shutdownComplete) {
                stop()
                appWindow.closeAfterShutdown = true
                Qt.callLater(appWindow.close)
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Rectangle {
            id: topBar
            width: parent.width
            height: Theme.toolbarHeight
            color: Theme.window

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space4
                spacing: Theme.space3

                Label {
                    Layout.fillWidth: true
                    text: player.mediaTitle.length > 0 ? player.mediaTitle : "Aperture"
                    color: Theme.text
                    font.pixelSize: Theme.textTitle
                    font.weight: Font.Medium
                    elide: Text.ElideMiddle
                }

                AppButton {
                    action: playerActions.inspect
                }

                AppButton {
                    action: playerActions.fullscreen
                }
            }
        }

        Item {
            id: mediaArea
            width: parent.width
            height: Math.max(0, parent.height - topBar.height - errorBanner.height - controlBar.height)

            Row {
                anchors.fill: parent
                spacing: 0

                Item {
                    id: playerPane
                    width: Math.max(0, parent.width - infoPanel.width)
                    height: parent.height

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.player
                    }

                    WindowContainer {
                        id: videoContainer
                        anchors.fill: parent
                        window: videoSurface.window
                        visible: player.hasMedia
                        Component.onCompleted: {
                            if (videoSurface.nativeHandle !== 0)
                                player.attachVideoSurface(videoSurface.nativeHandle)
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: Theme.space4
                        visible: !player.hasMedia

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Open a media file"
                            color: Theme.text
                            font.pixelSize: Theme.textEmptyState
                            font.weight: Font.Medium
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: "Drop a file here, or press Ctrl+O"
                            color: Theme.textMuted
                            font.pixelSize: Theme.textBody
                        }

                        AppButton {
                            anchors.horizontalCenter: parent.horizontalCenter
                            action: playerActions.open
                            text: "Choose file"
                        }
                    }

                    DropArea {
                        anchors.fill: parent
                        onDropped: function(drop) {
                            if (drop.urls.length > 0) {
                                player.openUrl(drop.urls[0])
                                drop.acceptProposedAction()
                            }
                        }
                    }
                }

                MediaInfoPanel {
                    id: infoPanel
                    width: visible ? Math.min(Theme.inspectorWidth, Math.max(0, mediaArea.width - Theme.minimumPlayerWidth)) : 0
                    height: parent.height
                    visible: appWindow.showMediaInfo && player.hasMedia
                    player: appWindow.playbackController
                }
            }
        }

        Rectangle {
            id: errorBanner
            visible: player.errorText.length > 0
            width: parent.width
            height: visible ? implicitHeight : 0
            implicitHeight: errorRow.implicitHeight + Theme.space3 * 2
            color: Theme.errorSurface
            border.width: Theme.borderWidth
            border.color: Theme.errorBorder

            RowLayout {
                id: errorRow
                anchors.fill: parent
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space3
                spacing: Theme.space3

                Label {
                    Layout.fillWidth: true
                    Layout.minimumWidth: Theme.errorTextMinWidth
                    text: player.errorText
                    color: Theme.errorText
                    font.pixelSize: Theme.textBody
                    wrapMode: Text.Wrap
                }

                AppButton {
                    id: dismissButton
                    text: "Dismiss"
                    onClicked: player.clearError()
                }
            }
        }

        ControlBar {
            id: controlBar
            width: parent.width
            player: appWindow.playbackController
            actions: playerActions
        }
    }
}
