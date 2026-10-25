import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Energy saving")
    statusText: PowerSaving.statusText
    toggled: PowerSaving.active
    icon: "energy_savings_leaf"
    mainAction: () => PowerSaving.toggle()
    altAction: () => {
        GlobalStates.closeSidebars();
        PowerSaving.openSettings();
    }
    tooltipText: Translation.tr("Energy saving | Right-click for settings")
}
