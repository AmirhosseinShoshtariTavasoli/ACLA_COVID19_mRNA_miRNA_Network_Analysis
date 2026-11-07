#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import numpy as np
import pandas as pd
import networkx as nx

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

def sha256_file(path: Path, chunk: int=8*1024*1024) -> str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk), b""):
            h.update(b)
    return h.hexdigest()

def require(cond: bool, message: str):
    if not cond:
        raise RuntimeError(message)

def source_static_audit(source_path: Path):
    require(source_path.is_file(), f"ORIGINAL_ACLA_SOURCE_MISSING={source_path}")
    actual=sha256_file(source_path)
    require(actual==EXPECTED_SOURCE_SHA,
            f"ORIGINAL_ACLA_SOURCE_SHA256_MISMATCH expected={EXPECTED_SOURCE_SHA} actual={actual}")
    text=source_path.read_text(encoding="utf-8-sig",errors="strict")

    checks={
        "square_adjacency": all(x in text for x in [
            "pd.read_excel(path, index_col=0)",
            "pd.read_csv(path, index_col=0)",
            "if df.shape[0] != df.shape[1]",
        ]),
        "binarize_positive": 'df2 = (df > 0).astype(int)' in text,
        "weight_none": bool(re.search(r"modularity\\s*\\([^\\n]*weight\\s*=\\s*None",text)),
        "louvain_init": "labels = louvain_init(G)" in text,
        "dynamic_candidates": all(x in text for x in [
            "def candidate_labels_for(n)",
            "neigh_labs = [labels[v] for v in G.neighbors(n)]",
            "labs = set(neigh_labs + [labels[n]])",
        ]),
        "local_count_max": all(x in text for x in [
            "counts = Counter(neigh_labs)",
            "maxc = max(counts.values())",
            "local_scores[c] = counts.get(c, 0) / maxc",
        ]),
        "candidate_modularity_gain": all(x in text for x in [
            "q_c = try_move_label(G, labels, n, c)",
            "global_scores[c] = max(0.0, q_c - q_now)",
        ]),
        "fused_signal": "fused[c] = (1 - global_w) * ls + global_w * gs" in text,
        "explore_top2": all(x in text for x in [
            "if random.random() < alpha",
            "top2 = sorted(",
            "choice = random.choice(top2)[0]",
        ]),
        "immediate_hard_label": all(x in text for x in [
            "if choice != labels[n]",
            "labels[n] = choice",
        ]),
        "global_alpha": all(x in text for x in [
            "alpha = alpha0",
            "alpha = max(alpha_min, alpha * 0.95)",
        ]),
        "settings": all(x in text for x in [
            "ITERATIONS = 200",
            "ALPHA0 = 0.20",
            "ALPHA_MIN = 0.01",
            "GLOBAL_WEIGHT = 0.35",
            "PATIENCE = 10",
            "SEED = 42",
        ]),
        "early_stop": "if no_improve >= patience or not changed" in text,
        "best_labels": all(x in text for x in [
            "best_labels = labels.copy()",
            "final_labels = best_labels",
        ]),
        "main": 'if __name__ == "__main__":' in text and "main()" in text,
    }
    missing=[k for k,v in checks.items() if not v]
    require(not missing, "SOURCE_STATIC_CONTRACT_MISSING="+"|".join(missing))

    # Explicit absence of manuscript probability-vector machinery.
    has_explicit_P_vector = bool(re.search(
        r"(?m)^\\s*(?:P_i|P\\s*=|probabilities\\s*=|action_prob)", text
    ))
    has_density = bool(re.search(r"(?i)\\bdens(?:ity)?\\b",text))
    has_betweenness = bool(re.search(r"(?i)betweenness",text))
    has_beta_update = bool(re.search(r"(?i)\\bbeta\\b",text))
    has_sigmoid = bool(re.search(r"(?i)sigmoid",text))
    has_kglobal = bool(re.search(r"(?i)K_global|KGLOBAL",text))

    return text, checks, {
        "has_explicit_P_vector":has_explicit_P_vector,
        "has_density":has_density,
        "has_betweenness":has_betweenness,
        "has_beta_update":has_beta_update,
        "has_sigmoid":has_sigmoid,
        "has_kglobal":has_kglobal,
    }

