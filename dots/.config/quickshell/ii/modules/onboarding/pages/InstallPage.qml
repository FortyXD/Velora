pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.onboarding
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Installing the extras, right in the assistant. Arriving here asks for the password (the dialog is
 * the view's, over the whole sheet); then a shape morphs while the packages come in, each item says
 * where it is, and the tools' latest line runs underneath. Done: a check pops in. Failed: what went
 * wrong, the tools' output, and another try.
 */
PageScaffold {
    id: root
    readonly property string installState: root.flow.installState
    readonly property bool working: ["checking", "running"].includes(root.installState)
    // What's shown: what is being (or was) installed, else what would be
    readonly property var items: root.installState === "idle" || root.installState === "password" || root.installState === "wrongPassword"
        ? root.flow.installItems : root.flow.installing
    readonly property bool nothingLeft: root.flow.extrasReady && root.installState === "idle" && root.items.length === 0

    title: root.installState === "done" ? Translation.tr("Installed")
        : root.installState === "failed" ? Translation.tr("Couldn't install everything")
        : root.working ? Translation.tr("Installing")
        : root.nothingLeft ? Translation.tr("Everything is here already")
        : Translation.tr("Ready to install")
    subtitle: root.installState === "done" ? Translation.tr("Everything you picked is on your computer now.")
        : root.installState === "failed" ? root.flow.installError
        : root.installState === "checking" ? Translation.tr("Checking the password…")
        : root.installState === "running" ? Translation.tr("This can take a few minutes. You can't leave this step until it's done.")
        : root.nothingLeft ? Translation.tr("Nothing more to install.")
        : Translation.tr("Velora needs your password to install system packages.")

    // Arriving asks for the password at once
    function askWhenReady() {
        if (root.flow.step === "install" && root.installState === "idle" && root.flow.extrasReady && root.flow.installItems.length > 0) root.flow.askPassword();
    }
    Component.onCompleted: Qt.callLater(root.askWhenReady)
    Connections {
        target: root.flow
        function onExtrasReadyChanged() { root.askWhenReady(); }
    }

    readonly property var phases: ["password", "repo", "aur", "record"]
    function itemState(item) {
        if (root.installState === "done") return "done";
        if (!["checking", "running", "failed"].includes(root.installState)) return "waiting";
        const current = root.phases.indexOf(root.flow.installPhase);
        const own = [...(item.repo.length > 0 ? ["repo"] : []), ...(item.aur.length > 0 ? ["aur"] : [])].map(phase => root.phases.indexOf(phase));
        if (own.every(phase => phase < current)) return "done";
        if (own.includes(current)) return root.installState === "failed" ? "failed" : "installing";
        return "waiting";
    }
    readonly property string phaseText: ({
        "password": Translation.tr("Checking the password"),
        "repo": Translation.tr("Downloading and installing packages"),
        "aur": Translation.tr("Building packages from the AUR"),
        "record": Translation.tr("Finishing"),
    })[root.flow.installPhase] ?? ""
    property bool showLog: false

    Reveal {
        order: 1
        RowLayout {
            width: parent.width
            height: root.areaHeight
            spacing: 36

            // The picture of it: shapes morphing while it works, a check or a warning at the end
            Item {
                Layout.preferredWidth: 220
                Layout.fillHeight: true

                Item {
                    id: hero
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Math.max(0, (parent.height - height) / 2 - 30)
                    width: 168
                    height: 168

                    MaterialLoadingIndicator {
                        anchors.centerIn: parent
                        implicitSize: 168
                        loading: root.working
                        opacity: root.working ? 1 : 0
                        scale: root.working ? 1 : 0.6
                        visible: opacity > 0
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.ms(260) }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: Motion.ms(420); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial }
                        }
                    }
                    MaterialShapeWrappedMaterialSymbol {
                        anchors.centerIn: parent
                        readonly property bool shown: !root.working
                        shape: root.installState === "done" ? MaterialShape.Shape.Cookie9Sided
                            : root.installState === "failed" ? MaterialShape.Shape.Pentagon : MaterialShape.Shape.Cookie4Sided
                        implicitSize: 150
                        text: root.installState === "done" || root.nothingLeft ? "check" : root.installState === "failed" ? "priority_high" : "download"
                        iconSize: 64
                        color: root.installState === "failed" ? Appearance.colors.colErrorContainer
                            : root.installState === "done" ? Appearance.colors.colPrimary : Appearance.colors.colPrimaryContainer
                        colSymbol: root.installState === "failed" ? Appearance.colors.colOnErrorContainer
                            : root.installState === "done" ? Appearance.colors.colOnPrimary : Appearance.colors.colOnPrimaryContainer
                        opacity: shown ? 1 : 0
                        scale: shown ? 1 : 0.4
                        rotation: shown ? 0 : -90
                        visible: opacity > 0
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.ms(220) }
                        }
                        Behavior on scale {
                            NumberAnimation { duration: Motion.ms(520); easing.type: Easing.OutBack; easing.overshoot: 2.2 }
                        }
                        Behavior on rotation {
                            NumberAnimation { duration: Motion.ms(520); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spatial }
                        }
                    }
                }

                ColumnLayout {
                    anchors.top: hero.bottom
                    anchors.topMargin: 24
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    spacing: 12
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.working
                        horizontalAlignment: Text.AlignHCenter
                        text: root.phaseText
                        wrapMode: Text.Wrap
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledIndeterminateProgressBar {
                        Layout.fillWidth: true
                        visible: root.working
                    }
                    // Asked again after closing the password dialog, or after a failure
                    RippleButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: ["idle", "failed"].includes(root.installState) && root.flow.installItems.length > 0
                        focusPolicy: Qt.NoFocus
                        implicitHeight: 44
                        implicitWidth: againRow.implicitWidth + 40
                        buttonRadius: height / 2
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: root.flow.askPassword()
                        contentItem: RowLayout {
                            id: againRow
                            spacing: 8
                            MaterialSymbol {
                                Layout.leftMargin: 20
                                text: root.installState === "failed" ? "refresh" : "download"
                                iconSize: 20
                                color: Appearance.colors.colOnPrimary
                            }
                            StyledText {
                                Layout.rightMargin: 20
                                text: root.installState === "failed" ? Translation.tr("Try again") : Translation.tr("Install")
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }
                }
            }

            // What's being installed, each with where it is
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 8

                StyledFlickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: itemList.implicitHeight
                    interactive: contentHeight > height
                    clip: true
                    ColumnLayout {
                        id: itemList
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: root.items
                            delegate: Rectangle {
                                id: entry
                                required property var modelData
                                required property int index
                                readonly property string itemState: root.itemState(entry.modelData)
                                readonly property var app: entry.modelData.kind === "app" ? root.flow.apps.find(app => app.package === entry.modelData.id) : null
                                Layout.fillWidth: true
                                implicitHeight: 56
                                radius: Appearance.rounding.normal
                                color: entry.itemState === "installing" ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                                    : entry.itemState === "failed" ? ColorUtils.transparentize(Appearance.colors.colError, 0.88) : Appearance.colors.colLayer1
                                border.width: entry.itemState === "installing" ? 2 : 1
                                border.color: entry.itemState === "installing" ? Appearance.colors.colPrimary
                                    : entry.itemState === "failed" ? Appearance.colors.colError : Appearance.colors.colOutlineVariant
                                Behavior on color {
                                    ColorAnimation { duration: Motion.ms(240) }
                                }
                                // Comes in one after another
                                opacity: 0
                                Component.onCompleted: entryIn.start()
                                NumberAnimation on opacity {
                                    id: entryIn
                                    running: false
                                    to: 1
                                    duration: Motion.ms(280)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 12
                                    Item {
                                        implicitWidth: 32
                                        implicitHeight: 32
                                        Image {
                                            anchors.fill: parent
                                            visible: entry.app !== null
                                            source: entry.app ? Quickshell.iconPath(entry.app.icon, "application-x-executable") : ""
                                            sourceSize.width: 64
                                            sourceSize.height: 64
                                        }
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            visible: entry.app === null
                                            text: root.flow.componentInfo[entry.modelData.id]?.[2] ?? "extension"
                                            iconSize: 26
                                            color: Appearance.colors.colPrimary
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.flow.itemName(entry.modelData)
                                            elide: Text.ElideRight
                                            font.weight: Font.DemiBold
                                            color: Appearance.colors.colOnLayer1
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: [...entry.modelData.repo, ...entry.modelData.aur].join(", ")
                                            elide: Text.ElideRight
                                            font.family: Appearance.font.family.monospace
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                    // Where it is
                                    Item {
                                        implicitWidth: 28
                                        implicitHeight: 28
                                        MaterialLoadingIndicator {
                                            anchors.centerIn: parent
                                            implicitSize: 28
                                            visible: entry.itemState === "installing"
                                            loading: visible
                                        }
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            visible: entry.itemState !== "installing"
                                            text: entry.itemState === "done" ? "check_circle" : entry.itemState === "failed" ? "error" : "schedule"
                                            fill: entry.itemState === "waiting" ? 0 : 1
                                            iconSize: 24
                                            color: entry.itemState === "done" ? Appearance.colors.colPrimary
                                                : entry.itemState === "failed" ? Appearance.colors.colError : Appearance.colors.colSubtext
                                            scale: visible ? 1 : 0
                                            Behavior on scale {
                                                NumberAnimation { duration: Motion.ms(360); easing.type: Easing.OutBack; easing.overshoot: 2 }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // The tools' latest line, or all of them
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    visible: root.flow.installLog.length > 0
                    implicitHeight: root.showLog ? 200 : 40
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    clip: true
                    Behavior on implicitHeight {
                        NumberAnimation { duration: Motion.ms(260); easing.type: Easing.OutCubic }
                    }
                    StyledText {
                        visible: !root.showLog
                        anchors.left: parent.left
                        anchors.right: logButton.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        text: root.flow.installLine
                        elide: Text.ElideRight
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                    StyledFlickable {
                        id: logView
                        visible: root.showLog
                        anchors.fill: parent
                        anchors.margins: 12
                        anchors.rightMargin: 44
                        contentHeight: logText.implicitHeight
                        clip: true
                        onContentHeightChanged: contentY = Math.max(0, contentHeight - height)
                        StyledText {
                            id: logText
                            width: logView.width
                            text: root.flow.installLog.join("\n")
                            wrapMode: Text.WrapAnywhere
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                    RippleButton {
                        id: logButton
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 4
                        focusPolicy: Qt.NoFocus
                        implicitWidth: 32
                        implicitHeight: 32
                        buttonRadius: 16
                        onClicked: root.showLog = !root.showLog
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: root.showLog ? "unfold_less" : "unfold_more"
                            iconSize: 20
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }
}
