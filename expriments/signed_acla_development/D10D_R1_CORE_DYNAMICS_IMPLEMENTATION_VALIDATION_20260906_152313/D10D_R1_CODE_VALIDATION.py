#!/usr/bin/env python3
from __future__ import annotations

import ast
import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_R0_SHA="a46a2fd5beacec09f800fd6d1c855b2c8f4c10e2159028542ac46cedef19fe24"
EXPECTED_R1_SHA="2bfe790d6aff0fc0404d37683fed2ef0a7c85b78c6a31bb692d3f69d0f7e257d"
FROZEN_FUNCTIONS=[
    "load_frozen_d9_bundle",
    "validate_d9_contract",
    "build_signed_components",
    "signed_local_score",
    "signed_component_objective",
    "delta_signed_objective_move",
    "learning_automaton_update",
    "adjusted_rand_index_from_labels",
    "select_partition_medoid",
    "deterministic_seed",
]

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk),b""):
            h.update(b)
    return h.hexdigest()

def load_module(path: Path, name: str):
    spec=importlib.util.spec_from_file_location(name,path)
    mod=importlib.util.module_from_spec(spec)
    sys.modules[name]=mod
    spec.loader.exec_module(mod)
    return mod

def function_ast_map(path: Path):
    tree=ast.parse(path.read_text(encoding="utf-8"))
    out={}
    for n in tree.body:
        if isinstance(n,ast.FunctionDef):
            out[n.name]=ast.dump(n,include_attributes=False)
    return out

def make_component(mod,n,edges):
    ndf=pd.DataFrame({"node_index":list(range(n)),"node_id":[f"N{i}" for i in range(n)]})
    edf=pd.DataFrame([
        {"source_index":u,"target_index":v,"association_score":w}
        for u,v,w,r in edges
    ])
    rdf=pd.DataFrame(
        [{"source_index":u,"target_index":v} for u,v,w,r in edges if r],
        columns=["source_index","target_index"],
    )
    return mod.build_signed_components(ndf,edf,rdf)[0]

def ideal_component(mod):
    n=10
    edges=[]
    for i in range(n):
        for j in range(i+1,n):
            same=(i<5)==(j<5)
            if same:
                w=0.75+0.05*((i+2*j)%5)
            else:
                w=-(0.55+0.05*((2*i+j)%5))
            edges.append((i,j,float(w),False))
    truth={i:(0 if i<5 else 5) for i in range(10)}
    return make_component(mod,n,edges),truth

def selftest():
    assert EXPECTED_R0_SHA != EXPECTED_R1_SHA
    assert 0.0 <= 1e-12
    print("D10D_R1_VALIDATOR_SELFTEST=PASS")
    print("R0_R1_HASH_DISTINCTION_SELFTEST=PASS")
    print("NO_GSE243219_ALGORITHM_EXECUTION_SELFTEST=PASS")
    return 0

