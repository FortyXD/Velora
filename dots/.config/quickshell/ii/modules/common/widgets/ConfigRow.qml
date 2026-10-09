import QtQuick
import QtQuick.Layouts

/**
 * Groups related rows. They are listed one under another with separators.
 * `uniform` and `stackBelow` are kept for compatibility and have no effect.
 */
SeparatedColumn {
    property bool uniform: false
    property real stackBelow: 0
    Layout.fillWidth: true
}
