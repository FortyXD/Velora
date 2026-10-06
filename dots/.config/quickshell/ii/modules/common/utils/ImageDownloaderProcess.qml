import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

Process {
    id: root

    signal done(string path, int width, int height);
    required property string filePath;
    required property string sourceUrl;
    property string downloadUserAgent: Config.options?.networking.userAgent ?? ""
    
    function processFilePath() {
        return StringUtils.shellSingleQuoteEscape(FileUtils.trimFileProtocol(filePath));
    }

    running: true
    // Download to a temp file and move it into place only when complete: a stalled transfer
    // must not leave a broken file in the cache (an existing file is never downloaded again)
    command: ["bash", "-c", 
        `mkdir -p $(dirname '${processFilePath()}'); [ -f '${processFilePath()}' ] || `
        + `{ curl -sSL --fail --connect-timeout 8 --speed-limit 1024 --speed-time 10 --max-time 60 '${sourceUrl}' -o '${processFilePath()}.part' `
        + `&& mv -f '${processFilePath()}.part' '${processFilePath()}' || { rm -f '${processFilePath()}.part'; false; }; } `
        + `&& file '${processFilePath()}'`
    ]
    stdout: StdioCollector {
        id: imageSizeOutputCollector
        onStreamFinished: {
            const output = imageSizeOutputCollector.text.trim();
            const match = output.match(/(\d+)\s*x\s*(\d+)/);

            if (match) {
                const width = Number(match[1]);
                const height = Number(match[2]);
                root.done(root.filePath, width, height);
            }
        }
    }
}
