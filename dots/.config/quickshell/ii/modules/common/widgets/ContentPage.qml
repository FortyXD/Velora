import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledFlickable {
    id: root
    property real baseWidth: 600
    property bool forceWidth: false
    property real maxContentWidth: 760
    property real horizontalPadding: 28
    property real topContentPadding: 16
    property real bottomContentPadding: 100

    // Optional header card at the top of the page
    property string heroIcon: ""
    property real heroIconRotation: 0
    property string heroTitle: ""
    property string heroDescription: ""
    property color heroColor: Appearance.colors.colPrimary

    default property alias contentData: contentColumn.data

    property bool pageShown: true // False while another settings page is in front
    signal revealCancelled() // The user scrolled, so nothing should pull the page to a revealed item any more

    clip: true
    contentHeight: contentColumn.implicitHeight + root.topContentPadding + root.bottomContentPadding
    implicitWidth: contentColumn.implicitWidth

    // Scrolls so that `item` (anything inside this page) is in view and briefly outlines it.
    // Whatever keeps it out of sight first gets a chance to show it: an ancestor with a
    // `settingsReveal()` function (folded rows, one of several panels) returns true when it changed.
    function revealItem(item, highlight = true) {
        if (!item) return;
        let unfolded = false;
        for (let node = item.parent; node && node !== root; node = node.parent) {
            if (typeof node.settingsReveal === "function" && node.settingsReveal()) unfolded = true;
        }
        if (unfolded) { // Reveal once the page is laid out again
            pendingReveal.item = item;
            pendingReveal.highlight = highlight;
            pendingReveal.restart();
            return;
        }
        const pos = item.mapToItem(contentColumn, 0, 0);
        const maxY = Math.max(0, root.contentHeight - root.height);
        const targetY = Math.max(0, Math.min(pos.y + contentColumn.y - 64, maxY));
        if (Math.abs(root.contentY - targetY) > 1) {
            revealScrollAnim.stop();
            revealScrollAnim.to = targetY;
            revealScrollAnim.start();
        }
        if (!highlight) return;
        revealHighlight.x = contentColumn.x + pos.x - 4;
        revealHighlight.y = contentColumn.y + pos.y - 4;
        revealHighlight.width = item.width + 8;
        revealHighlight.height = item.height + 8;
        revealHighlightAnim.restart();
    }

    function cancelReveal() {
        pendingReveal.stop();
        revealScrollAnim.stop();
        root.revealCancelled();
    }
    onMovementStarted: root.cancelReveal()
    Connections {
        target: root.wheelArea
        function onUserScrolled() { root.cancelReveal() }
    }

    ColumnLayout {
        id: contentColumn
        y: root.topContentPadding
        x: Math.round((root.width - width) / 2)
        width: root.forceWidth ? root.baseWidth : Math.max(0, Math.min(root.maxContentWidth, root.width - root.horizontalPadding * 2))
        spacing: 22

        Rectangle { // Hero
            visible: root.heroTitle.length > 0
            Layout.fillWidth: true
            implicitHeight: heroColumn.implicitHeight + 44
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer2

            ColumnLayout {
                id: heroColumn
                anchors.centerIn: parent
                width: Math.min(480, parent.width - 40)
                spacing: 6

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 4
                    implicitWidth: 64
                    implicitHeight: 64
                    radius: 19
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.lighter(root.heroColor, 1.15) }
                        GradientStop { position: 1; color: root.heroColor }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.heroIcon
                        rotation: root.heroIconRotation
                        iconSize: 38
                        fill: 1
                        color: "white"
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.heroTitle
                    wrapMode: Text.Wrap
                    font {
                        family: Appearance.font.family.title
                        pixelSize: 22
                        variableAxes: Appearance.font.variableAxes.title
                    }
                    color: Appearance.colors.colOnLayer2
                }
                StyledText {
                    visible: root.heroDescription.length > 0
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.heroDescription
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    Timer {
        id: pendingReveal
        property var item: null
        property bool highlight: true
        interval: 50
        onTriggered: root.revealItem(item, highlight)
    }

    NumberAnimation { // Not the scroll Behavior, so a wheel animation can't swallow it
        id: revealScrollAnim
        target: root
        property: "contentY"
        duration: 450
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }

    Rectangle {
        id: revealHighlight
        z: 10
        opacity: 0
        visible: opacity > 0
        color: "transparent"
        radius: Appearance.rounding.large
        border.width: 2
        border.color: Appearance.colors.colPrimary

        SequentialAnimation {
            id: revealHighlightAnim
            PauseAnimation { duration: 180 }
            NumberAnimation { target: revealHighlight; property: "opacity"; to: 1; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { target: revealHighlight; property: "opacity"; to: 0.25; duration: 260; easing.type: Easing.InOutCubic }
            NumberAnimation { target: revealHighlight; property: "opacity"; to: 1; duration: 260; easing.type: Easing.InOutCubic }
            PauseAnimation { duration: 500 }
            NumberAnimation { target: revealHighlight; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InCubic }
        }
    }
}
