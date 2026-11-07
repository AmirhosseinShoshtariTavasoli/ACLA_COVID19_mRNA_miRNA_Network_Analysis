#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import re
import sys
from pathlib import Path

import pandas as pd

EXPECTED_COMMUNITIES=8
EXPECTED_TARGETS=187
EXPECTED_UNITS=374
EXPECTED_SCREENED_PAIRS=2531
EXPECTED_PMIDS=2137
EXPECTED_ZERO_UNITS=194

EVIDENCE_STATES={
    "ZERO_RETRIEVAL_UNDER_FROZEN_SEARCH",
    "NO_DIRECT_RELEVANT_ABSTRACT_EVIDENCE",
    "CONCORDANT_CONTEXTUAL_SUPPORT_PRESENT",
    "CONCORDANT_WITH_CONTRADICTORY_OR_MIXED_EVIDENCE",
    "CONTRADICTORY_OR_MIXED_EVIDENCE_WITHOUT_CONCORDANT_PAIR",
    "DIRECT_RELEVANCE_WITHOUT_DIRECTIONAL_CONCORDANCE_CLASS",
}

HUMAN_OR_REVIEW_PRIORITY={
    "SYSTEMATIC_REVIEW_OR_META_ANALYSIS":0,
    "ORIGINAL_HUMAN_CLINICAL_OR_COHORT":1,
    "ORIGINAL_HUMAN_OMICS_OR_COMPUTATIONAL":2,
    "NARRATIVE_REVIEW":3,
    "ORIGINAL_EXPERIMENTAL_MODEL":4,
    "CASE_REPORT_OR_CASE_SERIES":5,
    "OTHER_OR_UNCLEAR":6,
    "EDITORIAL_LETTER_COMMENTARY":7,
}

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
    req={"full_path","size_bytes","SHA256"}
    require(req.issubset(df.columns),f"MANIFEST_SCHEMA_INVALID={path}")
    bad=0
    for row in df.itertuples(index=False):
        p=Path(row.full_path)
        if not p.is_file():
            bad+=1; continue
        if int(p.stat().st_size)!=int(row.size_bytes):
            bad+=1; continue
        if sha256_file(p)!=str(row.SHA256).lower():
            bad+=1
    require(bad==0,f"MANIFEST_HASH_MISMATCHES={bad}")

def truthy(x):
    return str(x).strip().lower() in {"true","1","yes"}

def int_or_zero(x):
    try:
        return int(float(x))
    except Exception:
        return 0

def year_num(x):
    try:
        return int(float(x))
    except Exception:
        return -1

def pmid_num(x):
    try:
        return int(str(x))
    except Exception:
        return 10**20

def clean_text(x):
    x=str(x).strip()
    x=re.sub(r"\s+"," ",x)
    return x

def cite_label(row):
    pmid=str(row["pmid"])
    year=clean_text(row.get("publication_year",""))
    journal=clean_text(row.get("journal",""))
    st=clean_text(row.get("study_type_class",""))
    title=clean_text(row.get("title",""))
    bits=[f"PMID {pmid}"]
    if year:
        bits.append(year)
    if journal:
        bits.append(journal)
    if st:
        bits.append(st)
    base=", ".join(bits)
    if title:
        return f"{base}: {title}"
    return base

def select_slot(df, evidence_class=None, study_types=None, limit=1, nondirectional=False):
    z=df.copy()
    if evidence_class is not None:
        z=z[z["evidence_class"]==evidence_class]
    if study_types is not None:
        z=z[z["study_type_class"].isin(study_types)]
    if nondirectional:
        z=z[z["evidence_class"].isin([
            "NO_DIRECTIONAL_CLAIM",
            "RELEVANT_NOT_DIRECTIONALLY_COMPARABLE",
        ])]
        z["_study_priority"]=z["study_type_class"].map(HUMAN_OR_REVIEW_PRIORITY).fillna(99)
        z["_year"]=z["publication_year"].map(year_num)
        z["_pmid"]=z["pmid"].map(pmid_num)
        z=z.sort_values(
            ["_study_priority","_year","_pmid"],
            ascending=[True,False,True]
        )
    else:
        z["_year"]=z["publication_year"].map(year_num)
        z["_pmid"]=z["pmid"].map(pmid_num)
        z=z.sort_values(["_year","_pmid"],ascending=[False,True])
    return z.head(limit).copy()