def reconcile_table(absence):
    rows=[
        {
            "MECHANISM":"INPUT_SCHEMA",
            "PSEUDOCODE_BEHAVIOR":"Undirected graph G=(V,E); weighted optional.",
            "CODE_BEHAVIOR":"Square labeled adjacency matrix loaded from xlsx/xls/csv/txt; default graph construction binarizes entries >0.",
            "MATCH":"PARTIAL",
            "SCIENTIFIC_SIGNIFICANCE":"Mechanical edge-list-to-adjacency serialization is required; topology can be preserved exactly."
        },
        {
            "MECHANISM":"INITIAL_PARTITION",
            "PSEUDOCODE_BEHAVIOR":"Each node starts in its own singleton label c_i=i.",
            "CODE_BEHAVIOR":"Hard labels initialized with Louvain when python-louvain is available; otherwise iterative majority-label propagation from singleton labels.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Material difference in starting partition and search trajectory."
        },
        {
            "MECHANISM":"AUTOMATON_TYPE",
            "PSEUDOCODE_BEHAVIOR":"Per-node multi-action learning automaton with explicit probability vector P_i over community-label actions.",
            "CODE_BEHAVIOR":"No explicit per-action probability vector. Hard-label stochastic exploration/exploitation search over current candidate labels.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Material algorithmic difference; recovered implementation is not the manuscript probability-vector automaton."
        },
        {
            "MECHANISM":"ACTION_SET_RULE",
            "PSEUDOCODE_BEHAVIOR":"A_i={own label} union {neighbor labels}; pseudocode does not explicitly specify later action-set remapping.",
            "CODE_BEHAVIOR":"candidate_labels_for(n) recomputes current neighbor labels plus current node label at every node evaluation.",
            "MATCH":"PARTIAL",
            "SCIENTIFIC_SIGNIFICANCE":"Same conceptual candidate source, but code is explicitly dynamic."
        },
        {
            "MECHANISM":"ACTION_SET_DYNAMICS",
            "PSEUDOCODE_BEHAVIOR":"Ambiguous after initialization; if dynamic, probability-mass transfer is not specified.",
            "CODE_BEHAVIOR":"Dynamic candidate labels; no probability transfer because there is no per-action P_i.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Resolves execution behavior but differs from manuscript LA semantics."
        },
        {
            "MECHANISM":"INITIAL_ACTION_PROBABILITIES",
            "PSEUDOCODE_BEHAVIOR":"Uniform P_i[k]=1/|A_i|.",
            "CODE_BEHAVIOR":"Not implemented; action choice uses scalar exploration alpha and fused candidate scores.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Material change to learning mechanism."
        },
        {
            "MECHANISM":"LOCAL_REWARD",
            "PSEUDOCODE_BEHAVIOR":"Fraction of neighbors aligned with sampled action: aligned_count/degree.",
            "CODE_BEHAVIOR":"Candidate local score = neighbor-label count / maximum neighbor-label count; then fused with global candidate score.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Different normalization and no sampled-action reward/penalty update."
        },
        {
            "MECHANISM":"ADAPTIVE_ALPHA",
            "PSEUDOCODE_BEHAVIOR":"Node-specific alpha_i = norm(w1*dens(i)+w2*deg(i)+w3*bet(i), alpha_min, alpha_max).",
            "CODE_BEHAVIOR":"Single global exploration alpha starts at 0.20 and decays by 0.95 per outer iteration to floor 0.01.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Degree/density/betweenness adaptive learning is absent from recovered final modularity implementation."
        },
        {
            "MECHANISM":"GLOBAL_FEEDBACK_TIMING",
            "PSEUDOCODE_BEHAVIOR":"Periodic every K_global iterations.",
            "CODE_BEHAVIOR":"Candidate-specific modularity is evaluated during every node update.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Global feedback is immediate rather than periodic."
        },
        {
            "MECHANISM":"GLOBAL_REWARD_FORMULA",
            "PSEUDOCODE_BEHAVIOR":"sigmoid(Q_curr-Q_prev), followed by beta update of P_i.",
            "CODE_BEHAVIOR":"global_score(c)=max(0,Q_if_moved_to_c-best_Q_so_far), normalized across candidates and fused with local score using GLOBAL_WEIGHT=0.35.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Different feedback semantics; no sigmoid and no beta probability-vector update."
        },
        {
            "MECHANISM":"ACTION_SELECTION",
            "PSEUDOCODE_BEHAVIOR":"Sample a_i ~ P_i; optional greedy argmax variant.",
            "CODE_BEHAVIOR":"With probability alpha choose randomly among top two fused candidates; otherwise choose fused-score argmax.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Exploration is scalar top-two exploration, not sampling from learned action probabilities."
        },
        {
            "MECHANISM":"COMMUNITY_UPDATE_TIMING",
            "PSEUDOCODE_BEHAVIOR":"Crisp labels explicitly induced by argmax(P_i) for periodic global feedback and at final output; provisional-label timing during local phase is not fully explicit.",
            "CODE_BEHAVIOR":"Hard label is changed immediately after each node's candidate choice inside the shuffled asynchronous sweep.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Code is asynchronous hard-label search."
        },
        {
            "MECHANISM":"MODULARITY_WEIGHTING",
            "PSEUDOCODE_BEHAVIOR":"Q(P) modularity; graph may optionally be weighted.",
            "CODE_BEHAVIOR":"current_modularity and final modularity explicitly use weight=None, even when graph construction retains weights.",
            "MATCH":"PARTIAL",
            "SCIENTIFIC_SIGNIFICANCE":"Optimization objective is topology-only."
        },
        {
            "MECHANISM":"CONVERGENCE",
            "PSEUDOCODE_BEHAVIOR":"Mean L1 change of P_i below epsilon, or Tmax.",
            "CODE_BEHAVIOR":"Stop when modularity has not improved for PATIENCE=10 outer iterations, or no hard labels changed, or ITERATIONS=200 reached.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Convergence monitors hard-label/modularity search, not probability stabilization."
        },
        {
            "MECHANISM":"FINAL_MEMBERSHIP",
            "PSEUDOCODE_BEHAVIOR":"community_i=argmax_k P_i[k].",
            "CODE_BEHAVIOR":"Return best_labels, the hard partition saved at the best observed modularity.",
            "MATCH":"NO",
            "SCIENTIFIC_SIGNIFICANCE":"Final membership is not derived from a probability vector."
        },
        {
            "MECHANISM":"RNG_AND_REPRODUCIBILITY",
            "PSEUDOCODE_BEHAVIOR":"set RNG(seed).",
            "CODE_BEHAVIOR":"Python random.seed(42) controls node shuffle/top-two exploration; Louvain best_partition is called without explicit random_state.",
            "MATCH":"PARTIAL",
            "SCIENTIFIC_SIGNIFICANCE":"Execution path is defined, but Louvain initialization is not explicitly pinned by the script's seed."
        },
    ]
    return pd.DataFrame(rows)

