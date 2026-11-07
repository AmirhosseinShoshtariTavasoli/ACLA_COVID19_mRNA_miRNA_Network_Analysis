# D10H Original A-CLA — Code-Authoritative Method Specification

## Execution authority

Publication-provenanced recovered final modularity source:

`legacy/submission_code/Modularity/A-CLA.02.01.Modularity.py`

SHA256:

`ee3c3b735ba6593d5a6af155e599403e697f498b290dc75a39ff0e3ab90b07de`

The source code is authoritative for later execution. The article pseudocode is used
for reconciliation only and is not used to silently rewrite the recovered code.

## Recovered code behavior

- Required input: square labeled adjacency matrix in Excel or CSV/TXT format.
- Default topology conversion: `(df > 0).astype(int)`.
- Initialization: Louvain if available, otherwise iterative majority-label fallback.
- Candidate labels: dynamically recomputed current neighbor labels plus current label.
- No explicit per-node action probability vector P_i.
- Local score: neighbor-label count divided by maximum neighbor-label count.
- Global score: `max(0, Q_if_candidate_move - best_Q_so_far)`, normalized.
- Fused score: 0.65 local + 0.35 global.
- Exploration alpha: starts at 0.20, multiplied by 0.95 each outer iteration, floor 0.01.
- Action: random choice among top two fused candidates with probability alpha;
  otherwise fused-score argmax.
- Community update: immediate asynchronous hard-label update.
- Modularity: unweighted (`weight=None`).
- Stop: no improvement for 10 iterations, or no label change, or 200 iterations.
- Final membership: `best_labels`, the best-modularity hard partition.

## D10H representation

D9 remains the frozen signed scientific association network.

The D10H optimization projection contains all 4,508 D9 nodes and all 11,531 frozen
structural associations. Every frozen pair is represented as binary adjacency 1
irrespective of original sign.

This is not `negative weight -> abs(weight)`.

It is:

`stable association exists -> topology edge exists`.

The original signed coefficient and regulatory evidence remain unchanged in
`D10H_ACLA_EDGE_METADATA.csv`.

Original A-CLA therefore addresses topology-only dense association groups. It does not
optimize positive-within / negative-between signed organization.

Regulatory evidence is not used during A-CLA optimization and remains available for
post-community characterization.
