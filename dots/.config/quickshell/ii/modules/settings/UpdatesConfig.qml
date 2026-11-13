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
    property var installation: ({})
    property bool showUpdateDetails: false
    readonly property bool installing: installation.status === "starting" || installation.status === "running"
    readonly property string veloraCommand: Quickshell.shellPath("scripts/maintenance/velora.sh")
    readonly property bool busy: installing || startInstallation.running || checkVeloraUpdates.running || saveUpdateSettings.running || loadUpdateSettings.running

    function installUpdate() {
        root.updateError = "";
        root.installation = ({ status: "starting", phase: "checking" });
        startInstallation.running = true;
    }

    function installMessage() {
        if (installation.phase === "authorizing") return Translation.tr("Waiting for administrator authorization…");
        if (installation.phase === "installing") return Translation.tr("Installing the update and its dependencies…");
        return Translation.tr("Preparing the update…");
    }

    function configureUpdates(options) {
        root.updateError = "";
        saveUpdateSettings.command = [root.veloraCommand, "update-settings", ...options];
        saveUpdateSettings.running = true;
    }

    // Written by the velora command (scripts/velora.py), also when the timer checks in the background
    readonly property string veloraStateDir: `${Quickshell.env("XDG_STATE_HOME") || `${FileUtils.trimFileProtocol(Directories.home)}/.local/state`}/velora`

    FileView {
        id: installationFile
        path: `${root.veloraStateDir}/gui-update.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                root.installation = JSON.parse(text());
                if (root.installation.status === "succeeded") updateStateFile.reload();
            } catch (error) {}
        }
    }

    Process {
        id: startInstallation
        command: [root.veloraCommand, "update", "--gui"]
        stderr: StdioCollector { onStreamFinished: { if (text.trim()) root.updateError = text.trim(); } }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) root.installation = ({ status: "failed" });
            installationFile.reload();
        }
    }

    Process {
        id: readInstallation
        running: true
        command: [root.veloraCommand, "update", "--gui-status"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.installation = JSON.parse(text); } catch (error) {} }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.installing
        onTriggered: { if (!readInstallation.running) readInstallation.running = true; }
    }

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
            if (exitCode === 0 && root.updateSettings.automatic_checks && !checkVeloraUpdates.running && !root.installing)
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
                    text: root.installing ? root.installMessage()
                        : root.installation.status === "failed" ? Translation.tr("The update did not finish. You can retry it.")
                        : root.installation.status === "succeeded" && !root.updateStatus.available ? Translation.tr("Update installed.")
                        : checkVeloraUpdates.running ? Translation.tr("Checking for updates…")
                        : root.updateError || root.updateStatus.error ? Translation.tr("Couldn't check for updates")
                        : root.updateStatus.diverged ? Translation.tr("This installation has custom changes. Automatic updates are paused to preserve them.")
                        : root.updateStatus.dirty && root.updateStatus.available ? Translation.tr("Local changes were detected. Automatic updates are paused to preserve them.")
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

        ColumnLayout {
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 8
            visible: root.installing || root.installation.status === "succeeded" || root.showUpdateDetails
            StyledIndeterminateProgressBar {
                Layout.fillWidth: true
                visible: root.installing
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.installing || root.installation.status === "succeeded"
                wrapMode: Text.Wrap
                text: root.installing
                    ? Translation.tr("You can close Settings. Authorization is requested only when system changes need it.")
                    : Translation.tr("Reopen running applications to load their changes.")
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.showUpdateDetails
                wrapMode: Text.WrapAnywhere
                text: (root.installation.tail || []).join("\n") || root.installation.error || ""
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
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
                mainText: root.installation.status === "failed" ? Translation.tr("Retry update") : Translation.tr("Install update")
                visible: !!root.updateStatus.available || root.installation.status === "failed"
                enabled: !root.updateStatus.diverged && !root.updateStatus.dirty && !root.busy
                onClicked: root.installUpdate()
            }
            ActionButton {
                materialIcon: "refresh"
                mainText: Translation.tr("Check for updates")
                enabled: !root.busy
                onClicked: {
                    root.updateError = "";
                    checkVeloraUpdates.running = true;
                }
            }
            ActionButton {
                materialIcon: "description"
                mainText: root.showUpdateDetails ? Translation.tr("Hide details") : Translation.tr("Show details")
                visible: !!root.installation.status
                onClicked: root.showUpdateDetails = !root.showUpdateDetails
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
