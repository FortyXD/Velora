#!/usr/bin/env python3
"""Offline comparison on synthetic queries; never modifies installed models.
Run with the Lens venv + onnx available. Generates a candidate only; promotion
requires the recorded CPU/quality thresholds and all navigation scenarios.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import shutil
import subprocess


def metrics(rows):
    rows=[r for r in rows if r['phase']=='indexed']
    relevant=[r for r in rows if r['expected'] is not None]
    times=sorted(r['ms'] for r in rows)
    return {'recall5':sum(r['expected'] in r['found'][:5] for r in relevant)/len(relevant),
            'ndcg10':sum(1/math.log2(r['found'].index(r['expected'])+2) if r['expected'] in r['found'][:10] else 0 for r in relevant)/len(relevant),
            'p50_ms':statistics.median(times),'p95_ms':times[math.ceil(len(times)*.95)-1],
            'scenarios_passed':all(r['pass'] for r in rows),'queries':len(rows)}


def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--test-binary',type=Path,required=True);p.add_argument('--repeat',type=int,default=3);a=p.parse_args()
    from onnxruntime.quantization import quantize_dynamic,QuantType
    a.output.mkdir(parents=True,exist_ok=True);results={}
    for precision in ['fp32','int8']:
        data=a.output/precision/'velora-lens';models=data/'models';models.mkdir(parents=True,exist_ok=True)
        manifest=json.loads((a.source/'models/manifest.json').read_text())
        for name in manifest['files']:
            source=(a.source/'models'/name).resolve();target=models/name
            if target.is_symlink():target.unlink()
            if target.exists():continue
            if precision=='int8' and name in ['e5-text.onnx','reranker.onnx']:
                quantize_dynamic(source,target,per_channel=True,weight_type=QuantType.QInt8,op_types_to_quantize=['MatMul'])
            else:
                try:os.link(source,target)
                except OSError:shutil.copy2(source,target)
        for name in manifest['files']:
            with (models/name).open('rb') as f:manifest['files'][name]=hashlib.file_digest(f,'sha256').hexdigest()
        manifest['precision']=precision
        manifest['embedding_revision']=str(manifest.get('embedding_revision',''))+'-eval-'+precision
        (models/'manifest.json').write_text(json.dumps(manifest))
        venv=data/'venv'
        if not venv.exists():venv.symlink_to((a.source/'venv').resolve(),target_is_directory=True)
        runs=[]
        for n in range(a.repeat):
            report=a.output/f'{precision}-{n}.json'
            env={**os.environ,'XDG_DATA_HOME':str(data.parent.resolve()),'VELORA_LENS_EVAL_REPORT':str(report.resolve()),'VELORA_LENS_PYTHON':str((a.source/'venv/bin/python').absolute())}
            with (a.output/f'{precision}-{n}.log').open('w') as log:
                result=subprocess.run([str(a.test_binary.resolve()),'--ignored','--nocapture'],env=env,stdout=log,stderr=subprocess.STDOUT)
            if not report.exists():raise RuntimeError('Evaluation did not produce a report; inspect the log')
            rows=json.loads(report.read_text())
            if any(r.get('problem') for r in rows):raise RuntimeError('Model was unavailable: timing comparison is invalid; inspect logs')
            runs.append(metrics(rows))
        results[precision]={k:all(r[k] for r in runs) if isinstance(runs[0][k],bool) else statistics.median(r[k] for r in runs) for k in runs[0]}
        results[precision]['runs']=runs
    base,new=results['fp32'],results['int8']
    results['accept_int8']=(base['scenarios_passed'] and new['scenarios_passed'] and new['p95_ms']<=base['p95_ms']*.8 and new['recall5']>=base['recall5']-.01 and new['ndcg10']>=base['ndcg10']-.01)
    results['note']='CPUExecutionProvider only. New index for every run; cold model startup included. No battery energy claim.'
    (a.output/'comparison.json').write_text(json.dumps(results,indent=2)+'\n')
    print(json.dumps(results,indent=2))

if __name__=='__main__':main()
