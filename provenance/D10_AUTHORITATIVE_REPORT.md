# Comprehensive D10 Report

## GSE243219 Paired mRNA–miRNA Project

### A-CLA Method Audit, Community Detection, Biological Interpretation, Literature Contextualization, and Final Reporting

**Final D10 state:** COMPLETE
**Final reporting phase:** D10V PASS
**Ready for final manuscript interpretation:** YES
**Authoritative final D10V run:**
`D10V_R2_CORRECTED_REPORTING_SOURCE_MAP_20260908_085942`

---

# 1. Purpose of D10

Phase D10 was originally intended to apply A-CLA community detection to the frozen GSE243219 mRNA–miRNA network generated in D9.

However, D10 became substantially more extensive because the D9 network contained both positive and negative association edges, whereas the publication-provenanced A-CLA implementation was fundamentally topology-oriented and was not designed to optimize a signed network directly.

Consequently, D10 developed into a complete methodological chain involving:

1. A-CLA source and lineage audit.
2. Compatibility assessment between published A-CLA and the signed D9 network.
3. Prospective development of a signed A-CLA extension.
4. Synthetic validation and independent benchmarking of that extension.
5. Prospective rejection of the signed extension when signed incremental value could not be demonstrated.
6. Recovery and freezing of the publication-provenanced original A-CLA implementation.
7. Construction of a topology-only representation retaining all D9 associations.
8. Prospective parameter/environment freezing.
9. A single frozen biological A-CLA execution.
10. Post-community recovery of signed and regulatory edge semantics.
11. Differential-expression contextualization.
12. Hub and enrichment analysis.
13. Biological evidence synthesis.
14. Frozen PubMed literature retrieval and abstract-level evidence classification.
15. Final literature synthesis.
16. Construction and validation of the final manuscript-ready reporting package.

This distinction is essential: **the final communities are not Signed A-CLA communities.** They were generated using the publication-provenanced original A-CLA applied to the all-association topology projection.

---

# 2. Scientific network entering D10

D10 consumed the already-frozen D9 multilayer/network representation.

The D9 network contained:

| PropertyFrozen value       |                     |
| -------------------------- | ------------------- |
| Total nodes                | 4,508               |
| mRNA nodes                 | 4,467               |
| miRNA nodes                | 41                  |
| Structural edges           | 11,531              |
| Positive association edges | 5,225               |
| Negative association edges | 6,306               |
| Regulatory-evidence edges  | 1,978               |
| Association-only edges     | 9,553               |
| Connected components       | 2                   |
| Largest component          | 4,502 nodes         |
| Second component           | 6 nodes             |
| Isolated nodes             | 0                   |
| Minimum signed weight      | −0.7753835531973502 |
| Maximum signed weight      | +0.7428957195865319 |

The edge weights represented frozen signed partial-Spearman associations. Both positive and negative associations therefore had scientific meaning and could not simply be deleted, converted to absolute values, clipped, shifted, or rescaled.

The 1,978 regulatory-supported relationships were annotations on structural pairs, not additional duplicate edges.

---

# 3. Fundamental methodological issue identified in D10

## D10A — historical A-CLA lineage audit

D10A investigated whether a previously developed and already validated A-CLA variant existed that could directly be reused.

Historical files showed that an R1 prototype had existed, but it had not completed the required lifecycle of:

- implementation completion;
- execution;
- synthetic validation;
- benchmarking;
- prospective acceptance.

Therefore no authoritative reusable signed R1 implementation existed.

This closed the direct historical-reuse route.

---

# 4. D10B — compatibility of published A-CLA with D9

The publication-provenanced A-CLA implementation was audited against the signed D9 network.

The important properties of original A-CLA included:

- topology-oriented processing;
- default graph binarization;
- positive-edge filtering in its normal input route;
- no signed modularity/objective;
- no explicit use of negative-edge semantics;
- no native regulatory evidence channel;
- no true multilayer signed optimization.

Therefore direct execution against the signed D9 matrix would either ignore or discard information that had already been scientifically frozen.

The resulting scientific decision was:

`PUBLISHED_ACLA_D9_COMPATIBILITY=FAIL`

and:

`SIGNED_WEIGHT_COMPATIBILITY_BLOCKER=YES`

The published method was therefore judged **not natively compatible with the signed D9 representation**.

Importantly, D9 itself was not modified.

---

# 5. D10C — prospective Signed A-CLA design

Because original A-CLA could not directly optimize the signed network, D10C prospectively defined a new methodology before any GSE243219 community result was generated.

The primary design was a signed multichannel A-CLA incorporating:

- signed local evidence;
- signed global objective;
- explicit positive/negative semantics;
- learning-automata reward and penalty rules;
- probability updates;
- regulatory-evidence semantics;
- convergence rules;
- failure criteria;
- synthetic benchmarks;
- ablations;
- independent baselines.

