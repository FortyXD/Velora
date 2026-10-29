pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import Quickshell.Io

/**
 * The first login: the setup assistant (onboarding.qml) starts by itself. It's started when it has
 * never finished (~/.local/state/velora/onboarding.json) on a desktop that was never greeted
 * (state/user/first_run.txt), so an update doesn't spring it on people already set up; they get one
 * notification about it instead.
 */
Singleton {
    id: root
    property string firstRunFilePath: `${Directories.state}/user/first_run.txt`
    property string firstRunFileContent: "This file is just here to confirm you've been greeted :>"
    property string defaultWallpaperPath: FileUtils.trimFileProtocol(`${Directories.assetsPath}/images/default_wallpaper.png`)
    readonly property string onboardingPath: FileUtils.trimFileProtocol(Quickshell.shellPath("onboarding.qml"))
    readonly property string onboardingStatePath: `${FileUtils.trimFileProtocol(Directories.home)}/.local/state/velora/onboarding.json`
    readonly property string announcedPath: `${FileUtils.trimFileProtocol(Directories.home)}/.local/state/velora/onboarding-announced`

    function load() {
        onboardingState.reload();
    }

    function openOnboarding() {
        Quickshell.execDetached(["qs", "-p", root.onboardingPath]);
    }

    // Not finished: greeted before (an existing desktop) gets told about it once; a new one gets it
    function decide(finished) {
        if (finished) return;
        if (!firstRunFile.loaded) {
            firstRunFile.setText(root.firstRunFileContent);
            // A wallpaper and its colors to start from; the assistant offers others
            initialWallpaper.running = true;
            return;
        }
        announce.running = true;
    }

    Process {
        id: initialWallpaper
        command: [Directories.wallpaperSwitchScriptPath, root.defaultWallpaperPath]
        // Finish the initial wallpaper job before setup can apply Autumn or a user's choice.
        onRunningChanged: if (!running) Qt.callLater(root.openOnboarding)
    }

    FileView {
        id: onboardingState
        path: root.onboardingStatePath
        printErrors: false
        onLoaded: {
            let state = {};
            try {
                state = JSON.parse(onboardingState.text());
            } catch (error) {}
            // Stopped halfway: carry on where it was
            if (!state.completed && !state.skipped) root.openOnboarding();
        }
        onLoadFailed: firstRunFile.reload()
    }
    FileView {
        id: firstRunFile
        path: Qt.resolvedUrl(root.firstRunFilePath)
        printErrors: false
        property bool loaded: false
        onLoaded: {
            firstRunFile.loaded = true;
            root.decide(false);
        }
        onLoadFailed: root.decide(false)
    }
    Process {
        id: announce
        command: ["bash", "-c", '[ -e "$1" ] && exit 0; mkdir -p "$(dirname "$1")" && touch "$1" && '
            + 'action=$(notify-send -a Velora -i preferences-desktop -A setup="$2" "$3" "$4") && [ "$action" = setup ] && qs -p "$5"',
            "_", root.announcedPath, Translation.tr("Open setup"), Translation.tr("New: setup assistant and a quick tour"),
            Translation.tr("Choose a desktop layout, free or tiled windows, and learn the shortcuts. Shift+Super+Alt+/ opens it any time."),
            root.onboardingPath]
    }
}
