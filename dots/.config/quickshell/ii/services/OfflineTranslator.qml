pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtCore
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Offline English <-> Russian translation with CTranslate2 (scripts/translate/nmt_server.py),
 * plus optional refinement by a local Ollama model.
 * The translation server only runs while it's being used: it's stopped after a short idle period.
 */
Singleton {
    id: root

    readonly property var languages: ({ "en": "English", "ru": "Russian" })
    readonly property string dataDir: FileUtils.trimFileProtocol(StandardPaths.standardLocations(StandardPaths.GenericDataLocation)[0]) + "/folis/translate"
    readonly property string pythonPath: `${root.dataDir}/venv/bin/python`
    readonly property string scriptDir: FileUtils.trimFileProtocol(`${Directories.scriptPath}/translate`)
    property int idleTimeout: 120000
    property int refineTimeout: 180000

    property bool installed: false
    property bool checked: false
    readonly property bool installing: installProc.running
    property int installProgress: 0
    property string installStatus: ""
    property string installError: ""

    property int lastRequestId: 0
    property var callbacks: ({})
    readonly property bool busy: Object.keys(root.callbacks).length > 0

    // Script-based detection is enough for two languages and costs nothing
    function detectLanguage(text) {
        const cyrillic = (text.match(/[Ѐ-ӿ]/g) ?? []).length;
        const latin = (text.match(/[A-Za-z]/g) ?? []).length;
        return cyrillic > latin ? "ru" : "en";
    }

    function otherLanguage(code) {
        return code === "ru" ? "en" : "ru";
    }

    function checkInstalled() {
        checkProc.running = true;
    }

    function install() {
        if (installProc.running) return;
        root.installError = "";
        root.installProgress = 0;
        root.installStatus = Translation.tr("Starting…");
        installProc.running = true;
    }

    // callback(text, error). Returns the request id; callers ignore replies to older ids.
    function translate(text, src, tgt, callback) {
        const id = ++root.lastRequestId;
        root.callbacks = Object.assign({}, root.callbacks, { [id]: callback });
        // The process is created synchronously when started; input written before it's up is buffered
        if (!server.running) server.running = true;
        server.write(JSON.stringify({ "id": id, "text": text, "src": src, "tgt": tgt }) + "\n");
        idleTimer.restart();
        return id;
    }

    function finishRequest(id, text, error) {
        const callback = root.callbacks[id];
        const remaining = Object.assign({}, root.callbacks);
        delete remaining[id];
        root.callbacks = remaining;
        if (callback) callback(text, error);
    }

    function failPending() {
        for (const id of Object.keys(root.callbacks)) {
            root.finishRequest(id, "", Translation.tr("The offline translator stopped unexpectedly"));
        }
    }

    // Asks a local Ollama model to polish a machine translation. callback(text, error). Returns an abort function.
    function refine(text, draft, src, tgt, model, callback) {
        const xhr = new XMLHttpRequest();
        const timer = refineTimerComponent.createObject(root, { "interval": root.refineTimeout });
        let finished = false;
        const done = (result, error) => {
            if (finished) return;
            finished = true;
            timer.stop();
            timer.destroy();
            callback(result, error);
        };
        timer.triggered.connect(() => {
            xhr.abort();
            done("", Translation.tr("The model took too long to answer"));
        });
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) {
                done("", xhr.status === 0 ? Translation.tr("Ollama isn't running") : Translation.tr("Ollama error (HTTP %1)").arg(xhr.status));
                return;
            }
            try {
                const content = JSON.parse(xhr.responseText).message?.content ?? "";
                done(content.replace(/<think>[\s\S]*?<\/think>/g, "").trim(), "");
            } catch (e) {
                done("", Translation.tr("Unexpected answer from Ollama"));
            }
        };
        const prompt = `Translate the following ${root.languages[src]} text into ${root.languages[tgt]}. `
            + `A draft machine translation is given: fix its mistakes and make it sound natural while keeping the meaning. `
            + `Reply with the translation only, without quotes or comments.\n\nText:\n${text}\n\nDraft:\n${draft}`;
        xhr.open("POST", "http://127.0.0.1:11434/api/chat");
        xhr.setRequestHeader("Content-Type", "application/json");
        xhr.send(JSON.stringify({
            "model": model,
            "stream": false,
            "think": false,
            "keep_alive": "2m", // Free the model's memory soon after
            "options": { "temperature": 0.2 },
            "messages": [{ "role": "user", "content": prompt }],
        }));
        timer.start();
        return () => {
            xhr.abort();
            done("", "");
        };
    }

    property Component refineTimerComponent: Timer {
        repeat: false
    }

    Timer {
        id: idleTimer
        interval: root.idleTimeout
        onTriggered: {
            if (root.busy) {
                restart();
                return;
            }
            server.running = false; // Frees the models' memory
        }
    }

    Process {
        id: server
        command: [root.pythonPath, `${root.scriptDir}/nmt_server.py`]
        stdinEnabled: true
        // Also covers a server that fails to start: no request may wait forever
        onRunningChanged: if (!running) root.failPending()
        onExited: (exitCode, exitStatus) => root.failPending()
        stdout: SplitParser {
            onRead: data => {
                try {
                    const reply = JSON.parse(data);
                    root.finishRequest(reply.id, reply.text ?? "", reply.error ?? "");
                } catch (e) {
                    console.warn("[OfflineTranslator] Bad reply:", data);
                }
            }
        }
    }

    Process {
        id: checkProc
        command: ["bash", "-c", `test -x '${root.pythonPath}' && test -f '${root.dataDir}/models/en_ru/model/model.bin' && test -f '${root.dataDir}/models/ru_en/model/model.bin'`]
        onExited: (exitCode, exitStatus) => {
            root.installed = exitCode === 0;
            root.checked = true;
        }
    }

    Process {
        id: installProc
        command: ["bash", `${root.scriptDir}/setup.sh`]
        stdout: SplitParser {
            onRead: data => {
                const line = data.trim();
                if (line.startsWith("PROGRESS ")) {
                    const parts = line.split(" ");
                    root.installProgress = parseInt(parts[1]);
                    root.installStatus = parts.slice(2).join(" ");
                } else if (line.startsWith("ERROR ")) {
                    root.installError = line.substring(6);
                }
            }
        }
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && root.installError.length === 0)
                root.installError = Translation.tr("Installation failed");
            root.checkInstalled();
        }
    }
}
