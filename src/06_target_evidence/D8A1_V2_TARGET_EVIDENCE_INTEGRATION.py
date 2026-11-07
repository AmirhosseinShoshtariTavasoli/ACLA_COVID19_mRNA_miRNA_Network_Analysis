#!/usr/bin/env python3
from __future__ import annotations

import gzip
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_EDGES = 11531
EXPECTED_MRNA = 4467
EXPECTED_MIRNA = 41
MIRDB_THRESHOLD = 80.0

def emit(res, k, v):
    res[k] = v
    print(f"{k}={v}", flush=True)

def norm_col(x):
    return re.sub(r"[^a-z0-9]+", "", str(x).lower())

def strip_ver(x):
    return str(x or "").strip().split(".")[0]

def split_multi(x):
    s = str(x or "").strip()
    if not s or s in {"-", "nan", "None"}:
        return []
    return [z.strip() for z in re.split(r"[|,;]+", s) if z.strip() and z.strip() != "-"]

def canonical_hsa_name(x):
    s = str(x or "").strip()
    if not s:
        return ""
    if s.startswith("hsa-"):
        return s
    if s.startswith(("miR-", "mir-", "let-")):
        return "hsa-" + s
    return s

def sha256_file(path: Path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(8*1024*1024)
            if not b:
                break
            h.update(b)
    return h.hexdigest()

class GeneBridge:
    def __init__(self, project_genes, gene_audit, ref_path):
        self.project_genes = set(project_genes)

        need = {"project_mRNA_id","reference_current_symbol","external_mapping_ambiguity"}
        miss = need - set(gene_audit.columns)
        if miss:
            raise RuntimeError(f"GENE_AUDIT_COLUMNS_MISSING={sorted(miss)}")

        current_to_project = {}
        for _, r in gene_audit.iterrows():
            p = str(r["project_mRNA_id"]).strip()
            c = str(r["reference_current_symbol"]).strip()
            if c:
                if c in current_to_project and current_to_project[c] != p:
                    raise RuntimeError(f"GENE_AUDIT_REFERENCE_COLLISION={c}")
                current_to_project[c] = p

        ref = pd.read_csv(ref_path, sep="\t", dtype=str, keep_default_na=False, low_memory=False)
        cols = {norm_col(c): c for c in ref.columns}
        need_ref = {"symbol","aliassymbol","prevsymbol"}
        miss = need_ref - set(cols)
        if miss:
            raise RuntimeError(f"GENE_REFERENCE_COLUMNS_MISSING={sorted(miss)}")

        sym_c = cols["symbol"]
        alias_c = cols["aliassymbol"]
        prev_c = cols["prevsymbol"]

        candidates = defaultdict(set)

        # Exact frozen project symbols are authoritative.
        for g in self.project_genes:
            candidates[g].add(g)

        # External aliases/previous names only bridge if the current reference
        # symbol was uniquely linked to one frozen project gene in D8A-V3.
        for _, r in ref.iterrows():
            current = str(r[sym_c]).strip()
            project = current_to_project.get(current)
            if not project:
                continue
            candidates[current].add(project)
            for a in split_multi(r[alias_c]):
                candidates[a].add(project)
            for p in split_multi(r[prev_c]):
                candidates[p].add(project)

        self.unique = {k: next(iter(v)) for k, v in candidates.items() if len(v) == 1}
        self.ambig = {k for k, v in candidates.items() if len(v) > 1}

    def map_symbol(self, raw):
        s = str(raw or "").strip()
        if s in self.project_genes:
            return s, "EXACT_PROJECT_SYMBOL"
        if s in self.ambig:
            return "", "AMBIGUOUS_NO_SUPPORT"
        if s in self.unique:
            return self.unique[s], "UNIQUE_EXTERNAL_BRIDGE"
        return "", "UNMATCHED_NO_SUPPORT"

def selected_assets(inv_path: Path):
    inv = pd.read_csv(inv_path, dtype=str, keep_default_na=False)
    sel = inv.loc[inv["selected_primary"].astype(str).eq("YES")].copy()
    required = {
        "TARBASE_V9_HUMAN",
        "MIRDB_V6_HUMAN",
        "TARGETSCANHUMAN_8_DEFAULT",
        "MIRBASE_22_1_MATURE",
        "HGNC_COMPLETE_SET",
    }
    got = set(sel["asset_kind"].astype(str))
    if got != required:
        raise RuntimeError(f"SELECTED_ASSET_KIND_SET_CHANGED={sorted(got)}")
    out = {}
    for _, r in sel.iterrows():
        p = Path(str(r["full_path"]))
        if not p.is_file():
            raise RuntimeError(f"SELECTED_ASSET_MISSING={r['asset_kind']}|{p}")
        if sha256_file(p) != str(r["SHA256"]).lower():
            raise RuntimeError(f"SELECTED_ASSET_SHA256_CHANGED={r['asset_kind']}")
        out[str(r["asset_kind"])] = p
    return out

def main():
    if len(sys.argv) != 9:
        raise SystemExit(
            "usage: script stable_edges asset_inventory gene_audit mirbase_audit "
            "targetscan_family_audit mirdb_refseq_bridge out_dir result_json"
        )

    stable_path = Path(sys.argv[1])
    asset_inv = Path(sys.argv[2])
    gene_audit_path = Path(sys.argv[3])
    mirbase_audit_path = Path(sys.argv[4])
    ts_family_audit_path = Path(sys.argv[5])
    mirdb_bridge_path = Path(sys.argv[6])
    outdir = Path(sys.argv[7])
    result_json = Path(sys.argv[8])
    outdir.mkdir(parents=True, exist_ok=True)

    res = {}
    emit(res, "TARGET_DATABASE_EDGE_MATCHING_EXECUTED_AT_START", "NO")

    stable = pd.read_csv(stable_path, compression="gzip", engine="c", float_precision="round_trip")
    required = {"mRNA_id","miRNA_id","partial_spearman_rho","bootstrap_selection_frequency"}
    miss = required - set(stable.columns)
    if miss:
        raise RuntimeError(f"FROZEN_EDGE_COLUMNS_MISSING={sorted(miss)}")
    if len(stable) != EXPECTED_EDGES:
        raise RuntimeError(f"FROZEN_EDGE_COUNT_CHANGED={len(stable)}")
    if stable.duplicated(["miRNA_id","mRNA_id"]).any():
        raise RuntimeError("FROZEN_EDGE_DUPLICATES_DETECTED")

    stable["mRNA_id"] = stable["mRNA_id"].astype(str)
    stable["miRNA_id"] = stable["miRNA_id"].astype(str)
    parts = stable["miRNA_id"].str.split("|", n=1, expand=True)
    if parts.shape[1] != 2:
        raise RuntimeError("MIRNA_IDENTITY_FORMAT_CHANGED")
    stable["MIMAT"] = parts[0]
    stable["mature"] = parts[1]

    project_genes = set(stable["mRNA_id"])
    project_mirna_ids = set(stable["miRNA_id"])
    if len(project_genes) != EXPECTED_MRNA:
        raise RuntimeError(f"UNIQUE_MRNA_CHANGED={len(project_genes)}")
    if len(project_mirna_ids) != EXPECTED_MIRNA:
        raise RuntimeError(f"UNIQUE_MIRNA_CHANGED={len(project_mirna_ids)}")

    mature_to_id = dict(zip(stable["mature"], stable["miRNA_id"]))
    mimat_to_id = dict(zip(stable["MIMAT"], stable["miRNA_id"]))
    stable_keys = set(zip(stable["miRNA_id"], stable["mRNA_id"]))

    emit(res, "FROZEN_EDGE_INPUT_COUNT", len(stable))
    emit(res, "FROZEN_UNIQUE_MRNA", len(project_genes))
    emit(res, "FROZEN_UNIQUE_MIRNA", len(project_mirna_ids))
    emit(res, "FROZEN_EDGE_INPUT_GATE", "PASS")

    assets = selected_assets(asset_inv)
    emit(res, "SELECTED_DATABASE_ASSET_SHA256_RECERTIFICATION", "PASS")

    gene_audit = pd.read_csv(gene_audit_path, dtype=str, keep_default_na=False)
    if len(gene_audit) != EXPECTED_MRNA or set(gene_audit["project_mRNA_id"]) != project_genes:
        raise RuntimeError("D8A_V3_GENE_AUDIT_PROJECT_SET_CHANGED")

    mirbase_audit = pd.read_csv(mirbase_audit_path, dtype=str, keep_default_na=False)
    if len(mirbase_audit) != EXPECTED_MIRNA:
        raise RuntimeError("D8A_V3_MIRBASE_AUDIT_ROW_COUNT_CHANGED")
    if "exact_miRBase22_1_pair" not in mirbase_audit.columns:
        raise RuntimeError("MIRBASE_EXACT_PAIR_COLUMN_MISSING")
    if not mirbase_audit["exact_miRBase22_1_pair"].eq("YES").all():
        raise RuntimeError("MIRBASE_41_OF_41_VALIDATION_CHANGED")

    bridge = GeneBridge(project_genes, gene_audit, assets["HGNC_COMPLETE_SET"])
    emit(res, "PROJECT_GENE_AUTHORITATIVE_IDENTITY", "EXACT_FROZEN_PROJECT_SYMBOL")
    emit(res, "PROJECT_MIRNA_MIRBASE22_1_VALIDATED", "41/41")
    emit(res, "IDENTIFIER_BRIDGE_GATE", "PASS")

    tar_support = defaultdict(int)
    ts_support = defaultdict(int)
    mirdb_support = defaultdict(int)
    mirdb_max = {}

    # ----------------------------------------------------------
    # TarBase v9
    # ----------------------------------------------------------
    tar = assets["TARBASE_V9_HUMAN"]
    header = pd.read_csv(tar, sep="\t", compression="gzip", nrows=0)
    cols = list(header.columns)
    norm = {norm_col(c): c for c in cols}
    for k in ["mirnaname","mirnaid","genename"]:
        if k not in norm:
            raise RuntimeError(f"TARBASE_REQUIRED_COLUMN_MISSING={k}|columns={cols}")

    mir_name_col = norm["mirnaname"]
    mir_id_col = norm["mirnaid"]
    gene_col = norm["genename"]

    tar_rows = 0
    tar_ambig = 0
    tar_matched_records = 0

    for ch in pd.read_csv(
        tar, sep="\t", compression="gzip",
        dtype=str, keep_default_na=False, chunksize=200000
    ):
        tar_rows += len(ch)
        for _, r in ch.iterrows():
            mids = set()
            n = canonical_hsa_name(r[mir_name_col])
            a = str(r[mir_id_col]).strip()
            if n in mature_to_id:
                mids.add(mature_to_id[n])
            if a in mimat_to_id:
                mids.add(mimat_to_id[a])
            if not mids:
                continue
            if len(mids) != 1:
                tar_ambig += 1
                continue
            gene, route = bridge.map_symbol(r[gene_col])
            if not gene:
                if route == "AMBIGUOUS_NO_SUPPORT":
                    tar_ambig += 1
                continue
            key = (next(iter(mids)), gene)
            if key in stable_keys:
                tar_support[key] += 1
                tar_matched_records += 1
        if tar_rows % 1000000 < 200000:
            print(f"TARBASE_PROGRESS_ROWS={tar_rows}", flush=True)

    emit(res, "TARBASE_MATCHING_COMPLETED", "YES")
    emit(res, "TARBASE_SOURCE_ROWS", tar_rows)
    emit(res, "TARBASE_MATCHED_EDGES", len(tar_support))

    # ----------------------------------------------------------
    # TargetScan 8 — corrected Release-8 explicit metadata mapping
    # D8A1-V1 incorrectly treated prediction column "miRNA" as a family
    # column. Human Release-8 rows contain native miRNA labels.
    # Only labels explicitly tied to the 40 certified project miRNAs in
    # Release-8 metadata are authorized. No seed/name/arm inference.
    # ----------------------------------------------------------
    fam = pd.read_csv(ts_family_audit_path, dtype=str, keep_default_na=False)
    need_fam = {"project_mature_miRNA","targetscan_family"}
    miss = need_fam - set(fam.columns)
    if miss:
        raise RuntimeError(f"TARGETSCAN_FAMILY_AUDIT_COLUMNS_MISSING={sorted(miss)}")

    explicit_mature = set()
    label_to_ids = defaultdict(set)

    for _, r in fam.iterrows():
        mature = str(r["project_mature_miRNA"]).strip()
        if mature not in mature_to_id:
            continue
        mir_id = mature_to_id[mature]
        explicit_mature.add(mature)

        # Exact validated mature project label.
        label_to_ids[mature].add(mir_id)

        # Exact native MiRBase-ID from Release-8 metadata when preserved.
        if "targetscan_miRBase_ID_raw" in fam.columns:
            raw_id = str(r["targetscan_miRBase_ID_raw"]).strip()
            if raw_id:
                label_to_ids[raw_id].add(mir_id)

        # Exact family label from Release-8 metadata is also explicit.
        family = str(r["targetscan_family"]).strip()
        if family:
            label_to_ids[family].add(mir_id)

    if len(explicit_mature) != 40:
        raise RuntimeError(f"TARGETSCAN_EXPLICIT_FAMILY_COUNT_CHANGED={len(explicit_mature)}")

    unique_label_to_id = {
        label: next(iter(ids))
        for label, ids in label_to_ids.items()
        if len(ids) == 1
    }
    ambiguous_labels = {
        label for label, ids in label_to_ids.items() if len(ids) > 1
    }

    ts = assets["TARGETSCANHUMAN_8_DEFAULT"]
    header = pd.read_csv(ts, sep="\t", compression="zip", nrows=0)
    cols = list(header.columns)
    norm = {norm_col(c): c for c in cols}
    for k in ["genesymbol","genetaxid","mirna"]:
        if k not in norm:
            raise RuntimeError(f"TARGETSCAN_REQUIRED_COLUMN_MISSING={k}|columns={cols}")

    gene_col = norm["genesymbol"]
    tax_col = norm["genetaxid"]
    mirna_col = norm["mirna"]

    ts_rows = 0
    ts_human_rows = 0
    ts_explicit_label_rows = 0
    ts_ambig = 0
    ts_matched_records = 0
    observed_project_mirnas = set()

    for ch in pd.read_csv(
        ts, sep="\t", compression="zip",
        dtype=str, keep_default_na=False, chunksize=200000
    ):
        ts_rows += len(ch)
        h = ch.loc[ch[tax_col].astype(str).str.strip().eq("9606")]
        ts_human_rows += len(h)

        for _, r in h.iterrows():
            native_label = str(r[mirna_col]).strip()
            if native_label in ambiguous_labels:
                ts_ambig += 1
                continue

            mir_id = unique_label_to_id.get(native_label)
            if not mir_id:
                continue

            ts_explicit_label_rows += 1
            observed_project_mirnas.add(mir_id)

            gene, route = bridge.map_symbol(r[gene_col])
            if not gene:
                if route == "AMBIGUOUS_NO_SUPPORT":
                    ts_ambig += 1
                continue

            key = (mir_id, gene)
            if key in stable_keys:
                ts_support[key] += 1
                ts_matched_records += 1

        print(f"TARGETSCAN_PROGRESS_ROWS={ts_rows}", flush=True)

    if ts_explicit_label_rows <= 0:
        raise RuntimeError("TARGETSCAN_EXPLICIT_PROJECT_LABEL_ROWS_ZERO_AFTER_CORRECTION")
    if len(observed_project_mirnas) <= 0:
        raise RuntimeError("TARGETSCAN_PROJECT_MIRNAS_OBSERVED_ZERO_AFTER_CORRECTION")

    emit(res, "TARGETSCAN_MATCHING_COMPLETED", "YES")
    emit(res, "TARGETSCAN_MAPPING_CORRECTION",
         "PREDICTION_MIRNA_COLUMN_IS_NATIVE_MIRNA_LABEL_NOT_FAMILY_COLUMN")
    emit(res, "TARGETSCAN_LABEL_MATCHING_MODE",
         "EXACT_RELEASE8_METADATA_LABEL_ONLY")
    emit(res, "TARGETSCAN_FAMILY_INFERENCE_FROM_NAME_OR_SEQUENCE", "NO")
    emit(res, "TARGETSCAN_SOURCE_ROWS", ts_rows)
    emit(res, "TARGETSCAN_HUMAN_ROWS", ts_human_rows)
    emit(res, "TARGETSCAN_EXPLICIT_FAMILY_PROJECT_MIRNAS", 40)
    emit(res, "TARGETSCAN_EXPLICIT_METADATA_LABELS", len(unique_label_to_id))
    emit(res, "TARGETSCAN_HUMAN_ROWS_WITH_EXPLICIT_PROJECT_LABEL", ts_explicit_label_rows)
    emit(res, "TARGETSCAN_PROJECT_MIRNAS_OBSERVED_IN_PREDICTION_TABLE",
         len(observed_project_mirnas))
    emit(res, "TARGETSCAN_MATCHED_EDGES", len(ts_support))

    # ----------------------------------------------------------
    # miRDB 6 — score >80 + certified RefSeq bridge only
    # ----------------------------------------------------------
    rb = pd.read_csv(mirdb_bridge_path, compression="gzip", dtype=str, keep_default_na=False)
    need_rb = {
        "refseq_rna_accession",
        "mapped_project_gene_symbol",
        "mapping_status",
        "eligible_to_support_miRDB_route",
    }
    miss = need_rb - set(rb.columns)
    if miss:
        raise RuntimeError(f"MIRDB_REFSEQ_BRIDGE_COLUMNS_MISSING={sorted(miss)}")

    eligible = rb.loc[
        rb["eligible_to_support_miRDB_route"].eq("YES")
        & rb["mapping_status"].eq("UNIQUE_PROJECT_GENE")
    ]
    refseq_to_gene = {}
    for _, r in eligible.iterrows():
        acc = strip_ver(r["refseq_rna_accession"])
        gene = str(r["mapped_project_gene_symbol"]).strip()
        if not acc or gene not in project_genes:
            continue
        if acc in refseq_to_gene and refseq_to_gene[acc] != gene:
            raise RuntimeError(f"MIRDB_REFSEQ_BRIDGE_COLLISION={acc}")
        refseq_to_gene[acc] = gene

    rb_ambig = int(rb["mapping_ambiguity"].eq("YES").sum()) if "mapping_ambiguity" in rb.columns else 0
    rb_unresolved = int(rb["mapping_status"].astype(str).str.startswith("UNRESOLVED").sum())

    mirdb = assets["MIRDB_V6_HUMAN"]
    mirdb_rows = 0
    mirdb_human = 0
    mirdb_project_mirna = 0
    mirdb_high_conf = 0
    mirdb_unmapped = 0
    mirdb_matched_records = 0
    invalid_scores = 0

    with gzip.open(mirdb, "rt", encoding="utf-8-sig", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\r\n").split("\t")
            if len(parts) < 3:
                continue
            mirdb_rows += 1
            mir = parts[0].strip()
            if not mir.startswith("hsa-"):
                continue
            mirdb_human += 1
            if mir not in mature_to_id:
                continue
            mirdb_project_mirna += 1
            try:
                score = float(parts[2].strip())
            except Exception:
                invalid_scores += 1
                continue
            if not (score > MIRDB_THRESHOLD):
                continue
            mirdb_high_conf += 1
            acc = strip_ver(parts[1])
            gene = refseq_to_gene.get(acc)
            if not gene:
                mirdb_unmapped += 1
                continue
            key = (mature_to_id[mir], gene)
            if key in stable_keys:
                mirdb_support[key] += 1
                old = mirdb_max.get(key, -np.inf)
                if score > old:
                    mirdb_max[key] = score
                mirdb_matched_records += 1

    if invalid_scores:
        raise RuntimeError(f"MIRDB_PROJECT_ROWS_INVALID_SCORE={invalid_scores}")

    emit(res, "MIRDB_MATCHING_COMPLETED", "YES")
    emit(res, "MIRDB_SCORE_RULE", "STRICT_GT_80")
    emit(res, "MIRDB_SOURCE_ROWS", mirdb_rows)
    emit(res, "MIRDB_MATCHED_EDGES", len(mirdb_support))

    # ----------------------------------------------------------
    # Edge evidence matrix
    # ----------------------------------------------------------
    out = pd.DataFrame({
        "miRNA_ID": stable["miRNA_id"].to_numpy(copy=True),
        "mRNA_SYMBOL": stable["mRNA_id"].to_numpy(copy=True),
        "association_score": stable["partial_spearman_rho"].to_numpy(copy=True),
        "stability_score": stable["bootstrap_selection_frequency"].to_numpy(copy=True),
    })

    tar_flags, ts_flags, mdb_flags = [], [], []
    tar_n, ts_n, mdb_n, mdb_s = [], [], [], []

    for mir, gene in zip(out["miRNA_ID"], out["mRNA_SYMBOL"]):
        key = (str(mir), str(gene))
        a = int(tar_support.get(key, 0))
        b = int(ts_support.get(key, 0))
        c = int(mirdb_support.get(key, 0))
        tar_flags.append("YES" if a else "NO")
        ts_flags.append("YES" if b else "NO")
        mdb_flags.append("YES" if c else "NO")
        tar_n.append(a)
        ts_n.append(b)
        mdb_n.append(c)
        mdb_s.append(mirdb_max.get(key, np.nan))

    out["TarBase_support"] = tar_flags
    out["TargetScan_support"] = ts_flags
    out["miRDB_support"] = mdb_flags
    out["TarBase_source_record_count"] = tar_n
    out["TargetScan_source_record_count"] = ts_n
    out["miRDB_high_confidence_record_count"] = mdb_n
    out["miRDB_max_score"] = mdb_s

    pred_count = (
        out["TargetScan_support"].eq("YES").astype(int)
        + out["miRDB_support"].eq("YES").astype(int)
    )
    out["prediction_database_count"] = pred_count
    out["prediction_consensus_both"] = np.where(pred_count.eq(2), "YES", "NO")
    out["evidence_class"] = np.where(
        out["TarBase_support"].eq("YES"),
        "A_EXPERIMENTAL_SUPPORTED",
        np.where(
            pred_count.gt(0),
            "B_MULTI_DATABASE_PREDICTED",
            "C_ASSOCIATION_ONLY",
        ),
    )

    # hard identity/topology preservation
    if len(out) != EXPECTED_EDGES:
        raise RuntimeError("OUTPUT_EDGE_COUNT_CHANGED")
    if out.duplicated(["miRNA_ID","mRNA_SYMBOL"]).any():
        raise RuntimeError("DUPLICATE_EDGE_CREATION")
    if out["miRNA_ID"].tolist() != stable["miRNA_id"].tolist():
        raise RuntimeError("MIRNA_IDENTITY_OR_ORDER_CHANGED")
    if out["mRNA_SYMBOL"].tolist() != stable["mRNA_id"].tolist():
        raise RuntimeError("MRNA_IDENTITY_OR_ORDER_CHANGED")

    edge_matrix = outdir / "EDGE_EVIDENCE_MATRIX.csv"
    out.to_csv(edge_matrix, index=False, float_format="%.17g")

    rt = pd.read_csv(edge_matrix, dtype={"miRNA_ID":str,"mRNA_SYMBOL":str}, float_precision="round_trip")
    if len(rt) != EXPECTED_EDGES:
        raise RuntimeError("EDGE_MATRIX_ROUNDTRIP_ROW_COUNT_CHANGED")
    if rt["miRNA_ID"].tolist() != stable["miRNA_id"].tolist():
        raise RuntimeError("EDGE_MATRIX_ROUNDTRIP_MIRNA_CHANGED")
    if rt["mRNA_SYMBOL"].tolist() != stable["mRNA_id"].tolist():
        raise RuntimeError("EDGE_MATRIX_ROUNDTRIP_MRNA_CHANGED")
    if rt.duplicated(["miRNA_ID","mRNA_SYMBOL"]).any():
        raise RuntimeError("EDGE_MATRIX_ROUNDTRIP_DUPLICATES")

    def summary(path, db, matched, ambig, extra):
        row = {
            "database": db,
            "total_frozen_edges": EXPECTED_EDGES,
            "matched_edges": matched,
            "unmatched_edges": EXPECTED_EDGES - matched,
            "ambiguous_mappings": ambig,
            "database_coverage_percentage": 100.0 * matched / EXPECTED_EDGES,
        }
        row.update(extra)
        pd.DataFrame([row]).to_csv(path, index=False)

    summary(
        outdir/"TarBase_match_summary.csv",
        "DIANA-TarBase_v9",
        len(tar_support),
        tar_ambig,
        {
            "source_rows_scanned": tar_rows,
            "matched_source_records": tar_matched_records,
            "support_rule": "at_least_one_experimental_TarBase_v9_record",
        },
    )
    summary(
        outdir/"TargetScan_match_summary.csv",
        "TargetScanHuman_8.0",
        len(ts_support),
        ts_ambig,
        {
            "source_rows_scanned": ts_rows,
            "human_rows": ts_human_rows,
            "project_miRNAs_with_explicit_family_metadata": 40,
            "human_rows_with_explicit_project_label": ts_explicit_label_rows,
            "project_miRNAs_observed_in_prediction_table": len(observed_project_mirnas),
            "unique_explicit_metadata_labels": len(unique_label_to_id),
            "matched_source_records": ts_matched_records,
            "prediction_miRNA_column_semantics": "native_miRNA_label_not_family_column",
            "matching_mode": "exact_Release8_metadata_label_only",
            "family_inference_from_names_or_sequences": "NO",
        },
    )
    summary(
        outdir/"miRDB_match_summary.csv",
        "miRDB_6.0",
        len(mirdb_support),
        rb_ambig,
        {
            "source_rows_scanned": mirdb_rows,
            "human_rows": mirdb_human,
            "project_miRNA_rows": mirdb_project_mirna,
            "high_confidence_rows_score_gt_80": mirdb_high_conf,
            "high_confidence_rows_without_unique_bridge": mirdb_unmapped,
            "unresolved_bridge_accessions_no_support": rb_unresolved,
            "matched_source_records": mirdb_matched_records,
            "support_rule": "score_gt_80_and_unique_certified_RefSeq_bridge",
        },
    )

    class_order = [
        "A_EXPERIMENTAL_SUPPORTED",
        "B_MULTI_DATABASE_PREDICTED",
        "C_ASSOCIATION_ONLY",
    ]
    cc = out["evidence_class"].value_counts().reindex(class_order, fill_value=0)
    rows = [
        {
            "evidence_class": k,
            "edge_count": int(v),
            "percentage_of_11531": 100.0 * int(v) / EXPECTED_EDGES,
        }
        for k, v in cc.items()
    ]
    rows.append({
        "evidence_class": "PREDICTION_CONSENSUS_BOTH_TARGETSCAN_AND_MIRDB",
        "edge_count": int(out["prediction_consensus_both"].eq("YES").sum()),
        "percentage_of_11531": 100.0 * int(out["prediction_consensus_both"].eq("YES").sum()) / EXPECTED_EDGES,
    })
    pd.DataFrame(rows).to_csv(outdir/"D8A1_EVIDENCE_CLASS_SUMMARY.csv", index=False)

    pd.DataFrame([
        ["input_edge_count", EXPECTED_EDGES, len(stable), "PASS"],
        ["output_edge_count", EXPECTED_EDGES, len(out), "PASS"],
        ["duplicate_edge_count", 0, 0, "PASS"],
        ["miRNA_identity_changed", "NO", "NO", "PASS"],
        ["mRNA_identity_changed", "NO", "NO", "PASS"],
        ["edge_order_changed", "NO", "NO", "PASS"],
        ["edge_removed", 0, 0, "PASS"],
        ["edge_added", 0, 0, "PASS"],
        ["network_topology_changed", "NO", "NO", "PASS"],
    ], columns=["check","expected","observed","status"]).to_csv(
        outdir/"D8A1_EDGE_PRESERVATION_AUDIT.csv", index=False
    )

    pd.DataFrame([
        ["frozen_project_mRNA_symbols", EXPECTED_MRNA, len(project_genes), "PASS", "authoritative project IDs"],
        ["frozen_project_miRNA_identities", EXPECTED_MIRNA, len(project_mirna_ids), "PASS", "MIMAT|mature-miRNA"],
        ["miRBase22_1_exact_project_miRNA_validation", 41, 41, "PASS", "41/41 retained"],
        ["TargetScan_project_miRNAs_with_explicit_family_metadata", 40, len(explicit_mature), "PASS", "no inference for missing family"],
        ["miRDB_ambiguous_RefSeq_bridge_accessions", "NO_SUPPORT", rb_ambig, "PASS", "no guessing"],
        ["miRDB_unresolved_RefSeq_bridge_accessions", "NO_SUPPORT", rb_unresolved, "PASS", "no guessing"],
        ["TarBase_matched_edges", "ANNOTATION_ONLY", len(tar_support), "PASS", ""],
        ["TargetScan_matched_edges", "ANNOTATION_ONLY", len(ts_support), "PASS", ""],
        ["miRDB_matched_edges", "ANNOTATION_ONLY", len(mirdb_support), "PASS", ""],
    ], columns=["audit_item","expected","observed","status","notes"]).to_csv(
        outdir/"D8A1_IDENTIFIER_AUDIT.csv", index=False
    )

    spec = """GSE243219_D8A1_EXECUTION_SPECIFICATION
MODE=ANNOTATION_ONLY
FROZEN_INPUT_EDGES=11531
FROZEN_MRNA_FEATURES=4467
FROZEN_MIRNA_FEATURES=41
EDGE_REMOVAL_ALLOWED=NO
EDGE_ADDITION_ALLOWED=NO
GENE_MATCH_PRIORITY_1=EXACT_FROZEN_PROJECT_SYMBOL
GENE_MATCH_PRIORITY_2=UNIQUE_EXTERNAL_BRIDGE
AMBIGUOUS_EXTERNAL_BRIDGE=NO_SUPPORT
TARBASE_SUPPORT=AT_LEAST_ONE_EXPERIMENTAL_RECORD
TARGETSCAN_MAPPING=EXACT_PREDICTION_MIRNA_LABEL_VIA_EXPLICIT_RELEASE8_METADATA_ONLY
TARGETSCAN_FAMILY_INFERENCE_FROM_NAME_OR_SEQUENCE=NO
MIRDB_SUPPORT=SCORE_GT_80_AND_UNIQUE_CERTIFIED_REFSEQ_BRIDGE
MIRDB_AMBIGUOUS_OR_UNRESOLVED_BRIDGE=NO_SUPPORT_NO_GUESSING
EVIDENCE_CLASS_A=TARBASE_POSITIVE
EVIDENCE_CLASS_B=TARBASE_NEGATIVE_AND_TARGETSCAN_OR_MIRDB_POSITIVE
EVIDENCE_CLASS_C=NO_EXTERNAL_EVIDENCE
DE_RERUN=NO
NORMALIZATION_RERUN=NO
ASSOCIATION_RERUN=NO
NETWORK_REBUILDING_EXECUTED=NO
ACLA_EXECUTED=NO
FUNCTIONAL_ENRICHMENT_EXECUTED=NO
DRUG_ANALYSIS_EXECUTED=NO
"""
    (outdir/"D8A1_EXECUTION_SPECIFICATION.txt").write_text(spec, encoding="utf-8")

    emit(res, "OUTPUT_EDGE_COUNT", len(out))
    emit(res, "DUPLICATE_EDGE_COUNT", 0)
    emit(res, "MIRNA_IDENTITY_CHANGED", "NO")
    emit(res, "MRNA_SYMBOL_CHANGED", "NO")
    emit(res, "NETWORK_TOPOLOGY_CHANGED", "NO")
    emit(res, "CLASS_A_EXPERIMENTAL_SUPPORTED", int(cc["A_EXPERIMENTAL_SUPPORTED"]))
    emit(res, "CLASS_B_MULTI_DATABASE_PREDICTED", int(cc["B_MULTI_DATABASE_PREDICTED"]))
    emit(res, "CLASS_C_ASSOCIATION_ONLY", int(cc["C_ASSOCIATION_ONLY"]))
    emit(res, "PREDICTION_CONSENSUS_BOTH_TARGETSCAN_AND_MIRDB", int(out["prediction_consensus_both"].eq("YES").sum()))
    emit(res, "TARGET_DATABASE_EDGE_MATCHING_EXECUTED", "YES")
    emit(res, "TARGET_EVIDENCE_INTEGRATION", "PASS")
    emit(res, "D8A1_COMPLETE", "YES")
    emit(res, "NETWORK_REBUILDING_EXECUTED", "NO")
    emit(res, "ACLA_EXECUTED", "NO")
    emit(res, "READY_FOR_FINAL_MULTILAYER_NETWORK_CONSTRUCTION", "YES")
    emit(res, "READY_FOR_ACLA", "NO")
    emit(res, "STOP", "YES")

    result_json.write_text(json.dumps({"results":res}, indent=2, sort_keys=True), encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