A predeclared fallback was also frozen:

`PLAN_B_METHOD=SIGNED_SINGLE_LAYER_ACLA`

D10C was strictly design-only. No GSE243219 community detection occurred.

---

# 6. D10D/D10E — Signed A-CLA implementation and synthetic validation

The first Signed A-CLA implementation exposed an important transition-dynamics defect.

Although the signed objective and local semantics themselves were valid, the learning dynamics allowed:

- harmful moves;
- duplicate singleton actions;
- label-sensitive switching statistics;
- departure from otherwise good planted partitions.

The failure was classified as:

`LEARNING_DYNAMICS_TRANSITION_INSTABILITY`

A prospective R1 correction was therefore designed.

The R1 correction introduced:

- a strict improving-move gate: `d_i > 1e-12`;
- elimination of duplicate singleton actions;
- partition-invariant switch counting;
- stronger convergence conditions requiring no remaining improving moves;
- stable objective/probability behavior.

The signed objective itself was not redesigned after seeing biological results.

D10D-R1 validation confirmed:

`HARMFUL_MOVE_EXECUTION_BLOCKED=YES`

`BENEFICIAL_MOVE_REMAINS_ELIGIBLE=YES`

`PLANTED_IDEAL_PARTITION_ABSORBING_UNIT_TEST=PASS`

`ALL_EXECUTED_MOVES_STRICTLY_IMPROVING=YES`

The implementation SHA-256 was:

`2bfe790d6aff0fc0404d37683fed2ef0a7c85b78c6a31bb692d3f69d0f7e257d`

No biological execution occurred.

D10E-R1 then repeated the original synthetic test framework without relaxing thresholds:

`D10E_R1_STATUS=PASS`

`CORE_CONFIGURATIONS_TESTED=12`

`CORE_ELIGIBLE_CONFIGURATIONS=12`

Thus the transition correction successfully resolved the original synthetic failure.

---

# 7. Plan A rejection and activation of Plan B

The regulatory multichannel Plan A was prospectively evaluated for identifiability.

Result:

`PLAN_A_STATUS=FAIL_MULTICHANNEL_IDENTIFIABILITY`

`PLAN_A_NONZERO_LAMBDA_IDENTIFIED=NO`

Therefore the predeclared fallback was activated:

`ACTIVE_PLAN_FOR_D10F=PLAN_B_SIGNED_SINGLE_LAYER_ACLA`

Critically, this occurred before any GSE243219 community result existed.

---

# 8. D10F — Signed A-CLA benchmarking

Plan B was benchmarked against independent signed-community approaches including:

- Gómez signed modularity;
- Traag–Bruggeman signed optimization;
- signed spectral clustering;
- unsigned/positive-only Louvain diagnostic.

Ablations included:

- full Signed A-CLA;
- local-only variant;
- global-only variant;
- positive-only semantic diagnostic.

The highest-ranked configuration was:

`CORE_04`

with:

| ParameterFrozen value  |      |
| ---------------------- | ---- |
| alpha\_reward          | 0.1  |
| alpha\_penalty         | 0.3  |
| gamma                  | 0.25 |
| lambda\_regulatory     | 0    |
| Tmax                   | 200  |
| objective\_tolerance   | 1e-6 |
| probability\_tolerance | 0.01 |
| patience               | 5    |

D10F itself did not authorize execution on GSE243219.

---

# 9. D10G — prospective rejection of Signed A-CLA

Nine acceptance gates were prospectively frozen.

CORE\_04 passed:

`8 / 9`

The sole failed gate was:

`G7_SIGNED_VALUE_OVER_POSITIVE_ONLY`

Therefore:

`D10G_STATUS=FAIL_CLOSED`

`METHOD_ACCEPTED_FOR_PROSPECTIVE_FREEZE=NO`

The Signed A-CLA implementation was **not authorized for GSE243219 biological community detection**.

## D10G-D1

The failure was not marginal:

`G7_AGGREGATE_ARI_ADVANTAGE=0.0`

Required:

`0.02`

Signed-task wins:

`3`

Required:

`7`

Conclusion:

`SIGNED_SEMANTIC_INCREMENTAL_VALUE_ESTABLISHED=NO`

## D10G-D2/D3

A stronger sign-identifiability experiment was then performed.

Results included:

`INFORMATIVE_AGGREGATE_MEDIAN_TASK_ARI_ADVANTAGE=0.015018453733424711`

`SIGNED_WINS=13/25`

`MEDIAN_SIGNED_ARI=0.05121683614775767`

`MEDIAN_SEED_STABILITY=0.35946872322193657`

`COUNTERFACTUAL_SUCCESS=2/5`

Final classification:

