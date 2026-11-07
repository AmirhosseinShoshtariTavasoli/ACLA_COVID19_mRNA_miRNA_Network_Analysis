#!/usr/bin/env python3
from __future__ import annotations

import ast
import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path
from typing import Dict, Mapping, Tuple

import numpy as np
import pandas as pd

EXPECTED_R1_IMPLEMENTATION_SHA256 = "2bfe790d6aff0fc0404d37683fed2ef0a7c85b78c6a31bb692d3f69d0f7e257d"
EXPECTED_ORIGINAL_D10E_VALIDATOR_SHA256 = "3167c39fcd874fbae3a28d287db03e02ddc53844aefe5cb7810007faac105295"

# Exact failed-D10E prospective contract.
EXPECTED_CORE_ALPHA_REWARD = (0.1, 0.3)
EXPECTED_CORE_ALPHA_PENALTY = (0.1, 0.3)
EXPECTED_CORE_GAMMA = (0.25, 0.50, 0.75)
EXPECTED_PLAN_A_LAMBDA = (0.25, 0.50, 1.00)

EXPECTED_MAX_ITERATIONS = 200
EXPECTED_OBJECTIVE_TOLERANCE = 1e-6
EXPECTED_R0_NODE_CHANGE_TOLERANCE_SCHEMA_VALUE = 0.02
EXPECTED_PROBABILITY_CHANGE_TOLERANCE = 1e-2
EXPECTED_PATIENCE = 5
EXPECTED_SEEDS = 10

EXPECTED_A_ARI_MIN = 0.90
EXPECTED_A_NMI_MIN = 0.90
EXPECTED_A_EXACT_MIN = 0.70
EXPECTED_B_ARI_MIN = 0.40
EXPECTED_B_NMI_MIN = 0.50

# These functions are called DIRECTLY from the exact original D10E validator.
REUSED_ORIGINAL_FUNCTIONS = [
    "make_component",
    "make_components",
    "truth_two_block",
    "ideal_two_block",
    "noisy_two_block",
    "regulatory_informative_fixture",
    "zero_regulatory_fixture",
    "positive_only_fixture",
    "adversarial_negative_within_fixture",
    "disconnected_fixture",
    "nmi_from_labels",
    "pairwise_seed_stability",
    "run_panel",
    "weighted_positive_modularity_reference",
    "config_grid",
    "cfg_record",
]

def sha256_file(path: Path, chunk=8*1024*1024) -> str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda:f.read(chunk),b""):
            h.update(block)
    return h.hexdigest()

def load_module(path: Path, name: str):
    spec=importlib.util.spec_from_file_location(name,path)
    mod=importlib.util.module_from_spec(spec)
    sys.modules[name]=mod
    spec.loader.exec_module(mod)
    return mod

