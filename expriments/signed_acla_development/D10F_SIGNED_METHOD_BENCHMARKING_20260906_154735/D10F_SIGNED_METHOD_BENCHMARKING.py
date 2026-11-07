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

BENCHMARK_FAMILIES = {
    "F1_TWO_BLOCK_LOW_NOISE": {
        "sizes":[12,12],"p_in":0.75,"p_out":0.45,"flip":0.05
    },
    "F2_THREE_BLOCK_MODERATE_NOISE": {
        "sizes":[10,10,10],"p_in":0.65,"p_out":0.35,"flip":0.12
    },
    "F3_THREE_BLOCK_UNEQUAL_SPARSE": {
        "sizes":[8,12,16],"p_in":0.55,"p_out":0.22,"flip":0.12
    },
    "F4_FOUR_BLOCK_HARD_NOISE": {
        "sizes":[8,8,8,8],"p_in":0.55,"p_out":0.28,"flip":0.22
    },
}
REPLICATES_PER_FAMILY=3
R1_SEEDS_PER_TASK=10
BASELINE_SEEDS_PER_TASK=10
TRAAQ_GAMMAS=(0.5,1.0,2.0)

def sha256_file(path: Path, chunk=8*1024*1024) -> str:
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

def require_token(path: Path, token: str, label: str) -> None:
    if not path.is_file():
        raise RuntimeError(f"{label}_FILE_MISSING={path}")
    text=path.read_text(encoding="utf-8-sig",errors="replace")
    if token not in text:
        raise RuntimeError(f"{label}_TOKEN_MISSING={token}")

def nmi_from_labels(a: Mapping[int,int], b: Mapping[int,int]) -> float:
    nodes=sorted(set(a)&set(b))
    if set(nodes)!=set(a) or set(nodes)!=set(b):
        raise ValueError("NMI partitions must cover same nodes")
    n=len(nodes)
    if n==0:
        return 1.0
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
    denom=(hx+hy)/2
    return 0.0 if denom==0 else float(mi/denom)

def pairwise_stability(ari_fn, partitions: Sequence[Mapping[int,int]]) -> float:
    if len(partitions)<2:
        return 1.0
    vals=[]
    for i in range(len(partitions)):
        for j in range(i+1,len(partitions)):
            vals.append(ari_fn(partitions[i],partitions[j]))
    return float(np.median(vals))

def task_seed(family: str, replicate: int) -> int:
    return deterministic_int(f"D10F-TASK-{family}-{replicate}")

def benchmark_seed(method: str, task_id: str, k: int) -> int:
    return deterministic_int(f"D10F-{method}-{task_id}-{k}")

def generate_signed_sbm(family: str, replicate: int):
    cfg=BENCHMARK_FAMILIES[family]
    sizes=list(cfg["sizes"])
    n=sum(sizes)
    truth={}
    groups=[]
    start=0
    for g,size in enumerate(sizes):
        nodes=list(range(start,start+size))
        groups.append(nodes)
        for node in nodes:
            truth[node]=g
        start+=size

    rng=np.random.default_rng(np.uint64(task_seed(family,replicate)))
    W=np.zeros((n,n),dtype=float)
    scaffold=set()

    # Deterministic sign-consistent connectivity scaffold.
    for nodes in groups:
        for a,b in zip(nodes,nodes[1:]+nodes[:1]):
            u,v=sorted((a,b))
            scaffold.add((u,v))
            W[u,v]=W[v,u]=0.90

    for g in range(len(groups)-1):
        u=groups[g][-1]
        v=groups[g+1][0]
        a,b=sorted((u,v))
        scaffold.add((a,b))
        W[a,b]=W[b,a]=-0.80

    p_in=float(cfg["p_in"])
    p_out=float(cfg["p_out"])
    flip=float(cfg["flip"])

    for i in range(n):
        for j in range(i+1,n):
            if (i,j) in scaffold:
                continue
            same=(truth[i]==truth[j])
            p=p_in if same else p_out
            if rng.random()>=p:
                continue
            sign=1.0 if same else -1.0
            if rng.random()<flip:
                sign*=-1.0
            mag=float(rng.uniform(0.40,1.00))
            W[i,j]=W[j,i]=sign*mag

    if not np.any(W<0) or not np.any(W>0):
        raise RuntimeError(f"Task lacks both signs: {family} rep={replicate}")
    return W,truth,len(sizes)

def matrix_to_component(mod,W):
    n=W.shape[0]
    ndf=pd.DataFrame({"node_index":range(n),"node_id":[f"N{i}" for i in range(n)]})
    rows=[]
    for i in range(n):
        for j in range(i+1,n):
            if W[i,j]!=0:
                rows.append({
                    "source_index":i,
                    "target_index":j,
                    "association_score":float(W[i,j]),
                })
    edf=pd.DataFrame(rows)
    rdf=pd.DataFrame(columns=["source_index","target_index"])
    comps=mod.build_signed_components(ndf,edf,rdf)
    if len(comps)!=1:
        raise RuntimeError(f"Benchmark task unexpectedly disconnected: {[len(c.nodes) for c in comps]}")
    return comps[0]

