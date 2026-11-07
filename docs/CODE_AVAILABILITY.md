# Code availability

This repository accompanies the GSE243219 paired mRNA–miRNA A-CLA manuscript.

The recovered executable D0–D9 workflow and the authoritative D10H–D10U source lineage are included. The exact publication-provenanced A-CLA source and the frozen execution wrapper used for the accepted D10J biological run are preserved byte-for-byte and verified against their recorded SHA-256 hashes. D10V was a deterministic reporting/provenance stage and did not contain a standalone executable source file.

## Non-code manuscript stages

The final drug–gene validation and Validated Drug–Gene Evidence Index (VDGEI) ranking were **not executed as a local program**. The scores were constructed during an interactive AI-assisted evidence-synthesis process using the manuscript's prespecified scoring rubric. To preserve methodological accuracy, this repository documents that rubric and the final evidence-review procedure but does not create replacement scoring code after the fact.

No dedicated manuscript figure-generation program was executed in the recovered project archive. The publication figures were assembled from frozen computational/reporting outputs; therefore no reconstructed plotting script is presented as original executed code.

These distinctions are intentional: the repository reproduces the computational stages for which executable provenance exists and documents manual/AI-assisted or presentation-only stages separately.
