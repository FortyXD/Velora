import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.sidebarLeft.aiChat

ColumnLayout {
    id: root
    signal searchRequested()
    property bool embedded: false
    property alias inputField: input
    property real maximumTranscriptHeight: 350
    readonly property bool cpuOnly: Assistant.profile.provider === "ollama" && (!Assistant.profile.gpu || PowerSaving.onBattery)
    readonly property string modelName: (Assistant.useStrong ? Assistant.profile.strong_model : Assistant.profile.model) || Translation.tr("Choose a model")
    readonly property string problem: Assistant.problem || SidebarChat.problem
    visible: Assistant.available && (embedded || Assistant.panelOpen)
    Layout.fillWidth: true
    spacing: 12

    function focusInput() { input.forceActiveFocus(); }
    function send() {
        if (SidebarChat.busy || !input.text.trim()) return;
        Assistant.submitFollowUp(input.text.trim(), input.text.trim(), root.embedded ? "sidebar" : "launcher");
    }
    function editRequest() {
        const last = Assistant.messages.filter(message => message.role === "user").slice(-1)[0];
        if (last) { SidebarChat.draft = last.text; input.selectAll(); focusInput(); }
    }
    onVisibleChanged: if (visible && !embedded) Qt.callLater(root.focusInput)

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 12
        spacing: 10
        Rectangle {
            implicitWidth: 38; implicitHeight: 38
            radius: 13
            color: Appearance.colors.colSecondaryContainer
            MaterialSymbol { anchors.centerIn: parent; text: "auto_awesome"; iconSize: 22; color: Appearance.colors.colOnSecondaryContainer }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText { text: "Velora AI"; font.weight: Font.DemiBold; font.pixelSize: Appearance.font.pixelSize.normal }
            StyledText {
                Layout.fillWidth: true
                text: root.modelName + (root.cpuOnly ? " · CPU" : "")
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
        ChatIconButton {
            symbol: "open_in_full"; tooltip: Translation.tr("Open conversation")
            onClicked: { GlobalStates.sidebarLeftOpen = true; Assistant.panelOpen = false; }
        }
        ChatIconButton {
            symbol: "add_comment"; tooltip: Translation.tr("New conversation")
            enabled: !SidebarChat.busy
            onClicked: { SidebarChat.newConversation(); root.focusInput(); }
        }
        ChatIconButton {
            objectName: "launcherAssistantClose"
            visible: !root.embedded
            symbol: "close"; tooltip: Translation.tr("Back to search")
            onClicked: { Assistant.panelOpen = false; root.searchRequested(); }
        }
    }

    ScrollView {
        id: scroll
        objectName: "launcherAssistantTranscript"
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(root.maximumTranscriptHeight, Math.max(88, conversation.implicitHeight + 8))
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        property bool followTail: true
        function revealLatest() {
            if (followTail && contentItem) contentItem.contentY = Math.max(0, contentHeight - availableHeight);
        }
        onContentHeightChanged: if (followTail) Qt.callLater(scroll.revealLatest)
        Connections {
            target: scroll.contentItem
            ignoreUnknownSignals: true
            function onMovementEnded() { scroll.followTail = scroll.contentItem.contentY + scroll.availableHeight >= scroll.contentHeight - 24; }
        }
        Connections {
            target: Assistant
            function onSubmitted() { scroll.followTail = true; Qt.callLater(scroll.revealLatest); }
            function onApprovalChanged() { if (Assistant.approval) { scroll.followTail = true; Qt.callLater(scroll.revealLatest); } }
        }
        ColumnLayout {
            id: conversation
            width: scroll.availableWidth
            spacing: 16
            Repeater {
                model: Assistant.messages
                delegate: ColumnLayout {
                    id: messageRow
                    required property var modelData
                    readonly property bool user: modelData.role === "user"
                    Layout.fillWidth: true
                    spacing: 5
                    StyledText {
                        visible: !messageRow.user
                        text: "Velora"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: Appearance.colors.colSubtext
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.maximumWidth: messageRow.user ? conversation.width * 0.93 : conversation.width
                        Layout.alignment: messageRow.user ? Qt.AlignRight : Qt.AlignLeft
                        implicitHeight: messageText.implicitHeight + (messageRow.user ? 22 : 4)
                        radius: Appearance.rounding.normal
                        color: messageRow.user ? Appearance.colors.colLayer2 : "transparent"
                        ChatMarkdown {
                            id: messageText
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: messageRow.user ? 11 : 2 }
                            content: messageRow.modelData.text
                            sourceView: messageRow.user
                        }
                    }
                }
            }
            ColumnLayout {
                visible: Assistant.streaming.length > 0
                Layout.fillWidth: true
                spacing: 5
                StyledText { text: "Velora"; font.pixelSize: Appearance.font.pixelSize.smaller; font.weight: Font.Medium; color: Appearance.colors.colSubtext }
                ChatMarkdown { Layout.fillWidth: true; content: Assistant.streaming; completed: false }
            }
            ColumnLayout {
                visible: !Assistant.messages.length && !Assistant.streaming && !root.problem
                Layout.fillWidth: true
                Layout.topMargin: 12
                Layout.bottomMargin: 12
                spacing: 6
                StyledText { text: Translation.tr("What can I help with?"); font.pixelSize: Appearance.font.pixelSize.normal; font.weight: Font.Medium }
                StyledText {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: Translation.tr("Ask a question or describe a task. You review changes before they run.")
                    color: Appearance.colors.colSubtext
                }
            }
            RowLayout {
                visible: SidebarChat.currentReply?.truncated ?? false
                Layout.fillWidth: true
                spacing: 8
                StyledText {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: Translation.tr("Response limit reached. Ask to continue.")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                RippleButtonWithIcon {
                    materialIcon: "arrow_forward"; mainText: Translation.tr("Continue")
                    enabled: !SidebarChat.busy
                    onClicked: Assistant.submitFollowUp(Translation.tr("Continue your response."), undefined, root.embedded ? "sidebar" : "launcher")
                }
            }
            Repeater {
                model: Assistant.completedSteps
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    MaterialSymbol { text: "check_circle"; iconSize: 18; color: Appearance.colors.colPrimary }
                    ChatTextBlock {
                        Layout.fillWidth: true; markdown: false
                        content: modelData.label + (modelData.result?.path ? "\n" + modelData.result.path : "")
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
            Repeater {
                model: Assistant.choices
                delegate: RippleButtonWithIcon {
                    required property var modelData
                    Layout.fillWidth: true
                    mainText: modelData.label || modelData.value
                    materialIcon: "arrow_forward"
                    enabled: !SidebarChat.busy
                    onClicked: Assistant.submitChoice(modelData.value, modelData.label, root.embedded ? "sidebar" : "launcher")
                }
            }
            Rectangle {
                visible: root.problem.length > 0
                Layout.fillWidth: true
                implicitHeight: errorContent.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Qt.rgba(Appearance.colors.colError.r, Appearance.colors.colError.g, Appearance.colors.colError.b, 0.08)
                border.width: 1
                border.color: Qt.rgba(Appearance.colors.colError.r, Appearance.colors.colError.g, Appearance.colors.colError.b, 0.2)
                ColumnLayout {
                    id: errorContent
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 8
                    RowLayout {
                        spacing: 8
                        MaterialSymbol { text: "error_outline"; iconSize: 20; color: Appearance.colors.colError }
                        StyledText { Layout.fillWidth: true; wrapMode: Text.Wrap; text: Translation.tr("The request could not be completed"); font.weight: Font.Medium }
                    }
                    ChatTextBlock { Layout.fillWidth: true; content: root.problem; markdown: false; color: Appearance.colors.colSubtext }
                    RippleButtonWithIcon {
                        materialIcon: "edit"; mainText: Translation.tr("Edit request")
                        enabled: !SidebarChat.busy && Assistant.messages.some(message => message.role === "user")
                        onClicked: root.editRequest()
                    }
                }
            }
            Rectangle {
                visible: Assistant.approval !== null
                Layout.fillWidth: true
                implicitHeight: approvalContent.implicitHeight + 24
                radius: Appearance.rounding.normal
                color: Appearance.colors.colSecondaryContainer
                ColumnLayout {
                    id: approvalContent
                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                    spacing: 10
                    RowLayout {
                        spacing: 8
                        MaterialSymbol { text: "verified_user"; iconSize: 20; color: Appearance.colors.colOnSecondaryContainer }
                        StyledText { Layout.fillWidth: true; text: Translation.tr("Your confirmation is needed"); font.weight: Font.DemiBold; wrapMode: Text.Wrap }
                    }
                    StyledText { text: Assistant.actionLabel(Assistant.approval?.tool ?? ""); wrapMode: Text.Wrap; Layout.fillWidth: true }
                    ScrollView {
                        id: approvalScroll
                        objectName: "launcherApprovalScroll"
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.min(260, approvalText.implicitHeight)
                        contentWidth: availableWidth
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ChatTextBlock {
                            id: approvalText
                            width: approvalScroll.availableWidth
                            content: Assistant.approvalDescription()
                            markdown: false
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }
                    Image {
                        visible: (Assistant.approval?.details?.preview ?? "").length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? 180 : 0
                        fillMode: Image.PreserveAspectFit
                        source: visible ? "data:image/png;base64," + Assistant.approval.details.preview : ""
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        RippleButtonWithIcon { materialIcon: "check"; mainText: Translation.tr("Allow this action"); enabled: Assistant.approvalReviewComplete; onClicked: Assistant.decide(true) }
                        RippleButtonWithIcon { materialIcon: "close"; mainText: Translation.tr("Cancel"); onClicked: Assistant.decide(false) }
                    }
                }
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: composerContent.implicitHeight + 16
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer2
        border.width: input.activeFocus ? 1 : 0
        border.color: Appearance.colors.colOutlineVariant
        ColumnLayout {
            id: composerContent
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 6
            RowLayout {
                visible: SidebarChat.busy
                Layout.fillWidth: true
                Layout.margins: 4
                spacing: 8
                MaterialSymbol {
                    text: Assistant.approval ? "verified_user" : "progress_activity"
                    iconSize: 16; color: Appearance.colors.colPrimary
                    RotationAnimation on rotation { from: 0; to: 360; duration: 1800; loops: Animation.Infinite; running: root.visible && SidebarChat.busy && !Assistant.approval && Appearance.animationSpeed > 0 }
                }
                StyledText {
                    objectName: "launcherAssistantStatus"
                    Layout.fillWidth: true
                    text: SidebarChat.statusText
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
                StyledText { text: SidebarChat.elapsedSeconds + " " + Translation.tr("s"); font.pixelSize: Appearance.font.pixelSize.smaller; color: Appearance.colors.colSubtext }
            }
            StyledText {
                visible: root.cpuOnly && Assistant.thinking && SidebarChat.elapsedSeconds >= 15
                Layout.fillWidth: true
                Layout.leftMargin: 4; Layout.rightMargin: 4
                text: Translation.tr("Running on CPU. The first response may take longer.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
            ProgressBar { visible: Assistant.download.total > 0; Layout.fillWidth: true; value: (Assistant.download.completed ?? 0) / Math.max(1, Assistant.download.total ?? 1) }
            StyledText { visible: Assistant.selectedPaths.length > 0; text: Translation.tr("Selected files: %1").arg(Assistant.selectedPaths.length); color: Appearance.colors.colSubtext; Layout.fillWidth: true }
            ScrollView {
                id: inputScroll
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(104, Math.max(42, input.implicitHeight))
                contentWidth: availableWidth
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                StyledTextArea {
                    id: input
                    objectName: "launcherAssistantInput"
                    implicitWidth: 0
                    width: inputScroll.availableWidth
                    text: SidebarChat.draft
                    onTextChanged: if (SidebarChat.draft !== text) SidebarChat.draft = text
                    placeholderText: SidebarChat.busy ? Translation.tr("Write your next message…") : Translation.tr("Ask or describe an action…")
                    wrapMode: TextEdit.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    padding: 6
                    selectByMouse: true
                    background: null
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier) && !input.inputMethodComposing) {
                            root.send(); event.accepted = true;
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Shift+Enter for a new line")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    elide: Text.ElideRight
                }
                ChatIconButton {
                    visible: !SidebarChat.busy
                    symbol: "arrow_upward"; tooltip: Translation.tr("Send")
                    enabled: input.text.trim().length > 0
                    toggled: true
                    onClicked: root.send()
                }
                RippleButtonWithIcon {
                    objectName: "launcherAssistantStop"
                    visible: SidebarChat.busy
                    materialIcon: "stop"; mainText: Translation.tr("Stop")
                    onClicked: SidebarChat.stop()
                }
            }
        }
    }
    Flow {
        Layout.fillWidth: true
        spacing: 8
        RippleButtonWithIcon {
            materialIcon: Assistant.extended ? "check_circle" : "more_time"
            mainText: Translation.tr("Extended task")
            colBackground: Assistant.extended ? Appearance.colors.colSecondaryContainer : "transparent"
            enabled: !SidebarChat.busy
            onClicked: Assistant.extended = !Assistant.extended
        }
        RippleButtonWithIcon {
            visible: Assistant.profile.strong_model.length > 0
            materialIcon: Assistant.useStrong ? "check_circle" : "auto_awesome"
            mainText: Translation.tr("Stronger model")
            colBackground: Assistant.useStrong ? Appearance.colors.colSecondaryContainer : "transparent"
            enabled: !SidebarChat.busy
            onClicked: Assistant.useStrong = !Assistant.useStrong
        }
    }
}
