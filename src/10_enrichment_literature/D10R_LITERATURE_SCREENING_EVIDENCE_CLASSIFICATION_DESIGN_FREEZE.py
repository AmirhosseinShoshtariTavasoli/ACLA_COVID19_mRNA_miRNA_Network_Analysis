#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import pandas as pd

EXPECTED_COMMUNITIES=8
EXPECTED_TARGETS=187
EXPECTED_QUERIES=374
EXPECTED_MAPPING_ROWS=2531
EXPECTED_UNIQUE_PMIDS=2137
EXPECTED_RECORDS=2137
EXPECTED_WITH_ABSTRACT=2132
EXPECTED_WITHOUT_ABSTRACT=5

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

def main():
    if len(sys.argv)!=8:
        raise SystemExit(
            "usage: D10R <d10q_status> <d10q_manifest> <query_results> "
            "<query_pmid_mapping> <records> <query_article_candidates> <outdir>"
        )

    status_path=Path(sys.argv[1])
    manifest_path=Path(sys.argv[2])
    query_results_path=Path(sys.argv[3])
    mapping_path=Path(sys.argv[4])
    records_path=Path(sys.argv[5])
    candidates_path=Path(sys.argv[6])
    outdir=Path(sys.argv[7])
    outdir.mkdir(parents=True,exist_ok=True)

    t=status_path.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10Q_STATUS=PASS",
        "COMMUNITIES_COVERED=8",
        "LITERATURE_TARGETS=187",
        "FROZEN_QUERIES_EXECUTED=374",
        "QUERY_PMID_MAPPING_ROWS=2531",
        "UNIQUE_PMIDS=2137",
        "PUBMED_RECORDS_RETRIEVED=2137",
        "RECORDS_WITH_ABSTRACT=2132",
        "RECORDS_WITHOUT_ABSTRACT=5",
        "BIOLOGICAL_NARRATIVE_EXECUTED=NO",
        "LITERATURE_SCREENING_EXECUTED=NO",
        "READY_FOR_D10R_LITERATURE_SCREENING_DESIGN=YES",
    ]:
        require(tok in t,f"D10Q_AUTHORITY_TOKEN_MISSING={tok}")

    verify_manifest(manifest_path)

    q=pd.read_csv(query_results_path,dtype=str,keep_default_na=False)
    m=pd.read_csv(mapping_path,dtype=str,keep_default_na=False)
    r=pd.read_csv(records_path,dtype=str,keep_default_na=False)
    c=pd.read_csv(candidates_path,dtype=str,keep_default_na=False)

    require(len(q)==EXPECTED_QUERIES,f"QUERY_RESULT_ROWS={len(q)}")
    require(q["query_id"].nunique()==EXPECTED_QUERIES,"QUERY_RESULT_DUPLICATE_IDS")
    require(len(m)==EXPECTED_MAPPING_ROWS,f"MAPPING_ROWS={len(m)}")
    require(m["pmid"].nunique()==EXPECTED_UNIQUE_PMIDS,f"UNIQUE_PMIDS={m['pmid'].nunique()}")
    require(len(r)==EXPECTED_RECORDS,f"RECORD_ROWS={len(r)}")
    require(r["pmid"].nunique()==EXPECTED_RECORDS,"RECORD_DUPLICATE_PMIDS")
    require(len(c)==EXPECTED_MAPPING_ROWS,f"CANDIDATE_ROWS={len(c)}")

    require("abstract_available" in r.columns,"ABSTRACT_AVAILABLE_COLUMN_MISSING")
    with_abs=int((r["abstract_available"]=="YES").sum())
    without_abs=int((r["abstract_available"]=="NO").sum())
    require(with_abs==EXPECTED_WITH_ABSTRACT,f"WITH_ABSTRACT={with_abs}")
    require(without_abs==EXPECTED_WITHOUT_ABSTRACT,f"WITHOUT_ABSTRACT={without_abs}")

    # All query-PMID pairs are the mandatory screening universe.
    pair_cols=["query_id","target_id","community_id","target_category",
               "target_label","disease_context","pmid"]
    for col in pair_cols:
        require(col in c.columns,f"CANDIDATE_COLUMN_MISSING={col}")
    pair_count=len(c[pair_cols].drop_duplicates())
    require(pair_count==EXPECTED_MAPPING_ROWS,f"UNIQUE_QUERY_PMID_PAIRS={pair_count}")

    # Screening universe registry; no semantic screening yet.
    registry=c[pair_cols + [
        "title","abstract","publication_year","publication_types",
        "journal","doi","pmc","abstract_available"
    ]].copy()
    registry.insert(0,"screening_pair_id",
                    [f"D10R_PAIR_{i:06d}" for i in range(1,len(registry)+1)])
    registry["screening_status"]="NOT_SCREENED"
    registry["screening_design_version"]="D10R_V1"
    registry.to_csv(outdir/"D10R_SCREENING_UNIVERSE.csv",index=False)

    # Frozen relevance classes.
    relevance_rows=[
        ["DIRECT_TARGET_DISEASE",
         "Title/abstract substantively discusses the frozen target (gene/miRNA/process/pathway) in the frozen disease context.",
         "ELIGIBLE_FOR_EVIDENCE_CLASSIFICATION"],
        ["INDIRECT_CONTEXTUAL",
         "Disease context is present and target is mentioned, but the abstract does not provide target-specific biological/clinical evidence; background/context only.",
         "RETAIN_CONTEXTUAL_NOT_PRIMARY_EVIDENCE"],
        ["IRRELEVANT_OR_AMBIGUOUS",
         "Lexical PubMed hit does not substantively address the frozen target in the disease context, or target meaning is ambiguous/unrelated.",
         "EXCLUDE_FROM_TARGET_EVIDENCE_RETAIN_PROVENANCE"],
        ["NO_ABSTRACT_METADATA_ONLY",
         "No PubMed abstract is available; title/metadata retained but no mechanistic or directional evidence may be inferred.",
         "METADATA_ONLY"],
        ["UNDETERMINED_FROM_ABSTRACT",
         "Abstract exists but relevance cannot be determined without full text.",
         "RETAIN_UNDETERMINED_NO_MECHANISTIC_CLAIM"],
    ]
    pd.DataFrame(relevance_rows,columns=[
        "RELEVANCE_CLASS","FROZEN_DEFINITION","DOWNSTREAM_USE"
    ]).to_csv(outdir/"D10R_RELEVANCE_CLASSIFICATION_RULES.csv",index=False)

    # Evidence direction classes are only applied to DIRECT_TARGET_DISEASE pairs.
    evidence_rows=[
        ["CONCORDANT_CONTEXTUAL_SUPPORT",
         "Literature reports target/process involvement, association, activation/suppression, or disease-linked behavior compatible with the direction/role represented in the frozen D10O/D10N evidence when a comparison is genuinely comparable.",
         "Contextual support only; never independent A-CLA validation."],
        ["DISCORDANT_OR_CONTRADICTORY",
         "Literature reports a comparable result with an opposite direction, explicit lack of association, or evidence arguing against the frozen target/disease interpretation.",
         "Must be retained and surfaced."],
        ["RELEVANT_NOT_DIRECTIONALLY_COMPARABLE",
         "Target is directly relevant to the disease context, but study design/endpoint/model does not permit a valid direction-level comparison with the frozen result.",
         "Contextual relevance without concordance label."],
        ["MIXED_WITHIN_RECORD",
         "The same record reports both supportive and conflicting findings across cohorts/endpoints/conditions.",
         "Retain as mixed; do not collapse to supportive."],
        ["NO_DIRECTIONAL_CLAIM",
         "Directly relevant article discusses the target but does not make a directional/association claim comparable to the frozen result.",
         "Retain as direct contextual evidence."],
    ]
    pd.DataFrame(evidence_rows,columns=[
        "EVIDENCE_CLASS","FROZEN_DEFINITION","INTERPRETATION_BOUNDARY"
    ]).to_csv(outdir/"D10R_EVIDENCE_CLASSIFICATION_RULES.csv",index=False)

    # Study-type strata.
    study_rows=[
        ["SYSTEMATIC_REVIEW_OR_META_ANALYSIS","Publication type/abstract supports systematic review or meta-analysis."],
        ["ORIGINAL_HUMAN_CLINICAL_OR_COHORT","Original human patient/cohort/clinical study."],
        ["ORIGINAL_HUMAN_OMICS_OR_COMPUTATIONAL","Original human omics/computational analysis with human biological data."],
        ["ORIGINAL_EXPERIMENTAL_MODEL","Cell, animal, ex vivo, or mechanistic experimental model."],
        ["NARRATIVE_REVIEW","Review without systematic/meta-analysis classification."],
        ["CASE_REPORT_OR_CASE_SERIES","Case report/series."],
        ["EDITORIAL_LETTER_COMMENTARY","Editorial, letter, commentary, news, or non-primary opinion format."],
        ["OTHER_OR_UNCLEAR","Does not fit above based on metadata/abstract."],
    ]
    pd.DataFrame(study_rows,columns=[
        "STUDY_TYPE_CLASS","FROZEN_DEFINITION"
    ]).to_csv(outdir/"D10R_STUDY_TYPE_RULES.csv",index=False)

    # Comparison rules against frozen project evidence.
    comparison_rows=[
        ["HUB_GENE_OR_MIRNA",
         "Compare only when article gives target-specific disease association/direction relevant to the frozen disease context. Do not infer concordance from mere mention."],
        ["FUNCTIONAL_OR_PATHWAY_TERM",
         "Use contextual relevance rather than gene-level direction unless article explicitly reports pathway/process activation/suppression in a comparable disease setting."],
        ["COVID19_QUERY",
         "Compare with COVID-related frozen evidence only; sepsis evidence is a separate axis."],
        ["SEPSIS_QUERY",
         "Compare with sepsis/comparator frozen evidence only; do not reinterpret sepsis non-significance as absence."],
        ["NONCOMPARABLE_MODEL",
         "Animal/cell/model evidence can be mechanistically contextual but is not directionally equivalent to human whole-blood differential expression unless explicitly justified."],
    ]
    pd.DataFrame(comparison_rows,columns=[
        "COMPARISON_CONTEXT","FROZEN_RULE"
    ]).to_csv(outdir/"D10R_PROJECT_COMPARISON_RULES.csv",index=False)

    policy_rows=[
        ["SCREENING_UNIT","QUERY_PMID_PAIR","Each of 2,531 query-PMID pairs screened independently.","FROZEN"],
        ["UNIQUE_PMID_REUSE","ALLOWED_WITH_PAIR_SPECIFIC_LABELS","Same PMID may have different relevance for different targets/queries.","FROZEN"],
        ["ALL_PAIRS_SCREENED","MANDATORY","No manual preselection of papers.","FROZEN"],
        ["ZERO_HIT_QUERY","NOT_NEGATIVE_BIOLOGICAL_EVIDENCE","Zero retrieval means no hit under frozen search, not absence of biology.","FROZEN"],
        ["NO_ABSTRACT_RECORD","METADATA_ONLY","No mechanistic/directional inference from the five no-abstract records.","FROZEN"],
        ["SCREENING_INFORMATION_SOURCE","TITLE_ABSTRACT_PUBMED_METADATA_ONLY","No full-text screening in D10S.","FROZEN"],
        ["FULL_TEXT_EXPANSION","PROHIBITED_IN_D10S","Would require separately versioned design.","FROZEN"],
        ["GENE_ALIAS_EXPANSION","PROHIBITED","No post-hoc search/screening alias expansion.","FROZEN"],
        ["NEW_LITERATURE_SEARCH","PROHIBITED_IN_D10S","D10S screens only D10Q retrieval universe.","FROZEN"],
        ["CONTRADICTORY_EVIDENCE","MANDATORY_RETENTION","Contradictory/negative evidence cannot be removed.","FROZEN"],
        ["REVIEW_AND_ORIGINAL_STUDIES","BOTH_RETAINED_SEPARATELY","Do not mix evidence types silently.","FROZEN"],
        ["EVIDENCE_CLASSIFICATION","PAIR_SPECIFIC","Evidence direction is assigned per target/disease query pair.","FROZEN"],
        ["CONCORDANCE_LANGUAGE","CONTEXTUAL_SUPPORT_ONLY","Never call literature concordance independent validation.","FROZEN"],
        ["MODULE_EFFECT","NONE","Screening cannot change modules.","FROZEN"],
        ["HUB_EFFECT","NONE","Screening cannot change frozen hub status.","FROZEN"],
        ["ENRICHMENT_EFFECT","NONE","Screening cannot change frozen enrichment.","FROZEN"],
        ["BIOLOGICAL_NARRATIVE","PROHIBITED_IN_D10S","D10S performs screening/classification only.","FROZEN"],
        ["ALL_8_COMMUNITIES","MANDATORY","Screening coverage remains complete across communities.","FROZEN"],
    ]
    pd.DataFrame(policy_rows,columns=[
        "POLICY_ITEM","FROZEN_VALUE","RATIONALE","STATUS"
    ]).to_csv(outdir/"D10R_SCREENING_POLICY.csv",index=False)

    # Later narrative exemplar rule is frozen now to avoid paper cherry-picking.
    exemplar_rows=[
        ["CONCORDANT_CONTEXTUAL_SUPPORT","SYSTEMATIC_REVIEW_OR_META_ANALYSIS",1,
         "Lowest PMID after filtering to the class if multiple equally eligible records remain."],
        ["CONCORDANT_CONTEXTUAL_SUPPORT","ORIGINAL_HUMAN_CLINICAL_OR_COHORT",2,
         "Most recent publication year first, then lowest PMID; no manual replacement."],
        ["DISCORDANT_OR_CONTRADICTORY","ANY_ELIGIBLE_STUDY_TYPE",2,
         "Most recent publication year first, then lowest PMID; equal visibility when present."],
        ["MIXED_WITHIN_RECORD","ANY_ELIGIBLE_STUDY_TYPE",1,
         "Most recent publication year first, then lowest PMID."],
    ]
    pd.DataFrame(exemplar_rows,columns=[
        "EVIDENCE_CLASS","STUDY_TYPE_PRIORITY","MAX_DISPLAY_PER_TARGET_DISEASE",
        "DETERMINISTIC_SELECTION_RULE"
    ]).to_csv(outdir/"D10R_FUTURE_NARRATIVE_EXEMPLAR_RULES.csv",index=False)

    # Schema for D10S output.
    schema_rows=[
        ["screening_pair_id","string","Immutable D10R pair identifier."],
        ["query_id","string","Frozen D10P/D10Q query identifier."],
        ["target_id","string","Frozen literature target identifier."],
        ["pmid","string","PubMed PMID."],
        ["community_id","integer","Frozen community."],
        ["disease_context","enum","COVID19 or SEPSIS."],
        ["relevance_class","enum","One D10R relevance class."],
        ["study_type_class","enum","One D10R study-type class."],
        ["evidence_class","enum_or_blank","Applied only when relevant; one D10R evidence class."],
        ["target_mentioned_substantively","boolean","Screening judgment from title/abstract."],
        ["disease_context_substantive","boolean","Disease context is substantive, not incidental."],
        ["direction_or_association_extract","string","Short paraphrased abstract-supported finding; no long quotation."],
        ["project_comparability","enum","COMPARABLE / PARTIALLY_COMPARABLE / NOT_COMPARABLE."],
        ["screening_reason","string","Concise rationale grounded in title/abstract."],
        ["abstract_available","YES_NO","Inherited from D10Q."],
        ["screening_status","enum","SCREENED / METADATA_ONLY / UNDETERMINED."],
    ]
    pd.DataFrame(schema_rows,columns=[
        "FIELD","TYPE","DEFINITION"
    ]).to_csv(outdir/"D10R_D10S_OUTPUT_SCHEMA.csv",index=False)

    contract={
        "D10R_STATUS":"PASS",
        "COMMUNITIES_FROZEN":8,
        "LITERATURE_TARGETS":187,
        "FROZEN_QUERIES":374,
        "SCREENING_QUERY_PMID_PAIRS":EXPECTED_MAPPING_ROWS,
        "UNIQUE_PMIDS":EXPECTED_UNIQUE_PMIDS,
        "PUBMED_RECORDS":EXPECTED_RECORDS,
        "RECORDS_WITH_ABSTRACT":EXPECTED_WITH_ABSTRACT,
        "RECORDS_WITHOUT_ABSTRACT":EXPECTED_WITHOUT_ABSTRACT,
        "SCREENING_UNIT":"QUERY_PMID_PAIR",
        "ALL_QUERY_PMID_PAIRS_MUST_BE_SCREENED":"YES",
        "SCREENING_SOURCE":"PUBMED_TITLE_ABSTRACT_METADATA_ONLY",
        "FULL_TEXT_SCREENING_AUTHORIZED":"NO",
        "NEW_LITERATURE_SEARCH_AUTHORIZED":"NO",
        "GENE_ALIAS_EXPANSION_AUTHORIZED":"NO",
        "ZERO_HIT_QUERY_COUNTS_AS_NEGATIVE_BIOLOGICAL_EVIDENCE":"NO",
        "NO_ABSTRACT_MECHANISTIC_INFERENCE_AUTHORIZED":"NO",
        "CONTRADICTORY_EVIDENCE_MUST_BE_RETAINED":"YES",
        "PAIR_SPECIFIC_EVIDENCE_CLASSIFICATION":"YES",
        "LITERATURE_CAN_CHANGE_COMMUNITIES":"NO",
        "LITERATURE_CAN_CHANGE_HUB_STATUS":"NO",
        "LITERATURE_CAN_CHANGE_ENRICHMENT":"NO",
        "LITERATURE_CONCORDANCE_COUNTS_AS_ACLA_VALIDATION":"NO",
        "D10S_BIOLOGICAL_NARRATIVE_AUTHORIZED":"NO",
        "SCREENING_EXECUTED":"NO",
        "READY_FOR_D10S_LITERATURE_SCREENING_AND_CLASSIFICATION":"YES",
        "STOP":"YES",
    }
    (outdir/"D10R_EXECUTION_CONTRACT.json").write_text(
        json.dumps(contract,indent=2),encoding="utf-8"
    )

    spec="""# D10R — Literature Screening + Evidence Classification Design Freeze

## Objective

Freeze screening and evidence-classification rules before any of the 2,531
query-PMID candidate pairs is labeled relevant, supportive, contradictory, or
contextual.

## Unit of screening

The screening unit is the query-PMID pair, not the PMID alone.

One PMID may legitimately be directly relevant to one frozen target but only
contextual or irrelevant to another target. Therefore pair-specific labels are
required.

## Screening source

D10S is restricted to:
- PubMed title
- PubMed abstract
- PubMed metadata/publication type

No full-text screening, new searches, alias expansion, or manual paper additions.

The five no-abstract records remain metadata-only.

## Relevance classes

DIRECT_TARGET_DISEASE
INDIRECT_CONTEXTUAL
IRRELEVANT_OR_AMBIGUOUS
NO_ABSTRACT_METADATA_ONLY
UNDETERMINED_FROM_ABSTRACT

Only DIRECT_TARGET_DISEASE pairs can receive directional evidence classification.

## Evidence classes

CONCORDANT_CONTEXTUAL_SUPPORT
DISCORDANT_OR_CONTRADICTORY
RELEVANT_NOT_DIRECTIONALLY_COMPARABLE
MIXED_WITHIN_RECORD
NO_DIRECTIONAL_CLAIM

"Concordant" means contextual compatibility only. It is never independent
validation of A-CLA.

## Mandatory negative-evidence handling

Contradictory or null findings must be retained.

A PubMed query returning zero final results is a zero retrieval under the frozen
search strategy, not evidence that the biology is absent.

## Project integrity

Literature screening cannot:
- change community membership
- change hub status
- change enrichment results
- trigger new PubMed searches
- create new gene aliases
- suppress weak/contradictory records

D10S performs screening/classification only and writes no biological narrative.
"""
    (outdir/"D10R_DESIGN_SPECIFICATION.md").write_text(spec,encoding="utf-8")

    return 0

if __name__=="__main__":
    raise SystemExit(main())
