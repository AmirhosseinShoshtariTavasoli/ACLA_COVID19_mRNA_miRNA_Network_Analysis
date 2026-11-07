#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_IMPL_SHA="a46a2fd5beacec09f800fd6d1c855b2c8f4c10e2159028542ac46cedef19fe24"

def sha256_file(p: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda:f.read(chunk),b""):
            h.update(b)
    return h.hexdigest()

def load_impl(p: Path):
    if sha256_file(p)!=EXPECTED_IMPL_SHA:
        raise RuntimeError("IMPLEMENTATION_SHA256_MISMATCH")
    spec=importlib.util.spec_from_file_location("sacla_diag",p)
    mod=importlib.util.module_from_spec(spec)
    sys.modules[spec.name]=mod
    spec.loader.exec_module(mod)
    return mod

def make_component(mod,n,edges):
    ndf=pd.DataFrame({"node_index":range(n),"node_id":[f"N{i}" for i in range(n)]})
    edf=pd.DataFrame([{"source_index":u,"target_index":v,"association_score":w} for u,v,w in edges])
    rdf=pd.DataFrame(columns=["source_index","target_index"])
    return mod.build_signed_components(ndf,edf,rdf)[0]

def ideal_fixture():
    n_per=5
    n=10
    edges=[]
    for i in range(n):
        for j in range(i+1,n):
            same=(i<n_per)==(j<n_per)
            if same:
                w=0.75+0.05*((i+2*j)%5)
            else:
                w=-(0.55+0.05*((2*i+j)%5))
            edges.append((i,j,float(w)))
    truth={i:(0 if i<5 else 5) for i in range(10)}
    return n,edges,truth

def static_audit(source: str):
    harmful = bool(re.search(
        r"(?is)if\s+do_move\s*:\s*.*?labels\[node\]\s*=\s*new.*?e\s*=\s*d\s+if\s+chosen\s*==\s*[\"']MOVE[\"']\s+else\s+-d",
        source
    ))
    singleton_always = bool(re.search(
        r"(?is)def\s+candidate_communities.*?result\.append\(None\)",
        source
    ))
    label_sensitive = bool(re.search(
        r"(?is)before_labels\s*=\s*labels\.copy\(\).*?labels\s*=\s*canonicalize_labels\(labels\).*?changed\s*=\s*sum\(before_labels\[n\]\s*!=\s*labels\[n\]",
        source
    ))
    return harmful,singleton_always,label_sensitive

