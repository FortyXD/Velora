import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

QuickToggleModel {
    name: Translation.tr("Audio output")
    statusText: !Audio.sink?.audio ? Translation.tr("No output device") : toggled ? Translation.tr("Unmuted") : Translation.tr("Muted")
    tooltipText: Translation.tr("Audio output | Right-click for volume mixer & device selector")
    toggled: !!Audio.sink?.audio && !Audio.sink.audio.muted
    available: Audio.outputDevices.length > 0
    icon: !Audio.sink?.audio || Audio.sink.audio.muted ? "volume_off" : "volume_up"
    mainAction: () => {
        Audio.toggleMute()
    }
    hasMenu: true
}
