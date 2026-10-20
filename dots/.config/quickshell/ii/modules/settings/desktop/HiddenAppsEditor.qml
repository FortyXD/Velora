import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Apps the dock leaves out even while they run (dock.ignoredAppRegexes): pick one of the running
 * apps or type a pattern. Empty and broken patterns are refused, since they would hide everything.
 */
ColumnLayout {
    id: root
    readonly property var patterns: Config.options.dock.ignoredAppRegexes ?? []
    property string error: ""

    readonly property bool settingsSearchable: true
    property string searchText: `${Translation.tr("Hidden from the dock")} ${Translation.tr("Pattern")}`

    Layout.fillWidth: true
    Layout.margins: 12
    spacing: 8

    function escapePattern(text) {
        return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }

    function add(pattern) {
        const trimmed = pattern.trim();
        if (trimmed.length === 0) {
            root.error = Translation.tr("An empty pattern would hide every app");
            return false;
        }
        try {
            new RegExp(trimmed, "i");
        } catch (e) {
            root.error = Translation.tr("This isn't a valid pattern");
            return false;
        }
        root.error = "";
        if (!root.patterns.includes(trimmed)) Config.options.dock.ignoredAppRegexes = root.patterns.concat([trimmed]);
        return true;
    }

    function remove(pattern) {
        Config.options.dock.ignoredAppRegexes = root.patterns.filter(item => item !== pattern);
    }

    // Running apps that aren't hidden yet
    readonly property var runningApps: {
        let ids = [];
        for (const toplevel of ToplevelManager.toplevels.values) {
            const id = toplevel.appId;
            if (!id || ids.includes(id)) continue;
            if (root.patterns.some(pattern => {
                try {
                    return new RegExp(pattern, "i").test(id);
                } catch (e) {
                    return false;
                }
            })) continue;
            ids.push(id);
        }
        return ids.sort();
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6
        visible: root.patterns.length > 0

        Repeater {
            model: root.patterns
            delegate: Rectangle {
                id: chip
                required property string modelData
                implicitWidth: chipRow.implicitWidth + 16
                implicitHeight: 32
                radius: height / 2
                color: Appearance.colors.colSecondaryContainer
                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 4
                    StyledText {
                        Layout.leftMargin: 4
                        text: chip.modelData
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                    RippleButton {
                        implicitWidth: 22
                        implicitHeight: 22
                        buttonRadius: Appearance.rounding.full
                        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                        onClicked: root.remove(chip.modelData)
                        contentItem: MaterialSymbol {
                            horizontalAlignment: Text.AlignHCenter
                            text: "close"
                            iconSize: 15
                            color: Appearance.colors.colOnSecondaryContainer
                        }
                    }
                }
            }
        }
    }

    StyledText {
        visible: root.patterns.length === 0
        text: Translation.tr("Every running app shows in the dock.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6
        TextField {
            id: patternField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Pattern, like ^steam$")
            placeholderTextColor: Appearance.colors.colSubtext
            color: Appearance.colors.colOnLayer3
            leftPadding: 14
            topPadding: 9
            bottomPadding: 9
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.small
            background: Rectangle {
                implicitHeight: 38
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
                border.width: patternField.activeFocus ? 2 : 0
                border.color: root.error.length > 0 ? Appearance.colors.colError : Appearance.colors.colPrimary
            }
            onAccepted: if (root.add(text)) text = ""
        }
        DialogButton {
            buttonText: Translation.tr("Hide")
            onClicked: if (root.add(patternField.text)) patternField.text = ""
        }
    }

    // Running apps, one click to hide
    Flow {
        Layout.fillWidth: true
        visible: root.runningApps.length > 0
        spacing: 6
        StyledText {
            height: 30
            verticalAlignment: Text.AlignVCenter
            text: Translation.tr("Running now:")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        Repeater {
            model: root.runningApps
            delegate: RippleButton {
                id: suggestion
                required property string modelData
                implicitHeight: 30
                implicitWidth: suggestionRow.implicitWidth + 20
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer3
                colBackgroundHover: Appearance.colors.colLayer3Hover
                onClicked: root.add(`^${root.escapePattern(suggestion.modelData)}$`)
                contentItem: RowLayout {
                    id: suggestionRow
                    spacing: 6
                    IconImage {
                        implicitSize: 18
                        source: Quickshell.iconPath(TaskbarApps.iconFor(suggestion.modelData), "image-missing")
                    }
                    StyledText {
                        text: TaskbarApps.displayName(suggestion.modelData)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Hide %1 from the dock").arg(suggestion.modelData)
                }
            }
        }
    }

    StyledText {
        visible: root.error.length > 0
        text: root.error
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colError
    }
}
