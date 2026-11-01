pragma Singleton
import Quickshell

Singleton {
    // Sent through Process stdin with curl --config -, keeping API keys in both
    // URLs and headers out of the command line. No extra config option can be injected.
    function config(url, headers = []) {
        const quote = value => {
            const text = String(value);
            if (/[\x00-\x1f\x7f]/.test(text)) throw new Error("Invalid control character in request");
            return '"' + text.replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"';
        };
        return "url = " + quote(url) + "\n"
            + headers.map(header => "header = " + quote(header) + "\n").join("");
    }
}
