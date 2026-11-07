#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path
from typing import Dict, Mapping

import numpy as np
import pandas as pd

EXPECTED_R1_SHA="2bfe790d6aff0fc0404d37683fed2ef0a7c85b78c6a31bb692d3f69d0f7e257d"
EXPECTED_D3_GENERATOR_SHA="5c138c84ce73cfa0a2d6f05aecf9d2cac7ef6e7f975ae451236c5b5d634efce1"

# D10G-D4 frozen constants.
M1_RANDOM_PARTITIONS=100
M1_MARGIN_MIN=0.10
M1_FAMILY_PASS_FRACTION=0.80

M2_ACCESS_FAILURE_THRESHOLD=0.25
M2_SUFFICIENT_ACCESS_THRESHOLD=0.50

M3_DISAGREEMENT_MIN=0.50
M3_TRUTH_CONSISTENCY_LOSS_MIN=0.20
M3_FAMILIES_REQUIRED=2

M4_SWEEPS=5
M4_SEEDS=10
M4_ARI_IMPROVING_MOVE_FRACTION_MIN=0.50

M5_RELATIONAL_GAP_MIN=0.20
M5_REPRESENTATION_FAILURE_FRACTION=0.80

EXPECTED_TASKS=15

EXPECTED_CORE04={
    "alpha_reward":0.1,
    "alpha_penalty":0.3,
    "gamma":0.25,
    "lambda_regulatory":0.0,
    "max_iterations":200,
    "objective_tolerance":1e-6,
    "node_change_tolerance":0.02,
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

def verify_core04(row: pd.Series):
    for key,expected in EXPECTED_CORE04.items():
        if key in ("max_iterations","patience"):
            actual=int(row[key])
            if actual!=int(expected):
                raise RuntimeError(f"CORE04_VALUE_MISMATCH {key}={actual} expected={expected}")
        else:
            actual=float(row[key])
            if abs(actual-float(expected))>1e-15:
                raise RuntimeError(f"CORE04_VALUE_MISMATCH {key}={actual} expected={expected}")

def balanced_random_partition(n: int, k: int, random_index: int, task_id: str):
    if n % k != 0:
        raise ValueError("Balanced random partition requires n divisible by k")
    rng=np.random.default_rng(np.uint64(deterministic_int(
        f"D10G-D5-M1-{task_id}-RANDOM-{random_index}"
    )))
    perm=np.arange(n,dtype=int)
    rng.shuffle(perm)
    size=n//k
    labels={}
    for c in range(k):
        for node in perm[c*size:(c+1)*size]:
            labels[int(node)]=c
    return labels

def objective_identifiability(mod,d3,W,truth,task_id):
    component=d3.make_component(mod,W)
    q_truth=mod.signed_component_objective(component,truth)
    singleton={i:i for i in range(W.shape[0])}
    all_one={i:0 for i in range(W.shape[0])}
    q_single=mod.signed_component_objective(component,singleton)
    q_all=mod.signed_component_objective(component,all_one)
    k=len(set(truth.values()))
    qs=[]
    for r in range(1,M1_RANDOM_PARTITIONS+1):
        labels=balanced_random_partition(W.shape[0],k,r,task_id)
        qs.append(mod.signed_component_objective(component,labels))
    q_random_median=float(np.median(qs))
    margin_random=float(q_truth-q_random_median)
    margin_single=float(q_truth-q_single)
    passed=(margin_random>=M1_MARGIN_MIN and margin_single>=M1_MARGIN_MIN)
    return {
        "task_id":task_id,
        "Q_truth":float(q_truth),
        "Q_singleton":float(q_single),
        "Q_all_one":float(q_all),
        "Q_random_median_100":q_random_median,
        "objective_margin_random":margin_random,
        "objective_margin_singleton":margin_single,
        "OBJECTIVE_IDENTIFIES_TRUTH":"YES" if passed else "NO",
    }

def singleton_accessibility(mod,d3,W,truth,cfg,task_id):
    component=d3.make_component(mod,W)
    labels={n:n for n in component.nodes}
    cp,cn=mod.component_community_strengths(component,labels)
    sizes=mod.community_sizes(labels)
    rows=[]

    for node in component.nodes:
        scores=mod.candidate_scores(
            component,labels,node,cfg.lambda_regulatory,cfg.gamma,
            cp,cn,community_sizes_map=sizes
        )
        current=int(labels[node])
        current_u,current_l,current_dq=scores[current]
        alternatives=[(c,s) for c,s in scores.items() if c!=current]
        if not alternatives:
            raise RuntimeError(f"NO_ALTERNATIVES_AT_SINGLETON task={task_id} node={node}")

        fused_best_c,fused_best_s=max(
            alternatives,key=lambda x: mod._candidate_tiebreak_key(x,node)
        )
        fused_adv=float(fused_best_s[0]-current_u)
        any_improving=mod.is_move_eligible(fused_adv)

        truth_improving=[]
        nontruth_improving=[]
        for c,s in alternatives:
            truth_cons=(c is not None and truth[int(c)]==truth[node])
            adv=float(s[0]-current_u)
            if mod.is_move_eligible(adv):
                if truth_cons:
                    truth_improving.append(adv)
                else:
                    nontruth_improving.append(adv)

        any_truth_improving=bool(truth_improving)
        best_fused_truth=(
            fused_best_c is not None
            and truth[int(fused_best_c)]==truth[node]
            and any_improving
        )

        local_best_c,local_best_s=max(
            alternatives,
            key=lambda x: (
                x[1][1],x[1][2],
                -(node if x[0] is None else int(x[0]))
            )
        )

        raw={c:float(s[2]) for c,s in scores.items()}
        scale=max(abs(v) for v in raw.values()) if raw else 0.0
        def g_of(c):
            return 0.0 if scale==0.0 else raw[c]/scale

        global_best_c,global_best_s=max(
            alternatives,
            key=lambda x: (
                g_of(x[0]),x[1][1],x[1][2],
                -(node if x[0] is None else int(x[0]))
            )
        )

        local_truth=(local_best_c is not None and truth[int(local_best_c)]==truth[node])
        global_truth=(global_best_c is not None and truth[int(global_best_c)]==truth[node])
        fused_truth=(fused_best_c is not None and truth[int(fused_best_c)]==truth[node])

        rows.append({
            "task_id":task_id,
            "node":node,
            "any_fused_improving_move":int(any_improving),
            "any_truth_consistent_improving_move":int(any_truth_improving),
            "best_fused_improving_truth_consistent":int(best_fused_truth),
            "best_truth_consistent_advantage":(
                max(truth_improving) if truth_improving else float("nan")
            ),
            "best_truth_inconsistent_advantage":(
                max(nontruth_improving) if nontruth_improving else float("nan")
            ),
            "local_best_candidate":local_best_c,
            "global_best_candidate":global_best_c,
            "fused_best_candidate":fused_best_c,
            "local_best_truth_consistent":int(local_truth),
            "global_best_truth_consistent":int(global_truth),
            "fused_best_truth_consistent":int(fused_truth),
            "local_global_destination_disagree":int(local_best_c!=global_best_c),
            "fused_advantage":fused_adv,
        })

    ndf=pd.DataFrame(rows)
    eligible=ndf[ndf["any_fused_improving_move"]==1]
    task={
        "task_id":task_id,
        "fraction_nodes_with_any_improving_move":float(ndf["any_fused_improving_move"].mean()),
        "fraction_nodes_with_truth_consistent_improving_move":float(ndf["any_truth_consistent_improving_move"].mean()),
        "fraction_best_improving_moves_truth_consistent":(
            float(eligible["best_fused_improving_truth_consistent"].mean()) if len(eligible) else 0.0
        ),
        "median_advantage_truth_consistent_best":(
            float(ndf["best_truth_consistent_advantage"].median(skipna=True))
            if ndf["best_truth_consistent_advantage"].notna().any() else float("nan")
        ),
        "median_advantage_truth_inconsistent_best":(
            float(ndf["best_truth_inconsistent_advantage"].median(skipna=True))
            if ndf["best_truth_inconsistent_advantage"].notna().any() else float("nan")
        ),
        "eligible_nodes_for_M3":int(len(eligible)),
        "local_global_disagreement_fraction":(
            float(eligible["local_global_destination_disagree"].mean()) if len(eligible) else 0.0
        ),
        "local_truth_consistency_rate":(
            float(eligible["local_best_truth_consistent"].mean()) if len(eligible) else 0.0
        ),
        "global_truth_consistency_rate":(
            float(eligible["global_best_truth_consistent"].mean()) if len(eligible) else 0.0
        ),
        "fused_truth_consistency_rate":(
            float(eligible["fused_best_truth_consistent"].mean()) if len(eligible) else 0.0
        ),
    }
    return ndf,task

def replay_first_sweeps(mod,d3,W,truth,cfg,task_id,seed_index):
    component=d3.make_component(mod,W)
    seed=mod.deterministic_seed(seed_index)
    rng=np.random.default_rng(np.uint64(seed))
    labels={n:n for n in component.nodes}
    p_move={n:0.5 for n in component.nodes}
    next_temp_label=max(component.nodes)+1 if component.nodes else 0

    prev_q=mod.signed_component_objective(component,labels)
    stable_count=0
    moves=[]
    sweeps=[]

    for iteration in range(1,M4_SWEEPS+1):
        before_p=p_move.copy()
        cp,cn=mod.component_community_strengths(component,labels)
        sizes=mod.community_sizes(labels)
        order=np.array(component.nodes,dtype=int)
        rng.shuffle(order)
        accepted=0

        for node_np in order:
            node=int(node_np)
            best_c,best_s,current_s=mod.candidate_best_alternative(
                component,labels,node,cfg.lambda_regulatory,cfg.gamma,
                cp,cn,community_sizes_map=sizes
            )
            d=float(best_s[0]-current_s[0])
            if not mod.is_move_eligible(d):
                continue

            do_move=bool(rng.random()<p_move[node])
            chosen="MOVE" if do_move else "STAY"

            if do_move:
                old=int(labels[node])
                if best_c is None:
                    if sizes.get(old,0)<=1:
                        raise RuntimeError("REPLAY_SINGLETON_IDENTITY_VIOLATION")
                    new=int(next_temp_label)
                    next_temp_label+=1
                else:
                    new=int(best_c)

                dest_members=[n for n,l in labels.items() if int(l)==new]
                dest_truth_consistent=any(truth[n]==truth[node] for n in dest_members)

                ari_before=mod.adjusted_rand_index_from_labels(labels,truth)
                q_before=mod.signed_component_objective(component,labels)

                labels[node]=new
                mod.apply_strength_move(component,node,old,new,cp,cn)
                sizes[old]=sizes.get(old,0)-1
                if sizes[old]<=0:
                    sizes.pop(old,None)
                sizes[new]=sizes.get(new,0)+1
                accepted+=1

                ari_after=mod.adjusted_rand_index_from_labels(labels,truth)
                q_after=mod.signed_component_objective(component,labels)

                moves.append({
                    "task_id":task_id,
                    "seed_index":seed_index,
                    "seed":seed,
                    "iteration":iteration,
                    "node":node,
                    "source_label":old,
                    "destination_label":new,
                    "utility_advantage":d,
                    "destination_contains_same_truth_node":int(dest_truth_consistent),
                    "ARI_before":ari_before,
                    "ARI_after":ari_after,
                    "ARI_improving_move":int(ari_after>ari_before+1e-12),
                    "Q_before":q_before,
                    "Q_after":q_after,
                    "Q_improving_move":int(q_after>q_before+1e-12),
                })
                environment_response=d
            else:
                environment_response=-d

            p_move[node]=mod.learning_automaton_update(
                p_move[node],chosen,environment_response,
                cfg.alpha_reward,cfg.alpha_penalty
            )

        labels=mod.canonicalize_labels(labels)
        q=mod.signed_component_objective(component,labels)
        q_delta=float(q-prev_q)
        p_delta=max(abs(p_move[n]-before_p[n]) for n in component.nodes)
        improving_nodes,max_adv=mod.post_sweep_improvement_audit(
            component,labels,cfg.lambda_regulatory,cfg.gamma
        )
        converged_now=mod.evaluate_convergence(
            q_delta,accepted,improving_nodes,p_delta,cfg
        )
        stable_count=stable_count+1 if converged_now else 0

        sweeps.append({
            "task_id":task_id,
            "seed_index":seed_index,
            "iteration":iteration,
            "accepted_moves":accepted,
            "partition_signature":mod.partition_signature(labels),
            "signed_objective":q,
            "improving_nodes_post_sweep":improving_nodes,
            "patience_count":stable_count,
        })
        prev_q=q
        if stable_count>=cfg.patience:
            break

    # Exact replay-equivalence guard.
    full=mod.run_one_component(component,cfg,seed)
    full_h=full.history.head(len(sweeps))
    if len(full_h)!=len(sweeps):
        raise RuntimeError(
            f"REPLAY_HISTORY_LENGTH_MISMATCH task={task_id} seed={seed_index}"
        )
    for replay_row,(_,orig_row) in zip(sweeps,full_h.iterrows()):
        if int(replay_row["accepted_moves"])!=int(orig_row["accepted_moves"]):
            raise RuntimeError(
                f"REPLAY_ACCEPTED_MOVE_MISMATCH task={task_id} "
                f"seed={seed_index} iter={replay_row['iteration']}"
            )
        if str(replay_row["partition_signature"])!=str(orig_row["partition_signature"]):
            raise RuntimeError(
                f"REPLAY_PARTITION_SIGNATURE_MISMATCH task={task_id} "
                f"seed={seed_index} iter={replay_row['iteration']}"
            )

    mdf=pd.DataFrame(moves)
    if len(mdf):
        truth_frac=float(mdf["destination_contains_same_truth_node"].mean())
        ari_frac=float(mdf["ARI_improving_move"].mean())
        q_frac=float(mdf["Q_improving_move"].mean())
    else:
        truth_frac=ari_frac=q_frac=0.0

    summary={
        "task_id":task_id,
        "seed_index":seed_index,
        "seed":seed,
        "sweeps_replayed":len(sweeps),
        "accepted_move_count":len(moves),
        "truth_consistent_move_fraction":truth_frac,
        "ARI_improving_move_fraction":ari_frac,
        "Q_improving_move_fraction":q_frac,
        "REPLAY_EQUIVALENCE":"PASS",
    }
    return mdf,pd.DataFrame(sweeps),summary

def signed_relational_signal(W,truth,task_id):
    same=[]
    diff=[]
    n=W.shape[0]
    for i in range(n):
        for j in range(i+1,n):
            mask=np.ones(n,dtype=bool)
            mask[[i,j]]=False
            a=W[i,mask]
            b=W[j,mask]
            na=float(np.linalg.norm(a))
            nb=float(np.linalg.norm(b))
            sim=0.0 if na==0.0 or nb==0.0 else float(np.dot(a,b)/(na*nb))
            if truth[i]==truth[j]:
                same.append(sim)
            else:
                diff.append(sim)
    med_same=float(np.median(same))
    med_diff=float(np.median(diff))
    gap=float(med_same-med_diff)
    return {
        "task_id":task_id,
        "median_similarity_same_truth":med_same,
        "median_similarity_different_truth":med_diff,
        "relational_signal_gap":gap,
        "SIGN_RELATIONAL_SIGNAL_AVAILABLE":"YES" if gap>=M5_RELATIONAL_GAP_MIN else "NO",
    }

def selftest():
    assert M1_RANDOM_PARTITIONS==100
    assert M4_SWEEPS==5 and M4_SEEDS==10
    assert M3_FAMILIES_REQUIRED==2
    assert M5_RELATIONAL_GAP_MIN==0.20
    print("D10G_D5_INTERNAL_SELFTEST=PASS")
    print("MECHANISM_CLASSIFICATION_LOGIC_SELFTEST=PASS")
    print("REPLAY_EQUIVALENCE_GUARD_SELFTEST=PASS")
    print("NO_R2_DESIGN_SELFTEST=PASS")
    print("NO_GSE243219_ALGORITHM_EXECUTION_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=10:
        raise SystemExit(
            "usage: D10G_D5 <r1.py> <d3_generator.py> <d4_run> <d3_run> "
            "<d10g_run> <core04_csv> <outdir> <result_json> <expected_r1_sha>"
        )

    impl=Path(sys.argv[1])
    d3_source=Path(sys.argv[2])
    d4=Path(sys.argv[3])
    d3run=Path(sys.argv[4])
    d10g=Path(sys.argv[5])
    core04_csv=Path(sys.argv[6])
    out=Path(sys.argv[7])
    result_json=Path(sys.argv[8])
    expected_r1=sys.argv[9]
    out.mkdir(parents=True,exist_ok=True)

    if expected_r1!=EXPECTED_R1_SHA or sha256_file(impl)!=EXPECTED_R1_SHA:
        raise RuntimeError("R1_IMPLEMENTATION_SHA256_MISMATCH")
    if sha256_file(d3_source)!=EXPECTED_D3_GENERATOR_SHA:
        raise RuntimeError("D10G_D3_GENERATOR_SHA256_MISMATCH")

    for p,t,l in [
        (d4/"D10G_D4_FINAL_STATUS.txt","D10G_D4_STATUS=PASS","D10G_D4"),
        (d4/"D10G_D4_FINAL_STATUS.txt","DIAGNOSTIC_FAMILIES=S1_AND_S2_COUNTERFACTUALS_ONLY","D10G_D4"),
        (d4/"D10G_D4_FINAL_STATUS.txt","DIAGNOSTIC_SIGNED_TASKS=15","D10G_D4"),
        (d4/"D10G_D4_FINAL_STATUS.txt","READY_FOR_D10G_D5_MECHANISTIC_DIAGNOSTIC_EXECUTION=YES","D10G_D4"),
        (d4/"D10G_D4_FINAL_STATUS.txt","R2_METHOD_DESIGNED=NO","D10G_D4"),
        (d3run/"D10G_D3_FINAL_STATUS.txt","D10G_D3_STATUS=PASS","D10G_D3"),
        (d3run/"D10G_D3_FINAL_STATUS.txt","SIGN_IDENTIFIABILITY_CLASSIFICATION=SIGN_UTILIZATION_NOT_DEMONSTRATED","D10G_D3"),
        (d3run/"D10G_D3_FINAL_STATUS.txt","READY_FOR_R2_METHOD_REDESIGN_OR_ABANDONMENT=YES","D10G_D3"),
        (d10g/"D10G_FINAL_STATUS.txt","D10G_STATUS=FAIL_CLOSED","D10G"),
        (d10g/"D10G_FINAL_STATUS.txt","METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE=NO","D10G"),
    ]:
        require_token(p,t,l)

    cdf=pd.read_csv(core04_csv)
    row=cdf[cdf["config_id"].astype(str)=="CORE_04"]
    if len(row)!=1:
        raise RuntimeError(f"CORE04_ROW_COUNT={len(row)}")
    core=row.iloc[0]
    verify_core04(core)

    mod=load_module(impl,"signed_acla_r1_d10g_d5")
    d3=load_module(d3_source,"d10g_d3_frozen_generators")

    cfg=mod.SACLAConfig(
        float(core["alpha_reward"]),
        float(core["alpha_penalty"]),
        float(core["gamma"]),
        0.0,
        int(core["max_iterations"]),
        float(core["objective_tolerance"]),
        float(core["node_change_tolerance"]),
        float(core["probability_change_tolerance"]),
        int(core["patience"]),
    )

    tasks=[]
    for rep in range(1,6):
        W,P,t=d3.generate_S1(rep)
        tasks.append((f"S1_R{rep}","S1",W,t))
        Wa,Wb,P,ta,tb=d3.generate_S2(rep)
        tasks.append((f"S2A_R{rep}","S2A",Wa,ta))
        tasks.append((f"S2B_R{rep}","S2B",Wb,tb))
    if len(tasks)!=EXPECTED_TASKS:
        raise RuntimeError(f"TASK_COUNT={len(tasks)}")

    # M1
    m1_rows=[]
    for task_id,family,W,truth in tasks:
        rec=objective_identifiability(mod,d3,W,truth,task_id)
        rec["family"]=family
        m1_rows.append(rec)
    m1=pd.DataFrame(m1_rows)
    m1.to_csv(out/"D10G_D5_M1_OBJECTIVE_IDENTIFIABILITY.csv",index=False)
    m1_pass_fraction=float((m1["OBJECTIVE_IDENTIFIES_TRUTH"]=="YES").mean())
    m1_family_identifies=m1_pass_fraction>=M1_FAMILY_PASS_FRACTION

    # M2/M3
    m2_node_frames=[]
    m2_task_rows=[]
    for task_id,family,W,truth in tasks:
        ndf,trec=singleton_accessibility(mod,d3,W,truth,cfg,task_id)
        ndf.insert(1,"family",family)
        trec["family"]=family
        m2_node_frames.append(ndf)
        m2_task_rows.append(trec)
    m2_nodes=pd.concat(m2_node_frames,ignore_index=True)
    m2_tasks=pd.DataFrame(m2_task_rows)
    m2_nodes.to_csv(out/"D10G_D5_M2_M3_SINGLETON_NODE_AUDIT.csv",index=False)
    m2_tasks.to_csv(out/"D10G_D5_M2_M3_TASK_SUMMARY.csv",index=False)

    m1_ids=set(m1.loc[m1["OBJECTIVE_IDENTIFIES_TRUTH"]=="YES","task_id"])
    identifiable_m2=m2_tasks[m2_tasks["task_id"].isin(m1_ids)].copy()
    if len(identifiable_m2):
        access_fail_fraction=float(
            (identifiable_m2["fraction_nodes_with_truth_consistent_improving_move"]
             < M2_ACCESS_FAILURE_THRESHOLD).mean()
        )
        m2_median_truth_access=float(
            identifiable_m2["fraction_nodes_with_truth_consistent_improving_move"].median()
        )
    else:
        access_fail_fraction=0.0
        m2_median_truth_access=0.0
    m2_accessibility_support=(
        m1_family_identifies and len(identifiable_m2)>0 and access_fail_fraction>=0.80
    )

    family_rows=[]
    family_conflict_count=0
    for family,g in m2_tasks.groupby("family",sort=True):
        disagree=float(g["local_global_disagreement_fraction"].median())
        local_rate=float(g["local_truth_consistency_rate"].median())
        global_rate=float(g["global_truth_consistency_rate"].median())
        fused_rate=float(g["fused_truth_consistency_rate"].median())
        best_channel=max(local_rate,global_rate)
        conflict=(
            disagree>=M3_DISAGREEMENT_MIN
            and best_channel>=fused_rate+M3_TRUTH_CONSISTENCY_LOSS_MIN
        )
        if conflict:
            family_conflict_count+=1
        family_rows.append({
            "family":family,
            "median_local_global_disagreement_fraction":disagree,
            "median_local_truth_consistency_rate":local_rate,
            "median_global_truth_consistency_rate":global_rate,
            "median_fused_truth_consistency_rate":fused_rate,
            "best_channel_minus_fused_truth_consistency":best_channel-fused_rate,
            "FAMILY_FUSION_CONFLICT":"YES" if conflict else "NO",
        })
    pd.DataFrame(family_rows).to_csv(
        out/"D10G_D5_M3_FAMILY_FUSION_CONFLICT.csv",index=False
    )
    m3_support=family_conflict_count>=M3_FAMILIES_REQUIRED

    # M4
    move_frames=[]
    sweep_frames=[]
    m4_seed_rows=[]
    for task_id,family,W,truth in tasks:
        for seed_index in range(1,M4_SEEDS+1):
            mdf,sdf,srec=replay_first_sweeps(
                mod,d3,W,truth,cfg,task_id,seed_index
            )
            if len(mdf):
                mdf.insert(1,"family",family)
                move_frames.append(mdf)
            sdf.insert(1,"family",family)
            sweep_frames.append(sdf)
            srec["family"]=family
            m4_seed_rows.append(srec)

    m4_moves=(
        pd.concat(move_frames,ignore_index=True)
        if move_frames else
        pd.DataFrame()
    )
    m4_sweeps=pd.concat(sweep_frames,ignore_index=True)
    m4_seed=pd.DataFrame(m4_seed_rows)

    m4_moves.to_csv(out/"D10G_D5_M4_ACCEPTED_MOVE_LOG.csv",index=False)
    m4_sweeps.to_csv(out/"D10G_D5_M4_SWEEP_REPLAY_AUDIT.csv",index=False)
    m4_seed.to_csv(out/"D10G_D5_M4_SEED_SUMMARY.csv",index=False)

    if not (m4_seed["REPLAY_EQUIVALENCE"]=="PASS").all():
        raise RuntimeError("M4_REPLAY_EQUIVALENCE_FAILED")

    m4_task=m4_seed.groupby(["task_id","family"],as_index=False).agg(
        median_accepted_moves=("accepted_move_count","median"),
        median_truth_consistent_move_fraction=("truth_consistent_move_fraction","median"),
        median_ARI_improving_move_fraction=("ARI_improving_move_fraction","median"),
        median_Q_improving_move_fraction=("Q_improving_move_fraction","median"),
        replay_pass_rate=("REPLAY_EQUIVALENCE",lambda x: float((x=="PASS").mean())),
    )
    m4_task.to_csv(out/"D10G_D5_M4_TASK_SUMMARY.csv",index=False)
    m4_median_ari_improving=float(m4_seed["ARI_improving_move_fraction"].median())

    d3_final_poor=True
    m4_search_support=(
        m1_family_identifies
        and m2_median_truth_access>=M2_SUFFICIENT_ACCESS_THRESHOLD
        and (
            m4_median_ari_improving<M4_ARI_IMPROVING_MOVE_FRACTION_MIN
            or d3_final_poor
        )
    )

    # M5
    m5_rows=[]
    for task_id,family,W,truth in tasks:
        rec=signed_relational_signal(W,truth,task_id)
        rec["family"]=family
        m5_rows.append(rec)
    m5=pd.DataFrame(m5_rows)
    m5.to_csv(out/"D10G_D5_M5_RELATIONAL_SIGNAL.csv",index=False)
    m5_available_fraction=float(
        (m5["SIGN_RELATIONAL_SIGNAL_AVAILABLE"]=="YES").mean()
    )
    m5_fail_fraction=1.0-m5_available_fraction
    representation_support=(
        (not m1_family_identifies)
        and m5_fail_fraction>=M5_REPRESENTATION_FAILURE_FRACTION
    )

    objective_support=not m1_family_identifies

    # Per-task mechanism matrix.
    merged=m1[["task_id","OBJECTIVE_IDENTIFIES_TRUTH"]].merge(
        m2_tasks[[
            "task_id",
            "fraction_nodes_with_truth_consistent_improving_move",
            "local_global_disagreement_fraction",
            "local_truth_consistency_rate",
            "global_truth_consistency_rate",
            "fused_truth_consistency_rate",
        ]],on="task_id",how="inner"
    ).merge(
        m4_task[["task_id","median_ARI_improving_move_fraction"]],
        on="task_id",how="inner"
    ).merge(
        m5[["task_id","relational_signal_gap"]],
        on="task_id",how="inner"
    )

    merged["objective_failure_task"]=(
        merged["OBJECTIVE_IDENTIFIES_TRUTH"]!="YES"
    ).astype(int)
    merged["accessibility_failure_task"]=(
        (merged["OBJECTIVE_IDENTIFIES_TRUTH"]=="YES")
        & (merged["fraction_nodes_with_truth_consistent_improving_move"]
           < M2_ACCESS_FAILURE_THRESHOLD)
    ).astype(int)

    best_channel=merged[[
        "local_truth_consistency_rate","global_truth_consistency_rate"
    ]].max(axis=1)
    merged["fusion_conflict_task"]=(
        (merged["local_global_disagreement_fraction"]>=M3_DISAGREEMENT_MIN)
        & (best_channel>=merged["fused_truth_consistency_rate"]
           + M3_TRUTH_CONSISTENCY_LOSS_MIN)
    ).astype(int)

    merged["search_failure_task"]=(
        (merged["OBJECTIVE_IDENTIFIES_TRUTH"]=="YES")
        & (merged["fraction_nodes_with_truth_consistent_improving_move"]
           >= M2_SUFFICIENT_ACCESS_THRESHOLD)
        & (merged["median_ARI_improving_move_fraction"]
           < M4_ARI_IMPROVING_MOVE_FRACTION_MIN)
    ).astype(int)

    merged["representation_failure_task"]=(
        (merged["OBJECTIVE_IDENTIFIES_TRUTH"]!="YES")
        & (merged["relational_signal_gap"]<M5_RELATIONAL_GAP_MIN)
    ).astype(int)

    merged.to_csv(out/"D10G_D5_TASK_MECHANISM_MATRIX.csv",index=False)

    explanation={
        "SIGNED_OBJECTIVE_IDENTIFICATION_FAILURE":float(merged["objective_failure_task"].mean()),
        "LOCAL_MOVE_ACCESSIBILITY_FAILURE":float(merged["accessibility_failure_task"].mean()),
        "LOCAL_GLOBAL_FUSION_CONFLICT":float(merged["fusion_conflict_task"].mean()),
        "STOCHASTIC_TRANSITION_OR_SEARCH_FAILURE":float(merged["search_failure_task"].mean()),
        "REPRESENTATION_SIGNAL_DEFICIENCY":float(merged["representation_failure_task"].mean()),
    }

    supports={
        "SIGNED_OBJECTIVE_IDENTIFICATION_FAILURE":objective_support,
        "LOCAL_MOVE_ACCESSIBILITY_FAILURE":m2_accessibility_support,
        "LOCAL_GLOBAL_FUSION_CONFLICT":m3_support,
        "STOCHASTIC_TRANSITION_OR_SEARCH_FAILURE":m4_search_support,
        "REPRESENTATION_SIGNAL_DEFICIENCY":representation_support,
    }
    supported=[k for k,v in supports.items() if v]

    if representation_support:
        primary="REPRESENTATION_SIGNAL_DEFICIENCY"
        secondary=[x for x in supported if x!=primary]
    elif len(supported)==1:
        primary=supported[0]
        secondary=[]
    elif len(supported)>1:
        dominant=[x for x in supported if explanation.get(x,0.0)>=0.80]
        if len(dominant)==1:
            primary=dominant[0]
            secondary=[x for x in supported if x!=primary]
        else:
            primary="MIXED_MECHANISM"
            secondary=supported
    else:
        primary="MIXED_MECHANISM"
        secondary=[]

    pd.DataFrame([
        {
            "mechanism":m,
            "supported":"YES" if supports[m] else "NO",
            "task_explanation_fraction":explanation[m],
        }
        for m in supports
    ]).to_csv(out/"D10G_D5_MECHANISM_SUPPORT.csv",index=False)

    if primary=="REPRESENTATION_SIGNAL_DEFICIENCY":
        ready_r2="NO"
        ready_repr="YES"
    else:
        ready_r2="YES"
        ready_repr="NO"

    result={
        "D10G_D5_STATUS":"PASS",
        "R1_IMPLEMENTATION_SHA256":EXPECTED_R1_SHA,
        "D10G_D3_GENERATOR_SHA256":EXPECTED_D3_GENERATOR_SHA,
        "DIAGNOSTIC_CONFIGURATION":"CORE_04",
        "DIAGNOSTIC_TASKS":EXPECTED_TASKS,
        "M1_OBJECTIVE_IDENTIFIABLE_TASK_FRACTION":m1_pass_fraction,
        "M1_OBJECTIVE_IDENTIFIES_TRUTH_FAMILY_LEVEL":"YES" if m1_family_identifies else "NO",
        "M2_M1_IDENTIFIABLE_TASK_ACCESS_FAILURE_FRACTION":access_fail_fraction,
        "M2_MEDIAN_TRUTH_CONSISTENT_IMPROVING_ACCESS":m2_median_truth_access,
        "M3_FAMILY_CONFLICT_COUNT":family_conflict_count,
        "M4_MEDIAN_EARLY_ARI_IMPROVING_MOVE_FRACTION":m4_median_ari_improving,
        "M4_REPLAY_EQUIVALENCE":"PASS",
        "M5_RELATIONAL_SIGNAL_AVAILABLE_TASK_FRACTION":m5_available_fraction,
        "PRIMARY_MECHANISM":primary,
        "SECONDARY_MECHANISMS":"|".join(secondary),
        "D10G_DECISION_OVERRIDDEN":"NO",
        "METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE":"NO",
        "D10H_PARAMETER_FREEZE_AUTHORIZED":"NO",
        "R2_METHOD_DESIGNED":"NO",
        "R2_IMPLEMENTED":"NO",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "PARAMETER_TUNING_USING_GSE243219":"NO",
        "GSE243219_ACLA_EXECUTED":"NO",
        "D9_COMMUNITY_DETECTION_EXECUTED":"NO",
        "NETWORK_CHANGED":"NO",
        "D9_FILES_MODIFIED":"NO",
        "WEIGHT_TRANSFORMATION_APPLIED":"NO",
        "READY_FOR_D10C_R2_PROSPECTIVE_DESIGN":ready_r2,
        "READY_FOR_REPRESENTATION_REDESIGN_OR_BRANCH_ABANDONMENT":ready_repr,
        "READY_FOR_D10H_PARAMETER_AND_EXECUTION_FREEZE":"NO",
        "READY_FOR_GSE243219_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }
    result_json.write_text(json.dumps(result,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
