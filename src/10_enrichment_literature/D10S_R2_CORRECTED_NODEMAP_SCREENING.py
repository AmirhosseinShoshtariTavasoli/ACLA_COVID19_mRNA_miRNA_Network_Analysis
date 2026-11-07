#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import re
import sys
from pathlib import Path

import pandas as pd

EXPECTED_PAIRS=2531
EXPECTED_PMIDS=2137
EXPECTED_COMMUNITIES=8
EXPECTED_NO_ABSTRACT=5

HUB_CATEGORIES={
    "COVID_ASSOCIATED_HUB",
    "COV_VS_SEPSIS_DISCRIMINATING_HUB",
    "REGULATORY_HUB_EVIDENCE_NODE",
}
PATHWAY_CATEGORIES={
    "PRIMARY_FUNCTIONAL_TERM",
    "SECONDARY_KEGG_TERM",
    "REGULATORY_TARGET_FUNCTIONAL_TERM",
}

UP_PATTERNS=[
    r"\bup[- ]?regulat(?:e|ed|ion|ing)\w*\b",
    r"\bincreas(?:e|ed|es|ing)\b",
    r"\belevat(?:e|ed|ion|ing)\w*\b",
    r"\bhigher\b",
    r"\boverexpress(?:ed|ion|ing)?\b",
    r"\bactivat(?:e|ed|ion|ing)\w*\b",
    r"\benhanc(?:e|ed|ement|ing)\w*\b",
    r"\binduc(?:e|ed|tion|ing)\w*\b",
]
DOWN_PATTERNS=[
    r"\bdown[- ]?regulat(?:e|ed|ion|ing)\w*\b",
    r"\bdecreas(?:e|ed|es|ing)\b",
    r"\breduc(?:e|ed|tion|ing)\w*\b",
    r"\blower\b",
    r"\bunderexpress(?:ed|ion|ing)?\b",
    r"\bsuppress(?:ed|ion|ing)?\b",
    r"\binhibit(?:ed|ion|ing)?\b",
    r"\battenuat(?:e|ed|ion|ing)\w*\b",
]
NULL_PATTERNS=[
    r"\bno significant (?:association|difference|change|correlation)\b",
    r"\bnot significantly (?:associated|different|changed|correlated)\b",
    r"\bwas not associated\b",
    r"\bwere not associated\b",
    r"\bno association\b",
    r"\bno difference\b",
]
ASSOC_PATTERNS=[
    r"\bassociat(?:e|ed|ion)\w*\b",
    r"\bcorrelat(?:e|ed|ion)\w*\b",
    r"\blink(?:ed|age)?\b",
    r"\bpredict(?:ed|ive|or|ion)\w*\b",
]

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

def norm(s):
    s=str(s).lower()
    s=re.sub(r"[\u2010-\u2015]","-",s)
    s=re.sub(r"[^a-z0-9+\-/ ]+"," ",s)
    s=re.sub(r"\s+"," ",s).strip()
    return s

def sentences(text):
    text=str(text).replace("\r"," ").replace("\n"," ")
    parts=re.split(r"(?<=[.!?;])\s+",text)
    return [p.strip() for p in parts if p.strip()]

def disease_present(text, disease):
    x=norm(text)
    if disease=="COVID19":
        pats=[
            r"\bcovid[- ]?19\b",
            r"\bsars[- ]?cov[- ]?2\b",
            r"\bcoronavirus disease 2019\b",
        ]
    else:
        pats=[
            r"\bsepsis\b",
            r"\bseptic\b",
        ]
    return any(re.search(p,x,re.I) for p in pats)

