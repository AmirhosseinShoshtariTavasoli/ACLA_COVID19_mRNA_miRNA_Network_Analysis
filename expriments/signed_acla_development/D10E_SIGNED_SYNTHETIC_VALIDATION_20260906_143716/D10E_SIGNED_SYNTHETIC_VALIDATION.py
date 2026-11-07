#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import itertools
import json
import math
import statistics
import sys
from dataclasses import asdict
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, Sequence, Tuple

import numpy as np
import pandas as pd

EXPECTED_IMPLEMENTATION_SHA256 = "a46a2fd5beacec09f800fd6d1c855b2c8f4c10e2159028542ac46cedef19fe24"

CORE_ALPHA_REWARD = (0.1, 0.3)
CORE_ALPHA_PENALTY = (0.1, 0.3)
CORE_GAMMA = (0.25, 0.50, 0.75)
PLAN_A_LAMBDA = (0.25, 0.50, 1.00)

VALIDATION_MAX_ITERATIONS = 200
VALIDATION_OBJECTIVE_TOLERANCE = 1e-6
VALIDATION_NODE_CHANGE_TOLERANCE = 0.02
VALIDATION_PROBABILITY_CHANGE_TOLERANCE = 1e-2
VALIDATION_PATIENCE = 5
VALIDATION_SEEDS = 10

# Predeclared D10E hard recovery gates.
FIXTURE_A_MEDIAN_ARI_MIN = 0.90
FIXTURE_A_MEDIAN_NMI_MIN = 0.90
FIXTURE_A_EXACT_RECOVERY_RATE_MIN = 0.70
FIXTURE_B_MEDIAN_ARI_MIN = 0.40
FIXTURE_B_MEDIAN_NMI_MIN = 0.50

def sha256_file(path: Path, chunk=8*1024*1024) -> str:
    import hashlib
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(chunk), b""):
            h.update(block)
    return h.hexdigest()

