#!/usr/bin/env python3
# A-CLA for Modularity — Excel adjacency input
# --------------------------------------------
# Usage: set FILE_PATH to your Excel (e.g., 'adjacency_matrix_Dolphin_output.xlsx')
# Output: number of communities, modularity, execution time
#
# Notes:
# - Reads a square adjacency matrix with node labels in both the first row and first column.
# - By default, edges are binarized (>0) before running (more stable across datasets).
# - Produces a *hard* partition (non-overlapping) suitable for modularity.
# - Initialization uses Louvain to get a sensible starting partition.
# - Global signal = modularity gain from hypothetical label moves (approx; recomputed on the fly).
# - Early stopping when modularity stops improving.

import time
import random
from pathlib import Path
from collections import defaultdict, Counter

import pandas as pd
import networkx as nx
from networkx.algorithms.community.quality import modularity

try:
    from community import community_louvain
    HAS_LOUVAIN = True
except Exception:
    HAS_LOUVAIN = False

# -------------- SETTINGS (edit these) --------------
FILE_PATH = "adjacency_matrix_DanioRerio_output.xlsx"   # <-- put your file here
BINARIZE = True          # True: treat >0 as unweighted edges; False: keep weights
ITERATIONS = 200         # max outer iterations
ALPHA0 = 0.20            # initial exploration probability
ALPHA_MIN = 0.01         # floor on exploration
GLOBAL_WEIGHT = 0.35     # weight of global (modularity) signal in [0,1]
PATIENCE = 10            # early-stop if no modularity improvement for this many iters
SEED = 42                # RNG seed for reproducibility
# ---------------------------------------------------

random.seed(SEED)


def load_adjacency(path: Path) -> pd.DataFrame:
    suff = path.suffix.lower()
    if suff in (".xlsx", ".xls"):
        df = pd.read_excel(path, index_col=0)
    elif suff in (".csv", ".txt"):
        df = pd.read_csv(path, index_col=0)
    else:
        raise ValueError(f"Unsupported file type: {suff}")
    if df.shape[0] != df.shape[1]:
        raise ValueError(f"Adjacency must be square; got {df.shape}")
    # Align rows/cols if the same set but different order
    if not df.index.equals(df.columns):
        if set(map(str, df.index)) == set(map(str, df.columns)):
            df = df.loc[df.index, df.index]
        else:
            raise ValueError("Row and column labels must match.")
    return df


def make_graph(df: pd.DataFrame, binarize: bool) -> nx.Graph:
    if binarize:
        df2 = (df > 0).astype(int)
        G = nx.from_pandas_adjacency(df2)
    else:
        # Weighted graph version (optional)
        G = nx.from_pandas_adjacency(df.astype(float))
    G.remove_edges_from(nx.selfloop_edges(G))
    return G


def partition_to_communities(labels: dict) -> list[set]:
    comms = defaultdict(set)
    for n, lab in labels.items():
        comms[lab].add(n)
    # drop empty labels and return as list of sets
    return [c for c in comms.values() if len(c) > 0]


def communities_to_partition(comms: list[set]) -> dict:
    labels = {}
    for cid, cset in enumerate(comms):
        for n in cset:
            labels[n] = cid
    return labels


def current_modularity(G: nx.Graph, labels: dict) -> float:
    comms = partition_to_communities(labels)
    if len(comms) <= 1:
        return 0.0
    # for weighted modularity, set weight="weight"
    return modularity(G, comms, weight=None)


def louvain_init(G: nx.Graph) -> dict:
    if HAS_LOUVAIN:
        return community_louvain.best_partition(G)
    # fallback: simple label propagation init
    labels = {n: i for i, n in enumerate(G.nodes())}
    changed = True
    while changed:
        changed = False
        for n in G.nodes():
            neigh_labels = [labels[v] for v in G.neighbors(n)]
            if not neigh_labels:
                continue
            maj = Counter(neigh_labels).most_common(1)[0][0]
            if labels[n] != maj:
                labels[n] = maj
                changed = True
    # relabel to 0..K-1
    relabel = {}
    for i, lab in enumerate(sorted(set(labels.values()))):
        relabel[lab] = i
    return {n: relabel[lab] for n, lab in labels.items()}


