# D10M — Prospective Biological Interpretation Design Freeze

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
