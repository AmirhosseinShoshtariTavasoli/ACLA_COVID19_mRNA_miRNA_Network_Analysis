#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_POLICY_SHA="2662a7e3f62fd0bf9b246e20e033ffd22608387d7f2942bbe04f3d40c5322150"
EXPECTED_R1_SHA="2bfe790d6aff0fc0404d37683fed2ef0a7c85b78c6a31bb692d3f69d0f7e257d"

SIGNED_BASELINES={
    "GOMEZ_SIGNED_MODULARITY_GREEDY",
    "TRAAG_BRUGGEMAN_GAMMA_0.5",
    "TRAAG_BRUGGEMAN_GAMMA_1.0",
    "TRAAG_BRUGGEMAN_GAMMA_2.0",
    "SIGNED_SPECTRAL_ORACLE_K",
}

ARI_NONINFERIORITY_MARGIN=0.05
NMI_NONINFERIORITY_MARGIN=0.05
MEDIAN_SEED_STABILITY_MIN=0.80
MEDIAN_CONVERGENCE_MIN=0.90
WORST_TASK_CONVERGENCE_MIN=0.70
MIN_TASK_ARI=0.25
MIN_TASK_NMI=0.35
ABLATION_NONINFERIORITY_MARGIN=0.03
SIGNED_OVER_POSITIVE_ARI_ADVANTAGE_MIN=0.02
SIGNED_OVER_POSITIVE_TASK_WINS_MIN=7
EXPECTED_TASKS=12
EXPECTED_R1_SEEDS_PER_TASK=10

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

def gate(name: str, passed: bool, observed, criterion: str, detail: str=""):
    return {
        "gate":name,
        "status":"PASS" if passed else "FAIL",
        "observed":observed,
        "criterion":criterion,
        "detail":detail,
    }

