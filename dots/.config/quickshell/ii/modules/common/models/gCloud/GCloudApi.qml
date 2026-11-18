pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import ".."

NestableObject {
    id: root

    enum State {
        Done, Preparing, Processing, Error
    }

    signal finished()
    signal error(message: string)
    property int errorCode
    property string errorMessage: ""
    property var outputData
    property var state: GCloudApi.State.Done

    property var pendingRequest: null
    property var activeJob: null

    function startRequest(request) {
        if (root.activeJob) {
            root.activeJob.destroy();
            root.activeJob = null;
        }
        root.pendingRequest = request;
        root.state = GCloudApi.State.Preparing;
        root.errorCode = 0;
        root.errorMessage = "";
        root.outputData = undefined;
        GoogleCloud.load();
        root.submitWhenReady();
    }

    function submitWhenReady() {
        if (!root.pendingRequest || !GoogleCloud.tokenReady) return;
        const request = root.pendingRequest;
        root.pendingRequest = null;
        if (GoogleCloud.keyError || GoogleCloud.tokenError || !GoogleCloud.token) {
            root.fail(Translation.tr("Set your Google Cloud service account key"));
            return;
        }
        root.state = GCloudApi.State.Processing;
        root.activeJob = requestProcess.createObject(root, {
            request: Object.assign({}, request, {token: GoogleCloud.token, project: GoogleCloud.projectId})
        });
        root.activeJob.running = true;
    }

    Connections {
        target: GoogleCloud
        function onTokenReadyChanged() { root.submitWhenReady(); }
    }

    Component {
        id: requestProcess
        Process {
            id: job
            required property var request
            command: [Quickshell.shellPath("scripts/helper"), "cloud-screen"]
            stdinEnabled: true
            onStarted: {
                job.write(JSON.stringify(job.request));
                job.stdinEnabled = false;
                job.request = null;
            }
            stdout: StdioCollector { id: response }
            onExited: (code, status) => {
                if (root.activeJob !== job) return;
                root.activeJob = null;
                if (code === 0 && status === 0) root.handleApiOutput(response.text);
                else root.fail(Translation.tr("Google Cloud request failed"));
                job.destroy();
            }
        }
    }

    function fail(message, code = 0) {
        root.state = GCloudApi.State.Error;
        root.errorCode = code;
        root.errorMessage = message;
        root.error(message);
    }

    function handleApiOutput(out: string): bool {
        try {
            root.outputData = JSON.parse(out);
            if (outputData.error) {
                root.fail(outputData.error.message, outputData.error.code);
                return false;
            }
            root.state = GCloudApi.State.Done;
            root.finished();
            return true
        } catch (e) {
            root.fail(Translation.tr("Failed to parse API response"));
            return false;
        }
    }
}
