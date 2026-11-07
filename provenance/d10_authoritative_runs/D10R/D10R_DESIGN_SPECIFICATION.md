# D10R — Literature Screening + Evidence Classification Design Freeze

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
