import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Search results over all settings pages.
 * Walks the built pages for items with `settingsSearchable` and matches their `searchText`.
 */
Item {
    id: root

    required property var pages
    property var pageItemAt: index => null // Returns the built page item for a page index
    property string query: ""
    property int maxResults: 40
    property var results: []

    signal resultChosen(int pageIndex, var item)

    function normalize(text) {
        return (text ?? "").toString().toLowerCase().replace(/ё/g, "е").replace(/\s+/g, " ").trim();
    }

    function collect(node, pageIndex, sectionTitle, terms, out) {
        if (!node || out.length >= root.maxResults) return;
        if (node.visible === false) return; // Hidden options don't apply right now
        let section = sectionTitle;
        if (node.settingsSearchable === true) {
            const haystack = root.normalize(node.searchText);
            if (terms.every(term => haystack.includes(term))) {
                const title = node.settingsSection ? node.title : (node.text || node.title || node.label || "");
                if (title && title.length > 0) {
                    out.push({
                        pageIndex: pageIndex,
                        section: node.settingsSection ? "" : sectionTitle,
                        title: title,
                        description: node.description ?? "",
                        icon: (typeof node.buttonIcon === "string" && node.buttonIcon) || (typeof node.icon === "string" && node.icon) || root.pages[pageIndex].icon,
                        isSection: node.settingsSection === true,
                        item: node
                    });
                }
            }
            if (node.settingsSection) section = node.title;
        }
        const kids = node.children ?? [];
        for (let i = 0; i < kids.length; i++) {
            root.collect(kids[i], pageIndex, section, terms, out);
        }
    }

    function refresh() {
        const q = root.normalize(root.query);
        if (q.length === 0) {
            root.results = [];
            return;
        }
        const terms = q.split(" ");
        let out = [];
        // Page names and descriptions match too
        for (let i = 0; i < root.pages.length; i++) {
            const pageText = root.normalize(`${root.pages[i].name} ${root.pages[i].description}`);
            if (terms.every(term => pageText.includes(term))) {
                out.push({
                    pageIndex: i,
                    section: "",
                    title: root.pages[i].name,
                    description: root.pages[i].description,
                    icon: root.pages[i].icon,
                    isPage: true,
                    item: null
                });
            }
        }
        for (let i = 0; i < root.pages.length; i++) {
            root.collect(root.pageItemAt(i), i, "", terms, out);
        }
        root.results = out.slice(0, root.maxResults);
    }

    function acceptFirst() {
        if (root.results.length > 0) root.resultChosen(root.results[0].pageIndex, root.results[0].item);
    }

    onQueryChanged: refreshTimer.restart()
    Timer {
        id: refreshTimer
        interval: 90
        onTriggered: root.refresh()
    }

    StyledFlickable {
        id: resultsFlickable
        anchors.fill: parent
        contentHeight: resultsColumn.implicitHeight + 120
        clip: true

        ColumnLayout {
            id: resultsColumn
            y: 16
            x: Math.round((resultsFlickable.width - width) / 2)
            width: Math.max(0, Math.min(860, resultsFlickable.width - 56))
            spacing: 6

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.bottomMargin: 4
                visible: root.results.length > 0
                text: Translation.tr("Found: %1").arg(root.results.length)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            Repeater {
                model: root.results
                delegate: RippleButton {
                    id: resultButton
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    implicitHeight: resultRow.implicitHeight + 12 * 2
                    leftPadding: 12
                    rightPadding: 12
                    buttonRadius: Appearance.rounding.large
                    colBackground: Appearance.colors.colLayer2
                    colBackgroundHover: Appearance.colors.colLayer2Hover
                    colRipple: Appearance.colors.colLayer2Active
                    onClicked: root.resultChosen(modelData.pageIndex, modelData.item)

                    // Results slide in one after another
                    opacity: 0
                    transform: Translate { id: resultTranslate; y: 10 }
                    Component.onCompleted: resultAnim.start()
                    SequentialAnimation {
                        id: resultAnim
                        PauseAnimation { duration: Math.min(resultButton.index, 10) * 18 }
                        ParallelAnimation {
                            NumberAnimation { target: resultButton; property: "opacity"; to: 1; duration: 220; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                            NumberAnimation { target: resultTranslate; property: "y"; to: 0; duration: 320; easing.type: Easing.BezierSpline; easing.bezierCurve: Appearance.animationCurves.emphasizedDecel }
                        }
                    }

                    contentItem: RowLayout {
                        id: resultRow
                        spacing: 12
                        ConfigIconTile {
                            icon: resultButton.modelData.icon ?? "settings"
                            active: resultButton.modelData.isPage === true || resultButton.index === 0
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                Layout.fillWidth: true
                                text: resultButton.modelData.title
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: (resultButton.modelData.isPage || resultButton.modelData.isSection) ? Font.Medium : Font.Normal
                                color: Appearance.colors.colOnLayer2
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    const pageName = root.pages[resultButton.modelData.pageIndex].name;
                                    if (resultButton.modelData.isPage) return Translation.tr("Page");
                                    if (resultButton.modelData.section && resultButton.modelData.section.length > 0) return `${pageName}  ›  ${resultButton.modelData.section}`;
                                    return pageName;
                                }
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }
                        MaterialSymbol {
                            text: "arrow_forward"
                            iconSize: 20
                            color: Appearance.colors.colSubtext
                        }
                    }
                }
            }
        }
    }

    // Nothing found
    ColumnLayout {
        anchors.centerIn: parent
        visible: root.results.length === 0 && root.normalize(root.query).length > 0 && !refreshTimer.running
        spacing: 10
        MaterialShapeWrappedMaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            shape: MaterialShape.Shape.Cookie9Sided
            text: "search_off"
            iconSize: 40
            padding: 22
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Nothing found")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.Medium
            color: Appearance.colors.colOnLayer1
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Try another word or check the config file")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }
    }
}