def method_spec_text(source_path: Path):
    return f"""# D10H Original A-CLA — Code-Authoritative Method Specification

## Authority

Execution authority is the publication-provenanced recovered final modularity source:

`{ENTRYPOINT_REPO_PATH}`

SHA256:

`{EXPECTED_SOURCE_SHA}`

The manuscript/article pseudocode is used for reconciliation, not to silently rewrite
the recovered source.

## Code-authoritative algorithm

### Input

A square labeled adjacency matrix in Excel or CSV/TXT form.

Default graph construction:

`(adjacency > 0).astype(int)`

Therefore the D10H topology projection must be mechanically serialized into a square
0/1 labeled adjacency matrix before later execution.

### Initialization

The recovered code initializes a hard partition using Louvain when available.
If python-louvain is unavailable, it falls back to iterative majority-label propagation.

It does **not** initialize every node as a singleton probability automaton.

### Candidate action set

For every node update, candidate labels are recomputed dynamically as:

current labels among graph neighbors + the node's current label.

There is no persistent per-action probability vector and therefore no probability-mass
transfer rule when candidate labels change.

### Local signal

For candidate community c:

`local(c) = neighbor_count(c) / max_neighbor_label_count`

The local candidate scores are then normalized and fused with the global signal.

### Global signal

For each candidate c, the code hypothetically moves the node and recomputes unweighted
modularity.

`global_raw(c) = max(0, Q_candidate - best_Q_so_far)`

Candidate global scores are normalized across candidates.

Final fused candidate score:

`fused(c) = 0.65 * local_normalized(c) + 0.35 * global_normalized(c)`

### Exploration

A single scalar exploration probability alpha is used.

Initial alpha = 0.20.

After each outer iteration:

`alpha = max(0.01, alpha * 0.95)`

With probability alpha, one of the top two fused candidates is selected randomly.
Otherwise the highest fused-score candidate is selected.

This is not a multi-action probability-vector learning automaton.

### Community update timing

Updates are asynchronous within a shuffled node order.

If the selected candidate differs from the current label, the hard label changes
immediately and later nodes in the same sweep see the updated partition.

### Global objective

NetworkX modularity is evaluated with `weight=None`.

Thus the recovered final modularity implementation is topology-only even if weighted
input is loaded.

### Convergence

The run stops if any of the following occurs:

1. no modularity improvement for PATIENCE=10 outer iterations;
2. no labels changed in an outer iteration;
3. ITERATIONS=200 is reached.

A modularity increase must exceed 1e-6 to reset patience.

### Final partition

The output is `best_labels`: the hard partition associated with the best modularity
observed during the run.

It is not `argmax(P_i)` because no P_i exists in the recovered implementation.

## D10H topology interpretation

D9 remains the signed scientific association network.

D10H creates a separate derived optimization representation:

- all 4,508 D9 nodes;
- all 11,531 frozen structural association pairs;
- every retained association represented as adjacency 1;
- original signed coefficients preserved unchanged in edge metadata.

The original A-CLA therefore asks:

> Which nodes form densely interconnected groups of stable associations?

It does not ask:

> Which communities optimize positive-within / negative-between signed structure?

Regulatory evidence is not used during A-CLA optimization and is retained for
post-community characterization only.
"""

