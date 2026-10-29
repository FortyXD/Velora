pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.onboarding.pages
import QtQuick
import QtQuick.Layouts

/**
 * The setup assistant on screen: the live desktop blurred behind (rules.lua blurs this layer), the
 * greeting, then a sheet that grows out of the "Start" button and holds one step at a time.
 */
Item {
    id: root
    required property var flow
    signal closed(bool tour)

    // The sheet: centered, at most this large
    readonly property real sheetWidth: Math.min(1100, root.width - 96)
    readonly property real sheetHeight: Math.min(760, root.height - 96)
    readonly property bool onSheet: root.flow.step !== "hello"
    function focusPage() {
        if (passwordDialog.open) passwordDialog.focusField();
        else (root.page?.focusTarget ?? sheet).forceActiveFocus();
    }

    // Leaving: everything drifts toward you and fades, the blur goes, then the desktop is yours
    property bool leaving: false
    function leave(tour) {
        root.leaving = true;
        leaveTimer.tour = tour;
        leaveTimer.start();
    }
    Timer {
        id: leaveTimer
        property bool tour: false
        interval: Motion.ms(460)
        onTriggered: root.closed(tour)
    }
    Connections {
        target: root.flow
        function onFinished(tour) { root.leave(tour); }
    }

    // Tint over the blurred desktop, breathing slowly
    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0
        property real breath: 0
        opacity: root.leaving ? 0 : 0.64 + breath * 0.06
        Behavior on opacity {
            NumberAnimation { duration: Motion.ms(460) }
        }
        SequentialAnimation on breath {
            running: !Motion.reduced
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: 5200; easing.type: Easing.InOutSine }
            NumberAnimation { to: 0; duration: 5200; easing.type: Easing.InOutSine }
        }
    }

    Item {
        id: stage
        anchors.fill: parent
        opacity: root.leaving ? 0 : 1
        scale: root.leaving && !Motion.reduced ? 1.03 : 1
        Behavior on opacity {
            NumberAnimation { duration: Motion.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.accelerate }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.ms(460); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.accelerate }
        }

        HelloPage {
            id: hello
            anchors.fill: parent
            flow: root.flow
            opacity: root.onSheet ? 0 : 1
            scale: root.onSheet && !Motion.reduced ? 0.94 : 1
            visible: opacity > 0
            enabled: !root.onSheet
            Behavior on opacity {
                NumberAnimation { duration: Motion.ms(320) }
            }
            Behavior on scale {
                NumberAnimation { duration: Motion.ms(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.decelerate }
            }
            onStarted: root.flow.next()
        }

        StyledRectangularShadow {
            target: sheet
            visible: sheet.visible
        }
        // Grows out of the "Start" button: from its place and shape to the sheet
        Rectangle {
            id: sheet
            visible: opacity > 0
            opacity: 0
            color: Appearance.colors.colLayer0
            border.width: 1
            border.color: Appearance.colors.colLayer0Border
            clip: true
            x: (root.width - root.sheetWidth) / 2
            y: (root.height - root.sheetHeight) / 2
            width: root.sheetWidth
            height: root.sheetHeight
            radius: Appearance.rounding.verylarge

            function grow() {
                const button = hello.startButton.mapToItem(root, 0, 0, hello.startButton.width, hello.startButton.height);
                growAnimation.stop();
                sheet.x = button.x;
                sheet.y = button.y;
                sheet.width = button.width;
                sheet.height = button.height;
                sheet.radius = button.height / 2;
                growAnimation.start();
            }
            ParallelAnimation {
                id: growAnimation
                NumberAnimation { target: sheet; property: "opacity"; to: 1; duration: Motion.ms(180) }
                NumberAnimation { target: sheet; property: "x"; to: (root.width - root.sheetWidth) / 2; duration: Motion.ms(640); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
                NumberAnimation { target: sheet; property: "y"; to: (root.height - root.sheetHeight) / 2; duration: Motion.ms(640); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
                NumberAnimation { target: sheet; property: "width"; to: root.sheetWidth; duration: Motion.ms(640); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
                NumberAnimation { target: sheet; property: "height"; to: root.sheetHeight; duration: Motion.ms(640); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
                NumberAnimation { target: sheet; property: "radius"; to: Appearance.rounding.verylarge; duration: Motion.ms(640); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
            }
            NumberAnimation {
                id: shrink
                target: sheet
                property: "opacity"
                to: 0
                duration: Motion.ms(240)
            }

            focus: root.onSheet
            Keys.onPressed: event => {
                if (passwordDialog.open) {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) passwordDialog.submit();
                    else if (event.key === Qt.Key_Escape) passwordDialog.cancel();
                    else passwordDialog.focusField();
                    event.accepted = true;
                    return;
                }
                const typing = root.page?.focusTarget ?? null;
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !root.flow.last) root.flow.next();
                else if (event.key === Qt.Key_Escape) root.flow.back();
                else if (typing && !typing.activeFocus && event.text.length > 0 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                    // Typed while a click had taken the keyboard elsewhere: it still goes where typing goes
                    typing.forceActiveFocus();
                    if (event.text.charCodeAt(0) >= 32) typing.insert(typing.cursorPosition, event.text);
                } else return;
                event.accepted = true;
            }

            // Everything inside appears once the sheet has its size
            Item {
                id: inside
                enabled: !passwordDialog.open
                width: root.sheetWidth
                height: root.sheetHeight
                opacity: sheet.width > root.sheetWidth * 0.9 ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Motion.ms(200) }
                }

                StepIndicator {
                    id: indicator
                    anchors.top: parent.top
                    anchors.topMargin: 18
                    anchors.horizontalCenter: parent.horizontalCenter
                    flow: root.flow
                }

                Item {
                    id: pageHost
                    anchors {
                        top: indicator.bottom
                        bottom: nav.top
                        left: parent.left
                        right: parent.right
                        topMargin: 22
                        bottomMargin: 12
                        leftMargin: 56
                        rightMargin: 56
                    }
                    clip: true
                }

                RowLayout {
                    id: nav
                    anchors {
                        bottom: parent.bottom
                        left: parent.left
                        right: parent.right
                        margins: 22
                        leftMargin: 32
                        rightMargin: 32
                    }
                    spacing: 10

                    AccessibilityButton {
                        flow: root.flow
                    }
                    Item { Layout.fillWidth: true }
                    RippleButton {
                        visible: !root.flow.first
                        enabled: !root.flow.navigationLocked
                        focusPolicy: Qt.NoFocus
                        implicitHeight: 44
                        implicitWidth: backText.implicitWidth + 36
                        buttonRadius: height / 2
                        onClicked: root.flow.back()
                        contentItem: StyledText {
                            id: backText
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("Back")
                        }
                    }
                    RippleButton {
                        visible: !root.flow.last
                        enabled: !root.flow.navigationLocked
                        focusPolicy: Qt.NoFocus
                        opacity: enabled ? 1 : 0.5
                        implicitHeight: 44
                        implicitWidth: nextText.implicitWidth + 44
                        buttonRadius: height / 2
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: root.flow.next()
                        contentItem: StyledText {
                            id: nextText
                            horizontalAlignment: Text.AlignHCenter
                            text: (root.flow.step === "network" && !(Network.wifi || Network.ethernet))
                                || (root.flow.step === "install" && !["done", "failed"].includes(root.flow.installState) && root.flow.installItems.length > 0)
                                ? Translation.tr("Skip") : Translation.tr("Next")
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }
                }
            }

            // Before the extras are installed
            PasswordDialog {
                id: passwordDialog
                anchors.fill: parent
                radius: sheet.radius
                flow: root.flow
                onOpenChanged: Qt.callLater(root.focusPage)
            }
        }
    }

    // One page at a time: the new one comes in from the side it was reached from, the old one leaves
    readonly property var pageComponents: ({
        "language": languagePage, "display": displayPage, "network": networkPage, "layout": layoutPage,
        "appearance": appearancePage, "extras": extrasPage, "install": installPage, "done": donePage,
    })
    Component { id: languagePage; LanguagePage {} }
    Component { id: displayPage; DisplayPage {} }
    Component { id: networkPage; NetworkPage {} }
    Component { id: layoutPage; LayoutPage {} }
    Component { id: appearancePage; AppearancePage {} }
    Component { id: extrasPage; ExtrasPage {} }
    Component { id: installPage; InstallPage {} }
    Component { id: donePage; DonePage {} }

    property Item page: null
    property string shownStep: "hello"
    function showStep() {
        const step = root.flow.step;
        if (step === root.shownStep) return;
        const wasHello = root.shownStep === "hello";
        root.shownStep = step;
        root.page?.leave(root.flow.direction);
        root.page = null;
        if (step === "hello") {
            shrink.start();
            return;
        }
        if (wasHello) sheet.grow();
        const component = root.pageComponents[step];
        if (!component) return;
        root.page = component.createObject(pageHost, {
            "flow": root.flow,
            "fromSide": root.flow.direction,
            "width": Qt.binding(() => pageHost.width),
            "height": Qt.binding(() => pageHost.height),
        });
        // After the sheet's own focus binding has settled
        Qt.callLater(root.focusPage);
    }
    Connections {
        target: root.flow
        function onStepChanged() { root.showStep(); }
        function onLoadedChanged() { root.showStep(); }
    }
}