`SIGN_UTILIZATION_NOT_DEMONSTRATED`

Thus Signed A-CLA R1 could not reliably exploit negative-edge structure even in deliberately sign-informative synthetic tasks.

## D10G-D4/D5 mechanistic analysis

Further diagnostics localized the problem:

- objective-identifiable task fraction: `0.06666666666666667`;
- truth-consistent improving-move accessibility: `1.0`;
- local/global fusion conflict count: `0`;
- median early ARI-improving move fraction: `0.48148148148148145`;
- implementation replay equivalence: PASS;
- second-order relational signal availability: `0.0`.

Final mechanistic classification:

`PRIMARY_MECHANISM=REPRESENTATION_SIGNAL_DEFICIENCY`

`SECONDARY_MECHANISM=SIGNED_OBJECTIVE_IDENTIFICATION_FAILURE`

Therefore the failure was methodological evidence against using this Signed A-CLA implementation—not a failure of the biological dataset itself.

---

# 10. Return to publication-provenanced A-CLA

The signed extension having failed prospective acceptance, D10 returned to the original published A-CLA implementation.

A separate reconciliation also established that Signed A-CLA R1 differed substantially from the architecture represented by the recovered publication implementation. The publication-provenanced code, rather than R1 or simplified pseudocode, was therefore designated the authoritative implementation for the final biological analysis.

---

# 11. D10H — topology-only projection for original A-CLA

The key methodological solution was to separate:

**Scientific D9 network**

from:

**A-CLA optimization representation**

All 11,531 frozen associations were retained as structural existence edges:

`association exists → adjacency = 1`

This is not equivalent to replacing signed weights by their absolute values.

The signed weights remained unchanged as metadata for later interpretation.

The initial D10H package encountered a package/runtime failure and was not scientifically evaluated.

The corrected D10H-R2 passed.

Frozen conservation:

| PropertyD9D10H projection |        |        |
| ------------------------- | ------ | ------ |
| Nodes                     | 4,508  | 4,508  |
| Edges                     | 11,531 | 11,531 |
| Positive edges retained   | 5,225  | 5,225  |
| Negative edges retained   | 6,306  | 6,306  |
| Negative edges deleted    | —      | 0      |

Other gates:

`SELF_LOOPS=0`

`DUPLICATE_EDGES=0`

`UNKNOWN_ENDPOINTS=0`

`D9_SIGNED_WEIGHT_METADATA_PRESERVED=YES`

`REGULATORY_EVIDENCE_USED_DURING_ACLA_OPTIMIZATION=NO`

`REGULATORY_EDGE_DUPLICATION=0`

`ORIGINAL_ACLA_TOPOLOGY_PROJECTION_COMPATIBILITY=PASS`

The projection therefore asked:

**Which mRNA/miRNA nodes form densely interconnected groups of stable associations?**

It did **not** claim to optimize separation of positive versus negative relationships.

---

# 12. D10I — original A-CLA parameter/environment freeze

The exact publication-provenanced defaults were frozen:

| ParameterValue     |      |
| ------------------ | ---- |
| BINARIZE           | True |
| ITERATIONS         | 200  |
| ALPHA0             | 0.20 |
| ALPHA\_MIN         | 0.01 |
| GLOBAL\_WEIGHT     | 0.35 |
| PATIENCE           | 10   |
| SEED               | 42   |
| MODULARITY\_WEIGHT | None |
| RUN\_COUNT         | 1    |

The original source remained byte-identical.

Because the Louvain initializer did not explicitly receive a `random_state`, reproducibility was externally frozen using:

`PYTHONHASHSEED=42`

`random.seed(42)`

`numpy.random.seed(42)`

The initial D10I execution failed closed because the required Louvain runtime dependency was unavailable. This was an environment failure only—not a scientific failure.

After dependency remediation, the unchanged frozen D10I configuration was subsequently accepted and D10J execution became authorized.

---

# 13. D10J — authoritative original A-CLA biological execution

D10J was the first D10 stage authorized to execute community detection on the actual GSE243219 network.

The publication-provenanced original A-CLA was run once against the frozen D10H topology projection.

Authoritative result:

`D10J_STATUS=PASS`

Key execution results:

| MetricResult                             |                    |
| ---------------------------------------- | ------------------ |
| Input nodes                              | 4,508              |
| Input edges                              | 11,531             |
| Frozen seed                              | 42                 |
| Final communities                        | 8                  |
| Best communities                         | 8                  |
| Final modularity                         | 0.5022686748930412 |
| Approximate community-size range         | 566–583 nodes      |
| Unmapped nodes                           | 0                  |
| Singleton communities                    | 0                  |
| Parameter tuning after biological result | NO                 |

The original A-CLA run used topology only. Signed weights and regulatory annotations did not participate in the optimization.

