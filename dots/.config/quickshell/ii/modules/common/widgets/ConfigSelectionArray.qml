import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Flow {
    id: root
    Layout.fillWidth: true
    Layout.leftMargin: 12
    Layout.rightMargin: 12
    Layout.topMargin: 2
    Layout.bottomMargin: 6
    spacing: 2
    property list<var> options: [
        {
            "displayName": "Option 1",
            "icon": "check",
            "value": 1
        },
        {
            "displayName": "Option 2",
            "icon": "close",
            "value": 2
        },
    ]
    property var currentValue: null

    signal selected(var newValue)

    // Pill ends go wherever a row of buttons starts or ends, also after wrapping
    function updateEdges() {
        for (let i = 0; i < repeater.count; i++) {
            const button = repeater.itemAt(i);
            if (!button) continue;
            const previous = i > 0 ? repeater.itemAt(i - 1) : null;
            const next = i < repeater.count - 1 ? repeater.itemAt(i + 1) : null;
            button.leftmost = !previous || previous.y !== button.y;
            button.rightmost = !next || next.y !== button.y;
        }
    }
    onPositioningComplete: root.updateEdges()

    Repeater {
        id: repeater
        model: root.options
        onItemAdded: Qt.callLater(root.updateEdges)
        delegate: SelectionGroupButton {
            required property var modelData
            required property int index
            leftmost: index === 0
            rightmost: index === root.options.length - 1
            buttonIcon: modelData.icon || ""
            buttonText: modelData.displayName
            toggled: root.currentValue == modelData.value
            onClicked: {
                root.selected(modelData.value);
            }
        }
    }
}