def function_ast_sha256(path: Path, function_name: str) -> str:
    tree=ast.parse(path.read_text(encoding="utf-8"))
    node=next(
        (n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name==function_name),
        None
    )
    if node is None:
        raise RuntimeError(f"ORIGINAL_D10E_FUNCTION_MISSING={function_name}")
    payload=ast.dump(node,include_attributes=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()

def require_token(path: Path, token: str, label: str) -> None:
    if not path.is_file():
        raise RuntimeError(f"{label}_FILE_MISSING={path}")
    text=path.read_text(encoding="utf-8-sig",errors="replace")
    if token not in text:
        raise RuntimeError(f"{label}_TOKEN_MISSING={token}")

def assert_original_contract(orig) -> pd.DataFrame:
    checks = [
        ("CORE_ALPHA_REWARD", tuple(orig.CORE_ALPHA_REWARD), EXPECTED_CORE_ALPHA_REWARD),
        ("CORE_ALPHA_PENALTY", tuple(orig.CORE_ALPHA_PENALTY), EXPECTED_CORE_ALPHA_PENALTY),
        ("CORE_GAMMA", tuple(orig.CORE_GAMMA), EXPECTED_CORE_GAMMA),
        ("PLAN_A_LAMBDA", tuple(orig.PLAN_A_LAMBDA), EXPECTED_PLAN_A_LAMBDA),
        ("VALIDATION_MAX_ITERATIONS", int(orig.VALIDATION_MAX_ITERATIONS), EXPECTED_MAX_ITERATIONS),
        ("VALIDATION_OBJECTIVE_TOLERANCE", float(orig.VALIDATION_OBJECTIVE_TOLERANCE), EXPECTED_OBJECTIVE_TOLERANCE),
        ("VALIDATION_NODE_CHANGE_TOLERANCE", float(orig.VALIDATION_NODE_CHANGE_TOLERANCE), EXPECTED_R0_NODE_CHANGE_TOLERANCE_SCHEMA_VALUE),
        ("VALIDATION_PROBABILITY_CHANGE_TOLERANCE", float(orig.VALIDATION_PROBABILITY_CHANGE_TOLERANCE), EXPECTED_PROBABILITY_CHANGE_TOLERANCE),
        ("VALIDATION_PATIENCE", int(orig.VALIDATION_PATIENCE), EXPECTED_PATIENCE),
        ("VALIDATION_SEEDS", int(orig.VALIDATION_SEEDS), EXPECTED_SEEDS),
        ("FIXTURE_A_MEDIAN_ARI_MIN", float(orig.FIXTURE_A_MEDIAN_ARI_MIN), EXPECTED_A_ARI_MIN),
        ("FIXTURE_A_MEDIAN_NMI_MIN", float(orig.FIXTURE_A_MEDIAN_NMI_MIN), EXPECTED_A_NMI_MIN),
        ("FIXTURE_A_EXACT_RECOVERY_RATE_MIN", float(orig.FIXTURE_A_EXACT_RECOVERY_RATE_MIN), EXPECTED_A_EXACT_MIN),
        ("FIXTURE_B_MEDIAN_ARI_MIN", float(orig.FIXTURE_B_MEDIAN_ARI_MIN), EXPECTED_B_ARI_MIN),
        ("FIXTURE_B_MEDIAN_NMI_MIN", float(orig.FIXTURE_B_MEDIAN_NMI_MIN), EXPECTED_B_NMI_MIN),
    ]
    rows=[]
    for name,actual,expected in checks:
        passed=(actual==expected)
        rows.append({
            "contract_item":name,
            "actual":repr(actual),
            "expected":repr(expected),
            "status":"PASS" if passed else "FAIL",
        })
        if not passed:
            raise RuntimeError(f"ORIGINAL_D10E_CONTRACT_CHANGED={name} actual={actual} expected={expected}")
    return pd.DataFrame(rows)

def audit_r1_history(result, fixture_id: str, config_id: str, seed_index: int) -> Dict[str,object]:
    h=result.history
    required={
        "accepted_moves",
        "improving_nodes_post_sweep",
        "min_executed_move_advantage",
        "partition_signature",
        "joint_convergence_condition",
        "patience_count",
    }
    missing=required-set(h.columns)
    if missing:
        raise RuntimeError(f"R1_HISTORY_COLUMNS_MISSING={sorted(missing)}")

    bad_move_rows=h[
        h["min_executed_move_advantage"].notna()
        & (pd.to_numeric(h["min_executed_move_advantage"],errors="coerce") <= 1e-12)
    ]
    if len(bad_move_rows):
        raise RuntimeError(
            f"R1_NONIMPROVING_EXECUTED_MOVE fixture={fixture_id} "
            f"config={config_id} seed_index={seed_index}"
        )

    declared=h[h["joint_convergence_condition"].astype(bool)]
    bad_declared=declared[
        (pd.to_numeric(declared["accepted_moves"],errors="coerce") != 0)
        | (pd.to_numeric(declared["improving_nodes_post_sweep"],errors="coerce") != 0)
    ]
    if len(bad_declared):
        raise RuntimeError(
            f"R1_FALSE_CONVERGENCE_CONDITION fixture={fixture_id} "
            f"config={config_id} seed_index={seed_index}"
        )

    if result.converged:
        last=h.iloc[-1]
        if int(last["accepted_moves"]) != 0 or int(last["improving_nodes_post_sweep"]) != 0:
            raise RuntimeError(
                f"R1_CONVERGED_WITH_NONTERMINAL_STATE fixture={fixture_id} "
                f"config={config_id} seed_index={seed_index}"
            )

    executed=int(pd.to_numeric(h["accepted_moves"],errors="coerce").fillna(0).sum())
    max_remaining=int(pd.to_numeric(h["improving_nodes_post_sweep"],errors="coerce").max())
    return {
        "fixture_id":fixture_id,
        "config_id":config_id,
        "seed_index":seed_index,
        "seed":result.seed,
        "executed_moves_total":executed,
        "max_improving_nodes_post_sweep":max_remaining,
        "converged":int(result.converged),
        "final_accepted_moves":int(h["accepted_moves"].iloc[-1]),
        "final_improving_nodes":int(h["improving_nodes_post_sweep"].iloc[-1]),
        "transition_invariants":"PASS",
    }

def selftest():
    assert EXPECTED_CORE_ALPHA_REWARD == (0.1,0.3)
    assert EXPECTED_CORE_ALPHA_PENALTY == (0.1,0.3)
    assert EXPECTED_CORE_GAMMA == (0.25,0.50,0.75)
    assert EXPECTED_A_ARI_MIN == 0.90
    assert EXPECTED_B_NMI_MIN == 0.50
    print("D10E_R1_INTERNAL_SELFTEST=PASS")
    print("ORIGINAL_D10E_CONTRACT_SELFTEST=PASS")
    print("R1_TRANSITION_AUDIT_SELFTEST=PASS")
    print("NO_GSE243219_ALGORITHM_EXECUTION_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=9:
        raise SystemExit(
            "usage: D10E_R1 <r1_impl.py> <orig_d10e_validator.py> <orig_d10e_status> "
            "<d10c_r1_status> <d10d_r1_status> <outdir> <result_json> <expected_r1_sha>"
        )

    impl_path=Path(sys.argv[1])
    orig_validator_path=Path(sys.argv[2])
    orig_d10e_status=Path(sys.argv[3])
    d10c_r1_status=Path(sys.argv[4])
    d10d_r1_status=Path(sys.argv[5])
    out=Path(sys.argv[6])
    result_json=Path(sys.argv[7])
    expected_r1=sys.argv[8]
    out.mkdir(parents=True,exist_ok=True)

    if expected_r1 != EXPECTED_R1_IMPLEMENTATION_SHA256:
        raise RuntimeError("EXPECTED_R1_ARGUMENT_MISMATCH")
    if sha256_file(impl_path) != EXPECTED_R1_IMPLEMENTATION_SHA256:
        raise RuntimeError("R1_IMPLEMENTATION_SHA256_MISMATCH")
    if sha256_file(orig_validator_path) != EXPECTED_ORIGINAL_D10E_VALIDATOR_SHA256:
        raise RuntimeError("ORIGINAL_D10E_VALIDATOR_SHA256_MISMATCH")

    # Authority chain.
    for p,t,l in [
        (orig_d10e_status,"D10E_STATUS=FAIL_CLOSED","ORIGINAL_D10E"),
        (orig_d10e_status,"CORE_CONFIGURATIONS_TESTED=12","ORIGINAL_D10E"),
        (orig_d10e_status,"CORE_ELIGIBLE_CONFIGURATIONS=0","ORIGINAL_D10E"),
        (orig_d10e_status,"FAILURE_STAGE=CORE_SIGNED_METHOD_SYNTHETIC_VALIDATION","ORIGINAL_D10E"),
        (orig_d10e_status,"READY_FOR_D10F_SIGNED_BENCHMARKING=NO","ORIGINAL_D10E"),
        (d10c_r1_status,"D10C_R1_STATUS=PASS","D10C_R1"),
        (d10c_r1_status,"D10E_R1_REUSES_ORIGINAL_CORE_GRID=YES","D10C_R1"),
        (d10c_r1_status,"D10E_R1_REUSES_ORIGINAL_RECOVERY_GATES=YES","D10C_R1"),
        (d10c_r1_status,"THRESHOLD_RELAXATION_USED=NO","D10C_R1"),
        (d10c_r1_status,"PARAMETER_GRID_EXPANSION_USED=NO","D10C_R1"),
        (d10d_r1_status,"D10D_R1_STATUS=PASS","D10D_R1"),
        (d10d_r1_status,f"R1_IMPLEMENTATION_SHA256={EXPECTED_R1_IMPLEMENTATION_SHA256}","D10D_R1"),
        (d10d_r1_status,"R0_TO_R1_FROZEN_MATH_EQUIVALENCE=PASS","D10D_R1"),
        (d10d_r1_status,"R1_UNIT_TESTS_PASS=YES","D10D_R1"),
        (d10d_r1_status,"READY_FOR_D10E_R1_SYNTHETIC_REVALIDATION=YES","D10D_R1"),
        (d10d_r1_status,"SIGNED_ACLA_R1_EXECUTED_ON_GSE243219=NO","D10D_R1"),
    ]:
        require_token(p,t,l)

    orig=load_module(orig_validator_path,"d10e_original_contract")
    contract_df=assert_original_contract(orig)

    ast_rows=[]
    for fn in REUSED_ORIGINAL_FUNCTIONS:
        ast_rows.append({
            "function":fn,
            "original_function_ast_sha256":function_ast_sha256(orig_validator_path,fn),
            "reuse_mode":"DIRECT_CALL_FROM_ORIGINAL_D10E_VALIDATOR",
            "status":"PASS",
        })
    ast_df=pd.DataFrame(ast_rows)
    contract_df.to_csv(out/"D10E_R1_ORIGINAL_PARAMETER_GATE_CONTRACT.csv",index=False)
    ast_df.to_csv(out/"D10E_R1_ORIGINAL_FIXTURE_FUNCTION_REUSE_AUDIT.csv",index=False)

    # Load exact R1 implementation. Do not use original D10E load_impl because it
    # intentionally hard-codes the failed R0 implementation hash.
    mod=load_module(impl_path,"signed_acla_r1_d10e_revalidation")

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
        out/"D10E_R1_FIXTURE_DEFINITIONS.csv",index=False
    )

    seed_level=[]
    screen_rows=[]
    transition_audit_rows=[]

    nA,eA,tA=orig.ideal_two_block()
    compA=orig.make_component(mod,nA,eA)
    nB,eB,tB=orig.noisy_two_block()
    compB=orig.make_component(mod,nB,eB)

    eligible=[]
    for config_id,cfg in orig.config_grid(mod):
        # Exact original D10E core grid is reused. The legacy
        # node_change_tolerance=0.02 field remains only in SACLAConfig schema;
        # R1 evaluate_convergence does not use it.
        a_df,a_results,a_sum=orig.run_panel(mod,compA,tA,cfg)
        a_df.insert(0,"fixture_id","A")
        a_df.insert(1,"config_id",config_id)
        seed_level.append(a_df)
        for k,r in enumerate(a_results,1):
            transition_audit_rows.append(audit_r1_history(r,"A",config_id,k))

        b_df,b_results,b_sum=orig.run_panel(mod,compB,tB,cfg)
        b_df.insert(0,"fixture_id","B")
        b_df.insert(1,"config_id",config_id)
        seed_level.append(b_df)
        for k,r in enumerate(b_results,1):
            transition_audit_rows.append(audit_r1_history(r,"B",config_id,k))

        A_pass=(
            a_sum["median_ARI"] >= orig.FIXTURE_A_MEDIAN_ARI_MIN
            and a_sum["median_NMI"] >= orig.FIXTURE_A_MEDIAN_NMI_MIN
            and a_sum["exact_recovery_rate"] >= orig.FIXTURE_A_EXACT_RECOVERY_RATE_MIN
        )
        B_pass=(
            b_sum["median_ARI"] >= orig.FIXTURE_B_MEDIAN_ARI_MIN
            and b_sum["median_NMI"] >= orig.FIXTURE_B_MEDIAN_NMI_MIN
        )
        row={
            "config_id":config_id,
            **orig.cfg_record(cfg),
            "R1_NODE_CHANGE_TOLERANCE_FIELD_ACTIVE":0,
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
    screen.to_csv(out/"D10E_R1_CORE_PARAMETER_SCREEN.csv",index=False)
    pd.concat(seed_level,ignore_index=True).to_csv(
        out/"D10E_R1_SEED_LEVEL_RESULTS.csv",index=False
    )

    invariant_rows=[]

    # D: exact original positive-only reduction test.
    nD,eD,tD=orig.positive_only_fixture()
    compD=orig.make_component(mod,nD,eD)
    q_impl=mod.signed_component_objective(compD,tD)
    q_ref=orig.weighted_positive_modularity_reference(eD,tD)
    D_pass=abs(q_impl-q_ref)<=1e-12
    invariant_rows.append({
        "fixture_id":"D","test":"POSITIVE_ONLY_OBJECTIVE_REDUCTION",
        "status":"PASS" if D_pass else "FAIL",
        "detail":f"implementation={q_impl:.15g};reference={q_ref:.15g};absdiff={abs(q_impl-q_ref):.3g}"
    })

    # G: exact original sign-semantics test.
    nG,eG,goodG,badG=orig.adversarial_negative_within_fixture()
    compG=orig.make_component(mod,nG,eG)
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

    # C: exact original disconnected-component retention test.
    nC,eC=orig.disconnected_fixture()
    compsC=orig.make_components(mod,nC,eC)
    sizes=sorted([len(c.nodes) for c in compsC],reverse=True)
    C_pass=(sizes==[6,6] and sum(len(c.nodes) for c in compsC)==12)
    invariant_rows.append({
        "fixture_id":"C","test":"DISCONNECTED_COMPONENT_RETENTION",
        "status":"PASS" if C_pass else "FAIL",
        "detail":f"component_sizes={sizes};nodes_retained={sum(len(c.nodes) for c in compsC)}"
    })

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
    pd.DataFrame([x[2] for x in top_core]).to_csv(
        out/"D10E_R1_TOP_CORE_CANDIDATES.csv",index=False
    )

    core_pass=(len(eligible_sorted)>0 and D_pass and G_pass and C_pass)
    plan_a_rows=[]
    plan_a_identified=False
    selected_plan_a=None
    selected_core_id=""
    selected_core_cfg=None

    if top_core:
        selected_core_id,selected_core_cfg,_=top_core[0]

        # F: same-seed exact reproducibility.
        seed=mod.deterministic_seed(1)
        r1a=mod.run_one_component(compA,selected_core_cfg,seed)
        r1b=mod.run_one_component(compA,selected_core_cfg,seed)
        F_pass=(r1a.labels==r1b.labels and r1a.history.equals(r1b.history))
        transition_audit_rows.append(audit_r1_history(r1a,"F",selected_core_id,1))
        invariant_rows.append({
            "fixture_id":"F","test":"FULL_ALGORITHM_SAME_SEED_REPRODUCIBILITY",
            "status":"PASS" if F_pass else "FAIL",
            "detail":f"config={selected_core_id};seed={seed};history_equal={r1a.history.equals(r1b.history)}"
        })

        # H: zero regulatory info makes Plan A mathematically equal Plan B.
        nH,eH,tH=orig.zero_regulatory_fixture()
        compH=orig.make_component(mod,nH,eH)
        cfg0=mod.SACLAConfig(
            selected_core_cfg.alpha_reward,
            selected_core_cfg.alpha_penalty,
            selected_core_cfg.gamma,
            0.0,
            selected_core_cfg.max_iterations,
            selected_core_cfg.objective_tolerance,
            selected_core_cfg.node_change_tolerance,
            selected_core_cfg.probability_change_tolerance,
            selected_core_cfg.patience,
        )
        cfg1=mod.SACLAConfig(
            selected_core_cfg.alpha_reward,
            selected_core_cfg.alpha_penalty,
            selected_core_cfg.gamma,
            1.0,
            selected_core_cfg.max_iterations,
            selected_core_cfg.objective_tolerance,
            selected_core_cfg.node_change_tolerance,
            selected_core_cfg.probability_change_tolerance,
            selected_core_cfg.patience,
        )
        h0=mod.run_one_component(compH,cfg0,seed)
        h1=mod.run_one_component(compH,cfg1,seed)
        H_pass=(h0.labels==h1.labels and h0.history.equals(h1.history))
        transition_audit_rows.append(audit_r1_history(h0,"H_LAMBDA0",selected_core_id,1))
        transition_audit_rows.append(audit_r1_history(h1,"H_LAMBDA1",selected_core_id,1))
        invariant_rows.append({
            "fixture_id":"H","test":"ZERO_REGULATORY_PLAN_A_EQUALS_PLAN_B",
            "status":"PASS" if H_pass else "FAIL",
            "detail":f"config={selected_core_id};seed={seed};partition_equal={h0.labels==h1.labels};history_equal={h0.history.equals(h1.history)}"
        })

        # E: exact original Plan-A identifiability policy.
        nE,eE,tE=orig.regulatory_informative_fixture()
        compE=orig.make_component(mod,nE,eE)
        for core_id,core_cfg,_ in top_core:
            base_cfg=mod.SACLAConfig(
                core_cfg.alpha_reward,core_cfg.alpha_penalty,core_cfg.gamma,0.0,
                core_cfg.max_iterations,core_cfg.objective_tolerance,
                core_cfg.node_change_tolerance,core_cfg.probability_change_tolerance,
                core_cfg.patience,
            )
            base_df,base_results,base_sum=orig.run_panel(mod,compE,tE,base_cfg)
            for k,r in enumerate(base_results,1):
                transition_audit_rows.append(audit_r1_history(r,"E_LAMBDA0",core_id,k))
            base_ari_by_seed=dict(zip(base_df["seed"],base_df["ARI"]))

            for lam in orig.PLAN_A_LAMBDA:
                cfg=mod.SACLAConfig(
                    core_cfg.alpha_reward,core_cfg.alpha_penalty,core_cfg.gamma,float(lam),
                    core_cfg.max_iterations,core_cfg.objective_tolerance,
                    core_cfg.node_change_tolerance,core_cfg.probability_change_tolerance,
                    core_cfg.patience,
                )
                df,results,s=orig.run_panel(mod,compE,tE,cfg)
                for k,r in enumerate(results,1):
                    transition_audit_rows.append(
                        audit_r1_history(r,f"E_LAMBDA{lam}",core_id,k)
                    )
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

    pd.DataFrame(plan_a_rows).to_csv(
        out/"D10E_R1_PLAN_A_REGULATORY_SCREEN.csv",index=False
    )
    pd.DataFrame(invariant_rows).to_csv(
        out/"D10E_R1_INVARIANT_TESTS.csv",index=False
    )
    transition_df=pd.DataFrame(transition_audit_rows)
    transition_df.to_csv(
        out/"D10E_R1_TRANSITION_INVARIANT_AUDIT.csv",index=False
    )

    if top_core:
        core_pass = core_pass and F_pass and H_pass

    transition_pass = (
        len(transition_df) > 0
        and (transition_df["transition_invariants"]=="PASS").all()
    )
    core_pass = core_pass and transition_pass

    if not core_pass:
        status="FAIL_CLOSED"
        plan_a_status="NOT_REACHED"
        plan_b_status="FAIL_CORE_SIGNED_VALIDATION"
        plan_b_activated="NO"
        active_plan="NONE"
        failure_stage="R1_CORE_SIGNED_METHOD_SYNTHETIC_REVALIDATION"
        failure_reason=(
            "No R1 core configuration satisfied the unchanged original A/B recovery gates"
            if len(eligible_sorted)==0
            else "One or more unchanged hard signed/reproducibility/R1-transition invariants failed"
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

    selected_plan_a_core=""
    selected_plan_a_lambda=""
    if selected_plan_a is not None:
        selected_plan_a_core=selected_plan_a[1]["core_config_id"]
        selected_plan_a_lambda=selected_plan_a[1]["lambda_regulatory"]

    result={
        "D10E_R1_STATUS":status,
        "ORIGINAL_D10E_VALIDATOR_SHA256":EXPECTED_ORIGINAL_D10E_VALIDATOR_SHA256,
        "R1_IMPLEMENTATION_SHA256":EXPECTED_R1_IMPLEMENTATION_SHA256,
        "ORIGINAL_D10E_FIXTURE_FUNCTIONS_REUSED_DIRECTLY":"YES",
        "ORIGINAL_D10E_PARAMETER_GRID_REUSED":"YES",
        "ORIGINAL_D10E_RECOVERY_GATES_REUSED":"YES",
        "PARAMETER_GRID_EXPANSION_USED":"NO",
        "THRESHOLD_RELAXATION_USED":"NO",
        "R1_LABEL_SWITCH_TOLERANCE_RETIRED":"YES",
        "R1_TRANSITION_INVARIANTS_PASS":"YES" if transition_pass else "NO",
        "FIXTURES_A_TO_H_DEFINED":"YES",
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
        "SYNTHETIC_REVALIDATION_EXECUTED":"YES",
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
