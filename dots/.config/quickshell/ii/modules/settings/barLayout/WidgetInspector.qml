import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Card with everything about the selected widget, shown on the canvas beside it: what it is,
 * duplicate / move / remove, its pill and narrow-screen behavior, and its own options.
 */
Rectangle {
    id: root
    required property string orientation
    required property var selected // { zone, index, item } from BarLayout.find
    required property var zoneInfo // [{ zone, title, icon }]
    property real maximumHeight: 400
    readonly property var item: root.selected?.item ?? null
    readonly property var meta: root.item ? BarWidgetCatalog.get(root.item.type) : null
    readonly property bool horizontal: root.orientation !== "vertical"
    readonly property bool islands: Config.options.bar.style.islands

    signal closeRequested()
    signal selectRequested(string uid)

    implicitWidth: 330
    implicitHeight: Math.min(root.maximumHeight, header.implicitHeight + flick.contentHeight + 12)
    radius: Appearance.rounding.normal
    color: ColorUtils.applyAlpha(Appearance.colors.colLayer1, 1) // Opaque, so the wallpaper never shows through the text
    border.width: 1
    border.color: Appearance.colors.colOutlineVariant

    // Small round action in the header
    component HeaderAction: RippleButton {
        id: action
        property string symbol
        property string tip
        property color iconColor: Appearance.colors.colOnLayer1
        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackgroundHover: Appearance.colors.colLayer1Hover
        contentItem: MaterialSymbol {
            horizontalAlignment: Text.AlignHCenter
            text: action.symbol
            iconSize: 19
            color: action.iconColor
        }
        StyledToolTip {
            text: action.tip
        }
    }

    // Segmented choice in a compact row
    component Choice: ColumnLayout {
        id: choice
        property string title
        property var options: []
        property var value
        signal picked(var value)
        Layout.fillWidth: true
        Layout.leftMargin: 12
        Layout.rightMargin: 12
        spacing: 4
        StyledText {
            text: choice.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 2
            Repeater {
                model: choice.options
                delegate: SelectionGroupButton {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    horizontalPadding: 8
                    leftmost: index === 0
                    rightmost: index === choice.options.length - 1
                    buttonText: modelData.name
                    toggled: JSON.stringify(choice.value) === JSON.stringify(modelData.value)
                    onClicked: choice.picked(modelData.value)
                }
            }
        }
    }

    ColumnLayout {
        id: header
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Rectangle {
                implicitWidth: 36
                implicitHeight: 36
                radius: 11
                color: Appearance.colors.colPrimaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.meta?.icon ?? "error"
                    iconSize: 20
                    fill: 1
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.meta?.name ?? Translation.tr("Unknown widget")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.variableAxes: ({ "wght": 600 })
                    color: Appearance.colors.colOnLayer1
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.selected ? (root.zoneInfo.find(info => info.zone === root.selected.zone)?.title ?? "") : ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
            HeaderAction {
                visible: !(root.meta?.unique ?? false)
                symbol: "content_copy"
                tip: Translation.tr("Duplicate")
                onClicked: {
                    const item = root.item;
                    root.selectRequested(BarLayout.insert(root.orientation, item.type, root.selected.zone, root.selected.index + 1, {
                        "pill": item.pill, "hideAt": item.hideAt, "options": item.options
                    }));
                }
            }
            HeaderAction {
                symbol: "delete"
                tip: Translation.tr("Remove from the bar")
                iconColor: Appearance.colors.colError
                onClicked: {
                    BarLayout.remove(root.orientation, root.item.uid);
                    root.closeRequested();
                }
            }
            HeaderAction {
                symbol: "close"
                tip: Translation.tr("Close")
                onClicked: root.closeRequested()
            }
        }

        StyledText {
            visible: (root.meta?.description ?? "").length > 0
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: root.meta?.description ?? ""
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    StyledFlickable {
        id: flick
        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            bottom: parent.bottom
            topMargin: 8
            bottomMargin: 4
        }
        clip: true
        contentHeight: body.implicitHeight + 8
        interactive: contentHeight > height

        ColumnLayout {
            id: body
            width: flick.width
            spacing: 10

            Choice {
                title: Translation.tr("Part of the bar")
                value: root.selected?.zone ?? ""
                options: root.zoneInfo.map(info => ({ "value": info.zone, "name": info.short }))
                onPicked: value => BarLayout.move(root.orientation, root.item.uid, value, 999)
            }

            Choice { // With islands every run of widgets shares one card, so the question is only whether this one stands apart
                visible: root.islands
                title: Translation.tr("Island")
                value: root.item && BarLayout.isOwnIsland(root.orientation, root.item.uid) ? "own" : "shared"
                options: [
                    { "value": "shared", "name": Translation.tr("With neighbours") },
                    { "value": "own", "name": Translation.tr("Separate") },
                ]
                onPicked: value => BarLayout.setOwnIsland(root.orientation, root.item.uid, value === "own")
            }

            Choice {
                visible: !root.islands
                title: Translation.tr("Background")
                value: !root.item?.pill ? "none" : root.item?.pillBreak ? "new" : "pill"
                options: [
                    { "value": "pill", "name": Translation.tr("In a pill") },
                    { "value": "new", "name": Translation.tr("New pill") },
                    { "value": "none", "name": Translation.tr("None") },
                ]
                onPicked: value => BarLayout.setItem(root.orientation, root.item.uid, {
                    "pill": value === "none" ? null : true,
                    "pillBreak": value === "new" ? true : null
                })
            }

            Choice {
                visible: root.horizontal
                title: Translation.tr("On narrow screens")
                value: root.item?.hideAt ?? 0
                options: [
                    { "value": 0, "name": Translation.tr("Always show") },
                    { "value": 1, "name": Translation.tr("Hide") },
                    { "value": 2, "name": Translation.tr("Hide on very narrow") },
                ]
                onPicked: value => BarLayout.setItem(root.orientation, root.item.uid, { "hideAt": value === 0 ? null : value })
            }

            Choice {
                visible: root.horizontal && (root.meta?.elastic ?? false)
                title: Translation.tr("Width")
                value: root.item?.fill === undefined ? "auto" : root.item.fill
                options: [
                    { "value": "auto", "name": Translation.tr("Automatic") },
                    { "value": true, "name": Translation.tr("Take free space") },
                    { "value": false, "name": Translation.tr("Fit content") },
                ]
                onPicked: value => BarLayout.setItem(root.orientation, root.item.uid, { "fill": value === "auto" ? null : value })
            }

            Rectangle {
                visible: (root.meta?.options ?? []).length > 0
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                implicitHeight: optionsForm.implicitHeight + 8
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                BarWidgetOptionsForm {
                    id: optionsForm
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 4
                    }
                    orientation: root.orientation
                    item: root.item
                }
            }
        }
    }
}
