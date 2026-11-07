#!/usr/bin/env python3
from __future__ import annotations

import csv
import gzip
import hashlib
import json
import math
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_MRNA = 4467
EXPECTED_MIRNA = 41
EXPECTED_NODES = 4508
EXPECTED_ASSOC_EDGES = 11531
EXPECTED_REG_EDGES = 1978
EXPECTED_NONREG_EDGES = 9553
EXPECTED_R1 = 1935
EXPECTED_R2 = 6
EXPECTED_R3 = 37


def sha256_file(path: Path, chunk_size: int = 8 * 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            b = f.read(chunk_size)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def recertify_manifest(manifest_path: Path, expected_rows: int, label: str):
    if not manifest_path.is_file():
        raise RuntimeError(f"{label}_MANIFEST_MISSING={manifest_path}")
    rows = pd.read_csv(manifest_path, dtype=str, keep_default_na=False)
    if len(rows) != expected_rows:
        raise RuntimeError(
            f"{label}_MANIFEST_ROW_COUNT_CHANGED expected={expected_rows} observed={len(rows)}"
        )
    required = {"full_path", "size_bytes", "SHA256"}
    missing = required - set(rows.columns)
    if missing:
        raise RuntimeError(f"{label}_MANIFEST_COLUMNS_MISSING={sorted(missing)}")

    mismatches = []
    for _, r in rows.iterrows():
        p = Path(str(r["full_path"]))
        if not p.is_file():
            mismatches.append(f"MISSING:{p}")
            continue
        if p.stat().st_size != int(r["size_bytes"]):
            mismatches.append(f"SIZE:{p}")
            continue
        if sha256_file(p) != str(r["SHA256"]).lower():
            mismatches.append(f"SHA256:{p}")
    if mismatches:
        raise RuntimeError(f"{label}_HASH_MISMATCHES={len(mismatches)}|" + "||".join(mismatches[:20]))
    return rows


def finite_numeric(series: pd.Series) -> tuple[pd.Series, int]:
    vals = pd.to_numeric(series, errors="coerce")
    arr = vals.to_numpy(dtype=float)
    invalid = int((~np.isfinite(arr)).sum())
    return vals, invalid


class UnionFind:
    def __init__(self, nodes):
        self.parent = {n: n for n in nodes}
        self.size = {n: 1 for n in nodes}

    def find(self, x):
        p = self.parent[x]
        if p != x:
            self.parent[x] = self.find(p)
        return self.parent[x]

    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra == rb:
            return
        if self.size[ra] < self.size[rb]:
            ra, rb = rb, ra
        self.parent[rb] = ra
        self.size[ra] += self.size[rb]


def graph_stats(all_nodes: list[str], edges: pd.DataFrame, weight_col: str | None = None):
    uf = UnionFind(all_nodes)
    deg = Counter({n: 0 for n in all_nodes})

    for s, t in zip(edges["source"], edges["target"]):
        if s == t:
            continue
        uf.union(s, t)
        deg[s] += 1
        deg[t] += 1

    comps = defaultdict(int)
    for n in all_nodes:
        comps[uf.find(n)] += 1

    comp_sizes = sorted(comps.values(), reverse=True)
    largest = comp_sizes[0] if comp_sizes else 0
    degrees = np.array([deg[n] for n in all_nodes], dtype=float)

    out = {
        "NODES": len(all_nodes),
        "EDGES": len(edges),
        "CONNECTED_COMPONENTS": len(comp_sizes),
        "LARGEST_COMPONENT_NODES": int(largest),
        "LARGEST_COMPONENT_FRACTION": float(largest / len(all_nodes)) if all_nodes else 0.0,
        "ISOLATED_NODES": int((degrees == 0).sum()),
        "MIN_DEGREE": int(degrees.min()) if len(degrees) else 0,
        "MEDIAN_DEGREE": float(np.median(degrees)) if len(degrees) else 0.0,
        "MEAN_DEGREE": float(degrees.mean()) if len(degrees) else 0.0,
        "MAX_DEGREE": int(degrees.max()) if len(degrees) else 0,
    }

    if weight_col and weight_col in edges.columns and len(edges):
        w = pd.to_numeric(edges[weight_col], errors="coerce").to_numpy(dtype=float)
        out.update({
            "WEIGHT_MIN": float(np.nanmin(w)),
            "WEIGHT_MEDIAN": float(np.nanmedian(w)),
            "WEIGHT_MEAN": float(np.nanmean(w)),
            "WEIGHT_MAX": float(np.nanmax(w)),
        })
    else:
        out.update({
            "WEIGHT_MIN": np.nan,
            "WEIGHT_MEDIAN": np.nan,
            "WEIGHT_MEAN": np.nan,
            "WEIGHT_MAX": np.nan,
        })
    return out


def detect_acla_code(reusable_root: Path):
    candidates = []
    allowed_ext = {".py", ".ps1", ".R", ".r", ".ipynb", ".m", ".jl", ".txt", ".md"}
    for p in reusable_root.rglob("*"):
        if not p.is_file() or p.suffix not in allowed_ext:
            continue
        low_name = p.name.lower()
        try:
            size = p.stat().st_size
        except Exception:
            continue
        if size == 0 or size > 20_000_000:
            continue

        name_hit = ("acla" in low_name or "learning_automata" in low_name or "learningautomata" in low_name)
        text_hit = False
        text = ""
        if name_hit or p.suffix.lower() in {".py", ".ps1", ".r", ".m", ".jl", ".txt", ".md"}:
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
                text_low = text.lower()
                text_hit = (
                    "a-cla" in text_low
                    or "acla" in text_low
                    or "cellular learning automata" in text_low
                    or "learning automata" in text_low
                )
            except Exception:
                text = ""
        if not (name_hit or text_hit):
            continue

        tl = text.lower()
        indicators = []
        for token, label in [
            ("read_csv", "READ_CSV"),
            ("read_edgelist", "READ_EDGELIST"),
            ("networkx", "NETWORKX"),
            ("adjacency", "ADJACENCY"),
            ("np.load", "NP_LOAD"),
            ("loadtxt", "LOADTXT"),
            ("sparse", "SPARSE"),
            ("source", "SOURCE_COLUMN"),
            ("target", "TARGET_COLUMN"),
            ("weight", "WEIGHT_COLUMN"),
        ]:
            if token in tl:
                indicators.append(label)

        candidates.append({
            "file": str(p),
            "size_bytes": size,
            "SHA256": sha256_file(p),
            "name_hit": "YES" if name_hit else "NO",
            "content_hit": "YES" if text_hit else "NO",
            "schema_indicators": "|".join(indicators),
        })

    candidates.sort(key=lambda x: (x["name_hit"] != "YES", x["file"].lower()))
    return candidates


def composite_hash(candidates):
    h = hashlib.sha256()
    for r in sorted(candidates, key=lambda x: x["file"].lower()):
        h.update(r["file"].encode("utf-8"))
        h.update(b"\0")
        h.update(r["SHA256"].encode("ascii"))
        h.update(b"\n")
    return h.hexdigest()


def try_attach_de_metadata(de_root: Path, nodes: pd.DataFrame):
    """
    Conservative best-effort only.
    Attach node DE metadata only if one unambiguous exact-ID table per
    modality/contrast can be identified. Otherwise report NO and do not fail D9.
    """
    audit = []
    if not de_root.exists():
        return nodes, audit, False

    candidates = []
    patterns = [
        ("COV_vs_H", re.compile(r"cov[^a-z0-9]*vs[^a-z0-9]*h|cov.*healthy", re.I)),
        ("P_vs_H", re.compile(r"(^|[^a-z])p[^a-z0-9]*vs[^a-z0-9]*h|sepsis.*healthy", re.I)),
        ("COV_vs_P", re.compile(r"cov[^a-z0-9]*vs[^a-z0-9]*p|cov.*sepsis", re.I)),
    ]

    mRNA_ids = set(nodes.loc[nodes["node_type"].eq("MRNA"), "node_id"])
    miRNA_ids = set(nodes.loc[nodes["node_type"].eq("MIRNA"), "node_id"])

    for p in de_root.rglob("*"):
        if not p.is_file():
            continue
        low = p.name.lower()
        if not (low.endswith(".csv") or low.endswith(".csv.gz")):
            continue
        contrast = None
        path_text = str(p).replace("\\", "/")
        for label, rgx in patterns:
            if rgx.search(path_text):
                contrast = label
                break
        if contrast is None:
            continue
        try:
            head = pd.read_csv(p, nrows=100, dtype=str, keep_default_na=False)
        except Exception:
            continue
        cols = list(head.columns)
        ncols = {re.sub(r"[^a-z0-9]+", "", c.lower()): c for c in cols}

        id_col = None
        for key in ["mrnaid","mirnaid","featureid","genesymbol","symbol","gene","mirna"]:
            if key in ncols:
                id_col = ncols[key]
                break
        logfc_col = None
        for key in ["logfc","log2foldchange","log2fc"]:
            if key in ncols:
                logfc_col = ncols[key]
                break
        fdr_col = None
        for key in ["fdr","padj","adjpvalue","adjustedpvalue"]:
            if key in ncols:
                fdr_col = ncols[key]
                break
        pval_col = None
        for key in ["pvalue","pval","p"]:
            if key in ncols:
                pval_col = ncols[key]
                break

        if not id_col or not logfc_col or not fdr_col:
            continue

        values = set(head[id_col].astype(str))
        m_hits = len(values & mRNA_ids)
        mi_hits = len(values & miRNA_ids)
        modality = None
        if m_hits >= 3 and mi_hits == 0:
            modality = "MRNA"
        elif mi_hits >= 3 and m_hits == 0:
            modality = "MIRNA"
        else:
            continue

        candidates.append({
            "path": p,
            "contrast": contrast,
            "modality": modality,
            "id_col": id_col,
            "logfc_col": logfc_col,
            "fdr_col": fdr_col,
            "pval_col": pval_col,
        })

    attached_any = False
    out = nodes.copy()

    for modality in ["MRNA", "MIRNA"]:
        for contrast, _ in patterns:
            group = [c for c in candidates if c["modality"] == modality and c["contrast"] == contrast]
            if len(group) != 1:
                audit.append({
                    "modality": modality,
                    "contrast": contrast,
                    "status": "NOT_ATTACHED",
                    "candidate_count": len(group),
                    "source_file": "" if not group else "|".join(str(x["path"]) for x in group[:10]),
                    "reason": "requires_exactly_one_unambiguous_candidate",
                })
                continue

            c = group[0]
            try:
                df = pd.read_csv(c["path"], dtype=str, keep_default_na=False)
            except Exception as e:
                audit.append({
                    "modality": modality,
                    "contrast": contrast,
                    "status": "NOT_ATTACHED",
                    "candidate_count": 1,
                    "source_file": str(c["path"]),
                    "reason": f"read_failed:{e}",
                })
                continue

            use = [c["id_col"], c["logfc_col"], c["fdr_col"]]
            if c["pval_col"]:
                use.append(c["pval_col"])
            sub = df[use].copy()
            sub = sub.drop_duplicates(subset=[c["id_col"]], keep=False)
            prefix = contrast
            rename = {
                c["id_col"]: "node_id",
                c["logfc_col"]: f"{prefix}_logFC",
                c["fdr_col"]: f"{prefix}_FDR",
            }
            if c["pval_col"]:
                rename[c["pval_col"]] = f"{prefix}_PValue"
            sub = sub.rename(columns=rename)

            mask = out["node_type"].eq(modality)
            merged = out.loc[mask, ["node_id"]].merge(sub, on="node_id", how="left")
            for col in [x for x in merged.columns if x != "node_id"]:
                out.loc[mask, col] = merged[col].to_numpy()
            attached_any = True
            audit.append({
                "modality": modality,
                "contrast": contrast,
                "status": "ATTACHED",
                "candidate_count": 1,
                "source_file": str(c["path"]),
                "reason": "exact_ID_unambiguous_table",
            })

    return out, audit, attached_any


def main():
    if len(sys.argv) != 10:
        raise SystemExit(
            "usage: D9_BUILD.py "
            "<d8b_run> <d8b_manifest> <d8b_final_status> "
            "<d7c_manifest> <d7c_edges> <d8a3_manifest> <d8a3_gene_audit> "
            "<project_root> <outdir>"
        )

    d8b_run = Path(sys.argv[1])
    d8b_manifest = Path(sys.argv[2])
    d8b_status_path = Path(sys.argv[3])
    d7c_manifest = Path(sys.argv[4])
    d7c_edges_path = Path(sys.argv[5])
    d8a3_manifest = Path(sys.argv[6])
    d8a3_gene_audit_path = Path(sys.argv[7])
    project_root = Path(sys.argv[8])
    outdir = Path(sys.argv[9])
    outdir.mkdir(parents=True, exist_ok=True)

    result_path = outdir / "D9_RESULT.json"

    # ------------------------------------------------------------
    # 1. Re-certify authoritative inputs
    # ------------------------------------------------------------
    recertify_manifest(d8b_manifest, 13, "D8B")
    recertify_manifest(d7c_manifest, 11, "D7C")
    recertify_manifest(d8a3_manifest, 14, "D8A_V3")

    status_text = d8b_status_path.read_text(encoding="utf-8-sig", errors="replace")
    required_status = [
        "D8B_STATUS=PASS",
        "INPUT_EDGES=11531",
        "OUTPUT_EDGE_UNIVERSE=11531",
        "TARBASE_SUPPORTED=1972",
        "TARGETSCAN_SUPPORTED=205",
        "MIRDB_GT80_SUPPORTED=118",
        "TARGETSCAN_AND_MIRDB_SUPPORTED=43",
        "UNIQUE_REGULATORY_EDGES=1978",
        "NONREGULATORY_ASSOCIATION_EDGES=9553",
        "REGULATORY_EXPERIMENTAL=1935",
        "REGULATORY_PREDICTED_CONSENSUS=6",
        "REGULATORY_EXPERIMENTAL_AND_PREDICTED=37",
        "FULL_EDGE_CONSERVATION=PASS",
        "D8B_HASH_MISMATCHES=0",
        "READY_FOR_D9_MULTILAYER_NETWORK_CONSTRUCTION=YES",
        "STOP=YES",
    ]
    for tok in required_status:
        if tok not in status_text:
            raise RuntimeError(f"D8B_STATUS_TOKEN_MISSING={tok}")

    d8b_full_path = d8b_run / "D8B_FULL_EDGE_CLASSIFICATION.csv"
    d8b_reg_path = d8b_run / "D8B_REGULATORY_EDGE_FREEZE.csv"
    d8b_nonreg_path = d8b_run / "D8B_NONREGULATORY_ASSOCIATION_EDGES.csv"
    d8b_overlap_path = d8b_run / "D8B_EVIDENCE_OVERLAP_AUDIT.csv"

    for p in [d8b_full_path, d8b_reg_path, d8b_nonreg_path, d8b_overlap_path]:
        if not p.is_file():
            raise RuntimeError(f"REQUIRED_D8B_ARTIFACT_MISSING={p}")

    # ------------------------------------------------------------
    # 2. Read D8B full classification / frozen subsets
    # ------------------------------------------------------------
    full = pd.read_csv(
        d8b_full_path,
        dtype={"miRNA_ID": str, "mRNA_SYMBOL": str},
        float_precision="round_trip",
    )
    reg = pd.read_csv(
        d8b_reg_path,
        dtype={"miRNA_ID": str, "mRNA_SYMBOL": str},
        float_precision="round_trip",
    )
    nonreg = pd.read_csv(
        d8b_nonreg_path,
        dtype={"miRNA_ID": str, "mRNA_SYMBOL": str},
        float_precision="round_trip",
    )

    if len(full) != EXPECTED_ASSOC_EDGES:
        raise RuntimeError(f"D8B_FULL_ROWS_CHANGED={len(full)}")
    if len(reg) != EXPECTED_REG_EDGES:
        raise RuntimeError(f"D8B_REG_ROWS_CHANGED={len(reg)}")
    if len(nonreg) != EXPECTED_NONREG_EDGES:
        raise RuntimeError(f"D8B_NONREG_ROWS_CHANGED={len(nonreg)}")

    if full.duplicated(["miRNA_ID", "mRNA_SYMBOL"]).any():
        raise RuntimeError("D8B_FULL_DUPLICATE_EDGE_KEYS")
    if reg.duplicated(["miRNA_ID", "mRNA_SYMBOL"]).any():
        raise RuntimeError("D8B_REG_DUPLICATE_EDGE_KEYS")
    if nonreg.duplicated(["miRNA_ID", "mRNA_SYMBOL"]).any():
        raise RuntimeError("D8B_NONREG_DUPLICATE_EDGE_KEYS")

    # Exact R class checks
    r_counts = full["regulatory_class"].value_counts().to_dict()
    if int(r_counts.get("REGULATORY_EXPERIMENTAL", 0)) != EXPECTED_R1:
        raise RuntimeError("R1_COUNT_CHANGED")
    if int(r_counts.get("REGULATORY_PREDICTED_CONSENSUS", 0)) != EXPECTED_R2:
        raise RuntimeError("R2_COUNT_CHANGED")
    if int(r_counts.get("REGULATORY_EXPERIMENTAL_AND_PREDICTED", 0)) != EXPECTED_R3:
        raise RuntimeError("R3_COUNT_CHANGED")
    if int(r_counts.get("ASSOCIATION_ONLY_NOT_REGULATORY", 0)) != EXPECTED_NONREG_EDGES:
        raise RuntimeError("N_CLASS_COUNT_CHANGED")

    # ------------------------------------------------------------
    # 3. Re-compare with original D7C frozen association universe
    # ------------------------------------------------------------
    d7c = pd.read_csv(
        d7c_edges_path,
        compression="gzip",
        dtype={"miRNA_id": str, "mRNA_id": str},
        float_precision="round_trip",
    )
    if len(d7c) != EXPECTED_ASSOC_EDGES:
        raise RuntimeError("D7C_EDGE_COUNT_CHANGED")
    if d7c.duplicated(["miRNA_id", "mRNA_id"]).any():
        raise RuntimeError("D7C_DUPLICATE_EDGE_KEYS")

    if full["miRNA_ID"].tolist() != d7c["miRNA_id"].tolist():
        raise RuntimeError("MIRNA_IDENTITY_CHANGED=YES")
    if full["mRNA_SYMBOL"].tolist() != d7c["mRNA_id"].tolist():
        raise RuntimeError("MRNA_IDENTITY_CHANGED=YES")

    assoc_full = pd.to_numeric(full["association_score"], errors="coerce").to_numpy(dtype=float)
    assoc_d7c = pd.to_numeric(d7c["partial_spearman_rho"], errors="coerce").to_numpy(dtype=float)
    stab_full = pd.to_numeric(full["stability_score"], errors="coerce").to_numpy(dtype=float)
    stab_d7c = pd.to_numeric(d7c["bootstrap_selection_frequency"], errors="coerce").to_numpy(dtype=float)

    if not np.array_equal(assoc_full, assoc_d7c):
        raise RuntimeError("ASSOCIATION_WEIGHT_CHANGED=YES")
    if not np.array_equal(stab_full, stab_d7c):
        raise RuntimeError("STABILITY_WEIGHT_CHANGED=YES")

    # ------------------------------------------------------------
    # 4. Freeze node universe
    # ------------------------------------------------------------
    mRNAs = sorted(set(full["mRNA_SYMBOL"]))
    miRNAs = sorted(set(full["miRNA_ID"]))
    if len(mRNAs) != EXPECTED_MRNA:
        raise RuntimeError(f"MRNA_NODE_COUNT_CHANGED={len(mRNAs)}")
    if len(miRNAs) != EXPECTED_MIRNA:
        raise RuntimeError(f"MIRNA_NODE_COUNT_CHANGED={len(miRNAs)}")

    node_ids = miRNAs + mRNAs
    if len(node_ids) != EXPECTED_NODES or len(set(node_ids)) != EXPECTED_NODES:
        raise RuntimeError("NODE_UNIVERSE_COLLISION_OR_COUNT_FAILURE")

    nodes = pd.DataFrame({
        "node_id": node_ids,
        "node_type": ["MIRNA"] * len(miRNAs) + ["MRNA"] * len(mRNAs),
    })
    nodes["authoritative_gene_symbol"] = np.where(nodes["node_type"].eq("MRNA"), nodes["node_id"], "")
    nodes["mature_miRNA_id"] = np.where(nodes["node_type"].eq("MIRNA"), nodes["node_id"], "")
    nodes["MIMAT_accession"] = ""
    nodes["mature_miRNA_name"] = ""

    mir_mask = nodes["node_type"].eq("MIRNA")
    mir_parts = nodes.loc[mir_mask, "node_id"].str.split("|", n=1, expand=True)
    if mir_parts.shape[1] == 2:
        nodes.loc[mir_mask, "MIMAT_accession"] = mir_parts[0].to_numpy()
        nodes.loc[mir_mask, "mature_miRNA_name"] = mir_parts[1].to_numpy()
    else:
        nodes.loc[mir_mask, "mature_miRNA_name"] = nodes.loc[mir_mask, "node_id"].to_numpy()

    # D8A-V3 identity bridge/collision audit
    gene_audit = pd.read_csv(d8a3_gene_audit_path, dtype=str, keep_default_na=False)
    if len(gene_audit) != EXPECTED_MRNA:
        raise RuntimeError("D8A_V3_GENE_AUDIT_ROWS_CHANGED")
    if set(gene_audit["project_mRNA_id"]) != set(mRNAs):
        raise RuntimeError("D8A_V3_GENE_SET_CHANGED")
    nonempty = gene_audit[gene_audit["reference_current_symbol"].astype(str).ne("")]
    collisions = int(
        (
            nonempty.groupby("reference_current_symbol")["project_mRNA_id"].nunique() > 1
        ).sum()
    )
    if collisions != 0:
        raise RuntimeError(f"GENE_NORMALIZATION_COLLISIONS={collisions}")

    # Optional exact DE metadata attachment
    de_root = project_root / "05_DIFFERENTIAL_EXPRESSION"
    nodes, de_audit_rows, de_attached = try_attach_de_metadata(de_root, nodes)
    pd.DataFrame(de_audit_rows).to_csv(outdir / "D9_DE_METADATA_AUDIT.csv", index=False)

    # ------------------------------------------------------------
    # 5. Master structural edge table — one row per association pair
    # ------------------------------------------------------------
    master = full.copy()
    master.insert(0, "source", master["miRNA_ID"])
    master.insert(1, "target", master["mRNA_SYMBOL"])
    master.insert(2, "source_type", "MIRNA")
    master.insert(3, "target_type", "MRNA")
    master.insert(4, "layer", "MRNA_MIRNA_ASSOCIATION")
    master.insert(5, "association_edge", "YES")
    master["miRDB_GT80_support"] = master["miRDB_support"]

    master["biological_direction_source"] = np.where(
        master["regulatory_eligible"].astype(str).eq("YES"),
        master["miRNA_ID"],
        "",
    )
    master["biological_direction_target"] = np.where(
        master["regulatory_eligible"].astype(str).eq("YES"),
        master["mRNA_SYMBOL"],
        "",
    )
    master["structural_graph_directionality"] = "UNDIRECTED"
    master["D9_transformation_applied"] = "NO"

    if len(master) != EXPECTED_ASSOC_EDGES:
        raise RuntimeError("MASTER_EDGE_COUNT_CHANGED")
    if master.duplicated(["source", "target"]).any():
        raise RuntimeError("DUPLICATE_STRUCTURAL_EDGES")
    if int((master["source"] == master["target"]).sum()) != 0:
        raise RuntimeError("SELF_LOOPS_DETECTED")

    known = set(nodes["node_id"])
    unknown_endpoints = int(
        (~master["source"].isin(known)).sum()
        + (~master["target"].isin(known)).sum()
    )
    if unknown_endpoints != 0:
        raise RuntimeError(f"UNKNOWN_ENDPOINTS={unknown_endpoints}")

    assoc_vals, invalid_assoc = finite_numeric(master["association_score"])
    stab_vals, invalid_stab = finite_numeric(master["stability_score"])
    invalid_weights = invalid_assoc + invalid_stab
    if invalid_weights != 0:
        raise RuntimeError(f"INVALID_WEIGHTS={invalid_weights}")

    # reverse copies: because source is always MIRNA and target MRNA, any reverse duplicate is invalid
    forward_keys = set(zip(master["source"], master["target"]))
    reverse_copy_count = sum((t, s) in forward_keys for s, t in forward_keys)
    if reverse_copy_count != 0:
        raise RuntimeError(f"DUPLICATE_REVERSE_COPIES={reverse_copy_count}")

    reg_eligible = master["regulatory_eligible"].astype(str).eq("YES")
    if int(reg_eligible.sum()) != EXPECTED_REG_EDGES:
        raise RuntimeError("REGULATORY_SUBSET_COUNT_CHANGED_IN_MASTER")

    # ------------------------------------------------------------
    # 6. Frozen layer inventory
    # ------------------------------------------------------------
    layer_inventory = pd.DataFrame([
        {
            "LAYER_NAME": "MRNA_MRNA_ASSOCIATION",
            "AUTHORITATIVE_SOURCE_FILE": "",
            "SOURCE_PHASE": "",
            "EDGE_COUNT": 0,
            "WEIGHT_COLUMN": "",
            "STABILITY_COLUMN": "",
            "DIRECTED_OR_UNDIRECTED": "",
            "STRUCTURAL_LAYER": "NO",
            "AVAILABLE_AND_FROZEN": "NO",
            "NOTES": "No certified mRNA-mRNA structural edge set exists in the authoritative D7C/D8B freeze.",
        },
        {
            "LAYER_NAME": "MIRNA_MIRNA_ASSOCIATION",
            "AUTHORITATIVE_SOURCE_FILE": "",
            "SOURCE_PHASE": "",
            "EDGE_COUNT": 0,
            "WEIGHT_COLUMN": "",
            "STABILITY_COLUMN": "",
            "DIRECTED_OR_UNDIRECTED": "",
            "STRUCTURAL_LAYER": "NO",
            "AVAILABLE_AND_FROZEN": "NO",
            "NOTES": "No certified miRNA-miRNA structural edge set exists in the authoritative D7C/D8B freeze.",
        },
        {
            "LAYER_NAME": "MRNA_MIRNA_ASSOCIATION",
            "AUTHORITATIVE_SOURCE_FILE": str(d8b_full_path),
            "SOURCE_PHASE": "D7C_ASSOCIATION_FREEZE + D8B_EVIDENCE_FREEZE",
            "EDGE_COUNT": EXPECTED_ASSOC_EDGES,
            "WEIGHT_COLUMN": "association_score",
            "STABILITY_COLUMN": "stability_score",
            "DIRECTED_OR_UNDIRECTED": "UNDIRECTED",
            "STRUCTURAL_LAYER": "YES",
            "AVAILABLE_AND_FROZEN": "YES",
            "NOTES": "One structural edge per frozen mRNA-miRNA association pair.",
        },
        {
            "LAYER_NAME": "MRNA_MIRNA_REGULATORY_EVIDENCE",
            "AUTHORITATIVE_SOURCE_FILE": str(d8b_reg_path),
            "SOURCE_PHASE": "D8B_REGULATORY_EDGE_FREEZE",
            "EDGE_COUNT": EXPECTED_REG_EDGES,
            "WEIGHT_COLUMN": "binary_regulatory_eligible",
            "STABILITY_COLUMN": "stability_score",
            "DIRECTED_OR_UNDIRECTED": "BIOLOGICAL_DIRECTION_MIRNA_TO_MRNA;NOT_ADDED_AS_SECOND_STRUCTURAL_EDGE",
            "STRUCTURAL_LAYER": "NO",
            "AVAILABLE_AND_FROZEN": "YES",
            "NOTES": "Semantic/binary channel on a subset of the association layer; not double-counted in flattened structural graph.",
        },
    ])
    layer_inventory.to_csv(outdir / "D9_LAYER_INVENTORY.csv", index=False)

    frozen_layers_discovered = int(layer_inventory["AVAILABLE_AND_FROZEN"].eq("YES").sum())
    frozen_layers_included = frozen_layers_discovered

    # ------------------------------------------------------------
    # 7. Save master node/edge and layer tables
    # ------------------------------------------------------------
    nodes_path = outdir / "D9_MASTER_NODES.csv"
    master_path = outdir / "D9_MASTER_EDGES.csv"
    assoc_path = outdir / "D9_MRNA_MIRNA_ASSOCIATION_EDGES.csv"
    reg_layer_path = outdir / "D9_REGULATORY_EDGE_LAYER.csv"

    nodes.to_csv(nodes_path, index=False, float_format="%.17g")
    master.to_csv(master_path, index=False, float_format="%.17g")
    master.to_csv(assoc_path, index=False, float_format="%.17g")
    master.loc[reg_eligible].to_csv(reg_layer_path, index=False, float_format="%.17g")

    # Round-trip identity checks
    nrt = pd.read_csv(nodes_path, dtype={"node_id": str, "node_type": str})
    ert = pd.read_csv(master_path, dtype={"source": str, "target": str}, float_precision="round_trip")
    if len(nrt) != EXPECTED_NODES or nrt["node_id"].duplicated().any():
        raise RuntimeError("MASTER_NODE_ROUNDTRIP_FAILURE")
    if len(ert) != EXPECTED_ASSOC_EDGES or ert.duplicated(["source", "target"]).any():
        raise RuntimeError("MASTER_EDGE_ROUNDTRIP_FAILURE")
    if ert["source"].tolist() != master["source"].tolist() or ert["target"].tolist() != master["target"].tolist():
        raise RuntimeError("MASTER_EDGE_IDENTITY_ROUNDTRIP_CHANGED")

    # ------------------------------------------------------------
    # 8. Layer / complete network topology summaries
    # ------------------------------------------------------------
    all_nodes = nodes["node_id"].tolist()

    structural_stats = graph_stats(
        all_nodes,
        master[["source", "target", "association_score"]].copy(),
        "association_score",
    )

    reg_edges_for_stats = master.loc[reg_eligible, ["source", "target", "association_score"]].copy()
    regulatory_stats = graph_stats(all_nodes, reg_edges_for_stats, "association_score")

    layer_summary_rows = []
    for layer_name, structural_flag, edge_count, stats in [
        ("MRNA_MIRNA_ASSOCIATION", "YES", EXPECTED_ASSOC_EDGES, structural_stats),
        ("MRNA_MIRNA_REGULATORY_EVIDENCE", "NO_SEMANTIC_CHANNEL", EXPECTED_REG_EDGES, regulatory_stats),
    ]:
        row = {
            "layer": layer_name,
            "structural_layer": structural_flag,
            "node_count": EXPECTED_NODES,
            "edge_count": edge_count,
        }
        row.update(stats)
        layer_summary_rows.append(row)

    layer_summary = pd.DataFrame(layer_summary_rows)
    layer_summary.to_csv(outdir / "D9_LAYER_SUMMARY.csv", index=False)

    # ------------------------------------------------------------
    # 9. Regulatory coverage audit
    # ------------------------------------------------------------
    reg_master = master.loc[reg_eligible].copy()
    regulatory_mirnas = reg_master["source"].nunique()
    regulatory_mrnas = reg_master["target"].nunique()

    r1_count = int((master["regulatory_class"] == "REGULATORY_EXPERIMENTAL").sum())
    r2_count = int((master["regulatory_class"] == "REGULATORY_PREDICTED_CONSENSUS").sum())
    r3_count = int((master["regulatory_class"] == "REGULATORY_EXPERIMENTAL_AND_PREDICTED").sum())

    coverage = pd.DataFrame([
        ["REGULATORY_EDGES", EXPECTED_REG_EDGES],
        ["REGULATORY_MIRNAS", regulatory_mirnas],
        ["REGULATORY_MRNAS", regulatory_mrnas],
        ["MIRNAS_WITH_AT_LEAST_ONE_REGULATORY_EDGE", regulatory_mirnas],
        ["MRNAS_WITH_AT_LEAST_ONE_REGULATORY_EDGE", regulatory_mrnas],
        ["REGULATORY_EDGE_FRACTION_OF_MRNA_MIRNA_ASSOCIATIONS", EXPECTED_REG_EDGES / EXPECTED_ASSOC_EDGES],
        ["R1_EDGE_FRACTION", r1_count / EXPECTED_REG_EDGES],
        ["R2_EDGE_FRACTION", r2_count / EXPECTED_REG_EDGES],
        ["R3_EDGE_FRACTION", r3_count / EXPECTED_REG_EDGES],
    ], columns=["metric", "value"])
    coverage.to_csv(outdir / "D9_REGULATORY_COVERAGE_AUDIT.csv", index=False)

    # ------------------------------------------------------------
    # 10. Reusable A-CLA code inspection + deterministic input bundle
    # ------------------------------------------------------------
    reusable_root = project_root.parent / "00_REUSABLE_ASSETS"
    if not reusable_root.exists():
        raise RuntimeError(f"REUSABLE_ASSETS_ROOT_MISSING={reusable_root}")

    acla_candidates = detect_acla_code(reusable_root)
    if len(acla_candidates) == 0:
        raise RuntimeError("AUTHORITATIVE_ACLA_CODE_CANDIDATES_FOUND=0")

    acla_inventory = pd.DataFrame(acla_candidates)
    acla_inventory_path = outdir / "D9_ACLA_CODE_INVENTORY.csv"
    acla_inventory.to_csv(acla_inventory_path, index=False)

    acla_composite = composite_hash(acla_candidates)
    acla_code_hash = f"COMPOSITE_SHA256:{acla_composite}"

    acla_dir = outdir / "D9_ACLA_INPUT"
    acla_dir.mkdir(exist_ok=True)

    node_index = nodes[["node_id", "node_type"]].copy()
    node_index.insert(0, "node_index", np.arange(len(node_index), dtype=int))
    node_index_path = acla_dir / "node_index.csv"
    node_index.to_csv(node_index_path, index=False)

    acla_edge_list = master[
        [
            "source", "target", "association_score", "stability_score",
            "regulatory_eligible", "regulatory_class",
            "TarBase_support", "TargetScan_support", "miRDB_GT80_support",
        ]
    ].copy()
    acla_edge_list_path = acla_dir / "structural_edge_list.csv"
    acla_edge_list.to_csv(acla_edge_list_path, index=False, float_format="%.17g")

    reg_sem_path = acla_dir / "regulatory_semantic_edge_list.csv"
    acla_edge_list.loc[acla_edge_list["regulatory_eligible"].astype(str).eq("YES")].to_csv(
        reg_sem_path, index=False, float_format="%.17g"
    )

    idx = dict(zip(node_index["node_id"], node_index["node_index"]))
    rows = np.array([idx[x] for x in master["source"]], dtype=np.int32)
    cols = np.array([idx[x] for x in master["target"]], dtype=np.int32)
    assoc_data = pd.to_numeric(master["association_score"], errors="raise").to_numpy(dtype=np.float64)
    stability_data = pd.to_numeric(master["stability_score"], errors="raise").to_numpy(dtype=np.float64)
    reg_data = reg_eligible.to_numpy(dtype=np.int8)

    # Symmetric COO representation for the undirected structural optimization graph.
    sym_rows = np.concatenate([rows, cols])
    sym_cols = np.concatenate([cols, rows])
    assoc_sym = np.concatenate([assoc_data, assoc_data])
    stability_sym = np.concatenate([stability_data, stability_data])
    reg_sym = np.concatenate([reg_data, reg_data])
    shape = np.array([EXPECTED_NODES, EXPECTED_NODES], dtype=np.int32)

    np.savez_compressed(
        acla_dir / "association_score_symmetric_coo.npz",
        row=sym_rows, col=sym_cols, data=assoc_sym, shape=shape,
    )
    np.savez_compressed(
        acla_dir / "stability_score_symmetric_coo.npz",
        row=sym_rows, col=sym_cols, data=stability_sym, shape=shape,
    )
    np.savez_compressed(
        acla_dir / "regulatory_binary_symmetric_coo.npz",
        row=sym_rows, col=sym_cols, data=reg_sym, shape=shape,
    )

    acla_schema = "MULTIFORMAT_COMPATIBILITY_BUNDLE_EDGE_LIST_PLUS_SYMMETRIC_COO_NPZ"
    schema_json = {
        "ACLA_INPUT_SCHEMA": acla_schema,
        "ACLA_CODE_VERSION_OR_HASH": acla_code_hash,
        "structural_directionality": "UNDIRECTED",
        "biological_regulatory_direction": "miRNA_to_mRNA_metadata_only",
        "node_count": EXPECTED_NODES,
        "structural_edge_count": EXPECTED_ASSOC_EDGES,
        "regulatory_semantic_edge_count": EXPECTED_REG_EDGES,
        "files": {
            "node_index": "node_index.csv",
            "structural_edge_list": "structural_edge_list.csv",
            "regulatory_semantic_edge_list": "regulatory_semantic_edge_list.csv",
            "association_score_coo": "association_score_symmetric_coo.npz",
            "stability_score_coo": "stability_score_symmetric_coo.npz",
            "regulatory_binary_coo": "regulatory_binary_symmetric_coo.npz",
        },
        "note": "Exact executable invocation is intentionally deferred to the A-CLA pre-execution freeze. D9 does not execute or modify A-CLA.",
    }
    (acla_dir / "input_schema.json").write_text(
        json.dumps(schema_json, indent=2, sort_keys=True), encoding="utf-8"
    )
    (acla_dir / "README.txt").write_text(
        "D9 A-CLA compatibility bundle. Structural graph is the frozen undirected "
        "11,531-edge mRNA-miRNA association layer. Regulatory evidence is a separate "
        "semantic/binary channel and is not added as duplicate structural edges. "
        "No A-CLA execution occurred in D9.\n",
        encoding="utf-8",
    )

    # ------------------------------------------------------------
    # 11. Network QC
    # ------------------------------------------------------------
    self_loops = int((master["source"] == master["target"]).sum())
    duplicates = int(master.duplicated(["source", "target"]).sum())
    qc = pd.DataFrame([
        ["TOTAL_NODES", EXPECTED_NODES],
        ["TOTAL_STRUCTURAL_EDGES", EXPECTED_ASSOC_EDGES],
        ["SELF_LOOPS", self_loops],
        ["DUPLICATE_STRUCTURAL_EDGES", duplicates],
        ["DUPLICATE_REVERSE_COPIES", reverse_copy_count],
        ["UNKNOWN_ENDPOINTS", unknown_endpoints],
        ["INVALID_WEIGHTS", invalid_weights],
        ["CONNECTED_COMPONENTS", structural_stats["CONNECTED_COMPONENTS"]],
        ["LARGEST_COMPONENT_NODES", structural_stats["LARGEST_COMPONENT_NODES"]],
        ["LARGEST_COMPONENT_FRACTION", structural_stats["LARGEST_COMPONENT_FRACTION"]],
        ["ISOLATED_NODES", structural_stats["ISOLATED_NODES"]],
        ["MIN_DEGREE", structural_stats["MIN_DEGREE"]],
        ["MEDIAN_DEGREE", structural_stats["MEDIAN_DEGREE"]],
        ["MEAN_DEGREE", structural_stats["MEAN_DEGREE"]],
        ["MAX_DEGREE", structural_stats["MAX_DEGREE"]],
        ["REGULATORY_EDGE_DOUBLE_COUNT_IN_FLATTENED_GRAPH", 0],
        ["ASSOCIATION_ONLY_EDGES_RETAINED", EXPECTED_NONREG_EDGES],
        ["GENE_NORMALIZATION_COLLISIONS", collisions],
    ], columns=["metric", "value"])
    qc.to_csv(outdir / "D9_NETWORK_QC_SUMMARY.csv", index=False)

    # ------------------------------------------------------------
    # 12. Freeze execution specification and upstream hashes
    # ------------------------------------------------------------
    upstream_hash_rows = []
    for label, p in [
        ("D8B_MANIFEST", d8b_manifest),
        ("D8B_FINAL_STATUS", d8b_status_path),
        ("D8B_FULL_EDGE_CLASSIFICATION", d8b_full_path),
        ("D8B_REGULATORY_EDGE_FREEZE", d8b_reg_path),
        ("D8B_NONREGULATORY_ASSOCIATION_EDGES", d8b_nonreg_path),
        ("D7C_MANIFEST", d7c_manifest),
        ("D7C_FROZEN_ASSOCIATION_EDGES", d7c_edges_path),
        ("D8A_V3_MANIFEST", d8a3_manifest),
        ("D8A_V3_GENE_AUDIT", d8a3_gene_audit_path),
    ]:
        upstream_hash_rows.append({
            "artifact": label,
            "full_path": str(p),
            "size_bytes": p.stat().st_size,
            "SHA256": sha256_file(p),
        })
    pd.DataFrame(upstream_hash_rows).to_csv(
        outdir / "D9_AUTHORITATIVE_UPSTREAM_HASHES.csv", index=False
    )

    spec = f"""GSE243219_D9_EXECUTION_SPECIFICATION
MODE=FINAL_MULTILAYER_NETWORK_CONSTRUCTION_ONLY
AUTHORITATIVE_D8B_RUN={d8b_run}
D9_INPUT_HASH_VALIDATION=PASS
MRNA_NODES=4467
MIRNA_NODES=41
TOTAL_NODES=4508
MRNA_MRNA_ASSOCIATION_AVAILABLE_AND_FROZEN=NO
MIRNA_MIRNA_ASSOCIATION_AVAILABLE_AND_FROZEN=NO
MRNA_MIRNA_ASSOCIATION_AVAILABLE_AND_FROZEN=YES
MRNA_MIRNA_ASSOCIATION_EDGES=11531
REGULATORY_SEMANTIC_LAYER_AVAILABLE_AND_FROZEN=YES
REGULATORY_EDGES=1978
NONREGULATORY_ASSOCIATION_EDGES=9553
REGULATORY_EXPERIMENTAL=1935
REGULATORY_PREDICTED_CONSENSUS=6
REGULATORY_EXPERIMENTAL_AND_PREDICTED=37
REGULATORY_EDGE_DOUBLE_COUNT_IN_FLATTENED_GRAPH=0
RAW_WEIGHT_FIELD=association_score
STABILITY_FIELD=stability_score
TRANSFORMATION_ALREADY_FROZEN=NONE
D9_TRANSFORMATION_APPLIED=NO
ASSOCIATION_GRAPH_DIRECTIONALITY=UNDIRECTED
REGULATORY_BIOLOGICAL_DIRECTION_RETAINED=YES
REGULATORY_BIOLOGICAL_DIRECTION=miRNA_TO_mRNA
ACLA_OPTIMIZATION_DIRECTIONALITY=UNDIRECTED_INPUT_FREEZE;FINAL_EXECUTION_POLICY_DEFERRED_TO_PREEXECUTION_FREEZE
DE_USED_FOR_NODE_METADATA={"YES" if de_attached else "NO"}
DE_USED_FOR_NEW_EDGE_FILTERING=NO
DE_RECOMPUTED=NO
ASSOCIATION_RECOMPUTED=NO
TARGET_EVIDENCE_RECOMPUTED=NO
NODE_IDENTITY_NORMALIZATION_RENAMING_MERGING=NO
ACLA_INPUT_SCHEMA={acla_schema}
ACLA_CODE_VERSION_OR_HASH={acla_code_hash}
ACLA_INPUT_GENERATED=YES
ACLA_EXECUTED=NO
COMMUNITY_DETECTION_EXECUTED=NO
MODULE_SELECTION_EXECUTED=NO
HUB_ANALYSIS_EXECUTED=NO
ENRICHMENT_EXECUTED=NO
DRUG_ANALYSIS_EXECUTED=NO
STOP_AFTER_D9=YES
"""
    (outdir / "D9_EXECUTION_SPECIFICATION.txt").write_text(spec, encoding="utf-8")

    # ------------------------------------------------------------
    # 13. Final result JSON (PowerShell creates final status + manifest)
    # ------------------------------------------------------------
    result = {
        "D9_STATUS": "PASS",
        "UPSTREAM_INPUT_INTEGRITY": "PASS",
        "MRNA_NODES": EXPECTED_MRNA,
        "MIRNA_NODES": EXPECTED_MIRNA,
        "TOTAL_NODES": EXPECTED_NODES,
        "FROZEN_LAYERS_DISCOVERED": frozen_layers_discovered,
        "FROZEN_LAYERS_INCLUDED": frozen_layers_included,
        "MRNA_MRNA_EDGES": 0,
        "MIRNA_MIRNA_EDGES": 0,
        "MRNA_MIRNA_ASSOCIATION_EDGES": EXPECTED_ASSOC_EDGES,
        "REGULATORY_EDGES": EXPECTED_REG_EDGES,
        "NONREGULATORY_MRNA_MIRNA_ASSOCIATION_EDGES": EXPECTED_NONREG_EDGES,
        "REGULATORY_EXPERIMENTAL": EXPECTED_R1,
        "REGULATORY_PREDICTED_CONSENSUS": EXPECTED_R2,
        "REGULATORY_EXPERIMENTAL_AND_PREDICTED": EXPECTED_R3,
        "ASSOCIATION_ONLY_EDGES_RETAINED": EXPECTED_NONREG_EDGES,
        "REGULATORY_EDGE_DOUBLE_COUNT_IN_FLATTENED_GRAPH": 0,
        "TOTAL_STRUCTURAL_EDGES": EXPECTED_ASSOC_EDGES,
        "SELF_LOOPS": self_loops,
        "DUPLICATE_STRUCTURAL_EDGES": duplicates,
        "UNKNOWN_ENDPOINTS": unknown_endpoints,
        "INVALID_WEIGHTS": invalid_weights,
        "CONNECTED_COMPONENTS": structural_stats["CONNECTED_COMPONENTS"],
        "LARGEST_COMPONENT_NODES": structural_stats["LARGEST_COMPONENT_NODES"],
        "LARGEST_COMPONENT_FRACTION": structural_stats["LARGEST_COMPONENT_FRACTION"],
        "ISOLATED_NODES": structural_stats["ISOLATED_NODES"],
        "REGULATORY_MIRNAS": regulatory_mirnas,
        "REGULATORY_MRNAS": regulatory_mrnas,
        "DE_USED_FOR_NODE_METADATA": "YES" if de_attached else "NO",
        "DE_RECOMPUTED": "NO",
        "ASSOCIATION_RECOMPUTED": "NO",
        "TARGET_EVIDENCE_RECOMPUTED": "NO",
        "MRNA_IDENTITY_CHANGED": "NO",
        "MIRNA_IDENTITY_CHANGED": "NO",
        "D9_MASTER_NODES_CREATED": "YES",
        "D9_MASTER_EDGES_CREATED": "YES",
        "D9_LAYER_SUMMARY_CREATED": "YES",
        "ACLA_INPUT_SCHEMA": acla_schema,
        "ACLA_CODE_VERSION_OR_HASH": acla_code_hash,
        "ACLA_CODE_CANDIDATES": len(acla_candidates),
        "ACLA_INPUT_GENERATED": "YES",
        "ACLA_EXECUTED": "NO",
        "NETWORK_CONSTRUCTION_EXECUTED": "YES",
        "READY_FOR_ACLA_PREEXECUTION_FREEZE": "YES",
        "STOP": "YES",
    }
    result_path.write_text(
        json.dumps(result, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
