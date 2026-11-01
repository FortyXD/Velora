pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland

import qs.modules.common
import qs.modules.common.functions

/**
 * Configs Hyprland
 */
Singleton {
    id: root
    
    signal reloaded()

    readonly property string configuratorScriptPath: Quickshell.shellPath("scripts/helper")
    readonly property string shellOverridesPath: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hyprland/shellOverrides/main.lua`)

    function set(key: string, value: var) {
        Quickshell.execDetached([root.configuratorScriptPath, "hypr-config", "--file", root.shellOverridesPath,
            "--set", key, String(value)]);
    }
    
    function setMany(entries: var) {
        let args = [];
        for (let key in entries) {
            args.push("--set", key, String(entries[key]));
        }
        Quickshell.execDetached([root.configuratorScriptPath, "hypr-config", "--file", root.shellOverridesPath, ...args]);
    }
    
    function reset(key: string) {
        Quickshell.execDetached([root.configuratorScriptPath, "hypr-config", "--file", root.shellOverridesPath, "--reset", key]);
    }
    
    function resetMany(keys: list<string>) {
        let args = [];
        for (let i = 0; i < keys.length; i++) {
            args.push("--reset", keys[i]);
        }
        Quickshell.execDetached([root.configuratorScriptPath, "hypr-config", "--file", root.shellOverridesPath, ...args]);
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name == "configreloaded") {
                root.reloaded()
            }
        }
    }
}
