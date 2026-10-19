pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "onlineWallpapers/providers.js" as Providers

/**
 * Searching wallpapers on the web (see onlineWallpapers/providers.js) and saving them to
 * ~/Pictures/Wallpapers/Online/<source>/ with their credits in a .json next to each file.
 * API keys live in the keyring under wallpaperKeys.<source>.
 */
Singleton {
    id: root

    // Metadata only: functions don't survive a `var` property, so requests go through Providers.find()
    readonly property var providerList: Providers.providers.map(provider => ({
        "id": provider.id, "name": provider.name, "icon": provider.icon, "homepage": provider.homepage,
        "description": provider.description, "needsKey": !!provider.needsKey, "keyOptional": !!provider.keyOptional,
        "supportsQuery": !!provider.supportsQuery, "supportsColor": !!provider.supportsColor,
        "sortings": provider.sortings ?? [], "categories": provider.categories ?? []
    }))
    readonly property var enabledProviders: providerList.filter(provider => !(Config.options.background.online.disabledProviders ?? []).includes(provider.id))

    readonly property string providerId: Config.options.background.online.provider
    readonly property var provider: providerList.find(provider => provider.id === providerId) ?? providerList[0]
    readonly property string userAgent: Config.options?.networking?.userAgent || "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"
    readonly property string downloadDir: (Config.options.background.online.downloadDir ?? "").length > 0
        ? FileUtils.trimFileProtocol(Config.options.background.online.downloadDir) : `${FileUtils.trimFileProtocol(Directories.pictures)}/Wallpapers/Online`
    readonly property string thumbnailDir: `${FileUtils.trimFileProtocol(Directories.cache)}/media/onlinewalls`
    readonly property string downloadScript: Quickshell.shellPath("scripts/colors/random/download_wallpaper.sh")

    property list<var> results: []
    property int page: 1
    property bool loading: requestProc.running
    property bool hasMore: false
    property string error: ""
    property string query: ""
    property string sorting: ""
    property string category: ""
    property string color: ""
    property var searchState: ({})
    property var unreachable: ({}) // provider id → true after a network failure

    readonly property var keys: KeyringStorage.keyringData?.wallpaperKeys ?? ({})
    function keyFor(id) {
        return (root.keys[id] ?? "").trim();
    }
    function hasKey(id) {
        return root.keyFor(id).length > 0;
    }

    // Physical size of the focused screen, for "fits my screen" searches
    readonly property var focusedScreen: Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
    readonly property int screenWidth: Math.round((focusedScreen?.width ?? 1920) * (focusedScreen?.devicePixelRatio ?? 1))
    readonly property int screenHeight: Math.round((focusedScreen?.height ?? 1080) * (focusedScreen?.devicePixelRatio ?? 1))

    function load() {} // For starting the service (and its IPC) with the shell

    function setProvider(id) {
        Config.options.background.online.provider = id;
        root.sorting = "";
        root.category = "";
        root.results = [];
        root.error = "";
        root.hasMore = false;
    }

    function search(query = root.query) {
        root.keyringChecked = false;
        root.query = query.trim();
        root.page = 1;
        root.results = [];
        root.searchState = {};
        root.request();
    }

    function loadMore() {
        if (!root.hasMore || root.loading) return;
        root.page += 1;
        root.request();
    }

    // Keys can be changed by the settings app; a search re-reads the keyring once when a key is missing
    property bool keyringChecked: false
    property bool waitingForKeyring: false
    function request() {
        const provider = Providers.find(root.provider.id);
        if (!provider) return;
        if ((provider.needsKey || provider.keyOptional) && root.keyFor(provider.id).length === 0 && !root.keyringChecked) {
            root.keyringChecked = true;
            root.waitingForKeyring = true;
            keyringTimeout.restart();
            KeyringStorage.fetchKeyringData();
            return;
        }
        const key = root.keyFor(provider.id);
        if (provider.needsKey && key.length === 0) {
            root.error = Translation.tr("%1 needs an API key. Add it under Settings → Wallpaper → Online sources.").arg(provider.name);
            root.hasMore = false;
            return;
        }
        root.error = "";
        const ctx = {
            "query": root.query, "page": root.page, "sorting": root.sorting, "category": root.category,
            "fitScreen": Config.options.background.online.fitScreen, "screenWidth": root.screenWidth, "screenHeight": root.screenHeight,
            "color": root.color, "key": key, "state": root.searchState, "subreddits": Config.options.background.online.subreddits
        };
        const req = provider.request(ctx);
        requestProc.ctx = ctx;
        requestProc.providerId = provider.id;
        let command = ["curl", "-sS", "-L", "--compressed", "--connect-timeout", "8", "--max-time", "25",
            "-A", root.userAgent, "-w", "\n%{http_code}"];
        for (const header of req.headers) command.push("-H", header);
        command.push("--", req.url);
        requestProc.running = false;
        requestProc.command = command;
        requestProc.running = true;
    }

    function continueAfterKeyring() {
        if (!root.waitingForKeyring) return;
        root.waitingForKeyring = false;
        keyringTimeout.stop();
        root.request();
    }
    Connections {
        target: KeyringStorage
        function onKeyringDataChanged() {
            root.continueAfterKeyring();
        }
        function onLoadedChanged() {
            root.continueAfterKeyring();
        }
    }
    Timer { // A locked keyring answers nothing
        id: keyringTimeout
        interval: 4000
        onTriggered: root.continueAfterKeyring()
    }

    function curlErrorText(code, host) {
        switch (code) {
        case 6: return Translation.tr("Could not resolve %1 (DNS blocked or offline).").arg(host);
        case 7: case 28: return Translation.tr("%1 is not responding. It may be blocked without a VPN.").arg(host);
        case 35: case 60: return Translation.tr("Secure connection to %1 failed.").arg(host);
        default: return Translation.tr("Request to %1 failed (curl error %2).").arg(host).arg(code);
        }
    }

    Process {
        id: requestProc
        property var ctx: null
        property string providerId: ""
        stdout: StdioCollector {
            id: requestOutput
        }
        onExited: (exitCode, exitStatus) => {
            const host = (root.provider.homepage ?? "").replace(/^https?:\/\//, "").split("/")[0];
            const text = requestOutput.text;
            const split = text.lastIndexOf("\n");
            const status = parseInt(text.slice(split + 1));
            const body = text.slice(0, split);
            if (requestProc.providerId !== root.provider.id) return; // Switched source meanwhile
            if (exitCode !== 0) {
                let unreachable = Object.assign({}, root.unreachable);
                unreachable[requestProc.providerId] = true;
                root.unreachable = unreachable;
                root.error = root.curlErrorText(exitCode, host);
                root.hasMore = false;
                return;
            }
            if (status === 401 || status === 403) {
                root.error = Translation.tr("%1 refused the request (HTTP %2). Check the API key, or try again later.").arg(root.provider.name).arg(status);
                root.hasMore = false;
                return;
            }
            if (status === 429) {
                root.error = Translation.tr("%1 is rate limiting requests. Try again in a while.").arg(root.provider.name);
                root.hasMore = false;
                return;
            }
            if (status >= 400) {
                root.error = Translation.tr("%1 answered with HTTP %2.").arg(root.provider.name).arg(status);
                root.hasMore = false;
                return;
            }
            try {
                const parsed = Providers.find(requestProc.providerId).parse(body, requestProc.ctx);
                const known = new Set(root.results.map(item => item.id));
                const fresh = parsed.items.filter(item => item.full && !known.has(item.id)).map(item => Object.assign({ "provider": requestProc.providerId }, item));
                root.results = [...root.results, ...fresh];
                root.hasMore = parsed.hasMore && fresh.length > 0;
                if (root.results.length === 0) root.error = Translation.tr("Nothing found.");
                let unreachable = Object.assign({}, root.unreachable);
                delete unreachable[requestProc.providerId];
                root.unreachable = unreachable;
            } catch (e) {
                console.warn("[OnlineWallpapers]", requestProc.providerId, e);
                root.error = Translation.tr("%1 sent an answer that couldn't be read.").arg(root.provider.name);
                root.hasMore = false;
            }
        }
    }

    function destinationFor(item) {
        const safeId = String(item.id).replace(/[^A-Za-z0-9._-]/g, "_");
        return `${root.downloadDir}/${item.provider}/${safeId}.${item.fileExt || "jpg"}`;
    }

    // Saves a wallpaper to the library and, with `apply`, sets it
    function download(item, apply = false) {
        const providerName = root.providerList.find(provider => provider.id === item.provider)?.name ?? item.provider;
        if (item.downloadPing) {
            Quickshell.execDetached(["curl", "-sS", "--max-time", "10", "-H", `Authorization: Client-ID ${root.keyFor(item.provider)}`, "--", item.downloadPing]);
        }
        const meta = JSON.stringify({
            "source": providerName, "page": item.pageUrl, "url": item.full, "title": item.title,
            "author": item.author, "license": item.license, "width": item.width, "height": item.height
        });
        Quickshell.execDetached([root.downloadScript, item.full, root.destinationFor(item), ...(apply ? ["--apply"] : []),
            "--meta", meta, "--title", providerName]);
    }

    IpcHandler {
        target: "onlineWallpapers"

        function search(provider: string, query: string): void {
            if (provider.length > 0) root.setProvider(provider);
            root.search(query);
        }
        function status(): string {
            return `${root.provider.id}: ${root.loading ? "loading" : `${root.results.length} results`}${root.error ? ` — ${root.error}` : ""}`;
        }
        function first(): string {
            return root.results.length > 0 ? JSON.stringify(root.results[0]) : "";
        }
    }

    // Thumbnails from the last week are reused; older ones are cleared
    Component.onCompleted: Quickshell.execDetached(["bash", "-c", 'mkdir -p "$1" && find "$1" -type f -mtime +7 -delete', "_", root.thumbnailDir])
}
