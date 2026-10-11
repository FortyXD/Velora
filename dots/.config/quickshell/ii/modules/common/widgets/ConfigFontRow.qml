import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Settings row that picks an installed font. Each family in the list is drawn in itself.
 * kind: "any", "monospace" or "nerd" (fonts with Nerd Font icons).
 */
ConfigComboRow {
    id: root
    property string value: ""
    property string kind: "any"

    signal picked(string family)

    readonly property string listedValue: Fonts.listed(root.value)
    readonly property bool known: Fonts.families.includes(root.listedValue)

    maximumWidth: 260
    searchable: true
    currentValue: root.listedValue
    dropdown.displayText: root.value.length > 0 ? root.value : dropdown.placeholderText
    dropdown.displayIcon: root.value.length > 0 && !Fonts.installed(root.value) ? "error" : ""
    dropdown.displayFontFamily: Fonts.installed(root.value) ? root.value : ""
    dropdown.popupWidth: 340
    options: [
        ...(root.value.length > 0 && !root.known
            ? [{ displayName: root.value, value: root.value, icon: Fonts.installed(root.value) ? "" : "error",
                 description: Fonts.installed(root.value) ? "" : Translation.tr("Not installed") }] : []),
        ...Fonts.familiesFor(root.kind).map(family => ({ displayName: family, value: family, fontFamily: family }))
    ]
    onSelected: value => root.picked(value)
}
