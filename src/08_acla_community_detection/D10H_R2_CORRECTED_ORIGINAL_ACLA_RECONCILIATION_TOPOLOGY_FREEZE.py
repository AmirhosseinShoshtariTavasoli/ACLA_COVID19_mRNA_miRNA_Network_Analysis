#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_SOURCE_SHA="ee3c3b735ba6593d5a6af155e599403e697f498b290dc75a39ff0e3ab90b07de"
EXPECTED_NODES=4508
EXPECTED_EDGES=11531
EXPECTED_POS=5225
EXPECTED_NEG=6306
EXPECTED_REG=1978
EXPECTED_COMPONENTS=2
EXPECTED_LARGEST=4502
EXPECTED_SECOND=6

ENTRYPOINT_REPO_PATH="legacy/submission_code/Modularity/A-CLA.02.01.Modularity.py"

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk), b""):
            h.update(b)
    return h.hexdigest()

def require(cond, msg):
    if not cond:
        raise RuntimeError(msg)

class DSU:
    def __init__(self,n):
        self.p=list(range(n))
        self.sz=[1]*n
    def find(self,x):
        while self.p[x]!=x:
            self.p[x]=self.p[self.p[x]]
            x=self.p[x]
        return x
    def union(self,a,b):
        ra=self.find(a); rb=self.find(b)
        if ra==rb:
            return
        if self.sz[ra] < self.sz[rb]:
            ra,rb=rb,ra
        self.p[rb]=ra
        self.sz[ra]+=self.sz[rb]
    def component_sizes(self):
        roots={}
        for i in range(len(self.p)):
            r=self.find(i)
            roots[r]=roots.get(r,0)+1
        return sorted(roots.values(), reverse=True)

def source_static_audit(source_path: Path):
    require(source_path.is_file(), f"ORIGINAL_ACLA_SOURCE_MISSING={source_path}")
    actual=sha256_file(source_path)
    require(actual==EXPECTED_SOURCE_SHA,
            f"ORIGINAL_ACLA_SOURCE_SHA256_MISMATCH expected={EXPECTED_SOURCE_SHA} actual={actual}")
    text=source_path.read_text(encoding="utf-8-sig",errors="strict")

    required_literals=[
        "pd.read_excel(path, index_col=0)",
        "pd.read_csv(path, index_col=0)",
        "if df.shape[0] != df.shape[1]",
        "df2 = (df > 0).astype(int)",
        "labels = louvain_init(G)",
        "def candidate_labels_for(n)",
        "neigh_labs = [labels[v] for v in G.neighbors(n)]",
        "labs = set(neigh_labs + [labels[n]])",
        "counts = Counter(neigh_labs)",
        "maxc = max(counts.values())",
        "local_scores[c] = counts.get(c, 0) / maxc",
        "q_c = try_move_label(G, labels, n, c)",
        "global_scores[c] = max(0.0, q_c - q_now)",
        "fused[c] = (1 - global_w) * ls + global_w * gs",
        "if random.random() < alpha",
        "choice = random.choice(top2)[0]",
        "if choice != labels[n]",
        "labels[n] = choice",
        "alpha = alpha0",
        "alpha = max(alpha_min, alpha * 0.95)",
        "ITERATIONS = 200",
        "ALPHA0 = 0.20",
        "ALPHA_MIN = 0.01",
        "GLOBAL_WEIGHT = 0.35",
        "PATIENCE = 10",
        "SEED = 42",
        "if no_improve >= patience or not changed",
        "best_labels = labels.copy()",
        "final_labels = best_labels",
    ]
    missing=[x for x in required_literals if x not in text]
    require(not missing, "SOURCE_STATIC_CONTRACT_MISSING="+"|".join(missing))
    require("weight=None" in text, "UNWEIGHTED_MODULARITY_NOT_CONFIRMED")

    return text

