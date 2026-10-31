import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A password of the profile being edited: left alone unless something is typed, shown only on request, and with
 * the same choices as plasma-nm for where it is kept.
 */
ColumnLayout {
    id: root
    required property string fieldKey
    property string label: Translation.tr("Password")
    property string flagsKey: "" // Empty when this password has no storage choice
    property bool flagsAsText: false // A VPN's flags are text in its data dictionary
    property bool revealed: false

    readonly property string typed: ProfileEditor.changes[root.fieldKey] ?? ""
    readonly property string saved: ProfileEditor.secrets[root.fieldKey] ?? ""
    readonly property var storageOptions: [
        { displayName: Translation.tr("For all users (kept by the system)"), value: 0 },
        { displayName: Translation.tr("Only for me (kept in the keyring)"), value: 1 },
        { displayName: Translation.tr("Ask every time"), value: 2 },
        { displayName: Translation.tr("Not needed"), value: 4 },
    ]
    readonly property int storage: {
        const flags = root.flagsKey.length > 0 ? ProfileEditor.value(root.flagsKey, 0) : 0;
        return parseInt(flags) || 0;
    }
    readonly property bool hasStored: root.storage === 0 || root.storage === 1

    function show(): void {
        const text = root.typed || (root.revealed ? root.saved : "");
        if (field.text !== text) field.text = text;
    }

    function toggleReveal(): void {
        root.revealed = !root.revealed;
        if (root.revealed && root.saved.length === 0 && !ProfileEditor.isNew) ProfileEditor.readSecrets(() => root.show());
        else root.show();
    }

    onSavedChanged: root.show()
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    Layout.topMargin: 4
    Layout.bottomMargin: 4
    spacing: 6

    Connections {
        target: ProfileEditor
        function onReloaded() {
            root.revealed = false;
            root.show();
        }
    }

    StyledText {
        text: root.label
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colOnLayer2
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.hasStored
        spacing: 6

        TextField {
            id: field
            Layout.fillWidth: true
            echoMode: root.revealed ? TextInput.Normal : TextInput.Password
            placeholderText: ProfileEditor.isNew ? Translation.tr("Password") : Translation.tr("Saved, unchanged")
            placeholderTextColor: Appearance.colors.colSubtext
            color: Appearance.colors.colOnLayer2
            leftPadding: 14
            topPadding: 9
            bottomPadding: 9
            font.pixelSize: Appearance.font.pixelSize.small
            onTextEdited: ProfileEditor.set(root.fieldKey, field.text)
            background: Rectangle {
                implicitHeight: 38
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
                border.width: field.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
            }
        }
        RippleButton {
            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.full
            colBackgroundHover: Appearance.colors.colLayer3Hover
            onClicked: root.toggleReveal()
            contentItem: MaterialSymbol {
                text: root.revealed ? "visibility_off" : "visibility"
                iconSize: 18
                color: Appearance.colors.colSubtext
                horizontalAlignment: Text.AlignHCenter
            }
            StyledToolTip {
                text: root.revealed ? Translation.tr("Hide password") : Translation.tr("Show password")
            }
        }
    }

    ChoiceDropdown {
        visible: root.flagsKey.length > 0
        Layout.fillWidth: true
        maximumWidth: 100000
        options: root.storageOptions
        currentValue: root.storage
        onSelected: value => ProfileEditor.set(root.flagsKey, root.flagsAsText ? `${value}` : value)
    }
}
