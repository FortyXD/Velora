pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io

/** Renders LaTeX snippets with MicroTeX, caching successful renders by expression. */
Singleton {
    id: root

    readonly property int renderPadding: 4
    property list<string> processedHashes: []
    property var processedExpressions: ({})
    property var renderedImagePaths: ({})
    property var pendingHashes: ({})
    property string microtexBinaryDir: "/opt/MicroTeX"
    property string microtexBinaryName: "LaTeX"
    property string latexOutputPath: Directories.latexOutput

    signal renderFinished(string hash, string imagePath)

    function requestRender(expression) {
        const hash = Qt.md5(expression);
        const imagePath = `${latexOutputPath}/${hash}.svg`;
        if (processedHashes.includes(hash)) {
            renderFinished(hash, imagePath);
            return [hash, false];
        }
        if (root.pendingHashes[hash]) return [hash, false];
        root.pendingHashes[hash] = true;
        root.processedExpressions[hash] = expression;

        // Expressions can come from an AI response. Keep them out of QML and shell
        // source entirely: a static component passes the expression as one argument.
        renderProcess.createObject(root, { hash, expression, imagePath });
        return [hash, true];
    }

    Component {
        id: renderProcess
        Process {
            id: job
            required property string hash
            required property string expression
            required property string imagePath
            property bool didStart: false
            property bool finished: false
            running: true
            workingDirectory: root.microtexBinaryDir
            command: [root.microtexBinaryDir + "/" + root.microtexBinaryName, "-headless",
                "-input=" + job.expression, "-output=" + job.imagePath,
                "-textsize=" + Appearance.font.pixelSize.normal, "-padding=" + root.renderPadding,
                "-foreground=" + Appearance.colors.colOnLayer1, "-maxwidth=0.85"]
            onStarted: job.didStart = true
            // FailedToStart has no exited signal in Quickshell.
            onRunningChanged: if (!running && !job.didStart) job.finish(1, 1)
            onExited: (exitCode, exitStatus) => job.finish(exitCode, exitStatus)
            function finish(exitCode, exitStatus) {
                if (job.finished) return;
                job.finished = true;
                delete root.pendingHashes[job.hash];
                if (exitCode === 0 && exitStatus === 0) {
                    root.processedHashes.push(job.hash);
                    root.renderedImagePaths[job.hash] = job.imagePath;
                    root.renderFinished(job.hash, job.imagePath);
                }
                job.destroy();
            }
        }
    }
}
