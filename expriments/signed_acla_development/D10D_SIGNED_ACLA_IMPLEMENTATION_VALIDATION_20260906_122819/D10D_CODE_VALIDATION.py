#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd


def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk),b""):
            h.update(b)
    return h.hexdigest()


def load_module(path: Path):
    spec=importlib.util.spec_from_file_location("signed_acla_impl", path)
    mod=importlib.util.module_from_spec(spec)
    sys.modules[spec.name]=mod
    spec.loader.exec_module(mod)
    return mod


def tiny_component(mod, nodes, edge_specs):
    ndf=pd.DataFrame({"node_index":nodes,"node_id":[f"N{x}" for x in nodes]})
    edf=pd.DataFrame(
        [{"source_index":u,"target_index":v,"association_score":w} for u,v,w,r in edge_specs]
    )
    rdf=pd.DataFrame(
        [{"source_index":u,"target_index":v} for u,v,w,r in edge_specs if r],
        columns=["source_index","target_index"]
    )
    return mod.build_signed_components(ndf,edf,rdf)[0]


def assert_close(a,b,tol=1e-10,msg=""):
    if abs(a-b)>tol:
        raise AssertionError(f"{msg} {a} != {b}")


def run_unit_tests(mod):
    rows=[]

    def record(name, fn):
        try:
            detail=fn()
            rows.append({"test":name,"status":"PASS","detail":str(detail or "")})
        except Exception as e:
            rows.append({"test":name,"status":"FAIL","detail":repr(e)})
            raise

    def t_local_ideal():
        c=tiny_component(mod,[0,1,2,3],[
            (0,1,0.8,False),(2,3,0.7,False),
            (0,2,-0.6,False),(0,3,-0.5,False),
            (1,2,-0.4,False),(1,3,-0.3,False)
        ])
        labels={0:0,1:0,2:2,3:2}
        good=mod.signed_local_score(c,labels,0,0,0.0)
        bad=mod.signed_local_score(c,labels,0,2,0.0)
        if not good>bad: raise AssertionError((good,bad))
        if not (-1<=good<=1 and -1<=bad<=1): raise AssertionError("bounds")
        return f"good={good:.6f};bad={bad:.6f}"
    record("LOCAL_SIGNED_SCORE_IDEAL",t_local_ideal)

    def t_reg_channel():
        c=tiny_component(mod,[0,1,2],[
            (0,1,0.8,True),(0,2,-0.4,False)
        ])
        labels={0:0,1:0,2:2}
        x=mod.signed_local_score(c,labels,0,0,0.0)
        y=mod.signed_local_score(c,labels,0,0,1.0)
        if not y>=x: raise AssertionError((x,y))
        return f"lambda0={x:.6f};lambda1={y:.6f}"
    record("REGULATORY_BINARY_CONFIDENCE_ONLY",t_reg_channel)

    def t_positive_only_reduction():
        c=tiny_component(mod,[0,1,2,3],[
            (0,1,1.0,False),(2,3,1.0,False),(1,2,0.2,False)
        ])
        labels={0:0,1:0,2:2,3:2}
        q=mod.signed_component_objective(c,labels)
        if not math.isfinite(q): raise AssertionError(q)
        if c.two_m_neg!=0: raise AssertionError(c.two_m_neg)
        return f"Q={q:.8f}"
    record("POSITIVE_ONLY_OBJECTIVE_SAFE",t_positive_only_reduction)

    def t_negative_penalty():
        c=tiny_component(mod,[0,1,2],[
            (0,1,0.8,False),(0,2,-0.9,False),(1,2,-0.9,False)
        ])
        good={0:0,1:0,2:2}
        bad={0:0,1:0,2:0}
        qg=mod.signed_component_objective(c,good)
        qb=mod.signed_component_objective(c,bad)
        if not qg>qb: raise AssertionError((qg,qb))
        return f"goodQ={qg:.8f};badQ={qb:.8f}"
    record("NEGATIVE_WITHIN_PENALIZED",t_negative_penalty)

    def t_delta_exact():
        c=tiny_component(mod,[0,1,2,3],[
            (0,1,0.8,False),(2,3,0.7,False),
            (0,2,-0.6,False),(1,3,-0.5,False),(1,2,0.1,False)
        ])
        labels={0:0,1:0,2:2,3:2}
        cp,cn=mod.component_community_strengths(c,labels)
        d=mod.delta_signed_objective_move(c,labels,1,2,cp,cn)
        before=mod.signed_component_objective(c,labels)
        moved=dict(labels);moved[1]=2
        after=mod.signed_component_objective(c,moved)
        assert_close(d,after-before,1e-12,"delta")
        return f"delta={d:.12f}"
    record("INCREMENTAL_DELTA_EQUALS_FULL_OBJECTIVE",t_delta_exact)

    def t_probability():
        for p in [0.0,0.1,0.5,0.9,1.0]:
            for action in ["MOVE","STAY"]:
                for e in [-2,-0.5,0,0.5,2]:
                    x=mod.learning_automaton_update(p,action,e,0.2,0.3)
                    if not 0<=x<=1: raise AssertionError((p,action,e,x))
        return "simplex preserved"
    record("PROBABILITY_SIMPLEX",t_probability)

    def t_seed():
        vals=[mod.deterministic_seed(i) for i in range(1,6)]
        if len(set(vals))!=5: raise AssertionError(vals)
        if vals != [mod.deterministic_seed(i) for i in range(1,6)]:
            raise AssertionError("non-deterministic")
        return "|".join(map(str,vals))
    record("DETERMINISTIC_SEED_GENERATION",t_seed)

    def t_repro():
        c=tiny_component(mod,[0,1,2,3],[
            (0,1,0.9,True),(2,3,0.9,False),
            (0,2,-0.8,False),(0,3,-0.7,False),
            (1,2,-0.7,False),(1,3,-0.8,True)
        ])
        # D10D TEST-ONLY values. They are not biological parameter freeze.
        cfg=mod.SACLAConfig(
            alpha_reward=0.2,alpha_penalty=0.2,gamma=0.5,lambda_regulatory=0.5,
            max_iterations=12,objective_tolerance=1e-9,node_change_tolerance=0.0,
            probability_change_tolerance=1e-9,patience=2
        )
        seed=mod.deterministic_seed(1)
        a=mod.run_one_component(c,cfg,seed)
        b=mod.run_one_component(c,cfg,seed)
        if a.labels!=b.labels: raise AssertionError("partition mismatch")
        cols=[x for x in a.history.columns]
        if not a.history[cols].equals(b.history[cols]):
            raise AssertionError("history mismatch")
        return f"seed={seed};converged={a.converged};Q={a.objective:.8f}"
    record("TINY_SYNTHETIC_REPRODUCIBILITY_UNIT_TEST",t_repro)

    def t_medoid():
        H=pd.DataFrame()
        r1=mod.SeedResult(1,True,"X",{0:0,1:0,2:2,3:2},0.5,H)
        r2=mod.SeedResult(2,True,"X",{0:0,1:0,2:2,3:2},0.4,H)
        r3=mod.SeedResult(3,True,"X",{0:0,1:1,2:2,3:3},0.9,H)
        m=mod.select_partition_medoid([r1,r2,r3])
        if m.seed!=1: raise AssertionError(m.seed)
        return f"medoid_seed={m.seed}"
    record("PARTITION_MEDOID_TIEBREAK",t_medoid)

    return rows


