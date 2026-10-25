import QtQuick
import QtQuick.Layouts
import qs.modules.common

/**
 * A part of a settings page that scrolls on its own, for pages that keep a preview or tabs in place
 * (ContentPage.fitToWindow). Children are laid out in a column as wide as the pane.
 * ContentPage.revealItem() finds the pane an option sits in and scrolls it.
 */
StyledFlickable {
    id: root
    readonly property bool settingsScroller: true
    property real bottomPadding: 40
    property alias spacing: column.spacing
    default property alias contentData: column.data

    signal userScrolled()

    clip: true
    contentWidth: width
    contentHeight: column.implicitHeight + root.bottomPadding
    onMovementStarted: root.userScrolled()
    Connections {
        target: root.wheelArea
        function onUserScrolled() { root.userScrolled() }
    }

    function scrollTo(y) {
        scrollAnim.stop();
        scrollAnim.to = y;
        scrollAnim.start();
    }
    function stopScroll() {
        scrollAnim.stop();
    }

    ColumnLayout {
        id: column
        width: root.width
        spacing: 22
    }

    NumberAnimation { // Not the scroll Behavior, so a wheel animation can't swallow it
        id: scrollAnim
        target: root
        property: "contentY"
        duration: 450
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
    }
}
