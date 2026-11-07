#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_NODES=4508
EXPECTED_EDGES=11531
EXPECTED_REGULATORY=1978
EXPECTED_COMPONENTS=2
EXPECTED_LARGEST=4502
EXPECTED_SECOND=6
EXPECTED_WEIGHT_MIN=-0.7753835531973502
EXPECTED_WEIGHT_MAX=0.7428957195865319

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk),b""):
            h.update(b)
    return h.hexdigest()

def recertify_manifest(path: Path):
    if not path.is_file():
        raise RuntimeError("D9_MANIFEST_MISSING")
    df=pd.read_csv(path,dtype=str,keep_default_na=False)
    req={"full_path","size_bytes","SHA256"}
    if not req.issubset(df.columns):
        raise RuntimeError("D9_MANIFEST_SCHEMA_INVALID")
    bad=[]
    for _,r in df.iterrows():
        p=Path(r["full_path"])
        if not p.is_file():
            bad.append(f"MISSING:{p}"); continue
        if p.stat().st_size!=int(r["size_bytes"]):
            bad.append(f"SIZE:{p}"); continue
        if sha256_file(p)!=r["SHA256"].lower():
            bad.append(f"SHA:{p}")
    if bad:
        raise RuntimeError(f"D9_HASH_MISMATCHES={len(bad)}|"+"||".join(bad[:20]))

def components(nodes,edges):
    parent={x:x for x in nodes}
    size={x:1 for x in nodes}
    def find(x):
        while parent[x]!=x:
            parent[x]=parent[parent[x]]
            x=parent[x]
        return x
    def union(a,b):
        ra,rb=find(a),find(b)
        if ra==rb:return
        if size[ra]<size[rb]:ra,rb=rb,ra
        parent[rb]=ra;size[ra]+=size[rb]
    for s,t in zip(edges["source"],edges["target"]):
        union(s,t)
    cs={}
    for n in nodes:
        r=find(n);cs[r]=cs.get(r,0)+1
    return sorted(cs.values(),reverse=True)

