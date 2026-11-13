import QtQuick
import QtQuick.Window
import qs.modules.common.widgets

// Panels stay instantiated so their scroll positions and settings-search targets survive navigation.
ContentPage {
    id: root

    readonly property bool canNavigateBack: tab !== overviewKey
    property var detailHistory: []
    property string overviewKey: "overview"
    property string previousTab: overviewKey
    property bool returning: false
    property var sectionParents: ({})
    property var sectionTitles: ({})
    property string tab: overviewKey

    function navigateBack() {
        if (!root.canNavigateBack)
            return;
        const history = root.detailHistory.slice();
        const destination = history.pop() ?? {
            key: root.overviewKey,
            focus: null
        };
        root.detailHistory = history;
        root.returning = true;
        root.tab = destination.key;
        root.returning = false;
        Qt.callLater(() => {
            if (destination.focus?.visible && destination.focus?.enabled)
                destination.focus.forceActiveFocus();
            else
                root.forceActiveFocus();
        });
    }
    function navigateToSection(key) {
        const destination = key || root.overviewKey;
        if (destination === root.tab)
            return;
        const existing = root.detailHistory.map(entry => entry.key).lastIndexOf(destination);
        if (existing >= 0) {
            while (root.tab !== destination && root.canNavigateBack)
                root.navigateBack();
            return;
        }
        root.returning = true;
        root.tab = destination;
        root.returning = false;
        const ancestors = [
                  {
                      key: root.overviewKey,
                      focus: null
                  }
              ];
        for (const entry of root.navigationTrail.slice(0, -1))
            ancestors.push({
                               key: entry.key,
                               focus: null
                           });
        root.detailHistory = destination === root.overviewKey ? [] : ancestors;
        root.forceActiveFocus();
    }

    fitToWindow: true
    navigationTrail: {
        const trail = [];
        let section = root.tab;
        while (section && section !== root.overviewKey && !trail.some(entry => entry.key === section)) {
            trail.unshift({
                              key: section,
                              title: root.sectionTitles[section] ?? section
                          });
            section = root.sectionParents[section] ?? root.overviewKey;
        }
        return trail;
    }

    onTabChanged: {
        root.cancelReveal();
        if (root.tab === root.overviewKey)
            root.detailHistory = [];
        else if (!root.returning && root.previousTab !== root.tab) {
            root.detailHistory = [...root.detailHistory,
                                  {
                                      key: root.previousTab,
                                      focus: root.Window.window?.activeFocusItem ?? null
                                  }
                    ];
        }
        root.previousTab = root.tab;
    }
}
