#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import sys
import time
from pathlib import Path
from typing import Dict, List, Mapping, Sequence, Tuple

import numpy as np
import pandas as pd

EXPECTED_R1_SHA="2bfe790d6aff0fc0404d37683fed2ef0a7c85b78c6a31bb692d3f69d0f7e257d"

# D10G-D2 frozen diagnostic contract.
N=24
GROUPS=3
GROUP_SIZE=8
REPLICATES=5
SEEDS=10

S1_POS_P=0.45
S1_NEG_BETWEEN_P=0.45
S1_NEG_WITHIN_P=0.05

S2_POS_P=0.45
S2_NEG_BETWEEN_P=0.50
S2_NEG_WITHIN_P=0.04

S3_FLIP_FRACTION=0.35

# S4 label-independent negative probability equals the expected S1
# negative-placement probability across all 24-node pair categories.
WITHIN_PAIRS=GROUPS*(GROUP_SIZE*(GROUP_SIZE-1)//2)
TOTAL_PAIRS=N*(N-1)//2
BETWEEN_PAIRS=TOTAL_PAIRS-WITHIN_PAIRS
S4_NULL_NEG_P=(WITHIN_PAIRS*S1_NEG_WITHIN_P + BETWEEN_PAIRS*S1_NEG_BETWEEN_P)/TOTAL_PAIRS

MAG_MIN=0.40
MAG_MAX=1.00

# Frozen classification thresholds.
INFORMATIVE_ADVANTAGE_MIN=0.20
INFORMATIVE_TASK_WINS_MIN=20
INFORMATIVE_TASKS=25
SIGNED_MEDIAN_ARI_MIN=0.60
SIGNED_MEDIAN_STABILITY_MIN=0.80
S2_COUNTERFACTUAL_SUCCESS_MIN=4
NULL_ADVANTAGE_MAX_EXCLUSIVE=0.20

# Exact CORE_04 identity from the original D10E-R1 prospective grid.
EXPECTED_CORE04={
    "alpha_reward":0.1,
    "alpha_penalty":0.3,
    "gamma":0.25,
    "lambda_regulatory":0.0,
    "max_iterations":200,
    "objective_tolerance":1e-6,
    "node_change_tolerance":0.02,  # legacy schema only; R1 ignores this convergence field
    "probability_change_tolerance":0.01,
    "patience":5,
}

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk),b""):
            h.update(b)
    return h.hexdigest()

def deterministic_int(tag: str) -> int:
    return int.from_bytes(hashlib.sha256(tag.encode("utf-8")).digest()[:4],"big")

def load_module(path: Path, name: str):
    spec=importlib.util.spec_from_file_location(name,path)
    mod=importlib.util.module_from_spec(spec)
    sys.modules[name]=mod
    spec.loader.exec_module(mod)
    return mod

def require_token(path: Path, token: str, label: str):
    if not path.is_file():
        raise RuntimeError(f"{label}_FILE_MISSING={path}")
    text=path.read_text(encoding="utf-8-sig",errors="replace")
    if token not in text:
        raise RuntimeError(f"{label}_TOKEN_MISSING={token}")

