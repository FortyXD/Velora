pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    function dismiss() {
        ScreenRecorder.regionSelecting = false;
        GlobalStates.regionSelectorOpen = false
    }

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData
            active: GlobalStates.regionSelectorOpen

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                onDismiss: root.dismiss()
                action: root.action
                selectionMode: root.selectionMode
            }
        }
    }

    function screenshot() {
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    function search() {
        root.action = RegionSelection.SnipAction.Search
        if (Config.options.search.imageSearch.useCircleSelection) {
            root.selectionMode = RegionSelection.SelectionMode.Circle
        } else {
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        }
        GlobalStates.regionSelectorOpen = true
    }

    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    Connections {
        target: ScreenRecorder
        function onRegionRequested(sound) {
            if (sound === "both") root.recordWithMic();
            else if (sound === "system") root.recordWithSound();
            else root.record();
        }
    }

    function openRecording(action) {
        if (ScreenRecorder.active) { ScreenRecorder.stop(); root.dismiss(); return; }
        GlobalStates.regionSelectorOpen = false;
        root.action = action;
        root.selectionMode = RegionSelection.SelectionMode.RectCorners;
        ScreenRecorder.regionSelecting = true;
        GlobalStates.regionSelectorOpen = true;
    }
    function record() { root.openRecording(RegionSelection.SnipAction.Record); }
    function recordWithSound() { root.openRecording(RegionSelection.SnipAction.RecordWithSound); }
    function recordWithMic() { root.openRecording(RegionSelection.SnipAction.RecordWithMic); }

    IpcHandler {
        target: "region"

        function screenshot() {
            root.screenshot()
        }
        function search() {
            root.search()
        }
        function ocr() {
            root.ocr()
        }
        function record() {
            root.record()
        }
        function recordWithSound() {
            root.recordWithSound()
        }
        function recordWithMic() { root.recordWithMic(); }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshot()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record()
    }
    GlobalShortcut {
        name: "regionRecordWithMic"
        description: "Records the selected region with system sound and microphone"
        onPressed: root.recordWithMic()
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.recordWithSound()
    }
}
