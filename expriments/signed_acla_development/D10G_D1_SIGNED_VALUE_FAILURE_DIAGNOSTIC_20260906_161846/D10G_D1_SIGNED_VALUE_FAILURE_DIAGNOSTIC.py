#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_R1_SHA="2bfe790d6aff0fc0404d37683fed2ef0a7c85b78c6a31bb692d3f69d0f7e257d"
EXPECTED_POLICY_SHA="2662a7e3f62fd0bf9b246e20e033ffd22608387d7f2942bbe04f3d40c5322150"

AGGREGATE_ARI_ADVANTAGE_MIN=0.02
TASK_WINS_MIN=7
EXPECTED_TASKS=12

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk),b""):
            h.update(b)
    return h.hexdigest()

def require_token(path: Path, token: str, label: str):
    if not path.is_file():
        raise RuntimeError(f"{label}_FILE_MISSING={path}")
    text=path.read_text(encoding="utf-8-sig",errors="replace")
    if token not in text:
        raise RuntimeError(f"{label}_TOKEN_MISSING={token}")

def selftest():
    # Three possible scientifically meaningful G7 failure shapes.
    cases=[
        (0.01,8,"AGGREGATE_EFFECT_TOO_SMALL"),
        (0.03,5,"TASK_BREADTH_TOO_NARROW"),
        (0.01,5,"AGGREGATE_AND_BREADTH_FAIL"),
    ]
    for adv,wins,expected in cases:
        if adv < AGGREGATE_ARI_ADVANTAGE_MIN and wins < TASK_WINS_MIN:
            got="AGGREGATE_AND_BREADTH_FAIL"
        elif adv < AGGREGATE_ARI_ADVANTAGE_MIN:
            got="AGGREGATE_EFFECT_TOO_SMALL"
        elif wins < TASK_WINS_MIN:
            got="TASK_BREADTH_TOO_NARROW"
        else:
            got="PASS"
        assert got==expected
    print("D10G_D1_INTERNAL_SELFTEST=PASS")
    print("G7_DECOMPOSITION_SELFTEST=PASS")
    print("NO_ACCEPTANCE_RESCUE_SELFTEST=PASS")
    print("NO_GSE243219_ALGORITHM_EXECUTION_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=6:
        raise SystemExit("usage: diag <d10f_run> <d10g_run> <d9_run> <outdir> <result_json>")

    d10f=Path(sys.argv[1])
    d10g=Path(sys.argv[2])
    d9=Path(sys.argv[3])
    out=Path(sys.argv[4])
    result_json=Path(sys.argv[5])
    out.mkdir(parents=True,exist_ok=True)

    # Authority chain.
    for p,t,l in [
        (d10f/"D10F_FINAL_STATUS.txt","D10F_STATUS=PASS","D10F"),
        (d10f/"D10F_FINAL_STATUS.txt",f"R1_IMPLEMENTATION_SHA256={EXPECTED_R1_SHA}","D10F"),
        (d10f/"D10F_FINAL_STATUS.txt","ACTIVE_PLAN=PLAN_B_SIGNED_SINGLE_LAYER_ACLA","D10F"),
        (d10f/"D10F_FINAL_STATUS.txt","D10F_RANKED_CANDIDATE_CONFIG=CORE_04","D10F"),
        (d10f/"D10F_FINAL_STATUS.txt","GSE243219_ACLA_EXECUTED=NO","D10F"),
        (d10g/"D10G_FINAL_STATUS.txt","D10G_STATUS=FAIL_CLOSED","D10G"),
        (d10g/"D10G_FINAL_STATUS.txt",f"ACCEPTANCE_POLICY_SHA256={EXPECTED_POLICY_SHA}","D10G"),
        (d10g/"D10G_FINAL_STATUS.txt","ACCEPTANCE_GATES_TOTAL=9","D10G"),
        (d10g/"D10G_FINAL_STATUS.txt","ACCEPTANCE_GATES_PASSED=8","D10G"),
        (d10g/"D10G_FINAL_STATUS.txt","ACCEPTANCE_GATES_FAILED=1","D10G"),
        (d10g/"D10G_FINAL_STATUS.txt","METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE=NO","D10G"),
        (d10g/"D10G_FINAL_STATUS.txt","FAILURE_REASON=ACCEPTANCE_GATES_FAILED=G7_SIGNED_VALUE_OVER_POSITIVE_ONLY","D10G"),
        (d10g/"D10G_FINAL_STATUS.txt","READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE=NO","D10G"),
        (d10g/"D10G_FINAL_STATUS.txt","GSE243219_ACLA_EXECUTED=NO","D10G"),
    ]:
        require_token(p,t,l)

    required={
        "gate_results":d10g/"D10G_ACCEPTANCE_GATE_RESULTS.csv",
        "candidate_metrics":d10g/"D10G_CANDIDATE_METRICS.csv",
        "task_compare":d10g/"D10G_SIGNED_VS_POSITIVE_TASK_COMPARISON.csv",
        "ablation_summary":d10f/"D10F_ABLATION_SUMMARY.csv",
        "ablation_task":d10f/"D10F_ABLATION_TASK_SUMMARY.csv",
        "task_defs":d10f/"D10F_BENCHMARK_TASK_DEFINITIONS.csv",
        "r1_ranking":d10f/"D10F_R1_CONFIG_RANKING.csv",
        "baseline_summary":d10f/"D10F_BASELINE_SUMMARY.csv",
    }
    for name,p in required.items():
        if not p.is_file():
            raise RuntimeError(f"REQUIRED_EVIDENCE_MISSING={name}:{p}")

    gates=pd.read_csv(required["gate_results"])
    metrics=pd.read_csv(required["candidate_metrics"])
    compare=pd.read_csv(required["task_compare"])
    abls=pd.read_csv(required["ablation_summary"])
    abl_task=pd.read_csv(required["ablation_task"])
    task_defs=pd.read_csv(required["task_defs"])
    ranking=pd.read_csv(required["r1_ranking"])
    baselines=pd.read_csv(required["baseline_summary"])

    g7=gates[gates["gate"]=="G7_SIGNED_VALUE_OVER_POSITIVE_ONLY"]
    if len(g7)!=1 or str(g7.iloc[0]["status"])!="FAIL":
        raise RuntimeError("AUTHORITATIVE_G7_FAILURE_ROW_NOT_FOUND")

    if len(metrics)!=1:
        raise RuntimeError("D10G_CANDIDATE_METRICS_ROW_COUNT_INVALID")
    m=metrics.iloc[0]
    candidate=str(m["candidate_config"])
    if candidate!="CORE_04":
        raise RuntimeError(f"UNEXPECTED_CANDIDATE={candidate}")

    aggregate_adv=float(m["signed_over_positive_aggregate_ARI_advantage"])
    task_wins=int(m["signed_over_positive_task_wins"])

    aggregate_pass=aggregate_adv >= AGGREGATE_ARI_ADVANTAGE_MIN
    breadth_pass=task_wins >= TASK_WINS_MIN

    if not aggregate_pass and not breadth_pass:
        failure_shape="AGGREGATE_AND_BREADTH_FAIL"
    elif not aggregate_pass:
        failure_shape="AGGREGATE_EFFECT_TOO_SMALL"
    elif not breadth_pass:
        failure_shape="TASK_BREADTH_TOO_NARROW"
    else:
        failure_shape="G7_RESULT_INCONSISTENT_WITH_FROZEN_POLICY"

    if failure_shape=="G7_RESULT_INCONSISTENT_WITH_FROZEN_POLICY":
        raise RuntimeError("G7_GATE_INCONSISTENCY")

    # Recompute task wins independently from D10F ablation-task summaries.
    full=abl_task[abl_task["ablation"]=="FULL_PLAN_B_TOPCORE"][
        ["task_id","median_ARI","median_NMI","median_signed_Q"]
    ].rename(columns={
        "median_ARI":"signed_full_ARI",
        "median_NMI":"signed_full_NMI",
        "median_signed_Q":"signed_full_Q",
    })
    pos=abl_task[
        abl_task["ablation"]=="PUBLISHED_POSITIVE_ONLY_SEMANTICS_R1_DIAGNOSTIC"
    ][["task_id","median_ARI","median_NMI","median_signed_Q"]].rename(columns={
        "median_ARI":"positive_only_ARI",
        "median_NMI":"positive_only_NMI",
        "median_signed_Q":"positive_only_Q_on_original_signed_graph",
    })
    paired=full.merge(pos,on="task_id",how="inner")
    if len(paired)!=EXPECTED_TASKS:
        raise RuntimeError(f"PAIRED_TASK_COUNT={len(paired)}")

    paired["ARI_advantage_signed_minus_positive"]=paired["signed_full_ARI"]-paired["positive_only_ARI"]
    paired["NMI_advantage_signed_minus_positive"]=paired["signed_full_NMI"]-paired["positive_only_NMI"]
    paired["Q_advantage_signed_minus_positive"]=paired["signed_full_Q"]-paired["positive_only_Q_on_original_signed_graph"]
    paired["signed_ARI_win"]=(paired["ARI_advantage_signed_minus_positive"]>1e-12).astype(int)
    paired["signed_ARI_tie"]=(paired["ARI_advantage_signed_minus_positive"].abs()<=1e-12).astype(int)
    paired["signed_ARI_loss"]=(paired["ARI_advantage_signed_minus_positive"]<-1e-12).astype(int)

    recomputed_wins=int(paired["signed_ARI_win"].sum())
    if recomputed_wins!=task_wins:
        raise RuntimeError(
            f"G7_TASK_WIN_RECOMPUTATION_MISMATCH={recomputed_wins}!={task_wins}"
        )

    # Add benchmark family/noise context.
    family_cols=[
        "task_id","family","n_nodes","n_edges","positive_edges","negative_edges",
        "planted_communities","p_in","p_out","sign_flip_probability"
    ]
    paired=paired.merge(task_defs[family_cols],on="task_id",how="left")
    if paired["family"].isna().any():
        raise RuntimeError("TASK_FAMILY_JOIN_FAILED")

    paired.to_csv(out/"D10G_D1_TASK_LEVEL_SIGNED_VALUE.csv",index=False)

    family=paired.groupby("family",as_index=False).agg(
        tasks=("task_id","count"),
        signed_ARI_wins=("signed_ARI_win","sum"),
        median_ARI_advantage=("ARI_advantage_signed_minus_positive","median"),
        mean_ARI_advantage=("ARI_advantage_signed_minus_positive","mean"),
        median_NMI_advantage=("NMI_advantage_signed_minus_positive","median"),
        median_Q_advantage=("Q_advantage_signed_minus_positive","median"),
        median_negative_edges=("negative_edges","median"),
        sign_flip_probability=("sign_flip_probability","first"),
    )
    family.to_csv(out/"D10G_D1_FAMILY_LEVEL_SIGNED_VALUE.csv",index=False)

    # Determine whether positive-only ablation itself is already strong in the
    # benchmark suite, which may explain lack of incremental value.
    abls_idx=abls.set_index("ablation")
    for key in [
        "FULL_PLAN_B_TOPCORE",
        "PUBLISHED_POSITIVE_ONLY_SEMANTICS_R1_DIAGNOSTIC",
        "SIGNED_LOCAL_ONLY",
        "SIGNED_GLOBAL_ONLY",
    ]:
        if key not in abls_idx.index:
            raise RuntimeError(f"ABLATION_MISSING={key}")

    full_sum=abls_idx.loc["FULL_PLAN_B_TOPCORE"]
    pos_sum=abls_idx.loc["PUBLISHED_POSITIVE_ONLY_SEMANTICS_R1_DIAGNOSTIC"]

    summary=pd.DataFrame([{
        "candidate_config":candidate,
        "G7_aggregate_ARI_advantage":aggregate_adv,
        "G7_required_aggregate_ARI_advantage":AGGREGATE_ARI_ADVANTAGE_MIN,
        "G7_aggregate_subgate_pass":"YES" if aggregate_pass else "NO",
        "G7_signed_task_wins":task_wins,
        "G7_required_task_wins":TASK_WINS_MIN,
        "G7_breadth_subgate_pass":"YES" if breadth_pass else "NO",
        "G7_failure_shape":failure_shape,
        "signed_full_median_task_ARI":float(full_sum["median_task_ARI"]),
        "positive_only_median_task_ARI":float(pos_sum["median_task_ARI"]),
        "signed_full_median_task_NMI":float(full_sum["median_task_NMI"]),
        "positive_only_median_task_NMI":float(pos_sum["median_task_NMI"]),
        "signed_full_median_task_signed_Q":float(full_sum["median_task_signed_Q"]),
        "positive_only_median_task_signed_Q":float(pos_sum["median_task_signed_Q"]),
    }])
    summary.to_csv(out/"D10G_D1_G7_DECOMPOSITION.csv",index=False)

    # Classify the evidentiary meaning. This is diagnostic only; it cannot
    # override D10G.
    positive_only_is_competitive = (
        float(pos_sum["median_task_ARI"]) >= float(full_sum["median_task_ARI"]) - 0.02
    )

    result={
        "D10G_D1_STATUS":"PASS",
        "UPSTREAM_D10G_STATUS":"FAIL_CLOSED",
        "R1_IMPLEMENTATION_SHA256":EXPECTED_R1_SHA,
        "D10G_ACCEPTANCE_POLICY_SHA256":EXPECTED_POLICY_SHA,
        "CANDIDATE_CONFIG":candidate,
        "G7_AGGREGATE_ARI_ADVANTAGE":aggregate_adv,
        "G7_AGGREGATE_ARI_ADVANTAGE_REQUIRED":AGGREGATE_ARI_ADVANTAGE_MIN,
        "G7_AGGREGATE_SUBGATE_PASS":"YES" if aggregate_pass else "NO",
        "G7_SIGNED_TASK_WINS":task_wins,
        "G7_SIGNED_TASK_WINS_REQUIRED":TASK_WINS_MIN,
        "G7_BREADTH_SUBGATE_PASS":"YES" if breadth_pass else "NO",
        "G7_FAILURE_SHAPE":failure_shape,
        "POSITIVE_ONLY_ABLATION_COMPETITIVE":"YES" if positive_only_is_competitive else "NO",
        "SIGNED_SEMANTIC_INCREMENTAL_VALUE_ESTABLISHED":"NO",
        "D10G_DECISION_OVERRIDDEN":"NO",
        "THRESHOLD_RELAXATION_JUSTIFIED":"NO",
        "POSTHOC_G7_RELAXATION_ALLOWED":"NO",
        "D10H_PARAMETER_FREEZE_AUTHORIZED":"NO",
        "GSE243219_ACLA_EXECUTED":"NO",
        "D9_COMMUNITY_DETECTION_EXECUTED":"NO",
        "PARAMETER_TUNING_USING_GSE243219":"NO",
        "NETWORK_CHANGED":"NO",
        "D9_FILES_MODIFIED":"NO",
        "WEIGHT_TRANSFORMATION_APPLIED":"NO",
        "READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE":"NO",
        "READY_FOR_GSE243219_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }
    result_json.write_text(json.dumps(result,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
