import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

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
                    VeloraLogo {
                        anchors.centerIn: parent
                        size: 32
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
        icon: "waving_hand"
        title: Translation.tr("Setup and tour")
        description: Translation.tr("Choose your desktop again, or see the main shortcuts and gestures on your own desktop.")

        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 12
            spacing: 6

            LinkButton {
                materialIcon: "auto_fix_high"
                mainText: Translation.tr("Run the setup assistant")
                onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellPath("onboarding.qml").replace(/^file:\/\//, "")])
            }
            LinkButton {
                materialIcon: "tour"
                mainText: Translation.tr("Take the quick tour")
                onClicked: Quickshell.execDetached(["qs", "-c", "ii", "ipc", "call", "tour", "start"])
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
