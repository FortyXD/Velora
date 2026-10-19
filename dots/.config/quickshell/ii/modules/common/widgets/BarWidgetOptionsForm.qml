import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Options of one bar item, built from its catalog entry. Instance options are stored in the item,
 * the others are shared settings named by their scope (see BarWidgetCatalog).
 */
ColumnLayout {
    id: root

    required property string orientation
    required property var item // Layout item { uid, type, options }
    readonly property var specs: BarWidgetCatalog.get(item?.type ?? "")?.options ?? []

    spacing: 4
    visible: specs.length > 0

    Repeater {
        model: root.specs
        delegate: Loader {
            id: optionLoader
            required property var modelData
            readonly property var value: BarWidgetCatalog.optionValue(root.item, modelData)
            Layout.fillWidth: true
            sourceComponent: {
                switch (modelData.kind) {
                case "switch": return switchOption;
                case "spin": return spinOption;
                case "choice": return choiceOption;
                default: return textOption;
                }
            }

            function set(value) {
                BarLayout.setOptionValue(root.orientation, root.item.uid, optionLoader.modelData, value);
            }

            Component {
                id: switchOption
                ConfigSwitch {
                    buttonIcon: "toggle_on"
                    text: optionLoader.modelData.label
                    autoToggle: false
                    checked: !!optionLoader.value
                    onClicked: optionLoader.set(!optionLoader.value)
                }
            }

            Component {
                id: spinOption
                ConfigSpinBox {
                    icon: "tune"
                    text: optionLoader.modelData.label
                    from: optionLoader.modelData.from ?? 0
                    to: optionLoader.modelData.to ?? 100
                    stepSize: 1
                    value: optionLoader.value ?? optionLoader.modelData.from ?? 0
                    onValueChanged: if (value !== optionLoader.value) optionLoader.set(value)
                }
            }

            Component {
                id: choiceOption
                ConfigComboRow {
                    icon: "list"
                    text: optionLoader.modelData.label
                    currentValue: optionLoader.value
                    options: (optionLoader.modelData.choices ?? []).map(choice => ({
                        "value": choice.value, "displayName": choice.name, "icon": choice.icon ?? ""
                    }))
                    onSelected: value => optionLoader.set(value)
                }
            }

            Component {
                id: textOption
                ConfigTextRow {
                    icon: optionLoader.modelData.kind === "command" ? "terminal" : "edit"
                    label: optionLoader.modelData.label
                    monospace: optionLoader.modelData.kind === "command"
                    value: optionLoader.value ?? ""
                    onEditingFinished: if (value !== (optionLoader.value ?? "")) optionLoader.set(value)
                }
            }
        }
    }
}
