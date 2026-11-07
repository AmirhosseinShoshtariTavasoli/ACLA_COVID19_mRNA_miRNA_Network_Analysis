#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import re
import sys
from pathlib import Path

import pandas as pd

EXPECTED_COMMUNITIES=8
PUBMED_MAX_DATE="2026/09/07"
PUBMED_MIN_DATE="1900/01/01"
PUBMED_RETMAX=50
PUBMED_SORT="relevance"
MAX_REQUESTS_PER_SECOND=2.0

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk),b""):
            h.update(b)
    return h.hexdigest()

def require(cond,msg):
    if not cond:
        raise RuntimeError(msg)

def verify_manifest(path: Path):
    require(path.is_file(),f"MANIFEST_MISSING={path}")
    df=pd.read_csv(path,dtype=str,keep_default_na=False)
    required={"full_path","size_bytes","SHA256"}
    require(required.issubset(df.columns),f"MANIFEST_SCHEMA_INVALID={path}")
    bad=0
    for row in df.itertuples(index=False):
        p=Path(row.full_path)
        if not p.is_file():
            bad+=1
            continue
        if int(p.stat().st_size)!=int(row.size_bytes):
            bad+=1
            continue
        if sha256_file(p)!=str(row.SHA256).lower():
            bad+=1
    require(bad==0,f"MANIFEST_HASH_MISMATCHES={bad}")

def quote_pubmed_phrase(s: str):
    s=str(s).replace('"'," ").strip()
    s=re.sub(r"\s+"," ",s)
    return f'"{s}"[Title/Abstract]'

def unquoted_pubmed_term(s: str):
    s=str(s).replace('"'," ").strip()
    s=re.sub(r"\s+"," ",s)
    return f'({s})[Title/Abstract]'

def covid_context():
    return '("COVID-19"[Title/Abstract] OR "SARS-CoV-2"[Title/Abstract])'

def sepsis_context():
    return 'sepsis[Title/Abstract]'

def add_hub_targets(targets, df, category, per_community=5):
    if len(df)==0:
        return
    required={"community","node_id","internal_degree","node_type"}
    require(required.issubset(df.columns),f"HUB_TABLE_SCHEMA_INVALID category={category}")
    z=df.copy()
    z["community"]=pd.to_numeric(z["community"],errors="coerce")
    z["internal_degree"]=pd.to_numeric(z["internal_degree"],errors="coerce")
    require(z["community"].notna().all() and z["internal_degree"].notna().all(),
            f"HUB_TABLE_PARSE_FAILURE category={category}")
    z=z.sort_values(
        ["community","internal_degree","node_id"],
        ascending=[True,False,True]
    )
    for cid in range(1,EXPECTED_COMMUNITIES+1):
        g=z[z["community"].astype(int)==cid].head(per_community)
        for rank,row in enumerate(g.itertuples(index=False),1):
            targets.append({
                "community_id":cid,
                "target_category":category,
                "category_rank":rank,
                "target_label":str(row.node_id),
                "target_native_id":str(row.node_id),
                "source_family":"D10O_HUB_EVIDENCE",
                "node_type":str(row.node_type),
                "selection_rule":f"TOP_{per_community}_PER_COMMUNITY_BY_INTERNAL_DEGREE",
            })