def reconciliation():
    rows=[
        ["INPUT_SCHEMA","Undirected graph G=(V,E), weighted optional.",
         "Square labeled adjacency matrix; default graph construction binarizes entries >0.",
         "PARTIAL","Lossless topology edge-list to 0/1 adjacency serialization required."],
        ["INITIAL_PARTITION","Singleton c_i=i.",
         "Louvain initialization when available; otherwise iterative majority-label fallback.",
         "NO","Material starting-partition difference."],
        ["AUTOMATON_TYPE","Multi-action per-node P_i probability vector over community labels.",
         "No explicit P_i; hard-label stochastic exploration/exploitation over candidate labels.",
         "NO","Material algorithmic difference."],
        ["ACTION_SET_RULE","Own label plus neighbor labels.",
         "Current neighbor labels plus current label, recomputed for every node update.",
         "PARTIAL","Conceptually similar source of candidates; explicitly dynamic in code."],
        ["ACTION_SET_DYNAMICS","Not fully specified after initialization.",
         "Dynamic; no probability-mass transfer because P_i does not exist.",
         "NO","Execution semantics differ from manuscript LA representation."],
        ["INITIAL_ACTION_PROBABILITIES","Uniform 1/r_i.",
         "Not implemented; scalar alpha controls exploration.",
         "NO","Material learning-mechanism difference."],
        ["LOCAL_REWARD","Fraction of neighbors aligned with sampled action.",
         "Candidate score=count(candidate neighbor labels)/maximum candidate neighbor-label count.",
         "NO","Different normalization and no sampled-action reward/penalty P_i update."],
        ["ADAPTIVE_ALPHA","Node-specific normalized density/degree/betweenness formula.",
         "Single global alpha: 0.20 initially; alpha=max(0.01,0.95*alpha) per outer iteration.",
         "NO","Node-specific adaptive alpha absent."],
        ["GLOBAL_FEEDBACK","Periodic K_global; sigmoid(Q_curr-Q_prev); beta update of P_i.",
         "Per-candidate max(0,Q_if_move-best_Q_so_far), normalized and fused with local signal.",
         "NO","Different feedback semantics and timing."],
        ["ACTION_SELECTION","Sample a_i from P_i or optional greedy argmax.",
         "With probability alpha choose randomly among top two fused candidates; else fused argmax.",
         "NO","No learned action probability distribution."],
        ["COMMUNITY_UPDATE_TIMING","Crisp argmax(P_i) at global feedback/final; local provisional timing ambiguous.",
         "Immediate asynchronous hard-label update within shuffled sweep.",
         "NO","Different state-transition semantics."],
        ["MODULARITY_WEIGHTING","Q(P), weighted graph optional.",
         "NetworkX modularity explicitly called with weight=None.",
         "PARTIAL","Recovered final objective is topology-only."],
        ["CONVERGENCE","Mean L1 probability-vector change below epsilon or Tmax.",
         "No modularity improvement for 10 iterations OR no label changes OR 200 iterations.",
         "NO","Hard-label/modularity convergence, not P_i stabilization."],
        ["FINAL_MEMBERSHIP","argmax_k P_i[k].",
         "best_labels hard partition associated with best observed modularity.",
         "NO","No P_i exists in recovered implementation."],
        ["REPRODUCIBILITY","RNG seed specified.",
         "Python random seed 42; Louvain best_partition called without explicit random_state.",
         "PARTIAL","Main stochastic path seeded, but Louvain call itself is not explicitly pinned."],
    ]
    return pd.DataFrame(rows,columns=[
        "MECHANISM","PSEUDOCODE_BEHAVIOR","CODE_BEHAVIOR","MATCH","SCIENTIFIC_SIGNIFICANCE"
    ])

