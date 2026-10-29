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
 * Extras: Velora's optional parts and a few popular apps (loaded by the flow). Every card says exactly
 * what it brings — the packages themselves — and whether it's there already; a switch adds it. The line
 * at the bottom sums up what the next step installs, after asking for your password.
 */
PageScaffold {
    id: root
    title: Translation.tr("Anything else?")
    subtitle: Translation.tr("Nothing is picked: skip this if you don't need more.")
    scrollable: true

    readonly property var components: root.flow.components.filter(item => root.componentInfo[item.id])
    readonly property var apps: root.flow.apps
    readonly property var missingApps: root.flow.missingApps
    readonly property bool appsChecked: root.flow.appsChecked

    readonly property var componentInfo: root.flow.componentInfo
    readonly property var chosenComponents: root.flow.choices.components ?? []
    readonly property var chosenApps: root.flow.choices.apps ?? []
    // What the next step installs: picked and still missing
    readonly property var summary: root.flow.installItems.map(item => root.flow.itemName(item))

    function toggle(key, value) {
        const list = root.flow.choices[key] ?? [];
        root.flow.choose(key, list.includes(value) ? list.filter(item => item !== value) : [...list, value]);
    }

    component Section: StyledText {
        font.pixelSize: Appearance.font.pixelSize.larger
        font.weight: Font.DemiBold
        color: Appearance.colors.colOnLayer0
    }
    // Installed already: a quiet badge instead of a switch
    component InstalledBadge: Rectangle {
        implicitWidth: badgeRow.implicitWidth + 16
        implicitHeight: 26
        radius: 13
        color: Appearance.colors.colSecondaryContainer
        RowLayout {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 4
            MaterialSymbol {
                text: "check"
                iconSize: 14
                color: Appearance.colors.colOnSecondaryContainer
            }
            StyledText {
                text: Translation.tr("Installed")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    Reveal {
        order: 1
        Section {
            text: Translation.tr("Parts of Velora")
        }
    }
    Reveal {
        order: 2
        visible: !root.flow.componentsLoaded
        StyledIndeterminateProgressBar {
            width: parent.width
        }
    }

    Repeater {
        model: root.components
        delegate: Reveal {
            id: part
            required property var modelData
            required property int index
            order: 3 + index
            readonly property var info: root.componentInfo[part.modelData.id]
            readonly property bool chosen: root.chosenComponents.includes(part.modelData.id)
            readonly property var missing: part.modelData.missingNames ?? []

            Rectangle {
                width: parent.width
                implicitHeight: partColumn.implicitHeight + 28
                radius: Appearance.rounding.normal
                color: part.chosen ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88) : Appearance.colors.colLayer1
                border.width: part.chosen ? 2 : 1
                border.color: part.chosen ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                Behavior on color { ColorAnimation { duration: Motion.ms(200) } }

                MouseArea {
                    anchors.fill: parent
                    enabled: !part.modelData.installed
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggle("components", part.modelData.id)
                }

                ColumnLayout {
                    id: partColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14
                        MaterialSymbol {
                            text: part.info[2]
                            iconSize: 28
                            color: Appearance.colors.colPrimary
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            StyledText {
                                text: part.info[0]
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: part.modelData.installed ? part.info[1]
                                    : part.missing.length < part.modelData.packages
                                        ? Translation.tr("%1 — %2 of %3 packages are missing").arg(part.info[1]).arg(part.missing.length).arg(part.modelData.packages)
                                        : part.info[1]
                                wrapMode: Text.Wrap
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                        InstalledBadge {
                            visible: part.modelData.installed
                        }
                        StyledSwitch {
                            visible: !part.modelData.installed
                            checked: part.chosen
                            onClicked: root.toggle("components", part.modelData.id)
                        }
                    }
                    // What it brings, by name; what's missing is highlighted
                    Flow {
                        Layout.fillWidth: true
                        Layout.leftMargin: 42
                        spacing: 6
                        Repeater {
                            model: (part.modelData.packageNames ?? []).slice(0, 10)
                            delegate: Rectangle {
                                id: chip
                                required property string modelData
                                readonly property bool lacking: part.missing.includes(chip.modelData)
                                implicitHeight: 24
                                implicitWidth: chipText.implicitWidth + 16
                                radius: 12
                                color: chip.lacking ? Appearance.colors.colTertiaryContainer : Appearance.colors.colLayer2
                                StyledText {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: chip.modelData
                                    font.family: Appearance.font.family.monospace
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: chip.lacking ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colSubtext
                                }
                            }
                        }
                        StyledText {
                            visible: (part.modelData.packageNames ?? []).length > 10
                            text: Translation.tr("and %1 more").arg((part.modelData.packageNames ?? []).length - 10)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    Reveal {
        order: 8
        Section {
            text: Translation.tr("Popular apps")
        }
    }
    Reveal {
        order: 9
        GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: 12
            rowSpacing: 12
            Repeater {
                model: root.apps
                delegate: Rectangle {
                    id: app
                    required property var modelData
                    readonly property bool installed: root.appsChecked && !root.missingApps.includes(app.modelData.package)
                    readonly property bool chosen: root.chosenApps.includes(app.modelData.package)
                    Layout.fillWidth: true
                    implicitHeight: 72
                    radius: Appearance.rounding.normal
                    color: app.chosen ? ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88) : Appearance.colors.colLayer1
                    border.width: app.chosen ? 2 : 1
                    border.color: app.chosen ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                    Behavior on color { ColorAnimation { duration: Motion.ms(200) } }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !app.installed
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggle("apps", app.modelData.package)
                    }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12
                        Image {
                            Layout.preferredWidth: 36
                            Layout.preferredHeight: 36
                            source: Quickshell.iconPath(app.modelData.icon, "application-x-executable")
                            sourceSize.width: 72
                            sourceSize.height: 72
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: app.modelData.name
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr(app.modelData.description)
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }
                        }
                        InstalledBadge {
                            visible: app.installed
                        }
                        StyledSwitch {
                            visible: !app.installed
                            checked: app.chosen
                            onClicked: root.toggle("apps", app.modelData.package)
                        }
                    }
                }
            }
        }
    }

    // The sum of it
    Reveal {
        order: 10
        Rectangle {
            width: parent.width
            implicitHeight: summaryRow.implicitHeight + 24
            radius: Appearance.rounding.normal
            color: root.summary.length > 0 ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
            Behavior on color { ColorAnimation { duration: Motion.ms(200) } }
            RowLayout {
                id: summaryRow
                anchors.fill: parent
                anchors.margins: 12
                anchors.leftMargin: 16
                spacing: 12
                MaterialSymbol {
                    text: root.summary.length > 0 ? "download" : "check"
                    iconSize: 24
                    color: root.summary.length > 0 ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.summary.length > 0
                        ? Translation.tr("Installed on the next step: %1. It asks for your password first.").arg(root.summary.join(", "))
                        : Translation.tr("Nothing will be installed.")
                    color: root.summary.length > 0 ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
                }
            }
        }
    }
}
