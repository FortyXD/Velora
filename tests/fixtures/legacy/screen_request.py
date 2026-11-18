"""Send screen OCR and translation requests with credentials and content received on stdin."""
import base64
import json
from pathlib import Path
import re
import sys
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import build_opener, HTTPRedirectHandler, Request


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def build_request(params):
    project = params["project"]
    token = params["token"]
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.:-]*", project) or not re.fullmatch(r"[!-~]+", token):
        raise ValueError("Invalid cloud credentials")
    if params["operation"] == "vision":
        image = base64.b64encode(Path(params["path"]).read_bytes()).decode("ascii")
        url = "https://vision.googleapis.com/v1/images:annotate"
        payload = {"requests": [{"image": {"content": image}, "features": [{"type": "DOCUMENT_TEXT_DETECTION"}]}]}
    elif params["operation"] == "translate":
        url = "https://translation.googleapis.com/v3/projects/" + quote(project, safe="") + ":translateText"
        payload = {"targetLanguageCode": params["language"], "contents": params["contents"], "mimeType": "text/plain"}
    else:
        raise ValueError("Unknown cloud operation")
    return Request(url, data=json.dumps(payload).encode("utf-8"), headers={
        "Authorization": "Bearer " + token, "x-goog-user-project": project, "Content-Type": "application/json"
    })


def main():
    try:
        request = build_request(json.load(sys.stdin))
        with build_opener(NoRedirects()).open(request, timeout=60) as response:
            data = json.load(response)
    except HTTPError as error:
        with error:
            try:
                message = json.load(error)["error"]["message"]
            except (ValueError, KeyError, TypeError):
                message = "Google Cloud request failed"
            data = {"error": {"code": error.code, "message": message}}
    except (OSError, ValueError, KeyError, TypeError):
        return 1
    json.dump(data, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())