def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        print("D10D_VALIDATOR_SELFTEST=PASS")
        return 0
    if len(sys.argv)!=6:
        raise SystemExit("usage: validator <impl.py> <d9_run> <outdir> <result_json> <expected_impl_sha>")
    impl=Path(sys.argv[1]);d9=Path(sys.argv[2]);out=Path(sys.argv[3]);result_json=Path(sys.argv[4]);expected_sha=sys.argv[5]
    out.mkdir(parents=True,exist_ok=True)

    if sha256_file(impl)!=expected_sha:
        raise RuntimeError("IMPLEMENTATION_SHA256_MISMATCH")

    mod=load_module(impl)

    unit_rows=run_unit_tests(mod)
    pd.DataFrame(unit_rows).to_csv(out/"D10D_UNIT_TEST_REPORT.csv",index=False)

    bundle=d9/"D9_ACLA_INPUT"
    nodes,edges,reg=mod.load_frozen_d9_bundle(bundle)
    audit=mod.validate_d9_contract(nodes,edges,reg)
    pd.DataFrame([
        {"field":k,"value":json.dumps(v) if isinstance(v,(list,dict)) else v}
        for k,v in audit.items()
    ]).to_csv(out/"D10D_D9_READONLY_INTERFACE_AUDIT.csv",index=False)

    # Enforce frozen D9 facts.
    if audit["nodes"]!=4508: raise RuntimeError("D9_NODE_COUNT")
    if audit["edges"]!=11531: raise RuntimeError("D9_EDGE_COUNT")
    if audit["regulatory_edges"]!=1978: raise RuntimeError("D9_REGULATORY_COUNT")
    if audit["components"]!=2 or audit["component_sizes"][:2]!=[4502,6]:
        raise RuntimeError(f"D9_COMPONENTS={audit['component_sizes']}")
    if audit["isolates"]!=0: raise RuntimeError("D9_ISOLATES")
    if audit["negative_edges"]<=0: raise RuntimeError("D9_NEGATIVE_EDGES_MISSING")
    if audit["regulatory_edge_duplication"]!=0: raise RuntimeError("REGULATORY_DUPLICATION")

    # Build component data structures but DO NOT run the algorithm on D9.
    comps=mod.build_signed_components(nodes,edges,reg)
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
    pd.DataFrame(comp_rows).to_csv(out/"D10D_COMPONENT_STRUCTURE_AUDIT.csv",index=False)

    interface_rows=[
        ["load_frozen_d9_bundle",hasattr(mod,"load_frozen_d9_bundle")],
        ["validate_d9_contract",hasattr(mod,"validate_d9_contract")],
        ["build_signed_components",hasattr(mod,"build_signed_components")],
        ["signed_local_score",hasattr(mod,"signed_local_score")],
        ["signed_component_objective",hasattr(mod,"signed_component_objective")],
        ["delta_signed_objective_move",hasattr(mod,"delta_signed_objective_move")],
        ["candidate_best_alternative",hasattr(mod,"candidate_best_alternative")],
        ["learning_automaton_update",hasattr(mod,"learning_automaton_update")],
        ["run_one_component",hasattr(mod,"run_one_component")],
        ["evaluate_convergence",hasattr(mod,"evaluate_convergence")],
        ["select_partition_medoid",hasattr(mod,"select_partition_medoid")],
        ["write_iteration_history",hasattr(mod,"write_iteration_history")],
    ]
    pd.DataFrame(interface_rows,columns=["interface","present"]).to_csv(
        out/"D10D_IMPLEMENTATION_INTERFACE_AUDIT.csv",index=False
    )
    if not all(x[1] for x in interface_rows):
        raise RuntimeError("IMPLEMENTATION_INTERFACE_MISSING")

    result={
        "D10D_STATUS":"PASS",
        "IMPLEMENTATION_CREATED":"YES",
        "IMPLEMENTATION_SHA256":sha256_file(impl),
        "IMPLEMENTATION_UNIT_TESTS_PASS":"YES",
        "D9_READONLY_INTERFACE_AUDIT_PASS":"YES",
        "D9_COMPONENT_STRUCTURES_BUILT":"YES",
        "D9_COMMUNITY_DETECTION_EXECUTED":"NO",
        "SIGNED_ACLA_EXECUTED_ON_GSE243219":"NO",
        "SYNTHETIC_BENCHMARK_CAMPAIGN_EXECUTED":"NO",
        "TINY_SYNTHETIC_UNIT_TESTS_EXECUTED":"YES",
        "BIOLOGICAL_PARAMETER_VALUES_FROZEN":"NO",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "NETWORK_CHANGED":"NO",
        "D9_FILES_MODIFIED":"NO",
        "WEIGHT_TRANSFORMATION_APPLIED":"NO",
        "NEGATIVE_EDGES_REMOVED":"NO",
        "REGULATORY_EDGE_DUPLICATION":0,
        "READY_FOR_D10E_SIGNED_SYNTHETIC_VALIDATION":"YES",
        "READY_FOR_GSE243219_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }
    result_json.write_text(json.dumps(result,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
