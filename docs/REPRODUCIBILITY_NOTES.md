# Reproducibility notes

1. The preserved `.ps1` files are provenance-first scripts and may contain absolute paths or checks tied to the original Windows project layout.
2. Python 3.12.3 and InMoose 0.9.1 were explicitly validated in the project.
3. The source GEO matrices contain fractional counts for mRNA; do not coerce them to integers.
4. The mature-miRNA primary representation consolidates repeated precursor rows sample-wise by the median; maximum consolidation is sensitivity-only.
5. Only COV_vs_H FDR-significant features enter the primary cross-modal association universe.
6. Sepsis is a contextual comparator; it is not included in the primary partial-Spearman fit.
7. Bootstrap resampling is paired across modalities and stratified by disease group.
8. Regulatory evidence annotates retained stable associations; it does not create duplicate structural edges.
9. A-CLA community detection uses a topology-only projection containing all 11,531 stable associations; signed weights are restored only after partition discovery.
10. The final A-CLA design specifies one prospective biological execution; do not add a multi-seed stability claim that was not performed.
11. The final drug–gene review and VDGEI ranking were an **interactive AI-assisted evidence-synthesis step**, not an executed local analysis script. Reproducibility for this component means preserving the scoring rubric, evidence table, and final assigned scores—not implying a program was run.
12. No dedicated figure-generation script was executed for the manuscript figures. Figures should be treated as presentation artifacts derived from frozen results, not as outputs of an archived plotting pipeline.
13. VDGEI is a study-specific evidence-ranking index and must not be interpreted as a clinical efficacy score or universal pharmacological effect size.