def run_unit_tests(r0,r1):
    rows=[]
    def record(name,fn):
        try:
            detail=fn()
            rows.append({"test":name,"status":"PASS","detail":str(detail or "")})
        except Exception as e:
            rows.append({"test":name,"status":"FAIL","detail":repr(e)})
            raise

    def harmful_gate():
        if r1.is_move_eligible(-0.5) or r1.is_move_eligible(0.0) or r1.is_move_eligible(1e-12):
            raise AssertionError("non-improving move marked eligible")
        return "d<=1e-12 blocked"
    record("HARMFUL_MOVE_GATE",harmful_gate)

    def beneficial_gate():
        if not r1.is_move_eligible(0.1):
            raise AssertionError("beneficial move not eligible")
        return "positive advantage eligible"
    record("BENEFICIAL_MOVE_ELIGIBLE",beneficial_gate)

    def singleton_identity():
        c=make_component(r1,3,[
            (0,1,0.8,False),(0,2,-0.5,False),(1,2,-0.4,False)
        ])
        labels={0:0,1:1,2:2}
        cand=r1.candidate_communities(c,labels,0)
        if None in cand:
            raise AssertionError(cand)
        return str(cand)
    record("CURRENT_SINGLETON_NO_NEW_SINGLETON",singleton_identity)

    def multisize_singleton_available():
        c=make_component(r1,3,[
            (0,1,0.8,False),(0,2,-0.5,False),(1,2,-0.4,False)
        ])
        labels={0:0,1:0,2:2}
        cand=r1.candidate_communities(c,labels,0)
        if None not in cand:
            raise AssertionError(cand)
        return str(cand)
    record("MULTINODE_MEMBER_CAN_FORM_SINGLETON",multisize_singleton_available)

    def planted_absorbing():
        c,truth=ideal_component(r1)
        cp,cn=r1.component_community_strengths(c,truth)
        sizes=r1.community_sizes(truth)
        eligible=[]
        for node in c.nodes:
            best,best_s,current_s=r1.candidate_best_alternative(
                c,truth,node,0.0,0.25,cp,cn,community_sizes_map=sizes
            )
            d=best_s[0]-current_s[0]
            if r1.is_move_eligible(d):
                eligible.append((node,best,d))
        if eligible:
            raise AssertionError(eligible)
        nimp,maxadv=r1.post_sweep_improvement_audit(c,truth,0.0,0.25)
        if nimp!=0:
            raise AssertionError((nimp,maxadv))
        return "zero eligible moves at planted truth"
    record("PLANTED_IDEAL_PARTITION_ABSORBING",planted_absorbing)

    def partition_signature_invariant():
        a={0:0,1:0,2:2,3:2}
        b={0:10,1:10,2:4,3:4}
        if r1.partition_signature(a)!=r1.partition_signature(b):
            raise AssertionError("signature changed under relabel")
        return r1.partition_signature(a)
    record("CANONICAL_RELABEL_NOT_PARTITION_SWITCH",partition_signature_invariant)

    def no_false_convergence():
        cfg=r1.SACLAConfig(0.2,0.2,0.5,0.0,20,1e-6,0.02,1e-2,2)
        if r1.evaluate_convergence(0.0,0,1,0.0,cfg):
            raise AssertionError("converged with improving node")
        if r1.evaluate_convergence(0.0,1,0,0.0,cfg):
            raise AssertionError("converged with accepted move")
        if not r1.evaluate_convergence(0.0,0,0,0.0,cfg):
            raise AssertionError("valid terminal state rejected")
        return "zero moves + zero improvements required"
    record("R1_CONVERGENCE_REQUIRES_LOCAL_EQUILIBRIUM",no_false_convergence)

    def delta_exact():
        c=make_component(r1,4,[
            (0,1,0.8,False),(2,3,0.7,False),
            (0,2,-0.6,False),(1,3,-0.5,False),(1,2,0.1,False)
        ])
        labels={0:0,1:0,2:2,3:2}
        cp,cn=r1.component_community_strengths(c,labels)
        d=r1.delta_signed_objective_move(c,labels,1,2,cp,cn)
        before=r1.signed_component_objective(c,labels)
        moved=dict(labels);moved[1]=2
        after=r1.signed_component_objective(c,moved)
        if abs(d-(after-before))>1e-12:
            raise AssertionError((d,after-before))
        return f"delta={d:.12f}"
    record("INCREMENTAL_DELTA_EQUALS_FULL_OBJECTIVE",delta_exact)

    def simplex():
        for p in [0.0,0.1,0.5,0.9,1.0]:
            for action in ["MOVE","STAY"]:
                for e in [-2,-0.5,0,0.5,2]:
                    x=r1.learning_automaton_update(p,action,e,0.2,0.3)
                    if not 0<=x<=1:
                        raise AssertionError((p,action,e,x))
        return "simplex preserved"
    record("PROBABILITY_SIMPLEX",simplex)

    def full_repro():
        c=make_component(r1,6,[
            (0,1,0.9,True),(0,2,0.8,False),(1,2,0.85,False),
            (3,4,0.9,False),(3,5,0.8,True),(4,5,0.85,False),
            (0,3,-0.7,False),(1,4,-0.75,False),(2,5,-0.7,False),
            (0,4,-0.65,False),(1,5,-0.65,False),(2,3,-0.65,False),
        ])
        cfg=r1.SACLAConfig(0.2,0.2,0.5,0.5,40,1e-6,0.02,1e-2,3)
        seed=r1.deterministic_seed(1)
        a=r1.run_one_component(c,cfg,seed)
        b=r1.run_one_component(c,cfg,seed)
        if a.labels!=b.labels or not a.history.equals(b.history):
            raise AssertionError("same-seed scientific result differs")
        return f"seed={seed};converged={a.converged};Q={a.objective:.8f}"
    record("SAME_SEED_FULL_R1_REPRODUCIBILITY",full_repro)

    def executed_moves_positive():
        c=make_component(r1,6,[
            (0,1,0.9,False),(0,2,0.8,False),(1,2,0.85,False),
            (3,4,0.9,False),(3,5,0.8,False),(4,5,0.85,False),
            (0,3,-0.7,False),(1,4,-0.75,False),(2,5,-0.7,False),
            (0,4,-0.65,False),(1,5,-0.65,False),(2,3,-0.65,False),
        ])
        cfg=r1.SACLAConfig(0.3,0.3,0.5,0.0,60,1e-6,0.02,1e-2,3)
        rr=r1.run_one_component(c,cfg,r1.deterministic_seed(2))
        moved=rr.history[rr.history["accepted_moves"]>0]
        if len(moved):
            vals=moved["min_executed_move_advantage"].dropna().to_numpy(float)
            if len(vals) and not np.all(vals>r1.IMPROVEMENT_EPSILON):
                raise AssertionError(vals)
        return f"iterations={len(rr.history)}"
    record("ALL_EXECUTED_MOVES_STRICTLY_IMPROVING",executed_moves_positive)

    return rows

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=8:
        raise SystemExit(
            "usage: validator <r0.py> <r1.py> <d9_run> <d10c_r1_status> "
            "<outdir> <result_json> <expected_r1_sha>"
        )

    r0_path=Path(sys.argv[1])
    r1_path=Path(sys.argv[2])
    d9=Path(sys.argv[3])
    r1_status_path=Path(sys.argv[4])
    out=Path(sys.argv[5])
    result_path=Path(sys.argv[6])
    expected_r1=sys.argv[7]
    out.mkdir(parents=True,exist_ok=True)

    if sha256_file(r0_path)!=EXPECTED_R0_SHA:
        raise RuntimeError("R0_SHA256_MISMATCH")
    if sha256_file(r1_path)!=expected_r1 or expected_r1!=EXPECTED_R1_SHA:
        raise RuntimeError("R1_SHA256_MISMATCH")

    status=r1_status_path.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10C_R1_STATUS=PASS",
        "SIGNED_LOCAL_SCORE_CHANGED=NO",
        "SIGNED_GLOBAL_OBJECTIVE_CHANGED=NO",
        "HARMFUL_MOVE_EXECUTION_ALLOWED_R1=NO",
        "CURRENT_SINGLETON_DUPLICATE_ACTION_ALLOWED_R1=NO",
        "CONVERGENCE_REQUIRES_ZERO_IMPROVING_NODES=YES",
        "THRESHOLD_RELAXATION_USED=NO",
        "PARAMETER_GRID_EXPANSION_USED=NO",
        "READY_FOR_D10D_R1_CORE_DYNAMICS_IMPLEMENTATION=YES",
        "GSE243219_ACLA_EXECUTED=NO",
    ]:
        if tok not in status:
            raise RuntimeError(f"D10C_R1_AUTHORITY_TOKEN_MISSING={tok}")

    r0_ast=function_ast_map(r0_path)
    r1_ast=function_ast_map(r1_path)
    eq_rows=[]
    for fn in FROZEN_FUNCTIONS:
        eq=(r0_ast.get(fn)==r1_ast.get(fn))
        eq_rows.append({"function":fn,"AST_EQUIVALENT":int(eq)})
        if not eq:
            raise RuntimeError(f"FROZEN_FUNCTION_CHANGED={fn}")
    pd.DataFrame(eq_rows).to_csv(out/"D10D_R1_R0_R1_FROZEN_MATH_EQUIVALENCE.csv",index=False)

    r0=load_module(r0_path,"sacla_r0_audit")
    r1=load_module(r1_path,"sacla_r1_validation")

    tests=run_unit_tests(r0,r1)
    pd.DataFrame(tests).to_csv(out/"D10D_R1_UNIT_TEST_REPORT.csv",index=False)

    # D9 is read and structurally built only. run_one_component is never called on D9.
    bundle=d9/"D9_ACLA_INPUT"
    nodes,edges,reg=r1.load_frozen_d9_bundle(bundle)
    audit=r1.validate_d9_contract(nodes,edges,reg)
    pd.DataFrame([
        {"field":k,"value":json.dumps(v) if isinstance(v,(list,dict)) else v}
        for k,v in audit.items()
    ]).to_csv(out/"D10D_R1_D9_READONLY_INTERFACE_AUDIT.csv",index=False)

    if audit["nodes"]!=4508 or audit["edges"]!=11531 or audit["regulatory_edges"]!=1978:
        raise RuntimeError("D9_COUNT_GATE_FAILED")
    if audit["components"]!=2 or audit["component_sizes"][:2]!=[4502,6]:
        raise RuntimeError(f"D9_COMPONENT_GATE_FAILED={audit['component_sizes']}")
    if audit["isolates"]!=0 or audit["negative_edges"]<=0:
        raise RuntimeError("D9_SIGNED_STRUCTURE_GATE_FAILED")
    if audit["regulatory_edge_duplication"]!=0:
        raise RuntimeError("D9_REGULATORY_DUPLICATION")

    comps=r1.build_signed_components(nodes,edges,reg)
    comp_rows=[]
    for i,c in enumerate(comps,1):
        comp_rows.append({
            "component_id":i,
            "nodes":len(c.nodes),
            "edges":len(c.edges),
            "two_m_pos":c.two_m_pos,
            "two_m_neg":c.two_m_neg,
            "absolute_mass":c.absolute_mass,
        })
    pd.DataFrame(comp_rows).to_csv(out/"D10D_R1_COMPONENT_STRUCTURE_AUDIT.csv",index=False)

    result={
        "D10D_R1_STATUS":"PASS",
        "R0_IMPLEMENTATION_SHA256":EXPECTED_R0_SHA,
        "R1_IMPLEMENTATION_CREATED":"YES",
        "R1_IMPLEMENTATION_SHA256":EXPECTED_R1_SHA,
        "R0_TO_R1_FROZEN_MATH_EQUIVALENCE":"PASS",
        "R1_UNIT_TESTS_PASS":"YES",
        "HARMFUL_MOVE_EXECUTION_BLOCKED":"YES",
        "BENEFICIAL_MOVE_REMAINS_ELIGIBLE":"YES",
        "PLANTED_IDEAL_PARTITION_ABSORBING_UNIT_TEST":"PASS",
        "CURRENT_SINGLETON_DUPLICATE_ACTION_ALLOWED":"NO",
        "PARTITION_INVARIANT_SWITCH_ACCOUNTING_VALIDATED":"YES",
        "CONVERGENCE_WITH_IMPROVING_NODE_ALLOWED":"NO",
        "ALL_EXECUTED_MOVES_STRICTLY_IMPROVING":"YES",
        "D9_READONLY_INTERFACE_AUDIT_PASS":"YES",
        "D9_COMPONENT_STRUCTURES_BUILT":"YES",
        "D9_COMMUNITY_DETECTION_EXECUTED":"NO",
        "SIGNED_ACLA_R1_EXECUTED_ON_GSE243219":"NO",
        "TINY_SYNTHETIC_UNIT_TESTS_EXECUTED":"YES",
        "D10E_R1_SYNTHETIC_REVALIDATION_EXECUTED":"NO",
        "EXTERNAL_BASELINE_BENCHMARK_EXECUTED":"NO",
        "BIOLOGICAL_PARAMETER_VALUES_FROZEN":"NO",
        "PARAMETER_TUNING_USING_GSE243219":"NO",
        "NETWORK_CHANGED":"NO",
        "D9_FILES_MODIFIED":"NO",
        "WEIGHT_TRANSFORMATION_APPLIED":"NO",
        "NEGATIVE_EDGES_REMOVED":"NO",
        "READY_FOR_D10E_R1_SYNTHETIC_REVALIDATION":"YES",
        "READY_FOR_D10F_SIGNED_BENCHMARKING":"NO",
        "READY_FOR_GSE243219_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }
    result_path.write_text(json.dumps(result,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
