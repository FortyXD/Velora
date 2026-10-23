import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The left sidebar drawn from its settings: the tabs in their order and a sketch of the picked one.
 */
Rectangle {
    id: root
    property string selected: "ai"
    signal tabClicked(string id)

    readonly property bool wide: Config.options.sidebar.left.extendedByDefault
    readonly property var tabs: {
        const known = SidebarCatalog.leftTabs.map(tab => tab.id);
        const given = (Config.options.sidebar.left.order ?? []).filter(id => known.includes(id));
        return [...given, ...known.filter(id => !given.includes(id))].filter(id => root.tabShown(id)).map(id => SidebarCatalog.leftTabs.find(t => t.id === id));
    }
    function tabShown(id) {
        if (id === "ai") return Config.options.policies.ai !== 0;
        if (id === "translator") return Config.options.sidebar.translator.enable;
        return Config.options.policies.weeb === 1;
    }

    implicitWidth: Math.round(300 * (root.wide ? Appearance.sizes.sidebarWidthExtended : Appearance.sizes.sidebarWidth) / 460)
    implicitHeight: 620
    radius: 20
    color: Appearance.colors.colLayer0
    border.width: 1
    border.color: Appearance.colors.colLayer0Border
    Behavior on implicitWidth {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: 8
        }
        spacing: 8

        // Tab bar
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            visible: root.tabs.length > 0
            implicitWidth: tabRow.implicitWidth + 8
            implicitHeight: 34
            radius: 17
            color: Appearance.m3colors.m3surfaceContainer
            Row {
                id: tabRow
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: root.tabs
                    delegate: RippleButton {
                        id: tabButton
                        required property var modelData
                        readonly property bool picked: root.selected === modelData.id
                        implicitHeight: 26
                        leftPadding: 8
                        rightPadding: 10
                        buttonRadius: 13
                        colBackground: tabButton.picked ? Appearance.colors.colSecondaryContainer : "transparent"
                        onClicked: root.tabClicked(modelData.id)
                        contentItem: RowLayout {
                            spacing: 4
                            MaterialSymbol {
                                text: tabButton.modelData.icon
                                iconSize: 14
                                color: Appearance.colors.colOnLayer1
                            }
                            StyledText {
                                text: tabButton.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }

        // The picked tab
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: Appearance.colors.colLayer1
            clip: true

            StyledText {
                visible: root.tabs.length === 0
                anchors.centerIn: parent
                text: Translation.tr("No tabs")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            // Chat: bubbles and an input line
            Item {
                anchors.fill: parent
                anchors.margins: 10
                visible: root.selected === "ai" && root.tabShown("ai")
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
                            height: index % 2 === 0 ? 22 : 46
                            radius: 10
                            color: index % 2 === 0 ? Appearance.colors.colPrimaryContainer : Appearance.colors.colLayer2
                        }
                    }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 30
                    radius: 15
                    color: Appearance.colors.colLayer2
                }
            }

            // Translator: two boxes
            Column {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 10
                visible: root.selected === "translator" && root.tabShown("translator")
                Repeater {
                    model: 2
                    Rectangle {
                        width: parent.width
                        height: (parent.height - 10) / 2
                        radius: 10
                        color: Appearance.colors.colLayer2
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "translate"
                            iconSize: 22
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }

            // Images: a grid
            Grid {
                anchors.fill: parent
                anchors.margins: 10
                columns: 2
                spacing: 8
                visible: root.selected === "anime" && root.tabShown("anime")
                Repeater {
                    model: 8
                    Rectangle {
                        required property int index
                        width: (parent.width - 8) / 2
                        height: width * [1.3, 0.8, 1, 1.2][index % 4]
                        radius: 8
                        color: [Appearance.colors.colPrimaryContainer, Appearance.colors.colTertiaryContainer, Appearance.colors.colSecondaryContainer][index % 3]
                    }
                }
            }
        }
    }
}
