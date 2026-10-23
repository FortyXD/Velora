import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Qt.labs.qmlmodels
import Quickshell.Bluetooth

import qs.modules.ii.sidebarRight.quickToggles.classicStyle

AbstractQuickPanel {
    id: root
    Layout.alignment: Qt.AlignHCenter
    implicitWidth: buttonGroup.implicitWidth
    implicitHeight: buttonGroup.implicitHeight
    color: "transparent"

    ButtonGroup {
        id: buttonGroup
        spacing: 5
        padding: 5
        color: Appearance.colors.colLayer1

        // Which and in what order: Config.options.sidebar.quickToggles.classic.toggles
        Repeater {
            model: SidebarLayout.classicToggles()
            delegate: DelegateChooser {
                role: "modelData"
                DelegateChoice {
                    roleValue: "network"
                    NetworkToggle {
                        altAction: () => {
                            root.openWifiDialog();
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "bluetooth"
                    BluetoothToggle {
                        altAction: () => {
                            root.openBluetoothDialog();
                        }
                    }
                }
                DelegateChoice { roleValue: "nightLight"; NightLight {} }
                DelegateChoice { roleValue: "gameMode"; GameMode {} }
                DelegateChoice { roleValue: "idleInhibitor"; IdleInhibitor {} }
                DelegateChoice { roleValue: "powerSaving"; PowerSavingToggle {} }
                DelegateChoice { roleValue: "easyEffects"; EasyEffectsToggle {} }
                DelegateChoice { roleValue: "cloudflareWarp"; CloudflareWarp {} }
            }
        }
    }
}
