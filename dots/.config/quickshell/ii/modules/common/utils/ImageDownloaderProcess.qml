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
    
    running: true
    // Download to a temp file and move it into place only when complete: a stalled transfer
    // must not leave a broken file in the cache (an existing file is never downloaded again)
    // URLs from image providers and paths are data, never shell source. Each download
    // owns its temporary file so parallel requests cannot publish each other's bytes.
    command: ["bash", "-c",
        'set -eu; mkdir -p -- "$(dirname -- "$1")"; if [ ! -f "$1" ]; then '
        + 'tmp=$(mktemp -- "$1.part.XXXXXX"); trap \'rm -f -- "$tmp"\' EXIT; '
        + 'curl -sSL --fail --connect-timeout 8 --speed-limit 1024 --speed-time 10 --max-time 60 '
        + '--proto "=http,https,file" --proto-redir "=http,https" --user-agent "$3" -o "$tmp" -- "$2"; '
        + 'mv -fT -- "$tmp" "$1"; fi; file -- "$1"',
        "image-download", FileUtils.trimFileProtocol(filePath), sourceUrl, downloadUserAgent
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
