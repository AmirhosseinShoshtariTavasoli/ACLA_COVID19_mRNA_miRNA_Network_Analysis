# Drug–gene validation and VDGEI

The final manuscript drug–gene stage was **not executed as a local software pipeline**. Candidate drug–gene pairs were reviewed interactively against pharmacological, transcriptomic, disease-context, human, regulatory, and contradictory evidence, and the study-specific Validated Drug–Gene Evidence Index (VDGEI) was assigned during an **AI-assisted evidence-synthesis process**.

The scoring rubric used in the manuscript allocated:

- up to 40 points: gene-correction evidence;
- up to 25 points: disease-context evidence;
- up to 15 points: human exact-gene evidence;
- up to 10 points: independent reference support;
- up to 10 points: regulatory/translational feasibility;
- up to 20 points subtracted for substantial contradictory evidence.

The review also required exact target identity and direction relative to the COV_vs_H expression change. Expression modulation, protein-level pharmacology, and clinical efficacy were treated as distinct evidence layers.

No VDGEI script was executed on the author's computer. Consequently, this repository deliberately contains **no synthetic replacement implementation**. Reproducibility for this stage is documentary: preserve the rubric, reviewed evidence, final pair classifications, and reported scores.

VDGEI is a study-specific evidence-ranking device; it is not a validated clinical score, universal effect size, or substitute for measured pharmacological potency.
