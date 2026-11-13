"""Opt-in CPU acceptance using an installed model and a fake desktop.
Run only with tests/run_isolated.py and OLLAMA_MODELS pointing at installed weights.
"""
import json,os,time
from pathlib import Path
from test_agent import AgentTests

x=AgentTests();x.setUp();rows=[]
try:
    source=x.root/'project';source.mkdir();(source/'notes.txt').write_text('Synthetic project for archive acceptance')
    x.configure(selection=[str(source)],profile={'provider':'ollama','endpoint':'http://127.0.0.1:11434','model':os.environ.get('VELORA_LIVE_MODEL','qwen3.5:latest'),'gpu':False,'context_tokens':4096})
    for text in ['Создай ZIP из выделенной папки на рабочем столе.','Какой архив ты только что создал?']:
        start=time.monotonic();x.send('submit',{'text':text});_,events=x.until(lambda e:e['type']=='finished',seconds=600)
        rows.append({'seconds':time.monotonic()-start,'events':events})
    assert not (x.root/'opened').exists(), 'Unsupported document opening must not run'
    assert list((x.root/'Desktop').glob('*.zip')), 'The confirmed archive was not created'
    result={'model':os.environ.get('VELORA_LIVE_MODEL','qwen3.5:latest'),'cpu_only':True,'archives':[p.name for p in (x.root/'Desktop').glob('*.zip')],'unexpected_open':(x.root/'opened').exists(),'runs':rows}
    Path('cache/agent-live.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='runs'},ensure_ascii=False))
    print([(round(r['seconds'],2),[e.get('message') for e in r['events'] if e['type']=='error']) for r in rows])
finally:x.tearDown()
