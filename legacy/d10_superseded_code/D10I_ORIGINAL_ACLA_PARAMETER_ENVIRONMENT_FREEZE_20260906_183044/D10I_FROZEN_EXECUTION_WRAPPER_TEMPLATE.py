#!/usr/bin/env python3
from __future__ import annotations
import hashlib, importlib.util, json, random, sys, time
from pathlib import Path
import numpy as np

EXPECTED_SOURCE_SHA="__SOURCE_SHA__"
EXPECTED_ADJACENCY_SHA="__ADJ_SHA__"
BINARIZE=True
ITERATIONS=200
ALPHA0=0.20
ALPHA_MIN=0.01
GLOBAL_WEIGHT=0.35
PATIENCE=10
SEED=42

def sha256_file(path,chunk=8*1024*1024):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for b in iter(lambda:f.read(chunk),b''):
            h.update(b)
    return h.hexdigest()

def load_module(path):
    spec=importlib.util.spec_from_file_location('published_acla_exact',path)
    mod=importlib.util.module_from_spec(spec)
    sys.modules['published_acla_exact']=mod
    spec.loader.exec_module(mod)
    return mod

def main():
    if len(sys.argv)!=4:
        raise SystemExit('usage: frozen_wrapper <original_source.py> <adjacency.csv> <output_json>')
    source=Path(sys.argv[1]); adjacency=Path(sys.argv[2]); output=Path(sys.argv[3])
    if sha256_file(source)!=EXPECTED_SOURCE_SHA: raise RuntimeError('SOURCE_SHA_MISMATCH')
    if sha256_file(adjacency)!=EXPECTED_ADJACENCY_SHA: raise RuntimeError('ADJACENCY_SHA_MISMATCH')
    random.seed(SEED)
    np.random.seed(SEED)
    mod=load_module(source)
    if not getattr(mod,'HAS_LOUVAIN',False): raise RuntimeError('FROZEN_LOUVAIN_PATH_NOT_AVAILABLE')
    df=mod.load_adjacency(adjacency)
    G=mod.make_graph(df,BINARIZE)
    t0=time.time()
    labels,comms,q=mod.acla_modularity(G,iterations=ITERATIONS,alpha0=ALPHA0,alpha_min=ALPHA_MIN,global_w=GLOBAL_WEIGHT,patience=PATIENCE,seed=SEED)
    result={
        'source_sha256':EXPECTED_SOURCE_SHA,'adjacency_sha256':EXPECTED_ADJACENCY_SHA,
        'binarize':BINARIZE,'iterations':ITERATIONS,'alpha0':ALPHA0,'alpha_min':ALPHA_MIN,
        'global_weight':GLOBAL_WEIGHT,'patience':PATIENCE,'seed':SEED,
        'communities':len(comms),'modularity':float(q),'elapsed_seconds':float(time.time()-t0),
        'labels':{str(k):int(v) for k,v in labels.items()}}
    output.write_text(json.dumps(result,indent=2),encoding='utf-8')
    return 0

if __name__=='__main__': raise SystemExit(main())
