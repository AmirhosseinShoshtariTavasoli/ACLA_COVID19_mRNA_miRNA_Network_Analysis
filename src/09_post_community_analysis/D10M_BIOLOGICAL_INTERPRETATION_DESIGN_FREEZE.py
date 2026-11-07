#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import pandas as pd

EXPECTED_COMMUNITIES=8
EXPECTED_NODES=4508
EXPECTED_MRNA=4467
EXPECTED_MIRNA=41
EXPECTED_EDGES=11531
EXPECTED_REG=1978

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
    require(bad==0,f"MANIFEST_HASH_MISMATCHES={bad} manifest={path}")

def main():
    if len(sys.argv)!=7:
        raise SystemExit(
            "usage: D10M <d10j_status> <d10k_status> <d10l_status> "
            "<d10j_manifest> <d10k_manifest> <d10l_manifest>"
        )

    d10j_status=Path(sys.argv[1])
    d10k_status=Path(sys.argv[2])
    d10l_status=Path(sys.argv[3])
    d10j_manifest=Path(sys.argv[4])
    d10k_manifest=Path(sys.argv[5])
    d10l_manifest=Path(sys.argv[6])

    outdir=Path.cwd()

    jt=d10j_status.read_text(encoding="utf-8-sig",errors="replace")
    kt=d10k_status.read_text(encoding="utf-8-sig",errors="replace")
    lt=d10l_status.read_text(encoding="utf-8-sig",errors="replace")

    for tok in [
        "D10J_STATUS=PASS",
        "COMMUNITIES=8",
        "GSE243219_ACLA_EXECUTED=YES",
        "POSTEXECUTION_TECHNICAL_VALIDATION=PASS",
        "PARAMETER_TUNING_EXECUTED=NO",
    ]:
        require(tok in jt,f"D10J_AUTHORITY_TOKEN_MISSING={tok}")

    for tok in [
        "D10K_STATUS=PASS",
        "COMMUNITIES=8",
        "NODES=4508",
        "EDGES=11531",
        "REGULATORY_EDGES=1978",
        "COMMUNITY_ASSIGNMENTS_CHANGED=NO",
        "READY_FOR_D10L_BIOLOGICAL_CHARACTERIZATION=YES",
    ]:
        require(tok in kt,f"D10K_AUTHORITY_TOKEN_MISSING={tok}")

    for tok in [
        "D10L_STATUS=PASS",
        "COMMUNITIES=8",
        "NODES=4508",
        "MRNA_NODES=4467",
        "MIRNA_NODES=41",
        "DE_SOURCE_FILES_FROZEN=6",
        "COVID_SPECIFICITY_CLASSIFIER_CREATED=NO",
        "READY_FOR_D10M_BIOLOGICAL_INTERPRETATION_DESIGN=YES",
        "BIOLOGICAL_INTERPRETATION_EXECUTED=NO",
    ]:
        require(tok in lt,f"D10L_AUTHORITY_TOKEN_MISSING={tok}")

    verify_manifest(d10j_manifest)
    verify_manifest(d10k_manifest)
    verify_manifest(d10l_manifest)

    # Prospectively frozen analysis families.
    policy_rows=[
        ["COMMUNITY_INCLUSION","ALL_8_COMMUNITIES","All eight fixed D10J communities must be analyzed and reported; no module may be omitted because its later biology is weak or uninteresting.","FROZEN"],
        ["COMMUNITY_MEMBERSHIP","IMMUTABLE_D10J_ASSIGNMENTS","No reassignment, merging, splitting, pruning, or relabeling based on downstream biology.","FROZEN"],
        ["PRIMARY_FUNCTIONAL_QUERY","ALL_MRNA_IN_EACH_COMMUNITY","Primary functional enrichment query for each community is every mRNA assigned to that community.","FROZEN"],
        ["PRIMARY_ENRICHMENT_BACKGROUND","ALL_4467_NETWORK_MRNA","Custom universe is all 4,467 mRNA nodes in the frozen D10L network, not the whole human genome.","FROZEN"],
        ["PRIMARY_ENRICHMENT_ORGANISM","hsapiens","Homo sapiens.","FROZEN"],
        ["PRIMARY_ENRICHMENT_SOURCES","GO:BP;REAC","Primary functional sources are Gene Ontology Biological Process and Reactome.","FROZEN"],
        ["SECONDARY_ENRICHMENT_SOURCE","KEGG","KEGG may be reported as a separately labeled secondary pathway source; it cannot determine module inclusion.","FROZEN"],
        ["ENRICHMENT_TEST","gProfiler_gGOSt_OVERREPRESENTATION","Use unordered overrepresentation analysis with a custom background.","FROZEN"],
        ["ENRICHMENT_MULTIPLE_TESTING","FDR_0.05","Use g:Profiler significance_threshold_method=fdr and user_threshold=0.05.","FROZEN"],
        ["ENRICHMENT_DOMAIN_SCOPE","custom","Use custom statistical domain with the frozen 4,467-mRNA background.","FROZEN"],
        ["ENRICHMENT_ORDERED_QUERY","False","No ranked/ordered enrichment in the primary analysis.","FROZEN"],
        ["GO_IEA_POLICY","INCLUDE","Do not exclude IEA annotations in the primary analysis; use g:Profiler default no_iea=False.","FROZEN"],
        ["DATA_VERSION_PROVENANCE","REQUIRED","At execution, query and save g:Profiler data_versions for hsapiens before enrichment; all module queries must use the same observed service version.","FROZEN"],
        ["DE_PRIMARY_ROLE","COV_vs_H_FDR_LE_0.05","COVID-vs-healthy significance is a disease annotation, not a filter for primary module enrichment.","FROZEN"],
        ["DE_EFFECT_SIZE_ROLE","ABS_LOGFC_GE_1_SECONDARY_ONLY","|logFC|>=1 is secondary descriptive effect-size evidence only.","FROZEN"],
        ["SEPSIS_ROLE","COMPARATOR_NOT_EXCLUSION","P-vs-H and COV-vs-P remain comparator evidence; they do not remove nodes from modules or enrichment.","FROZEN"],
        ["COVID_SPECIFICITY","NO_SINGLE_BINARY_CLASSIFIER","Do not invent a binary COVID-specific label. Report three frozen evidence flags: COV-vs-H significance, P-vs-H significance, and COV-vs-P significance, plus directions.","FROZEN"],
        ["REGULATORY_TARGET_ENRICHMENT","SECONDARY_ONLY","A secondary miRNA-regulatory analysis may enrich only mRNA targets connected by the already frozen 1,978 regulatory-supported edges; no new target database expansion.","FROZEN"],
        ["REGULATORY_TARGET_BACKGROUND","ALL_MRNA_INCIDENT_TO_FROZEN_REGULATORY_EDGES","Use all mRNAs incident to any of the 1,978 frozen regulatory edges as the regulatory-target enrichment universe.","FROZEN"],
        ["SIGNED_EDGE_ROLE","DESCRIPTIVE_ONLY","Positive/negative edge distributions characterize fixed modules but cannot alter modules or enrichment query membership.","FROZEN"],
        ["HUB_PRIMARY_METRIC","INTERNAL_TOPOLOGY_DEGREE","Primary topological hub metric is within-community degree in the frozen 11,531-edge topology.","FROZEN"],
        ["HUB_STRATIFICATION","WITHIN_COMMUNITY_AND_NODE_TYPE","mRNA and miRNA hubs are ranked separately within each community to respect the bipartite topology.","FROZEN"],
        ["HUB_THRESHOLD","GE_90TH_PERCENTILE","Primary hub candidates are nodes at or above the 90th percentile of internal degree within the same community and node type; ties are retained.","FROZEN"],
        ["REGULATORY_HUB_METRIC","INTERNAL_REGULATORY_DEGREE","Regulatory hub evidence is reported separately using only the frozen regulatory-supported edges.","FROZEN"],
        ["DISEASE_HUB_ANNOTATION","COV_vs_H_FDR_LE_0.05","A hub can be annotated as COVID-associated when COV-vs-H FDR<=0.05; this does not change hub status.","FROZEN"],
        ["COMPOSITE_HUB_SCORE","PROHIBITED","No post-hoc weighted composite score mixing degree, DE, regulation, enrichment, or sign evidence.","FROZEN"],
        ["MODULE_RANKING","NO_SINGLE_COMPOSITE_SCORE","All modules are reported. No post-hoc module score is used to suppress modules.","FROZEN"],
        ["NARRATIVE_PRIORITY","CONCORDANT_EVIDENCE_ONLY","Narrative emphasis may note modules showing concordant functional enrichment, regulatory support, and COVID DE evidence, but all underlying module results remain reported.","FROZEN"],
        ["ENRICHMENT_AS_VALIDATION","NO","Functional enrichment is post-hoc biological characterization and must not be presented as independent validation of A-CLA.","FROZEN"],
        ["MODULE_STABILITY_CLAIM","NOT_AUTHORIZED","RUN_COUNT=1 was prospectively frozen; do not claim multi-seed or perturbation stability for these communities.","FROZEN"],
        ["HUB_AS_BIOMARKER_VALIDATION","NO","Topology-derived hubs are candidates/descriptive priorities, not validated biomarkers.","FROZEN"],
        ["BIOLOGICAL_INTERPRETATION_SCOPE","CHARACTERIZATION_AND_HYPOTHESIS_GENERATION","Interpretation may generate biological hypotheses but not causal or clinical claims.","FROZEN"],
    ]
    policy=pd.DataFrame(policy_rows,columns=["POLICY_ITEM","FROZEN_VALUE","RATIONALE","STATUS"])
    policy.to_csv(outdir/"D10M_BIOLOGICAL_INTERPRETATION_POLICY.csv",index=False)

    evidence_rows=[
        ["COVID_RESPONSE","COV_vs_H_FDR<=0.05","Primary disease-response evidence flag."],
        ["COVID_DIRECTION","sign(COV_vs_H_logFC)","UP/DOWN/ZERO; descriptive."],
        ["COVID_LARGE_EFFECT","COV_vs_H_FDR<=0.05 AND abs(COV_vs_H_logFC)>=1","Secondary large-effect annotation; not required for significance."],
        ["SEPSIS_RESPONSE","P_vs_H_FDR<=0.05","Comparator evidence flag; non-significance is not proof of absence."],
        ["COVID_VS_SEPSIS_DIFFERENCE","COV_vs_P_FDR<=0.05","Direct COVID-versus-sepsis discrimination evidence."],
        ["SHARED_DIRECTIONAL_RESPONSE","COV_vs_H_FDR<=0.05 AND P_vs_H_FDR<=0.05 AND same nonzero logFC direction","Descriptive shared-response label only."],
        ["COVID_ASSOCIATED_WITH_DIRECT_SEPSIS_DIFFERENCE","COV_vs_H_FDR<=0.05 AND COV_vs_P_FDR<=0.05","Strong two-contrast evidence; do not label strictly COVID-specific without qualification."],
    ]
    pd.DataFrame(evidence_rows,columns=["EVIDENCE_LABEL","RULE","INTERPRETATION"]).to_csv(
        outdir/"D10M_DE_EVIDENCE_RULES.csv",index=False
    )

    hub_rows=[
        ["PRIMARY_TOPOLOGICAL_HUB","internal_degree >= within-community/node-type 90th percentile","Ties retained; evaluated separately for mRNA and miRNA."],
        ["REGULATORY_HUB_EVIDENCE","internal_regulatory_degree >= within-community/node-type 90th percentile among nodes with regulatory degree >0","Secondary evidence only; does not replace primary hub definition."],
        ["COVID_ASSOCIATED_HUB","PRIMARY_TOPOLOGICAL_HUB AND COV_vs_H_FDR<=0.05","Disease annotation layered onto a topology-defined hub."],
        ["LARGE_EFFECT_COVID_HUB","COVID_ASSOCIATED_HUB AND abs(COV_vs_H_logFC)>=1","Secondary effect-size annotation."],
        ["COVID_VS_SEPSIS_DISCRIMINATING_HUB","PRIMARY_TOPOLOGICAL_HUB AND COV_vs_P_FDR<=0.05","Comparator annotation; no causal/clinical claim."],
    ]
    pd.DataFrame(hub_rows,columns=["HUB_LABEL","FROZEN_RULE","INTERPRETATION"]).to_csv(
        outdir/"D10M_HUB_RULES.csv",index=False
    )

    enrichment_rows=[
        ["PRIMARY_MODULE_FUNCTION","community mRNA set","all 4467 network mRNAs","GO:BP;REAC","FDR","0.05","custom","False"],
        ["SECONDARY_KEGG","community mRNA set","all 4467 network mRNAs","KEGG","FDR","0.05","custom","False"],
        ["SECONDARY_REGULATORY_TARGET_FUNCTION","within-community mRNAs incident to frozen regulatory edges","all network mRNAs incident to any frozen regulatory edge","GO:BP;REAC","FDR","0.05","custom","False"],
    ]
    pd.DataFrame(enrichment_rows,columns=[
        "ANALYSIS_FAMILY","QUERY","BACKGROUND","SOURCES",
        "MULTIPLE_TESTING","THRESHOLD","DOMAIN_SCOPE","ORDERED"
    ]).to_csv(outdir/"D10M_ENRICHMENT_FAMILIES.csv",index=False)

    execution_contract={
        "D10M_STATUS":"PASS",
        "COMMUNITIES_FROZEN":8,
        "NETWORK_MRNA_BACKGROUND":4467,
        "NETWORK_MIRNA_NODES":41,
        "NETWORK_EDGES":11531,
        "FROZEN_REGULATORY_EDGES":1978,
        "ALL_COMMUNITIES_MUST_BE_ANALYZED":"YES",
        "PRIMARY_ENRICHMENT_SOURCES":["GO:BP","REAC"],
        "SECONDARY_ENRICHMENT_SOURCE":"KEGG",
        "ENRICHMENT_SERVICE":"g:Profiler g:GOSt",
        "ENRICHMENT_ORGANISM":"hsapiens",
        "ENRICHMENT_BACKGROUND":"CUSTOM_ALL_4467_NETWORK_MRNA",
        "ENRICHMENT_SIGNIFICANCE_METHOD":"fdr",
        "ENRICHMENT_THRESHOLD":0.05,
        "ENRICHMENT_ORDERED":False,
        "ENRICHMENT_NO_IEA":False,
        "GPROFILER_DATA_VERSION_SNAPSHOT_REQUIRED":"YES",
        "COVID_SPECIFICITY_BINARY_CLASSIFIER":"PROHIBITED",
        "HUB_PRIMARY_METRIC":"INTERNAL_TOPOLOGY_DEGREE",
        "HUB_THRESHOLD":"WITHIN_COMMUNITY_AND_NODE_TYPE_90TH_PERCENTILE_TIES_RETAINED",
        "COMPOSITE_HUB_SCORE":"PROHIBITED",
        "MODULE_COMPOSITE_RANKING":"PROHIBITED",
        "FUNCTIONAL_ENRICHMENT_COUNTS_AS_ACLA_VALIDATION":"NO",
        "MULTISEED_STABILITY_CLAIM_AUTHORIZED":"NO",
        "COMMUNITY_ASSIGNMENTS_CHANGED":"NO",
        "ENRICHMENT_EXECUTED":"NO",
        "HUB_ANALYSIS_EXECUTED":"NO",
        "BIOLOGICAL_INTERPRETATION_EXECUTED":"NO",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "READY_FOR_D10N_BIOLOGICAL_CHARACTERIZATION_EXECUTION":"YES",
        "READY_FOR_BIOLOGICAL_INTERPRETATION":"NO",
        "STOP":"YES",
    }
    (outdir/"D10M_EXECUTION_CONTRACT.json").write_text(
        json.dumps(execution_contract,indent=2),encoding="utf-8"
    )

    md=f"""# D10M — Prospective Biological Interpretation Design Freeze

## Objective

Freeze all downstream biological characterization rules before enrichment, hub
analysis, pathway interpretation, or module-focused biological narrative is generated.

## Upstream authority

- D10J: one prospective original-A-CLA run, 8 fixed communities.
- D10K: signed/regulatory edge characterization, descriptive only.
- D10L: six D6 DE tables attached to all 4,508 nodes.
- Community membership is immutable.

## Functional enrichment

Primary module enrichment uses every mRNA assigned to each community.

Statistical background is all 4,467 mRNA nodes in the frozen network. This is a
selection-aware network background and is intentionally not the whole genome.

Primary sources:
- GO Biological Process (GO:BP)
- Reactome (REAC)

Secondary source:
- KEGG, reported separately.

Execution service:
- g:Profiler g:GOSt
- organism=hsapiens
- domain_scope=custom
- significance_threshold_method=fdr
- user_threshold=0.05
- ordered=False
- no_iea=False

The exact g:Profiler data-version response must be saved before the first query.
All eight communities must be queried in the same execution session/version.

## DE evidence

COVID-vs-healthy is the primary disease annotation.

No single post-hoc binary "COVID-specific" classifier is allowed. The downstream
report must expose the underlying three-contrast evidence directly:
- COV vs H significance and direction
- P vs H significance and direction
- COV vs P significance and direction

Non-significance in sepsis is not proof of absence.

## Hubs

Primary topology hub definition:
- within-community degree;
- mRNAs and miRNAs treated separately;
- threshold = within-community and node-type 90th percentile;
- ties retained.

Regulatory degree, COVID DE, and effect size are separate evidence layers.
No weighted composite hub score is allowed.

## Interpretation limitations

Functional enrichment is post-hoc characterization and cannot be presented as
independent validation of A-CLA.

Because RUN_COUNT=1 was frozen prospectively, these communities must not be described
as multi-seed stable or perturbation-stable.

Topology hubs are candidate priorities, not validated biomarkers.

D10M performs no biological-result analysis.
"""
    (outdir/"D10M_DESIGN_SPECIFICATION.md").write_text(md,encoding="utf-8")

    return 0

if __name__=="__main__":
    raise SystemExit(main())
