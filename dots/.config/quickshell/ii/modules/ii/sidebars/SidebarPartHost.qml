import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.ii.sidebars.parts

/**
 * One part of a sidebar (SidebarLayout): one of the *Part types in parts/. The part gets `host`
 * (this) for its options and state; it may say `partVisible: false` to leave the sidebar (media with
 * nothing playing) and `collapsed: true` to stop taking free height.
 * Built once wanted, then kept: right away, or for parts marked lazy the first time their sidebar opens;
 * a page of tabs only once it's the page shown.
 */
Item {
    id: root
    required property var part
    required property Item column // SidebarPartsColumn
    property bool current: true // A page of tabs: the one shown
    property bool page: false
    readonly property string uid: root.part?.uid ?? ""
    readonly property string type: root.part?.type ?? ""
    readonly property var meta: SidebarCatalog.part(root.type)
    readonly property var options: SidebarLayout.optionsOf(root.part)
    readonly property bool open: root.column?.open ?? false
    readonly property bool active: root.open && root.current
    readonly property Item item: loader.item
    readonly property bool partVisible: loader.item?.partVisible ?? true
    readonly property bool collapsed: loader.item?.collapsed ?? false

    readonly property bool wanted: root.current && (root.open || !(root.meta?.lazy ?? false))
    property bool built: false
    onWantedChanged: if (root.wanted) root.built = true
    Component.onCompleted: if (root.wanted) root.built = true

    // Gives the part the keyboard (a chat's or a search field's input)
    function focusPart() {
        const target = loader.item?.focusTarget ?? loader.item;
        target?.forceActiveFocus();
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: root.built && root.type.length > 0
        // Tabs hold hosts themselves, so they're loaded by file rather than named here (a cycle of types)
        source: active && root.type === "tabs" ? Qt.resolvedUrl("parts/TabsPart.qml") : ""
        sourceComponent: ({ "header": headerComponent, "sliders": slidersComponent, "toggles": togglesComponent, "tools": toolsComponent, "notifications": notificationsComponent, "media": mediaComponent, "weather": weatherComponent, "system": systemComponent, "calendar": calendarComponent, "todo": todoComponent, "timer": timerComponent, "notes": notesComponent, "clipboard": clipboardComponent, "ai": aiComponent, "translator": translatorComponent, "anime": animeComponent })[root.type] ?? null
        onLoaded: {
            if (loader.item.host !== undefined) loader.item.host = root;
            if (root.active && root.page) Qt.callLater(root.focusPart);
        }
    }

    Component {
        id: headerComponent
        HeaderPart {}
    }
    Component {
        id: slidersComponent
        SlidersPart {}
    }
    Component {
        id: togglesComponent
        TogglesPart {}
    }
    Component {
        id: toolsComponent
        ToolsPart {}
    }
    Component {
        id: notificationsComponent
        NotificationsPart {}
    }
    Component {
        id: mediaComponent
        MediaPart {}
    }
    Component {
        id: weatherComponent
        WeatherPart {}
    }
    Component {
        id: systemComponent
        SystemPart {}
    }
    Component {
        id: calendarComponent
        CalendarPart {}
    }
    Component {
        id: todoComponent
        TodoPart {}
    }
    Component {
        id: timerComponent
        TimerPart {}
    }
    Component {
        id: notesComponent
        NotesPart {}
    }
    Component {
        id: clipboardComponent
        ClipboardPart {}
    }
    Component {
        id: aiComponent
        AiPart {}
    }
    Component {
        id: translatorComponent
        TranslatorPart {}
    }
    Component {
        id: animeComponent
        AnimePart {}
    }
}
