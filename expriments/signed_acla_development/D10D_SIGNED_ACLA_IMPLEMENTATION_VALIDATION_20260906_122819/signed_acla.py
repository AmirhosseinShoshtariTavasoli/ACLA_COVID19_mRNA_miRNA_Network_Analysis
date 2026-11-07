#!/usr/bin/env python3
"""
Signed A-CLA (S-A-CLA) — D10D prospective implementation.

Implements the D10C-frozen design only.
This module contains no GSE243219-specific parameter values and no biological
interpretation logic.

The implementation operates component-wise on an undirected signed graph.
Regulatory evidence is a binary local-confidence modifier only:
    q_ij = 1 + lambda_R * r_ij
It never duplicates structural edges and never changes signed association weights.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, MutableMapping, Optional, Sequence, Tuple
import hashlib
import json
import math

import numpy as np
import pandas as pd


@dataclass(frozen=True)
class Edge:
    u: int
    v: int
    weight: float
    regulatory: bool = False


@dataclass
class ComponentGraph:
    nodes: List[int]
    edges: List[Edge]
    adjacency: Dict[int, List[Tuple[int, float, bool]]]
    pos_strength: Dict[int, float]
    neg_strength: Dict[int, float]
    two_m_pos: float
    two_m_neg: float
    absolute_mass: float


@dataclass(frozen=True)
class SACLAConfig:
    alpha_reward: float
    alpha_penalty: float
    gamma: float
    lambda_regulatory: float
    max_iterations: int
    objective_tolerance: float
    node_change_tolerance: float
    probability_change_tolerance: float
    patience: int

    def validate(self) -> None:
        if not (0.0 < self.alpha_reward <= 1.0):
            raise ValueError("alpha_reward must be in (0,1]")
        if not (0.0 < self.alpha_penalty <= 1.0):
            raise ValueError("alpha_penalty must be in (0,1]")
        if not (0.0 <= self.gamma <= 1.0):
            raise ValueError("gamma must be in [0,1]")
        if not (0.0 <= self.lambda_regulatory <= 1.0):
            raise ValueError("lambda_regulatory must be in [0,1]")
        if self.max_iterations < 1:
            raise ValueError("max_iterations must be >=1")
        if self.objective_tolerance < 0:
            raise ValueError("objective_tolerance must be >=0")
        if not (0.0 <= self.node_change_tolerance <= 1.0):
            raise ValueError("node_change_tolerance must be in [0,1]")
        if not (0.0 <= self.probability_change_tolerance <= 1.0):
            raise ValueError("probability_change_tolerance must be in [0,1]")
        if self.patience < 1:
            raise ValueError("patience must be >=1")


@dataclass
class SeedResult:
    seed: int
    converged: bool
    convergence_reason: str
    labels: Dict[int, int]
    objective: float
    history: pd.DataFrame


def _sha256_file(path: Path, chunk: int = 8 * 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(chunk), b""):
            h.update(block)
    return h.hexdigest()


def _resolve_column(df: pd.DataFrame, candidates: Sequence[str], role: str) -> str:
    normalized = {str(c).strip().lower(): c for c in df.columns}
    for name in candidates:
        if name.lower() in normalized:
            return normalized[name.lower()]
    raise ValueError(f"Required {role} column not found. Available={list(df.columns)}")


def _canonical_pair(a: str, b: str) -> Tuple[str, str]:
    return (a, b) if a <= b else (b, a)


def load_frozen_d9_bundle(bundle_dir: Path) -> Tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """
    Read the D9 A-CLA compatibility bundle without mutation.

    Returns normalized:
      nodes: node_index:int, node_id:str
      edges: source_index:int, target_index:int, association_score:float
      regulatory: source_index:int, target_index:int
    """
    bundle_dir = Path(bundle_dir)
    node_path = bundle_dir / "node_index.csv"
    edge_path = bundle_dir / "structural_edge_list.csv"
    reg_path = bundle_dir / "regulatory_semantic_edge_list.csv"
    schema_path = bundle_dir / "input_schema.json"

    for p in (node_path, edge_path, reg_path, schema_path):
        if not p.is_file():
            raise FileNotFoundError(f"Missing D9 bundle file: {p}")

    # Parse schema to ensure it is valid JSON; implementation does not reinterpret it.
    json.loads(schema_path.read_text(encoding="utf-8-sig", errors="strict"))

    nraw = pd.read_csv(node_path, dtype=str, keep_default_na=False)
    eraw = pd.read_csv(edge_path, dtype=str, keep_default_na=False)
    rraw = pd.read_csv(reg_path, dtype=str, keep_default_na=False)

    n_id = _resolve_column(nraw, ["node_id", "node", "id"], "node id")
    try:
        n_idx = _resolve_column(nraw, ["node_index", "node_idx", "index", "idx"], "node index")
        idx = pd.to_numeric(nraw[n_idx], errors="raise").astype(int)
    except ValueError:
        idx = pd.Series(np.arange(len(nraw), dtype=int), index=nraw.index)

    nodes = pd.DataFrame({"node_index": idx, "node_id": nraw[n_id].astype(str)})
    if nodes["node_index"].duplicated().any() or nodes["node_id"].duplicated().any():
        raise ValueError("Duplicate node_index or node_id in D9 bundle")

    node_to_idx = dict(zip(nodes["node_id"], nodes["node_index"]))

    es = _resolve_column(eraw, ["source", "source_id", "u", "node1"], "edge source")
    et = _resolve_column(eraw, ["target", "target_id", "v", "node2"], "edge target")
    ew = _resolve_column(
        eraw,
        ["association_score", "weight", "signed_weight", "rho", "score"],
        "signed association weight",
    )

    def endpoint_to_index(series: pd.Series) -> pd.Series:
        vals = series.astype(str)
        if set(vals).issubset(set(node_to_idx)):
            return vals.map(node_to_idx).astype(int)
        num = pd.to_numeric(vals, errors="coerce")
        if num.notna().all() and set(num.astype(int)).issubset(set(nodes["node_index"])):
            return num.astype(int)
        missing = sorted(set(vals) - set(node_to_idx))[:10]
        raise ValueError(f"Unknown D9 edge endpoints; examples={missing}")

    edges = pd.DataFrame({
        "source_index": endpoint_to_index(eraw[es]),
        "target_index": endpoint_to_index(eraw[et]),
        "association_score": pd.to_numeric(eraw[ew], errors="raise").astype(float),
    })

    rs = _resolve_column(rraw, ["source", "source_id", "u", "node1"], "regulatory source")
    rt = _resolve_column(rraw, ["target", "target_id", "v", "node2"], "regulatory target")
    regulatory = pd.DataFrame({
        "source_index": endpoint_to_index(rraw[rs]),
        "target_index": endpoint_to_index(rraw[rt]),
    })

    return nodes, edges, regulatory


def validate_d9_contract(
    nodes: pd.DataFrame,
    edges: pd.DataFrame,
    regulatory: pd.DataFrame,
    expected_nodes: int = 4508,
    expected_edges: int = 11531,
    expected_regulatory: int = 1978,
) -> Dict[str, object]:
    """Validate D10C-frozen D9 invariants without running community detection."""
    if len(nodes) != expected_nodes:
        raise ValueError(f"Node count mismatch: {len(nodes)} != {expected_nodes}")
    if len(edges) != expected_edges:
        raise ValueError(f"Edge count mismatch: {len(edges)} != {expected_edges}")
    if len(regulatory) != expected_regulatory:
        raise ValueError(f"Regulatory count mismatch: {len(regulatory)} != {expected_regulatory}")
    if nodes["node_index"].duplicated().any():
        raise ValueError("Duplicate node indices")
    if (edges["source_index"] == edges["target_index"]).any():
        raise ValueError("Self loops are prohibited")
    if not np.isfinite(edges["association_score"].to_numpy(float)).all():
        raise ValueError("Non-finite signed weights")
    if (edges["association_score"] == 0).any():
        raise ValueError("Zero structural weights are not expected in frozen D9")
    if not (edges["association_score"] < 0).any():
        raise ValueError("Frozen D9 must contain negative weights")

    node_set = set(nodes["node_index"].astype(int))
    endpoints = set(edges["source_index"].astype(int)) | set(edges["target_index"].astype(int))
    if not endpoints.issubset(node_set):
        raise ValueError("Unknown structural edge endpoint")

    edge_pairs = {
        tuple(sorted((int(u), int(v))))
        for u, v in zip(edges["source_index"], edges["target_index"])
    }
    if len(edge_pairs) != len(edges):
        raise ValueError("Duplicate structural pair")

    reg_pairs = {
        tuple(sorted((int(u), int(v))))
        for u, v in zip(regulatory["source_index"], regulatory["target_index"])
    }
    if len(reg_pairs) != len(regulatory):
        raise ValueError("Duplicate regulatory pair")
    if not reg_pairs.issubset(edge_pairs):
        raise ValueError("Regulatory pair not present in structural edge universe")

    # Component check.
    adj = {int(n): [] for n in node_set}
    for u, v in edge_pairs:
        adj[u].append(v)
        adj[v].append(u)
    unseen = set(adj)
    comp_sizes = []
    while unseen:
        start = min(unseen)
        stack = [start]
        unseen.remove(start)
        count = 0
        while stack:
            x = stack.pop()
            count += 1
            for y in adj[x]:
                if y in unseen:
                    unseen.remove(y)
                    stack.append(y)
        comp_sizes.append(count)
    comp_sizes.sort(reverse=True)

    isolates = sum(1 for n in node_set if not adj[n])
    return {
        "nodes": len(nodes),
        "edges": len(edges),
        "regulatory_edges": len(regulatory),
        "negative_edges": int((edges["association_score"] < 0).sum()),
        "positive_edges": int((edges["association_score"] > 0).sum()),
        "weight_min": float(edges["association_score"].min()),
        "weight_max": float(edges["association_score"].max()),
        "components": len(comp_sizes),
        "component_sizes": comp_sizes,
        "isolates": isolates,
        "regulatory_edge_duplication": 0,
    }


def build_signed_components(
    nodes: pd.DataFrame,
    edges: pd.DataFrame,
    regulatory: pd.DataFrame,
) -> List[ComponentGraph]:
    """Build all connected components while retaining every signed structural edge."""
    node_set = set(nodes["node_index"].astype(int))
    reg_pairs = {
        tuple(sorted((int(u), int(v))))
        for u, v in zip(regulatory["source_index"], regulatory["target_index"])
    }

    raw_adj: Dict[int, List[Tuple[int, float, bool]]] = {n: [] for n in node_set}
    edge_objs: List[Edge] = []
    for row in edges.itertuples(index=False):
        u = int(row.source_index)
        v = int(row.target_index)
        w = float(row.association_score)
        r = tuple(sorted((u, v))) in reg_pairs
        edge = Edge(u, v, w, r)
        edge_objs.append(edge)
        raw_adj[u].append((v, w, r))
        raw_adj[v].append((u, w, r))

    unseen = set(node_set)
    components_nodes: List[List[int]] = []
    while unseen:
        start = min(unseen)
        stack = [start]
        unseen.remove(start)
        comp = []
        while stack:
            x = stack.pop()
            comp.append(x)
            for y, _, _ in raw_adj[x]:
                if y in unseen:
                    unseen.remove(y)
                    stack.append(y)
        components_nodes.append(sorted(comp))

    components_nodes.sort(key=lambda xs: (-len(xs), xs[0]))

    result = []
    for comp_nodes in components_nodes:
        cset = set(comp_nodes)
        comp_edges = [e for e in edge_objs if e.u in cset]
        adjacency = {n: list(raw_adj[n]) for n in comp_nodes}
        pos = {n: 0.0 for n in comp_nodes}
        neg = {n: 0.0 for n in comp_nodes}
        for e in comp_edges:
            if e.weight > 0:
                pos[e.u] += e.weight
                pos[e.v] += e.weight
            else:
                a = abs(e.weight)
                neg[e.u] += a
                neg[e.v] += a
        two_m_pos = float(sum(pos.values()))
        two_m_neg = float(sum(neg.values()))
        result.append(
            ComponentGraph(
                nodes=comp_nodes,
                edges=comp_edges,
                adjacency=adjacency,
                pos_strength=pos,
                neg_strength=neg,
                two_m_pos=two_m_pos,
                two_m_neg=two_m_neg,
                absolute_mass=two_m_pos + two_m_neg,
            )
        )
    return result


def canonicalize_labels(labels: Mapping[int, int]) -> Dict[int, int]:
    members: Dict[int, List[int]] = {}
    for n, c in labels.items():
        members.setdefault(int(c), []).append(int(n))
    cmap = {c: min(ns) for c, ns in members.items()}
    return {int(n): int(cmap[int(c)]) for n, c in labels.items()}


def signed_local_score(
    component: ComponentGraph,
    labels: Mapping[int, int],
    node: int,
    candidate_label: Optional[int],
    lambda_regulatory: float,
) -> float:
    """
    D10C local signed satisfaction score L_i(c) in [-1,1].

    candidate_label=None denotes a new singleton community for node.
    """
    if not (0.0 <= lambda_regulatory <= 1.0):
        raise ValueError("lambda_regulatory must be in [0,1]")

    num = 0.0
    den = 0.0
    for nbr, w, regulatory in component.adjacency[node]:
        q = 1.0 + lambda_regulatory * (1.0 if regulatory else 0.0)
        aw = abs(w)
        den += q * aw
        same = False if candidate_label is None else (labels[nbr] == candidate_label)
        if w > 0:
            num += q * aw * (1.0 if same else -1.0)
        else:
            num += q * aw * (-1.0 if same else 1.0)
    if den == 0.0:
        return 0.0
    value = num / den
    # Protect only against machine roundoff.
    if value < -1.0 and value > -1.0 - 1e-12:
        value = -1.0
    if value > 1.0 and value < 1.0 + 1e-12:
        value = 1.0
    if not (-1.0 <= value <= 1.0):
        raise FloatingPointError(f"Local score outside [-1,1]: {value}")
    return float(value)


def signed_component_objective(
    component: ComponentGraph,
    labels: Mapping[int, int],
) -> float:
    """
    Gómez-style signed modularity for one component.

    Positive and negative observed/null terms are handled separately.
    """
    denom = component.absolute_mass
    if denom <= 0:
        raise ValueError("Component has zero absolute signed mass")

    comm_pos: Dict[int, float] = {}
    comm_neg: Dict[int, float] = {}
    for n in component.nodes:
        c = labels[n]
        comm_pos[c] = comm_pos.get(c, 0.0) + component.pos_strength[n]
        comm_neg[c] = comm_neg.get(c, 0.0) + component.neg_strength[n]

    observed = 0.0
    for e in component.edges:
        if labels[e.u] == labels[e.v]:
            observed += 2.0 * e.weight  # positive adds, negative subtracts

    null_term = 0.0
    communities = set(comm_pos) | set(comm_neg)
    for c in communities:
        if component.two_m_pos > 0:
            sp = comm_pos.get(c, 0.0)
            null_term -= (sp * sp) / component.two_m_pos
        if component.two_m_neg > 0:
            sn = comm_neg.get(c, 0.0)
            null_term += (sn * sn) / component.two_m_neg

    q = (observed + null_term) / denom
    if not math.isfinite(q):
        raise FloatingPointError("Non-finite signed objective")
    return float(q)


def component_community_strengths(
    component: ComponentGraph,
    labels: Mapping[int, int],
) -> Tuple[Dict[int, float], Dict[int, float]]:
    pos: Dict[int, float] = {}
    neg: Dict[int, float] = {}
    for n in component.nodes:
        c = labels[n]
        pos[c] = pos.get(c, 0.0) + component.pos_strength[n]
        neg[c] = neg.get(c, 0.0) + component.neg_strength[n]
    return pos, neg


def delta_signed_objective_move(
    component: ComponentGraph,
    labels: Mapping[int, int],
    node: int,
    candidate_label: Optional[int],
    comm_pos_strength: Mapping[int, float],
    comm_neg_strength: Mapping[int, float],
) -> float:
    """
    Exact O(degree(node)) change in component signed objective if node moves.

    candidate_label=None denotes a new singleton community.
    """
    old = labels[node]
    if candidate_label is not None and candidate_label == old:
        return 0.0

    # Observed signed within-community term.
    pos_to_old = pos_to_new = 0.0
    neg_to_old = neg_to_new = 0.0
    for nbr, w, _ in component.adjacency[node]:
        c = labels[nbr]
        if w > 0:
            if c == old:
                pos_to_old += w
            if candidate_label is not None and c == candidate_label:
                pos_to_new += w
        else:
            a = abs(w)
            if c == old:
                neg_to_old += a
            if candidate_label is not None and c == candidate_label:
                neg_to_new += a

    delta_observed = 2.0 * (
        (pos_to_new - pos_to_old)
        - (neg_to_new - neg_to_old)
    )

    sp_i = component.pos_strength[node]
    sn_i = component.neg_strength[node]
    sp_old = comm_pos_strength.get(old, 0.0)
    sn_old = comm_neg_strength.get(old, 0.0)
    new_key = candidate_label
    sp_new = 0.0 if new_key is None else comm_pos_strength.get(new_key, 0.0)
    sn_new = 0.0 if new_key is None else comm_neg_strength.get(new_key, 0.0)

    delta_null = 0.0
    if component.two_m_pos > 0:
        before = -(sp_old * sp_old + sp_new * sp_new) / component.two_m_pos
        after = -(
            (sp_old - sp_i) ** 2 + (sp_new + sp_i) ** 2
        ) / component.two_m_pos
        delta_null += after - before
    if component.two_m_neg > 0:
        before = (sn_old * sn_old + sn_new * sn_new) / component.two_m_neg
        after = (
            (sn_old - sn_i) ** 2 + (sn_new + sn_i) ** 2
        ) / component.two_m_neg
        delta_null += after - before

    return float((delta_observed + delta_null) / component.absolute_mass)


def apply_strength_move(
    component: ComponentGraph,
    node: int,
    old_label: int,
    new_label: int,
    comm_pos_strength: MutableMapping[int, float],
    comm_neg_strength: MutableMapping[int, float],
) -> None:
    sp = component.pos_strength[node]
    sn = component.neg_strength[node]
    comm_pos_strength[old_label] = comm_pos_strength.get(old_label, 0.0) - sp
    comm_neg_strength[old_label] = comm_neg_strength.get(old_label, 0.0) - sn
    comm_pos_strength[new_label] = comm_pos_strength.get(new_label, 0.0) + sp
    comm_neg_strength[new_label] = comm_neg_strength.get(new_label, 0.0) + sn


def candidate_communities(
    component: ComponentGraph,
    labels: Mapping[int, int],
    node: int,
) -> List[Optional[int]]:
    """
    Current community + neighbor communities + singleton(None).
    Current label is first only for readability; scoring/tie-breaking is explicit.
    """
    current = labels[node]
    neigh = sorted({labels[nbr] for nbr, _, _ in component.adjacency[node]})
    result: List[Optional[int]] = [current]
    result.extend(c for c in neigh if c != current)
    result.append(None)
    return result


def candidate_scores(
    component: ComponentGraph,
    labels: Mapping[int, int],
    node: int,
    lambda_regulatory: float,
    gamma: float,
    comm_pos_strength: Mapping[int, float],
    comm_neg_strength: Mapping[int, float],
) -> Dict[Optional[int], Tuple[float, float, float]]:
    """Return candidate -> (utility U, local L, delta signed Q)."""
    cands = candidate_communities(component, labels, node)
    raw_delta = {
        c: delta_signed_objective_move(
            component, labels, node, c, comm_pos_strength, comm_neg_strength
        )
        for c in cands
    }
    scale = max(abs(x) for x in raw_delta.values()) if raw_delta else 0.0
    scores = {}
    for c in cands:
        L = signed_local_score(component, labels, node, c, lambda_regulatory)
        G = 0.0 if scale == 0.0 else raw_delta[c] / scale
        U = (1.0 - gamma) * L + gamma * G
        scores[c] = (float(U), float(L), float(raw_delta[c]))
    return scores


def _candidate_tiebreak_key(
    item: Tuple[Optional[int], Tuple[float, float, float]],
    node: int,
) -> Tuple[float, float, float, int]:
    c, (u, l, dq) = item
    canonical = node if c is None else int(c)
    # max() is used; negative canonical gives preference to smallest label.
    return (u, l, dq, -canonical)


def candidate_best_alternative(
    component: ComponentGraph,
    labels: Mapping[int, int],
    node: int,
    lambda_regulatory: float,
    gamma: float,
    comm_pos_strength: Mapping[int, float],
    comm_neg_strength: Mapping[int, float],
) -> Tuple[Optional[int], Tuple[float, float, float], Tuple[float, float, float]]:
    scores = candidate_scores(
        component, labels, node, lambda_regulatory, gamma,
        comm_pos_strength, comm_neg_strength,
    )
    current = labels[node]
    current_score = scores[current]
    alternatives = [(c, s) for c, s in scores.items() if c != current]
    if not alternatives:
        return current, current_score, current_score
    best_c, best_s = max(alternatives, key=lambda x: _candidate_tiebreak_key(x, node))
    return best_c, best_s, current_score


def learning_automaton_update(
    p_move: float,
    chosen_action: str,
    environment_response: float,
    alpha_reward: float,
    alpha_penalty: float,
) -> float:
    """
    Apply D10C binary linear reward/penalty update.

    environment_response is e_i in [-2,2].
    """
    if not (0.0 <= p_move <= 1.0):
        raise ValueError("p_move outside [0,1]")
    if chosen_action not in {"MOVE", "STAY"}:
        raise ValueError("chosen_action must be MOVE or STAY")
    mu = min(1.0, abs(float(environment_response)) / 2.0)
    if environment_response == 0.0 or mu == 0.0:
        return float(p_move)

    reward = environment_response > 0.0
    if chosen_action == "MOVE":
        p_chosen = p_move
        if reward:
            p_chosen = p_chosen + alpha_reward * mu * (1.0 - p_chosen)
        else:
            p_chosen = p_chosen * (1.0 - alpha_penalty * mu)
        new_p_move = p_chosen
    else:
        p_stay = 1.0 - p_move
        if reward:
            p_stay = p_stay + alpha_reward * mu * (1.0 - p_stay)
        else:
            p_stay = p_stay * (1.0 - alpha_penalty * mu)
        new_p_move = 1.0 - p_stay

    if new_p_move < 0.0 and new_p_move > -1e-12:
        new_p_move = 0.0
    if new_p_move > 1.0 and new_p_move < 1.0 + 1e-12:
        new_p_move = 1.0
    if not (0.0 <= new_p_move <= 1.0):
        raise FloatingPointError(f"Probability outside [0,1]: {new_p_move}")
    return float(new_p_move)


def evaluate_convergence(
    objective_delta: float,
    changed_fraction: float,
    probability_delta: float,
    config: SACLAConfig,
) -> bool:
    return (
        abs(objective_delta) <= config.objective_tolerance
        and changed_fraction <= config.node_change_tolerance
        and probability_delta <= config.probability_change_tolerance
    )


def run_one_component(
    component: ComponentGraph,
    config: SACLAConfig,
    seed: int,
) -> SeedResult:
    """
    Execute S-A-CLA on one supplied component.

    D10D validates this only on tiny synthetic unit graphs.
    It is not called on GSE243219 until a later authorized phase.
    """
    config.validate()
    rng = np.random.default_rng(np.uint64(seed))
    labels = {n: n for n in component.nodes}
    p_move = {n: 0.5 for n in component.nodes}
    next_temp_label = max(component.nodes) + 1 if component.nodes else 0

    prev_q = signed_component_objective(component, labels)
    stable_count = 0
    history_rows = []

    for iteration in range(1, config.max_iterations + 1):
        before_labels = labels.copy()
        before_p = p_move.copy()
        comm_pos, comm_neg = component_community_strengths(component, labels)

        order = np.array(component.nodes, dtype=int)
        rng.shuffle(order)

        for node_np in order:
            node = int(node_np)
            best_c, best_s, current_s = candidate_best_alternative(
                component, labels, node,
                config.lambda_regulatory, config.gamma,
                comm_pos, comm_neg,
            )
            u_alt = best_s[0]
            u_current = current_s[0]
            d = u_alt - u_current

            do_move = bool(rng.random() < p_move[node])
            chosen = "MOVE" if do_move else "STAY"

            if do_move:
                old = labels[node]
                if best_c is None:
                    new = next_temp_label
                    next_temp_label += 1
                else:
                    new = int(best_c)
                if new != old:
                    labels[node] = new
                    apply_strength_move(
                        component, node, old, new, comm_pos, comm_neg
                    )

            e = d if chosen == "MOVE" else -d
            p_move[node] = learning_automaton_update(
                p_move[node], chosen, e,
                config.alpha_reward, config.alpha_penalty,
            )

        labels = canonicalize_labels(labels)
        q = signed_component_objective(component, labels)
        changed = sum(before_labels[n] != labels[n] for n in component.nodes)
        changed_fraction = changed / max(1, len(component.nodes))
        p_delta = max(abs(p_move[n] - before_p[n]) for n in component.nodes)
        q_delta = q - prev_q

        converged_now = evaluate_convergence(
            q_delta, changed_fraction, p_delta, config
        )
        stable_count = stable_count + 1 if converged_now else 0

        history_rows.append({
            "seed": int(seed),
            "iteration": iteration,
            "signed_objective": q,
            "objective_change": q_delta,
            "changed_nodes": changed,
            "changed_fraction": changed_fraction,
            "max_probability_change": p_delta,
            "community_count": len(set(labels.values())),
            "probability_min": min(p_move.values()),
            "probability_max": max(p_move.values()),
            "joint_convergence_condition": bool(converged_now),
            "patience_count": stable_count,
        })

        prev_q = q
        if stable_count >= config.patience:
            return SeedResult(
                seed=int(seed),
                converged=True,
                convergence_reason="JOINT_OBJECTIVE_SWITCHING_PROBABILITY_PATIENCE",
                labels=canonicalize_labels(labels),
                objective=float(q),
                history=pd.DataFrame(history_rows),
            )

    return SeedResult(
        seed=int(seed),
        converged=False,
        convergence_reason="MAX_ITERATIONS_REACHED_WITHOUT_JOINT_CONVERGENCE",
        labels=canonicalize_labels(labels),
        objective=float(prev_q),
        history=pd.DataFrame(history_rows),
    )


def adjusted_rand_index_from_labels(
    a: Mapping[int, int],
    b: Mapping[int, int],
) -> float:
    """Dependency-free ARI used only for partition-medoid consensus selection."""
    nodes = sorted(set(a) & set(b))
    if len(nodes) != len(a) or len(nodes) != len(b):
        raise ValueError("Partitions must cover identical node sets")
    n = len(nodes)
    if n < 2:
        return 1.0

    table: Dict[Tuple[int, int], int] = {}
    ca: Dict[int, int] = {}
    cb: Dict[int, int] = {}
    for node in nodes:
        x, y = a[node], b[node]
        table[(x, y)] = table.get((x, y), 0) + 1
        ca[x] = ca.get(x, 0) + 1
        cb[y] = cb.get(y, 0) + 1

    comb2 = lambda x: x * (x - 1) / 2.0
    sum_ij = sum(comb2(v) for v in table.values())
    sum_a = sum(comb2(v) for v in ca.values())
    sum_b = sum(comb2(v) for v in cb.values())
    total = comb2(n)
    if total == 0:
        return 1.0
    expected = sum_a * sum_b / total
    max_index = 0.5 * (sum_a + sum_b)
    denom = max_index - expected
    if denom == 0:
        return 1.0
    return float((sum_ij - expected) / denom)


def select_partition_medoid(results: Sequence[SeedResult]) -> SeedResult:
    """Choose converged partition maximizing mean pairwise ARI; tie signed Q then seed."""
    good = [r for r in results if r.converged]
    if not good:
        raise ValueError("No converged seed available for consensus")
    if len(good) == 1:
        return good[0]

    means = {}
    for i, r in enumerate(good):
        vals = []
        for j, s in enumerate(good):
            if i == j:
                continue
            vals.append(adjusted_rand_index_from_labels(r.labels, s.labels))
        means[i] = float(np.mean(vals))

    best_idx = max(
        range(len(good)),
        key=lambda i: (means[i], good[i].objective, -good[i].seed),
    )
    return good[best_idx]


def deterministic_seed(k: int) -> int:
    if k < 1:
        raise ValueError("k must start at 1")
    digest = hashlib.sha256(f"SACLA-v1-seed-{k}".encode("utf-8")).digest()
    return int.from_bytes(digest[:4], byteorder="big", signed=False)


def write_iteration_history(result: SeedResult, path: Path) -> None:
    path = Path(path)
    result.history.to_csv(path, index=False)
