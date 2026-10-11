pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Button showing the current choice that opens a list to pick from.
 *
 * options: [{ displayName, value, icon?, iconSource?, description?, fontFamily?, section?, more?, keywords? }]
 * - `icon` is a Material symbol, `iconSource` an image (app icons).
 * - `section` puts a small header above the first item of each section.
 * - Items with `more: true` stay folded behind a "More" row until it's clicked or something is searched.
 * With `customLabel` set, a last item asks for an own value instead (signal customRequested).
 */
RippleButton {
    id: root

    property var options: []
    property var currentValue: undefined
    property string placeholderText: Translation.tr("Choose…")
    property string displayText: root.currentOption?.displayName ?? root.placeholderText
    property string displayIcon: root.currentOption?.icon ?? ""
    property string displayIconSource: root.currentOption?.iconSource ?? ""
    property string displayFontFamily: root.currentOption?.fontFamily ?? ""
    property bool searchable: root.options.length > 12
    property string searchPlaceholder: Translation.tr("Search")
    property string moreLabel: Translation.tr("More…")
    property string customLabel: ""
    property string customDescription: ""
    property bool customSelected: false
    property real popupWidth: Math.max(root.width, 300)
    property real popupMaxHeight: 420
    property real maximumWidth: 260
    property real minimumWidth: 120

    signal selected(var value)
    signal customRequested()

    function same(a, b) {
        return a === b || (a !== undefined && a !== null && b !== undefined && b !== null && String(a) === String(b));
    }
    readonly property var currentOption: root.customSelected ? null : (root.options.find(option => root.same(option.value, root.currentValue)) ?? null)

    implicitHeight: 40
    Layout.preferredWidth: Math.max(root.minimumWidth, Math.min(root.maximumWidth, buttonRow.implicitWidth + 32))
    leftPadding: 14
    rightPadding: 10
    buttonRadius: height / 2
    colBackground: Appearance.colors.colSecondaryContainer
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colRipple: Appearance.colors.colSecondaryContainerActive
    onClicked: popup.opened ? popup.close() : popup.open()

    contentItem: RowLayout {
        id: buttonRow
        spacing: 8
        IconImage {
            visible: root.displayIconSource.length > 0
            implicitSize: 22
            source: root.displayIconSource
        }
        MaterialSymbol {
            visible: root.displayIconSource.length === 0 && root.displayIcon.length > 0
            text: root.displayIcon
            iconSize: 20
            color: Appearance.colors.colOnSecondaryContainer
        }
        StyledText {
            Layout.fillWidth: true
            text: root.displayText
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.small
            font.family: root.displayFontFamily.length > 0 ? root.displayFontFamily : Appearance.font.family.main
            color: Appearance.colors.colOnSecondaryContainer
        }
        MaterialSymbol {
            text: "keyboard_arrow_down"
            iconSize: 20
            color: Appearance.colors.colOnSecondaryContainer
            rotation: popup.opened ? 180 : 0
            Behavior on rotation {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }

    property string filter: ""
    property bool showMore: false
    // What the list shows: options, then the "More" and "Custom" rows
    readonly property var items: {
        const query = root.filter.trim().toLowerCase();
        const matches = option => query.length === 0
            || `${option.displayName ?? ""} ${option.description ?? ""} ${option.keywords ?? ""} ${option.value ?? ""}`.toLowerCase().includes(query);
        const expanded = root.showMore || query.length > 0;
        let list = [];
        let hiddenMore = false;
        for (const option of root.options) {
            if (!matches(option)) continue;
            if (option.more && !expanded) {
                hiddenMore = true;
                continue;
            }
            list.push({ kind: "option", option: option });
        }
        if (hiddenMore) list.push({ kind: "more" });
        if (root.customLabel.length > 0 && query.length === 0) list.push({ kind: "custom" });
        // Headers only where the section changes
        let lastSection = "";
        for (const item of list) {
            const section = item.kind === "option" ? (item.option.section ?? "") : "";
            item.header = section.length > 0 && section !== lastSection ? section : "";
            if (item.kind === "option") lastSection = section;
        }
        return list;
    }

    function pick(item) {
        if (item.kind === "more") {
            root.showMore = true;
            return;
        }
        popup.close();
        if (item.kind === "custom") root.customRequested();
        else root.selected(item.option.value);
    }

    Popup {
        id: popup
        x: Math.min(0, root.width - width)
        y: root.height + 6
        width: root.popupWidth
        height: Math.min(popupColumn.implicitHeight + topPadding + bottomPadding, root.popupMaxHeight)
        padding: 6
        margins: 8
        focus: true

        onAboutToShow: {
            root.filter = "";
            searchField.text = "";
            root.showMore = root.options.some(option => option.more && root.same(option.value, root.currentValue));
        }
        onOpened: {
            if (root.searchable) searchField.forceActiveFocus();
            const index = root.items.findIndex(item => item.kind === "option" && root.same(item.option.value, root.currentValue));
            if (index >= 0) choiceList.positionViewAtIndex(index, ListView.Contain);
        }

        enter: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 }
                NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 200; easing.type: Easing.OutCubic }
            }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 100 }
        }

        background: Item {
            StyledRectangularShadow {
                target: popupBackground
            }
            Rectangle {
                id: popupBackground
                anchors.fill: parent
                radius: Appearance.rounding.normal
                color: Appearance.m3colors.m3surfaceContainerHigh
            }
        }

        contentItem: ColumnLayout {
            id: popupColumn
            spacing: 6

            Rectangle { // Search
                visible: root.searchable
                Layout.fillWidth: true
                implicitHeight: 38
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer3
                border.width: searchField.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8
                    MaterialSymbol {
                        text: "search"
                        iconSize: 18
                        color: Appearance.colors.colSubtext
                    }
                    TextField {
                        id: searchField
                        Layout.fillWidth: true
                        background: null
                        padding: 0
                        placeholderText: root.searchPlaceholder
                        placeholderTextColor: Appearance.colors.colSubtext
                        color: Appearance.colors.colOnLayer3
                        font.family: Appearance.font.family.main
                        font.pixelSize: Appearance.font.pixelSize.small
                        onTextChanged: root.filter = text
                        Keys.onReturnPressed: {
                            const first = root.items.find(item => item.kind === "option");
                            if (first) root.pick(first);
                        }
                        Keys.onEnterPressed: {
                            const first = root.items.find(item => item.kind === "option");
                            if (first) root.pick(first);
                        }
                    }
                }
            }

            StyledText {
                visible: root.items.length === 0
                Layout.fillWidth: true
                Layout.margins: 10
                text: Translation.tr("Nothing found")
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            StyledListView {
                id: choiceList
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: contentHeight
                clip: true
                spacing: 2
                model: popup.visible ? root.items : []

                delegate: ColumnLayout {
                    id: choiceItem
                    required property var modelData
                    readonly property var option: choiceItem.modelData.option ?? ({})
                    readonly property bool isOption: choiceItem.modelData.kind === "option"
                    readonly property bool selected: choiceItem.isOption ? !root.customSelected && root.same(choiceItem.option.value, root.currentValue)
                        : (choiceItem.modelData.kind === "custom" && root.customSelected)
                    width: choiceList.width
                    spacing: 2

                    StyledText {
                        visible: choiceItem.modelData.header.length > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        Layout.topMargin: 6
                        Layout.bottomMargin: 2
                        text: choiceItem.modelData.header
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
                    }

                    RippleButton {
                        id: choiceButton
                        Layout.fillWidth: true
                        readonly property string title: choiceItem.isOption ? (choiceItem.option.displayName ?? "")
                            : choiceItem.modelData.kind === "more" ? root.moreLabel : root.customLabel
                        readonly property string subtitle: choiceItem.isOption ? (choiceItem.option.description ?? "")
                            : choiceItem.modelData.kind === "custom" ? root.customDescription : ""
                        readonly property string symbol: choiceItem.isOption ? (choiceItem.option.icon ?? "")
                            : choiceItem.modelData.kind === "more" ? "expand_more" : "edit"
                        readonly property string image: choiceItem.isOption ? (choiceItem.option.iconSource ?? "") : ""
                        implicitHeight: choiceButton.subtitle.length > 0 ? 46 : 38
                        buttonRadius: Appearance.rounding.small
                        colBackground: choiceItem.selected ? Appearance.colors.colSecondaryContainer : "transparent"
                        colBackgroundHover: choiceItem.selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover
                        colRipple: choiceItem.selected ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer3Active
                        onClicked: root.pick(choiceItem.modelData)

                        contentItem: RowLayout {
                            spacing: 10
                            IconImage {
                                visible: choiceButton.image.length > 0
                                Layout.leftMargin: 4
                                implicitSize: 26
                                source: choiceButton.image
                            }
                            MaterialSymbol {
                                visible: choiceButton.image.length === 0 && choiceButton.symbol.length > 0
                                Layout.leftMargin: 4
                                text: choiceButton.symbol
                                iconSize: 20
                                color: choiceItem.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: choiceButton.image.length === 0 && choiceButton.symbol.length === 0 ? 6 : 0
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: choiceButton.title
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: (choiceItem.option.fontFamily ?? "").length > 0 ? choiceItem.option.fontFamily : Appearance.font.family.main
                                    color: choiceItem.selected ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer3
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: choiceButton.subtitle.length > 0
                                    text: choiceButton.subtitle
                                    elide: Text.ElideRight
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: Appearance.colors.colSubtext
                                }
                            }
                            MaterialSymbol {
                                Layout.rightMargin: 6
                                visible: choiceItem.selected
                                text: "check"
                                iconSize: 18
                                color: Appearance.colors.colOnSecondaryContainer
                            }
                        }
                    }
                }
            }
        }
    }
}
