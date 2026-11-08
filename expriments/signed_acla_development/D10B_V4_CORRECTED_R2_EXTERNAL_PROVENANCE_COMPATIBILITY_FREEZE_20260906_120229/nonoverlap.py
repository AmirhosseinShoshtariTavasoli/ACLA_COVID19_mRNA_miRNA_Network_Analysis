"""Clean non-overlapping A-CLA reference implementation.

This module is derived from the recovered final manuscript modularity script
`A-CLA.02.01.Modularity.py`. The historical script is preserved verbatim under
`legacy/submission_code/Modularity/`.

Important: the recovered modularity script uses Louvain (or a label-propagation
fallback) as its initialization. This differs from the unbiased equal-probability
initialization described in the final manuscript pseudocode. The discrepancy is
preserved and documented rather than hidden.
"""

from __future__ import annotations

from collections import Counter, defaultdict
import random
from typing import Hashable

import networkx as nx
from networkx.algorithms.community.quality import modularity


def _partition_to_communities(labels: dict[Hashable, int]) -> list[set]:
    groups: dict[int, set] = defaultdict(set)
    for node, label in labels.items():
        groups[label].add(node)
    return [group for group in groups.values() if group]


def _current_modularity(graph: nx.Graph, labels: dict[Hashable, int]) -> float:
    communities = _partition_to_communities(labels)
    if len(communities) <= 1:
        return 0.0
    return modularity(graph, communities, weight=None)


def _louvain_init(graph: nx.Graph, seed: int) -> dict[Hashable, int]:
    try:
        from community import community_louvain  # type: ignore
        # Explicit random_state is added in the clean wrapper for repeatability.
        return community_louvain.best_partition(graph, random_state=seed)
    except Exception:
        # NetworkX Louvain is the preferred dependency-free fallback.
        try:
            comms = nx.algorithms.community.louvain_communities(graph, seed=seed)
            return {node: cid for cid, comm in enumerate(comms) for node in comm}
        except Exception:
            # Final fallback mirrors the majority-label strategy in the historical script.
            labels = {node: i for i, node in enumerate(graph.nodes())}
            changed = True
            while changed:
                changed = False
                for node in graph.nodes():
                    neigh_labels = [labels[v] for v in graph.neighbors(node)]
                    if not neigh_labels:
                        continue
                    majority = Counter(neigh_labels).most_common(1)[0][0]
                    if labels[node] != majority:
                        labels[node] = majority
                        changed = True
            remap = {lab: i for i, lab in enumerate(sorted(set(labels.values())))}
            return {node: remap[label] for node, label in labels.items()}


def _try_move_label(graph: nx.Graph, labels: dict, node, candidate_label) -> float:
    old = labels[node]
    if old == candidate_label:
        return _current_modularity(graph, labels)
    labels[node] = candidate_label
    score = _current_modularity(graph, labels)
    labels[node] = old
    return score


def detect_nonoverlapping(
    graph: nx.Graph,
    *,
    iterations: int = 200,
    alpha0: float = 0.20,
    alpha_min: float = 0.01,
    global_weight: float = 0.35,
    patience: int = 10,
    seed: int = 42,
) -> tuple[dict, list[set], float]:
    """Run the recovered modularity-oriented non-overlapping A-CLA variant.

    Returns `(node_to_label, communities, modularity)`.
    """
    rng = random.Random(seed)
    nodes = list(graph.nodes())
    labels = _louvain_init(graph, seed)

    def candidate_labels_for(node):
        neighbor_labels = [labels[v] for v in graph.neighbors(node)]
        return list(set(neighbor_labels + [labels[node]]))

    alpha = float(alpha0)
    best_q = _current_modularity(graph, labels)
    best_labels = labels.copy()
    no_improve = 0

    for _ in range(1, iterations + 1):
        changed = False
        order = nodes[:]
        rng.shuffle(order)

        for node in order:
            candidates = candidate_labels_for(node)
            if not candidates:
                continue

            neigh_labels = [labels[v] for v in graph.neighbors(node)]
            local_scores = {c: 0.0 for c in candidates}
            if neigh_labels:
                counts = Counter(neigh_labels)
                max_count = max(counts.values())
                for candidate in candidates:
                    local_scores[candidate] = counts.get(candidate, 0) / max_count

            q_now = best_q
            global_scores = {
                candidate: max(0.0, _try_move_label(graph, labels, node, candidate) - q_now)
                for candidate in candidates
            }

            local_max = max(local_scores.values()) if local_scores else 1.0
            global_max = max(global_scores.values()) if global_scores else 1.0
            local_max = local_max or 1.0
            global_max = global_max or 1.0

            fused = {
                candidate: (1.0 - global_weight) * (local_scores[candidate] / local_max)
                + global_weight * (global_scores[candidate] / global_max)
                for candidate in candidates
            }

            if rng.random() < alpha:
                top2 = sorted(fused.items(), key=lambda item: item[1], reverse=True)[:2]
                choice = rng.choice(top2)[0] if top2 else labels[node]
            else:
                choice = max(fused, key=fused.get)

            if choice != labels[node]:
                labels[node] = choice
                changed = True

        q = _current_modularity(graph, labels)
        if q > best_q + 1e-6:
            best_q = q
            best_labels = labels.copy()
            no_improve = 0
        else:
            no_improve += 1

        alpha = max(alpha_min, alpha * 0.95)
        if no_improve >= patience or not changed:
            break

    communities = _partition_to_communities(best_labels)
    final_q = modularity(graph, communities, weight=None) if len(communities) > 1 else 0.0
    return best_labels, communities, float(final_q)