def write_method_spec(outdir: Path):
    text="""# D10H Original A-CLA — Code-Authoritative Method Specification

## Execution authority

Publication-provenanced recovered final modularity source:

`legacy/submission_code/Modularity/A-CLA.02.01.Modularity.py`

SHA256:

`ee3c3b735ba6593d5a6af155e599403e697f498b290dc75a39ff0e3ab90b07de`

The source code is authoritative for later execution. The article pseudocode is used
for reconciliation only and is not used to silently rewrite the recovered code.

## Recovered code behavior

- Required input: square labeled adjacency matrix in Excel or CSV/TXT format.
- Default topology conversion: `(df > 0).astype(int)`.
- Initialization: Louvain if available, otherwise iterative majority-label fallback.
- Candidate labels: dynamically recomputed current neighbor labels plus current label.
- No explicit per-node action probability vector P_i.
- Local score: neighbor-label count divided by maximum neighbor-label count.
- Global score: `max(0, Q_if_candidate_move - best_Q_so_far)`, normalized.
- Fused score: 0.65 local + 0.35 global.
- Exploration alpha: starts at 0.20, multiplied by 0.95 each outer iteration, floor 0.01.
- Action: random choice among top two fused candidates with probability alpha;
  otherwise fused-score argmax.
- Community update: immediate asynchronous hard-label update.
- Modularity: unweighted (`weight=None`).
- Stop: no improvement for 10 iterations, or no label change, or 200 iterations.
- Final membership: `best_labels`, the best-modularity hard partition.

## D10H representation

D9 remains the frozen signed scientific association network.

The D10H optimization projection contains all 4,508 D9 nodes and all 11,531 frozen
structural associations. Every frozen pair is represented as binary adjacency 1
irrespective of original sign.

This is not `negative weight -> abs(weight)`.

It is:

`stable association exists -> topology edge exists`.

The original signed coefficient and regulatory evidence remain unchanged in
`D10H_ACLA_EDGE_METADATA.csv`.

Original A-CLA therefore addresses topology-only dense association groups. It does not
optimize positive-within / negative-between signed organization.

Regulatory evidence is not used during A-CLA optimization and remains available for
post-community characterization.
"""
    (outdir/"D10H_ORIGINAL_ACLA_METHOD_SPECIFICATION.md").write_text(text,encoding="utf-8")