def synthesis_sentence(state, row):
    direct=int_or_zero(row["direct_pairs"])
    con=int_or_zero(row["concordant_pairs"])
    dis=int_or_zero(row["discordant_pairs"])
    mix=int_or_zero(row["mixed_pairs"])
    nd=int_or_zero(row["nondirectional_pairs"])
    nc=int_or_zero(row["noncomparable_pairs"])
    retrieved=int_or_zero(row["retrieved_pairs"])

    if state=="ZERO_RETRIEVAL_UNDER_FROZEN_SEARCH":
        return (
            "No PubMed records were retrieved under the prospectively frozen query. "
            "This is a retrieval result only and does not establish biological absence."
        )
    if state=="NO_DIRECT_RELEVANT_ABSTRACT_EVIDENCE":
        return (
            f"{retrieved} query-linked record(s) were retrieved, but none met the frozen "
            "title/abstract criterion for direct target–disease evidence."
        )
    if state=="CONCORDANT_CONTEXTUAL_SUPPORT_PRESENT":
        return (
            f"Direct abstract-level literature included {con} concordant contextual-support "
            f"pair(s), with no screened discordant or mixed pair in this target–disease unit. "
            "This is compatibility, not independent validation."
        )
    if state=="CONCORDANT_WITH_CONTRADICTORY_OR_MIXED_EVIDENCE":
        return (
            f"Direct abstract-level literature was heterogeneous: {con} concordant contextual-support "
            f"pair(s), {dis} discordant/contradictory pair(s), and {mix} mixed pair(s). "
            "Supportive and conflicting evidence are therefore interpreted together."
        )
    if state=="CONTRADICTORY_OR_MIXED_EVIDENCE_WITHOUT_CONCORDANT_PAIR":
        return (
            f"Direct abstract-level literature included {dis} discordant/contradictory and "
            f"{mix} mixed pair(s), with no concordant pair under the frozen screening rules. "
            "This inconsistency is retained rather than resolved by vote-counting."
        )
    if state=="DIRECT_RELEVANCE_WITHOUT_DIRECTIONAL_CONCORDANCE_CLASS":
        return (
            f"{direct} directly relevant pair(s) were identified, but they were primarily "
            f"non-directional ({nd}) or not directionally comparable ({nc}); literature relevance "
            "is therefore contextual rather than evidence of directional agreement."
        )
    raise RuntimeError(f"UNKNOWN_SYNTHESIS_STATE={state}")

def project_context_for_category(category, community_row):
    if category=="PRIMARY_FUNCTIONAL_TERM":
        return (
            f"Primary GO:BP/Reactome characterization for this community contained "
            f"{int_or_zero(community_row['primary_GO_BP_REAC_significant_terms'])} significant terms."
        )
    if category=="SECONDARY_KEGG_TERM":
        return (
            f"Secondary KEGG characterization contained "
            f"{int_or_zero(community_row['secondary_KEGG_significant_terms'])} significant terms."
        )
    if category=="REGULATORY_TARGET_FUNCTIONAL_TERM":
        return (
            f"Frozen regulatory-target enrichment contained "
            f"{int_or_zero(community_row['secondary_regulatory_GO_BP_REAC_significant_terms'])} significant terms."
        )
    if category=="COVID_ASSOCIATED_HUB":
        return (
            f"This target belongs to the frozen COVID-associated topology-hub evidence layer; "
            f"the community contains {int_or_zero(community_row['cov_associated_hubs'])} such hub(s)."
        )
    if category=="COV_VS_SEPSIS_DISCRIMINATING_HUB":
        return (
            f"This target belongs to the frozen COV-vs-sepsis discriminating topology-hub layer; "
            f"the community contains {int_or_zero(community_row['cov_vs_sepsis_discriminating_hubs'])} such hub(s)."
        )
    if category=="REGULATORY_HUB_EVIDENCE_NODE":
        return (
            f"This target belongs to the frozen regulatory-hub evidence layer; "
            f"the community contains {int_or_zero(community_row['regulatory_hub_evidence_nodes'])} such node(s)."
        )
    return "Target belongs to a frozen D10P literature-contextualization category."

