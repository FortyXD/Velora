import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.overlay

OverlayBackground {
    id: root

    property alias content: textInput.text
    property bool applyingFile: false
    property bool pageActive: true
    readonly property bool displayed: visible && pageActive
    property var copyListEntries: []
    property bool isClickthrough: false
    readonly property real maxCopyButtonSize: 20

    function focusAtEnd() {
        textInput.forceActiveFocus();
        textInput.cursorPosition = textInput.length;
    }

    function saveContent() {
        saveDebounce.stop();
        noteFile.setText(textInput.text);
    }

    function applyFile(value) {
        if (saveDebounce.running || value === textInput.text)
            return;
        const cursor = textInput.cursorPosition;
        const anchor = cursor === textInput.selectionStart ? textInput.selectionEnd : textInput.selectionStart;
        root.applyingFile = true;
        textInput.text = value;
        root.applyingFile = false;
        textInput.select(Math.min(anchor, textInput.length), Math.min(cursor, textInput.length));
    }

    function scheduleCopyButtons() {
        if (root.displayed)
            Qt.callLater(root.updateCopyButtons);
    }

    function updateCopyButtons() {
        if (!root.displayed || viewport.height <= 0 || viewport.width <= 0)
            return;
        // positionAt uses editor coordinates, including the text area's padding.
        const top = viewport.contentY - textInput.y;
        const bottom = top + viewport.height;
        const first = textInput.positionAt(0, Math.max(0, top - root.maxCopyButtonSize));
        const last = textInput.positionAt(textInput.width, bottom);
        const value = textInput.text;
        let start = first > 0 ? value.lastIndexOf("\n", first - 1) + 1 : 0;
        const entries = [];
        while (start <= last && start < value.length) {
            const newline = value.indexOf("\n", start);
            const end = newline < 0 ? value.length : newline;
            if (!(textInput.selectionEnd > start && textInput.selectionStart <= end)) {
                const line = value.slice(start, end).trim();
                if (/^-\s/.test(line)) {
                    const rect = textInput.positionToRectangle(start);
                    if (rect.y < bottom && rect.y + root.maxCopyButtonSize > top)
                        entries.push({content: line.slice(1).trim(), y: rect.y, height: rect.height});
                }
            }
            start = end + 1;
        }
        const previous = root.copyListEntries;
        if (entries.length !== previous.length || entries.some((e, i) =>
                e.content !== previous[i].content || e.y !== previous[i].y || e.height !== previous[i].height))
            root.copyListEntries = entries;
    }

    onDisplayedChanged: {
        if (displayed) {
            Qt.callLater(noteFile.reload);
            scheduleCopyButtons();
        } else {
            if (saveDebounce.running) saveContent();
            copyListEntries = [];
        }
    }
    Component.onCompleted: scheduleCopyButtons()
    Component.onDestruction: if (saveDebounce.running) saveContent()

    implicitWidth: 300
    implicitHeight: 200

    ColumnLayout {
        id: contentItem
        anchors.fill: parent
        spacing: -16

        Flickable {
            id: viewport
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            onContentYChanged: root.scheduleCopyButtons()
            onWidthChanged: root.scheduleCopyButtons()
            onHeightChanged: root.scheduleCopyButtons()

            TextArea.flickable: StyledTextArea {
                id: textInput
                wrapMode: TextEdit.Wrap
                placeholderText: Translation.tr("Write something here...\nUse '-' to create copyable bullet points, like this:\n\nSheep fricker\n- 4x Slab\n- 1x Boat\n- 4x Redstone Dust\n- 1x Sticky Piston\n- 1x End Rod\n- 4x Redstone Repeater\n- 1x Redstone Torch\n- 1x Sheep")
                selectByMouse: true
                persistentSelection: true
                textFormat: TextEdit.PlainText
                background: null
                padding: 24

                onTextChanged: {
                    if (!root.applyingFile) saveDebounce.restart();
                    root.scheduleCopyButtons();
                }
                onContentHeightChanged: root.scheduleCopyButtons()
                onSelectionStartChanged: root.scheduleCopyButtons()
                onSelectionEndChanged: root.scheduleCopyButtons()
                onActiveFocusChanged: if (!activeFocus && saveDebounce.running) root.saveContent()

                Repeater {
                    model: root.copyListEntries.length
                    delegate: RippleButton {
                        id: copyButton
                        required property int index
                        readonly property var entry: root.copyListEntries[index]
                        property bool justCopied: false
                        onEntryChanged: justCopied = false

                        implicitHeight: Math.min(Math.max(entry?.height ?? 0, Appearance.font.pixelSize.normal + 6), root.maxCopyButtonSize)
                        implicitWidth: implicitHeight
                        buttonRadius: height / 2
                        y: entry?.y ?? 0
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        z: 5

                        Timer {
                            id: resetState
                            interval: 700
                            onTriggered: {
                                copyButton.justCopied = false;
                            }
                        }

                        onClicked: {
                            Quickshell.clipboardText = copyButton.entry.content;
                            justCopied = true;
                            resetState.start();
                        }

                        contentItem: Item {
                            anchors.centerIn: parent
                            MaterialSymbol {
                                id: iconItem
                                anchors.centerIn: parent
                                text: copyButton.justCopied ? "check" : "content_copy"
                                iconSize: Appearance.font.pixelSize.normal
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                }
            }
        }

        StyledText {
            id: statusLabel
            Layout.fillWidth: true
            Layout.margins: 16
            horizontalAlignment: Text.AlignRight
            text: saveDebounce.running ? Translation.tr("Saving...") : Translation.tr("Saved    ")
            color: Appearance.colors.colSubtext
        }
    }

    Timer {
        id: saveDebounce
        interval: 500
        repeat: false
        onTriggered: saveContent()
    }

    FileView {
        id: noteFile
        path: Directories.notesPath
        watchChanges: root.displayed
        printErrors: false
        onFileChanged: if (!saveDebounce.running) reload()
        onLoaded: root.applyFile(text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                root.applyFile("");
            else
                console.warn("[Overlay Notes] Error loading file:", error);
        }
    }
}
