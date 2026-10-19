import qs.modules.common
import qs.modules.ii.bar.widgets
import QtQuick
import QtQuick.Layouts

// The quick buttons chosen under Bar → Utility buttons, in their usual order
Item {
    id: root
    property bool borderless: Config.options.bar.borderless
    readonly property var buttons: Config.options.bar.utilButtons
    implicitWidth: rowLayout.implicitWidth + rowLayout.spacing * 2
    implicitHeight: rowLayout.implicitHeight

    RowLayout {
        id: rowLayout

        spacing: 4
        anchors.centerIn: parent

        Repeater {
            model: BarWidgetCatalog.utilButtonKinds.filter(entry => root.buttons[entry.option])
            delegate: UtilButton {
                required property var modelData
                kind: modelData.kind
            }
        }
    }
}
