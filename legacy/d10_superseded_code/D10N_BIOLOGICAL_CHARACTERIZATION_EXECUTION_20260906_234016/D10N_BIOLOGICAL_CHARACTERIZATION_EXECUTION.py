#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import json
import math
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_COMMUNITIES=8
EXPECTED_NODES=4508
EXPECTED_MRNA=4467
EXPECTED_MIRNA=41
EXPECTED_EDGES=11531
EXPECTED_REG=1978

GPROFILER_BASE="https://biit.cs.ut.ee/gprofiler"
DATA_VERSION_URL=GPROFILER_BASE+"/api/util/data_versions/?organism=hsapiens"
PROFILE_URL=GPROFILER_BASE+"/api/gost/profile/"

USER_AGENT="GSE243219-D10N/1.0 (prospective frozen biological characterization)"
TIMEOUT_SECONDS=240
MAX_ATTEMPTS=3

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk),b""):
            h.update(b)
    return h.hexdigest()

def require(cond,msg):
    if not cond:
        raise RuntimeError(msg)

def http_json(url, method="GET", payload=None):
    data=None
    headers={"Accept":"application/json","User-Agent":USER_AGENT}
    if payload is not None:
        data=json.dumps(payload,separators=(",",":")).encode("utf-8")
        headers["Content-Type"]="application/json"
    last=None
    for attempt in range(1,MAX_ATTEMPTS+1):
        try:
            req=urllib.request.Request(url=url,data=data,headers=headers,method=method)
            with urllib.request.urlopen(req,timeout=TIMEOUT_SECONDS) as r:
                body=r.read()
                status=getattr(r,"status",200)
            require(200 <= status < 300,f"HTTP_STATUS={status} url={url}")
            return json.loads(body.decode("utf-8"))
        except Exception as e:
            last=e
            if attempt < MAX_ATTEMPTS:
                time.sleep(2*attempt)
    raise RuntimeError(f"HTTP_JSON_FAILED url={url} error={type(last).__name__}:{last}")

def json_hash(obj):
    return hashlib.sha256(
        json.dumps(obj,sort_keys=True,separators=(",",":")).encode("utf-8")
    ).hexdigest()

def flatten_result_rows(raw, analysis_family):
    rows=[]
    for x in raw.get("result",[]):
        y=dict(x)
        y["analysis_family"]=analysis_family
        for k,v in list(y.items()):
            if isinstance(v,(list,dict)):
                y[k]=json.dumps(v,ensure_ascii=False,separators=(",",":"))
        rows.append(y)
    return rows

def bool_series(s):
    return s.astype(str).str.lower().isin(["true","1","yes"])