This is the **authoritative final community partition** for GSE243219.

No multi-seed stability claim is authorized because the frozen design specified a single prospective run.

---

# 14. D10K — post-community restoration of edge semantics

After community assignments had been frozen, D10K reattached the original D9 edge properties for descriptive characterization.

This did not rerun community detection.

All 11,531 frozen structural edges were mapped against the eight communities.

Approximate structural split:

- internal edges: 6,015;
- external edges: 5,516;
- positive edges: 5,225;
- negative edges: 6,306;
- regulatory-supported edges: 1,978.

Required scientific distinction:

`EDGE_SIGN_REATTACHED_POST_COMMUNITY=YES`

`EDGE_WEIGHT_REATTACHED_POST_COMMUNITY=YES`

`COMMUNITY_ASSIGNMENTS_CHANGED_BY_SIGN=NO`

`COMMUNITY_ASSIGNMENTS_CHANGED_BY_WEIGHT=NO`

Therefore positive/negative remains an **edge property**, not a universal gene label.

---

# 15. D10L — differential-expression contextualization

D10L attached already-frozen differential-expression evidence to the fixed community assignments.

No DE model was rerun.

Reported project-level node counts included approximately:

| DE categoryNodes                                        |     |
| ------------------------------------------------------- | --- |
| COV vs healthy significant                              | 711 |
| Sepsis vs healthy significant                           | 260 |
| COV vs sepsis significant                               | 256 |
| Shared directional COVID/sepsis response                | 221 |
| COVID-associated with direct COVID-vs-sepsis difference | 136 |

These values were descriptive biological annotations.

D10L did not:

- reassign communities;
- construct a new composite score;
- rerank nodes;
- select hubs;
- perform enrichment.

---

# 16. D10M — biological interpretation design freeze

D10M prospectively froze how biological characterization of the eight communities would be performed.

Authoritative run:

`D10M_BIOLOGICAL_INTERPRETATION_DESIGN_FREEZE_20260906_232912`

The phase defined enrichment families and interpretation policies before execution of the biological characterization. Its artifacts included `D10M_ENRICHMENT_FAMILIES.csv`.

The purpose of D10M was to prevent post-hoc selection of attractive pathways, hub definitions, or interpretation rules.

---

# 17. D10N — frozen enrichment, hub, and biological-evidence calculation

The authoritative D10N run was:

`D10N_R4_CERTIFI_TLS_REMEDIATION_EXECUTION_20260906_235931`

Final D10N authority required:

`D10N_STATUS=PASS`

`COMMUNITIES_ANALYZED=8`

`ALL_8_COMMUNITIES_REPORTED=YES`

`COMMUNITY_ASSIGNMENTS_CHANGED=NO`

`ENRICHMENT_EXECUTED=YES`

`HUB_ANALYSIS_EXECUTED=YES`

`BIOLOGICAL_EVIDENCE_CALCULATION_EXECUTED=YES`

`BIOLOGICAL_INTERPRETATION_NARRATIVE_EXECUTED=NO`

`READY_FOR_D10O_BIOLOGICAL_INTERPRETATION=YES`

D10N produced the authoritative full enrichment results, including:

- `D10N_PRIMARY_GO_BP_REAC_ENRICHMENT.csv`
- `D10N_SECONDARY_KEGG_ENRICHMENT.csv`
- `D10N_SECONDARY_REGULATORY_TARGET_ENRICHMENT.csv`

as well as g\:Profiler requests/responses, database version records, enrichment query coverage, hub candidates, and node-level biological evidence.

This phase—not D10S—owns the complete frozen enrichment results.

---

# 18. D10O — biological interpretation evidence synthesis

Authoritative run:

`D10O_BIOLOGICAL_INTERPRETATION_EVIDENCE_SYNTHESIS_20260907_093455`

D10O synthesized D10N results for all eight communities without rerunning the upstream analyses.

Final status:

`D10O_STATUS=PASS`

`COMMUNITIES_INTERPRETED=8`

`ALL_8_COMMUNITIES_REPORTED=YES`

Display policies were transparently frozen:

- primary GO\:BP/Reactome: top 10 per community by p-value;
- KEGG: top 5;
- regulatory-target GO\:BP/Reactome: top 10.

Important safeguards:

`ALL_PRIMARY_HUBS_RETAINED=YES`

`COMPOSITE_HUB_SCORE_CREATED=NO`

`MODULE_COMPOSITE_RANKING_CREATED=NO`

`COMMUNITY_ASSIGNMENTS_CHANGED=NO`

`ENRICHMENT_RERUN=NO`

`HUB_ANALYSIS_RERUN=NO`

`CAUSAL_CLAIMS_CREATED=NO`

`CLINICAL_VALIDATION_CLAIMS_CREATED=NO`

