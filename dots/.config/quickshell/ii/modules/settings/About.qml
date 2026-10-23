import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentPage {
    id: root

    property var updateStatus: ({})
    property var updateSettings: ({ channel: "branch", automatic_checks: true })
    property string updateError: ""
    readonly property string veloraCommand: Quickshell.shellPath("scripts/maintenance/velora.sh")

    function configureUpdates(options) {
        root.updateError = "";
        saveUpdateSettings.command = [root.veloraCommand, "update-settings", ...options];
        saveUpdateSettings.running = true;
    }

    FileView {
        id: updateStateFile
        path: FileUtils.trimFileProtocol(`${Directories.state}/velora/update.json`)
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

    component LinkButton: RippleButtonWithIcon {
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
    }

    // Logo, name and a link
    component IdentityRow: RowLayout {
        id: identity
        property alias logo: logoLoader.sourceComponent
        property string name
        property string subtitle
        property string link
        Layout.fillWidth: true
        Layout.margins: 12
        spacing: 18
        Loader {
            id: logoLoader
            Layout.alignment: Qt.AlignVCenter
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: identity.name
                elide: Text.ElideRight
                font {
                    family: Appearance.font.family.title
                    pixelSize: Appearance.font.pixelSize.title
                    variableAxes: Appearance.font.variableAxes.title
                }
                color: Appearance.colors.colOnLayer2
            }
            StyledText {
                visible: identity.subtitle.length > 0
                Layout.fillWidth: true
                text: identity.subtitle
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
            StyledText {
                visible: identity.link.length > 0
                Layout.fillWidth: true
                text: `[${identity.link.replace(/^https?:\/\//, "")}](${identity.link})`
                textFormat: Text.MarkdownText
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                onLinkActivated: link => Qt.openUrlExternally(link)
                PointingHandLinkHover {}
            }
        }
    }

    ContentSection {
        icon: "deployed_code"
        title: "Velora"
        description: Translation.tr("A desktop shaped around you. Built for Arch Linux, Hyprland and Quickshell.")

        IdentityRow {
            name: "Velora"
            subtitle: Translation.tr("Based on end-4/dots-hyprland (illogical-impulse)")
            link: "https://github.com/FortyXD/Velora"
            logo: Component {
                Item {
                    implicitWidth: 72
                    implicitHeight: 72
                    MaterialShape {
                        anchors.fill: parent
                        shape: MaterialShape.Shape.Cookie9Sided
                        color: Appearance.colors.colPrimaryContainer
                        RotationAnimation on rotation {
                            from: 0
                            to: 360
                            duration: 24000
                            loops: Animation.Infinite
                        }
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "eco"
                        iconSize: 34
                        fill: 1
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 12
            spacing: 6

            LinkButton {
                materialIcon: "code"
                mainText: Translation.tr("Repository")
                onClicked: Qt.openUrlExternally("https://github.com/FortyXD/Velora")
            }
            LinkButton {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: Qt.openUrlExternally("https://github.com/FortyXD/Velora#readme")
            }
            LinkButton {
                materialIcon: "adjust"
                materialIconFill: false
                mainText: Translation.tr("Report a Bug")
                onClicked: Qt.openUrlExternally("https://github.com/FortyXD/Velora/issues")
            }
            LinkButton {
                materialIcon: "forum"
                mainText: Translation.tr("Illogical Impulse")
                onClicked: Qt.openUrlExternally("https://github.com/end-4/dots-hyprland")
            }
            LinkButton {
                materialIcon: "favorite"
                mainText: Translation.tr("Support end-4")
                onClicked: Qt.openUrlExternally("https://github.com/sponsors/end-4")
            }
        }
    }

    ContentSection {
        icon: "system_update"
        title: Translation.tr("GitHub updates")
        description: Translation.tr("Check for new Velora versions and install them when you are ready.")

        ConfigSwitch {
            buttonIcon: "update"
            text: Translation.tr("Check for updates automatically")
            description: Translation.tr("Check on opening this page and every six hours in the background.")
            checked: root.updateSettings.automatic_checks ?? true
            autoToggle: false
            enabled: !saveUpdateSettings.running && !loadUpdateSettings.running && !checkVeloraUpdates.running
            onClicked: root.configureUpdates(["--automatic-checks", checked ? "off" : "on"])
        }

        ConfigSwitch {
            buttonIcon: "new_releases"
            text: Translation.tr("Use published GitHub releases")
            description: Translation.tr("Choose stable releases. Turn off to follow the latest changes on your tracked branch.")
            checked: root.updateSettings.channel === "release"
            autoToggle: false
            enabled: !saveUpdateSettings.running && !loadUpdateSettings.running && !checkVeloraUpdates.running
            onClicked: root.configureUpdates(["--channel", checked ? "branch" : "release"])
        }

        StyledText {
            Layout.fillWidth: true
            Layout.margins: 12
            visible: !!root.updateStatus.current_version
            text: `${Translation.tr("Installed")}: ${root.updateStatus.current_version ?? ""} (${(root.updateStatus.current ?? "").slice(0, 12)})\n${Translation.tr("Latest")}: ${root.updateStatus.latest_version ?? ""}`
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            Layout.margins: 12
            wrapMode: Text.Wrap
            text: checkVeloraUpdates.running ? Translation.tr("Checking for updates…")
                : root.updateError ? root.updateError
                : root.updateStatus.error ? root.updateStatus.error
                : root.updateStatus.diverged ? Translation.tr("Your branch has diverged. Merge your changes before updating.")
                : root.updateStatus.dirty && root.updateStatus.available ? Translation.tr("An update is available. Commit your local changes before installing it.")
                : root.updateStatus.available ? Translation.tr("An update is available.")
                : root.updateStatus.checked_at ? Translation.tr("Velora is up to date.")
                : Translation.tr("Run the Velora installer to enable update checks.")
        }

        Flow {
            Layout.fillWidth: true
            Layout.margins: 12
            spacing: 6
            LinkButton {
                materialIcon: "refresh"
                mainText: Translation.tr("Check for updates")
                enabled: !checkVeloraUpdates.running && !saveUpdateSettings.running
                onClicked: {
                    root.updateError = "";
                    checkVeloraUpdates.running = true;
                }
            }
            LinkButton {
                materialIcon: "download"
                mainText: Translation.tr("Install update")
                enabled: !!root.updateStatus.available && !root.updateStatus.diverged && !root.updateStatus.dirty
                    && !root.updateStatus.error && !checkVeloraUpdates.running && !saveUpdateSettings.running
                onClicked: Quickshell.execDetached(["kitty", "--hold", "--title", "Velora update",
                    root.veloraCommand, "update", "--interactive"])
            }
            LinkButton {
                materialIcon: "open_in_new"
                mainText: Translation.tr("Release notes")
                visible: !!root.updateStatus.release_url
                onClicked: Qt.openUrlExternally(root.updateStatus.release_url)
            }
        }
    }

    ContentSection {
        icon: "computer"
        title: Translation.tr("System")

        IdentityRow {
            name: SystemInfo.distroName
            subtitle: `${SystemInfo.username}@${SystemInfo.desktopEnvironment ?? "Hyprland"}`
            link: SystemInfo.homeUrl ?? ""
            logo: Component {
                IconImage {
                    implicitSize: 72
                    source: Quickshell.iconPath(SystemInfo.logo)
                }
            }
        }

        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 12
            spacing: 6

            LinkButton {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: Qt.openUrlExternally(SystemInfo.documentationUrl)
            }
            LinkButton {
                materialIcon: "support"
                mainText: Translation.tr("Help & Support")
                onClicked: Qt.openUrlExternally(SystemInfo.supportUrl)
            }
            LinkButton {
                materialIcon: "bug_report"
                mainText: Translation.tr("Report a Bug")
                onClicked: Qt.openUrlExternally(SystemInfo.bugReportUrl)
            }
            LinkButton {
                materialIcon: "policy"
                materialIconFill: false
                mainText: Translation.tr("Privacy Policy")
                onClicked: Qt.openUrlExternally(SystemInfo.privacyPolicyUrl)
            }
        }
    }
}
