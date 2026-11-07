# Authoritative D10 lineage

This file records the accepted D10 path used for the manuscript. Earlier runs are retained only under `legacy/` or `experiments/`.

| Stage | Authoritative run | Role | Final status |
|---|---|---|---|
| D10H | D10H_R2_CORRECTED_ORIGINAL_ACLA_RECONCILIATION_TOPOLOGY_FREEZE_20260906_180940 | Reconcile original published A-CLA and create the all-edge topology projection | PASS |
| D10I | D10I_ORIGINAL_ACLA_PARAMETER_ENVIRONMENT_FREEZE_20260906_222323 | Freeze parameters/environment and executable wrapper | PASS |
| D10J | D10J_ORIGINAL_ACLA_PROSPECTIVE_EXECUTION_20260906_223806 | Single prespecified biological A-CLA execution | PASS |
| D10K | D10K_POSTHOC_COMMUNITY_CHARACTERIZATION_20260906_230617 | Restore signed/regulatory edge semantics after partitioning | PASS |
| D10L | D10L_BIOLOGICAL_ANNOTATION_SOURCE_FREEZE_20260906_231618 | Freeze biological annotation sources | PASS |
| D10M | D10M_BIOLOGICAL_INTERPRETATION_DESIGN_FREEZE_20260906_232912 | Prespecify hub/enrichment/interpretation rules | PASS |
| D10N | D10N_R4_CERTIFI_TLS_REMEDIATION_EXECUTION_20260906_235931 | Accepted hub/enrichment execution | PASS |
| D10O | D10O_BIOLOGICAL_INTERPRETATION_EVIDENCE_SYNTHESIS_20260907_093455 | Biological evidence synthesis | PASS |
| D10P | D10P_EXTERNAL_LITERATURE_CONTEXTUALIZATION_DESIGN_FREEZE_20260907_094317 | Literature-search design freeze | PASS |
| D10Q | D10Q_PUBMED_RETRIEVAL_PROVENANCE_20260907_095155 | PubMed retrieval with provenance | PASS |
| D10R | D10R_LITERATURE_SCREENING_EVIDENCE_CLASSIFICATION_DESIGN_FREEZE_20260907_103030 | Screening/classification design freeze | PASS |
| D10S | D10S_R2_CORRECTED_NODEMAP_SCREENING_20260907_113729 | Corrected literature screening/classification | PASS |
| D10T | D10T_R2_CORRECTED_JOINKEY_SCHEMA_FREEZE_20260907_114951 | Corrected literature synthesis/join schema freeze | PASS |
| D10U | D10U_R2_CORRECTED_ZERO_RETRIEVAL_SCHEMA_20260907_120433 | Corrected biological/literature synthesis | PASS |
| D10V | D10V_R2_CORRECTED_REPORTING_SOURCE_MAP_20260908_085942 | Final deterministic reporting package | PASS |

## Exact A-CLA execution identity

The successful D10J run records:

- original published A-CLA source SHA-256: `ee3c3b735ba6593d5a6af155e599403e697f498b290dc75a39ff0e3ab90b07de`
- frozen execution wrapper SHA-256: `794e5564de1cea41a172692cb95f70199563128c2e01beae8c4fd7ed4f58a5a5`
- topology adjacency SHA-256: `51dd8e6d5bfcec0dfef48be679878677e52d5a4de6eea3f7b2f6ef88a85558ee`
- seed: `42`
- communities: `8`
- unweighted modularity: `0.5022686748930412`
- parameter tuning after result inspection: `NO`

The executable used for D10J was the frozen wrapper created in D10I; D10J itself preserved the result and post-execution technical audit rather than a second copy of the wrapper.

## D10V note

No executable D10V source file was present in the recovered D10V final run folder. The final D10V package explicitly states that it performed no new biological analysis, statistical testing, enrichment, literature search, hub selection, target ranking, community reassignment, evidence scoring, or vote counting. The final D10V status, reporting README, source map, and provenance map are retained under `provenance/d10_authoritative_runs/D10V/`.
