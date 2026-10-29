import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

/**
 * Software Update, opened from General: where Velora stands against GitHub, and how it checks.
 */
ContentPage {
    id: root

    property var updateStatus: ({})
    property var updateSettings: ({ channel: "branch", automatic_checks: true })
    property string updateError: ""
    readonly property string veloraCommand: Quickshell.shellPath("scripts/maintenance/velora.sh")
    readonly property bool busy: checkVeloraUpdates.running || saveUpdateSettings.running || loadUpdateSettings.running

    function configureUpdates(options) {
        root.updateError = "";
        saveUpdateSettings.command = [root.veloraCommand, "update-settings", ...options];
        saveUpdateSettings.running = true;
    }

    // Written by the velora command (scripts/velora.py), also when the timer checks in the background
    readonly property string veloraStateDir: `${Quickshell.env("XDG_STATE_HOME") || `${FileUtils.trimFileProtocol(Directories.home)}/.local/state`}/velora`

    FileView {
        id: updateStateFile
        path: `${root.veloraStateDir}/update.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.updateStatus = JSON.parse(text()); }
            catch (error) { root.updateStatus = ({ error: "Could not read update status" }); }
        }
    }

    Process {
        id: checkVeloraUpdates
        command: [root.veloraCommand, "update", "--check"]
        stderr: StdioCollector { onStreamFinished: root.updateError = text.trim() }
        onExited: (exitCode, exitStatus) => updateStateFile.reload()
    }

    Process {
        id: loadUpdateSettings
        running: true
        command: [root.veloraCommand, "update-settings"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.updateSettings = JSON.parse(text); }
                catch (error) { root.updateError = "Could not read update preferences"; }
            }
        }
        stderr: StdioCollector { onStreamFinished: root.updateError = text.trim() }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && root.updateSettings.automatic_checks && !checkVeloraUpdates.running)
                checkVeloraUpdates.running = true;
        }
    }

    Process {
        id: saveUpdateSettings
        stderr: StdioCollector { onStreamFinished: root.updateError = text.trim() }
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                loadUpdateSettings.running = true;
                root.updateStatus = ({});
            }
        }
    }

    component ActionButton: RippleButtonWithIcon {
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
    }

    // Where Velora stands, and what can be done about it
    ContentSection {
        icon: "system_update"
        title: ""
        searchText: `${Translation.tr("Software Update")} ${Translation.tr("Check for updates")} ${Translation.tr("Install update")}`

        RowLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 16

            Rectangle {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 56
                implicitHeight: 56
                radius: 15
                color: Appearance.colors.colPrimaryContainer
                VeloraLogo {
                    anchors.centerIn: parent
                    size: 28
                    color: Appearance.colors.colOnPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 3

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: checkVeloraUpdates.running ? Translation.tr("Checking for updates…")
                        : root.updateError || root.updateStatus.error ? Translation.tr("Couldn't check for updates")
                        : root.updateStatus.diverged ? Translation.tr("Your branch has diverged. Merge your changes before updating.")
                        : root.updateStatus.dirty && root.updateStatus.available ? Translation.tr("An update is available. Commit your local changes before installing it.")
                        : root.updateStatus.available ? Translation.tr("An update is available.")
                        : root.updateStatus.checked_at ? Translation.tr("Velora is up to date.")
                        : Translation.tr("Run the Velora installer to enable update checks.")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                }
                StyledText { // Why the check failed
                    Layout.fillWidth: true
                    readonly property string reason: root.updateError || root.updateStatus.error || ""
                    visible: !checkVeloraUpdates.running && reason.length > 0
                    wrapMode: Text.Wrap
                    text: reason
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colError
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: !!root.updateStatus.current_version
                    wrapMode: Text.Wrap
                    text: [
                        `${Translation.tr("Installed")}: ${root.updateStatus.current_version ?? ""} (${(root.updateStatus.current ?? "").slice(0, 12)})`,
                        ...(root.updateStatus.available ? [`${Translation.tr("Latest")}: ${root.updateStatus.latest_version ?? ""}`] : []),
                        ...(root.updateStatus.checked_at ? [`${Translation.tr("Checked")}: ${Qt.locale().toString(new Date(root.updateStatus.checked_at), "d MMM, " + Config.options.time.format)}`] : []),
                    ].join(" · ")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 12
            spacing: 6
            ActionButton {
                materialIcon: "download"
                mainText: Translation.tr("Install update")
                visible: !!root.updateStatus.available
                enabled: !root.updateStatus.diverged && !root.updateStatus.dirty && !root.updateStatus.error && !root.busy
                onClicked: Quickshell.execDetached(["kitty", "--hold", "--title", "Velora update",
                    root.veloraCommand, "update", "--interactive"])
            }
            ActionButton {
                materialIcon: "refresh"
                mainText: Translation.tr("Check for updates")
                enabled: !checkVeloraUpdates.running && !saveUpdateSettings.running
                onClicked: {
                    root.updateError = "";
                    checkVeloraUpdates.running = true;
                }
            }
            ActionButton {
                materialIcon: "open_in_new"
                mainText: Translation.tr("Release notes")
                visible: !!root.updateStatus.release_url
                onClicked: Qt.openUrlExternally(root.updateStatus.release_url)
            }
        }
    }

    ContentSection {
        icon: "update"
        title: Translation.tr("GitHub updates")
        description: Translation.tr("Check for new Velora versions and install them when you are ready.")

        ConfigSwitch {
            buttonIcon: "update"
            text: Translation.tr("Check for updates automatically")
            description: Translation.tr("Check on opening this page and every six hours in the background.")
            checked: root.updateSettings.automatic_checks ?? true
            autoToggle: false
            enabled: !root.busy
            onClicked: root.configureUpdates(["--automatic-checks", checked ? "off" : "on"])
        }

        ConfigSwitch {
            buttonIcon: "new_releases"
            text: Translation.tr("Use published GitHub releases")
            description: Translation.tr("Choose stable releases. Turn off to follow the latest changes on your tracked branch.")
            checked: root.updateSettings.channel === "release"
            autoToggle: false
            enabled: !root.busy
            onClicked: root.configureUpdates(["--channel", checked ? "branch" : "release"])
        }
    }
}
