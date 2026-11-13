import QtQuick
import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root
    property string symbol: "more_horiz"
    property string tooltip: ""
    property color foreground: root.enabled ? (root.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1) : Appearance.colors.colSubtext
    implicitWidth: 36
    implicitHeight: 36
    buttonRadius: Appearance.rounding.full
    Accessible.name: tooltip
    contentItem: MaterialSymbol {
        text: root.symbol
        iconSize: 20
        color: root.foreground
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    StyledToolTip { text: root.tooltip }
}
