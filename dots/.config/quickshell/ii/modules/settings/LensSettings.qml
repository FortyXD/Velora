pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Dialogs
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root

    // Older services report a combined catalogue. With no roots, it contains only apps.
    readonly property int applicationCount: Lens.usable ? (Lens.status.applications ?? (!root.folders.length
                                                                                        ? Lens.status.files
                                                                                          ?? 0 : -1)) : -1
    property string currentTab: "files"
    readonly property var datasets: Lens.usable ? (Lens.status.config?.dataset_folders ?? []) : []
    readonly property var excludes: Lens.usable ? (Lens.status.config?.excludes ?? []) : []
    readonly property var folders: Lens.usable ? (Lens.status.config?.roots ?? []) : []
    readonly property int indexCompleted: Math.max(0, root.indexTotal - root.indexPending)
    readonly property int indexFailed: Lens.usable ? (Lens.status.folder_stats?.failed ?? Lens.status.failed
                                                      ?? 0) : 0
    readonly property int indexPending: Lens.usable ? (Lens.status.folder_stats?.pending ?? Lens.status.pending
                                                       ?? 0) : 0
    readonly property int indexTotal: Lens.usable ? (Lens.status.folder_stats?.total ?? Lens.status.files
                                                     ?? 0) : 0
    readonly property bool indexTotalKnown: Lens.status.total_known ?? !Lens.status.scanning
    readonly property bool needsSetup: Lens.setupInfo.installed === false || (Lens.ready &&
                                                                              !Lens.status.models)
    property bool pageShown: true
    readonly property bool separateFolderCounts: Lens.status.folder_stats !== undefined
    readonly property bool setupFailed: ["failed", "cancelled", "interrupted"].includes(Lens.setupInfo.stage)
    readonly property bool setupMeasured: Number(root.setupProgress.total) > 0
    readonly property var setupProgress: Lens.setupInfo.progress ?? ({})
    readonly property bool showIndexProgress: Lens.usable && !Lens.setupRunning && root.folders.length > 0 && (
                                                  root.indexTotal > 0 || Lens.status.scanning)
    property alias sourceReviewItem: sourceReviewsPanel
    readonly property var sourceReviews: Lens.usable ? (Lens.status.config?.source_reviews ?? []) : []
    readonly property string statusDescription: {
        if (Lens.setupRunning)
            return Translation.tr("You can close Settings. Preparation continues in the background.");
        if (root.setupFailed)
            return Translation.tr("Your files are unchanged. You can retry here.");
        if (Lens.ready && Lens.status.opening)
            return Translation.tr("Your saved index is being prepared. Search will become available automatically.");
        if (root.needsSetup)
            return Translation.tr(
                        "Prepare local models once. Models use about 2.5 GB, plus temporary setup space. An internet connection is needed for setup only.");
        if (!Lens.ready)
            return Translation.tr("Starting the service on this computer.");
        if (Lens.status.locked)
            return Translation.tr(
                        "The system keyring protects your index. Unlock it using the secure system dialog.");
        if (!root.folders.length)
            return Translation.tr(
                        "No folders selected. Only applications are searchable. Add a folder to search its files.");
        return Translation.tr("%1 ready · %2 waiting · %3 skipped").arg(root.count(Math.max(0,
                                                                                            root.indexCompleted
                                                                                            - root.indexFailed))).arg(
                    root.count(root.indexPending)).arg(root.count(root.indexFailed));
    }
    readonly property string statusTitle: {
        if (Lens.setupRunning)
            return Lens.setupLabel();
        if (root.setupFailed)
            return Lens.setupLabel();
        if (Lens.setupInfo.installed === false)
            return Translation.tr("Set up search on this computer");
        if (!Lens.ready)
            return Translation.tr("Connecting to local search");
        if (Lens.status.opening)
            return Translation.tr("Preparing your search index");
        if (Lens.status.locked)
            return Lens.status.session_locked ? Translation.tr("Waiting for your desktop session") :
                                                Translation.tr("Unlock the search index");
        if (!Lens.status.models)
            return Translation.tr("Add search by meaning");
        if (!root.folders.length)
            return Translation.tr("Choose where to search");
        if (root.sourceReviews.length)
            return Translation.tr("Choose which large folders to search");
        if (Lens.status.config?.paused)
            return Translation.tr("Indexing is paused");
        if (Lens.status.scanning)
            return Translation.tr("Finding your files");
        if (root.indexPending > 0) {
            if (Lens.status.on_battery)
                return Translation.tr("Waiting for external power");
            if (Lens.status.config?.all_in)
                return Translation.tr("All in indexing is running");
            if (Lens.status.config?.fast_indexing)
                return Translation.tr("Fast indexing is running");
            if (!Lens.status.idle)
                return Translation.tr("Waiting for idle time");
            return Translation.tr("Indexing your files");
        }
        return Translation.tr("Ready to search");
    }

    signal tabRequested(string key)

    function addFolder(path, excluded, dataset = false) {
        const values = (dataset ? root.datasets : excluded ? root.excludes : root.folders).slice();
        if (!values.includes(path))
            values.push(path);
        Lens.configure(dataset ? {
                                     dataset_folders: values
                                 } : excluded ? {
                                                    excludes: values
                                                } : {
                           roots: values
                       });
    }
    function bytes(value) {
        const units = ["B", "KiB", "MiB", "GiB"];
        let number = Math.max(0, Number(value) || 0);
        let unit = 0;
        while (number >= 1024 && unit < units.length - 1) {
            number /= 1024;
            unit++;
        }
        return number.toLocaleString(Qt.locale(), 'f', unit > 0 ? 1 : 0) + " " + units[unit];
    }
    function count(value) {
        return Number(value).toLocaleString(Qt.locale(), 'f', 0);
    }
    function duration(value) {
        const seconds = Math.max(0, Math.floor(Number(value) || 0));
        return (seconds >= 3600 ? Math.floor(seconds / 3600) + ":" : "") + String(Math.floor(seconds / 60)
                                                                                  % 60).padStart(2, "0")
                + ":" + String(seconds % 60).padStart(2, "0");
    }
    function pickFolder(excluded, dataset = false) {
        folderDialog.excluded = excluded;
        folderDialog.dataset = dataset;
        folderDialog.currentFolder = Directories.home;
        folderDialog.open();
    }
    function ratio(done, total) {
        return total > 0 ? Math.min(1, Math.max(0, done / total)) : 0;
    }
    function removeFolder(path, excluded, dataset = false) {
        const values = (dataset ? root.datasets : excluded ? root.excludes : root.folders).filter(value
                                                                                                  => value
                                                                                                     !== path);
        Lens.configure(dataset ? {
                                     dataset_folders: values
                                 } : excluded ? {
                                                    excludes: values
                                                } : {
                           roots: values
                       });
    }
    function setupMetric() {
        const progress = root.setupProgress;
        if (progress.unit === "parts")
            return Translation.tr("Verified model parts: %1 of %2").arg(root.count(progress.done ?? 0)).arg(
                        root.count(progress.total ?? 3));
        if (progress.unit !== "bytes")
            return "";
        const amount = root.setupMeasured ? Translation.tr("%1 of %2").arg(root.bytes(progress.done)).arg(
                                                root.bytes(progress.total)) : root.bytes(progress.done);
        return (progress.task === "model-download" ? Translation.tr("Model data: %1") : Translation.tr(
                                                         "Current download: %1")).arg(amount);
    }

    Layout.fillWidth: true
    objectName: "lensSettings"

    Component.onCompleted: {
        Lens.settingsVisible = pageShown;
        Lens.checkSetup();
        Lens.refresh();
    }
    Component.onDestruction: Lens.settingsVisible = false
    onPageShownChanged: Lens.settingsVisible = pageShown

    FolderDialog {
        id: folderDialog

        property bool dataset: false
        property bool excluded: false

        title: dataset ? Translation.tr("Choose a dataset folder") : excluded ? Translation.tr(
                                                                                    "Exclude a folder") :
                                                                                Translation.tr(
                                                                                    "Choose a folder to search")

        onAccepted: root.addFolder(FileUtils.trimFileProtocol(decodeURIComponent(selectedFolder.toString())),
                                   excluded, dataset)
    }

    SettingsTabPage {
        anchors.fill: parent
        current: root.currentTab
        enabled: shown
        key: "files"

        onRevealRequested: key => root.tabRequested(key)

        SettingsScrollPane {
            anchors.fill: parent

            ContentSection {
                description: Translation.tr(
                                 "Search stays on this computer. The index is encrypted and closes when you lock the screen.")
                icon: "manage_search"
                title: Translation.tr("Files on this computer")

                ConfigSwitch {
                    autoToggle: false
                    buttonIcon: "manage_search"
                    checked: Lens.enabled
                    description: Translation.tr("Find projects, photos and apps from the launcher.")
                    objectName: "lensEnable"
                    text: Translation.tr("Search across your files")

                    onClicked: Config.options.search.lens.enabled = !checked
                }

                ConfigSwitch {
                    autoToggle: false
                    checked: Lens.enabled && (Lens.status.config?.semantic ?? false)
                    description: Translation.tr(
                                     "Prepare vector embeddings for search by meaning. Off by default; turning off stops neural processing and keeps existing embeddings.")
                    enabled: Lens.usable
                    objectName: "lensSemanticEnable"
                    text: Translation.tr("Search by meaning")
                    visible: Lens.enabled

                    onClicked: Lens.configure({
                                                  semantic: !checked
                                              })
                }

                ColumnLayout {
                    Layout.bottomMargin: 12
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: 12
                    objectName: "lensFolders"
                    spacing: 6
                    visible: Lens.usable

                    StyledText {
                        Layout.fillWidth: true
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        text: Translation.tr("Searching these folders")
                        visible: root.folders.length > 0
                    }

                    Repeater {
                        model: root.folders

                        delegate: FolderRow {
                            required property string modelData

                            path: modelData
                        }
                    }

                    ConfigNavRow {
                        buttonIcon: "create_new_folder"
                        description: root.folders.length ? "" : Translation.tr(
                                                               "Projects, documents, pictures or videos")
                        objectName: "lensAddFolder"
                        title: root.folders.length ? Translation.tr("Add another folder") : Translation.tr(
                                                         "Add your first folder")
                        trailingIcon: "add"

                        onClicked: root.pickFolder(false)
                    }

                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: Translation.tr(
                                  "Includes subfolders, except excluded folders and protected locations.")
                        visible: root.folders.length > 0
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        objectName: "lensApplicationCount"
                        text: root.applicationCount >= 0 ? Translation.tr("Applications: %1 available").arg(
                                                               root.count(root.applicationCount)) :
                                                           Translation.tr(
                                                               "Applications are searched separately from your folders.")
                        wrapMode: Text.Wrap
                    }
                }

                ColumnLayout {
                    id: sourceReviewsPanel

                    Layout.bottomMargin: 12
                    Layout.fillWidth: true
                    Layout.leftMargin: 12
                    Layout.rightMargin: 12
                    Layout.topMargin: 12
                    objectName: "lensSourceReviews"
                    spacing: 12
                    visible: root.sourceReviews.length > 0

                    StyledText {
                        Layout.fillWidth: true
                        font.weight: Font.Medium
                        text: Translation.tr("These folders contain many files. Include them in search?")
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        text: Translation.tr(
                                  "They stay out of the index until you choose. Other folders continue indexing.")
                        wrapMode: Text.Wrap
                    }

                    Repeater {
                        model: root.sourceReviews

                        delegate: Rectangle {
                            id: review

                            required property var modelData

                            Layout.fillWidth: true
                            border.color: Appearance.colors.colOutlineVariant
                            border.width: 1
                            color: Appearance.colors.colLayer1
                            implicitHeight: reviewContent.implicitHeight + 24
                            radius: 12

                            ColumnLayout {
                                id: reviewContent

                                spacing: 8

                                anchors {
                                    left: parent.left
                                    margins: 12
                                    right: parent.right
                                    top: parent.top
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    objectName: "lensReviewPath"
                                    text: review.modelData.path
                                    textFormat: Text.PlainText
                                    wrapMode: Text.WrapAnywhere
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    objectName: "lensReviewCount"
                                    text: Translation.tr("At least %1 files after automatic exclusions").arg(
                                              root.count(review.modelData.files))
                                    wrapMode: Text.Wrap
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    DialogButton {
                                        buttonText: Translation.tr("Exclude folder")
                                        enabled: Lens.reviewingSource === ""
                                        objectName: "lensReviewExclude"

                                        onClicked: Lens.reviewSource(review.modelData.path, false)
                                    }

                                    DialogButton {
                                        buttonText: Translation.tr("Include in search")
                                        enabled: Lens.reviewingSource === ""
                                        objectName: "lensReviewInclude"

                                        onClicked: Lens.reviewSource(review.modelData.path, true)
                                    }
                                }
                            }
                        }
                    }
                }

                ConfigExpander {
                    buttonIcon: "folder_off"
                    description: Translation.tr(
                                     "node_modules, venv, build output, caches and credentials are excluded automatically. Project .gitignore and .ignore rules also apply. Changes save immediately.")
                    title: Translation.tr("Excluded folders")
                    visible: Lens.usable

                    Repeater {
                        model: root.excludes

                        delegate: FolderRow {
                            required property string modelData

                            excluded: true
                            path: modelData
                        }
                    }

                    ConfigNavRow {
                        buttonIcon: "folder_off"
                        description: Translation.tr("Remove this folder and its contents from the index.")
                        title: Translation.tr("Exclude a folder")
                        trailingIcon: "add"

                        onClicked: root.pickFolder(true)
                    }
                }

                ConfigNavRow {
                    buttonIcon: "manage_search"
                    description: root.statusDescription
                    objectName: "lensOpenIndexing"
                    title: root.statusTitle

                    onClicked: {
                        forceActiveFocus();
                        root.tabRequested("indexing");
                    }
                }
            }
        }
    }

    SettingsTabPage {
        anchors.fill: parent
        current: root.currentTab
        enabled: shown
        key: "indexing"

        onRevealRequested: key => root.tabRequested(key)

        SettingsScrollPane {
            anchors.fill: parent

            ContentSection {
                icon: "manage_search"
                title: Translation.tr("Indexing")

                Item {
                    Layout.fillWidth: true
                    implicitHeight: statusBody.implicitHeight + 24
                    objectName: "lensSetupCard"
                    visible: Lens.enabled || Lens.setupRunning

                    ColumnLayout {
                        id: statusBody

                        spacing: 14

                        anchors {
                            left: parent.left
                            margins: 12
                            right: parent.right
                            top: parent.top
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 14

                            Rectangle {
                                Layout.alignment: Qt.AlignTop
                                color: Appearance.colors.colPrimaryContainer
                                implicitHeight: 44
                                implicitWidth: 44
                                radius: 14

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    color: Appearance.colors.colOnPrimaryContainer
                                    iconSize: 25
                                    text: Lens.setupRunning ? "downloading" : root.setupFailed ? "refresh" :
                                                                                                 root.needsSetup
                                                                                                 ? "download" :
                                                                                                   Lens.status.locked
                                                                                                   ? "lock" :
                                                                                                     "search"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                StyledText {
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    objectName: "lensStatusTitle"
                                    text: root.statusTitle
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    text: root.statusDescription
                                    textFormat: Text.PlainText
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: Lens.setupRunning

                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                objectName: "lensSetupSteps"
                                text: Translation.tr("Step %1 of %2 · %3 completed").arg(Lens.setupInfo.step
                                                                                         ?? 1).arg(
                                          Lens.setupInfo.steps_total ?? 5).arg(Lens.setupInfo.steps_done ?? 0)
                                wrapMode: Text.Wrap
                            }

                            StyledText {
                                Layout.fillWidth: true
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                text: Translation.tr("Model %1 of %2").arg(root.setupProgress.model_number
                                                                           ?? 1).arg(
                                          root.setupProgress.models_total ?? 2)
                                visible: (root.setupProgress.model_number ?? 0) > 0
                                wrapMode: Text.Wrap
                            }

                            StyledText {
                                Layout.fillWidth: true
                                font.pixelSize: Appearance.font.pixelSize.small
                                objectName: "lensSetupMetric"
                                text: root.setupMetric()
                                visible: text !== ""
                                wrapMode: Text.Wrap
                            }

                            StyledProgressBar {
                                Layout.fillWidth: true
                                objectName: "lensSetupProgress"
                                value: root.ratio(root.setupProgress.done ?? 0, root.setupProgress.total)
                                visible: root.setupMeasured
                            }

                            StyledIndeterminateProgressBar {
                                Layout.fillWidth: true
                                visible: !root.setupMeasured
                            }

                            StyledText {
                                Layout.fillWidth: true
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                text: Translation.tr("Received over the network: %1").arg(root.bytes(
                                                                                              root.setupProgress.transferred))
                                visible: (root.setupProgress.transferred ?? 0) > 0
                                wrapMode: Text.Wrap
                            }

                            StyledText {
                                Layout.fillWidth: true
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                text: Translation.tr("Elapsed: %1").arg(root.duration(
                                                                            Lens.setupInfo.elapsed_seconds))
                                visible: Lens.setupInfo.elapsed_seconds !== undefined
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            objectName: "lensIndexProgress"
                            spacing: 10
                            visible: root.showIndexProgress

                            RowLayout {
                                Layout.fillWidth: true

                                StyledText {
                                    Layout.fillWidth: true
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    objectName: "lensIndexCount"
                                    text: root.indexTotalKnown ? (root.separateFolderCounts ? Translation.tr(
                                                                                                  "In selected folders: %1 of %2 processed") :
                                                                                              Translation.tr(
                                                                                                  "Total index: %1 of %2 processed (files and apps)")).arg(
                                                                     root.count(root.indexCompleted)).arg(
                                                                     root.count(root.indexTotal)) :
                                                                 Translation.tr(
                                                                     "Found %1 items · counting…").arg(
                                                                     root.count(root.indexTotal))
                                    wrapMode: Text.Wrap
                                }

                                StyledText {
                                    color: Appearance.colors.colPrimary
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    objectName: "lensIndexPercent"
                                    text: Math.floor(root.ratio(root.indexCompleted, root.indexTotal) * 100)
                                          + "%"
                                    visible: root.indexTotalKnown && root.indexTotal > 0
                                }
                            }

                            StyledProgressBar {
                                Layout.fillWidth: true
                                objectName: "lensIndexBar"
                                value: root.ratio(root.indexCompleted, root.indexTotal)
                                visible: root.indexTotalKnown && root.indexTotal > 0
                            }

                            StyledIndeterminateProgressBar {
                                Layout.fillWidth: true
                                visible: !root.indexTotalKnown
                            }

                            StyledText {
                                Layout.fillWidth: true
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                objectName: "lensCurrentFolder"
                                text: Lens.usable && Lens.status.current?.folder ? Translation.tr(
                                                                                       "Current folder: %1").arg(
                                                                                       Lens.status.current.folder) :
                                                                                   ""
                                textFormat: Text.PlainText
                                visible: Lens.usable && !!Lens.status.current?.folder
                                wrapMode: Text.WrapAnywhere
                            }

                            StyledText {
                                Layout.fillWidth: true
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideMiddle
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                objectName: "lensCurrentFile"
                                text: Lens.usable && Lens.status.current?.name ? Translation.tr(
                                                                                     "Processing: %1 · %2").arg(
                                                                                     Lens.status.current.name).arg(
                                                                                     root.duration(
                                                                                         Lens.status.current.elapsed_seconds)) :
                                                                                 ""
                                textFormat: Text.PlainText
                                visible: Lens.usable && !!Lens.status.current?.name
                            }

                            StyledText {
                                Layout.fillWidth: true
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                text: Translation.tr("Video processed up to %1").arg(root.duration(
                                                                                         Lens.status.current
                                                                                         ?.video_seconds))
                                visible: Lens.usable && (Lens.status.current?.video_seconds ?? 0) > 0
                                wrapMode: Text.Wrap
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10
                            visible: Lens.setupRunning || root.needsSetup || root.setupFailed || !Lens.ready
                                     || Lens.status.locked

                            DialogButton {
                                buttonText: root.setupFailed ? Translation.tr("Retry setup") : Translation.tr(
                                                                   "Set up Lens")
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                colText: Appearance.colors.colOnPrimary
                                objectName: "lensPrepare"
                                visible: !Lens.setupRunning && (root.needsSetup || root.setupFailed)

                                onClicked: Lens.prepare()
                            }

                            DialogButton {
                                buttonText: Translation.tr("Cancel setup")
                                enabled: !Lens.setupInfo.cancelling
                                visible: Lens.setupRunning

                                onClicked: Lens.cancelSetup()
                            }

                            DialogButton {
                                buttonText: Lens.unlocking ? Translation.tr("Waiting for system dialog") :
                                                             Translation.tr("Unlock index")
                                enabled: !Lens.unlocking
                                visible: !Lens.setupRunning && !root.needsSetup && Lens.ready
                                         && Lens.status.locked && !Lens.status.session_locked && !Lens.status.opening

                                onClicked: Lens.unlockIndex()
                            }

                            DialogButton {
                                buttonText: Translation.tr("Reconnect")
                                visible: !Lens.setupRunning && !root.needsSetup && !Lens.ready

                                onClicked: Lens.reconnectNow()
                            }

                            Item {
                                Layout.fillWidth: true
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            color: Appearance.colors.colError
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            text: Lens.problem
                            textFormat: Text.PlainText
                            visible: Lens.problem !== "" && Lens.setupInfo.installed !== false
                            wrapMode: Text.Wrap
                        }
                    }
                }

                ConfigExpander {
                    title: Translation.tr("Setup details")
                    visible: Lens.enabled && root.setupFailed && (Lens.setupInfo.detail ?? "") !== ""

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: detail.implicitHeight + 24

                        StyledText {
                            id: detail

                            font.family: Appearance.font.family.monospace
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            text: Lens.setupInfo.detail ?? ""
                            textFormat: Text.PlainText
                            wrapMode: Text.WrapAnywhere

                            anchors {
                                left: parent.left
                                margins: 12
                                right: parent.right
                                top: parent.top
                            }
                        }
                    }
                }

                ConfigNavRow {
                    buttonIcon: "folder"
                    title: Translation.tr("Choose folders and set up search")
                    visible: !Lens.enabled || (Lens.usable && !root.folders.length)

                    onClicked: {
                        forceActiveFocus();
                        root.tabRequested("files");
                    }
                }
            }

            ContentSection {
                description: Translation.tr(
                                 "Content is analysed while plugged in. Normal mode waits for two minutes of inactivity.")
                icon: "tune"
                title: Translation.tr("Indexing behavior")
                visible: Lens.usable

                ConfigSwitch {
                    autoToggle: false
                    buttonIcon: "photo_library"
                    checked: Lens.enabled && (Lens.status.config?.media ?? false)
                    description: Translation.tr(
                                     "Search images, text in pictures and sampled video frames. No speech recognition.")
                    objectName: "lensMediaEnable"
                    text: Translation.tr("Photos and videos")

                    onClicked: Lens.configure({
                                                  media: !checked
                                              })
                }

                ConfigSwitch {
                    autoToggle: false
                    buttonIcon: "history"
                    checked: Lens.enabled && (Lens.status.config?.activity ?? true)
                    description: Translation.tr(
                                     "Find what you worked on by date. Keep opened files and terminal folders for 90 days.")
                    objectName: "lensActivityEnable"
                    text: Translation.tr("Remember recent work")

                    onClicked: Lens.configure({
                                                  activity: !checked
                                              })
                }

                ConfigSwitch {
                    autoToggle: false
                    buttonIcon: "pause_circle"
                    checked: Lens.status.config?.paused ?? false
                    text: Translation.tr("Pause content indexing")

                    onClicked: Lens.configure({
                                                  paused: !checked
                                              })
                }

                ConfigExpander {
                    title: Translation.tr("Performance and datasets")

                    ConfigSwitch {
                        autoToggle: false
                        buttonIcon: "speed"
                        checked: Lens.status.config?.fast_indexing ?? false
                        description: Translation.tr(
                                         "Keep indexing while you use the computer and use more CPU threads. May increase heat and fan noise. Pauses on battery.")
                        enabled: !(Lens.status.config?.all_in ?? false)
                        objectName: "lensFastIndexing"
                        text: Translation.tr("Fast indexing")

                        onClicked: Lens.configure({
                                                      fast_indexing: !checked
                                                  })
                    }

                    ConfigNavRow {
                        readonly property bool active: Lens.status.config?.all_in ?? false

                        buttonIcon: "bolt"
                        description: Translation.tr(
                                         "Use all available CPU threads without waiting for idle. Pauses on battery. Press again to return to the previous mode.")
                        objectName: "lensAllIn"
                        tileColor: active ? Appearance.colors.colPrimaryContainer : "transparent"
                        title: active ? Translation.tr("Stop All in") : Translation.tr("All in")
                        trailingIcon: active ? "stop" : "play_arrow"

                        onClicked: Lens.configure({
                                                      all_in: !active
                                                  })
                    }

                    ConfigSwitch {
                        autoToggle: false
                        buttonIcon: "dataset"
                        checked: Lens.status.config?.dataset_samples ?? false
                        description: Translation.tr(
                                         "Include images and binary samples from dataset folders, plus NumPy collections with 1,000 or more arrays. Folders and working materials stay searchable either way.")
                        objectName: "lensDatasetSamples"
                        text: Translation.tr("Individual dataset samples")

                        onClicked: Lens.configure({
                                                      dataset_samples: !checked
                                                  })
                    }

                    ConfigExpander {
                        buttonIcon: "dataset"
                        description: Translation.tr(
                                         "Keep folders, code, notebooks and descriptions in search; skip individual images and binary samples unless enabled above. These rules apply inside your selected search sources.")
                        objectName: "lensDatasetFolders"
                        title: Translation.tr("Dataset folders")

                        Repeater {
                            model: root.datasets

                            delegate: FolderRow {
                                required property string modelData

                                dataset: true
                                path: modelData
                            }
                        }

                        ConfigNavRow {
                            buttonIcon: "create_new_folder"
                            description: Translation.tr(
                                             "Mark a data collection without excluding its working materials.")
                            title: Translation.tr("Choose a dataset folder")
                            trailingIcon: "add"

                            onClicked: root.pickFolder(false, true)
                        }
                    }
                }

                ConfigExpander {
                    title: Translation.tr("Maintenance")

                    ConfigNavRow {
                        buttonIcon: "sync"
                        description: Translation.tr(
                                         "Analyse the selected folders again during the next idle period.")
                        title: Translation.tr("Rebuild content index")

                        onClicked: Lens.call("rescan", {}, () => Lens.refresh())
                    }
                }
            }
        }
    }

    component FolderRow: Item {
        id: entry

        readonly property bool awaitingConfirmation: !excluded && !dataset && root.sourceReviews.some(review
                                                                                                      => review.path
                                                                                                         === entry.path)
        property bool dataset: false
        property bool excluded: false
        required property string path

        Layout.fillWidth: true
        implicitHeight: folderRow.implicitHeight + 24

        RowLayout {
            id: folderRow

            spacing: 12

            anchors {
                left: parent.left
                margins: 12
                right: parent.right
                top: parent.top
            }

            ConfigIconTile {
                icon: entry.excluded ? "folder_off" : "folder"
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    text: entry.path.split("/").pop() || entry.path
                    textFormat: Text.PlainText
                }

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    objectName: "lensFolderPath"
                    text: entry.path
                    textFormat: Text.PlainText
                    wrapMode: Text.WrapAnywhere
                }

                StyledText {
                    Layout.fillWidth: true
                    color: Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    objectName: "lensFolderAwaitingConfirmation"
                    text: Translation.tr("Awaiting confirmation — not searched yet")
                    visible: entry.awaitingConfirmation
                    wrapMode: Text.Wrap
                }
            }

            IconToolbarButton {
                text: "close"

                onClicked: root.removeFolder(entry.path, entry.excluded, entry.dataset)

                StyledToolTip {
                    text: Translation.tr("Remove from this list")
                }
            }
        }
    }
}
