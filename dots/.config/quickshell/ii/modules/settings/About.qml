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
        title: Translation.tr("Folis")
        description: Translation.tr("Personal Hyprland setup with the Illogical Impulse shell on Quickshell")

        IdentityRow {
            name: "Folis"
            subtitle: Translation.tr("Based on end-4/dots-hyprland (illogical-impulse)")
            link: "https://github.com/FortyXD/Folis"
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
                onClicked: Qt.openUrlExternally("https://github.com/FortyXD/Folis")
            }
            LinkButton {
                materialIcon: "auto_stories"
                mainText: Translation.tr("Documentation")
                onClicked: Qt.openUrlExternally("https://end-4.github.io/dots-hyprland-wiki/en/ii-qs/02usage/")
            }
            LinkButton {
                materialIcon: "adjust"
                materialIconFill: false
                mainText: Translation.tr("Upstream issues")
                onClicked: Qt.openUrlExternally("https://github.com/end-4/dots-hyprland/issues")
            }
            LinkButton {
                materialIcon: "forum"
                mainText: Translation.tr("Discussions")
                onClicked: Qt.openUrlExternally("https://github.com/end-4/dots-hyprland/discussions")
            }
            LinkButton {
                materialIcon: "favorite"
                mainText: Translation.tr("Support end-4")
                onClicked: Qt.openUrlExternally("https://github.com/sponsors/end-4")
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