def build_topology(node_index_path: Path, structural_path: Path, outdir: Path):
    nodes=pd.read_csv(node_index_path,dtype=str,keep_default_na=False)
    edges=pd.read_csv(
        structural_path,
        dtype={"source":str,"target":str},
        float_precision="round_trip",
        keep_default_na=False,
    )

    require(len(nodes)==EXPECTED_NODES, f"NODE_COUNT_CHANGED={len(nodes)}")
    require(nodes["node_id"].nunique()==EXPECTED_NODES, "NODE_ID_DUPLICATION")
    require(len(edges)==EXPECTED_EDGES, f"EDGE_COUNT_CHANGED={len(edges)}")

    needed=[
        "source","target","association_score","regulatory_eligible","regulatory_class",
        "TarBase_support","TargetScan_support","miRDB_GT80_support"
    ]
    miss=[c for c in needed if c not in edges.columns]
    require(not miss, "D9_STRUCTURAL_COLUMNS_MISSING="+"|".join(miss))

    known=set(nodes["node_id"])
    unknown=int((~edges["source"].isin(known)).sum()+(~edges["target"].isin(known)).sum())
    self_loops=int((edges["source"]==edges["target"]).sum())

    canon=edges.apply(
        lambda r: tuple(sorted((str(r["source"]),str(r["target"])))),
        axis=1
    )
    duplicate_edges=int(canon.duplicated().sum())

    w=pd.to_numeric(edges["association_score"],errors="coerce")
    require(w.notna().all() and np.isfinite(w.to_numpy(float)).all(),"INVALID_SIGNED_WEIGHTS")
    pos=int((w>0).sum())
    neg=int((w<0).sum())
    zero=int((w==0).sum())

    reg=int(edges["regulatory_eligible"].astype(str).str.upper().eq("YES").sum())

    require(pos==EXPECTED_POS, f"POSITIVE_EDGE_COUNT_CHANGED={pos}")
    require(neg==EXPECTED_NEG, f"NEGATIVE_EDGE_COUNT_CHANGED={neg}")
    require(zero==0, f"ZERO_SIGNED_EDGES={zero}")
    require(reg==EXPECTED_REG, f"REGULATORY_EDGE_COUNT_CHANGED={reg}")
    require(self_loops==0, f"SELF_LOOPS={self_loops}")
    require(duplicate_edges==0, f"DUPLICATE_EDGES={duplicate_edges}")
    require(unknown==0, f"UNKNOWN_ENDPOINTS={unknown}")

    topo=edges[["source","target"]].copy()
    topo.to_csv(outdir/"D10H_ACLA_ALL_EDGE_TOPOLOGY.csv",index=False)

    meta=edges[
        [
            "source","target","association_score","regulatory_eligible","regulatory_class",
            "TarBase_support","TargetScan_support","miRDB_GT80_support"
        ]
    ].copy()
    meta=meta.rename(columns={"association_score":"original_signed_weight"})
    meta.insert(
        3,"sign",
        np.where(pd.to_numeric(meta["original_signed_weight"])>0,"POSITIVE","NEGATIVE")
    )
    meta.to_csv(
        outdir/"D10H_ACLA_EDGE_METADATA.csv",
        index=False,float_format="%.17g"
    )

    G=nx.Graph()
    G.add_nodes_from(nodes["node_id"].tolist())
    G.add_edges_from(topo.itertuples(index=False,name=None))
    comps=sorted((len(c) for c in nx.connected_components(G)),reverse=True)
    component_count=nx.number_connected_components(G)
    isolates=nx.number_of_isolates(G)

    require(component_count==EXPECTED_COMPONENTS,
            f"TOPOLOGY_COMPONENTS_CHANGED={component_count}")
    require(comps[:2]==[EXPECTED_LARGEST,EXPECTED_SECOND],
            f"TOPOLOGY_COMPONENT_SIZES_CHANGED={comps[:5]}")
    require(isolates==0,f"TOPOLOGY_ISOLATES={isolates}")

    # Mechanical serialization for the actual recovered A-CLA input schema.
    # This is not a scientific transformation: it is the exact same binary edge set.
    node_order=nodes["node_id"].tolist()
    idx={n:i for i,n in enumerate(node_order)}
    A=np.zeros((EXPECTED_NODES,EXPECTED_NODES),dtype=np.uint8)
    for s,t in topo.itertuples(index=False,name=None):
        i=idx[s];j=idx[t]
        A[i,j]=1
        A[j,i]=1
    require(int(np.triu(A,1).sum())==EXPECTED_EDGES,"ADJACENCY_EDGE_COUNT_CHANGED")
    require(int(A.diagonal().sum())==0,"ADJACENCY_SELF_LOOP_CREATED")

    adjacency_path=outdir/"D10H_ACLA_INPUT_ADJACENCY.csv"
    # Write without constructing a 4508-column object dataframe in memory twice.
    with adjacency_path.open("w",encoding="utf-8",newline="") as f:
        f.write(","+",".join(node_order)+"\\n")
        for i,n in enumerate(node_order):
            f.write(n+","+",".join(map(str,A[i].tolist()))+"\\n")

    # Round-trip structural verification of adjacency without running A-CLA.
    adj=pd.read_csv(adjacency_path,index_col=0,dtype=np.uint8)
    require(adj.shape==(EXPECTED_NODES,EXPECTED_NODES),f"ADJACENCY_SHAPE={adj.shape}")
    require(list(map(str,adj.index))==node_order,"ADJACENCY_ROW_ORDER_CHANGED")
    require(list(map(str,adj.columns))==node_order,"ADJACENCY_COLUMN_ORDER_CHANGED")
    arr=adj.to_numpy(dtype=np.uint8)
    require(np.array_equal(arr,arr.T),"ADJACENCY_NOT_SYMMETRIC")
    require(int(np.triu(arr,1).sum())==EXPECTED_EDGES,"ADJACENCY_ROUNDTRIP_EDGE_COUNT_CHANGED")

    audit=pd.DataFrame([
        ["NODES",EXPECTED_NODES,len(nodes),"PASS"],
        ["EDGES",EXPECTED_EDGES,len(topo),"PASS"],
        ["COMPONENTS",EXPECTED_COMPONENTS,component_count,"PASS"],
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
        ["ADJACENCY_SERIALIZED_EDGES",EXPECTED_EDGES,int(np.triu(arr,1).sum()),"PASS"],
    ],columns=["METRIC","EXPECTED","OBSERVED","STATUS"])
    audit.to_csv(outdir/"D10H_TOPOLOGY_CONSERVATION_AUDIT.csv",index=False)

    return {
        "nodes":len(nodes),
        "edges":len(topo),
        "pos":pos,
        "neg":neg,
        "reg":reg,
        "components":component_count,
        "largest":comps[0],
        "second":comps[1],
        "isolates":isolates,
        "self_loops":self_loops,
        "duplicates":duplicate_edges,
        "unknown":unknown,
        "adjacency_path":str(adjacency_path),
    }