def try_move_label(G: nx.Graph, labels: dict, node, candidate_label) -> float:
    """
    Return modularity if 'node' were assigned 'candidate_label' (others unchanged).
    This is a simple (re)compute; fine for small/medium graphs.
    """
    old_label = labels[node]
    if old_label == candidate_label:
        return current_modularity(G, labels)
    labels[node] = candidate_label
    q_new = current_modularity(G, labels)
    labels[node] = old_label  # revert
    return q_new


def acla_modularity(G: nx.Graph,
                    iterations=ITERATIONS,
                    alpha0=ALPHA0,
                    alpha_min=ALPHA_MIN,
                    global_w=GLOBAL_WEIGHT,
                    patience=PATIENCE,
                    seed=SEED):
    random.seed(seed)
    nodes = list(G.nodes())

    # Initialize labels via Louvain or fallback
    labels = louvain_init(G)

    # Candidate label set = labels that appear among neighbors (plus current)
    def candidate_labels_for(n):
        neigh_labs = [labels[v] for v in G.neighbors(n)]
        labs = set(neigh_labs + [labels[n]])
        return list(labs)

    alpha = alpha0
    best_q = current_modularity(G, labels)
    best_labels = labels.copy()
    no_improve = 0

    for it in range(1, iterations + 1):
        changed = False

        # Shuffle node order to reduce bias
        order = nodes[:]
        random.shuffle(order)

        for n in order:
            cands = candidate_labels_for(n)
            if not cands:
                continue

            # Local signal: neighbor majority per candidate
            neigh_labs = [labels[v] for v in G.neighbors(n)]
            local_scores = {c: 0.0 for c in cands}
            if neigh_labs:
                counts = Counter(neigh_labs)
                # normalize by max count
                maxc = max(counts.values())
                for c in cands:
                    local_scores[c] = counts.get(c, 0) / maxc

            # Global signal: modularity gain if moved to candidate c
            # approximate baseline; could also compute current_modularity(G, labels)
            q_now = best_q
            global_scores = {}
            # Evaluate q if node moved to each candidate
            for c in cands:
                q_c = try_move_label(G, labels, n, c)
                # normalize relative to current best q
                global_scores[c] = max(0.0, q_c - q_now)

            # Normalize both signals to [0,1]
            if len(local_scores) > 0:
                lmax = max(local_scores.values()) or 1.0
            else:
                lmax = 1.0
            if len(global_scores) > 0:
                gmax = max(global_scores.values()) or 1.0
            else:
                gmax = 1.0

            fused = {}
            for c in cands:
                ls = local_scores.get(c, 0.0) / lmax
                gs = global_scores.get(c, 0.0) / gmax
                fused[c] = (1 - global_w) * ls + global_w * gs

            # Choose action: exploit best or explore
            if random.random() < alpha:
                # exploration among top-2 if available
                top2 = sorted(
                    fused.items(), key=lambda x: x[1], reverse=True)[:2]
                choice = random.choice(top2)[0] if top2 else labels[n]
            else:
                choice = max(fused, key=fused.get)

            if choice != labels[n]:
                labels[n] = choice
                changed = True

        # Evaluate modularity and adapt parameters
        q = current_modularity(G, labels)
        if q > best_q + 1e-6:
            best_q = q
            best_labels = labels.copy()
            no_improve = 0
        else:
            no_improve += 1

        # cool down exploration
        alpha = max(alpha_min, alpha * 0.95)

        # early stop if no improvement for 'patience' iters or no changes
        if no_improve >= patience or not changed:
            break

    # Final communities and modularity
    final_labels = best_labels
    comms = partition_to_communities(final_labels)
    final_q = modularity(G, comms, weight=None)
    return final_labels, comms, final_q


def main():
    path = Path(FILE_PATH)
    df = load_adjacency(path)
    G = make_graph(df, BINARIZE)

    t0 = time.time()
    labels, comms, q = acla_modularity(G)
    elapsed = time.time() - t0

    print(f"\n=== A-CLA (Modularity) on {path.name} ===")
    print(f"Communities: {len(comms)}")
    print(f"Modularity:  {q:.4f}")
    print(f"Time:        {elapsed:.3f} s")

    # (Optional) print small partitions
    if len(comms) <= 10:
        for i, c in enumerate(sorted(comms, key=len, reverse=True), 1):
            print(f"  C{i} (|V|={len(c)}): sample={list(sorted(c))[:10]}")


if __name__ == "__main__":
    main()