def main():
    if len(sys.argv)!=8:
        raise SystemExit(
            "usage: D10N <d10m_contract> <d10l_node_annotation> "
            "<d10k_nodes> <d10k_edges> <d10m_status> <d10l_status> <outdir>"
        )

    contract_path=Path(sys.argv[1])
    de_path=Path(sys.argv[2])
    nodes_path=Path(sys.argv[3])
    edges_path=Path(sys.argv[4])
    d10m_status=Path(sys.argv[5])
    d10l_status=Path(sys.argv[6])
    outdir=Path(sys.argv[7])
    outdir.mkdir(parents=True,exist_ok=True)

    mt=d10m_status.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10M_STATUS=PASS",
        "COMMUNITIES_FROZEN=8",
        "NETWORK_MRNA_BACKGROUND=4467",
        "ALL_COMMUNITIES_MUST_BE_ANALYZED=YES",
        "PRIMARY_ENRICHMENT_SOURCES=GO:BP;REAC",
        "SECONDARY_ENRICHMENT_SOURCE=KEGG",
        "ENRICHMENT_ORGANISM=hsapiens",
        "ENRICHMENT_SIGNIFICANCE_METHOD=fdr",
        "ENRICHMENT_THRESHOLD=0.05",
        "COVID_SPECIFICITY_BINARY_CLASSIFIER=PROHIBITED",
        "COMPOSITE_HUB_SCORE=PROHIBITED",
        "MODULE_COMPOSITE_RANKING=PROHIBITED",
        "READY_FOR_D10N_BIOLOGICAL_CHARACTERIZATION_EXECUTION=YES",
    ]:
        require(tok in mt,f"D10M_AUTHORITY_TOKEN_MISSING={tok}")

    lt=d10l_status.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10L_STATUS=PASS",
        "NODES=4508",
        "MRNA_NODES=4467",
        "MIRNA_NODES=41",
        "COVID_SPECIFICITY_CLASSIFIER_CREATED=NO",
        "COMMUNITY_ASSIGNMENTS_CHANGED=NO",
    ]:
        require(tok in lt,f"D10L_AUTHORITY_TOKEN_MISSING={tok}")

    contract=json.loads(contract_path.read_text(encoding="utf-8"))
    require(contract["D10M_STATUS"]=="PASS","D10M_CONTRACT_NOT_PASS")
    require(contract["NETWORK_MRNA_BACKGROUND"]==EXPECTED_MRNA,"D10M_BACKGROUND_CHANGED")
    require(contract["ENRICHMENT_SIGNIFICANCE_METHOD"]=="fdr","D10M_CORRECTION_CHANGED")
    require(float(contract["ENRICHMENT_THRESHOLD"])==0.05,"D10M_THRESHOLD_CHANGED")
    require(contract["ENRICHMENT_ORDERED"] is False,"D10M_ORDERED_CHANGED")
    require(contract["ENRICHMENT_NO_IEA"] is False,"D10M_IEA_CHANGED")

    de=pd.read_csv(de_path,low_memory=False)
    nodes=pd.read_csv(nodes_path,dtype=str,keep_default_na=False)
    edges=pd.read_csv(edges_path,float_precision="round_trip",keep_default_na=False)

    require(len(de)==EXPECTED_NODES,f"DE_NODE_ROWS={len(de)}")
    require(len(nodes)==EXPECTED_NODES,f"NODE_ROWS={len(nodes)}")
    require(len(edges)==EXPECTED_EDGES,f"EDGE_ROWS={len(edges)}")
    require(de["node_id"].nunique()==EXPECTED_NODES,"DE_DUPLICATE_NODE_IDS")
    require(nodes["node_id"].nunique()==EXPECTED_NODES,"NODE_DUPLICATE_NODE_IDS")
    require(set(de["node_id"].astype(str))==set(nodes["node_id"].astype(str)),"DE_NODE_SET_MISMATCH")

    # Merge once; canonical community identity remains immutable.
    n=nodes[["node_id","canonical_community_id","node_type"]].copy()
    de2=de.copy()
    de2["node_id"]=de2["node_id"].astype(str)
    merged=n.merge(
        de2.drop(columns=[c for c in ["canonical_community_id","node_type"] if c in de2.columns]),
        on="node_id",how="left",validate="one_to_one"
    )
    merged["community"]=merged["canonical_community_id"].astype(int)
    typ=merged["node_type"].astype(str).str.lower()
    merged["is_mrna"]=typ.str.contains("mrna") & ~typ.str.contains("mirna")
    merged["is_mirna"]=typ.str.contains("mirna")
    require(int(merged["is_mrna"].sum())==EXPECTED_MRNA,"MRNA_COUNT_CHANGED")
    require(int(merged["is_mirna"].sum())==EXPECTED_MIRNA,"MIRNA_COUNT_CHANGED")
    require(set(merged["community"].unique())==set(range(1,EXPECTED_COMMUNITIES+1)),
            f"COMMUNITY_IDS_CHANGED={sorted(merged['community'].unique())}")

    # Edge/community mapping.
    comm_of=dict(zip(merged["node_id"],merged["community"]))
    type_of=dict(zip(merged["node_id"],merged["node_type"].astype(str).str.lower()))
    for c in ["source","target","regulatory_eligible"]:
        require(c in edges.columns,f"EDGE_COLUMN_MISSING={c}")
    edges["source"]=edges["source"].astype(str)
    edges["target"]=edges["target"].astype(str)
    edges["source_community"]=edges["source"].map(comm_of)
    edges["target_community"]=edges["target"].map(comm_of)
    require(edges["source_community"].notna().all() and edges["target_community"].notna().all(),
            "EDGE_COMMUNITY_MAPPING_FAILED")
    edges["source_community"]=edges["source_community"].astype(int)
    edges["target_community"]=edges["target_community"].astype(int)
    edges["within"]=edges["source_community"].eq(edges["target_community"])
    edges["is_regulatory"]=edges["regulatory_eligible"].astype(str).str.upper().eq("YES")
    require(int(edges["is_regulatory"].sum())==EXPECTED_REG,"REGULATORY_EDGE_COUNT_CHANGED")

    # Primary enrichment queries = all mRNA in every community.
    mrna_background=sorted(merged.loc[merged["is_mrna"],"node_id"].astype(str).unique())
    require(len(mrna_background)==EXPECTED_MRNA,"MRNA_BACKGROUND_SIZE_CHANGED")

    primary_queries={}
    for cid in range(1,EXPECTED_COMMUNITIES+1):
        q=sorted(
            merged.loc[(merged["community"]==cid)&merged["is_mrna"],"node_id"]
            .astype(str).unique()
        )
        require(len(q)>0,f"COMMUNITY_{cid}_HAS_NO_MRNA")
        primary_queries[f"C{cid}"]=q

    # Secondary regulatory-target query sets and universe.
    reg_edges=edges[edges["is_regulatory"]].copy()
    regulatory_mrna=set()
    reg_query_by_comm={cid:set() for cid in range(1,EXPECTED_COMMUNITIES+1)}
    for row in reg_edges.itertuples(index=False):
        s=str(row.source); t=str(row.target)
        sc=int(row.source_community); tc=int(row.target_community)
        s_is_mrna=("mrna" in type_of[s] and "mirna" not in type_of[s])
        t_is_mrna=("mrna" in type_of[t] and "mirna" not in type_of[t])
        if s_is_mrna:
            regulatory_mrna.add(s)
            if row.within:
                reg_query_by_comm[sc].add(s)
        if t_is_mrna:
            regulatory_mrna.add(t)
            if row.within:
                reg_query_by_comm[tc].add(t)
    regulatory_background=sorted(regulatory_mrna)
    require(len(regulatory_background)>0,"REGULATORY_MRNA_BACKGROUND_EMPTY")

    reg_queries={
        f"C{cid}":sorted(v)
        for cid,v in reg_query_by_comm.items()
        if len(v)>0
    }

    # Snapshot service versions before any enrichment.
    versions_before=http_json(DATA_VERSION_URL,"GET")
    (outdir/"D10N_GPROFILER_DATA_VERSIONS_BEFORE.json").write_text(
        json.dumps(versions_before,indent=2,ensure_ascii=False),encoding="utf-8"
    )
    version_hash_before=json_hash(versions_before)

    # One batched request for all 8 primary communities.
    primary_payload={
        "organism":"hsapiens",
        "query":primary_queries,
        "sources":["GO:BP","REAC","KEGG"],
        "user_threshold":0.05,
        "significance_threshold_method":"fdr",
        "no_iea":False,
        "ordered":False,
        "combined":False,
        "measure_underrepresentation":False,
        "domain_scope":"custom",
        "background":mrna_background,
        "all_results":False,
        "no_evidences":False,
        "output":"json",
    }
    (outdir/"D10N_PRIMARY_GPROFILER_REQUEST.json").write_text(
        json.dumps(primary_payload,indent=2,ensure_ascii=False),encoding="utf-8"
    )
    primary_raw=http_json(PROFILE_URL,"POST",primary_payload)
    (outdir/"D10N_PRIMARY_GPROFILER_RESPONSE.json").write_text(
        json.dumps(primary_raw,indent=2,ensure_ascii=False),encoding="utf-8"
    )

    primary_rows=flatten_result_rows(primary_raw,"PRIMARY_MODULE_FUNCTION")
    primary_df=pd.DataFrame(primary_rows)
    if len(primary_df)==0:
        primary_df=pd.DataFrame(columns=[
            "analysis_family","query","source","native","name","p_value","significant",
            "term_size","query_size","intersection_size","effective_domain_size",
            "precision","recall"
        ])

    # Validate result source/query namespaces if results exist.
    if len(primary_df)>0:
        require(set(primary_df["source"].astype(str)).issubset({"GO:BP","REAC","KEGG"}),
                f"UNEXPECTED_PRIMARY_SOURCE={set(primary_df['source'])}")
        require(set(primary_df["query"].astype(str)).issubset(set(primary_queries)),
                f"UNEXPECTED_PRIMARY_QUERY={set(primary_df['query'])}")
        require(bool_series(primary_df["significant"]).all(),"PRIMARY_RESPONSE_CONTAINS_NONSIGNIFICANT_ROWS")

    go_reac=primary_df[primary_df["source"].astype(str).isin(["GO:BP","REAC"])].copy()
    kegg=primary_df[primary_df["source"].astype(str).eq("KEGG")].copy()
    go_reac.to_csv(outdir/"D10N_PRIMARY_GO_BP_REAC_ENRICHMENT.csv",index=False)
    kegg.to_csv(outdir/"D10N_SECONDARY_KEGG_ENRICHMENT.csv",index=False)

    # Secondary regulatory-target enrichment, batched for non-empty community queries.
    if reg_queries:
        reg_payload={
            "organism":"hsapiens",
            "query":reg_queries,
            "sources":["GO:BP","REAC"],
            "user_threshold":0.05,
            "significance_threshold_method":"fdr",
            "no_iea":False,
            "ordered":False,
            "combined":False,
            "measure_underrepresentation":False,
            "domain_scope":"custom",
            "background":regulatory_background,
            "all_results":False,
            "no_evidences":False,
            "output":"json",
        }
        (outdir/"D10N_REGULATORY_GPROFILER_REQUEST.json").write_text(
            json.dumps(reg_payload,indent=2,ensure_ascii=False),encoding="utf-8"
        )
        reg_raw=http_json(PROFILE_URL,"POST",reg_payload)
    else:
        reg_payload={}
        reg_raw={"result":[],"meta":{"note":"No non-empty regulatory-target community query"}}
        (outdir/"D10N_REGULATORY_GPROFILER_REQUEST.json").write_text(
            json.dumps(reg_payload,indent=2),encoding="utf-8"
        )
    (outdir/"D10N_REGULATORY_GPROFILER_RESPONSE.json").write_text(
        json.dumps(reg_raw,indent=2,ensure_ascii=False),encoding="utf-8"
    )
    reg_rows=flatten_result_rows(reg_raw,"SECONDARY_REGULATORY_TARGET_FUNCTION")
    reg_df=pd.DataFrame(reg_rows)
    if len(reg_df)==0:
        reg_df=pd.DataFrame(columns=[
            "analysis_family","query","source","native","name","p_value","significant",
            "term_size","query_size","intersection_size","effective_domain_size",
            "precision","recall"
        ])
    if len(reg_df)>0:
        require(set(reg_df["source"].astype(str)).issubset({"GO:BP","REAC"}),
                f"UNEXPECTED_REG_SOURCE={set(reg_df['source'])}")
        require(set(reg_df["query"].astype(str)).issubset(set(reg_queries)),
                f"UNEXPECTED_REG_QUERY={set(reg_df['query'])}")
        require(bool_series(reg_df["significant"]).all(),"REG_RESPONSE_CONTAINS_NONSIGNIFICANT_ROWS")
    reg_df.to_csv(outdir/"D10N_SECONDARY_REGULATORY_TARGET_ENRICHMENT.csv",index=False)

    # Snapshot service versions again and require exact consistency.
    versions_after=http_json(DATA_VERSION_URL,"GET")
    (outdir/"D10N_GPROFILER_DATA_VERSIONS_AFTER.json").write_text(
        json.dumps(versions_after,indent=2,ensure_ascii=False),encoding="utf-8"
    )
    version_hash_after=json_hash(versions_after)
    require(version_hash_before==version_hash_after,
            f"GPROFILER_DATA_VERSION_CHANGED_DURING_RUN before={version_hash_before} after={version_hash_after}")

    # Primary topology degree and secondary internal regulatory degree.
    internal_degree=defaultdict(int)
    internal_reg_degree=defaultdict(int)
    for row in edges.itertuples(index=False):
        if bool(row.within):
            s=str(row.source); t=str(row.target)
            internal_degree[s]+=1
            internal_degree[t]+=1
            if bool(row.is_regulatory):
                internal_reg_degree[s]+=1
                internal_reg_degree[t]+=1

    merged["internal_degree"]=merged["node_id"].map(lambda x:internal_degree.get(str(x),0)).astype(int)
    merged["internal_regulatory_degree"]=merged["node_id"].map(
        lambda x:internal_reg_degree.get(str(x),0)
    ).astype(int)

    # Hub thresholds: community + exact node_type groups.
    threshold_rows=[]
    merged["primary_topological_hub"]=False
    merged["regulatory_hub_evidence"]=False

    for (cid,nt),idx in merged.groupby(["community","node_type"]).groups.items():
        inds=list(idx)
        deg=merged.loc[inds,"internal_degree"].astype(float)
        require(len(deg)>0,"EMPTY_HUB_STRATUM")
        thr=float(np.quantile(deg.to_numpy(),0.90,method="linear"))
        is_hub=deg>=thr
        merged.loc[inds,"primary_topological_hub"]=is_hub.to_numpy()

        pos_reg=merged.loc[inds,"internal_regulatory_degree"].astype(float)
        pos_only=pos_reg[pos_reg>0]
        if len(pos_only)>0:
            rthr=float(np.quantile(pos_only.to_numpy(),0.90,method="linear"))
            is_rhub=(pos_reg>0)&(pos_reg>=rthr)
            merged.loc[inds,"regulatory_hub_evidence"]=is_rhub.to_numpy()
        else:
            rthr=float("nan")

        threshold_rows.append({
            "community_id":int(cid),
            "node_type":nt,
            "nodes_in_stratum":len(inds),
            "internal_degree_90th_percentile":thr,
            "primary_hubs_with_ties":int(is_hub.sum()),
            "regulatory_positive_degree_nodes":int((pos_reg>0).sum()),
            "internal_regulatory_degree_90th_percentile_positive_only":rthr,
            "regulatory_hubs_with_ties":int(
                merged.loc[inds,"regulatory_hub_evidence"].astype(bool).sum()
            ),
        })
    pd.DataFrame(threshold_rows).to_csv(
        outdir/"D10N_HUB_THRESHOLDS.csv",index=False,float_format="%.17g"
    )

    # Frozen DE evidence layers. No binary COVID-specific classifier.
    required_de=[
        "COV_vs_H_FDR","COV_vs_H_logFC","P_vs_H_FDR","P_vs_H_logFC",
        "COV_vs_P_FDR","COV_vs_P_logFC"
    ]
    for c in required_de:
        require(c in merged.columns,f"DE_COLUMN_MISSING={c}")
        merged[c]=pd.to_numeric(merged[c],errors="coerce")
        require(merged[c].notna().all(),f"DE_COLUMN_NA={c}")

    merged["cov_vs_h_significant"]=merged["COV_vs_H_FDR"]<=0.05
    merged["p_vs_h_significant"]=merged["P_vs_H_FDR"]<=0.05
    merged["cov_vs_p_significant"]=merged["COV_vs_P_FDR"]<=0.05
    merged["cov_large_effect"]=merged["cov_vs_h_significant"] & (merged["COV_vs_H_logFC"].abs()>=1)
    merged["shared_directional_response"]=(
        merged["cov_vs_h_significant"] &
        merged["p_vs_h_significant"] &
        (np.sign(merged["COV_vs_H_logFC"])==np.sign(merged["P_vs_H_logFC"])) &
        (np.sign(merged["COV_vs_H_logFC"])!=0)
    )
    merged["cov_associated_with_direct_sepsis_difference"]=(
        merged["cov_vs_h_significant"] & merged["cov_vs_p_significant"]
    )
    merged["cov_associated_hub"]=merged["primary_topological_hub"] & merged["cov_vs_h_significant"]
    merged["large_effect_cov_hub"]=merged["cov_associated_hub"] & (merged["COV_vs_H_logFC"].abs()>=1)
    merged["cov_vs_sepsis_discriminating_hub"]=merged["primary_topological_hub"] & merged["cov_vs_p_significant"]

    # Save all hub candidates (primary topology hubs); non-hub node evidence remains in node table.
    hub_df=merged[merged["primary_topological_hub"]].copy()
    hub_df.to_csv(outdir/"D10N_PRIMARY_HUB_CANDIDATES.csv",index=False,float_format="%.17g")
    merged.to_csv(outdir/"D10N_NODE_BIOLOGICAL_EVIDENCE.csv",index=False,float_format="%.17g")

    # Module-level calculation summary. No narrative ranking.
    module_rows=[]
    for cid in range(1,EXPECTED_COMMUNITIES+1):
        g=merged[merged["community"]==cid]
        mq=primary_queries[f"C{cid}"]
        rq=reg_query_by_comm[cid]
        pgr=go_reac[go_reac["query"].astype(str).eq(f"C{cid}")] if len(go_reac) else go_reac
        pkg=kegg[kegg["query"].astype(str).eq(f"C{cid}")] if len(kegg) else kegg
        prg=reg_df[reg_df["query"].astype(str).eq(f"C{cid}")] if len(reg_df) else reg_df
        module_rows.append({
            "community_id":cid,
            "nodes_total":len(g),
            "mrna_nodes":int(g["is_mrna"].sum()),
            "mirna_nodes":int(g["is_mirna"].sum()),
            "primary_enrichment_query_mrna":len(mq),
            "primary_GO_BP_REAC_significant_terms":len(pgr),
            "secondary_KEGG_significant_terms":len(pkg),
            "regulatory_target_query_mrna":len(rq),
            "secondary_regulatory_GO_BP_REAC_significant_terms":len(prg),
            "COV_vs_H_significant_nodes":int(g["cov_vs_h_significant"].sum()),
            "P_vs_H_significant_nodes":int(g["p_vs_h_significant"].sum()),
            "COV_vs_P_significant_nodes":int(g["cov_vs_p_significant"].sum()),
            "shared_directional_response_nodes":int(g["shared_directional_response"].sum()),
            "cov_associated_with_direct_sepsis_difference_nodes":int(
                g["cov_associated_with_direct_sepsis_difference"].sum()
            ),
            "primary_topological_hubs":int(g["primary_topological_hub"].sum()),
            "regulatory_hub_evidence_nodes":int(g["regulatory_hub_evidence"].sum()),
            "cov_associated_hubs":int(g["cov_associated_hub"].sum()),
            "large_effect_cov_hubs":int(g["large_effect_cov_hub"].sum()),
            "cov_vs_sepsis_discriminating_hubs":int(g["cov_vs_sepsis_discriminating_hub"].sum()),
        })
    module_df=pd.DataFrame(module_rows)
    require(len(module_df)==EXPECTED_COMMUNITIES,"MODULE_SUMMARY_NOT_ALL_8")
    module_df.to_csv(outdir/"D10N_ALL_COMMUNITY_CALCULATION_SUMMARY.csv",index=False)

    # Request/query coverage audit.
    coverage_rows=[]
    for cid in range(1,EXPECTED_COMMUNITIES+1):
        qname=f"C{cid}"
        coverage_rows.append({
            "community_id":cid,
            "primary_query_name":qname,
            "primary_query_mrna":len(primary_queries[qname]),
            "primary_request_included":"YES",
            "regulatory_query_mrna":len(reg_query_by_comm[cid]),
            "regulatory_request_included":"YES" if qname in reg_queries else "NO_EMPTY_QUERY",
        })
    pd.DataFrame(coverage_rows).to_csv(outdir/"D10N_ENRICHMENT_QUERY_COVERAGE.csv",index=False)

    summary={
        "D10N_STATUS":"PASS",
        "COMMUNITIES_ANALYZED":EXPECTED_COMMUNITIES,
        "NODES":EXPECTED_NODES,
        "MRNA_BACKGROUND":EXPECTED_MRNA,
        "MIRNA_NODES":EXPECTED_MIRNA,
        "EDGES":EXPECTED_EDGES,
        "REGULATORY_EDGES":EXPECTED_REG,
        "GPROFILER_API_BASE":GPROFILER_BASE,
        "GPROFILER_DATA_VERSION_HASH":version_hash_before,
        "GPROFILER_DATA_VERSION_STABLE_DURING_RUN":"YES",
        "PRIMARY_GO_BP_REAC_SIGNIFICANT_TERMS":int(len(go_reac)),
        "SECONDARY_KEGG_SIGNIFICANT_TERMS":int(len(kegg)),
        "SECONDARY_REGULATORY_TARGET_SIGNIFICANT_TERMS":int(len(reg_df)),
        "PRIMARY_TOPOLOGICAL_HUB_CANDIDATES":int(merged["primary_topological_hub"].sum()),
        "REGULATORY_HUB_EVIDENCE_NODES":int(merged["regulatory_hub_evidence"].sum()),
        "COVID_SPECIFICITY_BINARY_CLASSIFIER_CREATED":"NO",
        "COMPOSITE_HUB_SCORE_CREATED":"NO",
        "MODULE_COMPOSITE_RANKING_CREATED":"NO",
        "ALL_8_COMMUNITIES_REPORTED":"YES",
        "COMMUNITY_ASSIGNMENTS_CHANGED":"NO",
        "ENRICHMENT_EXECUTED":"YES",
        "HUB_ANALYSIS_EXECUTED":"YES",
        "BIOLOGICAL_EVIDENCE_CALCULATION_EXECUTED":"YES",
        "BIOLOGICAL_INTERPRETATION_NARRATIVE_EXECUTED":"NO",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "FUNCTIONAL_ENRICHMENT_COUNTS_AS_ACLA_VALIDATION":"NO",
        "MULTISEED_STABILITY_CLAIM_AUTHORIZED":"NO",
        "READY_FOR_D10O_BIOLOGICAL_INTERPRETATION":"YES",
        "READY_FOR_BIOLOGICAL_INTERPRETATION":"YES",
        "STOP":"YES",
    }
    (outdir/"D10N_SUMMARY.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