`FUNCTIONAL_ENRICHMENT_COUNTS_AS_ACLA_VALIDATION=NO`

`MULTISEED_STABILITY_CLAIM_AUTHORIZED=NO`

D10O explicitly states that functional enrichment is post-hoc biological characterization rather than independent validation of A-CLA.

---

# 19. D10P–D10Q — frozen literature-contextualization route

D10O authorized the next stage:

`READY_FOR_D10P_EXTERNAL_LITERATURE_CONTEXTUALIZATION=YES`

The precise D10P artifact title is not fully recoverable from the currently indexed evidence, so no unsupported implementation detail should be attributed to it.

The subsequent authoritative PubMed retrieval provenance stage is clearly identifiable as:

`D10Q_PUBMED_RETRIEVAL_PROVENANCE_20260907_095155`

D10Q preserved:

- raw NCBI ESearch responses;
- primary and fallback queries;
- query checkpoints;
- community;
- target category;
- COVID-19/sepsis context;
- exact PubMed retrieval provenance.

Raw ESearch JSON and query checkpoints exist across the frozen community/target/disease query universe.

Any intermediate D10R preparation should be regarded only as part of the frozen literature-preparation chain; its exact title/status is not sufficiently supported in the currently recovered evidence to warrant more specific claims.

---

# 20. D10S — title/abstract literature screening

Authoritative run:

`D10S_R2_CORRECTED_NODEMAP_SCREENING_20260907_113729`

Final:

`D10S_STATUS=PASS`

The screening universe contained:

| MeasureValue                              |       |
| ----------------------------------------- | ----- |
| Communities screened                      | 8     |
| Query–PMID pairs                          | 2,531 |
| Unique PMIDs                              | 2,137 |
| Direct target-disease records             | 2,137 |
| Irrelevant/ambiguous                      | 389   |
| Metadata-only/no abstract                 | 5     |
| Concordant contextual-support records     | 75    |
| Discordant/contradictory records          | 28    |
| Mixed records                             | 62    |
| Relevant but not directionally comparable | 1,051 |
| No directional claim                      | 921   |
| Zero-hit queries                          | 194   |

The screening source was:

`PUBMED_TITLE_ABSTRACT_METADATA_ONLY`

Important restrictions:

`FULL_TEXT_SCREENING_EXECUTED=NO`

`NEW_LITERATURE_SEARCH_EXECUTED=NO`

`GENE_ALIAS_EXPANSION_EXECUTED=NO`

Zero-hit queries were explicitly **not** treated as negative biological evidence.

Contradictory evidence was retained.

Community assignments, hub status, and enrichment were not modified.

---

# 21. D10T — frozen join-key/schema layer

Authoritative run:

`D10T_R2_CORRECTED_JOINKEY_SCHEMA_FREEZE_20260907_114951`

D10T froze the mapping needed to connect the literature targets back to the already-frozen project/community identifiers.

This phase was important because literature tables contained both display labels and stable identifiers.

The final D10V reconciliation later demonstrated exact coverage of the authoritative 187 `(community,target)` pairs.

No biological selection was performed in D10T.

---

# 22. D10U — literature evidence synthesis

## Initial D10U attempt

The first D10U run failed because of a reporting/package schema error involving the expected field:

`zero_retrieval_under_frozen_search`

This was classified as:

- package/schema error;
- not a scientific failure;
- D10U not scientifically evaluated;
- no new literature search;
- no biological reanalysis;
- no reason to rerun D10O/S/T.

## D10U-R2

Authoritative corrected run:

`D10U_R2_CORRECTED_ZERO_RETRIEVAL_SCHEMA_20260907_120433`

Final:

`D10U_STATUS=PASS`

The authoritative universe was:

| Literature measureFinal value    |       |
| -------------------------------- | ----- |
| Communities synthesized          | 8     |
| Literature targets               | 187   |
| Target-disease units             | 374   |
| Screened query–PMID pairs        | 2,531 |
| Unique PMIDs                     | 2,137 |
| Narrative targets                | 103   |
| Narrative target-disease units   | 206   |
| Deterministic citation exemplars | 133   |

The 374 target-disease units were exhaustively partitioned into:

| Evidence stateUnits                              |         |
| ------------------------------------------------ | ------- |
| Zero retrieval                                   | 194     |
| No direct relevant abstract evidence             | 29      |
| Concordant only                                  | 14      |
| Concordant + contradictory/mixed                 | 17      |
| Contradictory/mixed without concordant           | 15      |
| Direct relevance without directional concordance | 105     |
| **Total**                                        | **374** |

Additional guards:

`CONTRADICTORY_EVIDENCE_DISPLAYED_WHEN_PRESENT=YES`

`NARRATIVE_TARGET_SELECTION_CHANGED_BY_LITERATURE=NO`