def main():
    if len(sys.argv)!=8:
        raise SystemExit(
            "usage: D10P <d10o_status> <d10o_manifest> <display_terms> "
            "<cov_hubs> <discr_hubs> <reg_hubs> <outdir>"
        )

    status_path=Path(sys.argv[1])
    manifest_path=Path(sys.argv[2])
    display_terms_path=Path(sys.argv[3])
    cov_hubs_path=Path(sys.argv[4])
    discr_hubs_path=Path(sys.argv[5])
    reg_hubs_path=Path(sys.argv[6])
    outdir=Path(sys.argv[7])
    outdir.mkdir(parents=True,exist_ok=True)

    t=status_path.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10O_STATUS=PASS",
        "COMMUNITIES_INTERPRETED=8",
        "ALL_8_COMMUNITIES_REPORTED=YES",
        "COMMUNITY_ASSIGNMENTS_CHANGED=NO",
        "ENRICHMENT_RERUN=NO",
        "HUB_ANALYSIS_RERUN=NO",
        "BIOLOGICAL_INTERPRETATION_EXECUTED=YES_EVIDENCE_SYNTHESIS_ONLY",
        "EXTERNAL_LITERATURE_CONTEXTUALIZATION_EXECUTED=NO",
        "READY_FOR_D10P_EXTERNAL_LITERATURE_CONTEXTUALIZATION=YES",
    ]:
        require(tok in t,f"D10O_AUTHORITY_TOKEN_MISSING={tok}")

    verify_manifest(manifest_path)

    terms=pd.read_csv(display_terms_path,keep_default_na=False)
    cov_hubs=pd.read_csv(cov_hubs_path,low_memory=False)
    discr_hubs=pd.read_csv(discr_hubs_path,low_memory=False)
    reg_hubs=pd.read_csv(reg_hubs_path,low_memory=False)

    required_terms={"community_id","analysis_family","display_rank","source","native","name","p_value"}
    require(required_terms.issubset(terms.columns),"DISPLAY_TERMS_SCHEMA_INVALID")
    terms["community_id"]=pd.to_numeric(terms["community_id"],errors="coerce")
    terms["display_rank"]=pd.to_numeric(terms["display_rank"],errors="coerce")
    require(terms["community_id"].notna().all() and terms["display_rank"].notna().all(),
            "DISPLAY_TERMS_PARSE_FAILURE")

    targets=[]
    family_map={
        "PRIMARY_GO_BP_REAC":"PRIMARY_FUNCTIONAL_TERM",
        "SECONDARY_KEGG":"SECONDARY_KEGG_TERM",
        "SECONDARY_REGULATORY_TARGET_GO_BP_REAC":"REGULATORY_TARGET_FUNCTIONAL_TERM",
    }
    for row in terms.sort_values(
        ["community_id","analysis_family","display_rank","p_value","name"]
    ).itertuples(index=False):
        fam=str(row.analysis_family)
        require(fam in family_map,f"UNEXPECTED_D10O_ANALYSIS_FAMILY={fam}")
        targets.append({
            "community_id":int(row.community_id),
            "target_category":family_map[fam],
            "category_rank":int(row.display_rank),
            "target_label":str(row.name),
            "target_native_id":str(row.native),
            "source_family":str(row.source),
            "node_type":"",
            "selection_rule":"ALL_D10O_DISPLAYED_TERMS_RETAINED",
        })

    add_hub_targets(targets,cov_hubs,"COVID_ASSOCIATED_HUB",5)
    add_hub_targets(targets,discr_hubs,"COV_VS_SEPSIS_DISCRIMINATING_HUB",5)
    add_hub_targets(targets,reg_hubs,"REGULATORY_HUB_EVIDENCE_NODE",5)

    target_df=pd.DataFrame(targets)
    require(len(target_df)>0,"NO_LITERATURE_TARGETS_CREATED")
    require(set(target_df["community_id"].astype(int)).issubset(set(range(1,9))),
            "TARGET_COMMUNITY_OUT_OF_RANGE")

    target_df=target_df.sort_values(
        ["community_id","target_category","category_rank","target_label","target_native_id"]
    ).reset_index(drop=True)

    counters={}
    ids=[]
    for row in target_df.itertuples(index=False):
        key=(int(row.community_id),str(row.target_category))
        counters[key]=counters.get(key,0)+1
        ids.append(f"C{key[0]}_{key[1]}_{counters[key]:03d}")
    target_df.insert(0,"target_id",ids)
    target_df.to_csv(outdir/"D10P_LITERATURE_TARGETS.csv",index=False)

    query_rows=[]
    for row in target_df.itertuples(index=False):
        label=str(row.target_label)
        exact=quote_pubmed_phrase(label)
        fallback=unquoted_pubmed_term(label)
        for disease,ctx in [
            ("COVID19",covid_context()),
            ("SEPSIS",sepsis_context()),
        ]:
            query_rows.append({
                "query_id":f"{row.target_id}_{disease}",
                "target_id":row.target_id,
                "community_id":int(row.community_id),
                "target_category":row.target_category,
                "target_label":label,
                "disease_context":disease,
                "primary_query":f"{exact} AND {ctx}",
                "fallback_query_if_primary_count_zero":f"{fallback} AND {ctx}",
                "fallback_trigger":"PRIMARY_ESEARCH_COUNT_EQUALS_ZERO_ONLY",
                "database":"pubmed",
                "sort":PUBMED_SORT,
                "retmax":PUBMED_RETMAX,
                "datetype":"pdat",
                "mindate":PUBMED_MIN_DATE,
                "maxdate":PUBMED_MAX_DATE,
            })
    query_df=pd.DataFrame(query_rows)
    query_df.to_csv(outdir/"D10P_PUBMED_QUERY_PLAN.csv",index=False)

    coverage=[]
    for cid in range(1,9):
        g=target_df[target_df["community_id"].astype(int)==cid]
        coverage.append({
            "community_id":cid,
            "targets_total":len(g),
            "primary_functional_terms":int((g["target_category"]=="PRIMARY_FUNCTIONAL_TERM").sum()),
            "secondary_kegg_terms":int((g["target_category"]=="SECONDARY_KEGG_TERM").sum()),
            "regulatory_target_functional_terms":int((g["target_category"]=="REGULATORY_TARGET_FUNCTIONAL_TERM").sum()),
            "covid_associated_hubs":int((g["target_category"]=="COVID_ASSOCIATED_HUB").sum()),
            "cov_vs_sepsis_discriminating_hubs":int((g["target_category"]=="COV_VS_SEPSIS_DISCRIMINATING_HUB").sum()),
            "regulatory_hub_evidence_nodes":int((g["target_category"]=="REGULATORY_HUB_EVIDENCE_NODE").sum()),
            "pubmed_queries_planned":int(len(query_df[query_df["community_id"].astype(int)==cid])),
        })
    coverage_df=pd.DataFrame(coverage)
    require(len(coverage_df)==8,"COVERAGE_NOT_ALL_8")
    coverage_df.to_csv(outdir/"D10P_TARGET_COVERAGE_AUDIT.csv",index=False)

    policy_rows=[
        ["PRIMARY_LITERATURE_SOURCE","PubMed via NCBI E-utilities","Primary reproducible bibliographic source.","FROZEN"],
        ["SEARCH_CUTOFF_DATE","2026-09-07 publication date","Hard cutoff for reproducibility.","FROZEN"],
        ["PUBMED_SORT","relevance","Use ESearch relevance / Best Match ordering.","FROZEN"],
        ["PUBMED_RETMAX","50 per query","Candidate retrieval cap; no result-dependent expansion.","FROZEN"],
        ["REQUEST_RATE","<=2 requests/second","Below NCBI no-key documented limit.","FROZEN"],
        ["TOOL_PARAMETER","GSE243219_D10Q","Identify automated E-utility client.","FROZEN"],
        ["API_KEY_POLICY","OPTIONAL_NOT_REQUIRED","No API key required at <=2 requests/sec.","FROZEN"],
        ["TARGET_SCOPE","ALL_D10O_DISPLAYED_ENRICHMENT_TERMS","No manual omission.","FROZEN"],
        ["HUB_TARGET_SCOPE","TOP5_PER_COMMUNITY_PER_FROZEN_EVIDENCE_LAYER","Deterministic internal-degree selection.","FROZEN"],
        ["DISEASE_CONTEXTS","COVID19_AND_SEPSIS_SEPARATELY","Separate disease-context searches.","FROZEN"],
        ["PRIMARY_SEARCH_FIELD","Title/Abstract exact phrase","High-specificity primary query.","FROZEN"],
        ["FALLBACK_SEARCH","Unquoted Title/Abstract target","Only if primary count is zero.","FROZEN"],
        ["GENE_ALIAS_EXPANSION","PROHIBITED_IN_D10Q","Avoid target-specific flexibility.","FROZEN"],
        ["SCREENING_SCOPE","SEARCH_AND_RETRIEVAL_ONLY_IN_D10Q","No narrative in retrieval phase.","FROZEN"],
        ["NO_ABSTRACT_POLICY","METADATA_ONLY_NOT_MECHANISTIC_EVIDENCE","No mechanistic claim without accessible abstract/full text.","FROZEN"],
        ["REVIEWS_AND_ORIGINAL_STUDIES","BOTH_RETAINED","Later synthesis distinguishes evidence type.","FROZEN"],
        ["EDITORIAL_LETTER_POLICY","METADATA_ONLY_UNLESS_SUBSTANTIVE_ABSTRACT","Avoid unsupported inference.","FROZEN"],
        ["MODULE_EFFECT","LITERATURE_CANNOT_CHANGE_MODULES","No merge/split/reassignment/suppression.","FROZEN"],
        ["HUB_EFFECT","LITERATURE_CANNOT_CHANGE_FROZEN_HUB_STATUS","Contextualization only.","FROZEN"],
        ["ENRICHMENT_EFFECT","LITERATURE_CANNOT_REDEFINE_ENRICHMENT_RESULTS","No pathway re-selection.","FROZEN"],
        ["VALIDATION_LANGUAGE","CONTEXTUAL_SUPPORT_NOT_INDEPENDENT_VALIDATION","No A-CLA validation claim.","FROZEN"],
        ["CONTRADICTORY_LITERATURE","MUST_BE_RETAINED","Negative/contradictory evidence cannot be omitted.","FROZEN"],
        ["ALL_COMMUNITIES","MANDATORY","Every community remains represented.","FROZEN"],
    ]
    pd.DataFrame(policy_rows,columns=["POLICY_ITEM","FROZEN_VALUE","RATIONALE","STATUS"]).to_csv(
        outdir/"D10P_LITERATURE_SEARCH_POLICY.csv",index=False
    )

    contract={
        "D10P_STATUS":"PASS",
        "COMMUNITIES_FROZEN":8,
        "ALL_COMMUNITIES_INCLUDED":"YES",
        "LITERATURE_TARGETS":int(len(target_df)),
        "PUBMED_QUERIES_PLANNED":int(len(query_df)),
        "PUBMED_DATABASE":"pubmed",
        "PUBMED_ESEARCH_SORT":"relevance",
        "PUBMED_RETMAX":50,
        "PUBMED_MIN_DATE":"1900/01/01",
        "PUBMED_MAX_DATE":"2026/09/07",
        "MAX_REQUESTS_PER_SECOND":2.0,
        "NCBI_TOOL":"GSE243219_D10Q",
        "PRIMARY_SEARCH_FIELD":"TITLE_ABSTRACT_EXACT_PHRASE",
        "FALLBACK_POLICY":"UNQUOTED_TITLE_ABSTRACT_ONLY_IF_PRIMARY_COUNT_ZERO",
        "GENE_ALIAS_EXPANSION":"PROHIBITED",
        "D10Q_SCOPE":"SEARCH_RETRIEVAL_AND_PROVENANCE_ONLY",
        "D10Q_BIOLOGICAL_NARRATIVE":"PROHIBITED",
        "LITERATURE_CAN_CHANGE_COMMUNITIES":"NO",
        "LITERATURE_CAN_CHANGE_HUB_STATUS":"NO",
        "LITERATURE_CAN_CHANGE_ENRICHMENT":"NO",
        "CONTRADICTORY_EVIDENCE_MUST_BE_RETAINED":"YES",
        "LITERATURE_CONCORDANCE_COUNTS_AS_ACLA_VALIDATION":"NO",
        "EXTERNAL_LITERATURE_SEARCH_EXECUTED":"NO",
        "READY_FOR_D10Q_PUBMED_RETRIEVAL":"YES",
        "STOP":"YES",
    }
    (outdir/"D10P_EXECUTION_CONTRACT.json").write_text(
        json.dumps(contract,indent=2),encoding="utf-8"
    )

    spec="""# D10P — External Literature Contextualization Design Freeze

## Purpose
Freeze PubMed target selection and retrieval rules before any external search.

## Deterministic targets
1. Every enrichment term displayed by D10O.
2. Top five nodes/community by frozen internal degree for each:
   - COVID-associated hubs
   - COV-vs-sepsis discriminating hubs
   - regulatory-hub evidence nodes
3. No manual target addition/removal in D10Q.

## Search structure
Every target gets:
- a COVID-19/SARS-CoV-2 PubMed search
- a sepsis PubMed search

Primary search uses an exact quoted Title/Abstract target.
Fallback uses an unquoted Title/Abstract target only if the primary count is zero.
No gene-alias expansion.

## PubMed reproducibility
database=pubmed
sort=relevance
retmax=50
datetype=pdat
mindate=1900/01/01
maxdate=2026/09/07
request rate <=2 requests/second
tool=GSE243219_D10Q

## D10Q boundary
Search/retrieval/provenance only. No biological narrative, no cherry-picking,
no module/hub/enrichment changes, and contradictory literature must be retained.
"""
    (outdir/"D10P_DESIGN_SPECIFICATION.md").write_text(spec,encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