def build_projection(node_index_path: Path, structural_path: Path, outdir: Path):
    nodes=pd.read_csv(node_index_path,dtype=str,keep_default_na=False)
    edges=pd.read_csv(structural_path,float_precision="round_trip",keep_default_na=False)

    require("node_id" in nodes.columns, "NODE_INDEX_NODE_ID_COLUMN_MISSING")
    require(len(nodes)==EXPECTED_NODES, f"NODE_COUNT={len(nodes)}")
    require(nodes["node_id"].nunique()==EXPECTED_NODES, "DUPLICATE_NODE_IDS")

    required=[
        "source","target","association_score","regulatory_eligible","regulatory_class",
        "TarBase_support","TargetScan_support","miRDB_GT80_support"
    ]
    missing=[c for c in required if c not in edges.columns]
    require(not missing,"STRUCTURAL_EDGE_COLUMNS_MISSING="+"|".join(missing))
    require(len(edges)==EXPECTED_EDGES,f"EDGE_COUNT={len(edges)}")

    node_ids=nodes["node_id"].astype(str).tolist()
    node_set=set(node_ids)
    index={n:i for i,n in enumerate(node_ids)}

    source=edges["source"].astype(str)
    target=edges["target"].astype(str)
    unknown=int((~source.isin(node_set)).sum()+(~target.isin(node_set)).sum())
    self_loops=int((source==target).sum())

    canonical=[tuple(sorted((s,t))) for s,t in zip(source,target)]
    duplicate_edges=len(canonical)-len(set(canonical))

    weights=pd.to_numeric(edges["association_score"],errors="raise")
    require(np.isfinite(weights.to_numpy(float)).all(),"NONFINITE_WEIGHTS")
    pos=int((weights>0).sum())
    neg=int((weights<0).sum())
    zero=int((weights==0).sum())
    reg=int(edges["regulatory_eligible"].astype(str).str.upper().eq("YES").sum())

    require((pos,neg,zero)==(EXPECTED_POS,EXPECTED_NEG,0),
            f"SIGN_COUNTS={pos},{neg},{zero}")
    require(reg==EXPECTED_REG,f"REGULATORY_COUNT={reg}")
    require(self_loops==0,f"SELF_LOOPS={self_loops}")
    require(duplicate_edges==0,f"DUPLICATE_EDGES={duplicate_edges}")
    require(unknown==0,f"UNKNOWN_ENDPOINTS={unknown}")

    topo=pd.DataFrame({"source":source,"target":target})
    topo.to_csv(outdir/"D10H_ACLA_ALL_EDGE_TOPOLOGY.csv",index=False)

    meta=edges[required].copy()
    meta=meta.rename(columns={"association_score":"original_signed_weight"})
    meta.insert(
        3,"sign",
        np.where(pd.to_numeric(meta["original_signed_weight"])>0,"POSITIVE","NEGATIVE")
    )
    meta.to_csv(outdir/"D10H_ACLA_EDGE_METADATA.csv",index=False,float_format="%.17g")

    # Component audit with dependency-free union-find.
    dsu=DSU(EXPECTED_NODES)
    degrees=np.zeros(EXPECTED_NODES,dtype=np.int64)
    for s,t in topo.itertuples(index=False,name=None):
        i=index[s]; j=index[t]
        dsu.union(i,j)
        degrees[i]+=1
        degrees[j]+=1
    comps=dsu.component_sizes()
    isolates=int((degrees==0).sum())
    require(len(comps)==EXPECTED_COMPONENTS,f"COMPONENTS={len(comps)}")
    require(comps[0]==EXPECTED_LARGEST and comps[1]==EXPECTED_SECOND,
            f"COMPONENT_SIZES={comps[:5]}")
    require(isolates==0,f"ISOLATES={isolates}")

    # Square labeled adjacency serialization expected by recovered A-CLA.
    A=np.zeros((EXPECTED_NODES,EXPECTED_NODES),dtype=np.uint8)
    for s,t in topo.itertuples(index=False,name=None):
        i=index[s]; j=index[t]
        A[i,j]=1; A[j,i]=1

    require(np.array_equal(A,A.T),"ADJACENCY_NOT_SYMMETRIC")
    require(int(A.diagonal().sum())==0,"ADJACENCY_DIAGONAL_NONZERO")
    serialized_edges=int(np.triu(A,1).sum())
    require(serialized_edges==EXPECTED_EDGES,
            f"SERIALIZED_EDGE_COUNT={serialized_edges}")

    adjacency=outdir/"D10H_ACLA_INPUT_ADJACENCY.csv"
    with adjacency.open("w",encoding="utf-8",newline="") as f:
        writer=csv.writer(f,lineterminator="\n")
        writer.writerow([""]+node_ids)
        for i,n in enumerate(node_ids):
            writer.writerow([n]+A[i].tolist())

    # Lightweight streaming audit of the written serialization; no pandas reload.
    row_count=0
    with adjacency.open("r",encoding="utf-8",newline="") as f:
        reader=csv.reader(f)
        header=next(reader)
        require(len(header)==EXPECTED_NODES+1,"ADJACENCY_HEADER_WIDTH_CHANGED")
        require(header[1:]==node_ids,"ADJACENCY_HEADER_NODE_ORDER_CHANGED")
        for row_idx,row in enumerate(reader):
            require(len(row)==EXPECTED_NODES+1,
                    f"ADJACENCY_ROW_WIDTH_CHANGED row={row_idx}")
            require(row[0]==node_ids[row_idx],
                    f"ADJACENCY_ROW_LABEL_CHANGED row={row_idx}")
            row_count+=1
    require(row_count==EXPECTED_NODES,f"ADJACENCY_ROW_COUNT={row_count}")

    audit=pd.DataFrame([
        ["NODES",EXPECTED_NODES,len(nodes),"PASS"],
        ["EDGES",EXPECTED_EDGES,len(topo),"PASS"],
        ["COMPONENTS",EXPECTED_COMPONENTS,len(comps),"PASS"],
        ["LARGEST_COMPONENT",EXPECTED_LARGEST,comps[0],"PASS"],
        ["SECOND_COMPONENT",EXPECTED_SECOND,comps[1],"PASS"],
        ["ISOLATED_NODES",0,isolates,"PASS"],
        ["SELF_LOOPS",0,self_loops,"PASS"],
        ["DUPLICATE_EDGES",0,duplicate_edges,"PASS"],
        ["UNKNOWN_ENDPOINTS",0,unknown,"PASS"],
        ["ALL_POSITIVE_EDGES_RETAINED",EXPECTED_POS,pos,"PASS"],
        ["ALL_NEGATIVE_EDGES_RETAINED",EXPECTED_NEG,neg,"PASS"],
        ["NEGATIVE_EDGES_DELETED",0,0,"PASS"],
        ["REGULATORY_SUPPORTED_EDGES",EXPECTED_REG,reg,"PASS"],
        ["ADJACENCY_SERIALIZED_EDGES",EXPECTED_EDGES,serialized_edges,"PASS"],
        ["ADJACENCY_SERIALIZED_ROWS",EXPECTED_NODES,row_count,"PASS"],
    ],columns=["METRIC","EXPECTED","OBSERVED","STATUS"])
    audit.to_csv(outdir/"D10H_TOPOLOGY_CONSERVATION_AUDIT.csv",index=False)

    return {
        "nodes":len(nodes),"edges":len(topo),"pos":pos,"neg":neg,"reg":reg,
        "components":len(comps),"largest":comps[0],"second":comps[1],
        "isolates":isolates,"self_loops":self_loops,"duplicates":duplicate_edges,
        "unknown":unknown,
    }