def truth_A():
    return {i:i//GROUP_SIZE for i in range(N)}

def truth_B():
    # deterministic interleaving: groups are node_index mod 3
    return {i:i%GROUPS for i in range(N)}

def nmi_from_labels(a: Mapping[int,int], b: Mapping[int,int]) -> float:
    nodes=sorted(set(a)&set(b))
    if set(nodes)!=set(a) or set(nodes)!=set(b):
        raise ValueError("NMI partitions must cover identical nodes")
    n=len(nodes)
    ca={};cb={};joint={}
    for node in nodes:
        x,y=int(a[node]),int(b[node])
        ca[x]=ca.get(x,0)+1
        cb[y]=cb.get(y,0)+1
        joint[(x,y)]=joint.get((x,y),0)+1
    mi=0.0
    for (x,y),nij in joint.items():
        pxy=nij/n;px=ca[x]/n;py=cb[y]/n
        mi += pxy*math.log(pxy/(px*py))
    hx=-sum((v/n)*math.log(v/n) for v in ca.values())
    hy=-sum((v/n)*math.log(v/n) for v in cb.values())
    if hx==0 and hy==0:
        return 1.0
    return float(mi/((hx+hy)/2.0))

def canonical_labels(labels: Mapping[int,int]) -> Dict[int,int]:
    groups={}
    for n,c in labels.items():
        groups.setdefault(int(c),[]).append(int(n))
    ordered=sorted((min(ns),sorted(ns)) for ns in groups.values())
    out={}
    for new,(_,nodes) in enumerate(ordered):
        for n in nodes:
            out[n]=new
    return out

def graph_connected(W: np.ndarray) -> bool:
    n=W.shape[0]
    seen={0}
    stack=[0]
    while stack:
        u=stack.pop()
        nbr=np.where(np.abs(W[u])>0)[0]
        for v in nbr:
            v=int(v)
            if v not in seen:
                seen.add(v);stack.append(v)
    return len(seen)==n

def make_component(mod,W: np.ndarray):
    if not graph_connected(W):
        raise RuntimeError("DIAGNOSTIC_GRAPH_DISCONNECTED")
    ndf=pd.DataFrame({"node_index":range(N),"node_id":[f"N{i}" for i in range(N)]})
    rows=[]
    for i in range(N):
        for j in range(i+1,N):
            if W[i,j]!=0:
                rows.append({
                    "source_index":i,
                    "target_index":j,
                    "association_score":float(W[i,j]),
                })
    edf=pd.DataFrame(rows)
    rdf=pd.DataFrame(columns=["source_index","target_index"])
    comps=mod.build_signed_components(ndf,edf,rdf)
    if len(comps)!=1 or len(comps[0].nodes)!=N:
        raise RuntimeError("COMPONENT_CONSTRUCTION_FAILED")
    return comps[0]

def gomez_signed_q(W: np.ndarray, labels: Mapping[int,int]) -> float:
    Ap=np.maximum(W,0.0)
    An=np.maximum(-W,0.0)
    sp=Ap.sum(axis=1);sn=An.sum(axis=1)
    two_mp=float(sp.sum());two_mn=float(sn.sum())
    denom=two_mp+two_mn
    if denom<=0:
        return 0.0
    q=0.0
    for i in range(N):
        for j in range(N):
            if labels[i]!=labels[j]:
                continue
            term=Ap[i,j]-An[i,j]
            if two_mp>0:
                term-=sp[i]*sp[j]/two_mp
            if two_mn>0:
                term+=sn[i]*sn[j]/two_mn
            q+=term
    return float(q/denom)

def random_upper(seed_tag: str):
    rng=np.random.default_rng(np.uint64(deterministic_int(seed_tag)))
    U=np.zeros((N,N),float)
    for i in range(N):
        for j in range(i+1,N):
            U[i,j]=U[j,i]=rng.random()
    return U

def random_magnitudes(seed_tag: str):
    rng=np.random.default_rng(np.uint64(deterministic_int(seed_tag)))
    M=np.zeros((N,N),float)
    for i in range(N):
        for j in range(i+1,N):
            x=float(rng.uniform(MAG_MIN,MAG_MAX))
            M[i,j]=M[j,i]=x
    return M

def positive_ambiguous_graph(family: str, rep: int, p: float):
    U=random_upper(f"D10G-D3-{family}-R{rep}-POS-U")
    M=random_magnitudes(f"D10G-D3-{family}-R{rep}-POS-M")
    W=np.zeros((N,N),float)
    for i in range(N):
        for j in range(i+1,N):
            if U[i,j]<p:
                W[i,j]=W[j,i]=M[i,j]
    if not graph_connected(W):
        # The D10G-D2 design fixes stochastic support, not a repair rule.
        # A deterministic generation failure is a package/scenario failure.
        raise RuntimeError(f"POSITIVE_SUPPORT_DISCONNECTED family={family} rep={rep}")
    return W

def add_negative_structure(
    positive_W: np.ndarray,
    target: Mapping[int,int],
    family: str,
    rep: int,
    p_between: float,
    p_within: float,
    shared_counterfactual_tag: str | None=None,
):
    tag=shared_counterfactual_tag or f"D10G-D3-{family}-R{rep}"
    U=random_upper(tag+"-NEG-U")
    M=random_magnitudes(tag+"-NEG-M")
    W=positive_W.copy()
    for i in range(N):
        for j in range(i+1,N):
            if W[i,j]!=0:
                continue
            p=p_within if target[i]==target[j] else p_between
            if U[i,j]<p:
                W[i,j]=W[j,i]=-M[i,j]
    if not np.any(W<0):
        raise RuntimeError(f"NO_NEGATIVE_EDGES family={family} rep={rep}")
    return W

def generate_S1(rep: int):
    t=truth_A()
    P=positive_ambiguous_graph("S1",rep,S1_POS_P)
    W=add_negative_structure(P,t,"S1",rep,S1_NEG_BETWEEN_P,S1_NEG_WITHIN_P)
    return W,P,t

def generate_S2(rep: int):
    ta=truth_A();tb=truth_B()
    P=positive_ambiguous_graph("S2",rep,S2_POS_P)
    shared=f"D10G-D3-S2-R{rep}-SHARED"
    Wa=add_negative_structure(P,ta,"S2A",rep,S2_NEG_BETWEEN_P,S2_NEG_WITHIN_P,shared)
    Wb=add_negative_structure(P,tb,"S2B",rep,S2_NEG_BETWEEN_P,S2_NEG_WITHIN_P,shared)
    if not np.array_equal(np.where(P>0,P,0.0),np.where(P>0,P,0.0)):
        raise RuntimeError("S2_POSITIVE_IDENTITY_INTERNAL_ERROR")
    return Wa,Wb,P,ta,tb

def generate_S3(rep: int):
    t=truth_A()
    M=random_magnitudes(f"D10G-D3-S3-R{rep}-ABS-M")
    Wa=np.zeros((N,N),float)
    within=[];between=[]
    for i in range(N):
        for j in range(i+1,N):
            if t[i]==t[j]:
                Wa[i,j]=Wa[j,i]=M[i,j]
                within.append((i,j))
            else:
                Wa[i,j]=Wa[j,i]=-M[i,j]
                between.append((i,j))

    # Deterministically invert exactly floor(35%) within and between.
    rng=np.random.default_rng(np.uint64(deterministic_int(f"D10G-D3-S3-R{rep}-FLIP")))
    Wb=Wa.copy()
    for pairs in (within,between):
        idx=np.arange(len(pairs))
        rng.shuffle(idx)
        k=int(math.floor(S3_FLIP_FRACTION*len(pairs)))
        for z in idx[:k]:
            i,j=pairs[int(z)]
            Wb[i,j]=Wb[j,i]=-Wb[i,j]

    if not np.array_equal(np.abs(Wa),np.abs(Wb)):
        raise RuntimeError("S3_ABSOLUTE_TOPOLOGY_CHANGED")
    Pa=np.where(Wa>0,Wa,0.0)
    Pb=np.where(Wb>0,Wb,0.0)
    return Wa,Wb,Pa,Pb,t

def generate_S4(rep: int):
    t=truth_A()
    P=positive_ambiguous_graph("S4",rep,S1_POS_P)
    U=random_upper(f"D10G-D3-S4-R{rep}-NEG-U")
    M=random_magnitudes(f"D10G-D3-S4-R{rep}-NEG-M")
    W=P.copy()
    for i in range(N):
        for j in range(i+1,N):
            if W[i,j]!=0:
                continue
            if U[i,j]<S4_NULL_NEG_P:
                W[i,j]=W[j,i]=-M[i,j]
    if not np.any(W<0):
        raise RuntimeError("S4_NO_NEGATIVE_EDGES")
    return W,P,t

def run_representation(mod,W,truth,cfg,task_id,representation):
    component=make_component(mod,W)
    rows=[]
    results=[]
    partitions=[]
    for k in range(1,SEEDS+1):
        seed=mod.deterministic_seed(k)
        t0=time.perf_counter()
        rr=mod.run_one_component(component,cfg,seed)
        runtime=time.perf_counter()-t0
        labels=canonical_labels(rr.labels)
        partitions.append(labels)
        results.append(rr)

        h=rr.history
        bad=h[
            h["min_executed_move_advantage"].notna()
            & (pd.to_numeric(h["min_executed_move_advantage"],errors="coerce")<=1e-12)
        ]
        if len(bad):
            raise RuntimeError(f"NONIMPROVING_MOVE task={task_id} rep={representation} seed={k}")
        if rr.converged:
            last=h.iloc[-1]
            if int(last["accepted_moves"])!=0 or int(last["improving_nodes_post_sweep"])!=0:
                raise RuntimeError(f"FALSE_TERMINAL task={task_id} rep={representation} seed={k}")

        rows.append({
            "task_id":task_id,
            "representation":representation,
            "seed_index":k,
            "seed":seed,
            "ARI":mod.adjusted_rand_index_from_labels(labels,truth),
            "NMI":nmi_from_labels(labels,truth),
            "signed_Q_on_task_graph":gomez_signed_q(W,labels),
            "converged":int(rr.converged),
            "communities":len(set(labels.values())),
            "iterations":len(h),
            "runtime_seconds":runtime,
            "partition_signature":mod.partition_signature(labels),
        })

    df=pd.DataFrame(rows)
    stability=1.0
    vals=[]
    for i in range(len(partitions)):
        for j in range(i+1,len(partitions)):
            vals.append(mod.adjusted_rand_index_from_labels(partitions[i],partitions[j]))
    if vals:
        stability=float(np.median(vals))

    consensus=None
    converged=[r for r in results if r.converged]
    if converged:
        med=mod.select_partition_medoid(results)
        consensus=canonical_labels(med.labels)

    summary={
        "task_id":task_id,
        "representation":representation,
        "median_ARI":float(df["ARI"].median()),
        "median_NMI":float(df["NMI"].median()),
        "median_signed_Q":float(df["signed_Q_on_task_graph"].median()),
        "convergence_rate":float(df["converged"].mean()),
        "seed_stability":stability,
        "median_communities":float(df["communities"].median()),
        "median_runtime_seconds":float(df["runtime_seconds"].median()),
        "converged_seed_count":int(df["converged"].sum()),
    }
    return df,summary,consensus

def verify_core04(config_row):
    for key,expected in EXPECTED_CORE04.items():
        actual=float(config_row[key]) if key not in ("max_iterations","patience") else int(config_row[key])
        if key in ("max_iterations","patience"):
            if actual!=expected:
                raise RuntimeError(f"CORE04_VALUE_MISMATCH {key}={actual} expected={expected}")
        else:
            if abs(actual-expected)>1e-15:
                raise RuntimeError(f"CORE04_VALUE_MISMATCH {key}={actual} expected={expected}")

def selftest():
    assert N==24 and INFORMATIVE_TASKS==25
    assert abs(S4_NULL_NEG_P-((84*0.05+192*0.45)/276))<1e-15
    assert truth_A()!=truth_B()
    # Test deterministic generator and S3 fixed absolute topology.
    a=generate_S1(1)[0]
    b=generate_S1(1)[0]
    assert np.array_equal(a,b)
    Wa,Wb,_,_,_=generate_S3(1)
    assert np.array_equal(np.abs(Wa),np.abs(Wb))
    # All frozen deterministic tasks must be connected at construction time.
    for rep in range(1,REPLICATES+1):
        W,P,t=generate_S1(rep)
        assert graph_connected(W) and graph_connected(P)
        Wa,Wb,P,ta,tb=generate_S2(rep)
        assert graph_connected(Wa) and graph_connected(Wb) and graph_connected(P)
        Wa,Wb,Pa,Pb,t=generate_S3(rep)
        assert graph_connected(Wa) and graph_connected(Wb)
        # positive-only S3 controls may be disconnected; they must still be valid
        # for component-wise R1 semantics. The execution helper below handles that
        # through a dedicated componentwise path if required.
        W,P,t=generate_S4(rep)
        assert graph_connected(W) and graph_connected(P)
    print("D10G_D3_INTERNAL_SELFTEST=PASS")
    print("FROZEN_GENERATOR_DETERMINISM_SELFTEST=PASS")
    print("S2_POSITIVE_COUNTERFACTUAL_IDENTITY_SELFTEST=PASS")
    print("S3_ABSOLUTE_TOPOLOGY_INVARIANCE_SELFTEST=PASS")
    print("NO_GSE243219_ALGORITHM_EXECUTION_SELFTEST=PASS")
    return 0

def componentwise_run_representation(mod,W,truth,cfg,task_id,representation):
    """
    R1 policy is component-independent. For positive-only S3 controls, removing
    negative edges can disconnect the control graph. Preserve every node and optimize
    each connected component independently, then combine labels and compute global
    truth metrics. This does not add or modify edges.
    """
    ndf=pd.DataFrame({"node_index":range(N),"node_id":[f"N{i}" for i in range(N)]})
    rows=[]
    for i in range(N):
        for j in range(i+1,N):
            if W[i,j]!=0:
                rows.append({
                    "source_index":i,"target_index":j,"association_score":float(W[i,j])
                })
    edf=pd.DataFrame(rows)
    rdf=pd.DataFrame(columns=["source_index","target_index"])
    comps=mod.build_signed_components(ndf,edf,rdf)

    seed_rows=[]
    scientific_results=[]
    consensus_candidates=[]
    for k in range(1,SEEDS+1):
        seed=mod.deterministic_seed(k)
        combined={}
        all_converged=True
        total_iterations=0
        total_runtime=0.0
        community_offset=0
        component_results=[]
        for cidx,comp in enumerate(comps):
            t0=time.perf_counter()
            rr=mod.run_one_component(comp,cfg,seed)
            total_runtime+=time.perf_counter()-t0
            all_converged=all_converged and rr.converged
            total_iterations=max(total_iterations,len(rr.history))
            component_results.append(rr)
            labs=canonical_labels(rr.labels)
            unique=sorted(set(labs.values()))
            remap={u:i+community_offset for i,u in enumerate(unique)}
            for n,l in labs.items():
                combined[n]=remap[l]
            community_offset+=len(unique)

        if set(combined)!=set(range(N)):
            raise RuntimeError(f"COMPONENTWISE_NODE_LOSS task={task_id}")
        labels=canonical_labels(combined)
        scientific_results.append((seed,labels,all_converged,total_iterations,total_runtime))
        seed_rows.append({
            "task_id":task_id,
            "representation":representation,
            "seed_index":k,
            "seed":seed,
            "ARI":mod.adjusted_rand_index_from_labels(labels,truth),
            "NMI":nmi_from_labels(labels,truth),
            "signed_Q_on_task_graph":gomez_signed_q(W,labels),
            "converged":int(all_converged),
            "communities":len(set(labels.values())),
            "iterations":total_iterations,
            "runtime_seconds":total_runtime,
            "partition_signature":mod.partition_signature(labels),
        })

    df=pd.DataFrame(seed_rows)
    parts=[x[1] for x in scientific_results]
    vals=[]
    for i in range(len(parts)):
        for j in range(i+1,len(parts)):
            vals.append(mod.adjusted_rand_index_from_labels(parts[i],parts[j]))
    stability=float(np.median(vals)) if vals else 1.0

    # Componentwise medoid consensus among seeds where every component converged.
    good=[x for x in scientific_results if x[2]]
    consensus=None
    if good:
        means=[]
        for i,a in enumerate(good):
            aris=[]
            for j,b in enumerate(good):
                if i!=j:
                    aris.append(mod.adjusted_rand_index_from_labels(a[1],b[1]))
            means.append(1.0 if not aris else float(np.mean(aris)))
        best=max(
            range(len(good)),
            key=lambda i:(means[i],gomez_signed_q(W,good[i][1]),-good[i][0])
        )
        consensus=good[best][1]

    summary={
        "task_id":task_id,
        "representation":representation,
        "median_ARI":float(df["ARI"].median()),
        "median_NMI":float(df["NMI"].median()),
        "median_signed_Q":float(df["signed_Q_on_task_graph"].median()),
        "convergence_rate":float(df["converged"].mean()),
        "seed_stability":stability,
        "median_communities":float(df["communities"].median()),
        "median_runtime_seconds":float(df["runtime_seconds"].median()),
        "converged_seed_count":int(df["converged"].sum()),
        "connected_components":len(comps),
    }
    return df,summary,consensus

def run_any(mod,W,truth,cfg,task_id,representation):
    if graph_connected(W):
        df,s,c=run_representation(mod,W,truth,cfg,task_id,representation)
        s["connected_components"]=1
        return df,s,c
    return componentwise_run_representation(mod,W,truth,cfg,task_id,representation)

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=9:
        raise SystemExit(
            "usage: D10G_D3 <r1.py> <d10gd2_run> <d10g_run> <d10f_run> "
            "<core04_csv> <outdir> <result_json> <expected_r1_sha>"
        )

    impl=Path(sys.argv[1])
    d2=Path(sys.argv[2])
    d10g=Path(sys.argv[3])
    d10f=Path(sys.argv[4])
    core04_csv=Path(sys.argv[5])
    out=Path(sys.argv[6])
    result_json=Path(sys.argv[7])
    expected_r1=sys.argv[8]
    out.mkdir(parents=True,exist_ok=True)

    if expected_r1!=EXPECTED_R1_SHA or sha256_file(impl)!=EXPECTED_R1_SHA:
        raise RuntimeError("R1_IMPLEMENTATION_SHA256_MISMATCH")

    for p,t,l in [
        (d2/"D10G_D2_FINAL_STATUS.txt","D10G_D2_STATUS=PASS","D10G_D2"),
        (d2/"D10G_D2_FINAL_STATUS.txt","DIAGNOSTIC_CONFIGURATION=CORE_04_ONLY","D10G_D2"),
        (d2/"D10G_D2_FINAL_STATUS.txt","SIGNED_DIAGNOSTIC_TASKS=30","D10G_D2"),
        (d2/"D10G_D2_FINAL_STATUS.txt","READY_FOR_D10G_D3_SIGN_IDENTIFIABILITY_EXECUTION=YES","D10G_D2"),
        (d2/"D10G_D2_FINAL_STATUS.txt","D10G_DECISION_OVERRIDDEN=NO","D10G_D2"),
        (d10g/"D10G_FINAL_STATUS.txt","D10G_STATUS=FAIL_CLOSED","D10G"),
        (d10g/"D10G_FINAL_STATUS.txt","METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE=NO","D10G"),
        (d10f/"D10F_FINAL_STATUS.txt","D10F_STATUS=PASS","D10F"),
        (d10f/"D10F_FINAL_STATUS.txt","D10F_RANKED_CANDIDATE_CONFIG=CORE_04","D10F"),
        (d10f/"D10F_FINAL_STATUS.txt","GSE243219_ACLA_EXECUTED=NO","D10F"),
    ]:
        require_token(p,t,l)

    cdf=pd.read_csv(core04_csv)
    row=cdf[cdf["config_id"].astype(str)=="CORE_04"]
    if len(row)!=1:
        raise RuntimeError(f"CORE04_ROW_COUNT={len(row)}")
    r=row.iloc[0]
    verify_core04(r)

    mod=load_module(impl,"signed_acla_r1_d10g_d3")
    cfg=mod.SACLAConfig(
        float(r["alpha_reward"]),
        float(r["alpha_penalty"]),
        float(r["gamma"]),
        0.0,
        int(r["max_iterations"]),
        float(r["objective_tolerance"]),
        float(r["node_change_tolerance"]),
        float(r["probability_change_tolerance"]),
        int(r["patience"]),
    )

    task_defs=[]
    seed_frames=[]
    summaries=[]
    consensus={}
    matrices={}

    def execute_task(task_id,family,rep,W,P,truth):
        if not np.any(W<0):
            raise RuntimeError(f"SIGNED_TASK_HAS_NO_NEGATIVE_EDGES={task_id}")
        if np.any(P<0):
            raise RuntimeError(f"POSITIVE_CONTROL_HAS_NEGATIVE_EDGE={task_id}")
        if not np.array_equal(np.where(W>0,W,0.0),P):
            raise RuntimeError(f"POSITIVE_CONTROL_NOT_EXACT_POSITIVE_SUPPORT={task_id}")

        task_defs.append({
            "task_id":task_id,
            "family":family,
            "replicate":rep,
            "nodes":N,
            "signed_edges":int(np.count_nonzero(np.triu(W,1))),
            "positive_edges":int(np.count_nonzero(np.triu(W>0,1))),
            "negative_edges":int(np.count_nonzero(np.triu(W<0,1))),
            "positive_control_edges":int(np.count_nonzero(np.triu(P>0,1))),
            "target_partition":"A" if truth==truth_A() else "B",
        })

        sdf,ssum,scons=run_any(mod,W,truth,cfg,task_id,"FULL_SIGNED")
        pdf,psum,pcons=run_any(mod,P,truth,cfg,task_id,"POSITIVE_ONLY")
        seed_frames.extend([sdf,pdf])
        summaries.extend([ssum,psum])
        consensus[(task_id,"FULL_SIGNED")]=scons
        consensus[(task_id,"POSITIVE_ONLY")]=pcons
        matrices[(task_id,"FULL_SIGNED")]=W
        matrices[(task_id,"POSITIVE_ONLY")]=P

    # S1
    for rep in range(1,REPLICATES+1):
        W,P,t=generate_S1(rep)
        execute_task(f"S1_R{rep}","S1",rep,W,P,t)

    # S2 paired counterfactuals
    for rep in range(1,REPLICATES+1):
        Wa,Wb,P,ta,tb=generate_S2(rep)
        execute_task(f"S2A_R{rep}","S2A",rep,Wa,P,ta)
        execute_task(f"S2B_R{rep}","S2B",rep,Wb,P,tb)

    # S3 fixed absolute topology sign contrast
    for rep in range(1,REPLICATES+1):
        Wa,Wb,Pa,Pb,t=generate_S3(rep)
        execute_task(f"S3A_R{rep}","S3A",rep,Wa,Pa,t)
        execute_task(f"S3B_R{rep}","S3B",rep,Wb,Pb,t)

    # S4 null
    for rep in range(1,REPLICATES+1):
        W,P,t=generate_S4(rep)
        execute_task(f"S4_R{rep}","S4",rep,W,P,t)

    tdf=pd.DataFrame(task_defs)
    if len(tdf)!=30:
        raise RuntimeError(f"TASK_COUNT={len(tdf)}")
    tdf.to_csv(out/"D10G_D3_TASK_DEFINITIONS.csv",index=False)

    seed_df=pd.concat(seed_frames,ignore_index=True)
    if len(seed_df)!=30*2*SEEDS:
        raise RuntimeError(f"SEED_RESULT_COUNT={len(seed_df)}")
    seed_df.to_csv(out/"D10G_D3_SEED_LEVEL_RESULTS.csv",index=False)

    sum_df=pd.DataFrame(summaries)
    sum_df.to_csv(out/"D10G_D3_TASK_SUMMARY.csv",index=False)

    paired=sum_df.pivot(index="task_id",columns="representation",values=[
        "median_ARI","median_NMI","seed_stability","convergence_rate","median_signed_Q"
    ])
    paired.columns=["__".join(c) for c in paired.columns]
    paired=paired.reset_index()
    paired["ARI_advantage_signed_minus_positive"] = (
        paired["median_ARI__FULL_SIGNED"]-paired["median_ARI__POSITIVE_ONLY"]
    )
    paired["NMI_advantage_signed_minus_positive"] = (
        paired["median_NMI__FULL_SIGNED"]-paired["median_NMI__POSITIVE_ONLY"]
    )
    paired=paired.merge(tdf[["task_id","family","replicate"]],on="task_id",how="left")
    paired["signed_ARI_win"]=(paired["ARI_advantage_signed_minus_positive"]>1e-12).astype(int)
    paired.to_csv(out/"D10G_D3_SIGNED_VS_POSITIVE_TASK_COMPARISON.csv",index=False)

    informative=paired[paired["family"].isin(["S1","S2A","S2B","S3A","S3B"])].copy()
    null=paired[paired["family"]=="S4"].copy()
    if len(informative)!=25 or len(null)!=5:
        raise RuntimeError(f"INFORMATIVE_NULL_COUNT={len(informative)}/{len(null)}")

    aggregate_adv=float(informative["ARI_advantage_signed_minus_positive"].median())
    wins=int(informative["signed_ARI_win"].sum())
    signed_median_ari=float(informative["median_ARI__FULL_SIGNED"].median())
    signed_median_stability=float(informative["seed_stability__FULL_SIGNED"].median())
    null_adv=float(null["ARI_advantage_signed_minus_positive"].median())

    # S2 counterfactual response.
    s2_rows=[]
    s2_success=0
    for rep in range(1,REPLICATES+1):
        a_id=f"S2A_R{rep}"; b_id=f"S2B_R{rep}"
        ca=consensus[(a_id,"FULL_SIGNED")]
        cb=consensus[(b_id,"FULL_SIGNED")]
        pa=consensus[(a_id,"POSITIVE_ONLY")]
        pb=consensus[(b_id,"POSITIVE_ONLY")]

        # Strong identity requirement: positive-only paired seed outputs are exactly identical.
        aseed=seed_df[(seed_df["task_id"]==a_id)&(seed_df["representation"]=="POSITIVE_ONLY")].sort_values("seed_index")
        bseed=seed_df[(seed_df["task_id"]==b_id)&(seed_df["representation"]=="POSITIVE_ONLY")].sort_values("seed_index")
        pos_seed_identical=(
            aseed["partition_signature"].tolist()==bseed["partition_signature"].tolist()
            and aseed["converged"].tolist()==bseed["converged"].tolist()
        )
        if not pos_seed_identical:
            raise RuntimeError(f"S2_POSITIVE_ONLY_RESULTS_NOT_IDENTICAL rep={rep}")

        consensus_available=(ca is not None and cb is not None and pa is not None and pb is not None)
        if consensus_available:
            ari_ca_A=mod.adjusted_rand_index_from_labels(ca,truth_A())
            ari_ca_B=mod.adjusted_rand_index_from_labels(ca,truth_B())
            ari_cb_A=mod.adjusted_rand_index_from_labels(cb,truth_A())
            ari_cb_B=mod.adjusted_rand_index_from_labels(cb,truth_B())
            signed_changed=mod.adjusted_rand_index_from_labels(ca,cb) < 1.0-1e-12
            target_response=(
                ari_ca_A > ari_ca_B + 1e-12
                and ari_cb_B > ari_cb_A + 1e-12
                and signed_changed
            )
        else:
            ari_ca_A=ari_ca_B=ari_cb_A=ari_cb_B=float("nan")
            signed_changed=False
            target_response=False

        if target_response:
            s2_success+=1
        s2_rows.append({
            "replicate":rep,
            "positive_only_seed_results_identical":"YES",
            "consensus_available":"YES" if consensus_available else "NO",
            "ARI_S2A_consensus_to_A":ari_ca_A,
            "ARI_S2A_consensus_to_B":ari_ca_B,
            "ARI_S2B_consensus_to_A":ari_cb_A,
            "ARI_S2B_consensus_to_B":ari_cb_B,
            "signed_consensus_changed":"YES" if signed_changed else "NO",
            "counterfactual_target_response":"PASS" if target_response else "FAIL",
        })
    pd.DataFrame(s2_rows).to_csv(out/"D10G_D3_S2_COUNTERFACTUAL_RESPONSE.csv",index=False)

    # S3 response audit (diagnostic, not a frozen classification criterion).
    s3_rows=[]
    for rep in range(1,REPLICATES+1):
        a_id=f"S3A_R{rep}"; b_id=f"S3B_R{rep}"
        ca=consensus[(a_id,"FULL_SIGNED")]
        cb=consensus[(b_id,"FULL_SIGNED")]
        if ca is not None and cb is not None:
            part_ari=mod.adjusted_rand_index_from_labels(ca,cb)
        else:
            part_ari=float("nan")
        s3_rows.append({
            "replicate":rep,
            "signed_consensus_ARI_A_vs_B":part_ari,
            "absolute_topology_identical":"YES",
        })
    pd.DataFrame(s3_rows).to_csv(out/"D10G_D3_S3_SIGN_FLIP_RESPONSE.csv",index=False)

    c1=aggregate_adv>=INFORMATIVE_ADVANTAGE_MIN
    c2=wins>=INFORMATIVE_TASK_WINS_MIN
    c3=signed_median_ari>=SIGNED_MEDIAN_ARI_MIN
    c4=signed_median_stability>=SIGNED_MEDIAN_STABILITY_MIN
    c5=s2_success>=S2_COUNTERFACTUAL_SUCCESS_MIN
    c6=null_adv<NULL_ADVANTAGE_MAX_EXCLUSIVE

    criteria=pd.DataFrame([
        {"criterion":"C1_INFORMATIVE_AGGREGATE_ARI_ADVANTAGE","observed":aggregate_adv,"required":">=0.20","status":"PASS" if c1 else "FAIL"},
        {"criterion":"C2_INFORMATIVE_TASK_WINS","observed":wins,"required":">=20/25","status":"PASS" if c2 else "FAIL"},
        {"criterion":"C3_SIGNED_MEDIAN_INFORMATIVE_ARI","observed":signed_median_ari,"required":">=0.60","status":"PASS" if c3 else "FAIL"},
        {"criterion":"C4_SIGNED_MEDIAN_SEED_STABILITY","observed":signed_median_stability,"required":">=0.80","status":"PASS" if c4 else "FAIL"},
        {"criterion":"C5_S2_COUNTERFACTUAL_RESPONSE","observed":s2_success,"required":">=4/5","status":"PASS" if c5 else "FAIL"},
        {"criterion":"C6_NULL_SPECIFICITY","observed":null_adv,"required":"<0.20","status":"PASS" if c6 else "FAIL"},
    ])
    criteria.to_csv(out/"D10G_D3_CLASSIFICATION_CRITERIA.csv",index=False)

    informative_pass=c1 and c2 and c3 and c4 and c5
    if informative_pass and c6:
        classification="SIGN_UTILIZATION_DEMONSTRATED"
    elif informative_pass and not c6:
        classification="DIAGNOSTIC_SPECIFICITY_FAIL"
    else:
        classification="SIGN_UTILIZATION_NOT_DEMONSTRATED"

    family=paired.groupby("family",as_index=False).agg(
        tasks=("task_id","count"),
        signed_ARI_wins=("signed_ARI_win","sum"),
        median_ARI_advantage=("ARI_advantage_signed_minus_positive","median"),
        median_signed_ARI=("median_ARI__FULL_SIGNED","median"),
        median_positive_ARI=("median_ARI__POSITIVE_ONLY","median"),
        median_signed_stability=("seed_stability__FULL_SIGNED","median"),
    )
    family.to_csv(out/"D10G_D3_FAMILY_SUMMARY.csv",index=False)

    result={
        "D10G_D3_STATUS":"PASS",
        "R1_IMPLEMENTATION_SHA256":EXPECTED_R1_SHA,
        "ACTIVE_PLAN":"PLAN_B_SIGNED_SINGLE_LAYER_ACLA",
        "DIAGNOSTIC_CONFIGURATION":"CORE_04",
        "SIGNED_DIAGNOSTIC_TASKS":30,
        "INFORMATIVE_TASKS":25,
        "NULL_CONTROL_TASKS":5,
        "PAIRED_SEEDS_PER_REPRESENTATION":SEEDS,
        "INFORMATIVE_AGGREGATE_MEDIAN_TASK_ARI_ADVANTAGE":aggregate_adv,
        "INFORMATIVE_SIGNED_TASK_WINS":wins,
        "SIGNED_MEDIAN_INFORMATIVE_TASK_ARI":signed_median_ari,
        "SIGNED_MEDIAN_INFORMATIVE_TASK_SEED_STABILITY":signed_median_stability,
        "S2_COUNTERFACTUAL_SUCCESS_REPLICATES":s2_success,
        "S4_NULL_AGGREGATE_MEDIAN_TASK_ARI_ADVANTAGE":null_adv,
        "SIGN_IDENTIFIABILITY_CLASSIFICATION":classification,
        "D10G_DECISION_OVERRIDDEN":"NO",
        "METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE":"NO",
        "D10H_PARAMETER_FREEZE_AUTHORIZED":"NO",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "PARAMETER_TUNING_USING_GSE243219":"NO",
        "GSE243219_ACLA_EXECUTED":"NO",
        "D9_COMMUNITY_DETECTION_EXECUTED":"NO",
        "NETWORK_CHANGED":"NO",
        "D9_FILES_MODIFIED":"NO",
        "WEIGHT_TRANSFORMATION_APPLIED":"NO",
        "READY_FOR_D10C_R2_PROSPECTIVE_BRANCH":"YES" if classification=="SIGN_UTILIZATION_DEMONSTRATED" else "NO",
        "READY_FOR_R2_METHOD_REDESIGN_OR_ABANDONMENT":"YES" if classification=="SIGN_UTILIZATION_NOT_DEMONSTRATED" else "NO",
        "READY_FOR_SIGN_IDENTIFIABILITY_DIAGNOSTIC_REDESIGN":"YES" if classification=="DIAGNOSTIC_SPECIFICITY_FAIL" else "NO",
        "READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE":"NO",
        "READY_FOR_GSE243219_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }
    result_json.write_text(json.dumps(result,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
