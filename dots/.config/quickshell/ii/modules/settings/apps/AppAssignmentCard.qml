pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings
import qs.services

Rectangle {
    id: root
    required property string roleId
    required property var info
    required property var roleData
    required property string currentName
    required property var services
    required property string roleSearch
    required property bool expanded
    required property bool pageActive
    required property bool loaded
    readonly property alias header: headerButton
    readonly property var current: roleData.current ?? {}
    readonly property string currentId: current.app?.id ?? (current.command ? "__command" : current.ask ? "ask" : "")
    readonly property string provider: (current.webmail && services.find(service => service.id === current.webmail)?.name) || ""
    readonly property string appName: [currentName, provider].filter(Boolean).join(" · ")
    readonly property var shortcut: info.shortcut ? HyprlandKeybinds.bindMap[info.shortcut] : null
    readonly property color tone: ColorUtils.mix(info.color, Appearance.colors.colOnLayer2, Appearance.m3colors.darkmode ? 0.72 : 0.55)
    readonly property bool compact: width < 550
    readonly property var options: {
        const list = (roleData.candidates ?? []).slice(0, 3);
        if (!currentId || list.some(app => app.id === currentId)) return list;
        const choice = current.app ?? {id: currentId, name: currentName, symbol: current.command ? "terminal" : "help"};
        return [choice, ...list.slice(0, 2)];
    }
    property real reveal: expanded && pageActive ? 1 : 0
    property bool scrollOnOpen: false
    signal expandRequested(bool open)
    signal settled()
    signal moveFocus(int offset)
    signal browse(Item trigger)
    signal assign(string appId)
    signal saveCommand(string command)
    signal setWebmail(string service)

    objectName: "assignment-" + roleId
    Layout.fillWidth: true
    Layout.minimumWidth: 0
    implicitHeight: headerButton.height + drawer.height
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0; color: ColorUtils.mix(root.tone, Appearance.colors.colLayer2, 0.035 + 0.13 * root.reveal) }
        GradientStop { position: 0.80; color: ColorUtils.mix(root.tone, Appearance.colors.colLayer2, 0.07 * root.reveal) }
        GradientStop { position: 1; color: ColorUtils.mix(root.tone, Appearance.colors.colLayer2, 0.16 * root.reveal) }
    }
    border.width: root.reveal > 0 ? 1 : 0
    border.color: Qt.rgba(tone.r, tone.g, tone.b, reveal * 0.35)

    function settingsReveal() {
        if (expanded) return false;
        expandRequested(true);
        return true;
    }
    function toggle(open) {
        scrollOnOpen = open;
        expandRequested(open);
    }
    Behavior on reveal {
        enabled: root.pageActive && Appearance.animationSpeed > 0
        NumberAnimation { duration: Appearance.scaledDuration(300); easing.type: Easing.InOutCubic }
    }
    onRevealChanged: {
        if (reveal === 1 && scrollOnOpen) {
            scrollOnOpen = false;
            Qt.callLater(() => { if (root.expanded && root.pageActive) root.settled(); });
        }
    }
    onPageActiveChanged: if (!pageActive) scrollOnOpen = false
    onCurrentIdChanged: if (loaded && pageActive) {
        saved.restart();
        if (expanded) protocolTrail.play();
    }
    Timer { id: saved; interval: 1000 }

    SettingsAction {
        id: headerButton
        objectName: "default-" + root.roleId
        readonly property bool settingsSearchable: true
        readonly property string searchText: root.roleSearch + " " + root.provider
        readonly property string buttonIcon: root.info.icon
        readonly property Item settingsDestination: contentItem
        width: parent.width
        height: Math.max(50 + 8 * root.reveal, contentItem.implicitHeight + 12)
        horizontalPadding: root.compact ? 11 : 14
        text: root.info.action
        Accessible.name: text + " · " + root.appName
        Accessible.description: root.info.description
        Accessible.expandable: true
        Accessible.expanded: root.expanded
        enabled: root.loaded
        buttonRadius: root.radius
        colBackgroundHover: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.10)
        onClicked: root.toggle(!root.expanded)
        Keys.onDownPressed: root.moveFocus(1)
        Keys.onUpPressed: root.moveFocus(-1)
        Keys.onRightPressed: if (!root.expanded) root.toggle(true)
        Keys.onLeftPressed: if (root.expanded) root.toggle(false)
        contentItem: RowLayout {
            spacing: root.compact ? 8 : 12
            Rectangle {
                implicitWidth: 32 + 8 * root.reveal
                implicitHeight: implicitWidth
                radius: 10 + 3 * root.reveal
                color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.12 + root.reveal * 0.09)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.info.icon
                    iconSize: 19 + 5 * root.reveal
                    fill: root.reveal
                    color: root.tone
                    scale: headerButton.hovered ? 1.08 : 1
                    Behavior on scale { NumberAnimation { duration: Appearance.scaledDuration(140) } }
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: headerButton.text
                wrapMode: Text.Wrap
                font.weight: Font.DemiBold
                font.pixelSize: Appearance.font.pixelSize.small + 3 * root.reveal
            }
            Item {
                id: protocolTrail
                readonly property bool showing: root.expanded && root.pageActive && !root.compact
                property real travel: 1
                Layout.preferredWidth: !root.compact ? (token.implicitWidth + 44) * root.reveal : 0
                Layout.preferredHeight: 23
                visible: !root.compact && root.reveal > 0
                opacity: root.reveal
                clip: true
                function play() {
                    if (showing && Appearance.animationSpeed > 0) handoff.restart();
                }
                onShowingChanged: { if (showing) play(); else { handoff.stop(); travel = 1; } }
                NumberAnimation {
                    id: handoff
                    target: protocolTrail; property: "travel"; from: 0; to: 1
                    duration: Appearance.scaledDuration(650)
                    easing.type: Easing.InOutCubic
                }
                Rectangle {
                    id: token
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: sample.implicitWidth + 12
                    implicitHeight: 22
                    radius: 6
                    color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.10)
                    StyledText {
                        id: sample
                        anchors.centerIn: parent
                        text: root.info.example
                        color: root.tone
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
                Rectangle {
                    id: track
                    x: token.width + 5
                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: 31
                    implicitHeight: 1
                    color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.48)
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: protocolTrail.travel * (track.width - width)
                        width: 6; height: 6; radius: 3
                        opacity: Math.sin(Math.PI * protocolTrail.travel)
                        color: root.tone
                    }
                }
                MaterialSymbol { x: token.width + 26; anchors.verticalCenter: parent.verticalCenter; text: "chevron_right"; iconSize: 16; color: root.tone }
            }
            AppChoiceIcon {
                Layout.preferredWidth: 20
                Layout.preferredHeight: 20
                icon: root.current.app?.icon ?? ""
                symbol: root.current.command ? "terminal" : root.current.ask ? "help" : ""
                scale: saved.running ? 1.15 : 1
                Behavior on scale { NumberAnimation { duration: Appearance.scaledDuration(190); easing.type: Easing.OutCubic } }
            }
            StyledText {
                id: appLabel
                Layout.maximumWidth: headerButton.width * (root.compact ? 0.29 : 0.35)
                text: root.appName
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer2
                font.pixelSize: Appearance.font.pixelSize.smallie
            }
            MaterialSymbol { text: "expand_more"; iconSize: 19; rotation: -180 * root.reveal; color: root.tone }
        }
        StyledToolTip { text: root.appName; extraVisibleCondition: appLabel.truncated; delay: 650 }
    }

    Item {
        id: drawer
        y: headerButton.height
        width: parent.width
        height: (body.implicitHeight + 13) * root.reveal
        clip: true
        visible: height > 0
        enabled: root.expanded && root.pageActive
        ColumnLayout {
            id: body
            x: headerButton.horizontalPadding
            y: -8 * (1 - root.reveal)
            width: drawer.width - 2 * x
            opacity: Math.min(1, root.reveal * 1.3)
            spacing: 8
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    text: root.info.description
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                }
                KeyCombo {
                    visible: !!root.shortcut && !root.shortcut.disabled
                    mods: root.shortcut?.mods ?? []
                    key: root.shortcut?.key ?? ""
                    Accessible.name: Translation.tr("Keyboard shortcut") + " " + labels.join(" + ")
                }
            }
            Item {
                Layout.fillWidth: true
                implicitHeight: choices.implicitHeight
                GridLayout {
                    id: choices
                    width: parent.width
                    columns: Math.min(root.compact ? 2 : 4, root.options.length + 1)
                    uniformCellWidths: true
                    columnSpacing: 7
                    rowSpacing: 5
                    Repeater {
                        id: optionsRepeater
                        model: (root.expanded && root.pageActive) || root.reveal > 0 ? root.options.length : 0
                        delegate: SettingsAction {
                            id: option
                            required property int index
                            readonly property var app: root.options[index] ?? {}
                            readonly property bool chosen: !!app.id && app.id === root.currentId
                            readonly property real entry: Math.min(1, Math.max(0, (root.reveal - index * 0.10) / (1 - index * 0.10)))
                            objectName: "suggested-" + root.roleId + "-" + (app.id ?? "")
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
                            implicitHeight: 43
                            horizontalPadding: 9
                            text: app.name ?? ""
                            Accessible.role: Accessible.RadioButton
                            Accessible.checked: chosen
                            opacity: entry
                            transform: Translate { y: (1 - option.entry) * 12 }
                            scale: down ? 0.96 : hovered || visualFocus ? 1.02 : 1
                            Behavior on scale { NumberAnimation { duration: Appearance.scaledDuration(130); easing.type: Easing.OutCubic } }
                            buttonRadius: Appearance.rounding.small
                            colBackground: chosen ? ColorUtils.mix(root.tone, Appearance.colors.colLayer2Base, 0.23) : Appearance.colors.colLayer3
                            colBackgroundHover: ColorUtils.mix(root.tone, Appearance.colors.colLayer3Base, chosen ? 0.30 : 0.15)
                            onClicked: if (!chosen) root.assign(app.id)
                            contentItem: RowLayout {
                                spacing: 7
                                AppChoiceIcon { Layout.preferredWidth: 23; Layout.preferredHeight: 23; icon: option.app.icon ?? ""; symbol: option.app.symbol ?? "" }
                                StyledText { Layout.fillWidth: true; text: option.text; textFormat: Text.PlainText; elide: Text.ElideRight; font.pixelSize: Appearance.font.pixelSize.smallie }
                                MaterialSymbol {
                                    visible: option.chosen
                                    text: "check_circle"
                                    fill: 1
                                    iconSize: 17
                                    color: root.tone
                                    scale: option.chosen ? 1 : 0.6
                                    Behavior on scale { NumberAnimation { duration: Appearance.scaledDuration(210); easing.type: Easing.OutBack } }
                                }
                            }
                        }
                    }
                    SettingsAction {
                        id: browse
                        objectName: "browse-" + root.roleId
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: 1
                        implicitHeight: 43
                        horizontalPadding: 8
                        text: Translation.tr("All apps")
                        colBackgroundHover: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.12)
                        onClicked: root.browse(browse)
                        contentItem: RowLayout {
                            spacing: 5
                            Item { Layout.fillWidth: true }
                            MaterialSymbol { text: "search"; iconSize: 17; color: root.tone }
                            StyledText { text: browse.text; color: root.tone; font.pixelSize: Appearance.font.pixelSize.smallie }
                            Item { Layout.fillWidth: true }
                        }
                    }
                }
                Rectangle {
                    id: selection
                    readonly property int selectedIndex: root.options.findIndex(app => app.id === root.currentId)
                    readonly property Item selected: selectedIndex >= 0 && selectedIndex < optionsRepeater.count ? optionsRepeater.itemAt(selectedIndex) : null
                    readonly property bool glide: !!selected && root.pageActive && root.reveal === 1 && Appearance.animationSpeed > 0
                    visible: !!selected
                    x: selected?.x ?? 0
                    y: selected?.y ?? 0
                    width: selected?.width ?? 0
                    height: selected?.height ?? 0
                    radius: Appearance.rounding.small
                    color: "transparent"
                    border.width: 1
                    border.color: root.tone
                    component Glide: NumberAnimation { duration: Appearance.scaledDuration(260); easing.type: Easing.OutCubic }
                    Behavior on x { enabled: selection.glide; Glide {} }
                    Behavior on y { enabled: selection.glide; Glide {} }
                }
            }
            Loader {
                Layout.fillWidth: true
                active: !!root.roleData.allowsCommand && (root.expanded || root.reveal > 0)
                visible: active
                sourceComponent: RoleCommandEditor {
                    command: root.current.command ?? ""
                    onSaved: value => root.saveCommand(value)
                }
            }
            Loader {
                Layout.fillWidth: true
                active: root.roleId === "mail" && !!root.current.webmail && (root.expanded || root.reveal > 0)
                visible: active
                sourceComponent: ConfigComboRow {
                    objectName: "roleWebmail"
                    icon: "alternate_email"
                    text: Translation.tr("Web mail")
                    currentValue: root.current.webmail ?? ""
                    options: root.services.map(service => ({displayName: service.name, value: service.id}))
                    onSelected: value => root.setWebmail(value)
                }
            }
        }
    }
}
