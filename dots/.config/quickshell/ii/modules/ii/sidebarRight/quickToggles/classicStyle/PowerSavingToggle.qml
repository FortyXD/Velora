import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

QuickToggleButton {
    toggled: PowerSaving.active
    buttonIcon: "energy_savings_leaf"
    onClicked: PowerSaving.toggle()
    altAction: () => {
        GlobalStates.closeSidebars();
        PowerSaving.openSettings();
    }
    StyledToolTip {
        text: Translation.tr("Energy saving: %1").arg(PowerSaving.statusText)
    }
}
