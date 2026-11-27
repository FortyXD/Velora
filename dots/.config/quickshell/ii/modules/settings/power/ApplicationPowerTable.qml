pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ColumnLayout {
    id: root
    required property var samples
    readonly property var rows: (samples.rows ?? []).filter(row => row.name.toLowerCase().includes(filter.text.trim().toLowerCase()))
    spacing: 6
    StyledText {
        text: Translation.tr("Application power")
        color: Appearance.colors.colOnLayer2
        font.pixelSize: Appearance.font.pixelSize.large
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.samples.source === "package" ? Translation.tr("CPU package watts apportioned by each application's share of CPU time.")
            : root.samples.source === "battery" ? Translation.tr("Estimates use battery discharge and each application's share of CPU time.")
            : root.samples.source === "sampling" ? Translation.tr("Collecting the first interval…") : Translation.tr("Power readings are unavailable. CPU activity is shown.")
        color: Appearance.colors.colSubtext
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        visible: root.samples.battery_w != null
        text: visible ? Translation.tr("Battery %1 W · Applications ≈%2 W · System and devices ≈%3 W")
            .arg(root.samples.battery_w.toFixed(2)).arg(root.samples.applications_w.toFixed(2)).arg(root.samples.system_w.toFixed(2)) : ""
    }
    MaterialTextField {
        id: filter
        Layout.fillWidth: true
        placeholderText: Translation.tr("Filter applications")
    }
    RowLayout {
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: Translation.tr("Application") }
        StyledText { Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight; text: "CPU %" }
        StyledText { Layout.preferredWidth: 90; horizontalAlignment: Text.AlignRight; text: Translation.tr("Estimated W") }
    }
    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(220, contentHeight)
        clip: true
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }
        delegate: RowLayout {
            required property var modelData
            width: list.width - 10
            height: 28
            StyledText { Layout.fillWidth: true; text: parent.modelData.name; textFormat: Text.PlainText; elide: Text.ElideRight }
            StyledText { Layout.preferredWidth: 64; horizontalAlignment: Text.AlignRight; text: parent.modelData.cpu.toFixed(1) }
            StyledText { Layout.preferredWidth: 80; horizontalAlignment: Text.AlignRight; text: parent.modelData.watts == null ? "—" : parent.modelData.watts.toFixed(2) }
        }
    }
    StyledText {
        visible: filter.text.length > 0 && root.rows.length === 0
        text: Translation.tr("No matching applications")
        color: Appearance.colors.colSubtext
    }
}
