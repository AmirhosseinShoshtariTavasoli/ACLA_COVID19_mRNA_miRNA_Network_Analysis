#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import json
import math
import sys
from collections import Counter, defaultdict
from pathlib import Path

import pandas as pd

EXPECTED_NODES=4508
EXPECTED_EDGES=11531
EXPECTED_COMMUNITIES=8
EXPECTED_POS=5225
EXPECTED_NEG=6306
EXPECTED_REG=1978
EXPECTED_ASSOC_ONLY=9553

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk), b""):
            h.update(b)
    return h.hexdigest()

def require(cond,msg):
    if not cond:
        raise RuntimeError(msg)

def norm_yes(x):
    return str(x).strip().upper()=="YES"

def main():
    if len(sys.argv)!=8:
        raise SystemExit(
            "usage: D10K <d10j_status> <assignments_csv> <node_index_csv> "
            "<edge_metadata_csv> <topology_csv> <d10j_manifest> <outdir>"
        )

    d10j_status=Path(sys.argv[1])
    assignments_path=Path(sys.argv[2])
    node_index_path=Path(sys.argv[3])
    edge_meta_path=Path(sys.argv[4])
    topology_path=Path(sys.argv[5])
    d10j_manifest=Path(sys.argv[6])
    outdir=Path(sys.argv[7])
    outdir.mkdir(parents=True,exist_ok=True)

    status_text=d10j_status.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10J_STATUS=PASS",
        "GSE243219_ACLA_EXECUTED=YES",
        "COMMUNITY_RESULTS_CREATED=YES",
        "COMMUNITIES=8",
        "POSTEXECUTION_TECHNICAL_VALIDATION=PASS",
        "READY_FOR_D10K_POSTHOC_COMMUNITY_CHARACTERIZATION=YES",
        "BIOLOGICAL_INTERPRETATION_EXECUTED=NO",
    ]:
        require(tok in status_text,f"D10J_AUTHORITY_TOKEN_MISSING={tok}")

    # D10J manifest integrity.
    manifest=pd.read_csv(d10j_manifest,dtype=str,keep_default_na=False)
    bad=0
    for row in manifest.itertuples(index=False):
        p=Path(row.full_path)
        if not p.is_file():
            bad+=1
            continue
        if int(p.stat().st_size)!=int(row.size_bytes):
            bad+=1
            continue
        if sha256_file(p)!=str(row.SHA256).lower():
            bad+=1
    require(bad==0,f"D10J_MANIFEST_HASH_MISMATCHES={bad}")

    assignments=pd.read_csv(assignments_path,dtype=str,keep_default_na=False)
    nodes=pd.read_csv(node_index_path,dtype=str,keep_default_na=False)
    edges=pd.read_csv(edge_meta_path,float_precision="round_trip",keep_default_na=False)
    topo=pd.read_csv(topology_path,dtype=str,keep_default_na=False)

    require(len(assignments)==EXPECTED_NODES,f"ASSIGNMENT_ROWS={len(assignments)}")
    require(assignments["node_id"].nunique()==EXPECTED_NODES,"ASSIGNMENT_DUPLICATE_NODES")
    require(assignments["canonical_community_id"].nunique()==EXPECTED_COMMUNITIES,
            f"COMMUNITY_COUNT={assignments['canonical_community_id'].nunique()}")
    require(len(nodes)==EXPECTED_NODES,f"NODE_INDEX_ROWS={len(nodes)}")
    require(nodes["node_id"].nunique()==EXPECTED_NODES,"NODE_INDEX_DUPLICATE_NODES")
    require(set(assignments["node_id"])==set(nodes["node_id"]),"ASSIGNMENT_NODE_SET_MISMATCH")
    require(len(edges)==EXPECTED_EDGES,f"EDGE_METADATA_ROWS={len(edges)}")
    require(len(topo)==EXPECTED_EDGES,f"TOPOLOGY_ROWS={len(topo)}")

    # Required node type column from D9 node_index.
    type_col=None
    for c in ["node_type","type","entity_type"]:
        if c in nodes.columns:
            type_col=c
            break
    require(type_col is not None,"NODE_TYPE_COLUMN_NOT_FOUND")

    merged_nodes=assignments.merge(nodes[["node_id",type_col]],on="node_id",how="left",validate="one_to_one")
    require(merged_nodes[type_col].notna().all(),"NODE_TYPE_MISSING_AFTER_JOIN")
    merged_nodes["community"]=merged_nodes["canonical_community_id"].astype(int)

    comm_of=dict(zip(merged_nodes["node_id"],merged_nodes["community"]))
    type_of=dict(zip(merged_nodes["node_id"],merged_nodes[type_col].str.lower()))

    # Normalize edge metadata.
    for c in ["source","target","original_signed_weight","sign","regulatory_eligible","regulatory_class"]:
        require(c in edges.columns,f"EDGE_METADATA_COLUMN_MISSING={c}")

    weights=pd.to_numeric(edges["original_signed_weight"],errors="coerce")
    require(weights.notna().all(),"EDGE_WEIGHT_PARSE_FAILURE")
    require(((weights>0).sum(),(weights<0).sum())==(EXPECTED_POS,EXPECTED_NEG),
            f"GLOBAL_SIGN_COUNTS_CHANGED pos={(weights>0).sum()} neg={(weights<0).sum()}")

    reg_mask=edges["regulatory_eligible"].astype(str).str.upper().eq("YES")
    require(int(reg_mask.sum())==EXPECTED_REG,f"GLOBAL_REG_COUNT={int(reg_mask.sum())}")
    require(int((~reg_mask).sum())==EXPECTED_ASSOC_ONLY,f"GLOBAL_ASSOC_ONLY_COUNT={int((~reg_mask).sum())}")

    # Annotate fixed communities on each edge.
    e=edges.copy()
    e["source_community"]=e["source"].map(comm_of)
    e["target_community"]=e["target"].map(comm_of)
    require(e["source_community"].notna().all() and e["target_community"].notna().all(),
            "EDGE_ENDPOINT_COMMUNITY_MISSING")
    e["source_community"]=e["source_community"].astype(int)
    e["target_community"]=e["target_community"].astype(int)
    e["within_community"]=e["source_community"].eq(e["target_community"])
    e["edge_scope"]=e["within_community"].map({True:"WITHIN",False:"BETWEEN"})
    e["is_positive"]=pd.to_numeric(e["original_signed_weight"])>0
    e["is_negative"]=pd.to_numeric(e["original_signed_weight"])<0
    e["is_regulatory"]=reg_mask.to_numpy()

    # Global descriptive signed/regulatory mixing.
    global_rows=[]
    for name,mask in [
        ("ALL",pd.Series([True]*len(e))),
        ("POSITIVE",e["is_positive"]),
        ("NEGATIVE",e["is_negative"]),
        ("REGULATORY",e["is_regulatory"]),
        ("ASSOCIATION_ONLY",~e["is_regulatory"]),
    ]:
        total=int(mask.sum())
        within=int((mask & e["within_community"]).sum())
        between=total-within
        global_rows.append([
            name,total,within,between,
            (within/total if total else float("nan")),
            (between/total if total else float("nan")),
        ])
    global_df=pd.DataFrame(global_rows,columns=[
        "edge_class","total_edges","within_community_edges","between_community_edges",
        "within_fraction","between_fraction"
    ])
    global_df.to_csv(outdir/"D10K_GLOBAL_EDGE_MIXING.csv",index=False,float_format="%.17g")

    # Per-community node composition and internal edge composition.
    rows=[]
    for cid in sorted(merged_nodes["community"].unique()):
        ndf=merged_nodes[merged_nodes["community"]==cid]
        internal=e[e["within_community"] & (e["source_community"]==cid)]
        incident=e[(e["source_community"]==cid) | (e["target_community"]==cid)]
        boundary=incident[~incident["within_community"]]

        m_count=int(ndf[type_col].str.lower().str.contains("mrna").sum())
        mir_count=int(ndf[type_col].str.lower().str.contains("mirna").sum())

        pos_internal=int(internal["is_positive"].sum())
        neg_internal=int(internal["is_negative"].sum())
        reg_internal=int(internal["is_regulatory"].sum())
        assoc_internal=len(internal)-reg_internal

        pos_boundary=int(boundary["is_positive"].sum())
        neg_boundary=int(boundary["is_negative"].sum())
        reg_boundary=int(boundary["is_regulatory"].sum())
        assoc_boundary=len(boundary)-reg_boundary

        rows.append({
            "community_id":int(cid),
            "nodes_total":len(ndf),
            "mrna_nodes":m_count,
            "mirna_nodes":mir_count,
            "other_node_types":len(ndf)-m_count-mir_count,
            "internal_edges":len(internal),
            "internal_positive_edges":pos_internal,
            "internal_negative_edges":neg_internal,
            "internal_regulatory_edges":reg_internal,
            "internal_association_only_edges":assoc_internal,
            "boundary_edges":len(boundary),
            "boundary_positive_edges":pos_boundary,
            "boundary_negative_edges":neg_boundary,
            "boundary_regulatory_edges":reg_boundary,
            "boundary_association_only_edges":assoc_boundary,
            "internal_positive_fraction":pos_internal/len(internal) if len(internal) else float("nan"),
            "internal_negative_fraction":neg_internal/len(internal) if len(internal) else float("nan"),
            "internal_regulatory_fraction":reg_internal/len(internal) if len(internal) else float("nan"),
        })
    comm_df=pd.DataFrame(rows).sort_values("community_id")
    comm_df.to_csv(outdir/"D10K_COMMUNITY_CHARACTERIZATION.csv",index=False,float_format="%.17g")

    # Regulatory class summary, descriptive only.
    reg=e[e["is_regulatory"]].copy()
    reg_class=(
        reg.groupby(["edge_scope","regulatory_class"],dropna=False)
        .size().reset_index(name="edge_count")
        .sort_values(["edge_scope","edge_count"],ascending=[True,False])
    )
    reg_class.to_csv(outdir/"D10K_REGULATORY_CLASS_SUMMARY.csv",index=False)

    # Community-pair mixing matrix / long-form edge counts.
    pair_rows=[]
    e["community_a"]=e[["source_community","target_community"]].min(axis=1)
    e["community_b"]=e[["source_community","target_community"]].max(axis=1)
    for (a,b),g in e.groupby(["community_a","community_b"]):
        pair_rows.append({
            "community_a":int(a),
            "community_b":int(b),
            "same_community":bool(a==b),
            "edges_total":len(g),
            "positive_edges":int(g["is_positive"].sum()),
            "negative_edges":int(g["is_negative"].sum()),
            "regulatory_edges":int(g["is_regulatory"].sum()),
            "association_only_edges":int((~g["is_regulatory"]).sum()),
        })
    pair_df=pd.DataFrame(pair_rows).sort_values(["community_a","community_b"])
    pair_df.to_csv(outdir/"D10K_COMMUNITY_PAIR_EDGE_SUMMARY.csv",index=False)

    # Edge-level characterized file for future downstream biological work.
    characterized=e[[
        "source","target","original_signed_weight","sign","regulatory_eligible","regulatory_class",
        "TarBase_support","TargetScan_support","miRDB_GT80_support",
        "source_community","target_community","edge_scope"
    ]].copy()
    characterized.to_csv(outdir/"D10K_CHARACTERIZED_EDGE_METADATA.csv",index=False,float_format="%.17g")

    # Node-level file.
    merged_nodes.rename(columns={type_col:"node_type"}).to_csv(
        outdir/"D10K_CHARACTERIZED_NODES.csv",index=False
    )

    # Internal consistency checks.
    internal_total=int(e["within_community"].sum())
    between_total=len(e)-internal_total
    require(int(global_df.loc[global_df["edge_class"]=="ALL","within_community_edges"].iloc[0])==internal_total,
            "GLOBAL_INTERNAL_COUNT_MISMATCH")
    require(int(comm_df["internal_edges"].sum())==internal_total,
            "COMMUNITY_INTERNAL_EDGE_SUM_MISMATCH")
    require(int(pair_df["edges_total"].sum())==EXPECTED_EDGES,
            "PAIR_EDGE_SUM_MISMATCH")

    summary={
        "D10K_STATUS":"PASS",
        "COMMUNITIES":EXPECTED_COMMUNITIES,
        "NODES":EXPECTED_NODES,
        "EDGES":EXPECTED_EDGES,
        "POSITIVE_EDGES":EXPECTED_POS,
        "NEGATIVE_EDGES":EXPECTED_NEG,
        "REGULATORY_EDGES":EXPECTED_REG,
        "ASSOCIATION_ONLY_EDGES":EXPECTED_ASSOC_ONLY,
        "WITHIN_COMMUNITY_EDGES":internal_total,
        "BETWEEN_COMMUNITY_EDGES":between_total,
        "POSITIVE_WITHIN_COMMUNITY_EDGES":int((e["is_positive"] & e["within_community"]).sum()),
        "POSITIVE_BETWEEN_COMMUNITY_EDGES":int((e["is_positive"] & ~e["within_community"]).sum()),
        "NEGATIVE_WITHIN_COMMUNITY_EDGES":int((e["is_negative"] & e["within_community"]).sum()),
        "NEGATIVE_BETWEEN_COMMUNITY_EDGES":int((e["is_negative"] & ~e["within_community"]).sum()),
        "REGULATORY_WITHIN_COMMUNITY_EDGES":int((e["is_regulatory"] & e["within_community"]).sum()),
        "REGULATORY_BETWEEN_COMMUNITY_EDGES":int((e["is_regulatory"] & ~e["within_community"]).sum()),
        "SIGNED_EDGE_CHARACTERIZATION_EXECUTED":"YES_DESCRIPTIVE_ONLY",
        "REGULATORY_CHARACTERIZATION_EXECUTED":"YES_DESCRIPTIVE_ONLY",
        "BIOLOGICAL_INTERPRETATION_EXECUTED":"NO",
        "ENRICHMENT_EXECUTED":"NO",
        "HUB_ANALYSIS_EXECUTED":"NO",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "COMMUNITY_ASSIGNMENTS_CHANGED":"NO",
        "D9_FILES_MODIFIED":"NO",
        "D10H_TOPOLOGY_MODIFIED":"NO",
        "READY_FOR_D10L_BIOLOGICAL_CHARACTERIZATION":"YES",
        "READY_FOR_BIOLOGICAL_INTERPRETATION":"NO",
        "STOP":"YES",
    }
    (outdir/"D10K_SUMMARY.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
