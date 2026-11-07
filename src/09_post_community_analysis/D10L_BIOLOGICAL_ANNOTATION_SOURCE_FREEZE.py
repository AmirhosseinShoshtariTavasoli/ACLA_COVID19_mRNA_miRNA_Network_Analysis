#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_NODES=4508
EXPECTED_MRNA=4467
EXPECTED_MIRNA=41
PRIMARY_FDR_THRESHOLD=0.05
SECONDARY_ABS_LOGFC_THRESHOLD=1.0

FILES = [
    ("mRNA","COV_vs_H","D6_MRNA_COV_vs_H_FULL_RESULTS.csv.gz"),
    ("mRNA","P_vs_H","D6_MRNA_P_vs_H_FULL_RESULTS.csv.gz"),
    ("mRNA","COV_vs_P","D6_MRNA_COV_vs_P_FULL_RESULTS.csv.gz"),
    ("miRNA","COV_vs_H","D6_MIRNA_COV_vs_H_FULL_RESULTS.csv.gz"),
    ("miRNA","P_vs_H","D6_MIRNA_P_vs_H_FULL_RESULTS.csv.gz"),
    ("miRNA","COV_vs_P","D6_MIRNA_COV_vs_P_FULL_RESULTS.csv.gz"),
]

LOGFC_PRIORITY=["logFC","log2FoldChange","log2FC","log2_fold_change"]
FDR_PRIORITY=["FDR","padj","adj.P.Val","qvalue","q_value"]
PVALUE_PRIORITY=["PValue","P.Value","pvalue","p_value"]

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk), b""):
            h.update(b)
    return h.hexdigest()

def require(cond,msg):
    if not cond:
        raise RuntimeError(msg)

def choose_stat_col(df, priorities, label):
    present=[c for c in priorities if c in df.columns]
    require(len(present)>=1,f"{label}_COLUMN_NOT_FOUND priorities={priorities} columns={list(df.columns)}")
    # Freeze the highest-priority recognized column. Record all candidates in schema audit.
    c=present[0]
    vals=pd.to_numeric(df[c],errors="coerce")
    require(vals.notna().sum()>0,f"{label}_COLUMN_NOT_NUMERIC={c}")
    return c, present

def choose_id_col(df, expected_ids):
    expected=set(map(str,expected_ids))
    candidates=[]
    for c in df.columns:
        s=df[c].astype(str)
        vals=set(s)
        coverage=len(expected & vals)
        exact=coverage==len(expected)
        unique=s.nunique(dropna=False)
        candidates.append((c,coverage,exact,unique))
    exacts=[x for x in candidates if x[2]]
    require(len(exacts)>=1,
            "NO_ID_COLUMN_WITH_COMPLETE_NODE_COVERAGE top="+str(sorted(candidates,key=lambda x:x[1],reverse=True)[:8]))
    # Prefer common biological identifiers, but only among columns already proven to cover all expected IDs.
    preferred=["gene_symbol","node_id","feature_id","mirna_id","miRNA","mature_id","mature_miRNA","ID","id"]
    for p in preferred:
        for x in exacts:
            if x[0]==p:
                return x[0],candidates
    # Otherwise choose the exact-coverage column with highest uniqueness, then lexical name.
    exacts=sorted(exacts,key=lambda x:(-x[3],x[0]))
    return exacts[0][0],candidates

