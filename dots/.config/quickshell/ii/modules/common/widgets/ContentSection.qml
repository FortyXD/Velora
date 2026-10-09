import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A group of settings: bold title, the rows on a rounded card with separators,
 * and an optional explanation under the card. With `card: false` the content is laid out plainly.
 * Groups fade and slide in one after another when their page is first built.
 */
ColumnLayout {
    id: root
    property string title
    property string icon: "" // Used by search results
    property string description: ""
    property bool card: true
    default property alias contentData: sectionContent.contentData

    // Settings search
    readonly property bool settingsSearchable: true
    readonly property bool settingsSection: true
    property string searchText: `${root.title} ${root.description}`

    Layout.fillWidth: true
    spacing: 6

    // Entrance animation, staggered by the position among sibling sections
    property bool revealed: false
    opacity: revealed ? 1 : 0
    transform: Translate {
        y: root.revealed ? 0 : 16
        Behavior on y {
            NumberAnimation {
                duration: Appearance.animation.elementMoveEnter.duration
                easing.type: Appearance.animation.elementMoveEnter.type
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
        }
    }
    Timer {
        id: revealTimer
        onTriggered: root.revealed = true
    }
    Component.onCompleted: {
        let order = 0;
        const siblings = root.parent?.children ?? [];
        for (let i = 0; i < siblings.length && siblings[i] !== root; i++) {
            if (siblings[i].settingsSection) order++;
        }
        revealTimer.interval = 40 + Math.min(order, 8) * 45;
        revealTimer.start();
    }

    StyledText { // Title
        visible: root.title.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        text: root.title
        elide: Text.ElideRight
        font.pixelSize: Appearance.font.pixelSize.normal
        font.variableAxes: ({ "wght": 620, "wdth": 100 })
        color: Appearance.colors.colOnLayer1
    }

    Rectangle { // Card
        Layout.fillWidth: true
        implicitHeight: sectionContent.implicitHeight + sectionContent.anchors.margins * 2
        radius: Appearance.rounding.normal
        color: root.card ? Appearance.colors.colLayer2 : "transparent"

        SeparatedColumn {
            id: sectionContent
            separators: root.card
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: root.card ? 4 : 0
            }
        }
    }

    StyledText { // Footnote
        visible: root.description.length > 0
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        text: root.description
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
    }
}
