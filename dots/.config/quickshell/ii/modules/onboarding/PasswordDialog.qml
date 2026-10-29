pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Asks for the password before the extras are installed: over the whole sheet, dimming it. The
 * password goes to the flow, which checks it; a wrong one shakes the field and asks again. Shows the
 * keyboard layout you type in, since a password in the wrong one is the usual reason it's wrong.
 */
FocusScope {
    id: root
    required property var flow
    property real radius: 0 // The sheet's, so the dimming keeps its corners
    readonly property bool open: ["password", "checking", "wrongPassword"].includes(root.flow.installState)
    readonly property bool checking: root.flow.installState === "checking"
    visible: root.open || scrim.opacity > 0
    enabled: root.open
    focus: root.open

    function focusField() {
        if (root.open && !root.checking) field.forceActiveFocus();
    }
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.submit();
        else if (event.key === Qt.Key_Escape) root.cancel();
        event.accepted = true;
    }

    function submit() {
        if (root.checking || field.text.length === 0) return;
        root.flow.install(field.text);
        field.clear();
    }
    function cancel() {
        if (root.checking) return;
        field.clear();
        root.flow.cancelPassword();
    }
    onOpenChanged: {
        if (!root.open) {
            field.clear();
            return;
        }
        field.clear();
        Qt.callLater(root.focusField);
    }
    Connections {
        target: root.flow
        function onInstallStateChanged() {
            if (root.flow.installState !== "wrongPassword") return;
            field.clear();
            shake.restart();
            field.forceActiveFocus();
        }
    }

    Rectangle {
        id: scrim
        anchors.fill: parent
        radius: root.radius
        color: Appearance.colors.colScrim
        opacity: root.open ? 0.6 : 0
        Behavior on opacity {
            NumberAnimation { duration: Motion.ms(260) }
        }
    }
    // The sheet under it waits
    MouseArea {
        anchors.fill: parent
        enabled: root.open
        onClicked: field.forceActiveFocus()
    }

    StyledRectangularShadow {
        target: card
    }
    Rectangle {
        id: card
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.open ? 0 : Motion.travel(40)
        width: 440
        height: column.implicitHeight + 56
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer1
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.92
        Behavior on opacity {
            NumberAnimation { duration: Motion.ms(220) }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.ms(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial }
        }
        Behavior on anchors.verticalCenterOffset {
            NumberAnimation { duration: Motion.ms(380); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.decelerate }
        }

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 28
            spacing: 14

            // A lock, morphing while the password is checked
            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 72
                implicitHeight: 72
                MaterialShapeWrappedMaterialSymbol {
                    anchors.centerIn: parent
                    visible: !root.checking
                    shape: MaterialShape.Shape.Cookie7Sided
                    implicitSize: 72
                    text: "lock"
                    iconSize: 32
                    color: root.flow.installState === "wrongPassword" ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                    colSymbol: root.flow.installState === "wrongPassword" ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                }
                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.checking
                    implicitSize: 72
                    loading: visible
                }
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Enter your password")
                font.family: Appearance.font.family.title
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: Translation.tr("To install %1, Velora needs administrator rights.")
                    .arg(root.flow.installItems.map(item => root.flow.itemName(item)).join(", "))
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            Rectangle {
                id: fieldBox
                Layout.fillWidth: true
                Layout.topMargin: 6
                implicitHeight: 52
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer2
                border.width: 2
                border.color: root.flow.installState === "wrongPassword" ? Appearance.colors.colError
                    : field.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                Behavior on border.color {
                    ColorAnimation { duration: Motion.ms(160) }
                }
                ErrorShakeAnimation {
                    id: shake
                    target: fieldBox
                    distance: 14
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 8
                    spacing: 8
                    TextInput {
                        id: field
                        Layout.fillWidth: true
                        enabled: !root.checking
                        echoMode: reveal.toggled ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        color: Appearance.colors.colOnLayer2
                        selectionColor: Appearance.colors.colSecondaryContainer
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.large
                        clip: true
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.submit();
                            else if (event.key === Qt.Key_Escape) root.cancel();
                            else return;
                            event.accepted = true;
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: field.text.length === 0
                            text: Translation.tr("Password")
                            color: Appearance.colors.colSubtext
                        }
                    }
                    // The layout it's typed in
                    Rectangle {
                        implicitWidth: Math.max(36, layoutText.implicitWidth + 14)
                        implicitHeight: 26
                        radius: 13
                        visible: HyprlandXkb.currentLayoutCode.length > 0
                        color: Appearance.colors.colSecondaryContainer
                        StyledText {
                            id: layoutText
                            anchors.centerIn: parent
                            text: HyprlandXkb.currentLayoutCode.slice(0, 3).toUpperCase()
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                    RippleButton {
                        id: reveal
                        focusPolicy: Qt.NoFocus
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: 18
                        toggled: false
                        colBackgroundToggled: Appearance.colors.colSecondaryContainer
                        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: {
                            reveal.toggled = !reveal.toggled;
                            field.forceActiveFocus();
                        }
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: reveal.toggled ? "visibility_off" : "visibility"
                            iconSize: 20
                            color: reveal.toggled ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                        }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.flow.installState === "wrongPassword"
                text: Translation.tr("Wrong password. Check the keyboard layout and try again.")
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colError
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 10
                Item {
                    Layout.fillWidth: true
                }
                RippleButton {
                    enabled: !root.checking
                    focusPolicy: Qt.NoFocus
                    implicitHeight: 44
                    implicitWidth: cancelText.implicitWidth + 36
                    buttonRadius: height / 2
                    onClicked: root.cancel()
                    contentItem: StyledText {
                        id: cancelText
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Cancel")
                    }
                }
                RippleButton {
                    enabled: !root.checking && field.text.length > 0
                    opacity: enabled || root.checking ? 1 : 0.5
                    focusPolicy: Qt.NoFocus
                    implicitHeight: 44
                    implicitWidth: installRow.implicitWidth + 44
                    buttonRadius: height / 2
                    colBackground: Appearance.colors.colPrimary
                    colBackgroundHover: Appearance.colors.colPrimaryHover
                    colRipple: Appearance.colors.colPrimaryActive
                    onClicked: root.submit()
                    contentItem: RowLayout {
                        id: installRow
                        spacing: 8
                        MaterialSymbol {
                            Layout.leftMargin: 22
                            text: "download"
                            iconSize: 20
                            color: Appearance.colors.colOnPrimary
                        }
                        StyledText {
                            Layout.rightMargin: 22
                            text: root.checking ? Translation.tr("Checking…") : Translation.tr("Install")
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }
        }
    }
}