def main():
    if len(sys.argv)!=5:
        raise SystemExit("usage: D10L <d10k_status> <characterized_nodes> <d6_run_dir> <outdir>")

    d10k_status=Path(sys.argv[1])
    nodes_path=Path(sys.argv[2])
    d6_dir=Path(sys.argv[3])
    outdir=Path(sys.argv[4])
    outdir.mkdir(parents=True,exist_ok=True)

    t=d10k_status.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10K_STATUS=PASS",
        "COMMUNITIES=8",
        "NODES=4508",
        "COMMUNITY_ASSIGNMENTS_CHANGED=NO",
        "READY_FOR_D10L_BIOLOGICAL_CHARACTERIZATION=YES",
        "BIOLOGICAL_INTERPRETATION_EXECUTED=NO",
    ]:
        require(tok in t,f"D10K_AUTHORITY_TOKEN_MISSING={tok}")

    nodes=pd.read_csv(nodes_path,dtype=str,keep_default_na=False)
    require(len(nodes)==EXPECTED_NODES,f"NODE_ROWS={len(nodes)}")
    for c in ["node_id","canonical_community_id","node_type"]:
        require(c in nodes.columns,f"CHARACTERIZED_NODE_COLUMN_MISSING={c}")
    require(nodes["node_id"].nunique()==EXPECTED_NODES,"DUPLICATE_NODE_IDS")

    typ=nodes["node_type"].str.lower()
    mrna_mask=typ.str.contains("mrna") & ~typ.str.contains("mirna")
    mirna_mask=typ.str.contains("mirna")
    require(int(mrna_mask.sum())==EXPECTED_MRNA,f"MRNA_NODE_COUNT={int(mrna_mask.sum())}")
    require(int(mirna_mask.sum())==EXPECTED_MIRNA,f"MIRNA_NODE_COUNT={int(mirna_mask.sum())}")
    require(int((mrna_mask|mirna_mask).sum())==EXPECTED_NODES,"UNCLASSIFIED_NODE_TYPES_PRESENT")

    expected_by_type={
        "mRNA":nodes.loc[mrna_mask,"node_id"].tolist(),
        "miRNA":nodes.loc[mirna_mask,"node_id"].tolist(),
    }

    annotation=nodes.copy()
    schema_rows=[]
    source_rows=[]
    coverage_rows=[]

    for feature_type,contrast,filename in FILES:
        path=d6_dir/filename
        require(path.is_file(),f"D6_SOURCE_MISSING={path}")
        df=pd.read_csv(path,compression="gzip",low_memory=False)
        require(len(df)>0,f"D6_SOURCE_EMPTY={filename}")

        expected_ids=expected_by_type[feature_type]
        id_col,id_candidates=choose_id_col(df,expected_ids)
        logfc_col,logfc_candidates=choose_stat_col(df,LOGFC_PRIORITY,"LOGFC")
        fdr_col,fdr_candidates=choose_stat_col(df,FDR_PRIORITY,"FDR")

        pvalue_col=""
        pvalue_candidates=[c for c in PVALUE_PRIORITY if c in df.columns]
        if pvalue_candidates:
            pvalue_col=pvalue_candidates[0]

        ids=df[id_col].astype(str)
        require(ids.duplicated().sum()==0,
                f"DUPLICATE_IDENTIFIERS_IN_DE_SOURCE file={filename} id_col={id_col} duplicates={int(ids.duplicated().sum())}")

        expected=set(expected_ids)
        present=set(ids)
        covered=expected & present
        missing=expected-present
        require(len(missing)==0,
                f"D10K_NODE_IDS_MISSING_FROM_DE_SOURCE file={filename} missing={len(missing)} sample={sorted(missing)[:10]}")

        source_rows.append({
            "feature_type":feature_type,
            "contrast":contrast,
            "filename":filename,
            "sha256":sha256_file(path),
            "rows":len(df),
            "columns":len(df.columns),
            "id_column":id_col,
            "logFC_column":logfc_col,
            "FDR_column":fdr_col,
            "PValue_column":pvalue_col,
        })

        coverage_rows.append({
            "feature_type":feature_type,
            "contrast":contrast,
            "expected_D10K_nodes":len(expected),
            "covered_nodes":len(covered),
            "missing_nodes":len(missing),
            "coverage_fraction":len(covered)/len(expected),
        })

        for c,cov,exact,unique in id_candidates:
            schema_rows.append({
                "feature_type":feature_type,
                "contrast":contrast,
                "filename":filename,
                "column":c,
                "dtype":str(df[c].dtype),
                "expected_node_coverage":cov,
                "complete_expected_node_coverage":bool(exact),
                "unique_values":int(unique),
                "selected_as_id":bool(c==id_col),
                "selected_as_logFC":bool(c==logfc_col),
                "selected_as_FDR":bool(c==fdr_col),
                "selected_as_PValue":bool(c==pvalue_col),
            })

        use=[id_col,logfc_col,fdr_col] + ([pvalue_col] if pvalue_col else [])
        sub=df[use].copy()
        sub[id_col]=sub[id_col].astype(str)
        sub=sub.set_index(id_col)

        prefix=f"{contrast}"
        target_mask=mrna_mask if feature_type=="mRNA" else mirna_mask
        target_ids=annotation.loc[target_mask,"node_id"]

        logfc=pd.to_numeric(target_ids.map(sub[logfc_col]),errors="coerce")
        fdr=pd.to_numeric(target_ids.map(sub[fdr_col]),errors="coerce")
        require(logfc.notna().all(),f"LOGFC_MAPPING_NA file={filename}")
        require(fdr.notna().all(),f"FDR_MAPPING_NA file={filename}")
        require(((fdr>=0)&(fdr<=1)).all(),f"FDR_OUT_OF_RANGE file={filename}")

        annotation.loc[target_mask,f"{prefix}_logFC"]=logfc.to_numpy()
        annotation.loc[target_mask,f"{prefix}_FDR"]=fdr.to_numpy()

        if pvalue_col:
            pv=pd.to_numeric(target_ids.map(sub[pvalue_col]),errors="coerce")
            require(pv.notna().all(),f"PVALUE_MAPPING_NA file={filename}")
            annotation.loc[target_mask,f"{prefix}_PValue"]=pv.to_numpy()

    # The six files map disjointly by node type into the same contrast columns.
    for contrast in ["COV_vs_H","P_vs_H","COV_vs_P"]:
        for stat in ["logFC","FDR"]:
            c=f"{contrast}_{stat}"
            require(c in annotation.columns,f"ANNOTATION_COLUMN_MISSING={c}")
            require(pd.to_numeric(annotation[c],errors="coerce").notna().all(),
                    f"ANNOTATION_COLUMN_INCOMPLETE={c}")

    # Frozen descriptive labels from already-established D6 thresholds.
    annotation["COV_vs_H_FDR_significant"]=pd.to_numeric(annotation["COV_vs_H_FDR"])<=PRIMARY_FDR_THRESHOLD
    annotation["COV_vs_H_abs_logFC_ge_1"]=pd.to_numeric(annotation["COV_vs_H_logFC"]).abs()>=SECONDARY_ABS_LOGFC_THRESHOLD
    annotation["COV_vs_H_direction"]=np.where(
        pd.to_numeric(annotation["COV_vs_H_logFC"])>0,"UP",
        np.where(pd.to_numeric(annotation["COV_vs_H_logFC"])<0,"DOWN","ZERO")
    )

    # Comparator columns are annotations only; no COVID-specificity classifier is created here.
    for contrast in ["P_vs_H","COV_vs_P"]:
        annotation[f"{contrast}_FDR_significant"]=pd.to_numeric(annotation[f"{contrast}_FDR"])<=PRIMARY_FDR_THRESHOLD
        annotation[f"{contrast}_direction"]=np.where(
            pd.to_numeric(annotation[f"{contrast}_logFC"])>0,"UP",
            np.where(pd.to_numeric(annotation[f"{contrast}_logFC"])<0,"DOWN","ZERO")
        )

    annotation.to_csv(outdir/"D10L_NODE_DE_ANNOTATION.csv",index=False,float_format="%.17g")
    pd.DataFrame(source_rows).to_csv(outdir/"D10L_DE_SOURCE_FREEZE.csv",index=False)
    pd.DataFrame(coverage_rows).to_csv(outdir/"D10L_ID_COVERAGE_AUDIT.csv",index=False,float_format="%.17g")
    pd.DataFrame(schema_rows).to_csv(outdir/"D10L_SOURCE_SCHEMA_AUDIT.csv",index=False)

    # Per-community descriptive DE composition; no enrichment or module selection.
    rows=[]
    for (cid,node_type),g in annotation.groupby(["canonical_community_id","node_type"],sort=True):
        n=len(g)
        covsig=g["COV_vs_H_FDR_significant"].astype(bool)
        rows.append({
            "community_id":int(cid),
            "node_type":node_type,
            "nodes":n,
            "COV_vs_H_FDR_significant":int(covsig.sum()),
            "COV_vs_H_FDR_significant_fraction":float(covsig.mean()),
            "COV_vs_H_significant_UP":int((covsig & g["COV_vs_H_direction"].eq("UP")).sum()),
            "COV_vs_H_significant_DOWN":int((covsig & g["COV_vs_H_direction"].eq("DOWN")).sum()),
            "COV_vs_H_abs_logFC_ge_1":int(g["COV_vs_H_abs_logFC_ge_1"].astype(bool).sum()),
            "P_vs_H_FDR_significant":int(g["P_vs_H_FDR_significant"].astype(bool).sum()),
            "COV_vs_P_FDR_significant":int(g["COV_vs_P_FDR_significant"].astype(bool).sum()),
        })
    pd.DataFrame(rows).to_csv(outdir/"D10L_COMMUNITY_DE_COMPOSITION.csv",index=False,float_format="%.17g")

    summary={
        "D10L_STATUS":"PASS",
        "COMMUNITIES":8,
        "NODES":EXPECTED_NODES,
        "MRNA_NODES":EXPECTED_MRNA,
        "MIRNA_NODES":EXPECTED_MIRNA,
        "DE_SOURCE_FILES_FROZEN":6,
        "COVID_VS_HEALTHY_PRIMARY_ANNOTATION":"YES",
        "P_VS_H_COMPARATOR_ANNOTATION":"YES",
        "COV_VS_P_COMPARATOR_ANNOTATION":"YES",
        "PRIMARY_FDR_THRESHOLD":PRIMARY_FDR_THRESHOLD,
        "SECONDARY_ABS_LOGFC_THRESHOLD":SECONDARY_ABS_LOGFC_THRESHOLD,
        "COVID_SPECIFICITY_CLASSIFIER_CREATED":"NO",
        "COMMUNITY_ASSIGNMENTS_CHANGED":"NO",
        "ENRICHMENT_EXECUTED":"NO",
        "HUB_ANALYSIS_EXECUTED":"NO",
        "BIOLOGICAL_INTERPRETATION_EXECUTED":"NO",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "READY_FOR_D10M_BIOLOGICAL_INTERPRETATION_DESIGN":"YES",
        "READY_FOR_BIOLOGICAL_INTERPRETATION":"NO",
        "STOP":"YES",
    }
    (outdir/"D10L_SUMMARY.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
