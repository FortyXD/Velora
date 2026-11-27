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
    implicitWidth: 320
    implicitHeight: buttons.implicitHeight + 10
    color: "transparent"

    Flow {
        id: buttons
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(1, root.width - 10)
        spacing: 5
        // Which and in what order: Config.options.sidebar.quickToggles.classic.toggles
        Repeater {
            model: SidebarLayout.classicToggles()
            delegate: DelegateChooser {
                role: "modelData"
                DelegateChoice {
                    roleValue: "network"
                    NetworkToggle {
                        toggleType: "network"
                        altAction: () => {
                            root.openWifiDialog();
                        }
                    }
                }
                DelegateChoice {
                    roleValue: "bluetooth"
                    BluetoothToggle {
                        toggleType: "bluetooth"
                        altAction: () => {
                            root.openBluetoothDialog();
                        }
                    }
                }
                DelegateChoice { roleValue: "nightLight"; NightLight { toggleType: "nightLight" } }
                DelegateChoice { roleValue: "gameMode"; GameMode { toggleType: "gameMode" } }
                DelegateChoice { roleValue: "idleInhibitor"; IdleInhibitor { toggleType: "idleInhibitor" } }
                DelegateChoice { roleValue: "powerSaving"; PowerSavingToggle { toggleType: "powerSaving" } }
                DelegateChoice { roleValue: "easyEffects"; EasyEffectsToggle { toggleType: "easyEffects" } }
                DelegateChoice { roleValue: "cloudflareWarp"; CloudflareWarp { toggleType: "cloudflareWarp" } }
            }
        }
    }
}