def target_direct_match(target, text, is_hub):
    t=norm(target)
    x=norm(text)
    if not t:
        return False, "EMPTY_TARGET"
    if is_hub:
        # Exact symbol/identifier boundary after punctuation normalization.
        pat=r"(?<![a-z0-9])"+re.escape(t)+r"(?![a-z0-9])"
        return bool(re.search(pat,x,re.I)), "EXACT_SYMBOL_BOUNDARY"
    # Functional/pathway target: exact normalized phrase first.
    if t in x:
        return True, "EXACT_NORMALIZED_PHRASE"
    toks=[z for z in t.split() if len(z)>=4 and z not in {
        "process","pathway","signaling","response","regulation","activity","system"
    }]
    toks=list(dict.fromkeys(toks))
    if len(toks)>=2:
        best=0.0
        for s in sentences(x):
            sn=norm(s)
            hit=sum(1 for tok in toks if re.search(r"\b"+re.escape(tok)+r"\b",sn))
            best=max(best,hit/len(toks))
        if best>=0.80:
            return True, f"TOKEN_SENTENCE_COVERAGE_{best:.2f}"
    return False, "NO_SUBSTANTIVE_TARGET_MATCH"

def study_type(pubtypes,title,abstract):
    p=norm(pubtypes)
    ta=norm(str(title)+" "+str(abstract))
    if "meta-analysis" in p or "systematic review" in p or "meta analysis" in ta or "systematic review" in ta:
        return "SYSTEMATIC_REVIEW_OR_META_ANALYSIS"
    if any(z in p for z in ["case reports","case report"]):
        return "CASE_REPORT_OR_CASE_SERIES"
    if any(z in p for z in ["editorial","letter","comment","news"]):
        return "EDITORIAL_LETTER_COMMENTARY"
    if "review" in p:
        return "NARRATIVE_REVIEW"
    human_markers=[
        "patients","participants","cohort","clinical","hospital","adults","children",
        "subjects","plasma","serum","whole blood","peripheral blood","pbmc",
    ]
    omics_markers=[
        "transcriptom","rna-seq","rna sequencing","microarray","proteom","metabolom",
        "bioinformatic","gene expression","single-cell","single cell","sequencing",
    ]
    model_markers=[
        "mice","mouse","murine","rats","rat ","cell line","in vitro","in vivo",
        "animal model","cultured cells","organoid",
    ]
    has_human=any(z in ta for z in human_markers)
    has_omics=any(z in ta for z in omics_markers)
    has_model=any(z in ta for z in model_markers)
    if has_human and has_omics:
        return "ORIGINAL_HUMAN_OMICS_OR_COMPUTATIONAL"
    if has_human:
        return "ORIGINAL_HUMAN_CLINICAL_OR_COHORT"
    if has_model:
        return "ORIGINAL_EXPERIMENTAL_MODEL"
    return "OTHER_OR_UNCLEAR"

def local_target_sentences(target,text,is_hub):
    out=[]
    for s in sentences(text):
        direct,_=target_direct_match(target,s,is_hub)
        if direct:
            out.append(s)
    return out

def direction_signal(target_sents):
    if not target_sents:
        return "NONE"
    x=" ".join(norm(s) for s in target_sents)
    has_null=any(re.search(p,x,re.I) for p in NULL_PATTERNS)
    has_up=any(re.search(p,x,re.I) for p in UP_PATTERNS)
    has_down=any(re.search(p,x,re.I) for p in DOWN_PATTERNS)
    has_assoc=any(re.search(p,x,re.I) for p in ASSOC_PATTERNS)
    if has_up and has_down:
        return "MIXED"
    if has_null and not (has_up or has_down):
        return "NULL"
    if has_up:
        return "UP"
    if has_down:
        return "DOWN"
    if has_assoc:
        return "ASSOCIATED"
    return "NONE"

def comparable_study(st):
    return st in {
        "SYSTEMATIC_REVIEW_OR_META_ANALYSIS",
        "ORIGINAL_HUMAN_CLINICAL_OR_COHORT",
        "ORIGINAL_HUMAN_OMICS_OR_COMPUTATIONAL",
        "NARRATIVE_REVIEW",
    }

