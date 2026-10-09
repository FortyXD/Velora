import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions

/**
 * Column that draws thin separators between its visible children, like grouped lists in settings apps.
 * A child can opt out of the line above it with `property bool noSeparator: true`.
 */
Item {
    id: root
    default property alias contentData: column.data
    property alias spacing: column.spacing
    property bool separators: true
    property real separatorInset: 16

    implicitWidth: column.implicitWidth
    implicitHeight: column.implicitHeight

    // Top of the first visible row; nothing is drawn above it
    readonly property real firstRowY: {
        let top = Infinity;
        for (const child of column.visibleChildren) {
            if (child.height > 0) top = Math.min(top, child.y);
        }
        return top;
    }

    ColumnLayout {
        id: column
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        spacing: 0
    }

    Repeater {
        model: root.separators ? column.visibleChildren.length : 0
        delegate: Rectangle {
            id: separator
            required property int index
            readonly property Item target: column.visibleChildren[index] ?? null
            visible: target !== null && target.height > 0 && target.y > root.firstRowY + 0.5 && target.noSeparator !== true
            x: root.separatorInset
            y: target ? Math.round(target.y - column.spacing / 2) : 0
            width: Math.max(0, root.width - root.separatorInset * 2)
            height: 1
            color: ColorUtils.transparentize(Appearance.colors.colOutlineVariant, 0.3)
        }
    }
}
