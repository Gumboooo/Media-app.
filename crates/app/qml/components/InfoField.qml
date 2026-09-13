import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import org.aperture.player

ColumnLayout {
    id: root
    required property string label
    required property string value
    property bool wrapValue: false
    spacing: Theme.space1

    Label {
        Layout.fillWidth: true
        text: root.label
        color: Theme.textMuted
        font.pixelSize: Theme.textSmall
    }

    Label {
        Layout.fillWidth: true
        text: root.value
        color: Theme.text
        font.pixelSize: Theme.textBody
        elide: root.wrapValue ? Text.ElideNone : Text.ElideRight
        wrapMode: root.wrapValue ? Text.WrapAnywhere : Text.NoWrap
        textFormat: Text.PlainText
    }
}