def project_direction(node_row, disease):
    if node_row is None:
        return "NOT_APPLICABLE","NOT_APPLICABLE",None,None
    if disease=="COVID19":
        fdr=float(node_row["COV_vs_H_FDR"])
        lfc=float(node_row["COV_vs_H_logFC"])
        contrast="COV_vs_H"
    else:
        fdr=float(node_row["P_vs_H_FDR"])
        lfc=float(node_row["P_vs_H_logFC"])
        contrast="P_vs_H"
    if fdr>0.05:
        return "NOT_SIGNIFICANT",contrast,fdr,lfc
    if lfc>0:
        return "UP",contrast,fdr,lfc
    if lfc<0:
        return "DOWN",contrast,fdr,lfc
    return "ZERO",contrast,fdr,lfc

def main():
    if len(sys.argv)!=9:
        raise SystemExit(
            "usage: D10S <d10r_status> <d10r_manifest> <screening_universe> "
            "<d10q_query_results> <d10n_node_evidence> <d10q_status> "
            "<d10n_status> <outdir>"
        )

    d10r_status=Path(sys.argv[1])
    d10r_manifest=Path(sys.argv[2])
    universe_path=Path(sys.argv[3])
    query_results_path=Path(sys.argv[4])
    node_ev_path=Path(sys.argv[5])
    d10q_status=Path(sys.argv[6])
    d10n_status=Path(sys.argv[7])
    outdir=Path(sys.argv[8])
    outdir.mkdir(parents=True,exist_ok=True)

    rt=d10r_status.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10R_STATUS=PASS",
        "SCREENING_QUERY_PMID_PAIRS=2531",
        "SCREENING_UNIT=QUERY_PMID_PAIR",
        "ALL_QUERY_PMID_PAIRS_MUST_BE_SCREENED=YES",
        "SCREENING_SOURCE=PUBMED_TITLE_ABSTRACT_METADATA_ONLY",
        "FULL_TEXT_SCREENING_AUTHORIZED=NO",
        "NEW_LITERATURE_SEARCH_AUTHORIZED=NO",
        "GENE_ALIAS_EXPANSION_AUTHORIZED=NO",
        "CONTRADICTORY_EVIDENCE_MUST_BE_RETAINED=YES",
        "D10S_BIOLOGICAL_NARRATIVE_AUTHORIZED=NO",
        "READY_FOR_D10S_LITERATURE_SCREENING_AND_CLASSIFICATION=YES",
    ]:
        require(tok in rt,f"D10R_AUTHORITY_TOKEN_MISSING={tok}")
    verify_manifest(d10r_manifest)

    qt=d10q_status.read_text(encoding="utf-8-sig",errors="replace")
    require("D10Q_STATUS=PASS" in qt,"D10Q_NOT_PASS")
    require("LITERATURE_SCREENING_EXECUTED=NO" in qt,"D10Q_SCREENING_ALREADY_EXECUTED")

    nt=d10n_status.read_text(encoding="utf-8-sig",errors="replace")
    require("D10N_STATUS=PASS" in nt,"D10N_NOT_PASS")
    require("COMMUNITIES_ANALYZED=8" in nt,"D10N_COMMUNITY_COUNT_CHANGED")

    u=pd.read_csv(universe_path,dtype=str,keep_default_na=False)
    q=pd.read_csv(query_results_path,dtype=str,keep_default_na=False)
    nodes=pd.read_csv(node_ev_path,low_memory=False)

    require(len(u)==EXPECTED_PAIRS,f"SCREENING_UNIVERSE_ROWS={len(u)}")
    require(u["screening_pair_id"].nunique()==EXPECTED_PAIRS,"DUPLICATE_SCREENING_PAIR_IDS")
    require(u[["query_id","pmid"]].drop_duplicates().shape[0]==EXPECTED_PAIRS,
            "DUPLICATE_QUERY_PMID_PAIRS")
    require(u["pmid"].nunique()==EXPECTED_PMIDS,f"UNIQUE_PMIDS={u['pmid'].nunique()}")
    require(set(pd.to_numeric(u["community_id"]).astype(int))==set(range(1,9)),
            "SCREENING_UNIVERSE_NOT_ALL_8")

    require(len(q)==374,"QUERY_RESULT_COUNT_CHANGED")
    require(q["query_id"].nunique()==374,"QUERY_RESULT_IDS_CHANGED")

    nodes["node_id"]=nodes["node_id"].astype(str)

    # D10S-R2 correction:
    # project_direction() consumes mapping-style rows, so build a dictionary of
    # plain dictionaries rather than pandas namedtuples.
    required_project_cols=[
        "node_id",
        "COV_vs_H_FDR","COV_vs_H_logFC",
        "P_vs_H_FDR","P_vs_H_logFC",
    ]
    missing_project_cols=[c for c in required_project_cols if c not in nodes.columns]
    require(
        len(missing_project_cols)==0,
        f"D10N_NODE_EVIDENCE_REQUIRED_COLUMNS_MISSING={missing_project_cols}"
    )
    require(nodes["node_id"].nunique()==len(nodes),"D10N_NODE_EVIDENCE_DUPLICATE_NODE_IDS")

    for c in ["COV_vs_H_FDR","COV_vs_H_logFC","P_vs_H_FDR","P_vs_H_logFC"]:
        nodes[c]=pd.to_numeric(nodes[c],errors="coerce")
        require(nodes[c].notna().all(),f"D10N_NODE_EVIDENCE_NONNUMERIC_OR_NA={c}")

    node_map=(
        nodes[required_project_cols]
        .set_index("node_id",drop=False)
        .to_dict(orient="index")
    )

    # Every frozen hub target appearing in the D10R screening universe must
    # resolve to the authoritative D10N node-evidence table.
    frozen_hub_targets=set(
        u.loc[u["target_category"].isin(HUB_CATEGORIES),"target_label"].astype(str)
    )
    missing_hub_targets=sorted(frozen_hub_targets-set(node_map))
    require(
        len(missing_hub_targets)==0,
        f"D10S_HUB_TARGETS_MISSING_FROM_D10N_NODE_EVIDENCE={missing_hub_targets[:20]}"
    )

    out_rows=[]
    for row in u.itertuples(index=False):
        target=str(row.target_label)
        category=str(row.target_category)
        disease=str(row.disease_context)
        title=str(row.title)
        abstract=str(row.abstract)
        text=(title+" "+abstract).strip()
        is_hub=category in HUB_CATEGORIES
        is_pathway=category in PATHWAY_CATEGORIES
        require(is_hub or is_pathway,f"UNEXPECTED_TARGET_CATEGORY={category}")

        abs_av=str(row.abstract_available)=="YES"
        if not abs_av:
            relevance="NO_ABSTRACT_METADATA_ONLY"
            st=study_type(row.publication_types,title,abstract)
            evclass=""
            signal="NONE"
            comp="NOT_COMPARABLE"
            reason="PubMed record has no abstract; metadata retained only under frozen D10R rule."
            target_hit=False
            hit_rule="NO_ABSTRACT"
            disease_hit=disease_present(title,disease)
            proj_dir=proj_contrast=proj_fdr=proj_lfc=""
        else:
            disease_hit=disease_present(text,disease)
            target_hit,hit_rule=target_direct_match(target,text,is_hub)
            st=study_type(row.publication_types,title,abstract)

            if not disease_hit or not target_hit:
                relevance="IRRELEVANT_OR_AMBIGUOUS"
                evclass=""
                signal="NONE"
                comp="NOT_COMPARABLE"
                reason=(
                    f"Frozen title/abstract screen did not confirm both substantive target and "
                    f"disease-context presence; target_rule={hit_rule}, disease_present={disease_hit}."
                )
                proj_dir=proj_contrast=proj_fdr=proj_lfc=""
            else:
                relevance="DIRECT_TARGET_DISEASE"
                ts=local_target_sentences(target,text,is_hub)
                signal=direction_signal(ts)

                node_row=node_map.get(target) if is_hub else None
                proj_dir,proj_contrast,proj_fdr,proj_lfc=project_direction(node_row,disease)

                if is_pathway:
                    comp="NOT_COMPARABLE"
                    if signal in {"UP","DOWN","MIXED","NULL","ASSOCIATED"}:
                        evclass="RELEVANT_NOT_DIRECTIONALLY_COMPARABLE"
                        reason=(
                            "Direct pathway/process relevance confirmed, but D10O/D10N did not "
                            "freeze a pathway-direction statistic comparable to abstract direction."
                        )
                    else:
                        evclass="NO_DIRECTIONAL_CLAIM"
                        reason=(
                            "Direct pathway/process relevance confirmed; no explicit comparable "
                            "directional claim detected in target-local abstract text."
                        )
                else:
                    if not comparable_study(st):
                        comp="NOT_COMPARABLE"
                        evclass="RELEVANT_NOT_DIRECTIONALLY_COMPARABLE"
                        reason=(
                            f"Direct target/disease relevance confirmed, but study type {st} is not "
                            "treated as directionally equivalent to the frozen human whole-blood contrast."
                        )
                    elif proj_dir in {"NOT_SIGNIFICANT","ZERO","NOT_APPLICABLE"}:
                        comp="PARTIALLY_COMPARABLE"
                        evclass="RELEVANT_NOT_DIRECTIONALLY_COMPARABLE"
                        reason=(
                            f"Direct target/disease relevance confirmed, but frozen project contrast "
                            f"{proj_contrast} does not provide a significant nonzero direction."
                        )
                    elif signal=="MIXED":
                        comp="COMPARABLE"
                        evclass="MIXED_WITHIN_RECORD"
                        reason="Target-local abstract text contains both upward and downward directional language."
                    elif signal in {"UP","DOWN"}:
                        comp="COMPARABLE"
                        if signal==proj_dir:
                            evclass="CONCORDANT_CONTEXTUAL_SUPPORT"
                            reason=(
                                f"Explicit target-local literature direction ({signal}) matches frozen "
                                f"{proj_contrast} direction ({proj_dir}); contextual support only."
                            )
                        else:
                            evclass="DISCORDANT_OR_CONTRADICTORY"
                            reason=(
                                f"Explicit target-local literature direction ({signal}) opposes frozen "
                                f"{proj_contrast} direction ({proj_dir}); contradiction retained."
                            )
                    elif signal=="NULL":
                        comp="PARTIALLY_COMPARABLE"
                        evclass="DISCORDANT_OR_CONTRADICTORY"
                        reason=(
                            f"Abstract contains explicit target-local null/no-difference language while "
                            f"frozen {proj_contrast} is significant ({proj_dir}); contradiction retained."
                        )
                    elif signal=="ASSOCIATED":
                        comp="PARTIALLY_COMPARABLE"
                        evclass="NO_DIRECTIONAL_CLAIM"
                        reason=(
                            "Direct target/disease association is stated, but no explicit up/down direction "
                            "was detected for comparison."
                        )
                    else:
                        comp="PARTIALLY_COMPARABLE"
                        evclass="NO_DIRECTIONAL_CLAIM"
                        reason=(
                            "Direct target/disease relevance confirmed; no explicit target-local "
                            "directional/association claim detected."
                        )

        out_rows.append({
            "screening_pair_id":row.screening_pair_id,
            "query_id":row.query_id,
            "target_id":row.target_id,
            "pmid":str(row.pmid),
            "community_id":int(row.community_id),
            "target_category":category,
            "target_label":target,
            "disease_context":disease,
            "relevance_class":relevance,
            "study_type_class":st,
            "evidence_class":evclass,
            "target_mentioned_substantively":bool(target_hit),
            "target_match_rule":hit_rule,
            "disease_context_substantive":bool(disease_hit),
            "literature_direction_signal":signal,
            "project_direction":proj_dir,
            "project_contrast":proj_contrast,
            "project_fdr":proj_fdr,
            "project_logFC":proj_lfc,
            "project_comparability":comp,
            "direction_or_association_extract":(
                "Target-local abstract language classified as "+signal
                if signal!="NONE" else
                "No explicit target-local directional signal detected."
            ),
            "screening_reason":reason,
            "abstract_available":row.abstract_available,
            "screening_status":(
                "METADATA_ONLY" if relevance=="NO_ABSTRACT_METADATA_ONLY"
                else "SCREENED"
            ),
            "title":title,
            "publication_year":row.publication_year,
            "publication_types":row.publication_types,
            "journal":row.journal,
            "doi":row.doi,
            "pmc":row.pmc,
        })

    out=pd.DataFrame(out_rows)
    require(len(out)==EXPECTED_PAIRS,"OUTPUT_PAIR_COUNT_CHANGED")
    require(out["screening_pair_id"].nunique()==EXPECTED_PAIRS,"OUTPUT_PAIR_IDS_CHANGED")
    require(out[["query_id","pmid"]].drop_duplicates().shape[0]==EXPECTED_PAIRS,
            "OUTPUT_QUERY_PMID_DUPLICATION")

    allowed_rel={
        "DIRECT_TARGET_DISEASE","INDIRECT_CONTEXTUAL","IRRELEVANT_OR_AMBIGUOUS",
        "NO_ABSTRACT_METADATA_ONLY","UNDETERMINED_FROM_ABSTRACT"
    }
    allowed_ev={
        "","CONCORDANT_CONTEXTUAL_SUPPORT","DISCORDANT_OR_CONTRADICTORY",
        "RELEVANT_NOT_DIRECTIONALLY_COMPARABLE","MIXED_WITHIN_RECORD",
        "NO_DIRECTIONAL_CLAIM"
    }
    require(set(out["relevance_class"]).issubset(allowed_rel),"INVALID_RELEVANCE_CLASS")
    require(set(out["evidence_class"]).issubset(allowed_ev),"INVALID_EVIDENCE_CLASS")
    require(
        int((out["relevance_class"]=="NO_ABSTRACT_METADATA_ONLY").sum())>=EXPECTED_NO_ABSTRACT,
        "NO_ABSTRACT_PAIR_COUNT_UNEXPECTED"
    )
    require(
        (out.loc[out["relevance_class"]!="DIRECT_TARGET_DISEASE","evidence_class"]=="").all(),
        "EVIDENCE_CLASS_ASSIGNED_OUTSIDE_DIRECT_RELEVANCE"
    )

    out.to_csv(outdir/"D10S_SCREENED_QUERY_PMID_PAIRS.csv",index=False,float_format="%.17g")

    # Mandatory subsets and audits.
    direct=out[out["relevance_class"]=="DIRECT_TARGET_DISEASE"].copy()
    direct.to_csv(outdir/"D10S_DIRECT_RELEVANT_PAIRS.csv",index=False,float_format="%.17g")
    out[out["evidence_class"]=="CONCORDANT_CONTEXTUAL_SUPPORT"].to_csv(
        outdir/"D10S_CONCORDANT_CONTEXTUAL_SUPPORT_PAIRS.csv",index=False,float_format="%.17g"
    )
    out[out["evidence_class"]=="DISCORDANT_OR_CONTRADICTORY"].to_csv(
        outdir/"D10S_DISCORDANT_OR_CONTRADICTORY_PAIRS.csv",index=False,float_format="%.17g"
    )
    out[out["evidence_class"]=="MIXED_WITHIN_RECORD"].to_csv(
        outdir/"D10S_MIXED_EVIDENCE_PAIRS.csv",index=False,float_format="%.17g"
    )
    out[out["relevance_class"]=="NO_ABSTRACT_METADATA_ONLY"].to_csv(
        outdir/"D10S_NO_ABSTRACT_METADATA_ONLY_PAIRS.csv",index=False
    )

    rel_counts=out.groupby(["community_id","relevance_class"]).size().reset_index(name="pair_count")
    rel_counts.to_csv(outdir/"D10S_RELEVANCE_CLASS_COUNTS.csv",index=False)

    ev_counts=(
        direct.assign(evidence_class=direct["evidence_class"].replace("","UNCLASSIFIED"))
        .groupby(["community_id","evidence_class"]).size().reset_index(name="pair_count")
    )
    ev_counts.to_csv(outdir/"D10S_EVIDENCE_CLASS_COUNTS.csv",index=False)

    study_counts=out.groupby(["community_id","study_type_class"]).size().reset_index(name="pair_count")
    study_counts.to_csv(outdir/"D10S_STUDY_TYPE_COUNTS.csv",index=False)

    target_summary=(
        out.groupby(["target_id","community_id","target_category","target_label","disease_context"])
        .agg(
            retrieved_pairs=("screening_pair_id","count"),
            direct_pairs=("relevance_class",lambda x:int((x=="DIRECT_TARGET_DISEASE").sum())),
            irrelevant_or_ambiguous_pairs=("relevance_class",lambda x:int((x=="IRRELEVANT_OR_AMBIGUOUS").sum())),
            metadata_only_pairs=("relevance_class",lambda x:int((x=="NO_ABSTRACT_METADATA_ONLY").sum())),
            concordant_pairs=("evidence_class",lambda x:int((x=="CONCORDANT_CONTEXTUAL_SUPPORT").sum())),
            discordant_pairs=("evidence_class",lambda x:int((x=="DISCORDANT_OR_CONTRADICTORY").sum())),
            mixed_pairs=("evidence_class",lambda x:int((x=="MIXED_WITHIN_RECORD").sum())),
            nondirectional_pairs=("evidence_class",lambda x:int((x=="NO_DIRECTIONAL_CLAIM").sum())),
            noncomparable_pairs=("evidence_class",lambda x:int((x=="RELEVANT_NOT_DIRECTIONALLY_COMPARABLE").sum())),
        )
        .reset_index()
    )
    target_summary.to_csv(outdir/"D10S_TARGET_SCREENING_SUMMARY.csv",index=False)

    # Zero-hit queries remain explicitly separate and are never negative evidence.
    q["chosen_count_num"]=pd.to_numeric(q["chosen_count"],errors="coerce")
    require(q["chosen_count_num"].notna().all(),"QUERY_CHOSEN_COUNT_PARSE_FAILURE")
    zero=q[q["chosen_count_num"]==0].copy()
    zero["biological_negative_evidence"]="NO"
    zero.to_csv(outdir/"D10S_ZERO_HIT_QUERY_REGISTRY.csv",index=False)

    comm_summary=(
        out.groupby("community_id")
        .agg(
            screening_pairs=("screening_pair_id","count"),
            unique_pmids=("pmid","nunique"),
            direct_pairs=("relevance_class",lambda x:int((x=="DIRECT_TARGET_DISEASE").sum())),
            irrelevant_or_ambiguous_pairs=("relevance_class",lambda x:int((x=="IRRELEVANT_OR_AMBIGUOUS").sum())),
            metadata_only_pairs=("relevance_class",lambda x:int((x=="NO_ABSTRACT_METADATA_ONLY").sum())),
            concordant_pairs=("evidence_class",lambda x:int((x=="CONCORDANT_CONTEXTUAL_SUPPORT").sum())),
            discordant_pairs=("evidence_class",lambda x:int((x=="DISCORDANT_OR_CONTRADICTORY").sum())),
            mixed_pairs=("evidence_class",lambda x:int((x=="MIXED_WITHIN_RECORD").sum())),
            nondirectional_pairs=("evidence_class",lambda x:int((x=="NO_DIRECTIONAL_CLAIM").sum())),
            noncomparable_pairs=("evidence_class",lambda x:int((x=="RELEVANT_NOT_DIRECTIONALLY_COMPARABLE").sum())),
        )
        .reset_index()
    )
    require(len(comm_summary)==EXPECTED_COMMUNITIES,"COMMUNITY_SUMMARY_NOT_ALL_8")
    comm_summary.to_csv(outdir/"D10S_COMMUNITY_SCREENING_SUMMARY.csv",index=False)

    summary={
        "D10S_STATUS":"PASS",
        "COMMUNITIES_SCREENED":8,
        "SCREENING_QUERY_PMID_PAIRS":len(out),
        "UNIQUE_PMIDS_IN_SCREENING_UNIVERSE":out["pmid"].nunique(),
        "DIRECT_TARGET_DISEASE_PAIRS":int((out["relevance_class"]=="DIRECT_TARGET_DISEASE").sum()),
        "IRRELEVANT_OR_AMBIGUOUS_PAIRS":int((out["relevance_class"]=="IRRELEVANT_OR_AMBIGUOUS").sum()),
        "NO_ABSTRACT_METADATA_ONLY_PAIRS":int((out["relevance_class"]=="NO_ABSTRACT_METADATA_ONLY").sum()),
        "CONCORDANT_CONTEXTUAL_SUPPORT_PAIRS":int((out["evidence_class"]=="CONCORDANT_CONTEXTUAL_SUPPORT").sum()),
        "DISCORDANT_OR_CONTRADICTORY_PAIRS":int((out["evidence_class"]=="DISCORDANT_OR_CONTRADICTORY").sum()),
        "MIXED_WITHIN_RECORD_PAIRS":int((out["evidence_class"]=="MIXED_WITHIN_RECORD").sum()),
        "RELEVANT_NOT_DIRECTIONALLY_COMPARABLE_PAIRS":int((out["evidence_class"]=="RELEVANT_NOT_DIRECTIONALLY_COMPARABLE").sum()),
        "NO_DIRECTIONAL_CLAIM_PAIRS":int((out["evidence_class"]=="NO_DIRECTIONAL_CLAIM").sum()),
        "ZERO_HIT_QUERIES":len(zero),
        "ZERO_HIT_QUERY_COUNTS_AS_NEGATIVE_BIOLOGICAL_EVIDENCE":"NO",
        "SCREENING_SOURCE":"PUBMED_TITLE_ABSTRACT_METADATA_ONLY",
        "FULL_TEXT_SCREENING_EXECUTED":"NO",
        "NEW_LITERATURE_SEARCH_EXECUTED":"NO",
        "GENE_ALIAS_EXPANSION_EXECUTED":"NO",
        "ALL_QUERY_PMID_PAIRS_SCREENED":"YES",
        "PAIR_SPECIFIC_EVIDENCE_CLASSIFICATION":"YES",
        "CONTRADICTORY_EVIDENCE_RETAINED":"YES",
        "COMMUNITY_ASSIGNMENTS_CHANGED":"NO",
        "HUB_STATUS_CHANGED":"NO",
        "ENRICHMENT_CHANGED":"NO",
        "BIOLOGICAL_NARRATIVE_EXECUTED":"NO",
        "LITERATURE_CONCORDANCE_COUNTS_AS_ACLA_VALIDATION":"NO",
        "D10S_R2_CORRECTION":"NAMEDTUPLE_TO_MAPPING_NODEMAP",
        "D10S_R2_PROJECT_COLUMN_PREFLIGHT":"PASS",
        "READY_FOR_D10T_LITERATURE_SYNTHESIS_DESIGN":"YES",
        "STOP":"YES",
    }
    (outdir/"D10S_SUMMARY.json").write_text(json.dumps(summary,indent=2),encoding="utf-8")

    audit={
        "classification_engine":"DETERMINISTIC_RULE_BASED_HIGH_PRECISION_V1",
        "target_match_policy":"EXACT_SYMBOL_FOR_HUBS_EXACT_OR_80PCT_SENTENCE_TOKEN_COVERAGE_FOR_PATHWAYS",
        "direction_signal_scope":"TARGET_LOCAL_ABSTRACT_SENTENCES_ONLY",
        "human_direction_comparability_required_for_concordance":"YES",
        "pathway_direction_forced_to_project_direction":"NO",
        "null_finding_against_significant_project_direction_classified_contradictory":"YES",
        "manual_overrides":"PROHIBITED_IN_D10S",
        "D10S_R2_correction":"node_map switched from pandas namedtuple values to plain dictionaries",
        "D10S_R2_project_column_validation":"required project DE columns validated numeric before screening",
        "D10S_R2_hub_target_coverage_validation":"all frozen hub targets required to exist in D10N node evidence",
    }
    (outdir/"D10S_CLASSIFICATION_ENGINE_AUDIT.json").write_text(
        json.dumps(audit,indent=2),encoding="utf-8"
    )
    return 0

if __name__=="__main__":
    raise SystemExit(main())
