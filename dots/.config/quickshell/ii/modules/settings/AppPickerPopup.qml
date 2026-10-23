import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * A searchable list of installed apps in a popup; emits picked(entry) with the desktop entry.
 */
Popup {
    id: root
    parent: Overlay.overlay
    modal: true
    anchors.centerIn: parent
    width: Math.min(440, (parent?.width ?? 440) - 40)
    height: Math.min(520, (parent?.height ?? 520) - 40)
    padding: 14
    onOpened: {
        searchField.text = "";
        searchField.forceActiveFocus();
    }

    property string title: ""
    property list<string> excludedIds: [] // Apps not to offer, e.g. the ones already added
    signal picked(var entry)

    readonly property var apps: {
        const query = searchField.text.trim().toLowerCase();
        const excluded = root.excludedIds.map(id => id.toLowerCase());
        return DesktopEntries.applications.values
            .filter(entry => !entry.noDisplay && !excluded.includes(entry.id.toLowerCase()))
            .filter(entry => query.length === 0 || entry.name.toLowerCase().includes(query) || entry.id.toLowerCase().includes(query))
            .sort((a, b) => a.name.localeCompare(b.name));
    }

    background: Rectangle {
        radius: Appearance.rounding.normal
        color: ColorUtils.applyAlpha(Appearance.colors.colLayer1, 1)
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }

    contentItem: ColumnLayout {
        spacing: 10
        StyledText {
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnLayer1
        }
        TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: Translation.tr("Search apps")
            placeholderTextColor: Appearance.colors.colSubtext
            color: Appearance.colors.colOnLayer3
            leftPadding: 14
            topPadding: 10
            bottomPadding: 10
            font.pixelSize: Appearance.font.pixelSize.small
            background: Rectangle {
                implicitHeight: 40
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
                border.width: searchField.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
            }
            Keys.onEscapePressed: root.close()
        }
        StyledListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            model: root.apps
            delegate: RippleButton {
                id: appRow
                required property var modelData
                width: ListView.view.width
                implicitHeight: 44
                buttonRadius: Appearance.rounding.small
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: {
                    root.picked(appRow.modelData);
                    root.close();
                }
                contentItem: RowLayout {
                    spacing: 12
                    IconImage {
                        Layout.leftMargin: 6
                        implicitSize: 28
                        source: Quickshell.iconPath(appRow.modelData.icon, "image-missing")
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: appRow.modelData.name
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer1
                    }
                }
            }
        }
    }
}