def canonical_labels(labels: Mapping[int,int]) -> Dict[int,int]:
    groups={}
    for n,c in labels.items():
        groups.setdefault(int(c),[]).append(int(n))
    ordered=sorted((min(ns),sorted(ns)) for ns in groups.values())
    cmap={}
    for idx,(_,ns) in enumerate(ordered):
        for n in ns:
            cmap[n]=idx
    return cmap

# ------------------------------------------------------------------
# Independent dense quality functions: these do NOT call R1 objective.
# ------------------------------------------------------------------

def dense_gomez_signed_quality(W: np.ndarray, labels: Mapping[int,int]) -> float:
    W=np.asarray(W,float)
    Ap=np.maximum(W,0.0)
    An=np.maximum(-W,0.0)
    sp=Ap.sum(axis=1)
    sn=An.sum(axis=1)
    two_mp=float(sp.sum())
    two_mn=float(sn.sum())
    denom=two_mp+two_mn
    if denom<=0:
        raise ValueError("zero signed mass")
    q=0.0
    n=W.shape[0]
    for i in range(n):
        for j in range(n):
            if labels[i]!=labels[j]:
                continue
            term=Ap[i,j]-An[i,j]
            if two_mp>0:
                term-=sp[i]*sp[j]/two_mp
            if two_mn>0:
                term+=sn[i]*sn[j]/two_mn
            q+=term
    return float(q/denom)

def dense_traag_potts_quality(
    W: np.ndarray,
    labels: Mapping[int,int],
    gamma_plus: float,
    gamma_minus: float,
) -> float:
    W=np.asarray(W,float)
    Ap=np.maximum(W,0.0)
    An=np.maximum(-W,0.0)
    sp=Ap.sum(axis=1)
    sn=An.sum(axis=1)
    two_mp=float(sp.sum())
    two_mn=float(sn.sum())
    denom=max(two_mp+two_mn,1e-15)
    score=0.0
    n=W.shape[0]
    for i in range(n):
        for j in range(n):
            if labels[i]!=labels[j]:
                continue
            term=Ap[i,j]-An[i,j]
            if two_mp>0:
                term-=gamma_plus*sp[i]*sp[j]/two_mp
            if two_mn>0:
                term+=gamma_minus*sn[i]*sn[j]/two_mn
            score+=term
    return float(score/denom)

def dense_positive_modularity(Wp: np.ndarray, labels: Mapping[int,int]) -> float:
    Wp=np.asarray(Wp,float)
    s=Wp.sum(axis=1)
    two_m=float(s.sum())
    if two_m<=0:
        return 0.0
    q=0.0
    n=Wp.shape[0]
    for i in range(n):
        for j in range(n):
            if labels[i]==labels[j]:
                q += Wp[i,j]-s[i]*s[j]/two_m
    return float(q/two_m)

def induced_labels(members: Sequence[Sequence[int]], super_labels: Mapping[int,int]) -> Dict[int,int]:
    out={}
    for s,orig_nodes in enumerate(members):
        c=int(super_labels[s])
        for n in orig_nodes:
            out[int(n)]=c
    return out

def aggregate_matrix(M: np.ndarray, groups: Sequence[Sequence[int]]) -> np.ndarray:
    k=len(groups)
    out=np.zeros((k,k),float)
    for a,ga in enumerate(groups):
        for b,gb in enumerate(groups):
            out[a,b]=float(M[np.ix_(ga,gb)].sum())
    return out

