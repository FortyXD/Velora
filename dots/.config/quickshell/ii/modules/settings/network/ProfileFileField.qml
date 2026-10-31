import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/** A certificate or key file of the profile being edited. */
RowLayout {
    id: root
    required property string fieldKey
    property string label: ""
    property alias textKey: fieldRow.fieldKey
    readonly property alias fieldRow: fieldRow

    Layout.fillWidth: true
    spacing: 6

    ProfileTextField {
        id: fieldRow
        Layout.fillWidth: true
        fieldKey: root.fieldKey
        label: root.label
        placeholderText: "/path/to/file"
    }
    DialogButton {
        Layout.alignment: Qt.AlignBottom
        Layout.bottomMargin: 8
        Layout.rightMargin: 8
        buttonText: Translation.tr("Choose…")
        onClicked: fileDialog.open()
    }
    FileDialog {
        id: fileDialog
        onAccepted: {
            ProfileEditor.set(root.fieldKey, FileUtils.trimFileProtocol(decodeURIComponent(selectedFile.toString())));
            ProfileEditor.reloaded();
        }
    }
}