def main():
    if len(sys.argv)!=12:
        raise SystemExit(
            "usage: D10U <d10t_status> <d10t_manifest> <unit_plan> <narrative_registry> "
            "<citation_rules> <d10s_pairs> <d10o_status> <d10o_manifest> "
            "<d10o_community_table> <d10s_status> <outdir>"
        )

    d10t_status=Path(sys.argv[1])
    d10t_manifest=Path(sys.argv[2])
    unit_plan_path=Path(sys.argv[3])
    narrative_registry_path=Path(sys.argv[4])
    citation_rules_path=Path(sys.argv[5])
    d10s_pairs_path=Path(sys.argv[6])
    d10o_status=Path(sys.argv[7])
    d10o_manifest=Path(sys.argv[8])
    d10o_community_path=Path(sys.argv[9])
    d10s_status=Path(sys.argv[10])
    outdir=Path(sys.argv[11])
    outdir.mkdir(parents=True,exist_ok=True)

    tt=d10t_status.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10T_STATUS=PASS",
        "COMMUNITIES_FROZEN=8",
        "LITERATURE_TARGETS=187",
        "TARGET_DISEASE_SYNTHESIS_UNITS=374",
        "SCREENED_QUERY_PMID_PAIRS=2531",
        "UNIQUE_PMIDS=2137",
        "ALL_TARGET_DISEASE_UNITS_RETAINED=YES",
        "ALL_8_COMMUNITIES_REQUIRE_NARRATIVE=YES",
        "NARRATIVE_TARGET_SELECTION=PRE_LITERATURE_D10P_CATEGORY_RANK_ONLY",
        "LITERATURE_OUTCOME_CAN_CHANGE_NARRATIVE_TARGET_SELECTION=NO",
        "EVIDENCE_SCORE_CREATED=NO",
        "VOTE_COUNTING_AUTHORIZED=NO",
        "CONTRADICTORY_EVIDENCE_DISPLAY_MANDATORY=YES",
        "SYSTEMATIC_REVIEW_CLAIM_AUTHORIZED=NO",
        "FULL_TEXT_REVIEW_CLAIM_AUTHORIZED=NO",
        "NEW_LITERATURE_SEARCH_AUTHORIZED=NO",
        "NEW_BIOLOGICAL_ANALYSIS_AUTHORIZED=NO",
        "LITERATURE_SYNTHESIS_EXECUTED=NO",
        "READY_FOR_D10U_LITERATURE_SYNTHESIS_EXECUTION=YES",
    ]:
        require(tok in tt,f"D10T_AUTHORITY_TOKEN_MISSING={tok}")
    verify_manifest(d10t_manifest)

    st=d10s_status.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10S_STATUS=PASS",
        "SCREENING_QUERY_PMID_PAIRS=2531",
        "UNIQUE_PMIDS_IN_SCREENING_UNIVERSE=2137",
        "ALL_QUERY_PMID_PAIRS_SCREENED=YES",
        "CONTRADICTORY_EVIDENCE_RETAINED=YES",
        "BIOLOGICAL_NARRATIVE_EXECUTED=NO",
    ]:
        require(tok in st,f"D10S_AUTHORITY_TOKEN_MISSING={tok}")

    ot=d10o_status.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10O_STATUS=PASS",
        "COMMUNITIES_INTERPRETED=8",
        "ALL_8_COMMUNITIES_REPORTED=YES",
        "BIOLOGICAL_INTERPRETATION_EXECUTED=YES_EVIDENCE_SYNTHESIS_ONLY",
    ]:
        require(tok in ot,f"D10O_AUTHORITY_TOKEN_MISSING={tok}")
    verify_manifest(d10o_manifest)

    units=pd.read_csv(unit_plan_path,dtype=str,keep_default_na=False)
    registry=pd.read_csv(narrative_registry_path,dtype=str,keep_default_na=False)
    citation_rules=pd.read_csv(citation_rules_path,dtype=str,keep_default_na=False)
    pairs=pd.read_csv(d10s_pairs_path,dtype=str,keep_default_na=False)
    comm=pd.read_csv(d10o_community_path,dtype=str,keep_default_na=False)

    require(len(units)==EXPECTED_UNITS,f"UNIT_ROWS={len(units)}")
    require(units[["target_id","disease_context"]].drop_duplicates().shape[0]==EXPECTED_UNITS,
            "TARGET_DISEASE_UNITS_NOT_UNIQUE")
    require(len(registry)==EXPECTED_TARGETS,f"NARRATIVE_REGISTRY_TARGET_ROWS={len(registry)}")
    require(registry["target_id"].nunique()==EXPECTED_TARGETS,"NARRATIVE_REGISTRY_TARGET_IDS_CHANGED")
    require(len(pairs)==EXPECTED_SCREENED_PAIRS,f"SCREENED_PAIR_ROWS={len(pairs)}")
    require(pairs["pmid"].nunique()==EXPECTED_PMIDS,f"SCREENED_PMIDS={pairs['pmid'].nunique()}")
    require(len(comm)==EXPECTED_COMMUNITIES,f"D10O_COMMUNITY_ROWS={len(comm)}")
    require(set(pd.to_numeric(comm["community_id"]).astype(int))==set(range(1,9)),
            "D10O_COMMUNITY_IDS_CHANGED")
    require(set(units["frozen_literature_synthesis_state"]).issubset(EVIDENCE_STATES),
            "UNKNOWN_FROZEN_SYNTHESIS_STATE")

    # Canonical types.
    units["community_id"]=pd.to_numeric(units["community_id"],errors="coerce")
    registry["community_id"]=pd.to_numeric(registry["community_id"],errors="coerce")
    registry["category_rank"]=pd.to_numeric(registry["category_rank"],errors="coerce")
    pairs["community_id"]=pd.to_numeric(pairs["community_id"],errors="coerce")
    comm["community_id"]=pd.to_numeric(comm["community_id"],errors="coerce")
    require(
        units["community_id"].notna().all() and registry["community_id"].notna().all()
        and pairs["community_id"].notna().all() and comm["community_id"].notna().all(),
        "COMMUNITY_ID_PARSE_FAILURE"
    )
    for df in [units,registry,pairs,comm]:
        df["community_id"]=df["community_id"].astype(int)

    # D10U-R2 correction:
    # D10T-R2 freezes zero retrieval through retrieved_pairs==0 and the
    # categorical frozen_literature_synthesis_state. It does not require a
    # physical zero_retrieval_under_frozen_search column. Derive that convenience
    # column here and fail closed unless both frozen representations agree exactly.
    required_unit_cols={
        "retrieved_pairs",
        "frozen_literature_synthesis_state",
        "target_id","community_id","target_category","target_label","disease_context",
        "narrative_target_included",
        "concordant_pairs","discordant_pairs","mixed_pairs",
    }
    missing_unit_cols=sorted(required_unit_cols-set(units.columns))
    require(
        len(missing_unit_cols)==0,
        f"D10T_UNIT_PLAN_REQUIRED_COLUMNS_MISSING={missing_unit_cols}"
    )

    units["retrieved_pairs"]=pd.to_numeric(units["retrieved_pairs"],errors="coerce")
    require(
        units["retrieved_pairs"].notna().all(),
        "D10T_UNIT_PLAN_RETRIEVED_PAIRS_NONNUMERIC_OR_NA"
    )
    require(
        (units["retrieved_pairs"]>=0).all(),
        "D10T_UNIT_PLAN_RETRIEVED_PAIRS_NEGATIVE"
    )
    units["retrieved_pairs"]=units["retrieved_pairs"].astype(int)

    units["zero_retrieval_under_frozen_search"]=units["retrieved_pairs"].eq(0)
    state_zero=units["frozen_literature_synthesis_state"].eq(
        "ZERO_RETRIEVAL_UNDER_FROZEN_SEARCH"
    )
    require(
        (units["zero_retrieval_under_frozen_search"]==state_zero).all(),
        "D10T_ZERO_RETRIEVAL_REPRESENTATIONS_DISAGREE"
    )
    require(
        int(units["zero_retrieval_under_frozen_search"].sum())==EXPECTED_ZERO_UNITS,
        f"D10T_ZERO_RETRIEVAL_UNIT_COUNT_CHANGED={int(units['zero_retrieval_under_frozen_search'].sum())}"
    )

    registry["narrative_target_included"]=registry["narrative_target_included"].map(truthy)
    narrative_targets=registry[registry["narrative_target_included"]].copy()
    require(len(narrative_targets)>0,"NO_NARRATIVE_TARGETS")
    require(set(narrative_targets["community_id"])==set(range(1,9)),
            "NARRATIVE_TARGETS_NOT_ALL_8_COMMUNITIES")

    # Complete 374-row evidence matrix.
    matrix=units.copy()
    matrix["zero_retrieval_counts_as_negative_biological_evidence"]="NO"
    matrix["literature_concordance_counts_as_acla_validation"]="NO"
    matrix["evidence_score"]="PROHIBITED"
    matrix["vote_counting"]="PROHIBITED"
    matrix["new_search_executed"]="NO"
    matrix["new_biological_analysis_executed"]="NO"
    matrix.to_csv(outdir/"D10U_COMPLETE_TARGET_DISEASE_EVIDENCE_MATRIX.csv",index=False)

    # Deterministic citation exemplars for narrative-displayed targets.
    selected_rows=[]
    narrative_units=matrix[matrix["narrative_target_included"].map(truthy)].copy()
    require(
        narrative_units[["target_id","disease_context"]].drop_duplicates().shape[0]==len(narrative_units),
        "NARRATIVE_TARGET_DISEASE_UNITS_DUPLICATED"
    )

    for ur in narrative_units.itertuples(index=False):
        tid=str(ur.target_id)
        disease=str(ur.disease_context)
        g=pairs[
            (pairs["target_id"].astype(str)==tid) &
            (pairs["disease_context"].astype(str)==disease) &
            (pairs["relevance_class"]=="DIRECT_TARGET_DISEASE")
        ].copy()

        slots=[
            ("CONCORDANT_SYSTEMATIC_REVIEW",
             select_slot(
                 g,
                 evidence_class="CONCORDANT_CONTEXTUAL_SUPPORT",
                 study_types={"SYSTEMATIC_REVIEW_OR_META_ANALYSIS"},
                 limit=1
             )),
            ("CONCORDANT_ORIGINAL_HUMAN",
             select_slot(
                 g,
                 evidence_class="CONCORDANT_CONTEXTUAL_SUPPORT",
                 study_types={
                     "ORIGINAL_HUMAN_CLINICAL_OR_COHORT",
                     "ORIGINAL_HUMAN_OMICS_OR_COMPUTATIONAL",
                 },
                 limit=2
             )),
            ("DISCORDANT_OR_CONTRADICTORY",
             select_slot(
                 g,
                 evidence_class="DISCORDANT_OR_CONTRADICTORY",
                 study_types=None,
                 limit=2
             )),
            ("MIXED_WITHIN_RECORD",
             select_slot(
                 g,
                 evidence_class="MIXED_WITHIN_RECORD",
                 study_types=None,
                 limit=1
             )),
            ("DIRECT_NONDIRECTIONAL_CONTEXT",
             select_slot(
                 g,
                 evidence_class=None,
                 study_types=None,
                 limit=1,
                 nondirectional=True
             )),
        ]

        seen_pmids=set()
        for slot_name,z in slots:
            slot_rank=0
            for _,row in z.iterrows():
                pmid=str(row["pmid"])
                if pmid in seen_pmids:
                    continue
                seen_pmids.add(pmid)
                slot_rank+=1
                selected_rows.append({
                    "target_id":tid,
                    "community_id":int(ur.community_id),
                    "target_category":str(ur.target_category),
                    "target_label":str(ur.target_label),
                    "disease_context":disease,
                    "frozen_literature_synthesis_state":str(ur.frozen_literature_synthesis_state),
                    "citation_slot":slot_name,
                    "slot_rank":slot_rank,
                    "pmid":pmid,
                    "publication_year":row.get("publication_year",""),
                    "journal":row.get("journal",""),
                    "study_type_class":row.get("study_type_class",""),
                    "evidence_class":row.get("evidence_class",""),
                    "title":row.get("title",""),
                    "doi":row.get("doi",""),
                    "pmc":row.get("pmc",""),
                    "screening_reason":row.get("screening_reason",""),
                    "citation_label":cite_label(row),
                })

    selected=pd.DataFrame(selected_rows)
    if len(selected)==0:
        selected=pd.DataFrame(columns=[
            "target_id","community_id","target_category","target_label","disease_context",
            "frozen_literature_synthesis_state","citation_slot","slot_rank","pmid",
            "publication_year","journal","study_type_class","evidence_class","title",
            "doi","pmc","screening_reason","citation_label"
        ])
    selected.to_csv(outdir/"D10U_DETERMINISTIC_CITATION_EXEMPLARS.csv",index=False)

    # Validate contradiction visibility: every narrative unit with discordant/mixed evidence
    # and at least one corresponding direct pair must have a selected contradiction/mixed exemplar,
    # subject to the frozen slot limits.
    contradiction_required=narrative_units[
        (pd.to_numeric(narrative_units["discordant_pairs"],errors="coerce").fillna(0)>0) |
        (pd.to_numeric(narrative_units["mixed_pairs"],errors="coerce").fillna(0)>0)
    ][["target_id","disease_context"]].drop_duplicates()

    selected_contra=selected[
        selected["citation_slot"].isin(["DISCORDANT_OR_CONTRADICTORY","MIXED_WITHIN_RECORD"])
    ][["target_id","disease_context"]].drop_duplicates()

    merged_contra=contradiction_required.merge(
        selected_contra,
        on=["target_id","disease_context"],
        how="left",
        indicator=True
    )
    require(
        (merged_contra["_merge"]=="both").all(),
        "CONTRADICTORY_OR_MIXED_NARRATIVE_UNIT_MISSING_MANDATORY_EXEMPLAR"
    )

    # Community-level synthesis summary.
    unit_state_counts=(
        matrix.groupby(["community_id","frozen_literature_synthesis_state"])
        .size().reset_index(name="target_disease_units")
    )
    unit_state_counts.to_csv(outdir/"D10U_COMMUNITY_EVIDENCE_STATE_COUNTS.csv",index=False)

    narrative_unit_summary=(
        narrative_units.groupby("community_id")
        .agg(
            narrative_target_disease_units=("target_id","count"),
            narrative_targets=("target_id","nunique"),
            zero_retrieval_units=("zero_retrieval_under_frozen_search",lambda x:int(pd.Series(x).map(truthy).sum())),
            units_with_concordant=("concordant_pairs",lambda x:int((pd.to_numeric(x,errors="coerce").fillna(0)>0).sum())),
            units_with_discordant=("discordant_pairs",lambda x:int((pd.to_numeric(x,errors="coerce").fillna(0)>0).sum())),
            units_with_mixed=("mixed_pairs",lambda x:int((pd.to_numeric(x,errors="coerce").fillna(0)>0).sum())),
        )
        .reset_index()
    )
    narrative_unit_summary.to_csv(outdir/"D10U_COMMUNITY_NARRATIVE_EVIDENCE_SUMMARY.csv",index=False)

    # Generate narrative report.
    comm_map={
        int(r["community_id"]):r
        for _,r in comm.iterrows()
    }

    report=[]
    report.append("# D10U — Literature-Contextualized Biological Synthesis")
    report.append("")
    report.append("## Scope and interpretation boundary")
    report.append("")
    report.append(
        "This report integrates the frozen GSE243219 community-level biological characterization "
        "with deterministic PubMed title/abstract/metadata screening. It is not a systematic review, "
        "meta-analysis, full-text review, or formal risk-of-bias assessment. Literature concordance "
        "is contextual compatibility only and does not independently validate A-CLA, the community "
        "partition, hubs, enrichment, or causal/clinical claims."
    )
    report.append("")
    report.append(
        "All 187 literature targets × 2 disease contexts are retained in the accompanying 374-row "
        "evidence matrix. Narrative target selection was fixed before literature outcome using D10P "
        "category rank; literature strength cannot substitute a lower-ranked target."
    )
    report.append("")

    category_order=[
        "PRIMARY_FUNCTIONAL_TERM",
        "SECONDARY_KEGG_TERM",
        "REGULATORY_TARGET_FUNCTIONAL_TERM",
        "COVID_ASSOCIATED_HUB",
        "COV_VS_SEPSIS_DISCRIMINATING_HUB",
        "REGULATORY_HUB_EVIDENCE_NODE",
    ]
    category_title={
        "PRIMARY_FUNCTIONAL_TERM":"Primary GO:BP / Reactome targets",
        "SECONDARY_KEGG_TERM":"Secondary KEGG targets",
        "REGULATORY_TARGET_FUNCTIONAL_TERM":"Regulatory-target functional targets",
        "COVID_ASSOCIATED_HUB":"COVID-associated hub targets",
        "COV_VS_SEPSIS_DISCRIMINATING_HUB":"COV-vs-sepsis discriminating hub targets",
        "REGULATORY_HUB_EVIDENCE_NODE":"Regulatory-hub evidence targets",
    }

    for cid in range(1,9):
        crow=comm_map[cid]
        report.append(f"## Community {cid}")
        report.append("")
        report.append(
            f"**Frozen project context.** {int_or_zero(crow['nodes_total'])} nodes "
            f"({int_or_zero(crow['mrna_nodes'])} mRNAs; {int_or_zero(crow['mirna_nodes'])} miRNAs). "
            f"COV-vs-H significant nodes: {int_or_zero(crow['COV_vs_H_significant_nodes'])}; "
            f"P-vs-H significant nodes: {int_or_zero(crow['P_vs_H_significant_nodes'])}; "
            f"COV-vs-P significant nodes: {int_or_zero(crow['COV_vs_P_significant_nodes'])}. "
            f"Primary topology hubs: {int_or_zero(crow['primary_topological_hubs'])}; "
            f"regulatory-hub evidence nodes: {int_or_zero(crow['regulatory_hub_evidence_nodes'])}."
        )
        report.append("")
        report.append(
            f"Primary functional characterization identified "
            f"{int_or_zero(crow['primary_GO_BP_REAC_significant_terms'])} significant GO:BP/Reactome "
            f"terms; secondary KEGG identified {int_or_zero(crow['secondary_KEGG_significant_terms'])}; "
            f"frozen regulatory-target enrichment identified "
            f"{int_or_zero(crow['secondary_regulatory_GO_BP_REAC_significant_terms'])} significant terms."
        )
        report.append("")

        ctargets=narrative_targets[narrative_targets["community_id"]==cid].copy()
        ctargets["category_rank"]=pd.to_numeric(ctargets["category_rank"],errors="coerce").fillna(9999).astype(int)

        for cat in category_order:
            g=ctargets[ctargets["target_category"]==cat].sort_values(
                ["category_rank","target_label","target_id"]
            )
            if len(g)==0:
                continue
            report.append(f"### {category_title[cat]}")
            report.append("")
            for tr in g.itertuples(index=False):
                tid=str(tr.target_id)
                label=str(tr.target_label)
                rank=int(tr.category_rank)
                report.append(f"#### {label} (frozen category rank {rank})")
                report.append("")
                report.append(project_context_for_category(cat,crow))
                report.append("")

                for disease in ["COVID19","SEPSIS"]:
                    ur=matrix[
                        (matrix["target_id"].astype(str)==tid) &
                        (matrix["disease_context"].astype(str)==disease)
                    ]
                    require(len(ur)==1,f"TARGET_DISEASE_UNIT_LOOKUP_FAILED target={tid} disease={disease}")
                    rr=ur.iloc[0]
                    state=str(rr["frozen_literature_synthesis_state"])
                    report.append(f"**{disease} literature context.** {synthesis_sentence(state,rr)}")

                    cg=selected[
                        (selected["target_id"].astype(str)==tid) &
                        (selected["disease_context"].astype(str)==disease)
                    ].copy()
                    if len(cg):
                        report.append("")
                        report.append("Selected frozen citation exemplars:")
                        for cr in cg.sort_values(
                            ["citation_slot","slot_rank","pmid"]
                        ).itertuples(index=False):
                            qualifier={
                                "CONCORDANT_SYSTEMATIC_REVIEW":"concordant review/meta-analysis context",
                                "CONCORDANT_ORIGINAL_HUMAN":"concordant original-human context",
                                "DISCORDANT_OR_CONTRADICTORY":"discordant/contradictory context",
                                "MIXED_WITHIN_RECORD":"mixed evidence",
                                "DIRECT_NONDIRECTIONAL_CONTEXT":"direct nondirectional/noncomparable context",
                            }.get(str(cr.citation_slot),str(cr.citation_slot))
                            report.append(
                                f"- {qualifier}: {clean_text(cr.citation_label)}"
                            )
                    report.append("")
                report.append(
                    "**Boundary.** The literature statements above contextualize the frozen project "
                    "result; they do not modify target rank, community membership, hub status, enrichment, "
                    "or the A-CLA result."
                )
                report.append("")

        report.append(
            "**Community-level conclusion boundary.** Community interpretation remains "
            "hypothesis-generating and association-based. The A-CLA partition was topology-derived; "
            "literature agreement or disagreement is contextual evidence rather than algorithmic validation."
        )
        report.append("")

    (outdir/"D10U_LITERATURE_CONTEXTUALIZED_BIOLOGICAL_SYNTHESIS.md").write_text(
        "\n".join(report),encoding="utf-8"
    )

    limitations="""# D10U — Mandatory Limitations

1. D10S used deterministic automated screening of PubMed titles, abstracts, and metadata.
2. No full-text screening or formal risk-of-bias assessment was performed.
3. This is not a PRISMA systematic review or meta-analysis.
4. One PMID may map to multiple target/query pairs; this is one publication reused contextually, not multiple independent studies.
5. Citation counts are not evidence-strength scores and no vote-counting was used.
6. Zero retrieval under a frozen query does not establish biological absence.
7. No-abstract records are metadata-only.
8. Contradictory and mixed evidence is retained and surfaced for narrative-displayed targets.
9. Literature concordance means contextual compatibility only, not validation of A-CLA.
10. Literature did not alter communities, hubs, enrichment, DE, or network structure.
11. The A-CLA partition is based on the unweighted all-association topology projection; signed/regulatory evidence remained post hoc.
12. RUN_COUNT=1; multi-seed or perturbation stability is not established.
13. Causal, diagnostic, prognostic, or therapeutic claims require independent validation.
"""
    (outdir/"D10U_MANDATORY_LIMITATIONS.md").write_text(limitations,encoding="utf-8")

    # Final summary.
    state_counts=matrix["frozen_literature_synthesis_state"].value_counts().to_dict()
    summary={
        "D10U_STATUS":"PASS",
        "COMMUNITIES_SYNTHESIZED":8,
        "LITERATURE_TARGETS":187,
        "TARGET_DISEASE_UNITS":374,
        "SCREENED_QUERY_PMID_PAIRS":2531,
        "UNIQUE_PMIDS":2137,
        "NARRATIVE_TARGETS":int(narrative_targets["target_id"].nunique()),
        "NARRATIVE_TARGET_DISEASE_UNITS":int(len(narrative_units)),
        "DETERMINISTIC_CITATION_EXEMPLARS_SELECTED":int(len(selected)),
        "ZERO_RETRIEVAL_UNITS":int(state_counts.get("ZERO_RETRIEVAL_UNDER_FROZEN_SEARCH",0)),
        "NO_DIRECT_RELEVANT_ABSTRACT_EVIDENCE_UNITS":int(state_counts.get("NO_DIRECT_RELEVANT_ABSTRACT_EVIDENCE",0)),
        "CONCORDANT_ONLY_UNITS":int(state_counts.get("CONCORDANT_CONTEXTUAL_SUPPORT_PRESENT",0)),
        "CONCORDANT_WITH_CONTRADICTORY_OR_MIXED_UNITS":int(state_counts.get("CONCORDANT_WITH_CONTRADICTORY_OR_MIXED_EVIDENCE",0)),
        "CONTRADICTORY_OR_MIXED_WITHOUT_CONCORDANT_UNITS":int(state_counts.get("CONTRADICTORY_OR_MIXED_EVIDENCE_WITHOUT_CONCORDANT_PAIR",0)),
        "DIRECT_RELEVANCE_WITHOUT_DIRECTIONAL_CONCORDANCE_UNITS":int(state_counts.get("DIRECT_RELEVANCE_WITHOUT_DIRECTIONAL_CONCORDANCE_CLASS",0)),
        "ALL_374_TARGET_DISEASE_UNITS_RETAINED":"YES",
        "ALL_8_COMMUNITIES_NARRATED":"YES",
        "NARRATIVE_TARGET_SELECTION_CHANGED_BY_LITERATURE":"NO",
        "CONTRADICTORY_EVIDENCE_DISPLAYED_WHEN_PRESENT":"YES",
        "EVIDENCE_SCORE_CREATED":"NO",
        "VOTE_COUNTING_EXECUTED":"NO",
        "NEW_LITERATURE_SEARCH_EXECUTED":"NO",
        "FULL_TEXT_REVIEW_EXECUTED":"NO",
        "SYSTEMATIC_REVIEW_CLAIM_CREATED":"NO",
        "NEW_BIOLOGICAL_ANALYSIS_EXECUTED":"NO",
        "COMMUNITY_ASSIGNMENTS_CHANGED":"NO",
        "HUB_STATUS_CHANGED":"NO",
        "ENRICHMENT_CHANGED":"NO",
        "LITERATURE_CONCORDANCE_COUNTS_AS_ACLA_VALIDATION":"NO",
        "CAUSAL_OR_CLINICAL_CLAIMS_CREATED":"NO",
        "LITERATURE_SYNTHESIS_EXECUTED":"YES",
        "D10U_R2_CORRECTION":"DERIVE_ZERO_RETRIEVAL_BOOLEAN_FROM_FROZEN_RETRIEVED_PAIRS",
        "D10U_R2_ZERO_RETRIEVAL_STATE_CONSISTENCY_GATE":"PASS",
        "D10U_R2_SCIENTIFIC_POLICY_CHANGED":"NO",
        "READY_FOR_D10V_FINAL_REPORTING_PACKAGE_DESIGN":"YES",
        "STOP":"YES",
    }
    require(summary["ZERO_RETRIEVAL_UNITS"]==EXPECTED_ZERO_UNITS,
            f"ZERO_RETRIEVAL_UNIT_COUNT_CHANGED={summary['ZERO_RETRIEVAL_UNITS']}")
    (outdir/"D10U_SUMMARY.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")

    return 0

if __name__=="__main__":
    raise SystemExit(main())
