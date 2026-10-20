import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.barLayout
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * Panel under the bar while it is edited: undo, reset and done; the widgets that can be added
 * (click adds next to the selected widget, or drag onto the bar); the selected widget's options.
 */
Rectangle {
    id: root

    required property var view
    required property var controller

    readonly property string orientation: view?.orientation ?? "horizontal"
    readonly property var layout: orientation === "vertical" ? BarLayout.vertical : BarLayout.horizontal
    readonly property var selected: GlobalStates.barEditSelection.length > 0 ? BarLayout.find(layout, GlobalStates.barEditSelection) : null
    readonly property var selectedMeta: selected ? BarWidgetCatalog.get(selected.item.type) : null

    readonly property var paletteTypes: Object.keys(BarWidgetCatalog.widgets).filter(type => {
        const meta = BarWidgetCatalog.get(type);
        if (root.orientation === "vertical" && !meta.vertical) return false;
        if (meta.unique && BarLayout.zoneNames.some(zone => root.layout.zones[zone].some(item => item.type === type))) return false;
        return true;
    })

    function addWidget(type) {
        const zone = root.selected?.zone ?? "end";
        const index = root.selected ? root.selected.index + 1 : -1;
        GlobalStates.barEditSelection = BarLayout.insert(root.orientation, type, zone, index);
    }

    implicitHeight: content.implicitHeight + 24
    radius: Appearance.rounding.windowRounding
    color: Appearance.m3colors.m3surfaceContainer
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    focus: true
    Keys.onEscapePressed: GlobalStates.barEditing = false

    // Clicks on the drawer's background must not fall through to windows below
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onWheel: wheel => wheel.accepted = true
    }

    ColumnLayout {
        id: content
        anchors {
            fill: parent
            margins: 12
        }
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            MaterialSymbol {
                text: "edit"
                iconSize: 22
                color: Appearance.colors.colPrimary
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
                    wrapMode: Text.Wrap
                    text: Translation.tr("Drag widgets to move them, right click for more. Esc to finish.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            RippleButton {
                implicitHeight: 34
                leftPadding: 16
                rightPadding: 16
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

        Flow {
            Layout.fillWidth: true
            spacing: 4
            DialogButton {
                buttonText: Translation.tr("Undo")
                enabled: BarLayout.canUndo
                onClicked: BarLayout.undo()
            }
            DialogButton {
                buttonText: Translation.tr("Reset to default")
                onClicked: {
                    BarLayout.reset(root.orientation);
                    GlobalStates.barEditSelection = "";
                }
            }
            DialogButton {
                buttonText: Translation.tr("All settings")
                onClicked: root.view.openSettings("bar")
            }
        }

        StyledFlickable { // Widgets to add
            Layout.fillWidth: true
            implicitHeight: Math.min(paletteFlow.implicitHeight, 120)
            contentHeight: paletteFlow.implicitHeight
            clip: true

            Flow {
                id: paletteFlow
                width: parent.width
                spacing: 6
                Repeater {
                    model: root.paletteTypes
                    delegate: WidgetChip {
                        required property string modelData
                        readonly property var meta: BarWidgetCatalog.get(modelData)
                        compact: true
                        label: meta.name
                        icon: meta.icon
                        pill: !!meta.defaults?.pill
                        onClicked: root.addWidget(modelData)
                        onDragStarted: (sceneX, sceneY, offsetX, offsetY) => root.controller.start({
                            "mode": "add", "type": modelData, "offsetX": offsetX, "offsetY": offsetY
                        }, sceneX, sceneY)
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

        ColumnLayout { // The selected widget
            Layout.fillWidth: true
            visible: root.selected !== null
            spacing: 6

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: root.selectedMeta?.icon ?? "help"
                    iconSize: 20
                    color: Appearance.colors.colOnLayer0
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        text: root.selectedMeta?.name ?? (root.selected?.item.type ?? "")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: root.selectedMeta?.description ?? ""
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                ConfigSelectionArray {
                    currentValue: root.selected?.item.hideAt ?? 0
                    onSelected: newValue => BarLayout.setItem(root.orientation, GlobalStates.barEditSelection, { "hideAt": newValue === 0 ? null : newValue })
                    options: [
                        { displayName: Translation.tr("Always show"), icon: "visibility", value: 0 },
                        { displayName: Translation.tr("Hide when narrow"), icon: "compress", value: 1 }
                    ]
                }
                ConfigSelectionArray {
                    currentValue: !!root.selected?.item.pill
                    onSelected: newValue => BarLayout.setItem(root.orientation, GlobalStates.barEditSelection, { "pill": newValue ? true : null, "pillBreak": null })
                    options: [
                        { displayName: Translation.tr("Bare"), icon: "crop_free", value: false },
                        { displayName: Translation.tr("In a pill"), icon: "pill", value: true }
                    ]
                }
                DialogButton {
                    buttonText: Translation.tr("Remove")
                    colEnabled: Appearance.colors.colError
                    onClicked: {
                        BarLayout.remove(root.orientation, GlobalStates.barEditSelection);
                        GlobalStates.barEditSelection = "";
                    }
                }
            }

            StyledFlickable {
                Layout.fillWidth: true
                visible: optionsForm.visible
                implicitHeight: Math.min(optionsForm.implicitHeight, 260)
                contentHeight: optionsForm.implicitHeight
                clip: true
                BarWidgetOptionsForm {
                    id: optionsForm
                    width: parent.width
                    orientation: root.orientation
                    item: root.selected?.item ?? null
                }
            }
        }
    }
}
