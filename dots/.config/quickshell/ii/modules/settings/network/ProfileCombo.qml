import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** A setting of the profile being edited with a fixed set of values. */
ConfigComboRow {
    id: root
    required property string fieldKey
    property var defaultValue: ""
    currentValue: ProfileEditor.value(root.fieldKey, root.defaultValue)
    onSelected: value => ProfileEditor.set(root.fieldKey, value)
}