`LITERATURE_CONCORDANCE_COUNTS_AS_ACLA_VALIDATION=NO`

`FULL_TEXT_REVIEW_EXECUTED=NO`

`SYSTEMATIC_REVIEW_CLAIM_CREATED=NO`

`EVIDENCE_SCORE_CREATED=NO`

`VOTE_COUNTING_EXECUTED=NO`

`NEW_LITERATURE_SEARCH_EXECUTED=NO`

`NEW_BIOLOGICAL_ANALYSIS_EXECUTED=NO`

`D10U_HASH_MISMATCHES=0`

The correct interpretation of the 194 zero-retrieval units is:

**“No records were retrieved under the frozen search strategy.”**

They must not be described as evidence that “no literature exists.”

---

# 23. D10V — final reporting layer

D10V was explicitly defined as a reporting-only phase.

It was prohibited from:

- rerunning A-CLA;
- changing communities;
- recomputing hubs;
- rerunning enrichment;
- rerunning DE;
- rerunning association analysis;
- performing new PubMed searches;
- retrieving new PMIDs;
- creating evidence scores;
- performing vote counting;
- literature-based reranking;
- creating new biological thresholds or tests.

The intended final package included master tables, community narratives, literature evidence, citation exemplars, seven manuscript-ready tables, supplementary tables, figure plan, provenance map, limitations, final status, and SHA-256 manifest.

---

# 24. D10V fail-closed correction history

The D10V reporting package itself exposed several schema/provenance defects. None represented scientific failure.

## R1 — incorrect enrichment source

Initial D10V incorrectly expected enrichment from D10S.

Failure:

`NO_SOURCE_TABLE:D10S:required=community_id,enrichment_term`

Audit established that:

- D10S owns literature screening;
- D10N owns complete frozen enrichment;
- D10O synthesizes/displays D10N enrichment.

No upstream rerun occurred.

## R2 — corrected enrichment provenance

D10V was changed to use D10O/D10N frozen enrichment provenance.

Scientific policy unchanged.

## R2.1 — D9 root discovery

D9 had been incorrectly searched under `09_ACLA`.

Correct location:

`08_NETWORK_CONSTRUCTION\D9_FINAL_MULTILAYER_NETWORK_CONSTRUCTION_*`

This was an execution-path defect only.

## R2.2 — edge-sign schema

D9 did not have a standalone `edge_sign` column.

D10V therefore deterministically derived sign from the already-frozen signed edge weight:

`weight > 0 → positive`

`weight < 0 → negative`

Zero weight would fail closed.

No weight was recalculated.

## R2.3 — D10N community key

Full enrichment tables did not necessarily contain a literal `community_id`.

D10V accepted only an explicit community field or a strict frozen query key corresponding to communities 1–8, followed by exact reconciliation with D10O enrichment counts.

## R2.4 — `analysis_family` collision

D10N already contained an `analysis_family` column.

D10V stopped overwriting it and instead created a namespaced reporting field:

`D10V_analysis_family`

## R2.5 — D10U table discovery

D10V originally expected a particular D10U schema.

It was changed to identify the authoritative 374-unit matrix only through frozen accounting invariants.

## R2.6 — evidence-state reconstruction

The authoritative D10U matrix did not contain a literal final `evidence_state` field.

D10V reconstructed a reporting-only state from frozen counts and accepted it only when the exact partition:

`194 + 29 + 14 + 17 + 15 + 105 = 374`

was recovered.

No literature evidence was newly classified.

## R2.7 — target identifier

An initially selected display-level target field yielded only 157 unique targets.

D10V rejected it and accepted only the frozen identifier satisfying:

`187 unique targets × 2 contexts = 374 units`

## R2.8 — narrative-selection provenance

The 103 narrative targets were resolved from frozen D10U-R2 provenance.

Final:

`NARRATIVE_SELECTION_SOURCE_PHASE=D10U-R2`

and:

`103 targets × 2 contexts = 206 units`

Literature support did not change the narrative target selection.

## R2.9 — D10T join key

The generic alias logic preferred `target_label` before `target_id`, causing all 187 `(community,target)` joins to fail.

R2.9 selected the D10T target key only by exact frozen coverage of all 187 authoritative community-target pairs.

This correction finally resolved the reporting chain.

---

# 25. Final authoritative D10V result

Authoritative run:

`C:\Users\Amir\OneDrive\Desktop\covid-19\GSE243219_NEW_PROJECT\09_ACLA\D10V_R2_CORRECTED_REPORTING_SOURCE_MAP_20260908_085942`

Final terminal state:

