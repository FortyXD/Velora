import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * Password entry shown right inside a network row: a field with an eye to reveal what was typed,
 * an error line, and Connect / Cancel. Focuses itself when it appears.
 */
ColumnLayout {
    id: root
    property string errorText: ""
    property string acceptText: Translation.tr("Connect")
    property string placeholderText: Translation.tr("Password")
    property bool busy: false
    property bool allowEmpty: false // For open networks, where the password is optional
    readonly property alias text: field.text

    signal accepted(string password)
    signal canceled()

    spacing: 8

    function submit() {
        if ((field.text.length === 0 && !root.allowEmpty) || root.busy) return;
        root.accepted(field.text);
    }

    property bool focusOnShow: true
    Component.onCompleted: if (root.focusOnShow) field.forceActiveFocus()

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        TextField {
            id: field
            Layout.fillWidth: true
            echoMode: revealButton.toggled ? TextInput.Normal : TextInput.Password
            placeholderText: root.placeholderText
            placeholderTextColor: Appearance.colors.colSubtext
            color: Appearance.colors.colOnLayer3
            selectionColor: Appearance.colors.colSecondaryContainer
            selectedTextColor: Appearance.colors.colOnSecondaryContainer
            leftPadding: 14
            rightPadding: 44
            topPadding: 10
            bottomPadding: 10
            font {
                family: Appearance.font.family.main
                pixelSize: Appearance.font.pixelSize.small
            }
            background: Rectangle {
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: field.hovered && !field.activeFocus ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
                border.width: field.activeFocus ? 2 : 0
                border.color: root.errorText.length > 0 ? Appearance.colors.colError : Appearance.colors.colPrimary
            }
            Keys.onReturnPressed: root.submit()
            Keys.onEnterPressed: root.submit()
            Keys.onEscapePressed: root.canceled()

            RippleButton {
                id: revealButton
                anchors {
                    right: parent.right
                    rightMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                implicitWidth: 34
                implicitHeight: 34
                buttonRadius: Appearance.rounding.full
                onClicked: toggled = !toggled
                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    text: revealButton.toggled ? "visibility_off" : "visibility"
                    iconSize: 20
                    color: Appearance.colors.colSubtext
                }
                colBackgroundToggled: "transparent"
                colBackgroundToggledHover: Appearance.colors.colLayer3Hover
                StyledToolTip {
                    text: revealButton.toggled ? Translation.tr("Hide password") : Translation.tr("Show password")
                }
            }
        }

        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.canceled()
        }
        DialogButton {
            buttonText: root.acceptText
            enabled: (field.text.length > 0 || root.allowEmpty) && !root.busy
            colBackground: Appearance.colors.colPrimary
            colBackgroundHover: Appearance.colors.colPrimaryHover
            colRipple: Appearance.colors.colPrimaryActive
            colEnabled: Appearance.colors.colOnPrimary
            onClicked: root.submit()
        }
    }

    StyledText {
        visible: root.errorText.length > 0
        Layout.fillWidth: true
        text: root.errorText
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colError
    }
}