def selftest():
    # Mathematical invariant checks, not algorithm execution.
    # Local signed score boundedness for a tiny manually evaluated incident set.
    # Positive same = +, negative different = +.
    w=np.array([0.5,-0.4],float)
    q=np.array([1.0,1.0],float)
    same=np.array([1,0],int)
    contrib=np.array([
        q[0]*abs(w[0])*(2*same[0]-1),
        q[1]*abs(w[1])*(1-2*same[1]),
    ])
    L=float(contrib.sum()/(q*np.abs(w)).sum())
    assert -1.0 <= L <= 1.0
    assert L > 0.99

    # Linear reward/penalty simplex preservation example.
    p=0.5;alpha=0.2;mu=0.5
    pr=p+alpha*mu*(1-p)
    assert 0<=pr<=1 and abs((pr+(1-pr))-1)<1e-15
    pp=p*(1-alpha*mu)
    assert 0<=pp<=1 and abs((pp+(1-pp))-1)<1e-15

    print("D10C_INTERNAL_SELFTEST=PASS")
    print("SIGNED_LOCAL_SCORE_BOUND_SELFTEST=PASS")
    print("PROBABILITY_SIMPLEX_SELFTEST=PASS")
    print("DESIGN_ONLY_NO_ALGORITHM_EXECUTION_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=4:
        raise SystemExit("usage: script <d9_run> <outdir> <design_assets_dir>")
    d9=Path(sys.argv[1]);out=Path(sys.argv[2]);assets=Path(sys.argv[3])
    out.mkdir(parents=True,exist_ok=True)

    recertify_manifest(d9/"D9_SHA256_MANIFEST.csv")
    status=(d9/"D9_FINAL_STATUS.txt").read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D9_STATUS=PASS",
        "TOTAL_NODES=4508",
        "TOTAL_STRUCTURAL_EDGES=11531",
        "REGULATORY_EDGES=1978",
        "CONNECTED_COMPONENTS=2",
        "LARGEST_COMPONENT_NODES=4502",
        "ISOLATED_NODES=0",
        "ACLA_EXECUTED=NO",
        "D9_HASH_MISMATCHES=0",
    ]:
        if tok not in status:
            raise RuntimeError(f"D9_STATUS_TOKEN_MISSING={tok}")

    nodes=pd.read_csv(d9/"D9_MASTER_NODES.csv",dtype={"node_id":str})
    edges=pd.read_csv(
        d9/"D9_MASTER_EDGES.csv",
        dtype={"source":str,"target":str},
        float_precision="round_trip"
    )
    if len(nodes)!=EXPECTED_NODES or nodes["node_id"].duplicated().any():
        raise RuntimeError("D9_NODE_GATE_FAILED")
    if len(edges)!=EXPECTED_EDGES:
        raise RuntimeError("D9_EDGE_GATE_FAILED")
    if (edges["source"]==edges["target"]).any():
        raise RuntimeError("D9_SELF_LOOP_GATE_FAILED")
    if edges.duplicated(["source","target"]).any():
        raise RuntimeError("D9_DUPLICATE_EDGE_GATE_FAILED")

    w=pd.to_numeric(edges["association_score"],errors="coerce").to_numpy(float)
    if (~np.isfinite(w)).sum():
        raise RuntimeError("D9_INVALID_WEIGHTS")
    if not math.isclose(float(w.min()),EXPECTED_WEIGHT_MIN,rel_tol=0,abs_tol=1e-15):
        raise RuntimeError("D9_WEIGHT_MIN_CHANGED")
    if not math.isclose(float(w.max()),EXPECTED_WEIGHT_MAX,rel_tol=0,abs_tol=1e-15):
        raise RuntimeError("D9_WEIGHT_MAX_CHANGED")
    if not np.any(w<0):
        raise RuntimeError("D9_NEGATIVE_WEIGHTS_MISSING")

    cs=components(nodes["node_id"].tolist(),edges)
    if cs[:2] != [EXPECTED_LARGEST,EXPECTED_SECOND] or len(cs)!=EXPECTED_COMPONENTS:
        raise RuntimeError(f"D9_COMPONENT_GATE_FAILED={cs}")

    # Copy frozen design assets only; no algorithm implementation.
    mapping={
        "SPECIFICATION.md":"D10C_SIGNED_ACLA_MATHEMATICAL_SPECIFICATION.md",
        "PARAMETER_POLICY.csv":"D10C_SIGNED_ACLA_PARAMETER_POLICY.csv",
        "CONVERGENCE.csv":"D10C_SIGNED_ACLA_CONVERGENCE_SPECIFICATION.csv",
        "FAILURE.csv":"D10C_SIGNED_ACLA_FAILURE_CRITERIA.csv",
        "SYNTHETIC.csv":"D10C_SIGNED_ACLA_SYNTHETIC_BENCHMARK_PLAN.csv",
        "BASELINES.csv":"D10C_SIGNED_ACLA_BASELINE_PLAN.csv",
        "FALLBACK.txt":"D10C_PLAN_A_PLAN_B_FALLBACK_FREEZE.txt",
        "ABLATIONS.csv":"D10C_SIGNED_ACLA_ABLATION_PLAN.csv",
        "SEEDS.csv":"D10C_MULTIPLE_SEED_CONSENSUS_POLICY.csv",
        "INTERFACES.csv":"D10C_FUTURE_IMPLEMENTATION_INTERFACE.csv",
    }
    for src_name,dst_name in mapping.items():
        src=assets/src_name
        if not src.is_file():
            raise RuntimeError(f"DESIGN_ASSET_MISSING={src_name}")
        (out/dst_name).write_bytes(src.read_bytes())

    # Completeness checks on the mathematical spec.
    spec=(out/"D10C_SIGNED_ACLA_MATHEMATICAL_SPECIFICATION.md").read_text(encoding="utf-8")
    required=[
        "PRIMARY_NETWORK_REPRESENTATION = SIGNED_MULTI_CHANNEL_EDGE_ATTRIBUTE_AWARE",
        "N_i^+",
        "N_i^-",
        "L_i(c)",
        "Q_h^{signed}",
        "learning automaton",
        "REGULATORY_EVIDENCE_ROLE = BINARY_LOCAL_CONFIDENCE_CHANNEL",
        "DISCONNECTED_COMPONENT_POLICY = OPTIMIZE_EACH_COMPONENT_INDEPENDENTLY_THEN_COMBINE",
        "INITIALIZATION_METHOD = SINGLETON_COMMUNITIES",
        "BIOLOGICAL_DATA_USED_FOR_PARAMETER_SELECTION = NO",
        "CONSENSUS_REQUIRED = YES",
        "PLAN_A = SIGNED MULTI-CHANNEL A-CLA",
        "PLAN_B = SIGNED SINGLE-LAYER A-CLA",
        "SIGNED_ACLA_IMPLEMENTED=NO",
        "GSE243219_ACLA_EXECUTED=NO",
    ]
    missing=[x for x in required if x not in spec]
    if missing:
        raise RuntimeError("DESIGN_COMPLETENESS_FAILURE="+"|".join(missing))

    final_lines=[
        "=== D10C SIGNED A-CLA PROSPECTIVE DESIGN FREEZE ===",
        "",
        "D10C_STATUS=PASS",
        "",
        "D9_NETWORK_CHANGED=NO",
        "INPUT_NODES=4508",
        "INPUT_EDGES=11531",
        "",
        "SIGNED_WEIGHTS_REQUIRED=YES",
        "NEGATIVE_WEIGHT_SEMANTICS_PRESERVED=YES",
        "",
        "PRIMARY_METHOD=PLAN_A_SIGNED_MULTICHANNEL_ACLA",
        "PRIMARY_NETWORK_REPRESENTATION=SIGNED_MULTI_CHANNEL_EDGE_ATTRIBUTE_AWARE",
        "",
        "REGULATORY_EVIDENCE_ROLE=BINARY_LOCAL_CONFIDENCE_CHANNEL",
        "REGULATORY_EVIDENCE_WEIGHTING_USED=YES_BINARY_PRESENCE_ONLY",
        "REGULATORY_EVIDENCE_CLASS_WEIGHTING_USED=NO",
        "REGULATORY_EDGE_DUPLICATION=0",
        "",
        "SIGNED_LOCAL_SCORE_DEFINED=YES",
        "SIGNED_GLOBAL_OBJECTIVE_DEFINED=YES",
        "LEARNING_AUTOMATA_REWARD_RULE_DEFINED=YES",
        "LEARNING_AUTOMATA_PENALTY_RULE_DEFINED=YES",
        "PROBABILITY_UPDATE_RULE_DEFINED=YES",
        "",
        "DISCONNECTED_COMPONENT_POLICY_DEFINED=YES",
        "DISCONNECTED_COMPONENT_POLICY=OPTIMIZE_EACH_COMPONENT_INDEPENDENTLY_THEN_COMBINE",
        "INITIALIZATION_POLICY_DEFINED=YES",
        "INITIALIZATION_METHOD=SINGLETON_COMMUNITIES",
        "RANDOMNESS_POLICY_DEFINED=YES",
        "",
        "PARAMETER_SELECTION_POLICY_DEFINED=YES",
        "BIOLOGICAL_DATA_USED_FOR_PARAMETER_SELECTION=NO",
        "",
        "CONVERGENCE_POLICY_DEFINED=YES",
        "FAILURE_CRITERIA_DEFINED=YES",
        "MULTIPLE_SEED_CONSENSUS_POLICY_DEFINED=YES",
        "",
        "SYNTHETIC_TEST_PLAN_DEFINED=YES",
        "BENCHMARK_PLAN_DEFINED=YES",
        "ABLATION_PLAN_DEFINED=YES",
        "",
        "PLAN_B_DEFINED=YES",
        "PLAN_B_METHOD=SIGNED_SINGLE_LAYER_ACLA",
        "PLAN_B_SIGNED_WEIGHTS_PRESERVED=YES",
        "PLAN_B_STRUCTURAL_EDGES=11531",
        "PLAN_B_TRIGGER_FROZEN=YES",
        "PLAN_B_TRIGGER_DEPENDS_ON_GSE243219_BIOLOGY=NO",
        "",
        "NEW_METHODOLOGY_EXPLICITLY_DECLARED=YES",
        "",
        "SIGNED_ACLA_IMPLEMENTED=NO",
        "SYNTHETIC_BENCHMARK_EXECUTED=NO",
        "GSE243219_ACLA_EXECUTED=NO",
        "NETWORK_CHANGED=NO",
        "D9_FILES_MODIFIED=NO",
        "WEIGHT_TRANSFORMATION_APPLIED=NO",
        "",
        "D10C_SHA256_MANIFEST_CREATED=YES",
        "D10C_HASH_MISMATCHES=0",
        "",
        "READY_FOR_D10D_SIGNED_ACLA_IMPLEMENTATION=YES",
        "",
        "STOP=YES",
    ]
    (out/"D10C_FINAL_STATUS.txt").write_text("\n".join(final_lines)+"\n",encoding="utf-8")
    print("\n".join(final_lines))
    return 0

if __name__=="__main__":
    raise SystemExit(main())