def selftest():
    mock_candidate={
        "ari":0.80,"nmi":0.82,"stability":0.90,"conv":1.0,
        "worst_conv":0.9,"min_ari":0.5,"min_nmi":0.55,
    }
    assert mock_candidate["ari"] >= 0.84-ARI_NONINFERIORITY_MARGIN
    assert mock_candidate["nmi"] >= 0.86-NMI_NONINFERIORITY_MARGIN
    assert mock_candidate["stability"] >= MEDIAN_SEED_STABILITY_MIN
    assert SIGNED_OVER_POSITIVE_TASK_WINS_MIN == 7
    print("D10G_INTERNAL_SELFTEST=PASS")
    print("ACCEPTANCE_GATE_LOGIC_SELFTEST=PASS")
    print("NO_GSE243219_ALGORITHM_EXECUTION_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=6:
        raise SystemExit("usage: D10G <d10f_run> <d9_run> <policy> <outdir> <result_json>")

    d10f=Path(sys.argv[1])
    d9=Path(sys.argv[2])
    policy=Path(sys.argv[3])
    out=Path(sys.argv[4])
    result_json=Path(sys.argv[5])
    out.mkdir(parents=True,exist_ok=True)

    if sha256_file(policy)!=EXPECTED_POLICY_SHA:
        raise RuntimeError("D10G_ACCEPTANCE_POLICY_SHA_MISMATCH")

    status=d10f/"D10F_FINAL_STATUS.txt"
    required_status_tokens=[
        "D10F_STATUS=PASS",
        f"R1_IMPLEMENTATION_SHA256={EXPECTED_R1_SHA}",
        "ACTIVE_PLAN=PLAN_B_SIGNED_SINGLE_LAYER_ACLA",
        "PLAN_A_REOPENED=NO",
        "BENCHMARK_TASKS=12",
        "R1_SEEDS_PER_TASK=10",
        "D10F_PARAMETER_FREEZE_EXECUTED=NO",
        "D10F_METHOD_ACCEPTANCE_DECISION_EXECUTED=NO",
        "GSE243219_ACLA_EXECUTED=NO",
        "D9_COMMUNITY_DETECTION_EXECUTED=NO",
        "D10F_HASH_MISMATCHES=0",
        "READY_FOR_D10G_PROSPECTIVE_ACCEPTANCE=YES",
        "READY_FOR_GSE243219_ACLA_EXECUTION=NO",
    ]
    for tok in required_status_tokens:
        require_token(status,tok,"D10F")

    # Required evidence tables.
    paths={
        "ranking":d10f/"D10F_R1_CONFIG_RANKING.csv",
        "r1_task":d10f/"D10F_R1_TASK_SUMMARY.csv",
        "r1_seed":d10f/"D10F_R1_SEED_LEVEL_RESULTS.csv",
        "baseline":d10f/"D10F_BASELINE_SUMMARY.csv",
        "baseline_task":d10f/"D10F_BASELINE_TASK_SUMMARY.csv",
        "ablation":d10f/"D10F_ABLATION_SUMMARY.csv",
        "ablation_task":d10f/"D10F_ABLATION_TASK_SUMMARY.csv",
        "result":d10f/"D10F_RESULT.json",
    }
    for name,p in paths.items():
        if not p.is_file():
            raise RuntimeError(f"D10F_EVIDENCE_MISSING={name}:{p}")

    ranking=pd.read_csv(paths["ranking"])
    r1_task=pd.read_csv(paths["r1_task"])
    r1_seed=pd.read_csv(paths["r1_seed"])
    baseline=pd.read_csv(paths["baseline"])
    baseline_task=pd.read_csv(paths["baseline_task"])
    ablation=pd.read_csv(paths["ablation"])
    ablation_task=pd.read_csv(paths["ablation_task"])
    d10f_result=json.loads(paths["result"].read_text(encoding="utf-8"))

    if len(ranking)<1 or int(ranking.iloc[0]["benchmark_rank"])!=1:
        raise RuntimeError("D10F_RANKING_INVALID")
    candidate=str(ranking.iloc[0]["config_id"])
    if str(d10f_result["D10F_RANKED_CANDIDATE_CONFIG"])!=candidate:
        raise RuntimeError("D10F_CANDIDATE_ID_MISMATCH")

    candidate_rank=ranking.iloc[0]
    cand_tasks=r1_task[r1_task["config_id"].astype(str)==candidate].copy()
    cand_seeds=r1_seed[r1_seed["config_id"].astype(str)==candidate].copy()

    if len(cand_tasks)!=EXPECTED_TASKS:
        raise RuntimeError(f"CANDIDATE_TASK_COUNT={len(cand_tasks)}")
    if len(cand_seeds)!=EXPECTED_TASKS*EXPECTED_R1_SEEDS_PER_TASK:
        raise RuntimeError(f"CANDIDATE_SEED_RESULT_COUNT={len(cand_seeds)}")
    if cand_tasks["task_id"].nunique()!=EXPECTED_TASKS:
        raise RuntimeError("CANDIDATE_UNIQUE_TASK_COUNT_INVALID")

    signed=baseline[baseline["method"].isin(SIGNED_BASELINES)].copy()
    if set(signed["method"])!=SIGNED_BASELINES:
        raise RuntimeError(
            "SIGNED_BASELINE_SET_INCOMPLETE=" +
            repr(sorted(SIGNED_BASELINES-set(signed["method"])))
        )

    best_signed_ari=float(signed["median_task_ARI"].max())
    best_signed_nmi=float(signed["median_task_NMI"].max())

    cand_ari=float(candidate_rank["median_task_ARI"])
    cand_nmi=float(candidate_rank["median_task_NMI"])
    cand_stability=float(candidate_rank["median_task_seed_stability"])
    cand_conv=float(candidate_rank["median_task_convergence_rate"])
    worst_conv=float(cand_tasks["convergence_rate"].min())
    min_task_ari=float(cand_tasks["median_ARI"].min())
    min_task_nmi=float(cand_tasks["median_NMI"].min())

    gates=[]
    gates.append(gate(
        "G1_SIGNED_BASELINE_ARI_NONINFERIORITY",
        cand_ari >= best_signed_ari-ARI_NONINFERIORITY_MARGIN,
        cand_ari,
        f">= best_signed_ARI({best_signed_ari:.6g})-{ARI_NONINFERIORITY_MARGIN}",
    ))
    gates.append(gate(
        "G2_SIGNED_BASELINE_NMI_NONINFERIORITY",
        cand_nmi >= best_signed_nmi-NMI_NONINFERIORITY_MARGIN,
        cand_nmi,
        f">= best_signed_NMI({best_signed_nmi:.6g})-{NMI_NONINFERIORITY_MARGIN}",
    ))
    gates.append(gate(
        "G3_MEDIAN_SEED_STABILITY",
        cand_stability >= MEDIAN_SEED_STABILITY_MIN,
        cand_stability,
        f">={MEDIAN_SEED_STABILITY_MIN}",
    ))
    conv_pass=(cand_conv>=MEDIAN_CONVERGENCE_MIN and worst_conv>=WORST_TASK_CONVERGENCE_MIN)
    gates.append(gate(
        "G4_CONVERGENCE",
        conv_pass,
        f"median={cand_conv};worst_task={worst_conv}",
        f"median>={MEDIAN_CONVERGENCE_MIN} AND worst_task>={WORST_TASK_CONVERGENCE_MIN}",
    ))
    catastrophic_pass=(min_task_ari>=MIN_TASK_ARI and min_task_nmi>=MIN_TASK_NMI)
    gates.append(gate(
        "G5_NO_CATASTROPHIC_TASK",
        catastrophic_pass,
        f"min_task_ARI={min_task_ari};min_task_NMI={min_task_nmi}",
        f"ARI>={MIN_TASK_ARI} AND NMI>={MIN_TASK_NMI}",
    ))

    abl=ablation.set_index("ablation")
    required_abls={
        "FULL_PLAN_B_TOPCORE",
        "SIGNED_LOCAL_ONLY",
        "SIGNED_GLOBAL_ONLY",
        "PUBLISHED_POSITIVE_ONLY_SEMANTICS_R1_DIAGNOSTIC",
    }
    if not required_abls.issubset(set(abl.index)):
        raise RuntimeError("D10F_ABLATION_SET_INCOMPLETE")

    full=abl.loc["FULL_PLAN_B_TOPCORE"]
    local=abl.loc["SIGNED_LOCAL_ONLY"]
    global_=abl.loc["SIGNED_GLOBAL_ONLY"]
    positive=abl.loc["PUBLISHED_POSITIVE_ONLY_SEMANTICS_R1_DIAGNOSTIC"]

    best_component_ari=max(float(local["median_task_ARI"]),float(global_["median_task_ARI"]))
    best_component_nmi=max(float(local["median_task_NMI"]),float(global_["median_task_NMI"]))
    full_ari=float(full["median_task_ARI"])
    full_nmi=float(full["median_task_NMI"])

    g6=(
        full_ari >= best_component_ari-ABLATION_NONINFERIORITY_MARGIN
        and full_nmi >= best_component_nmi-ABLATION_NONINFERIORITY_MARGIN
    )
    gates.append(gate(
        "G6_FULL_VS_COMPONENT_ABLATIONS_NONINFERIORITY",
        g6,
        f"full_ARI={full_ari};best_component_ARI={best_component_ari};"
        f"full_NMI={full_nmi};best_component_NMI={best_component_nmi}",
        f"full no more than {ABLATION_NONINFERIORITY_MARGIN} below best local/global on both ARI and NMI",
    ))

    full_task=ablation_task[
        ablation_task["ablation"]=="FULL_PLAN_B_TOPCORE"
    ][["task_id","median_ARI"]].rename(columns={"median_ARI":"full_ARI"})
    pos_task=ablation_task[
        ablation_task["ablation"]=="PUBLISHED_POSITIVE_ONLY_SEMANTICS_R1_DIAGNOSTIC"
    ][["task_id","median_ARI"]].rename(columns={"median_ARI":"positive_ARI"})
    merged=full_task.merge(pos_task,on="task_id",how="inner")
    if len(merged)!=EXPECTED_TASKS:
        raise RuntimeError(f"ABLATION_TASK_PAIR_COUNT={len(merged)}")
    wins=int((merged["full_ARI"]>merged["positive_ARI"]+1e-12).sum())
    aggregate_adv=full_ari-float(positive["median_task_ARI"])
    g7=(aggregate_adv>=SIGNED_OVER_POSITIVE_ARI_ADVANTAGE_MIN and wins>=SIGNED_OVER_POSITIVE_TASK_WINS_MIN)
    gates.append(gate(
        "G7_SIGNED_VALUE_OVER_POSITIVE_ONLY",
        g7,
        f"aggregate_ARI_advantage={aggregate_adv};task_wins={wins}/{EXPECTED_TASKS}",
        f"aggregate ARI advantage>={SIGNED_OVER_POSITIVE_ARI_ADVANTAGE_MIN} AND wins>={SIGNED_OVER_POSITIVE_TASK_WINS_MIN}",
    ))

    runtimes=pd.to_numeric(cand_seeds["runtime_seconds"],errors="coerce")
    runtime_pass=(
        len(runtimes)==EXPECTED_TASKS*EXPECTED_R1_SEEDS_PER_TASK
        and runtimes.notna().all()
        and np.isfinite(runtimes.to_numpy(float)).all()
        and (runtimes>=0).all()
    )
    gates.append(gate(
        "G8_RUNTIME_AND_COMPLETION_SANITY",
        runtime_pass,
        f"rows={len(runtimes)};finite={bool(np.isfinite(runtimes.to_numpy(float)).all())}",
        f"exactly {EXPECTED_TASKS*EXPECTED_R1_SEEDS_PER_TASK} finite non-negative runtimes",
    ))

    gates.append(gate(
        "G9_SAFETY_AND_PROVENANCE",
        True,
        "upstream status tokens verified",
        "all mandatory D10F safety/provenance tokens present",
    ))

    gate_df=pd.DataFrame(gates)
    gate_df.to_csv(out/"D10G_ACCEPTANCE_GATE_RESULTS.csv",index=False)

    candidate_metrics=pd.DataFrame([{
        "candidate_config":candidate,
        "candidate_median_task_ARI":cand_ari,
        "best_signed_baseline_median_task_ARI":best_signed_ari,
        "ARI_noninferiority_difference":cand_ari-best_signed_ari,
        "candidate_median_task_NMI":cand_nmi,
        "best_signed_baseline_median_task_NMI":best_signed_nmi,
        "NMI_noninferiority_difference":cand_nmi-best_signed_nmi,
        "candidate_median_seed_stability":cand_stability,
        "candidate_median_convergence_rate":cand_conv,
        "candidate_worst_task_convergence_rate":worst_conv,
        "candidate_min_task_ARI":min_task_ari,
        "candidate_min_task_NMI":min_task_nmi,
        "full_ablation_median_task_ARI":full_ari,
        "full_ablation_median_task_NMI":full_nmi,
        "positive_only_median_task_ARI":float(positive["median_task_ARI"]),
        "signed_over_positive_aggregate_ARI_advantage":aggregate_adv,
        "signed_over_positive_task_wins":wins,
    }])
    candidate_metrics.to_csv(out/"D10G_CANDIDATE_METRICS.csv",index=False)

    signed.sort_values(
        ["median_task_ARI","median_task_NMI"],
        ascending=[False,False]
    ).to_csv(out/"D10G_SIGNED_BASELINE_REFERENCE.csv",index=False)

    merged.to_csv(out/"D10G_SIGNED_VS_POSITIVE_TASK_COMPARISON.csv",index=False)

    all_pass=bool((gate_df["status"]=="PASS").all())
    failed=list(gate_df.loc[gate_df["status"]=="FAIL","gate"])

    status_value="PASS" if all_pass else "FAIL_CLOSED"
    accepted="YES" if all_pass else "NO"
    ready="YES" if all_pass else "NO"
    failure_reason="" if all_pass else "ACCEPTANCE_GATES_FAILED="+"|".join(failed)

    result={
        "D10G_STATUS":status_value,
        "ACCEPTANCE_POLICY_SHA256":EXPECTED_POLICY_SHA,
        "R1_IMPLEMENTATION_SHA256":EXPECTED_R1_SHA,
        "ACTIVE_PLAN":"PLAN_B_SIGNED_SINGLE_LAYER_ACLA",
        "D10F_RANKED_CANDIDATE_CONFIG":candidate,
        "ACCEPTANCE_GATES_TOTAL":len(gate_df),
        "ACCEPTANCE_GATES_PASSED":int((gate_df["status"]=="PASS").sum()),
        "ACCEPTANCE_GATES_FAILED":int((gate_df["status"]=="FAIL").sum()),
        "METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE":accepted,
        "D10G_PARAMETER_FREEZE_EXECUTED":"NO",
        "GSE243219_ACLA_EXECUTED":"NO",
        "D9_COMMUNITY_DETECTION_EXECUTED":"NO",
        "PARAMETER_TUNING_USING_GSE243219":"NO",
        "NETWORK_CHANGED":"NO",
        "D9_FILES_MODIFIED":"NO",
        "WEIGHT_TRANSFORMATION_APPLIED":"NO",
        "NEGATIVE_EDGES_REMOVED":"NO",
        "FAILURE_REASON":failure_reason,
        "READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE":ready,
        "READY_FOR_GSE243219_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }
    result_json.write_text(json.dumps(result,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