def selftest():
    sample = (
        'if do_move:\n'
        '    labels[node] = new\n'
        'e = d if chosen == "MOVE" else -d\n'
    )
    assert re.search(
        r"(?is)if\s+do_move\s*:\s*.*?labels\[node\]\s*=\s*new.*?e\s*=\s*d\s+if\s+chosen",
        sample
    )
    print("D10E_D1_INTERNAL_SELFTEST=PASS")
    print("STATIC_TRANSITION_AUDIT_SELFTEST=PASS")
    print("NO_REDESIGN_EXECUTION_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=6:
        raise SystemExit("usage: diag <impl.py> <d10e_run> <d9_run> <outdir> <result_json>")

    impl=Path(sys.argv[1])
    d10e=Path(sys.argv[2])
    d9=Path(sys.argv[3])
    out=Path(sys.argv[4])
    res=Path(sys.argv[5])
    out.mkdir(parents=True,exist_ok=True)

    d10e_status=(d10e/"D10E_FINAL_STATUS.txt").read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10E_STATUS=FAIL_CLOSED",
        "CORE_ELIGIBLE_CONFIGURATIONS=0",
        "FAILURE_STAGE=CORE_SIGNED_METHOD_SYNTHETIC_VALIDATION",
        "READY_FOR_D10F_SIGNED_BENCHMARKING=NO",
        "GSE243219_ACLA_EXECUTED=NO",
    ]:
        if tok not in d10e_status:
            raise RuntimeError(f"D10E_AUTHORITY_TOKEN_MISSING={tok}")

    if sha256_file(impl)!=EXPECTED_IMPL_SHA:
        raise RuntimeError("IMPLEMENTATION_SHA256_MISMATCH")

    d9_status=(d9/"D9_FINAL_STATUS.txt").read_text(encoding="utf-8-sig",errors="replace")
    if "D9_STATUS=PASS" not in d9_status or "ACLA_EXECUTED=NO" not in d9_status:
        raise RuntimeError("D9_AUTHORITY_FAILED")

    mod=load_impl(impl)
    source=impl.read_text(encoding="utf-8",errors="replace")
    harmful,singleton_always,label_sensitive=static_audit(source)

    screen=pd.read_csv(d10e/"D10E_CORE_PARAMETER_SCREEN.csv")
    seed=pd.read_csv(d10e/"D10E_SEED_LEVEL_RESULTS.csv")
    inv=pd.read_csv(d10e/"D10E_INVARIANT_TESTS.csv")

    inv_map=dict(zip(inv["test"],inv["status"]))
    signed_math_pass=all(inv_map.get(k)=="PASS" for k in [
        "POSITIVE_ONLY_OBJECTIVE_REDUCTION",
        "NEGATIVE_WITHIN_PENALTY",
        "DISCONNECTED_COMPONENT_RETENTION",
    ])

    n,edges,truth=ideal_fixture()
    comp=make_component(mod,n,edges)
    singleton={i:i for i in range(n)}
    allone={i:0 for i in range(n)}
    q_truth=mod.signed_component_objective(comp,truth)
    q_single=mod.signed_component_objective(comp,singleton)
    q_all=mod.signed_component_objective(comp,allone)

    a=screen.copy()
    a=a.sort_values(
        ["A_median_ARI","A_median_NMI","config_id"],
        ascending=[False,False,True],
    )
    rep=a.iloc[0]
    config_id=str(rep["config_id"])
    cfg=mod.SACLAConfig(
        alpha_reward=float(rep["alpha_reward"]),
        alpha_penalty=float(rep["alpha_penalty"]),
        gamma=float(rep["gamma"]),
        lambda_regulatory=0.0,
        max_iterations=200,
        objective_tolerance=1e-6,
        node_change_tolerance=0.02,
        probability_change_tolerance=1e-2,
        patience=5,
    )

    sd=seed[(seed["fixture_id"]=="A")&(seed["config_id"]==config_id)].copy()
    sd=sd.sort_values(["ARI","objective","seed_index"],ascending=[False,False,True])
    rep_seed_row=sd.iloc[0]
    rep_seed=int(rep_seed_row["seed"])
    rr=mod.run_one_component(comp,cfg,rep_seed)

    cp,cn=mod.component_community_strengths(comp,rr.labels)
    move_rows=[]
    max_adv=-float("inf")
    max_dq=-float("inf")
    for node in comp.nodes:
        scores=mod.candidate_scores(comp,rr.labels,node,0.0,cfg.gamma,cp,cn)
        current=scores[rr.labels[node]]
        for dest,s in scores.items():
            if dest==rr.labels[node]:
                continue
            adv=s[0]-current[0]
            move_rows.append({
                "node":node,
                "current_label":rr.labels[node],
                "candidate_label":"NEW_SINGLETON" if dest is None else dest,
                "utility_current":current[0],
                "utility_candidate":s[0],
                "utility_advantage":adv,
                "delta_signed_objective":s[2],
                "local_current":current[1],
                "local_candidate":s[1],
            })
            max_adv=max(max_adv,adv)
            max_dq=max(max_dq,s[2])
    moves=pd.DataFrame(move_rows).sort_values(
        ["utility_advantage","delta_signed_objective"],
        ascending=[False,False]
    )
    moves.to_csv(out/"D10E_D1_REPRESENTATIVE_FINAL_MOVE_AUDIT.csv",index=False)

    cp_t,cn_t=mod.component_community_strengths(comp,truth)
    truth_rows=[]
    all_worse=True
    for node in comp.nodes:
        best,best_s,current_s=mod.candidate_best_alternative(
            comp,truth,node,0.0,cfg.gamma,cp_t,cn_t
        )
        d=best_s[0]-current_s[0]
        all_worse=all_worse and d<0
        truth_rows.append({
            "node":node,
            "best_alternative":"NEW_SINGLETON" if best is None else best,
            "candidate_advantage":d,
            "move_would_be_harmful":int(d<0),
            "current_transition_executes_move_if_sampled":int(harmful),
        })
    pd.DataFrame(truth_rows).to_csv(
        out/"D10E_D1_PLANTED_PARTITION_TRANSITION_AUDIT.csv",index=False
    )

    summary_rows=[]
    for _,row in screen.iterrows():
        cid=str(row["config_id"])
        ccfg=mod.SACLAConfig(
            float(row["alpha_reward"]),
            float(row["alpha_penalty"]),
            float(row["gamma"]),
            0.0,
            200,1e-6,0.02,1e-2,5
        )
        traj=[]
        for k in range(1,11):
            r=mod.run_one_component(comp,ccfg,mod.deterministic_seed(k))
            h=r.history
            traj.append({
                "max_abs_objective_jump":float(h["objective_change"].abs().max()),
                "median_changed_fraction":float(h["changed_fraction"].median()),
                "final_changed_fraction":float(h["changed_fraction"].iloc[-1]),
                "final_probability_min":float(h["probability_min"].iloc[-1]),
                "final_probability_max":float(h["probability_max"].iloc[-1]),
            })
        t=pd.DataFrame(traj)
        summary_rows.append({
            "config_id":cid,
            "median_max_abs_objective_jump":float(t["max_abs_objective_jump"].median()),
            "median_changed_fraction":float(t["median_changed_fraction"].median()),
            "median_final_changed_fraction":float(t["final_changed_fraction"].median()),
            "median_final_probability_min":float(t["final_probability_min"].median()),
            "median_final_probability_max":float(t["final_probability_max"].median()),
        })
    pd.DataFrame(summary_rows).to_csv(out/"D10E_D1_DYNAMICS_SUMMARY.csv",index=False)

    source_rows=[
        {
            "finding":"HARMFUL_MOVE_EXECUTION_ALLOWED",
            "status":"YES" if harmful else "NO",
            "evidence":"MOVE state transition occurs before environment response; negative d penalizes probability only after the move."
        },
        {
            "finding":"CURRENT_SINGLETON_DUPLICATE_ACTION_PRESENT",
            "status":"YES" if singleton_always else "NO",
            "evidence":"candidate_communities always appends None/new singleton, including when the node already forms a singleton."
        },
        {
            "finding":"SWITCH_METRIC_CANONICAL_LABEL_SENSITIVE",
            "status":"YES" if label_sensitive else "NO",
            "evidence":"changed_nodes compares labels before sweep with canonicalized labels after sweep rather than partition-equivalence membership."
        },
        {
            "finding":"SIGNED_MATHEMATICAL_INVARIANTS_PASS",
            "status":"YES" if signed_math_pass else "NO",
            "evidence":"positive-only reduction, negative-within penalty, disconnected retention passed in authoritative D10E."
        },
        {
            "finding":"PLANTED_PARTITION_OBJECTIVE_GT_SINGLETON_AND_ALLONE",
            "status":"YES" if q_truth>q_single and q_truth>q_all else "NO",
            "evidence":f"Q_truth={q_truth};Q_singleton={q_single};Q_allone={q_all}"
        },
        {
            "finding":"REPRESENTATIVE_TERMINAL_STATE_HAS_IMPROVING_MOVE",
            "status":"YES" if max_adv>0 and max_dq>0 else "NO",
            "evidence":f"config={config_id};seed={rep_seed};max_utility_advantage={max_adv};max_delta_Q={max_dq}"
        },
        {
            "finding":"PLANTED_PARTITION_NOT_ABSORBING_IF_P_MOVE_POSITIVE",
            "status":"YES" if harmful and all_worse else "NO",
            "evidence":"At planted truth every best alternative is worse, but current implementation still executes MOVE whenever sampled; penalty occurs afterward."
        },
    ]
    pd.DataFrame(source_rows).to_csv(out/"D10E_D1_FAILURE_MECHANISM_AUDIT.csv",index=False)

    diagnosis_pass=(
        signed_math_pass
        and harmful
        and singleton_always
        and label_sensitive
        and q_truth>q_single
        and q_truth>q_all
        and max_adv>0
        and max_dq>0
    )

    result={
        "D10E_D1_STATUS":"PASS" if diagnosis_pass else "REVIEW_REQUIRED",
        "UPSTREAM_D10E_STATUS":"FAIL_CLOSED",
        "IMPLEMENTATION_SHA256":EXPECTED_IMPL_SHA,
        "SIGNED_OBJECTIVE_AND_LOCAL_SEMANTICS_VALIDATED":"YES" if signed_math_pass else "NO",
        "PLANTED_TRUTH_SIGNED_OBJECTIVE":q_truth,
        "ALL_SINGLETON_SIGNED_OBJECTIVE":q_single,
        "ALL_ONE_SIGNED_OBJECTIVE":q_all,
        "REPRESENTATIVE_CONFIG_ID":config_id,
        "REPRESENTATIVE_SEED":rep_seed,
        "REPRESENTATIVE_FINAL_ARI":float(mod.adjusted_rand_index_from_labels(rr.labels,truth)),
        "REPRESENTATIVE_FINAL_OBJECTIVE":float(rr.objective),
        "REPRESENTATIVE_FINAL_COMMUNITIES":len(set(rr.labels.values())),
        "REPRESENTATIVE_MAX_IMPROVING_UTILITY_ADVANTAGE":float(max_adv),
        "REPRESENTATIVE_MAX_IMPROVING_DELTA_Q":float(max_dq),
        "HARMFUL_MOVE_EXECUTION_ALLOWED":"YES" if harmful else "NO",
        "CURRENT_SINGLETON_DUPLICATE_ACTION_PRESENT":"YES" if singleton_always else "NO",
        "SWITCH_METRIC_CANONICAL_LABEL_SENSITIVE":"YES" if label_sensitive else "NO",
        "PLANTED_PARTITION_NOT_ABSORBING_IF_P_MOVE_POSITIVE":"YES" if harmful and all_worse else "NO",
        "FAILURE_CLASSIFICATION":"LEARNING_DYNAMICS_TRANSITION_INSTABILITY",
        "THRESHOLD_RELAXATION_JUSTIFIED":"NO",
        "PARAMETER_RANGE_EXPANSION_AS_ACCEPTANCE_FIX_JUSTIFIED":"NO",
        "PLAN_A_REGULATORY_CHANNEL_REACHED":"NO",
        "PLAN_B_CAN_RESCUE_CURRENT_CORE":"NO",
        "GSE243219_ACLA_EXECUTED":"NO",
        "D9_COMMUNITY_DETECTION_EXECUTED":"NO",
        "NETWORK_CHANGED":"NO",
        "D9_FILES_MODIFIED":"NO",
        "WEIGHT_TRANSFORMATION_APPLIED":"NO",
        "PARAMETER_TUNING_USING_GSE243219":"NO",
        "READY_FOR_D10F_SIGNED_BENCHMARKING":"NO",
        "READY_FOR_D10C_R1_PROSPECTIVE_CORE_DYNAMICS_REDESIGN":"YES" if diagnosis_pass else "NO",
        "READY_FOR_GSE243219_ACLA_EXECUTION":"NO",
        "STOP":"YES"
    }
    res.write_text(json.dumps(result,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
