pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * A small drawing of what a sidebar part shows, for SidebarPartsMockup: the real toggles and their
 * layout, how many sliders, which tabs, and so on.
 */
Item {
    id: root
    required property var part
    required property Item mockup // SidebarPartsMockup, for the toggles' layout and picking pages
    readonly property var options: SidebarLayout.optionsOf(root.part)
    readonly property color ink: Appearance.colors.colOnLayer1

    Loader {
        anchors.fill: parent
        sourceComponent: ({ "header": header, "sliders": sliders, "toggles": toggles, "notifications": notifications,
            "calendar": calendar, "todo": todo, "timer": timer, "ai": ai, "translator": translator, "anime": anime,
            "media": media, "weather": weather, "system": system, "tools": tools, "clipboard": clipboard,
            "notes": notes, "tabs": tabs })[root.part?.type] ?? null
    }

    component Line: Rectangle {
        property real fraction: 0.6
        width: parent.width * fraction
        height: 5
        radius: 2.5
        color: root.ink
        opacity: 0.35
    }

    Component {
        id: header
        RowLayout {
            spacing: 4
            Rectangle {
                visible: root.options.showUptime ?? true
                implicitWidth: 64
                implicitHeight: 24
                radius: 12
                color: Appearance.colors.colLayer1
                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("Up %1").arg("3h")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: root.ink
                }
            }
            Item { Layout.fillWidth: true }
            Rectangle {
                implicitWidth: buttonsRow.implicitWidth + 10
                implicitHeight: 24
                radius: 12
                color: Appearance.colors.colLayer1
                Row {
                    id: buttonsRow
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: SidebarCatalog.headerButtons.filter(b => (root.options.buttons ?? SidebarCatalog.headerButtons.map(x => x.id)).includes(b.id)
                            && (b.id !== "edit" || !root.mockup.classic))
                        MaterialSymbol {
                            required property var modelData
                            text: modelData.icon
                            iconSize: 13
                            color: root.ink
                        }
                    }
                }
            }
        }
    }

    Component {
        id: sliders
        Column {
            spacing: 4
            Repeater {
                model: root.mockup.slidersShown.length > 0 ? root.mockup.slidersShown : ["tune"]
                Row {
                    required property string modelData
                    required property int index
                    spacing: 6
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData
                        iconSize: 12
                        color: root.ink
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: root.width - 30
                        height: 8
                        radius: 4
                        color: Appearance.colors.colSecondaryContainer
                        Rectangle {
                            width: parent.width * [0.6, 0.4, 0.75][index % 3]
                            height: parent.height
                            radius: 4
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }
        }
    }

    Component {
        id: toggles
        Item {
            id: togglesArea
            Column { // Tiles: the real grid, wide toggles with their name
                id: grid
                visible: !root.mockup.classic
                anchors.fill: parent
                spacing: 4
                readonly property real cell: (width - 4 * (root.mockup.columns - 1)) / root.mockup.columns
                Repeater {
                    model: root.mockup.toggleRows
                    Row {
                        required property var modelData
                        spacing: 4
                        Repeater {
                            model: modelData
                            Rectangle {
                                required property var modelData
                                required property int index
                                width: grid.cell * modelData.size + 4 * (modelData.size - 1)
                                height: 30
                                radius: modelData.size > 1 ? 15 : 10
                                color: index % 3 === 0 ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                                Row {
                                    anchors {
                                        left: parent.left
                                        leftMargin: modelData.size > 1 ? 8 : 0
                                        horizontalCenter: modelData.size > 1 ? undefined : parent.horizontalCenter
                                        verticalCenter: parent.verticalCenter
                                    }
                                    spacing: 4
                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: SidebarCatalog.toggle(modelData.type)?.icon ?? "help"
                                        iconSize: 14
                                        fill: 1
                                        color: index % 3 === 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                    }
                                    StyledText {
                                        visible: modelData.size > 1
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: grid.cell * modelData.size - 34
                                        elide: Text.ElideRight
                                        text: SidebarCatalog.toggle(modelData.type)?.name ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: index % 3 === 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Row { // Round buttons
                visible: root.mockup.classic
                anchors.centerIn: parent
                spacing: 4
                Repeater {
                    model: SidebarLayout.classicToggles()
                    Rectangle {
                        required property string modelData
                        required property int index
                        width: Math.min(26, (togglesArea.width - 4 * 7) / 8)
                        height: width
                        radius: width / 2
                        color: index % 3 === 0 ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: SidebarCatalog.toggle(modelData)?.icon ?? "help"
                            iconSize: 13
                            fill: 1
                            color: index % 3 === 0 ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer2
                        }
                    }
                }
            }
        }
    }

    Component {
        id: notifications
        Column {
            spacing: 6
            clip: true
            Repeater {
                model: 8
                Row {
                    required property int index
                    spacing: 6
                    Rectangle {
                        width: 18
                        height: 18
                        radius: 9
                        color: [Appearance.colors.colPrimary, Appearance.colors.colTertiary, Appearance.colors.colSecondary][index % 3]
                    }
                    Column {
                        spacing: 3
                        Rectangle { width: root.width * [0.45, 0.3, 0.38][index % 3]; height: 5; radius: 2.5; color: root.ink; opacity: 0.7 }
                        Rectangle { width: root.width * [0.7, 0.62, 0.55][index % 3]; height: 4; radius: 2; color: root.ink; opacity: 0.35 }
                    }
                }
            }
        }
    }

    Component {
        id: calendar
        Item {
            Grid {
                anchors.centerIn: parent
                columns: 7
                spacing: 5
                Repeater {
                    model: 35
                    Rectangle {
                        required property int index
                        width: 7
                        height: 7
                        radius: 3.5
                        color: index === 17 ? Appearance.colors.colPrimary : root.ink
                        opacity: index === 17 ? 1 : 0.3
                    }
                }
            }
        }
    }

    Component {
        id: todo
        Item {
            Column {
                anchors.centerIn: parent
                spacing: 6
                Repeater {
                    model: 4
                    Row {
                        required property int index
                        spacing: 5
                        Rectangle { width: 8; height: 8; radius: 2; border.width: 1; border.color: root.ink; color: "transparent" }
                        Rectangle { width: [70, 50, 62, 40][index]; height: 5; radius: 2.5; color: root.ink; opacity: 0.4; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
            }
        }
    }

    Component {
        id: timer
        Item {
            Rectangle {
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height) * 0.7
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 3
                border.color: Appearance.colors.colPrimary
                StyledText {
                    anchors.centerIn: parent
                    text: "05:00"
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.ink
                }
            }
        }
    }

    Component {
        id: ai
        Item { // Chat: bubbles and an input line
            Column {
                width: parent.width
                spacing: 8
                Repeater {
                    model: [0.55, 0.8, 0.4, 0.7]
                    Rectangle {
                        required property real modelData
                        required property int index
                        x: index % 2 === 0 ? parent.width - width : 0
                        width: parent.width * modelData
                        height: index % 2 === 0 ? 18 : 36
                        radius: 9
                        color: index % 2 === 0 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                    }
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 24
                radius: 12
                color: Appearance.colors.colLayer2
            }
        }
    }

    Component {
        id: translator
        Column { // Two boxes
            spacing: 8
            Repeater {
                model: 2
                Rectangle {
                    width: root.width
                    height: (root.height - 8) / 2
                    radius: 10
                    color: Appearance.colors.colLayer2
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "translate"
                        iconSize: 20
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }

    Component {
        id: anime
        Grid { // Images
            columns: 2
            spacing: 6
            clip: true
            Repeater {
                model: 8
                Rectangle {
                    required property int index
                    width: (root.width - 6) / 2
                    height: width * [1.3, 0.8, 1, 1.2][index % 4]
                    radius: 8
                    color: [Appearance.colors.colPrimaryContainer, Appearance.colors.colTertiaryContainer, Appearance.colors.colSecondaryContainer][index % 3]
                }
            }
        }
    }

    Component {
        id: media
        RowLayout { // Cover, title, progress
            spacing: 8
            Rectangle {
                Layout.fillHeight: true
                implicitWidth: height
                radius: 8
                color: Appearance.colors.colTertiaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "music_note"
                    iconSize: 18
                    color: Appearance.colors.colOnTertiaryContainer
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                Rectangle { Layout.preferredWidth: parent.width * 0.7; implicitHeight: 6; radius: 3; color: root.ink; opacity: 0.7 }
                Rectangle { Layout.preferredWidth: parent.width * 0.45; implicitHeight: 5; radius: 2.5; color: root.ink; opacity: 0.35 }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 4
                    radius: 2
                    color: Appearance.colors.colSecondaryContainer
                    Rectangle { width: parent.width * 0.4; height: parent.height; radius: 2; color: Appearance.colors.colPrimary }
                }
            }
        }
    }

    Component {
        id: weather
        ColumnLayout {
            spacing: 6
            RowLayout {
                spacing: 6
                MaterialSymbol {
                    text: "partly_cloudy_day"
                    iconSize: 24
                    fill: 1
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    text: "18°"
                    font.pixelSize: Appearance.font.pixelSize.larger
                    color: root.ink
                }
                Item { Layout.fillWidth: true }
            }
            Row {
                visible: root.options.showHours ?? true
                spacing: (root.width - 6 * 14) / 5
                Repeater {
                    model: 6
                    Column {
                        spacing: 2
                        MaterialSymbol { text: "cloud"; iconSize: 12; color: root.ink; opacity: 0.6 }
                        Rectangle { width: 14; height: 4; radius: 2; color: root.ink; opacity: 0.3 }
                    }
                }
            }
            Column {
                visible: root.options.showDays ?? false
                Layout.fillWidth: true
                spacing: 3
                Repeater {
                    model: 3
                    Rectangle { width: root.width; height: 12; radius: 4; color: Appearance.colors.colLayer2 }
                }
            }
            Grid {
                visible: root.options.showDetails ?? false
                columns: 3
                spacing: 3
                Repeater {
                    model: 6
                    Rectangle { width: (root.width - 6) / 3; height: 22; radius: 4; color: Appearance.colors.colLayer2 }
                }
            }
        }
    }

    Component {
        id: system
        ColumnLayout {
            spacing: 6
            RowLayout {
                spacing: 4
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: 6
                        color: Appearance.colors.colLayer2
                        Rectangle {
                            anchors {
                                left: parent.left
                                right: parent.right
                                bottom: parent.bottom
                                margins: 4
                            }
                            height: [16, 24, 8][parent.index]
                            radius: 3
                            color: Appearance.colors.colSecondaryContainer
                        }
                    }
                }
            }
            Row {
                spacing: 4
                Repeater {
                    model: 3
                    Rectangle { width: 44; height: 14; radius: 7; color: Appearance.colors.colLayer2 }
                }
            }
        }
    }

    Component {
        id: tools
        Grid {
            readonly property var items: (root.options.items ?? SidebarCatalog.defaultTools)
            readonly property int count: Math.max(3, root.options.columns ?? 4)
            columns: count
            spacing: 4
            Repeater {
                model: parent.items
                Rectangle {
                    required property string modelData
                    width: (root.width - 4 * (parent.count - 1)) / parent.count
                    height: (root.options.labels ?? true) ? 34 : 26
                    radius: 6
                    color: Appearance.colors.colLayer2
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: modelData.startsWith("app:") ? "apps" : (SidebarCatalog.tool(modelData)?.icon ?? "handyman")
                        iconSize: 14
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }

    Component {
        id: clipboard
        Column {
            spacing: 4
            clip: true
            Rectangle { width: root.width; height: 18; radius: 9; color: Appearance.colors.colLayer2 }
            Repeater {
                model: 7
                Rectangle {
                    required property int index
                    width: root.width
                    height: index === 2 ? 34 : 16
                    radius: 5
                    color: index === 2 ? Appearance.colors.colTertiaryContainer : Appearance.colors.colLayer2
                }
            }
        }
    }

    Component {
        id: notes
        Column {
            topPadding: 6
            spacing: 6
            clip: true
            Repeater {
                model: 9
                Line {
                    required property int index
                    fraction: [0.8, 0.6, 0.9, 0.4, 0.7, 0.85, 0.5, 0.75, 0.3][index]
                }
            }
        }
    }

    Component {
        id: tabs
        Item {
            id: tabsSketch
            readonly property var pages: (root.part.tabs ?? []).filter(tab => SidebarLayout.shown(tab))
            readonly property bool rail: root.options.style === "rail"
            readonly property string shownUid: {
                const picked = tabsSketch.pages.find(page => page.uid === root.mockup.selectedUid);
                if (picked) return picked.uid;
                const remembered = SidebarLayout.tabState(root.part.uid).tab;
                return tabsSketch.pages.find(page => page.uid === remembered)?.uid ?? (tabsSketch.pages[0]?.uid ?? "");
            }
            readonly property var shownPage: tabsSketch.pages.find(page => page.uid === tabsSketch.shownUid) ?? null

            GridLayout {
                anchors.fill: parent
                columns: tabsSketch.rail ? 2 : 1
                rowSpacing: 6
                columnSpacing: 6

                Flow { // The tabs; click one to pick that page
                    Layout.alignment: tabsSketch.rail ? Qt.AlignVCenter : Qt.AlignHCenter
                    Layout.maximumWidth: tabsSketch.rail ? 30 : tabsSketch.width
                    flow: tabsSketch.rail ? Flow.TopToBottom : Flow.LeftToRight
                    spacing: 3
                    Repeater {
                        model: tabsSketch.pages.filter(page => !page.swipeOnly)
                        delegate: RippleButton {
                            id: tabChip
                            required property var modelData
                            readonly property bool current: modelData.uid === tabsSketch.shownUid
                            implicitWidth: tabsSketch.rail ? 28 : tabRow.implicitWidth + 12
                            implicitHeight: 20
                            buttonRadius: 10
                            colBackground: tabChip.current ? Appearance.colors.colSecondaryContainer : "transparent"
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            onClicked: root.mockup.partClicked(modelData.uid)
                            contentItem: Row {
                                id: tabRow
                                spacing: 3
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: SidebarCatalog.part(tabChip.modelData.type)?.icon ?? "tab"
                                    iconSize: 12
                                    color: root.ink
                                }
                                StyledText {
                                    visible: !tabsSketch.rail && tabsSketch.pages.length <= 3
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: SidebarCatalog.part(tabChip.modelData.type)?.name ?? ""
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: root.ink
                                }
                            }
                        }
                    }
                }

                Rectangle { // The page shown
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 8
                    color: Appearance.colors.colLayer2
                    clip: true
                    Loader { // The page's own sketch (a file can't name itself as a type)
                        id: pageLoader
                        anchors.fill: parent
                        anchors.margins: 6
                        function load() {
                            if (tabsSketch.shownPage) pageLoader.setSource("PartSketch.qml", { "part": tabsSketch.shownPage, "mockup": root.mockup });
                            else pageLoader.source = "";
                        }
                        Component.onCompleted: pageLoader.load()
                        Connections {
                            target: tabsSketch
                            function onShownPageChanged() { pageLoader.load() }
                        }
                    }
                    StyledText {
                        visible: tabsSketch.pages.length === 0
                        anchors.centerIn: parent
                        text: Translation.tr("No tabs")
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}
