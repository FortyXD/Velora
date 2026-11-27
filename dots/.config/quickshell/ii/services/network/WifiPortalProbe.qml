import Quickshell.Io
import qs.modules.common.functions

Process {
    id: probe
    property string probeUrl: ""
    signal resolved(string url)

    function open(checkUri: string): void {
        if (running) return;
        const url = StringUtils.parseWebUrl(checkUri);
        probeUrl = url?.protocol === "http:" ? checkUri : "http://neverssl.com/";
        running = true;
    }

    // Ask for the portal's first redirect before the browser can upgrade the probe to HTTPS.
    command: ["curl", "--disable", "--noproxy", "*", "--proto", "=http", "--max-time", "3",
        "--silent", "--output", "/dev/null", "--write-out", "%{redirect_url}", "--", probeUrl]
    stdout: StdioCollector { id: output }
    onExited: (code, status) => {
        const redirect = output.text.trim();
        resolved(code === 0 && StringUtils.parseWebUrl(redirect) ? redirect : probeUrl);
    }
}
