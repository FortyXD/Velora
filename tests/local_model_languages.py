"""CPU-only comparison with simulated desktop tools. Run through tests/run_isolated.py."""
import argparse
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import tempfile
import time
import urllib.request

# Keep app IDs and workspace identical across languages. Day-of-week checks cover
# following the language of the question as well as producing a correct answer.
CASES = {
    "de": ("Welcher Tag kommt nach Montag?", "dienstag", "Öffne VS Code und Firefox auf Arbeitsfläche 5."),
    "en": ("What day follows Monday?", "tuesday", "Open VS Code and Firefox on workspace 5."),
    "es": ("¿Qué día viene después del lunes?", "martes", "Abre VS Code y Firefox en el escritorio 5."),
    "fr": ("Quel jour vient après lundi ?", "mardi", "Ouvre VS Code et Firefox sur le bureau 5."),
    "he": ("איזה יום בא אחרי יום שני?", "שלישי", "פתח את VS Code ואת Firefox בשולחן עבודה 5."),
    "id": ("Hari apa setelah Senin?", "selasa", "Buka VS Code dan Firefox di ruang kerja 5."),
    "it": ("Quale giorno viene dopo lunedì?", "martedì", "Apri VS Code e Firefox sulla scrivania 5."),
    "ja": ("月曜日の次は何曜日ですか？", "火曜", "ワークスペース5でVS CodeとFirefoxを開いて。"),
    "pt": ("Que dia vem depois de segunda-feira?", "terça", "Abra o VS Code e o Firefox na área de trabalho 5."),
    "ru": ("Какой день идёт после понедельника?", "вторник", "Открой VS Code на 5 столе с Firefox."),
    "tr": ("Pazartesiden sonra hangi gün gelir?", "salı", "VS Code ve Firefox’u 5. çalışma alanında aç."),
    "uk": ("Який день іде після понеділка?", "вівторок", "Відкрий VS Code та Firefox на робочому столі 5."),
    "vi": ("Sau thứ hai là thứ mấy?", "thứ ba|thứ 3", "Mở VS Code và Firefox trên không gian làm việc số 5."),
    "zh": ("星期一之后是星期几？", "星期二|周二|週二|礼拜二|禮拜二", "在第5个工作区打开VS Code和Firefox。"),
}
APPS = {"code.desktop": "Visual Studio Code", "firefox.desktop": "Firefox"}
TOOL = {"type":"function","function":{"name":"app_open","description":"Open an installed desktop ID on a workspace.",
        "parameters":{"type":"object","required":["app_id","workspace"],"properties":{
            "app_id":{"type":"string","enum":list(APPS)}, "workspace":{"type":"integer"}}}}}

def generate(base, model, messages, tools=()):
    payload = dict(model=model, messages=messages, think=False, stream=True, keep_alive="15m",
                   options=dict(num_ctx=16384, num_gpu=0, num_thread=4, num_predict=160, temperature=0, seed=42))
    if tools:
        payload["tools"] = tools
    start = time.monotonic()
    req = urllib.request.Request(base+"/api/chat", data=json.dumps(payload).encode(), headers={"Content-Type":"application/json"})
    content, calls, first = "", [], None
    with urllib.request.urlopen(req, timeout=300) as response:
        for line in response:
            part=json.loads(line)
            if part.get("error"): raise ValueError(part["error"])
            msg=part.get("message", {})
            if first is None and (msg.get("content") or msg.get("tool_calls")):
                first=time.monotonic()-start
            content+=msg.get("content","")
            calls.extend(msg.get("tool_calls",[]))
    return content,calls,first

def trial(base, model, question, answer, command, kind, prior):
    start=time.monotonic()
    if kind != "tools":
        history = prior if kind == "switch" else []
        text,calls,first=generate(base,model,history+[{"role":"user","content":question}])
        ok=not calls and bool(re.search(answer,text.casefold()))
        return ok,first,time.monotonic()-start
    messages=[{"role":"system","content":"Use app_open for requested desktop actions. Installed apps: "+str(APPS)+". Reply in the user's language after all actions."},
              {"role":"user","content":command}]
    seen=set()
    first=None
    for turn in range(3):
        text,calls,latency=generate(base,model,messages,[TOOL])
        if turn==0: first=latency
        if not calls:
            return seen==set(APPS) and bool(text.strip()),first,time.monotonic()-start
        messages.append({"role":"assistant","content":text,"tool_calls":calls})
        for call in calls:
            f=call.get("function",{}); args=f.get("arguments",{})
            if f.get("name")!="app_open" or not isinstance(args,dict) or set(args)!={"app_id","workspace"}:
                return False,first,time.monotonic()-start
            app=args["app_id"]
            if app not in APPS or app in seen or args["workspace"]!=5: return False,first,time.monotonic()-start
            seen.add(app)
            messages.append({"role":"tool","tool_name":"app_open","content":json.dumps({"verified":True,**args})})
    return False,first,time.monotonic()-start

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--models",type=Path,required=True)
    p.add_argument("--model",action="append",required=True)
    p.add_argument("--report",type=Path,required=True)
    args=p.parse_args()
    if not os.environ.get("VELORA_TEST_PREBUILT"): p.error("use the isolated test runner")
    with socket.socket() as sock:
        sock.bind(("127.0.0.1",0)); port=sock.getsockname()[1]
    base=f"http://127.0.0.1:{port}"
    with tempfile.TemporaryDirectory() as tmp:
        path=Path(tmp)
        env={**os.environ,"OLLAMA_MODELS":str(args.models),"OLLAMA_HOST":base,"CUDA_VISIBLE_DEVICES":"-1",
             "ROCR_VISIBLE_DEVICES":"-1","OLLAMA_VULKAN":"0","OLLAMA_NO_CLOUD":"1","OLLAMA_NOPRUNE":"1",
             "OLLAMA_NUM_PARALLEL":"1","OLLAMA_MAX_LOADED_MODELS":"1"}
        with (path/"server.log").open("w") as log, args.report.open("a",buffering=1) as output:
            server=subprocess.Popen(["ollama","serve"],env=env,stdout=log,stderr=log)
            try:
                for _ in range(100):
                    try:
                        with urllib.request.urlopen(base+"/api/version",timeout=1): break
                    except OSError:
                        if server.poll() is not None: raise RuntimeError((path/"server.log").read_text()[-1500:])
                        time.sleep(.1)
                for model in args.model:
                    for i,(lang,(q,answer,cmd)) in enumerate(CASES.items()):
                        prev=list(CASES.values())[i-1]
                        history=[{"role":"user","content":prev[0]},{"role":"assistant","content":prev[1].split("|")[0]}]
                        for kind in ("chat","tools","switch"):
                            ok,first,total=trial(base,model,q,answer,cmd,kind,history)
                            with urllib.request.urlopen(base+"/api/ps",timeout=2) as res: active=json.load(res)["models"]
                            assert len(active)==1 and active[0]["size_vram"]==0, "CPU-only runner required"
                            row=dict(model=model,language=lang,task=kind,ok=ok,first_s=first,total_s=total,
                                     resident_model_bytes=active[0]["size"],cold_start=i==0 and kind=="chat")
                            output.write(json.dumps(row)+"\n")
            finally:
                server.terminate()
                try: server.wait(timeout=8)
                except subprocess.TimeoutExpired: server.kill(); server.wait()

if __name__=="__main__": main()
