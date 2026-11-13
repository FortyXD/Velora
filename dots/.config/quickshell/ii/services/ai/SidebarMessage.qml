import QtQuick

QtObject {
    property string uid: ""
    property string role: "assistant"
    property string text: ""
    property string model: ""
    property string status: "done"
    property bool hasActions: false
    property bool contextExcluded: false
    property bool truncated: false
    property var attachments: []
    property var steps: []
    property string error: ""
    property string submissionId: ""
    property string transactionId: ""
    property string transactionState: ""
    property bool rollbackAvailable: false
    property var conflicts: []
    property var changes: []
    property var source: null
}
