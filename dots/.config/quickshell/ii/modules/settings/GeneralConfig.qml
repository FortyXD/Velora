import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * General, as on a Mac: grouped rows that lead to the pages about the computer as a whole,
 * each with a glance at where it stands.
 */
ContentPage {
    id: root

    // Velora's last update check (written by the velora command, see UpdatesConfig)
    property var updateStatus: ({})
    property var systemDisk: null // { size, avail } of / in bytes

    FileView {
        path: `${Quickshell.env("XDG_STATE_HOME") || `${FileUtils.trimFileProtocol(Directories.home)}/.local/state`}/velora/update.json`
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.updateStatus = JSON.parse(text()); }
            catch (error) { root.updateStatus = ({}); }
        }
    }

    Process {
        id: systemDiskUsage
        running: true
        command: ["df", "-B1", "--output=size,avail", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [size, avail] = (text.trim().split("\n")[1] ?? "").trim().split(/\s+/).map(Number);
                root.systemDisk = size > 0 ? { size, avail } : null;
            }
        }
    }
    onPageShownChanged: if (root.pageShown) systemDiskUsage.running = true

    // A row leading to another settings page, with that page's icon, color and name as in the sidebar
    component PageLink: ConfigNavRow {
        id: link
        property string pageKey
        readonly property var page: (ApplicationWindow.window?.pages ?? []).find(page => page.key === link.pageKey) ?? null
        buttonIcon: link.page?.icon ?? ""
        title: link.page?.name ?? ""
        tileColor: link.page ? ColorUtils.mix(link.page.color, Appearance.colors.colPrimary, 0.82) : "transparent"
        onClicked: ApplicationWindow.window?.openPage(link.pageKey)
    }

    ContentSection {
        title: ""

        PageLink {
            pageKey: "about"
            valueText: `${SystemInfo.distroName} · Velora`
        }
        PageLink {
            pageKey: "updates"
            valueText: root.updateStatus.error ? Translation.tr("Couldn't check")
                : root.updateStatus.available ? Translation.tr("Update available")
                : root.updateStatus.checked_at ? Translation.tr("Up to date")
                : ""
        }
        PageLink {
            pageKey: "storage"
            valueText: root.systemDisk ? Translation.tr("%1 GB available").arg((root.systemDisk.avail / 1e9).toFixed(1)) : ""
        }
    }

    ContentSection {
        title: ""

        PageLink {
            pageKey: "datetime"
            valueText: `${DateTime.time} · ${DateTime.shortDate}`
        }
        PageLink {
            pageKey: "language"
            readonly property string code: Config.options.language.ui === "auto" ? Qt.locale().name : Config.options.language.ui
            valueText: Translation.languageNames[code] ?? code
        }
    }

    ContentSection {
        title: ""

        PageLink {
            pageKey: "apps"
            valueText: ""
        }
    }
}