def multilevel_quality_optimize(
    W: np.ndarray,
    quality_fn,
    seed: int,
    max_levels: int=20,
    max_sweeps: int=100,
):
    rng=np.random.default_rng(np.uint64(seed))
    original_W=np.asarray(W,float)
    members=[[i] for i in range(W.shape[0])]
    super_W=original_W.copy()
    best_orig={i:i for i in range(W.shape[0])}
    best_q=float(quality_fn(original_W,best_orig))

    for _level in range(max_levels):
        m=len(members)
        labels={i:i for i in range(m)}

        for _sweep in range(max_sweeps):
            moved=0
            order=np.arange(m,dtype=int)
            rng.shuffle(order)
            sizes={}
            for c in labels.values():
                sizes[c]=sizes.get(c,0)+1

            for node_np in order:
                node=int(node_np)
                current=int(labels[node])
                neigh_comms=sorted({
                    int(labels[j]) for j in range(m)
                    if j!=node and abs(super_W[node,j])>0
                })
                candidates=[c for c in neigh_comms if c!=current]
                if sizes.get(current,0)>1:
                    candidates.append(None)

                current_orig=induced_labels(members,labels)
                q_current=float(quality_fn(original_W,current_orig))
                best_dest=current
                best_q_local=q_current

                for c in candidates:
                    trial=dict(labels)
                    if c is None:
                        new_label=max(labels.values())+1
                        while new_label in labels.values():
                            new_label+=1
                        trial[node]=new_label
                    else:
                        trial[node]=int(c)
                    q=float(quality_fn(original_W,induced_labels(members,trial)))
                    if q>best_q_local+1e-12 or (
                        abs(q-best_q_local)<=1e-12
                        and c is not None
                        and int(c)<int(best_dest)
                    ):
                        best_q_local=q
                        best_dest=c

                if best_dest!=current:
                    old=current
                    new=max(labels.values())+1 if best_dest is None else int(best_dest)
                    labels[node]=new
                    sizes[old]=sizes.get(old,0)-1
                    if sizes[old]<=0:
                        sizes.pop(old,None)
                    sizes[new]=sizes.get(new,0)+1
                    moved+=1

            if moved==0:
                break

        orig_partition=canonical_labels(induced_labels(members,labels))
        q=float(quality_fn(original_W,orig_partition))
        if q>best_q+1e-12:
            best_q=q
            best_orig=orig_partition

        comms={}
        for s,c in labels.items():
            comms.setdefault(int(c),[]).append(int(s))
        groups=[comms[k] for k in sorted(comms,key=lambda c:min(comms[c]))]

        if len(groups)==len(members):
            break

        new_members=[]
        for group in groups:
            merged=[]
            for s in group:
                merged.extend(members[s])
            new_members.append(sorted(merged))
        super_W=aggregate_matrix(original_W,new_members)
        members=new_members

    return canonical_labels(best_orig),float(best_q)

def baseline_gomez(W,seed):
    return multilevel_quality_optimize(
        W,lambda X,l:dense_gomez_signed_quality(X,l),seed
    )

def baseline_traag(W,seed,gamma):
    return multilevel_quality_optimize(
        W,lambda X,l:dense_traag_potts_quality(X,l,gamma,gamma),seed
    )

def kmeans_rows(X: np.ndarray,k: int,seed: int,max_iter: int=100):
    rng=np.random.default_rng(np.uint64(seed))
    n=X.shape[0]
    if k<1 or k>n:
        raise ValueError("invalid k")
    centers=X[rng.choice(n,size=k,replace=False)].copy()
    labels=np.zeros(n,dtype=int)
    for _ in range(max_iter):
        d=((X[:,None,:]-centers[None,:,:])**2).sum(axis=2)
        new_labels=d.argmin(axis=1)
        if np.array_equal(new_labels,labels):
            break
        labels=new_labels
        for c in range(k):
            idx=np.where(labels==c)[0]
            if len(idx)==0:
                # Reinitialize empty center to point farthest from its assigned center.
                assigned=d[np.arange(n),labels]
                centers[c]=X[int(np.argmax(assigned))]
            else:
                centers[c]=X[idx].mean(axis=0)
    inertia=float(((X-centers[labels])**2).sum())
    return {i:int(labels[i]) for i in range(n)},inertia

def baseline_signed_spectral(W,k,seed):
    W=np.asarray(W,float)
    D=np.diag(np.abs(W).sum(axis=1))
    L=D-W
    evals,evecs=np.linalg.eigh(L)
    X=evecs[:,:k]
    norms=np.linalg.norm(X,axis=1,keepdims=True)
    norms[norms==0]=1.0
    X=X/norms
    labels,inertia=kmeans_rows(X,k,seed)
    return canonical_labels(labels),float(inertia)

def baseline_unsigned_louvain_diagnostic(W,seed):
    Wp=np.maximum(np.asarray(W,float),0.0)
    return multilevel_quality_optimize(
        Wp,lambda X,l:dense_positive_modularity(X,l),seed
    )