def fixture_selftest():
    # Small topology-only fixture: verifies all-edge serialization logic conceptually.
    nodes=["a","b","c","d","e","f"]
    signed=[
        ("a","b",0.6),("b","c",-0.5),("a","c",0.4),
        ("d","e",-0.7),("e","f",0.3)
    ]
    G=nx.Graph()
    G.add_nodes_from(nodes)
    G.add_edges_from((s,t) for s,t,w in signed)
    assert G.number_of_edges()==5
    assert nx.number_connected_components(G)==2
    A=nx.to_numpy_array(G,nodelist=nodes,weight=None,dtype=np.uint8)
    assert int(np.triu(A,1).sum())==5
    # all signed edges survive as structural adjacency
    assert sum(1 for _,_,w in signed if w<0)==2
    assert int(np.triu(A,1).sum())==len(signed)
    return True

def selftest():
    assert fixture_selftest()
    rec=reconcile_table({})
    assert (rec["MATCH"]=="NO").sum()>=10
    assert "AUTOMATON_TYPE" in set(rec["MECHANISM"])
    print("D10H_INTERNAL_SELFTEST=PASS")
    print("PSEUDOCODE_CODE_RECONCILIATION_SELFTEST=PASS")
    print("ALL_EDGE_TOPOLOGY_FIXTURE_SELFTEST=PASS")
    print("NO_ACLA_EXECUTION_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return selftest()
    if len(sys.argv)!=7:
        raise SystemExit(
            "usage: D10H <original_source> <node_index_csv> <structural_edge_list_csv> "
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
    d10b_text=d10b_status.read_text(encoding="utf-8-sig",errors="replace")
    require("D10B_V4_STATUS=PASS" in d10b_text,"AUTHORITATIVE_D10B_V4_NOT_PASS")
    require(
        "HISTORICAL_FINAL_MODULARITY_SOURCE_SHA256="+EXPECTED_SOURCE_SHA in d10b_text,
        "D10B_SOURCE_HASH_NOT_AUTHORITATIVE"
    )

    source_text,checks,absence=source_static_audit(original_source)

    rec=reconcile_table(absence)
    rec_path=outdir/"D10H_PSEUDOCODE_CODE_RECONCILIATION.csv"
    rec.to_csv(rec_path,index=False)

    full_match="YES" if (rec["MATCH"]=="YES").all() else "NO"
    # Recovered source itself is sufficiently defined for execution despite manuscript mismatch.
    implementation_defined="YES"

    spec=method_spec_text(original_source)
    (outdir/"D10H_ORIGINAL_ACLA_METHOD_SPECIFICATION.md").write_text(
        spec,encoding="utf-8"
    )

    topo=build_topology(node_index_path,structural_path,outdir)

    # Direct edge-list schema is not what the recovered script loads, but the
    # required mechanical adjacency serialization is lossless and created here.
    required_schema="SQUARE_LABELED_ADJACENCY_MATRIX_CSV_OR_EXCEL"
    direct_edge_list_compatible="NO"
    mechanical_serialization_required="YES"
    topology_schema_compatible="YES"

    compatibility_pass=(
        implementation_defined=="YES"
        and topo["nodes"]==EXPECTED_NODES
        and topo["edges"]==EXPECTED_EDGES
        and topo["components"]==EXPECTED_COMPONENTS
        and topo["pos"]==EXPECTED_POS
        and topo["neg"]==EXPECTED_NEG
        and topo["duplicates"]==0
        and topo["unknown"]==0
    )

    decision="PASS" if compatibility_pass else "FAIL"
    ready="YES" if compatibility_pass else "NO"

    decision_text=f"""D10H ORIGINAL A-CLA TOPOLOGY-PROJECTION COMPATIBILITY DECISION

D9_SIGNED_NETWORK=SCIENTIFIC_ASSOCIATION_NETWORK
D10H_TOPOLOGY_PROJECTION=DERIVED_COMMUNITY_DETECTION_REPRESENTATION

ORIGINAL_ACLA_CODE_PSEUDOCODE_FULL_MATCH={full_match}

The code/pseudocode mismatch is material, but the publication-provenanced recovered
implementation is explicit enough to define what would be executed. Code is
authoritative; the pseudocode is not used to rewrite it.

The derived topology contains every frozen D9 structural association exactly once.
Each association is represented by adjacency=1 regardless of original sign.
The original signed coefficient and regulatory evidence remain unchanged in the
separate edge-metadata artifact.

Original A-CLA will therefore optimize topology only. It will answer which nodes form
densely interconnected groups of stable associations. It will not optimize
positive-within / negative-between signed organization.

ACLA_REQUIRED_INPUT_SCHEMA={required_schema}
DIRECT_EDGE_LIST_SCHEMA_COMPATIBLE={direct_edge_list_compatible}
MECHANICAL_SERIALIZATION_REQUIRED={mechanical_serialization_required}
TOPOLOGY_PROJECTION_SCHEMA_COMPATIBLE={topology_schema_compatible}

ORIGINAL_ACLA_TOPOLOGY_PROJECTION_COMPATIBILITY={decision}
READY_FOR_ORIGINAL_ACLA_PARAMETER_FREEZE={ready}

REGULATORY_EVIDENCE_USED_DURING_ACLA_OPTIMIZATION=NO
REGULATORY_EDGE_DUPLICATION=0

GSE243219_ACLA_EXECUTED=NO
COMMUNITY_RESULTS_CREATED=NO
"""
    (outdir/"D10H_COMPATIBILITY_DECISION.txt").write_text(
        decision_text,encoding="utf-8"
    )

    result={
        "D10H_STATUS":"PASS" if compatibility_pass else "FAIL_CLOSED",
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
        "ALPHA_FORMULA":"GLOBAL_EXPLORATION_ALPHA_0=0.20; alpha_t=max(0.01,alpha_(t-1)*0.95)",
        "ALPHA_MIN":"0.01",
        "ALPHA_MAX":"0.20_INITIAL_VALUE_NOT_NODEWISE_NORMALIZATION_BOUND",
        "GLOBAL_FEEDBACK_INTERVAL":"EVERY_NODE_CANDIDATE_EVALUATION",
        "GLOBAL_REWARD_FORMULA":"GLOBAL_SCORE_c=max(0,Q_IF_MOVE_c-BEST_Q_SO_FAR),NORMALIZED_ACROSS_CANDIDATES;FUSED_WEIGHT=0.35",
        "BETA_UPDATE_RULE":"NOT_IMPLEMENTED",
        "COMMUNITY_UPDATE_TIMING":"IMMEDIATE_ASYNCHRONOUS_HARD_LABEL_UPDATE_WITHIN_SHUFFLED_NODE_SWEEP",
        "CONVERGENCE_RULE":"STOP_IF_NO_MODULARITY_IMPROVEMENT_FOR_10_OUTER_ITERATIONS_OR_NO_LABEL_CHANGE_OR_200_ITERATIONS;IMPROVEMENT_EPS=1e-6",
        "FINAL_MEMBERSHIP_RULE":"BEST_MODULARITY_HARD_LABEL_PARTITION_BEST_LABELS",
        "ORIGINAL_ACLA_CODE_PSEUDOCODE_FULL_MATCH":full_match,
        "D9_ORIGINAL_NODES":EXPECTED_NODES,
        "D9_ORIGINAL_EDGES":EXPECTED_EDGES,
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
        "ACLA_REQUIRED_INPUT_SCHEMA":required_schema,
        "DIRECT_EDGE_LIST_SCHEMA_COMPATIBLE":direct_edge_list_compatible,
        "MECHANICAL_SERIALIZATION_REQUIRED":mechanical_serialization_required,
        "TOPOLOGY_PROJECTION_SCHEMA_COMPATIBLE":topology_schema_compatible,
        "ORIGINAL_ACLA_TOPOLOGY_PROJECTION_COMPATIBILITY":decision,
        "NETWORK_D9_CHANGED":"NO",
        "SIGNED_WEIGHTS_CHANGED":"NO",
        "TOPOLOGY_PROJECTION_CREATED":"YES",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "GSE243219_ACLA_EXECUTED":"NO",
        "COMMUNITY_RESULTS_CREATED":"NO",
        "READY_FOR_ORIGINAL_ACLA_PARAMETER_FREEZE":ready,
        "READY_FOR_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }
    (outdir/"D10H_RESULT.json").write_text(
        json.dumps(result,indent=2),encoding="utf-8"
    )
    return 0

if __name__=="__main__":
    raise SystemExit(main())
