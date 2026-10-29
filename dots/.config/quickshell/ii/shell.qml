//@ pragma UseQApplication
//@ pragma Env QS_NO_RELOAD_POPUP=1
//@ pragma Env QT_FFMPEG_DECODING_HW_DEVICE_TYPES=vaapi
//@ pragma Env QT_FFMPEG_ENCODING_HW_DEVICE_TYPES=vaapi
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000

// Remove two slashes below and adjust the value to change the UI scale
////@ pragma Env QT_SCALE_FACTOR=1

import "modules/common"
import "modules/common/panels"
import "services"
import "panelFamilies"

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // Stuff for every panel family
    ReloadPopup {}
    ThemeTransitionOverlay {}

    // `qs -c ii ipc call themeTransition test`: the wave alone, over an unchanged screen
    IpcHandler {
        target: "themeTransition"
        function test(): void {
            ThemeTransition.run(() => {});
        }
    }
    // Free or tiled windows; from the settings app, so the change happens under the shell's wave
    IpcHandler {
        target: "windowMode"
        function set(mode: string): void {
            HyprlandSettings.setWindowMode(mode === "floating" ? "floating" : "tiling");
        }
        function get(): string {
            return HyprlandSettings.windowMode;
        }
    }

    Component.onCompleted: {
        MaterialThemeLoader.reapplyTheme()
        Hyprsunset.load()
        FirstRunExperience.load()
        ConflictKiller.load()
        Cliphist.refresh()
        Wallpapers.load()
        Updates.load()
        Presets.load()
        OnlineWallpapers.load()
        WallpaperOfTheDay.load()
        PowerSaving.load()
        LiveWallpaper.load()
        Audio.load()
        HotCorners.load()
        TimerService.load()
        Weather.load()
        TouchpadGestures.libraryProgress // Listens for gestures from hyprland/gestures.lua
    }


    // Panel families
    property list<string> families: ["ii", "waffle"]
    function cyclePanelFamily() {
        const currentIndex = families.indexOf(Config.options.panelFamily)
        const nextIndex = (currentIndex + 1) % families.length
        Config.options.panelFamily = families[nextIndex]
    }

    component PanelFamilyLoader: LazyLoader {
        required property string identifier
        property bool extraCondition: true
        active: Config.ready && Config.options.panelFamily === identifier && extraCondition
    }
    
    PanelFamilyLoader {
        identifier: "ii"
        component: IllogicalImpulseFamily {}
    }

    PanelFamilyLoader {
        identifier: "waffle"
        component: WaffleFamily {}
    }


    // Shortcuts
    IpcHandler {
        target: "panelFamily"

        function cycle(): void {
            root.cyclePanelFamily()
        }
    }

    GlobalShortcut {
        name: "panelFamilyCycle"
        description: "Cycles panel family"

        onPressed: root.cyclePanelFamily()
    }
}