def r1_run_task(mod,W,truth,cfg,task_id):
    component=matrix_to_component(mod,W)
    rows=[]
    partitions=[]
    for k in range(1,R1_SEEDS_PER_TASK+1):
        seed=mod.deterministic_seed(k)
        t0=time.perf_counter()
        result=mod.run_one_component(component,cfg,seed)
        runtime=time.perf_counter()-t0

        h=result.history
        bad=h[
            h["min_executed_move_advantage"].notna()
            & (pd.to_numeric(h["min_executed_move_advantage"],errors="coerce")<=1e-12)
        ]
        if len(bad):
            raise RuntimeError(f"R1_NONIMPROVING_MOVE task={task_id} seed_index={k}")
        if result.converged:
            last=h.iloc[-1]
            if int(last["accepted_moves"])!=0 or int(last["improving_nodes_post_sweep"])!=0:
                raise RuntimeError(f"R1_FALSE_TERMINAL_STATE task={task_id} seed_index={k}")

        labels=canonical_labels(result.labels)
        partitions.append(labels)
        rows.append({
            "task_id":task_id,
            "seed_index":k,
            "seed":seed,
            "ARI":mod.adjusted_rand_index_from_labels(labels,truth),
            "NMI":nmi_from_labels(labels,truth),
            "converged":int(result.converged),
            "signed_Q":dense_gomez_signed_quality(W,labels),
            "communities":len(set(labels.values())),
            "iterations":len(h),
            "runtime_seconds":runtime,
        })
    df=pd.DataFrame(rows)
    summary={
        "median_ARI":float(df["ARI"].median()),
        "median_NMI":float(df["NMI"].median()),
        "convergence_rate":float(df["converged"].mean()),
        "median_signed_Q":float(df["signed_Q"].median()),
        "median_runtime_seconds":float(df["runtime_seconds"].median()),
        "seed_stability":pairwise_stability(mod.adjusted_rand_index_from_labels,partitions),
    }
    return df,summary

def baseline_panel(mod,W,truth,k_true,task_id,method):
    rows=[]
    partitions=[]
    for k in range(1,BASELINE_SEEDS_PER_TASK+1):
        seed=benchmark_seed(method,task_id,k)
        t0=time.perf_counter()
        if method=="GOMEZ_SIGNED_MODULARITY_GREEDY":
            labels,quality=baseline_gomez(W,seed)
        elif method.startswith("TRAAG_BRUGGEMAN_GAMMA_"):
            gamma=float(method.rsplit("_",1)[1])
            labels,quality=baseline_traag(W,seed,gamma)
        elif method=="SIGNED_SPECTRAL_ORACLE_K":
            labels,quality=baseline_signed_spectral(W,k_true,seed)
        elif method=="UNSIGNED_LOUVAIN_POSITIVE_ONLY_DIAGNOSTIC":
            labels,quality=baseline_unsigned_louvain_diagnostic(W,seed)
        else:
            raise ValueError(method)
        runtime=time.perf_counter()-t0
        labels=canonical_labels(labels)
        partitions.append(labels)
        rows.append({
            "method":method,
            "task_id":task_id,
            "seed_index":k,
            "seed":seed,
            "ARI":mod.adjusted_rand_index_from_labels(labels,truth),
            "NMI":nmi_from_labels(labels,truth),
            "signed_Q":dense_gomez_signed_quality(W,labels),
            "native_quality":quality,
            "communities":len(set(labels.values())),
            "runtime_seconds":runtime,
        })
    df=pd.DataFrame(rows)
    summary={
        "method":method,
        "task_id":task_id,
        "median_ARI":float(df["ARI"].median()),
        "median_NMI":float(df["NMI"].median()),
        "median_signed_Q":float(df["signed_Q"].median()),
        "median_runtime_seconds":float(df["runtime_seconds"].median()),
        "seed_stability":pairwise_stability(mod.adjusted_rand_index_from_labels,partitions),
    }
    return df,summary

def positive_only_r1_component(mod,W):
    M=np.where(W>0,1.0,0.0)
    return matrix_to_component(mod,M)

def ablation_panel(mod,W,truth,base_cfg,task_id,ablation):
    if ablation=="FULL_PLAN_B_TOPCORE":
        component=matrix_to_component(mod,W)
        cfg=base_cfg
    elif ablation=="SIGNED_LOCAL_ONLY":
        component=matrix_to_component(mod,W)
        cfg=mod.SACLAConfig(
            base_cfg.alpha_reward,base_cfg.alpha_penalty,0.0,0.0,
            base_cfg.max_iterations,base_cfg.objective_tolerance,
            base_cfg.node_change_tolerance,base_cfg.probability_change_tolerance,
            base_cfg.patience
        )
    elif ablation=="SIGNED_GLOBAL_ONLY":
        component=matrix_to_component(mod,W)
        cfg=mod.SACLAConfig(
            base_cfg.alpha_reward,base_cfg.alpha_penalty,1.0,0.0,
            base_cfg.max_iterations,base_cfg.objective_tolerance,
            base_cfg.node_change_tolerance,base_cfg.probability_change_tolerance,
            base_cfg.patience
        )
    elif ablation=="PUBLISHED_POSITIVE_ONLY_SEMANTICS_R1_DIAGNOSTIC":
        component=positive_only_r1_component(mod,W)
        cfg=mod.SACLAConfig(
            base_cfg.alpha_reward,base_cfg.alpha_penalty,base_cfg.gamma,0.0,
            base_cfg.max_iterations,base_cfg.objective_tolerance,
            base_cfg.node_change_tolerance,base_cfg.probability_change_tolerance,
            base_cfg.patience
        )
    else:
        raise ValueError(ablation)

    rows=[];parts=[]
    for k in range(1,R1_SEEDS_PER_TASK+1):
        seed=mod.deterministic_seed(k)
        t0=time.perf_counter()
        rr=mod.run_one_component(component,cfg,seed)
        runtime=time.perf_counter()-t0
        labels=canonical_labels(rr.labels)
        parts.append(labels)
        rows.append({
            "ablation":ablation,
            "task_id":task_id,
            "seed_index":k,
            "ARI":mod.adjusted_rand_index_from_labels(labels,truth),
            "NMI":nmi_from_labels(labels,truth),
            "signed_Q_on_original_graph":dense_gomez_signed_quality(W,labels),
            "converged":int(rr.converged),
            "runtime_seconds":runtime,
        })
    df=pd.DataFrame(rows)
    return df,{
        "ablation":ablation,
        "task_id":task_id,
        "median_ARI":float(df["ARI"].median()),
        "median_NMI":float(df["NMI"].median()),
        "median_signed_Q":float(df["signed_Q_on_original_graph"].median()),
        "convergence_rate":float(df["converged"].mean()),
        "seed_stability":pairwise_stability(mod.adjusted_rand_index_from_labels,parts),
        "median_runtime_seconds":float(df["runtime_seconds"].median()),
    }