```text
D10V_STATUS=PASS

D9_FROZEN_PROVENANCE_VERIFIED=YES
D10N_FROZEN_PROVENANCE_VERIFIED=YES
D10O_AUTHORITATIVE_INPUT_VERIFIED=YES
D10S_AUTHORITATIVE_INPUT_VERIFIED=YES
D10T_AUTHORITATIVE_INPUT_VERIFIED=YES
D10U_R2_AUTHORITATIVE_INPUT_VERIFIED=YES

UPSTREAM_HASH_MISMATCHES=0

COMMUNITIES_REPORTED=8

COMMUNITY_ASSIGNMENTS_CHANGED=NO
HUB_STATUS_CHANGED=NO
ENRICHMENT_CHANGED=NO

EDGE_SIGN_REATTACHED_POST_COMMUNITY=YES
EDGE_WEIGHT_REATTACHED_POST_COMMUNITY=YES
COMMUNITY_ASSIGNMENTS_CHANGED_BY_SIGN=NO
COMMUNITY_ASSIGNMENTS_CHANGED_BY_WEIGHT=NO

COMMUNITY_MASTER_SUMMARY_CREATED=YES
TARGET_MASTER_TABLE_CREATED=YES
COMMUNITY_NARRATIVES_CREATED=YES

```

Literature:

```text
LITERATURE_TARGETS=187
TARGET_DISEASE_UNITS=374

NARRATIVE_TARGETS=103
NARRATIVE_TARGET_DISEASE_UNITS=206

ZERO_RETRIEVAL_UNITS=194
NO_DIRECT_RELEVANT_ABSTRACT_EVIDENCE_UNITS=29
CONCORDANT_ONLY_UNITS=14
CONCORDANT_WITH_CONTRADICTORY_OR_MIXED_UNITS=17
CONTRADICTORY_OR_MIXED_WITHOUT_CONCORDANT_UNITS=15
DIRECT_RELEVANCE_WITHOUT_DIRECTIONAL_CONCORDANCE_UNITS=105

TARGET_DISEASE_ACCOUNTING=PASS

DETERMINISTIC_CITATION_EXEMPLARS_SELECTED=133

```

Cross-artifact accounting:

```text
COMMUNITY_ACCOUNTING=PASS
HUB_ACCOUNTING=PASS
ENRICHMENT_ACCOUNTING=PASS
LITERATURE_ACCOUNTING=PASS
CITATION_ACCOUNTING=PASS

```

Reporting outputs:

```text
MANUSCRIPT_TABLES_CREATED=7
SUPPLEMENTARY_TABLES_CREATED=9
FIGURE_PLAN_CREATED=YES
PROVENANCE_MAP_CREATED=YES
REPORTING_ELEMENT_WITHOUT_PROVENANCE=0
LIMITATIONS_FILE_CREATED=YES

```

No-new-analysis guards:

```text
NEW_BIOLOGICAL_ANALYSIS_EXECUTED=NO
NEW_STATISTICAL_TEST_EXECUTED=NO
NEW_LITERATURE_SEARCH_EXECUTED=NO
NEW_ENRICHMENT_EXECUTED=NO
NEW_HUB_SELECTION_EXECUTED=NO
NEW_TARGET_RANKING_CREATED=NO
NEW_CITATION_SELECTION_EXECUTED=NO
EVIDENCE_SCORE_CREATED=NO
VOTE_COUNTING_EXECUTED=NO

```

Integrity:

```text
D10V_SHA256_MANIFEST_CREATED=YES
D10V_HASH_MISMATCHES=0
D10V_POST_MANIFEST_VALIDATION=PASS

READY_FOR_FINAL_MANUSCRIPT_INTERPRETATION=YES
STOP=YES

```

---

# 26. Final D10 deliverables

The final reporting layer contains, at minimum:

- `D10V_COMMUNITY_MASTER_SUMMARY.csv`
- `D10V_TARGET_MASTER_TABLE.csv`
- `D10V_COMMUNITY_NARRATIVES.md`
- `D10V_LITERATURE_EVIDENCE_TABLE.csv`
- `D10V_CITATION_EXEMPLAR_TABLE.csv`
- `D10V_TABLE_1_COMMUNITY_OVERVIEW.csv`
- `D10V_TABLE_2_COMMUNITY_HUBS.csv`
- `D10V_TABLE_3_SIGNED_EDGE_CHARACTERISTICS.csv`
- `D10V_TABLE_4_REGULATORY_EVIDENCE.csv`
- `D10V_TABLE_5_FUNCTIONAL_ENRICHMENT_SUMMARY.csv`
- `D10V_TABLE_6_LITERATURE_CONTEXTUALIZATION.csv`
- `D10V_TABLE_7_ZERO_NEGATIVE_MIXED_EVIDENCE.csv`
- nine detailed supplementary tables;
- `D10V_FIGURE_PLAN.csv`
- `D10V_PROVENANCE_MAP.csv`
- `D10V_LIMITATIONS.md`
- `D10V_REPORTING_README.md`
- `D10V_FINAL_STATUS.txt`
- `D10V_SHA256_MANIFEST.csv`

