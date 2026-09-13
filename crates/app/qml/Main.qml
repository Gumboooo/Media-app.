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

    Shortcut {
        sequence: "Escape"
        enabled: appWindow.fullScreen
        onActivated: playerActions.fullscreen.trigger()
    }
    Shortcut {
        sequence: "Up"
        onActivated: player.requestVolume(Math.min(125, player.volume + 5))
    }
    Shortcut {
        sequence: "Down"
        onActivated: player.requestVolume(Math.max(0, player.volume - 5))
    }

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
            height: visible ? Theme.toolbarHeight : 0
            visible: !appWindow.fullScreen
            color: Theme.toolbar

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space4
                anchors.rightMargin: Theme.space3
                spacing: Theme.space3

                Label {
                    text: "Aperture"
                    color: Theme.text
                    font.pixelSize: Theme.textTitle
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    Layout.preferredWidth: Theme.borderWidth
                    Layout.preferredHeight: 18
                    color: Theme.borderStrong
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        Layout.fillWidth: true
                        text: player.mediaTitle.length > 0 ? player.mediaTitle : "Local media player"
                        color: player.mediaTitle.length > 0 ? Theme.text : Theme.textMuted
                        font.pixelSize: Theme.textBody
                        font.weight: player.mediaTitle.length > 0 ? Font.Medium : Font.Normal
                        elide: Text.ElideMiddle
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: player.mediaPath.length > 0 && topBar.height >= 44
                        text: player.mediaPath
                        color: Theme.textDim
                        font.pixelSize: Theme.textTiny
                        elide: Text.ElideMiddle
                    }
                }

                IconButton {
                    action: playerActions.inspect
                    iconName: "info"
                }

                IconButton {
                    action: playerActions.fullscreen
                    iconName: "fullscreen"
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Theme.dividerHeight
                color: Theme.border
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

                    Rectangle {
                        id: emptyDropZone
                        anchors.centerIn: parent
                        width: Math.max(280, Math.min(430, playerPane.width - Theme.space6 * 2))
                        height: Math.max(190, Math.min(240, playerPane.height - Theme.space6 * 2))
                        visible: !player.hasMedia
                        radius: Theme.radiusLarge
                        color: dropArea.containsDrag ? Theme.surface : "transparent"
                        border.width: Theme.borderWidth
                        border.color: dropArea.containsDrag ? Theme.borderStrong : Theme.border

                        Column {
                            anchors.centerIn: parent
                            width: parent.width - Theme.space6 * 2
                            spacing: Theme.space3

                            IconGlyph {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Theme.emptyIconSize
                                height: width
                                name: "open"
                                glyphColor: dropArea.containsDrag ? Theme.text : Theme.textDim
                                strokeWidth: 1.5
                            }

                            Label {
                                width: parent.width
                                text: dropArea.containsDrag ? "Release to open" : "Drop media here"
                                color: Theme.text
                                font.pixelSize: Theme.textEmptyState
                                font.weight: Font.Medium
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Label {
                                width: parent.width
                                text: "Video and audio files stay on this computer"
                                color: Theme.textMuted
                                font.pixelSize: Theme.textEmptySubhead
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }

                            AppButton {
                                anchors.horizontalCenter: parent.horizontalCenter
                                action: playerActions.open
                                text: "Open file"
                            }

                            Label {
                                width: parent.width
                                text: "Ctrl+O"
                                color: Theme.textDim
                                font.pixelSize: Theme.textTiny
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }

                    DropArea {
                        id: dropArea
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
                    width: visible ? Math.min(Theme.inspectorWidth,
                                              Math.max(0, mediaArea.width - Theme.minimumPlayerWidth)) : 0
                    height: parent.height
                    visible: appWindow.showMediaInfo && player.hasMedia && !appWindow.fullScreen
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