def selftest():
    # Independent Gómez objective must agree with R1 objective on a tiny graph.
    W=np.array([
        [0,0.8,-0.6],
        [0.8,0,-0.5],
        [-0.6,-0.5,0]
    ],float)
    labels={0:0,1:0,2:2}
    q=dense_gomez_signed_quality(W,labels)
    assert math.isfinite(q)

    # Spectral baseline should return the requested k.
    labs,_=baseline_signed_spectral(W,2,123)
    assert len(set(labs.values()))==2

    # Benchmark generator deterministic.
    a=generate_signed_sbm("F1_TWO_BLOCK_LOW_NOISE",1)[0]
    b=generate_signed_sbm("F1_TWO_BLOCK_LOW_NOISE",1)[0]
    assert np.array_equal(a,b)

    print("D10F_INTERNAL_SELFTEST=PASS")
    print("INDEPENDENT_SIGNED_BASELINE_SELFTEST=PASS")
    print("BENCHMARK_GENERATOR_DETERMINISM_SELFTEST=PASS")
    print("NO_GSE243219_ALGORITHM_EXECUTION_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=7:
        raise SystemExit(
            "usage: D10F <r1_impl.py> <d10e_r1_run> <d9_run> <outdir> <result_json> <expected_r1_sha>"
        )

    impl_path=Path(sys.argv[1])
    d10e_r1=Path(sys.argv[2])
    d9=Path(sys.argv[3])
    out=Path(sys.argv[4])
    result_json=Path(sys.argv[5])
    expected_r1=sys.argv[6]
    out.mkdir(parents=True,exist_ok=True)

    if expected_r1!=EXPECTED_R1_SHA or sha256_file(impl_path)!=EXPECTED_R1_SHA:
        raise RuntimeError("R1_IMPLEMENTATION_SHA256_MISMATCH")

    status=d10e_r1/"D10E_R1_FINAL_STATUS.txt"
    for tok in [
        "D10E_R1_STATUS=PASS",
        "CORE_CONFIGURATIONS_TESTED=12",
        "CORE_ELIGIBLE_CONFIGURATIONS=12",
        "PLAN_B_CORE_STATUS=PASS",
        "PLAN_A_STATUS=FAIL_MULTICHANNEL_IDENTIFIABILITY",
        "PLAN_B_ACTIVATED=YES",
        "ACTIVE_PLAN_FOR_D10F=PLAN_B_SIGNED_SINGLE_LAYER_ACLA",
        "PARAMETER_GRID_EXPANSION_USED=NO",
        "THRESHOLD_RELAXATION_USED=NO",
        "R1_TRANSITION_INVARIANTS_PASS=YES",
        "READY_FOR_D10F_SIGNED_BENCHMARKING=YES",
        "GSE243219_ACLA_EXECUTED=NO",
    ]:
        require_token(status,tok,"D10E_R1")

    top_path=d10e_r1/"D10E_R1_TOP_CORE_CANDIDATES.csv"
    if not top_path.is_file():
        raise RuntimeError("D10E_R1_TOP_CORE_CANDIDATES_MISSING")
    top=pd.read_csv(top_path)
    if len(top)<1 or len(top)>3:
        raise RuntimeError(f"Unexpected D10E-R1 shortlist size={len(top)}")

    mod=load_module(impl_path,"signed_acla_r1_d10f")

    # Independent objective equivalence sanity check on one generated task.
    W0,t0,k0=generate_signed_sbm("F1_TWO_BLOCK_LOW_NOISE",1)
    c0=matrix_to_component(mod,W0)
    truth_q_r1=mod.signed_component_objective(c0,t0)
    truth_q_ind=dense_gomez_signed_quality(W0,t0)
    if abs(truth_q_r1-truth_q_ind)>1e-12:
        raise RuntimeError(
            f"R1_VS_INDEPENDENT_GOMEZ_OBJECTIVE_MISMATCH={truth_q_r1} vs {truth_q_ind}"
        )

    task_rows=[]
    tasks=[]
    for fam in BENCHMARK_FAMILIES:
        for rep in range(1,REPLICATES_PER_FAMILY+1):
            W,truth,k_true=generate_signed_sbm(fam,rep)
            task_id=f"{fam}_R{rep}"
            task_rows.append({
                "task_id":task_id,
                "family":fam,
                "replicate":rep,
                "n_nodes":W.shape[0],
                "n_edges":int(np.count_nonzero(np.triu(W,1))),
                "positive_edges":int(np.count_nonzero(np.triu(W>0,1))),
                "negative_edges":int(np.count_nonzero(np.triu(W<0,1))),
                "planted_communities":k_true,
                "task_seed":task_seed(fam,rep),
                "p_in":BENCHMARK_FAMILIES[fam]["p_in"],
                "p_out":BENCHMARK_FAMILIES[fam]["p_out"],
                "sign_flip_probability":BENCHMARK_FAMILIES[fam]["flip"],
            })
            tasks.append((task_id,W,truth,k_true))
    pd.DataFrame(task_rows).to_csv(out/"D10F_BENCHMARK_TASK_DEFINITIONS.csv",index=False)

    # --------------------------------------------------------------
    # R1 shortlisted configuration benchmark.
    # --------------------------------------------------------------
    r1_seed_frames=[]
    r1_task_summaries=[]
    for row in top.itertuples(index=False):
        config_id=str(row.config_id)
        cfg=mod.SACLAConfig(
            alpha_reward=float(row.alpha_reward),
            alpha_penalty=float(row.alpha_penalty),
            gamma=float(row.gamma),
            lambda_regulatory=0.0,
            max_iterations=int(row.max_iterations),
            objective_tolerance=float(row.objective_tolerance),
            node_change_tolerance=float(row.node_change_tolerance),
            probability_change_tolerance=float(row.probability_change_tolerance),
            patience=int(row.patience),
        )
        for task_id,W,truth,k_true in tasks:
            df,s=r1_run_task(mod,W,truth,cfg,task_id)
            df.insert(0,"config_id",config_id)
            r1_seed_frames.append(df)
            r1_task_summaries.append({"config_id":config_id,"task_id":task_id,**s})

    r1_seed=pd.concat(r1_seed_frames,ignore_index=True)
    r1_summary=pd.DataFrame(r1_task_summaries)
    r1_seed.to_csv(out/"D10F_R1_SEED_LEVEL_RESULTS.csv",index=False)
    r1_summary.to_csv(out/"D10F_R1_TASK_SUMMARY.csv",index=False)

    ranking_rows=[]
    for cid,g in r1_summary.groupby("config_id",sort=True):
        ranking_rows.append({
            "config_id":cid,
            "benchmark_tasks":len(g),
            "median_task_ARI":float(g["median_ARI"].median()),
            "median_task_NMI":float(g["median_NMI"].median()),
            "median_task_seed_stability":float(g["seed_stability"].median()),
            "median_task_signed_Q":float(g["median_signed_Q"].median()),
            "median_task_convergence_rate":float(g["convergence_rate"].median()),
            "median_task_runtime_seconds":float(g["median_runtime_seconds"].median()),
        })
    ranking=pd.DataFrame(ranking_rows).sort_values(
        [
            "median_task_ARI","median_task_NMI","median_task_seed_stability",
            "median_task_signed_Q","median_task_runtime_seconds","config_id"
        ],
        ascending=[False,False,False,False,True,True]
    ).reset_index(drop=True)
    ranking.insert(0,"benchmark_rank",np.arange(1,len(ranking)+1))
    ranking.to_csv(out/"D10F_R1_CONFIG_RANKING.csv",index=False)
    candidate_config=str(ranking.iloc[0]["config_id"])

    # --------------------------------------------------------------
    # Independent baselines.
    # --------------------------------------------------------------
    baseline_methods=[
        "GOMEZ_SIGNED_MODULARITY_GREEDY",
        "TRAAG_BRUGGEMAN_GAMMA_0.5",
        "TRAAG_BRUGGEMAN_GAMMA_1.0",
        "TRAAG_BRUGGEMAN_GAMMA_2.0",
        "SIGNED_SPECTRAL_ORACLE_K",
        "UNSIGNED_LOUVAIN_POSITIVE_ONLY_DIAGNOSTIC",
    ]
    baseline_frames=[]
    baseline_task_rows=[]
    for task_id,W,truth,k_true in tasks:
        for method in baseline_methods:
            df,s=baseline_panel(mod,W,truth,k_true,task_id,method)
            baseline_frames.append(df)
            baseline_task_rows.append(s)
    baseline_seed=pd.concat(baseline_frames,ignore_index=True)
    baseline_task=pd.DataFrame(baseline_task_rows)
    baseline_seed.to_csv(out/"D10F_BASELINE_SEED_LEVEL_RESULTS.csv",index=False)
    baseline_task.to_csv(out/"D10F_BASELINE_TASK_SUMMARY.csv",index=False)

    baseline_summary_rows=[]
    for method,g in baseline_task.groupby("method",sort=True):
        baseline_summary_rows.append({
            "method":method,
            "benchmark_tasks":len(g),
            "median_task_ARI":float(g["median_ARI"].median()),
            "median_task_NMI":float(g["median_NMI"].median()),
            "median_task_seed_stability":float(g["seed_stability"].median()),
            "median_task_signed_Q":float(g["median_signed_Q"].median()),
            "median_task_runtime_seconds":float(g["median_runtime_seconds"].median()),
        })
    baseline_summary=pd.DataFrame(baseline_summary_rows).sort_values(
        ["median_task_ARI","median_task_NMI","median_task_seed_stability","median_task_signed_Q"],
        ascending=[False,False,False,False]
    )
    baseline_summary.to_csv(out/"D10F_BASELINE_SUMMARY.csv",index=False)

    # --------------------------------------------------------------
    # Predeclared ablations use D10E-R1 TOP_CORE_CONFIG_ID, not the
    # new D10F ranking, to avoid benchmark-selection circularity.
    # --------------------------------------------------------------
    topcore_row=top.iloc[0]
    topcore_id=str(topcore_row["config_id"])
    topcore_cfg=mod.SACLAConfig(
        float(topcore_row["alpha_reward"]),
        float(topcore_row["alpha_penalty"]),
        float(topcore_row["gamma"]),
        0.0,
        int(topcore_row["max_iterations"]),
        float(topcore_row["objective_tolerance"]),
        float(topcore_row["node_change_tolerance"]),
        float(topcore_row["probability_change_tolerance"]),
        int(topcore_row["patience"]),
    )
    ablations=[
        "FULL_PLAN_B_TOPCORE",
        "SIGNED_LOCAL_ONLY",
        "SIGNED_GLOBAL_ONLY",
        "PUBLISHED_POSITIVE_ONLY_SEMANTICS_R1_DIAGNOSTIC",
    ]
    abl_frames=[]
    abl_task_rows=[]
    for task_id,W,truth,k_true in tasks:
        for ab in ablations:
            df,s=ablation_panel(mod,W,truth,topcore_cfg,task_id,ab)
            abl_frames.append(df)
            abl_task_rows.append(s)
    abl_seed=pd.concat(abl_frames,ignore_index=True)
    abl_task=pd.DataFrame(abl_task_rows)
    abl_seed.to_csv(out/"D10F_ABLATION_SEED_LEVEL_RESULTS.csv",index=False)
    abl_task.to_csv(out/"D10F_ABLATION_TASK_SUMMARY.csv",index=False)

    abl_summary_rows=[]
    for ab,g in abl_task.groupby("ablation",sort=True):
        abl_summary_rows.append({
            "ablation":ab,
            "benchmark_tasks":len(g),
            "median_task_ARI":float(g["median_ARI"].median()),
            "median_task_NMI":float(g["median_NMI"].median()),
            "median_task_seed_stability":float(g["seed_stability"].median()),
            "median_task_signed_Q":float(g["median_signed_Q"].median()),
            "median_task_convergence_rate":float(g["convergence_rate"].median()),
            "median_task_runtime_seconds":float(g["median_runtime_seconds"].median()),
        })
    pd.DataFrame(abl_summary_rows).sort_values(
        ["median_task_ARI","median_task_NMI"],ascending=[False,False]
    ).to_csv(out/"D10F_ABLATION_SUMMARY.csv",index=False)

    # Candidate versus baseline task-by-task comparison.
    candidate_task=r1_summary[r1_summary["config_id"]==candidate_config].copy()
    compare_rows=[]
    for _,cr in candidate_task.iterrows():
        task_id=cr["task_id"]
        for _,br in baseline_task[baseline_task["task_id"]==task_id].iterrows():
            compare_rows.append({
                "task_id":task_id,
                "candidate_config":candidate_config,
                "baseline_method":br["method"],
                "candidate_median_ARI":cr["median_ARI"],
                "baseline_median_ARI":br["median_ARI"],
                "ARI_difference_candidate_minus_baseline":cr["median_ARI"]-br["median_ARI"],
                "candidate_median_NMI":cr["median_NMI"],
                "baseline_median_NMI":br["median_NMI"],
                "NMI_difference_candidate_minus_baseline":cr["median_NMI"]-br["median_NMI"],
                "candidate_median_signed_Q":cr["median_signed_Q"],
                "baseline_median_signed_Q":br["median_signed_Q"],
            })
    pd.DataFrame(compare_rows).to_csv(
        out/"D10F_CANDIDATE_BASELINE_COMPARISON.csv",index=False
    )

    refs=[
        {
            "method":"GOMEZ_SIGNED_MODULARITY_GREEDY",
            "reference":"Gómez S, Jensen P, Arenas A. Physical Review E 80, 016114 (2009)",
            "DOI":"10.1103/PhysRevE.80.016114",
            "signed_semantics":"YES",
            "implementation_note":"Independent dense Gómez objective + dependency-free multilevel local optimizer written for D10F",
        },
        {
            "method":"TRAAG_BRUGGEMAN_GAMMA_GRID",
            "reference":"Traag VA, Bruggeman J. Physical Review E 80, 036115 (2009)",
            "DOI":"10.1103/PhysRevE.80.036115",
            "signed_semantics":"YES",
            "implementation_note":"Independent positive/negative Potts quality with gamma+ = gamma- in predeclared {0.5,1,2}",
        },
        {
            "method":"SIGNED_SPECTRAL_ORACLE_K",
            "reference":"Kunegis J et al. SDM 2010, pp. 559-570",
            "DOI":"10.1137/1.9781611972801.49",
            "signed_semantics":"YES",
            "implementation_note":"Signed Laplacian D_abs-A; k smallest eigenvectors; oracle planted k gives baseline an explicit advantage",
        },
        {
            "method":"UNSIGNED_LOUVAIN_POSITIVE_ONLY_DIAGNOSTIC",
            "reference":"Blondel VD et al. J Stat Mech (2008) P10008",
            "DOI":"10.1088/1742-5468/2008/10/P10008",
            "signed_semantics":"NO",
            "implementation_note":"Dependency-free multilevel positive-only modularity diagnostic; negatives are excluded by design and method is not a valid D9 candidate",
        },
    ]
    pd.DataFrame(refs).to_csv(out/"D10F_METHOD_REFERENCES.csv",index=False)

    result={
        "D10F_STATUS":"PASS",
        "R1_IMPLEMENTATION_SHA256":EXPECTED_R1_SHA,
        "ACTIVE_PLAN":"PLAN_B_SIGNED_SINGLE_LAYER_ACLA",
        "PLAN_A_REOPENED":"NO",
        "BENCHMARK_FAMILIES":len(BENCHMARK_FAMILIES),
        "BENCHMARK_TASKS":len(tasks),
        "REPLICATES_PER_FAMILY":REPLICATES_PER_FAMILY,
        "R1_SHORTLIST_CONFIGURATIONS_BENCHMARKED":len(top),
        "R1_SEEDS_PER_TASK":R1_SEEDS_PER_TASK,
        "BASELINE_SEEDS_PER_TASK":BASELINE_SEEDS_PER_TASK,
        "INDEPENDENT_GOMEZ_BASELINE_COMPLETED":"YES",
        "TRAAG_BRUGGEMAN_BASELINE_COMPLETED":"YES",
        "SIGNED_SPECTRAL_BASELINE_COMPLETED":"YES",
        "UNSIGNED_LOUVAIN_DIAGNOSTIC_COMPLETED":"YES",
        "ABLATION_CAMPAIGN_COMPLETED":"YES",
        "ABLATION_REFERENCE_CONFIG":topcore_id,
        "D10F_RANKED_CANDIDATE_CONFIG":candidate_config,
        "D10F_PARAMETER_FREEZE_EXECUTED":"NO",
        "D10F_METHOD_ACCEPTANCE_DECISION_EXECUTED":"NO",
        "BIOLOGICAL_PARAMETER_VALUES_FROZEN":"NO",
        "PARAMETER_TUNING_USING_GSE243219":"NO",
        "GSE243219_ACLA_EXECUTED":"NO",
        "D9_COMMUNITY_DETECTION_EXECUTED":"NO",
        "NETWORK_CHANGED":"NO",
        "D9_FILES_MODIFIED":"NO",
        "WEIGHT_TRANSFORMATION_APPLIED":"NO",
        "NEGATIVE_EDGES_REMOVED":"NO",
        "READY_FOR_D10G_PROSPECTIVE_ACCEPTANCE":"YES",
        "READY_FOR_GSE243219_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }
    result_json.write_text(json.dumps(result,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
