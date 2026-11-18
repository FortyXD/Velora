import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.barLayout
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Panel beside the bar while it is edited (under or over a horizontal bar, next to a vertical one):
 * undo, reset, settings and done; the selected widget's card, the same one the settings page shows;
 * and the widgets that can be added, by category (click adds after the selected widget, or drag
 * one onto the bar). Delete removes the selected widget, Ctrl+Z undoes, Esc finishes.
 */
Rectangle {
    id: root

    required property var view
    required property var controller

    readonly property string orientation: view?.orientation ?? "horizontal"
    readonly property bool vertical: root.orientation === "vertical"
    readonly property var layout: root.vertical ? BarLayout.vertical : BarLayout.horizontal
    readonly property var selected: GlobalStates.barEditSelection.length > 0 ? BarLayout.find(root.layout, GlobalStates.barEditSelection) : null
    readonly property var zoneInfo: BarLayout.zoneInfo(root.orientation)
    // How tall the body is under a horizontal bar; beside a vertical one it takes the screen's height
    readonly property real horizontalBodyHeight: 300

    function usable(type) {
        const meta = BarWidgetCatalog.get(type);
        return !root.vertical || meta.vertical;
    }

    function placedOfType(type) {
        for (const zone of BarLayout.zoneNames) {
            const item = root.layout.zones[zone].find(item => item.type === type);
            if (item) return {zone: zone, item: item};
        }
        return null;
    }

    function catalogTypes(category) {
        return Object.keys(BarWidgetCatalog.widgets)
            .filter(type => BarWidgetCatalog.get(type).category === category && root.usable(type))
            .sort((a, b) => Number(!!root.placedOfType(b)) - Number(!!root.placedOfType(a))
                || BarWidgetCatalog.get(a).name.localeCompare(BarWidgetCatalog.get(b).name));
    }

    function addWidget(type) {
        const existing = root.placedOfType(type);
        if (existing) {
            GlobalStates.barEditSelection = existing.item.uid;
            return;
        }
        const zone = root.view.pickedInsertion?.zone ?? root.selected?.zone ?? "end";
        const index = root.view.pickedInsertion?.index ?? (root.selected ? root.selected.index + 1 : -1);
        GlobalStates.barEditSelection = BarLayout.insert(root.orientation, type, zone, index);
    }

    function dragWidget(type, sceneX, sceneY, offsetX, offsetY) {
        const existing = BarWidgetCatalog.get(type)?.unique ? root.placedOfType(type) : null;
        if (existing) {
            for (const zone of root.view.zoneItems) {
                const host = zone.orderedHosts().find(host => host.uid === existing.item.uid);
                if (host) {
                    root.controller.start({mode: "move", uid: host.uid, type: type, host: host, offsetX: offsetX, offsetY: offsetY}, sceneX, sceneY);
                    return;
                }
            }
            return;
        }
        root.controller.start({mode: "add", type: type, offsetX: offsetX, offsetY: offsetY}, sceneX, sceneY);
    }

    implicitHeight: header.implicitHeight + 12 + root.horizontalBodyHeight + 28
    radius: Appearance.rounding.windowRounding
    color: Appearance.m3colors.m3surfaceContainer
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    focus: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            GlobalStates.barEditing = false;
        } else if (event.key === Qt.Key_Delete && root.selected) {
            BarLayout.remove(root.orientation, GlobalStates.barEditSelection);
            GlobalStates.barEditSelection = "";
        } else if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
            BarLayout.undo();
        } else {
            return;
        }
        event.accepted = true;
    }

    // Clicks on the panel's background must not fall through to windows below
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.forceActiveFocus()
        onWheel: wheel => wheel.accepted = true
    }

    component ToolButton: RippleButton {
        id: toolButton
        property string symbol
        property string tip
        implicitWidth: 36
        implicitHeight: 36
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer1Hover
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: toolButton.symbol
            iconSize: 20
            color: toolButton.enabled ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
        }
        StyledToolTip {
            text: toolButton.tip
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 14
        }
        spacing: 12

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                implicitWidth: 38
                implicitHeight: 38
                radius: 12
                color: Appearance.colors.colPrimaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "edit"
                    iconSize: 20
                    fill: 1
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Translation.tr("Editing the bar")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer0
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Translation.tr("Drag widgets to move them · click one to set it up")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            ToolButton {
                symbol: "undo"
                tip: Translation.tr("Undo")
                enabled: BarLayout.canUndo
                onClicked: BarLayout.undo()
            }
            ToolButton {
                symbol: "restart_alt"
                tip: Translation.tr("Reset to default")
                onClicked: {
                    BarLayout.reset(root.orientation);
                    GlobalStates.barEditSelection = "";
                }
            }
            ToolButton {
                symbol: "settings"
                tip: Translation.tr("All settings")
                onClicked: root.view.openSettings("bar")
            }
            RippleButton {
                implicitHeight: 36
                leftPadding: 18
                rightPadding: 18
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: GlobalStates.barEditing = false
                contentItem: StyledText {
                    text: Translation.tr("Done")
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnPrimary
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: root.vertical ? 1 : 2
            columnSpacing: 14
            rowSpacing: 12

            // The selected widget, or how to pick one
            Item {
                Layout.row: 0
                Layout.column: root.vertical ? 0 : 1
                Layout.fillWidth: root.vertical
                Layout.preferredWidth: root.vertical ? -1 : 340
                Layout.fillHeight: !root.vertical
                implicitHeight: root.selected ? inspector.height : pickHint.implicitHeight

                WidgetInspector {
                    id: inspector
                    visible: root.selected !== null
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    orientation: root.orientation
                    selected: root.selected
                    zoneInfo: root.zoneInfo
                    maximumHeight: root.vertical ? 380 : root.horizontalBodyHeight
                    onCloseRequested: GlobalStates.barEditSelection = ""
                    onSelectRequested: uid => GlobalStates.barEditSelection = uid
                }

                Rectangle {
                    id: pickHint
                    visible: root.selected === null
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    implicitHeight: hintRow.implicitHeight + 28
                    radius: Appearance.rounding.normal
                    color: "transparent"
                    border.width: 1
                    border.color: Appearance.colors.colOutlineVariant
                    RowLayout {
                        id: hintRow
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            margins: 14
                        }
                        spacing: 10
                        MaterialSymbol {
                            text: "touch_app"
                            iconSize: 22
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: Translation.tr("Click a widget on the bar to set it up, move it to another part or remove it")
                            font.pixelSize: Appearance.font.pixelSize.small
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // Widgets to add
            ColumnLayout {
                Layout.row: root.vertical ? 1 : 0
                Layout.column: 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: Translation.tr("Highlighted widgets are already on the bar. Click to configure; drag to add another.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                StyledFlickable {
                    id: paletteFlick
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: paletteColumn.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: paletteColumn
                        width: paletteFlick.width
                        spacing: 10

                        Repeater {
                            model: BarWidgetCatalog.categories
                            delegate: ColumnLayout {
                                id: category
                                required property var modelData
                                readonly property var types: root.catalogTypes(category.modelData.id)
                                visible: category.types.length > 0
                                Layout.fillWidth: true
                                spacing: 4

                                StyledText {
                                    text: category.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.variableAxes: ({ "wght": 600 })
                                    color: Appearance.colors.colOnLayer0
                                }
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Repeater {
                                        model: category.types
                                        delegate: WidgetChip {
                                            required property string modelData
                                            readonly property var meta: BarWidgetCatalog.get(modelData)
                                            compact: true
                                            label: meta.name
                                            icon: meta.icon
                                            present: !!root.placedOfType(modelData)
                                            pill: present
                                            onClicked: root.addWidget(modelData)
                                            onDragStarted: (sceneX, sceneY, offsetX, offsetY) => root.dragWidget(modelData, sceneX, sceneY, offsetX, offsetY)
                                            onDragMoved: (sceneX, sceneY) => root.controller.update(sceneX, sceneY)
                                            onDragEnded: (sceneX, sceneY) => {
                                                if (sceneX < 0) root.controller.cancel();
                                                else root.controller.finish(sceneX, sceneY);
                                            }
                                            StyledToolTip {
                                                text: parent.meta.description
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
