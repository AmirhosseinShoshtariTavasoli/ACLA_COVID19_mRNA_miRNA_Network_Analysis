# D10P — External Literature Contextualization Design Freeze

## Purpose
Freeze PubMed target selection and retrieval rules before any external search.

## Deterministic targets
1. Every enrichment term displayed by D10O.
2. Top five nodes/community by frozen internal degree for each:
   - COVID-associated hubs
   - COV-vs-sepsis discriminating hubs
   - regulatory-hub evidence nodes
3. No manual target addition/removal in D10Q.

## Search structure
Every target gets:
- a COVID-19/SARS-CoV-2 PubMed search
- a sepsis PubMed search

Primary search uses an exact quoted Title/Abstract target.
Fallback uses an unquoted Title/Abstract target only if the primary count is zero.
No gene-alias expansion.

## PubMed reproducibility
database=pubmed
sort=relevance
retmax=50
datetype=pdat
mindate=1900/01/01
maxdate=2026/09/07
request rate <=2 requests/second
tool=GSE243219_D10Q

## D10Q boundary
Search/retrieval/provenance only. No biological narrative, no cherry-picking,
no module/hub/enrichment changes, and contradictory literature must be retained.