The reporting specification explicitly requires manuscript and supplementary outputs to derive only from authoritative frozen results.

---

# 27. Scientific interpretation boundaries

Several distinctions must be preserved in every manuscript derived from D10.

## 27.1 What the communities represent

The eight communities represent dense topological groupings of the 11,531 stable mRNA–miRNA associations.

They do not represent communities optimized directly according to signed correlation.

## 27.2 Edge sign

Positive and negative are edge properties.

A node can participate in both positive and negative relationships.

A gene must not be described as universally “positive” or “negative” merely because of its community.

## 27.3 Regulatory evidence

The 1,978 regulatory-supported associations were not duplicate structural edges and were not used as a separate optimization channel in the final A-CLA run.

They were used for post-community biological characterization.

## 27.4 Signed A-CLA

Signed A-CLA R1 was developed, corrected, validated, and benchmarked, but prospectively rejected.

It must not be described as the method that generated the final GSE243219 communities.

## 27.5 Enrichment

Functional enrichment is post-hoc biological characterization.

It is not independent validation of A-CLA.

## 27.6 Literature evidence

Literature concordance is biological contextualization, not validation of A-CLA.

Permitted language includes:

- literature-contextualized biological interpretation;
- literature concordance;
- supporting published evidence;
- contrasting published evidence;
- mixed published evidence.

Avoid:

- literature-validated community;
- validated A-CLA module;
- confirmed target;
- systematic review;
- comprehensive literature review;
- full-text review.

The literature phase was title/abstract/metadata based, not a full-text systematic review.

## 27.7 Zero retrieval

The 194 zero-retrieval target-disease units must be described as:

**No records were retrieved under the frozen search strategy.**

They do not establish absence of literature or absence of biological association.

## 27.8 Stability

The original A-CLA biological partition came from the prospectively frozen single-run execution.

No unsupported multi-seed stability claim should be made.

---

# 28. Overall methodological conclusion

D10 produced two very different methodological findings.

First, the project demonstrated that simply forcing published A-CLA onto a signed biological network would have been scientifically inappropriate. A new Signed A-CLA extension was therefore developed and evaluated prospectively. Although technically functional after correction, it failed the predefined evidence requirement demonstrating meaningful incremental value from signed information and was consequently rejected before biological execution.

Second, a scientifically defensible route for the original publication-provenanced A-CLA was established by separating the biological network from the optimization representation. All 11,531 stable associations were retained as topology edges; no positive or negative edge was deleted; the original signed weights and regulatory evidence remained frozen for downstream biological interpretation.

The resulting original A-CLA execution produced eight communities with modularity approximately 0.50227, after which signed edge profiles, regulatory evidence, differential-expression evidence, hubs, enrichment, and literature evidence were layered onto those fixed communities without altering membership.

The final literature analysis retained both supportive and contradictory evidence and explicitly preserved absent-evidence states.

Finally, D10V reconciled every reporting element against its authoritative source and achieved complete SHA-256 validation.

---

# 29. Final D10 decision

The authoritative final state is:

```text
D10_COMPLETE=YES

AUTHORITATIVE_COMMUNITIES=8
AUTHORITATIVE_ACLA_METHOD=
PUBLICATION_PROVENANCED_ORIGINAL_ACLA_ON_ALL_ASSOCIATION_TOPOLOGY_PROJECTION

SIGNED_ACLA_R1_USED_FOR_BIOLOGICAL_EXECUTION=NO

D9_SIGNED_NETWORK_MODIFIED=NO
NEGATIVE_EDGES_REMOVED=NO
SIGNED_WEIGHTS_MODIFIED=NO

COMMUNITY_ACCOUNTING=PASS
HUB_ACCOUNTING=PASS
ENRICHMENT_ACCOUNTING=PASS
LITERATURE_ACCOUNTING=PASS
CITATION_ACCOUNTING=PASS

NEW_ANALYSIS_IN_FINAL_REPORTING_LAYER=NO

D10V_STATUS=PASS
D10V_HASH_MISMATCHES=0
D10V_POST_MANIFEST_VALIDATION=PASS

READY_FOR_FINAL_MANUSCRIPT_INTERPRETATION=YES
STOP=YES

```

## Final scientific status

**Phase D10 is complete.**

No D10 analytical phase requires rerunning.

The authoritative outputs are now frozen and suitable for:

**final Results writing → community-by-community interpretation → figure generation from frozen results → manuscript assembly.**

The D10 analytical workflow should therefore be treated as closed unless a later independent audit demonstrates a concrete integrity problem in an authoritative artifact.