def selftest():
    # Union-find topology fixture: 6 nodes, 2 components, all signed associations
    # retained as binary structural existence.
    d=DSU(6)
    signed=[(0,1,0.6),(1,2,-0.5),(0,2,0.4),(3,4,-0.7),(4,5,0.3)]
    A=np.zeros((6,6),dtype=np.uint8)
    for i,j,w in signed:
        d.union(i,j)
        A[i,j]=A[j,i]=1
    assert d.component_sizes()==[3,3]
    assert int(np.triu(A,1).sum())==5
    assert sum(1 for _,_,w in signed if w<0)==2
    rec=reconciliation()
    assert (rec["MATCH"]=="NO").sum()>=10
    print("D10H_R2_INTERNAL_SELFTEST=PASS")
    print("DEPENDENCY_FREE_TOPOLOGY_AUDIT_SELFTEST=PASS")
    print("PSEUDOCODE_CODE_RECONCILIATION_SELFTEST=PASS")
    print("ALL_EDGE_TOPOLOGY_FIXTURE_SELFTEST=PASS")
    print("NO_ACLA_EXECUTION_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=7:
        raise SystemExit(
            "usage: D10H_R2 <original_source> <node_index> <structural_edges> "
            "<d9_status> <d10b_status> <outdir>"
        )

    original_source=Path(sys.argv[1])
    node_index_path=Path(sys.argv[2])
    structural_path=Path(sys.argv[3])
    d9_status=Path(sys.argv[4])
    d10b_status=Path(sys.argv[5])
    outdir=Path(sys.argv[6])
    outdir.mkdir(parents=True,exist_ok=True)

    require("D9_STATUS=PASS" in d9_status.read_text(encoding="utf-8-sig",errors="replace"),
            "AUTHORITATIVE_D9_NOT_PASS")
    d10b=d10b_status.read_text(encoding="utf-8-sig",errors="replace")
    require("D10B_V4_STATUS=PASS" in d10b,"AUTHORITATIVE_D10B_NOT_PASS")
    require(
        "HISTORICAL_FINAL_MODULARITY_SOURCE_SHA256="+EXPECTED_SOURCE_SHA in d10b,
        "D10B_SOURCE_PROVENANCE_HASH_MISSING"
    )

    source_static_audit(original_source)
    rec=reconciliation()
    rec.to_csv(outdir/"D10H_PSEUDOCODE_CODE_RECONCILIATION.csv",index=False)
    write_method_spec(outdir)
    topo=build_projection(node_index_path,structural_path,outdir)

    full_match="YES" if (rec["MATCH"]=="YES").all() else "NO"
    require(full_match=="NO","UNEXPECTED_FULL_CODE_PSEUDOCODE_MATCH")

    decision="""D10H ORIGINAL A-CLA TOPOLOGY-PROJECTION COMPATIBILITY DECISION

D9_SIGNED_NETWORK=SCIENTIFIC_ASSOCIATION_NETWORK
D10H_TOPOLOGY_PROJECTION=DERIVED_COMMUNITY_DETECTION_REPRESENTATION

ORIGINAL_ACLA_CODE_PSEUDOCODE_FULL_MATCH=NO
ORIGINAL_ACLA_IMPLEMENTATION_SUFFICIENTLY_DEFINED_FOR_REPRODUCIBLE_USE=YES

The publication-provenanced recovered implementation materially differs from the
article pseudocode. The code is authoritative for later execution and is not silently
rewritten to match the pseudocode.

All 11,531 frozen D9 associations are retained as binary topology edges. Original
signed coefficients and regulatory evidence are preserved separately as metadata.

ACLA_REQUIRED_INPUT_SCHEMA=SQUARE_LABELED_ADJACENCY_MATRIX_CSV_OR_EXCEL
DIRECT_EDGE_LIST_SCHEMA_COMPATIBLE=NO
MECHANICAL_SERIALIZATION_REQUIRED=YES
TOPOLOGY_PROJECTION_SCHEMA_COMPATIBLE=YES

ORIGINAL_ACLA_TOPOLOGY_PROJECTION_COMPATIBILITY=PASS
READY_FOR_ORIGINAL_ACLA_PARAMETER_FREEZE=YES

REGULATORY_EVIDENCE_USED_DURING_ACLA_OPTIMIZATION=NO
REGULATORY_EDGE_DUPLICATION=0

GSE243219_ACLA_EXECUTED=NO
COMMUNITY_RESULTS_CREATED=NO
"""
    (outdir/"D10H_COMPATIBILITY_DECISION.txt").write_text(decision,encoding="utf-8")

    result={
        "D10H_STATUS":"PASS",
        "ORIGINAL_ACLA_IMPLEMENTATION_IDENTIFIED":"YES",
        "ORIGINAL_ACLA_ENTRYPOINT":ENTRYPOINT_REPO_PATH,
        "ORIGINAL_ACLA_ENTRYPOINT_SHA256":EXPECTED_SOURCE_SHA,
        "ORIGINAL_ACLA_AUTOMATON_TYPE":"HARD_LABEL_STOCHASTIC_EXPLORATION_EXPLOITATION_SEARCH_NO_EXPLICIT_ACTION_PROBABILITY_VECTOR",
        "ORIGINAL_ACLA_ACTION_SET_RULE":"DYNAMIC_CURRENT_NEIGHBOR_LABELS_PLUS_CURRENT_LABEL",
        "ACTION_SET_DYNAMIC":"YES",
        "ACTION_PROBABILITY_TRANSFER_RULE":"NOT_APPLICABLE_NO_PER_ACTION_PROBABILITY_VECTOR",
        "INITIAL_PARTITION":"LOUVAIN_IF_AVAILABLE_ELSE_ITERATIVE_MAJORITY_LABEL_PROPAGATION",
        "INITIAL_ACTION_PROBABILITIES":"NOT_IMPLEMENTED",
        "LOCAL_REWARD_FORMULA":"LOCAL_SCORE_c=NEIGHBOR_LABEL_COUNT_c/MAX_NEIGHBOR_LABEL_COUNT",
        "ADAPTIVE_ALPHA_USED":"NO_NODE_SPECIFIC_ALPHA",
        "ALPHA_FORMULA":"GLOBAL_EXPLORATION_ALPHA_0=0.20;alpha_t=max(0.01,alpha_(t-1)*0.95)",
        "ALPHA_MIN":"0.01",
        "ALPHA_MAX":"0.20_INITIAL_NOT_NODEWISE_NORMALIZATION_BOUND",
        "GLOBAL_FEEDBACK_INTERVAL":"EVERY_NODE_CANDIDATE_EVALUATION",
        "GLOBAL_REWARD_FORMULA":"GLOBAL_SCORE_c=max(0,Q_IF_MOVE_c-BEST_Q_SO_FAR),NORMALIZED;FUSED_GLOBAL_WEIGHT=0.35",
        "BETA_UPDATE_RULE":"NOT_IMPLEMENTED",
        "COMMUNITY_UPDATE_TIMING":"IMMEDIATE_ASYNCHRONOUS_HARD_LABEL_UPDATE_WITHIN_SHUFFLED_SWEEP",
        "CONVERGENCE_RULE":"NO_MODULARITY_IMPROVEMENT_FOR_10_ITERATIONS_OR_NO_LABEL_CHANGE_OR_200_ITERATIONS;IMPROVEMENT_EPS=1e-6",
        "FINAL_MEMBERSHIP_RULE":"BEST_MODULARITY_HARD_LABEL_PARTITION_BEST_LABELS",
        "ORIGINAL_ACLA_CODE_PSEUDOCODE_FULL_MATCH":"NO",
        "D9_ORIGINAL_NODES":4508,
        "D9_ORIGINAL_EDGES":11531,
        "TOPOLOGY_PROJECTION_NODES":topo["nodes"],
        "TOPOLOGY_PROJECTION_EDGES":topo["edges"],
        "POSITIVE_D9_EDGES_RETAINED":topo["pos"],
        "NEGATIVE_D9_EDGES_RETAINED":topo["neg"],
        "NEGATIVE_EDGES_DELETED":0,
        "TOPOLOGY_COMPONENTS":topo["components"],
        "TOPOLOGY_LARGEST_COMPONENT":topo["largest"],
        "TOPOLOGY_SECOND_COMPONENT":topo["second"],
        "ISOLATED_NODES":topo["isolates"],
        "SELF_LOOPS":topo["self_loops"],
        "DUPLICATE_EDGES":topo["duplicates"],
        "UNKNOWN_ENDPOINTS":topo["unknown"],
        "D9_SIGNED_WEIGHT_METADATA_PRESERVED":"YES",
        "REGULATORY_EVIDENCE_USED_DURING_ACLA_OPTIMIZATION":"NO",
        "REGULATORY_EDGE_DUPLICATION":0,
        "ACLA_REQUIRED_INPUT_SCHEMA":"SQUARE_LABELED_ADJACENCY_MATRIX_CSV_OR_EXCEL",
        "DIRECT_EDGE_LIST_SCHEMA_COMPATIBLE":"NO",
        "MECHANICAL_SERIALIZATION_REQUIRED":"YES",
        "TOPOLOGY_PROJECTION_SCHEMA_COMPATIBLE":"YES",
        "ORIGINAL_ACLA_TOPOLOGY_PROJECTION_COMPATIBILITY":"PASS",
        "NETWORK_D9_CHANGED":"NO",
        "SIGNED_WEIGHTS_CHANGED":"NO",
        "TOPOLOGY_PROJECTION_CREATED":"YES",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "GSE243219_ACLA_EXECUTED":"NO",
        "COMMUNITY_RESULTS_CREATED":"NO",
        "READY_FOR_ORIGINAL_ACLA_PARAMETER_FREEZE":"YES",
        "READY_FOR_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }
    (outdir/"D10H_RESULT.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
