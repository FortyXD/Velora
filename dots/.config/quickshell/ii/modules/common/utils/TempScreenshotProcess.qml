import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Process {
    id: screenshotProc
    running: true
    property string screenshotDir: Directories.screenshotTemp
    required property ShellScreen screen
    property string screenshotPath: `${screenshotDir}/image-${screen.name}`
    // Non-screenshot consumers (e.g. screen translation) keep a clean source.
    property bool includeCursor: false
    environment: ({ VELORA_SCREENSHOT_CURSOR: screenshotProc.includeCursor ? "true" : "false" })
    command: ["bash", "-c", `mkdir -p '${StringUtils.shellSingleQuoteEscape(screenshotDir)}' && '${StringUtils.shellSingleQuoteEscape(Directories.scriptPath + "/images/screenshot.sh")}' -o '${StringUtils.shellSingleQuoteEscape(screen.name)}' '${StringUtils.shellSingleQuoteEscape(screenshotPath)}'`]
}