def load_impl(path: Path):
    if sha256_file(path) != EXPECTED_IMPLEMENTATION_SHA256:
        raise RuntimeError("D10D_IMPLEMENTATION_SHA256_MISMATCH")
    spec = importlib.util.spec_from_file_location("signed_acla_d10e", path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod

def make_component(mod, n: int, edges: Sequence[Tuple[int,int,float,bool]]):
    ndf = pd.DataFrame({
        "node_index": list(range(n)),
        "node_id": [f"N{i}" for i in range(n)],
    })
    edf = pd.DataFrame([
        {"source_index": u, "target_index": v, "association_score": w}
        for u, v, w, r in edges
    ])
    rdf = pd.DataFrame(
        [{"source_index": u, "target_index": v} for u, v, w, r in edges if r],
        columns=["source_index", "target_index"],
    )
    comps = mod.build_signed_components(ndf, edf, rdf)
    if len(comps) != 1:
        raise AssertionError(f"Expected one component, got {len(comps)}")
    return comps[0]

def make_components(mod, n: int, edges: Sequence[Tuple[int,int,float,bool]]):
    ndf = pd.DataFrame({
        "node_index": list(range(n)),
        "node_id": [f"N{i}" for i in range(n)],
    })
    edf = pd.DataFrame([
        {"source_index": u, "target_index": v, "association_score": w}
        for u, v, w, r in edges
    ])
    rdf = pd.DataFrame(
        [{"source_index": u, "target_index": v} for u, v, w, r in edges if r],
        columns=["source_index", "target_index"],
    )
    return mod.build_signed_components(ndf, edf, rdf)

def truth_two_block(n_per: int) -> Dict[int,int]:
    return {i: (0 if i < n_per else n_per) for i in range(2*n_per)}

def ideal_two_block(n_per: int = 5) -> Tuple[int, List[Tuple[int,int,float,bool]], Dict[int,int]]:
    n = 2*n_per
    edges = []
    for i in range(n):
        for j in range(i+1, n):
            same = (i < n_per) == (j < n_per)
            if same:
                # Deterministic mild magnitude heterogeneity.
                w = 0.75 + 0.05 * ((i + 2*j) % 5)
            else:
                w = -(0.55 + 0.05 * ((2*i + j) % 5))
            edges.append((i,j,float(w),False))
    return n, edges, truth_two_block(n_per)

def noisy_two_block(n_per: int = 5) -> Tuple[int, List[Tuple[int,int,float,bool]], Dict[int,int]]:
    n, base, truth = ideal_two_block(n_per)
    edges = []
    # Deterministic approximately 15-20% sign corruption.
    for i,j,w,r in base:
        flip = ((11*i + 7*j + 3) % 17) < 3
        ww = -w if flip else w
        # Reduce corrupted magnitudes so the fixture is noisy but not adversarially impossible.
        if flip:
            ww *= 0.70
        edges.append((i,j,float(ww),False))
    return n, edges, truth

def regulatory_informative_fixture(n_per: int = 5):
    n = 2*n_per
    edges = []
    for i in range(n):
        for j in range(i+1,n):
            same = (i < n_per) == (j < n_per)
            if same:
                w = 0.35 + 0.03 * ((i+j) % 4)
                regulatory = ((i + 3*j) % 3) != 0
            else:
                w = -(0.40 + 0.03 * ((2*i+j) % 4))
                # Add a small deterministic amount of sign noise; never label it regulatory.
                if ((5*i + 2*j) % 19) == 0:
                    w = abs(w) * 0.65
                regulatory = False
            edges.append((i,j,float(w),bool(regulatory)))
    return n, edges, truth_two_block(n_per)

def zero_regulatory_fixture(n_per: int = 5):
    n, edges, truth = regulatory_informative_fixture(n_per)
    return n, [(i,j,w,False) for i,j,w,r in edges], truth

def positive_only_fixture():
    n = 6
    edges = [
        (0,1,0.9,False),(0,2,0.8,False),(1,2,0.7,False),
        (3,4,0.9,False),(3,5,0.8,False),(4,5,0.7,False),
        (2,3,0.15,False),
    ]
    labels = {0:0,1:0,2:0,3:3,4:3,5:3}
    return n, edges, labels

def adversarial_negative_within_fixture():
    n = 4
    edges = [
        (0,1,0.8,False),
        (2,3,0.8,False),
        (0,2,-0.9,False),
        (0,3,-0.8,False),
        (1,2,-0.8,False),
        (1,3,-0.9,False),
    ]
    good = {0:0,1:0,2:2,3:2}
    bad = {0:0,1:0,2:0,3:0}
    return n, edges, good, bad

def disconnected_fixture():
    # Two disconnected signed components, each containing a planted 2-block structure.
    edges = []
    # component A: nodes 0..5, 3+3
    for offset, n_per in [(0,3),(6,3)]:
        nodes = list(range(offset, offset+2*n_per))
        for ii,i in enumerate(nodes):
            for j in nodes[ii+1:]:
                same = (i < offset+n_per) == (j < offset+n_per)
                w = 0.8 if same else -0.7
                edges.append((i,j,w,False))
    return 12, edges

def nmi_from_labels(a: Mapping[int,int], b: Mapping[int,int]) -> float:
    nodes = sorted(set(a) & set(b))
    if set(nodes) != set(a) or set(nodes) != set(b):
        raise ValueError("NMI partitions must cover same nodes")
    n = len(nodes)
    if n == 0:
        return 1.0
    ca: Dict[int,int] = {}
    cb: Dict[int,int] = {}
    joint: Dict[Tuple[int,int],int] = {}
    for node in nodes:
        x,y = a[node], b[node]
        ca[x] = ca.get(x,0)+1
        cb[y] = cb.get(y,0)+1
        joint[(x,y)] = joint.get((x,y),0)+1
    mi = 0.0
    for (x,y), nij in joint.items():
        pxy = nij/n
        px = ca[x]/n
        py = cb[y]/n
        mi += pxy * math.log(pxy/(px*py))
    hx = -sum((v/n)*math.log(v/n) for v in ca.values())
    hy = -sum((v/n)*math.log(v/n) for v in cb.values())
    if hx == 0 and hy == 0:
        return 1.0
    denom = (hx + hy) / 2.0
    return 0.0 if denom == 0 else float(mi/denom)

def pairwise_seed_stability(mod, results) -> float:
    if len(results) < 2:
        return 1.0
    vals = []
    for i in range(len(results)):
        for j in range(i+1,len(results)):
            vals.append(mod.adjusted_rand_index_from_labels(results[i].labels, results[j].labels))
    return float(np.median(vals))

def run_panel(mod, component, truth, cfg, seed_count=VALIDATION_SEEDS):
    rows = []
    results = []
    for k in range(1, seed_count+1):
        seed = mod.deterministic_seed(k)
        r = mod.run_one_component(component, cfg, seed)
        ari = mod.adjusted_rand_index_from_labels(r.labels, truth)
        nmi = nmi_from_labels(r.labels, truth)
        rows.append({
            "seed_index": k,
            "seed": seed,
            "ARI": ari,
            "NMI": nmi,
            "exact_recovery": int(abs(ari-1.0) <= 1e-12),
            "converged": int(r.converged),
            "objective": r.objective,
            "community_count": len(set(r.labels.values())),
            "iterations": len(r.history),
            "convergence_reason": r.convergence_reason,
        })
        results.append(r)
    df = pd.DataFrame(rows)
    summary = {
        "median_ARI": float(df["ARI"].median()),
        "median_NMI": float(df["NMI"].median()),
        "exact_recovery_rate": float(df["exact_recovery"].mean()),
        "convergence_rate": float(df["converged"].mean()),
        "median_objective": float(df["objective"].median()),
        "median_iterations": float(df["iterations"].median()),
        "median_pairwise_seed_ARI": pairwise_seed_stability(mod, results),
    }
    return df, results, summary

def weighted_positive_modularity_reference(edges, labels):
    nodes = sorted({u for u,v,w,r in edges} | {v for u,v,w,r in edges})
    strength = {n:0.0 for n in nodes}
    total = 0.0
    observed = 0.0
    for u,v,w,r in edges:
        if w < 0:
            raise ValueError("positive-only reference got negative weight")
        strength[u] += w
        strength[v] += w
        total += 2*w
        if labels[u] == labels[v]:
            observed += 2*w
    comm_strength = {}
    for n in nodes:
        c = labels[n]
        comm_strength[c] = comm_strength.get(c,0.0) + strength[n]
    null = -sum(s*s/total for s in comm_strength.values()) if total>0 else 0.0
    return (observed + null)/total

def config_grid(mod):
    rows=[]
    idx=0
    for ar,ap,gamma in itertools.product(CORE_ALPHA_REWARD, CORE_ALPHA_PENALTY, CORE_GAMMA):
        idx += 1
        cfg = mod.SACLAConfig(
            alpha_reward=ar,
            alpha_penalty=ap,
            gamma=gamma,
            lambda_regulatory=0.0,
            max_iterations=VALIDATION_MAX_ITERATIONS,
            objective_tolerance=VALIDATION_OBJECTIVE_TOLERANCE,
            node_change_tolerance=VALIDATION_NODE_CHANGE_TOLERANCE,
            probability_change_tolerance=VALIDATION_PROBABILITY_CHANGE_TOLERANCE,
            patience=VALIDATION_PATIENCE,
        )
        rows.append((f"CORE_{idx:02d}",cfg))
    return rows

def cfg_record(cfg):
    return {
        "alpha_reward": cfg.alpha_reward,
        "alpha_penalty": cfg.alpha_penalty,
        "gamma": cfg.gamma,
        "lambda_regulatory": cfg.lambda_regulatory,
        "max_iterations": cfg.max_iterations,
        "objective_tolerance": cfg.objective_tolerance,
        "node_change_tolerance": cfg.node_change_tolerance,
        "probability_change_tolerance": cfg.probability_change_tolerance,
        "patience": cfg.patience,
    }

def selftest():
    # Metric and fixture construction tests only.
    a={0:0,1:0,2:2,3:2}
    b={0:0,1:0,2:2,3:2}
    assert abs(nmi_from_labels(a,b)-1.0)<1e-12
    n,e,t=ideal_two_block(3)
    assert n==6 and len(e)==15 and len(t)==6
    n2,e2=disconnected_fixture()
    assert n2==12 and len(e2)>0
    print("D10E_INTERNAL_SELFTEST=PASS")
    print("FIXTURE_CONSTRUCTION_SELFTEST=PASS")
    print("NMI_METRIC_SELFTEST=PASS")
    print("NO_GSE243219_ALGORITHM_EXECUTION_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=5:
        raise SystemExit("usage: D10E <implementation.py> <outdir> <result_json> <d10d_final_status>")

    impl_path=Path(sys.argv[1])
    out=Path(sys.argv[2])
    result_json=Path(sys.argv[3])
    d10d_status_path=Path(sys.argv[4])
    out.mkdir(parents=True,exist_ok=True)

    d10d_text=d10d_status_path.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10D_STATUS=PASS",
        f"IMPLEMENTATION_SHA256={EXPECTED_IMPLEMENTATION_SHA256}",
        "IMPLEMENTATION_UNIT_TESTS_PASS=YES",
        "D9_READONLY_INTERFACE_AUDIT_PASS=YES",
        "READY_FOR_D10E_SIGNED_SYNTHETIC_VALIDATION=YES",
        "SIGNED_ACLA_EXECUTED_ON_GSE243219=NO",
    ]:
        if tok not in d10d_text:
            raise RuntimeError(f"D10D_AUTHORITY_TOKEN_MISSING={tok}")

    mod=load_impl(impl_path)

    fixture_defs = [
        ["A","IDEAL_TWO_BLOCK_SIGNED","10 nodes; complete; positive within; negative between","HARD_CORE_RECOVERY"],
        ["B","NOISY_MIXED_SIGN_PLANTED","10 nodes; deterministic sign corruption ~15-20%","HARD_CORE_RECOVERY"],
        ["C","DISCONNECTED_SIGNED","12 nodes; two disconnected 6-node signed components","HARD_INVARIANT"],
        ["D","POSITIVE_ONLY_REDUCTION","6-node positive weighted graph","HARD_MATHEMATICAL_REDUCTION"],
        ["E","REGULATORY_METADATA_CHANNEL","10-node signed planted graph; informative binary regulatory subset","PLAN_A_IDENTIFIABILITY"],
        ["F","DETERMINISTIC_REPRODUCIBILITY","same implementation/config/seed repeated","HARD_REPRODUCIBILITY"],
        ["G","ADVERSARIAL_NEGATIVE_WITHIN","4-node sign-consistent vs all-one partition","HARD_SIGN_SEMANTICS"],
        ["H","ZERO_REGULATORY_INFORMATION","fixture E with all r_ij=0","HARD_PLAN_A_TO_PLAN_B_REDUCTION"],
    ]
    pd.DataFrame(fixture_defs,columns=["fixture_id","name","construction","role"]).to_csv(
        out/"D10E_FIXTURE_DEFINITIONS.csv",index=False
    )

    seed_level=[]
    screen_rows=[]

    nA,eA,tA=ideal_two_block()
    compA=make_component(mod,nA,eA)
    nB,eB,tB=noisy_two_block()
    compB=make_component(mod,nB,eB)

    eligible=[]
    for config_id,cfg in config_grid(mod):
        a_df,a_results,a_sum=run_panel(mod,compA,tA,cfg)
        a_df.insert(0,"fixture_id","A")
        a_df.insert(1,"config_id",config_id)
        seed_level.append(a_df)

        b_df,b_results,b_sum=run_panel(mod,compB,tB,cfg)
        b_df.insert(0,"fixture_id","B")
        b_df.insert(1,"config_id",config_id)
        seed_level.append(b_df)

        A_pass=(
            a_sum["median_ARI"] >= FIXTURE_A_MEDIAN_ARI_MIN
            and a_sum["median_NMI"] >= FIXTURE_A_MEDIAN_NMI_MIN
            and a_sum["exact_recovery_rate"] >= FIXTURE_A_EXACT_RECOVERY_RATE_MIN
        )
        B_pass=(
            b_sum["median_ARI"] >= FIXTURE_B_MEDIAN_ARI_MIN
            and b_sum["median_NMI"] >= FIXTURE_B_MEDIAN_NMI_MIN
        )
        row={
            "config_id":config_id,
            **cfg_record(cfg),
            "A_median_ARI":a_sum["median_ARI"],
            "A_median_NMI":a_sum["median_NMI"],
            "A_exact_recovery_rate":a_sum["exact_recovery_rate"],
            "A_convergence_rate":a_sum["convergence_rate"],
            "A_seed_stability":a_sum["median_pairwise_seed_ARI"],
            "A_median_objective":a_sum["median_objective"],
            "A_PASS":int(A_pass),
            "B_median_ARI":b_sum["median_ARI"],
            "B_median_NMI":b_sum["median_NMI"],
            "B_exact_recovery_rate":b_sum["exact_recovery_rate"],
            "B_convergence_rate":b_sum["convergence_rate"],
            "B_seed_stability":b_sum["median_pairwise_seed_ARI"],
            "B_median_objective":b_sum["median_objective"],
            "B_PASS":int(B_pass),
            "CORE_ELIGIBLE":int(A_pass and B_pass),
        }
        row["rank_median_ARI"]=(row["A_median_ARI"]+row["B_median_ARI"])/2
        row["rank_median_NMI"]=(row["A_median_NMI"]+row["B_median_NMI"])/2
        row["rank_seed_stability"]=(row["A_seed_stability"]+row["B_seed_stability"])/2
        row["rank_signed_objective"]=(row["A_median_objective"]+row["B_median_objective"])/2
        screen_rows.append(row)
        if row["CORE_ELIGIBLE"]:
            eligible.append((config_id,cfg,row))

    screen=pd.DataFrame(screen_rows)
    screen.to_csv(out/"D10E_CORE_PARAMETER_SCREEN.csv",index=False)
    pd.concat(seed_level,ignore_index=True).to_csv(out/"D10E_SEED_LEVEL_RESULTS.csv",index=False)

    invariant_rows=[]

    # D: positive-only reduction to standard weighted positive modularity.
    nD,eD,tD=positive_only_fixture()
    compD=make_component(mod,nD,eD)
    q_impl=mod.signed_component_objective(compD,tD)
    q_ref=weighted_positive_modularity_reference(eD,tD)
    D_pass=abs(q_impl-q_ref)<=1e-12
    invariant_rows.append({
        "fixture_id":"D","test":"POSITIVE_ONLY_OBJECTIVE_REDUCTION",
        "status":"PASS" if D_pass else "FAIL",
        "detail":f"implementation={q_impl:.15g};reference={q_ref:.15g};absdiff={abs(q_impl-q_ref):.3g}"
    })

    # G: negative-within partition is worse than sign-consistent planted partition.
    nG,eG,goodG,badG=adversarial_negative_within_fixture()
    compG=make_component(mod,nG,eG)
    q_good=mod.signed_component_objective(compG,goodG)
    q_bad=mod.signed_component_objective(compG,badG)
    local_good=mod.signed_local_score(compG,goodG,0,goodG[0],0.0)
    local_bad=mod.signed_local_score(compG,badG,0,badG[0],0.0)
    G_pass=(q_good>q_bad and local_good>local_bad)
    invariant_rows.append({
        "fixture_id":"G","test":"NEGATIVE_WITHIN_PENALTY",
        "status":"PASS" if G_pass else "FAIL",
        "detail":f"Q_good={q_good:.9g};Q_bad={q_bad:.9g};L_good={local_good:.9g};L_bad={local_bad:.9g}"
    })

    # C: disconnected components retained without artificial connection.
    nC,eC=disconnected_fixture()
    compsC=make_components(mod,nC,eC)
    sizes=sorted([len(c.nodes) for c in compsC],reverse=True)
    C_pass=(sizes==[6,6] and sum(len(c.nodes) for c in compsC)==12)
    invariant_rows.append({
        "fixture_id":"C","test":"DISCONNECTED_COMPONENT_RETENTION",
        "status":"PASS" if C_pass else "FAIL",
        "detail":f"component_sizes={sizes};nodes_retained={sum(len(c.nodes) for c in compsC)}"
    })

    # Determine top core candidates using the D10C lexicographic policy.
    eligible_sorted=sorted(
        eligible,
        key=lambda x: (
            x[2]["rank_median_ARI"],
            x[2]["rank_median_NMI"],
            x[2]["rank_seed_stability"],
            x[2]["rank_signed_objective"],
            -int(x[0].split("_")[1]),
        ),
        reverse=True,
    )
    top_core=eligible_sorted[:3]
    top_rows=[x[2] for x in top_core]
    pd.DataFrame(top_rows).to_csv(out/"D10E_TOP_CORE_CANDIDATES.csv",index=False)

    core_pass=(len(eligible_sorted)>0 and D_pass and G_pass and C_pass)

    # F/H and Plan-A tests require at least one core configuration.
    plan_a_rows=[]
    plan_a_identified=False
    selected_plan_a=None
    selected_core_id=""
    selected_core_cfg=None

    if top_core:
        selected_core_id,selected_core_cfg,_=top_core[0]

        # F reproducibility.
        seed=mod.deterministic_seed(1)
        r1=mod.run_one_component(compA,selected_core_cfg,seed)
        r2=mod.run_one_component(compA,selected_core_cfg,seed)
        F_pass=(r1.labels==r2.labels and r1.history.equals(r2.history))
        invariant_rows.append({
            "fixture_id":"F","test":"FULL_ALGORITHM_SAME_SEED_REPRODUCIBILITY",
            "status":"PASS" if F_pass else "FAIL",
            "detail":f"config={selected_core_id};seed={seed};history_equal={r1.history.equals(r2.history)}"
        })

        # H zero regulatory info: lambda must have no effect when r=0.
        nH,eH,tH=zero_regulatory_fixture()
        compH=make_component(mod,nH,eH)
        cfg0=mod.SACLAConfig(
            alpha_reward=selected_core_cfg.alpha_reward,
            alpha_penalty=selected_core_cfg.alpha_penalty,
            gamma=selected_core_cfg.gamma,
            lambda_regulatory=0.0,
            max_iterations=selected_core_cfg.max_iterations,
            objective_tolerance=selected_core_cfg.objective_tolerance,
            node_change_tolerance=selected_core_cfg.node_change_tolerance,
            probability_change_tolerance=selected_core_cfg.probability_change_tolerance,
            patience=selected_core_cfg.patience,
        )
        cfg1=mod.SACLAConfig(
            alpha_reward=selected_core_cfg.alpha_reward,
            alpha_penalty=selected_core_cfg.alpha_penalty,
            gamma=selected_core_cfg.gamma,
            lambda_regulatory=1.0,
            max_iterations=selected_core_cfg.max_iterations,
            objective_tolerance=selected_core_cfg.objective_tolerance,
            node_change_tolerance=selected_core_cfg.node_change_tolerance,
            probability_change_tolerance=selected_core_cfg.probability_change_tolerance,
            patience=selected_core_cfg.patience,
        )
        h0=mod.run_one_component(compH,cfg0,seed)
        h1=mod.run_one_component(compH,cfg1,seed)
        H_pass=(h0.labels==h1.labels and h0.history.equals(h1.history))
        invariant_rows.append({
            "fixture_id":"H","test":"ZERO_REGULATORY_PLAN_A_EQUALS_PLAN_B",
            "status":"PASS" if H_pass else "FAIL",
            "detail":f"config={selected_core_id};seed={seed};partition_equal={h0.labels==h1.labels};history_equal={h0.history.equals(h1.history)}"
        })

        # E: Plan-A regulatory-channel identifiability, paired by seed against lambda=0.
        nE,eE,tE=regulatory_informative_fixture()
        compE=make_component(mod,nE,eE)
        for core_id,core_cfg,_ in top_core:
            base_cfg=mod.SACLAConfig(
                core_cfg.alpha_reward,core_cfg.alpha_penalty,core_cfg.gamma,0.0,
                core_cfg.max_iterations,core_cfg.objective_tolerance,
                core_cfg.node_change_tolerance,core_cfg.probability_change_tolerance,
                core_cfg.patience,
            )
            base_df,base_results,base_sum=run_panel(mod,compE,tE,base_cfg)
            base_ari_by_seed=dict(zip(base_df["seed"],base_df["ARI"]))
            for lam in PLAN_A_LAMBDA:
                cfg=mod.SACLAConfig(
                    core_cfg.alpha_reward,core_cfg.alpha_penalty,core_cfg.gamma,float(lam),
                    core_cfg.max_iterations,core_cfg.objective_tolerance,
                    core_cfg.node_change_tolerance,core_cfg.probability_change_tolerance,
                    core_cfg.patience,
                )
                df,results,s=run_panel(mod,compE,tE,cfg)
                improved=sum(
                    float(row.ARI) > base_ari_by_seed[int(row.seed)] + 1e-12
                    for row in df.itertuples(index=False)
                )
                not_worse=(
                    s["median_ARI"] >= base_sum["median_ARI"] - 1e-12
                    and s["exact_recovery_rate"] >= base_sum["exact_recovery_rate"] - 1e-12
                )
                identifiable=bool(not_worse and improved >= 6)
                row={
                    "core_config_id":core_id,
                    "lambda_regulatory":lam,
                    "baseline_median_ARI":base_sum["median_ARI"],
                    "planA_median_ARI":s["median_ARI"],
                    "baseline_median_NMI":base_sum["median_NMI"],
                    "planA_median_NMI":s["median_NMI"],
                    "baseline_exact_recovery_rate":base_sum["exact_recovery_rate"],
                    "planA_exact_recovery_rate":s["exact_recovery_rate"],
                    "paired_seeds_ARI_improved":improved,
                    "paired_seed_majority_improvement_required":6,
                    "not_worse_on_median_and_exact_rate":int(not_worse),
                    "PLAN_A_IDENTIFIABLE":int(identifiable),
                }
                plan_a_rows.append(row)
                if identifiable:
                    candidate_key=(
                        s["median_ARI"],s["median_NMI"],s["exact_recovery_rate"],
                        improved,-lam,-int(core_id.split("_")[1])
                    )
                    if selected_plan_a is None or candidate_key>selected_plan_a[0]:
                        selected_plan_a=(candidate_key,row,cfg)
                        plan_a_identified=True
    else:
        F_pass=False
        H_pass=False
        invariant_rows.extend([
            {"fixture_id":"F","test":"FULL_ALGORITHM_SAME_SEED_REPRODUCIBILITY","status":"NOT_REACHED","detail":"No core-eligible configuration"},
            {"fixture_id":"H","test":"ZERO_REGULATORY_PLAN_A_EQUALS_PLAN_B","status":"NOT_REACHED","detail":"No core-eligible configuration"},
        ])

    pd.DataFrame(plan_a_rows).to_csv(out/"D10E_PLAN_A_REGULATORY_SCREEN.csv",index=False)
    pd.DataFrame(invariant_rows).to_csv(out/"D10E_INVARIANT_TESTS.csv",index=False)

    if top_core:
        core_pass = core_pass and F_pass and H_pass

    if not core_pass:
        status="FAIL_CLOSED"
        plan_a_status="NOT_REACHED"
        plan_b_status="FAIL_CORE_SIGNED_VALIDATION"
        plan_b_activated="NO"
        active_plan="NONE"
        failure_stage="CORE_SIGNED_METHOD_SYNTHETIC_VALIDATION"
        failure_reason=(
            "No core configuration satisfied the predeclared A/B recovery gates"
            if len(eligible_sorted)==0
            else "One or more hard signed invariants/reproducibility gates failed"
        )
        ready_d10f="NO"
    else:
        status="PASS"
        plan_b_status="PASS"
        if plan_a_identified:
            plan_a_status="PASS"
            plan_b_activated="NO"
            active_plan="PLAN_A_SIGNED_MULTICHANNEL_ACLA"
            failure_stage=""
            failure_reason=""
        else:
            plan_a_status="FAIL_MULTICHANNEL_IDENTIFIABILITY"
            plan_b_activated="YES"
            active_plan="PLAN_B_SIGNED_SINGLE_LAYER_ACLA"
            failure_stage=""
            failure_reason="PLAN_A_TO_PLAN_B_TRIGGER=MULTICHANNEL_IDENTIFIABILITY_FAIL"
        ready_d10f="YES"

    selected_plan_a_core = ""
    selected_plan_a_lambda = ""
    if selected_plan_a is not None:
        selected_plan_a_core=selected_plan_a[1]["core_config_id"]
        selected_plan_a_lambda=selected_plan_a[1]["lambda_regulatory"]

    result={
        "D10E_STATUS":status,
        "IMPLEMENTATION_SHA256":EXPECTED_IMPLEMENTATION_SHA256,
        "FIXTURES_A_TO_H_DEFINED":"YES",
        "FIXTURE_A_HARD_GATE_MEDIAN_ARI":FIXTURE_A_MEDIAN_ARI_MIN,
        "FIXTURE_A_HARD_GATE_MEDIAN_NMI":FIXTURE_A_MEDIAN_NMI_MIN,
        "FIXTURE_A_HARD_GATE_EXACT_RECOVERY_RATE":FIXTURE_A_EXACT_RECOVERY_RATE_MIN,
        "FIXTURE_B_HARD_GATE_MEDIAN_ARI":FIXTURE_B_MEDIAN_ARI_MIN,
        "FIXTURE_B_HARD_GATE_MEDIAN_NMI":FIXTURE_B_MEDIAN_NMI_MIN,
        "CORE_CONFIGURATIONS_TESTED":len(screen),
        "CORE_ELIGIBLE_CONFIGURATIONS":len(eligible_sorted),
        "TOP_CORE_CONFIG_ID":selected_core_id,
        "PLAN_B_CORE_STATUS":plan_b_status,
        "PLAN_A_STATUS":plan_a_status,
        "PLAN_A_NONZERO_LAMBDA_IDENTIFIED":"YES" if plan_a_identified else "NO",
        "PLAN_A_SELECTED_CORE_CONFIG_ID":selected_plan_a_core,
        "PLAN_A_SELECTED_LAMBDA_FOR_D10F_CANDIDACY":selected_plan_a_lambda,
        "PLAN_B_ACTIVATED":"YES" if plan_b_activated=="YES" else "NO",
        "ACTIVE_PLAN_FOR_D10F":active_plan,
        "BIOLOGICAL_PARAMETER_VALUES_FROZEN":"NO",
        "PARAMETER_TUNING_USING_GSE243219":"NO",
        "SYNTHETIC_PARAMETER_SCREEN_EXECUTED":"YES",
        "EXTERNAL_BASELINE_BENCHMARK_EXECUTED":"NO",
        "GSE243219_ACLA_EXECUTED":"NO",
        "D9_COMMUNITY_DETECTION_EXECUTED":"NO",
        "NETWORK_CHANGED":"NO",
        "D9_FILES_MODIFIED":"NO",
        "WEIGHT_TRANSFORMATION_APPLIED":"NO",
        "NEGATIVE_EDGES_REMOVED":"NO",
        "FAILURE_STAGE":failure_stage,
        "FAILURE_REASON":failure_reason,
        "READY_FOR_D10F_SIGNED_BENCHMARKING":ready_d10f,
        "READY_FOR_GSE243219_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }
    result_json.write_text(json.dumps(result,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
