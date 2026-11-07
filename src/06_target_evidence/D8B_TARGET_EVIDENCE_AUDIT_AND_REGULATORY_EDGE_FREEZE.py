#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import sys
import traceback
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_EDGES = 11531
EXPECTED_MRNA = 4467
EXPECTED_MIRNA = 41

EXPECTED_TARBASE = 1972
EXPECTED_TARGETSCAN = 205
EXPECTED_MIRDB_GT80 = 118
EXPECTED_TS_MIRDB = 43
EXPECTED_ANY_EXTERNAL = 2079
EXPECTED_NO_EXTERNAL = 9452

EXPECTED_CLASS_A = 1972
EXPECTED_CLASS_B = 107
EXPECTED_CLASS_C = 9452


def sha256_file(path: Path, chunk: int = 8 * 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def normalize_support(series: pd.Series, name: str) -> pd.Series:
    s = series.astype(str).str.strip().str.upper()
    bad = sorted(set(s) - {"YES", "NO"})
    if bad:
        raise RuntimeError(f"{name}_INVALID_VALUES={bad}")
    return s.eq("YES")


def recertify_manifest(
    manifest_path: Path,
    expected_rows: int,
    label: str,
) -> tuple[int, list[str]]:
    if not manifest_path.is_file():
        raise RuntimeError(f"{label}_MANIFEST_MISSING={manifest_path}")
    rows = pd.read_csv(manifest_path, dtype=str, keep_default_na=False)
    if len(rows) != expected_rows:
        raise RuntimeError(
            f"{label}_MANIFEST_ROW_COUNT_CHANGED "
            f"expected={expected_rows} observed={len(rows)}"
        )
    required = {"full_path", "size_bytes", "SHA256"}
    missing = required - set(rows.columns)
    if missing:
        raise RuntimeError(
            f"{label}_MANIFEST_COLUMNS_MISSING={sorted(missing)}"
        )

    mismatches = []
    for _, r in rows.iterrows():
        p = Path(str(r["full_path"]))
        if not p.is_file():
            mismatches.append(f"MISSING:{p}")
            continue
        if p.stat().st_size != int(r["size_bytes"]):
            mismatches.append(f"SIZE:{p}")
            continue
        observed = sha256_file(p)
        expected = str(r["SHA256"]).lower()
        if observed != expected:
            mismatches.append(f"SHA256:{p}")

    if mismatches:
        raise RuntimeError(
            f"{label}_HASH_RECERTIFICATION_FAILED="
            + "||".join(mismatches[:20])
        )
    return len(rows), mismatches


def exact_numeric_equal(a: pd.Series, b: pd.Series) -> bool:
    av = pd.to_numeric(a, errors="coerce").to_numpy(dtype=float)
    bv = pd.to_numeric(b, errors="coerce").to_numpy(dtype=float)
    if av.shape != bv.shape:
        return False
    return bool(
        np.array_equal(np.isnan(av), np.isnan(bv))
        and np.array_equal(av[~np.isnan(av)], bv[~np.isnan(bv)])
    )


def main() -> int:
    if len(sys.argv) != 10:
        raise SystemExit(
            "usage: D8B_AUDIT.py "
            "<d8a1_manifest> <d8a1_decision> <d8a1_summary> "
            "<edge_matrix> <d7c_manifest> <d7c_edges> "
            "<d8a3_gene_audit> <outdir> <result_json>"
        )

    d8a1_manifest = Path(sys.argv[1])
    d8a1_decision = Path(sys.argv[2])
    d8a1_summary = Path(sys.argv[3])
    edge_matrix = Path(sys.argv[4])
    d7c_manifest = Path(sys.argv[5])
    d7c_edges = Path(sys.argv[6])
    gene_audit_path = Path(sys.argv[7])
    outdir = Path(sys.argv[8])
    result_json = Path(sys.argv[9])

    outdir.mkdir(parents=True, exist_ok=True)

    # Output paths
    full_class_path = outdir / "D8B_FULL_EDGE_CLASSIFICATION.csv"
    reg_freeze_path = outdir / "D8B_REGULATORY_EDGE_FREEZE.csv"
    nonreg_path = outdir / "D8B_NONREGULATORY_ASSOCIATION_EDGES.csv"
    summary_path = outdir / "D8B_REGULATORY_EDGE_SUMMARY.csv"
    overlap_path = outdir / "D8B_EVIDENCE_OVERLAP_AUDIT.csv"
    conservation_path = outdir / "D8B_EDGE_CONSERVATION_AUDIT.csv"
    spec_path = outdir / "D8B_EXECUTION_SPECIFICATION.txt"

    # ------------------------------------------------------------
    # 1) Authoritative input integrity
    # ------------------------------------------------------------
    d8a1_rows, _ = recertify_manifest(
        d8a1_manifest, 14, "D8A1_V2"
    )
    d7c_rows, _ = recertify_manifest(
        d7c_manifest, 11, "D7C"
    )

    if not d8a1_decision.is_file():
        raise RuntimeError(f"D8A1_V2_DECISION_MISSING={d8a1_decision}")
    if not d8a1_summary.is_file():
        raise RuntimeError(f"D8A1_V2_SUMMARY_MISSING={d8a1_summary}")

    decision_text = d8a1_decision.read_text(
        encoding="utf-8-sig", errors="replace"
    )
    summary_text = d8a1_summary.read_text(
        encoding="utf-8-sig", errors="replace"
    )

    required_tokens = [
        "PHASE_D8A1_V2_STATUS=PASS",
        "D8A1_V1_TARGETSCAN_PARSER_INVALID=YES",
        "FROZEN_INPUT_EDGES=11531",
        "OUTPUT_EDGES=11531",
        "DUPLICATE_EDGE_COUNT=0",
        "MIRNA_IDENTITY_CHANGED=NO",
        "MRNA_SYMBOL_CHANGED=NO",
        "TARBASE_MATCHED_EDGES=1972",
        "TARGETSCAN_MATCHED_EDGES=205",
        "MIRDB_MATCHED_EDGES=118",
        "CLASS_A_EXPERIMENTAL_SUPPORTED=1972",
        "CLASS_B_MULTI_DATABASE_PREDICTED=107",
        "CLASS_C_ASSOCIATION_ONLY=9452",
        "PREDICTION_CONSENSUS_BOTH_TARGETSCAN_AND_MIRDB=43",
        "TARGET_EVIDENCE_INTEGRATION=PASS",
        "D8A1_V2_COMPLETE=YES",
        "D8A1_COMPLETE=YES",
        "NETWORK_TOPOLOGY_CHANGED=NO",
        "NETWORK_REBUILDING_EXECUTED=NO",
        "ACLA_EXECUTED=NO",
        "STOP=YES",
    ]
    for tok in required_tokens:
        if tok not in decision_text and tok not in summary_text:
            raise RuntimeError(f"D8A1_V2_STATUS_TOKEN_MISSING={tok}")

    if not edge_matrix.is_file():
        raise RuntimeError("EDGE_EVIDENCE_MATRIX_EXISTS=NO")

    # ------------------------------------------------------------
    # 2) Read authoritative evidence matrix
    # ------------------------------------------------------------
    ev = pd.read_csv(
        edge_matrix,
        dtype={
            "miRNA_ID": str,
            "mRNA_SYMBOL": str,
            "TarBase_support": str,
            "TargetScan_support": str,
            "miRDB_support": str,
            "evidence_class": str,
        },
        float_precision="round_trip",
    )

    required_cols = {
        "miRNA_ID",
        "mRNA_SYMBOL",
        "association_score",
        "stability_score",
        "TarBase_support",
        "TargetScan_support",
        "miRDB_support",
        "miRDB_max_score",
        "prediction_database_count",
        "prediction_consensus_both",
        "evidence_class",
    }
    missing = required_cols - set(ev.columns)
    if missing:
        raise RuntimeError(
            f"EDGE_EVIDENCE_MATRIX_COLUMNS_MISSING={sorted(missing)}"
        )

    if len(ev) != EXPECTED_EDGES:
        raise RuntimeError(
            f"EDGE_EVIDENCE_ROWS_CHANGED={len(ev)}"
        )
    dup = int(ev.duplicated(["miRNA_ID", "mRNA_SYMBOL"]).sum())
    if dup != 0:
        raise RuntimeError(f"DUPLICATE_EDGE_COUNT={dup}")

    if ev["mRNA_SYMBOL"].nunique() != EXPECTED_MRNA:
        raise RuntimeError(
            f"MRNA_IDENTITIES_CHANGED={ev['mRNA_SYMBOL'].nunique()}"
        )
    if ev["miRNA_ID"].nunique() != EXPECTED_MIRNA:
        raise RuntimeError(
            f"MIRNA_IDENTITIES_CHANGED={ev['miRNA_ID'].nunique()}"
        )

    # ------------------------------------------------------------
    # 3) Independently compare with original D7C frozen association layer
    # ------------------------------------------------------------
    d7c = pd.read_csv(
        d7c_edges,
        compression="gzip",
        dtype={"mRNA_id": str, "miRNA_id": str},
        float_precision="round_trip",
    )
    if len(d7c) != EXPECTED_EDGES:
        raise RuntimeError(
            f"D7C_FROZEN_EDGE_COUNT_CHANGED={len(d7c)}"
        )
    if d7c.duplicated(["miRNA_id", "mRNA_id"]).any():
        raise RuntimeError("D7C_FROZEN_DUPLICATES_DETECTED")

    if ev["miRNA_ID"].tolist() != d7c["miRNA_id"].tolist():
        raise RuntimeError("MIRNA_IDENTITY_CHANGED=YES")
    if ev["mRNA_SYMBOL"].tolist() != d7c["mRNA_id"].tolist():
        raise RuntimeError("MRNA_SYMBOL_CHANGED=YES")

    if not exact_numeric_equal(
        ev["association_score"], d7c["partial_spearman_rho"]
    ):
        raise RuntimeError("ASSOCIATION_SCORE_CHANGED=YES")
    if not exact_numeric_equal(
        ev["stability_score"], d7c["bootstrap_selection_frequency"]
    ):
        raise RuntimeError("STABILITY_SCORE_CHANGED=YES")

    # D8A-V3 gene audit collision gate.
    gene_audit = pd.read_csv(
        gene_audit_path, dtype=str, keep_default_na=False
    )
    if len(gene_audit) != EXPECTED_MRNA:
        raise RuntimeError(
            f"D8A_V3_GENE_AUDIT_ROWS_CHANGED={len(gene_audit)}"
        )
    if set(gene_audit["project_mRNA_id"]) != set(ev["mRNA_SYMBOL"]):
        raise RuntimeError("D8A_V3_PROJECT_GENE_SET_CHANGED=YES")

    nonempty_ref = gene_audit[
        gene_audit["reference_current_symbol"].astype(str).ne("")
    ]
    collisions = int(
        (
            nonempty_ref.groupby("reference_current_symbol")[
                "project_mRNA_id"
            ].nunique() > 1
        ).sum()
    )
    if collisions != 0:
        raise RuntimeError(
            f"GENE_NORMALIZATION_COLLISIONS={collisions}"
        )

    # ------------------------------------------------------------
    # 4) Independently recompute evidence flags/counts
    # ------------------------------------------------------------
    tar = normalize_support(ev["TarBase_support"], "TarBase_support")
    ts = normalize_support(ev["TargetScan_support"], "TargetScan_support")
    mdb_flag = normalize_support(ev["miRDB_support"], "miRDB_support")

    mdb_score = pd.to_numeric(
        ev["miRDB_max_score"], errors="coerce"
    )
    mdb_gt80 = mdb_score.gt(80.0)

    # D8A1-V2 defined miRDB_support only from strict score > 80.
    if not np.array_equal(mdb_flag.to_numpy(), mdb_gt80.to_numpy()):
        mismatch_count = int((mdb_flag != mdb_gt80).sum())
        raise RuntimeError(
            f"MIRDB_SUPPORT_VS_SCORE_GT80_MISMATCHES={mismatch_count}"
        )

    # Support/source-record consistency where count columns exist.
    if "TarBase_source_record_count" in ev.columns:
        tc = pd.to_numeric(
            ev["TarBase_source_record_count"], errors="coerce"
        ).fillna(0)
        if int((tar != tc.gt(0)).sum()) != 0:
            raise RuntimeError(
                "TARBASE_SUPPORT_RECORD_COUNT_MISMATCH"
            )
    if "TargetScan_source_record_count" in ev.columns:
        sc = pd.to_numeric(
            ev["TargetScan_source_record_count"], errors="coerce"
        ).fillna(0)
        if int((ts != sc.gt(0)).sum()) != 0:
            raise RuntimeError(
                "TARGETSCAN_SUPPORT_RECORD_COUNT_MISMATCH"
            )
    if "miRDB_high_confidence_record_count" in ev.columns:
        mc = pd.to_numeric(
            ev["miRDB_high_confidence_record_count"], errors="coerce"
        ).fillna(0)
        if int((mdb_gt80 != mc.gt(0)).sum()) != 0:
            raise RuntimeError(
                "MIRDB_SUPPORT_RECORD_COUNT_MISMATCH"
            )

    tar_n = int(tar.sum())
    ts_n = int(ts.sum())
    mdb_n = int(mdb_gt80.sum())
    ts_mdb = ts & mdb_gt80
    ts_mdb_n = int(ts_mdb.sum())

    tar_ts = int((tar & ts).sum())
    tar_mdb = int((tar & mdb_gt80).sum())
    triple = int((tar & ts & mdb_gt80).sum())

    any_ext = tar | ts | mdb_gt80
    any_ext_n = int(any_ext.sum())
    no_ext_n = int((~any_ext).sum())

    # Required expected primary counts
    expected_checks = {
        "TARBASE_SUPPORTED": (tar_n, EXPECTED_TARBASE),
        "TARGETSCAN_SUPPORTED": (ts_n, EXPECTED_TARGETSCAN),
        "MIRDB_GT80_SUPPORTED": (mdb_n, EXPECTED_MIRDB_GT80),
        "TARGETSCAN_AND_MIRDB_SUPPORTED": (ts_mdb_n, EXPECTED_TS_MIRDB),
        "ANY_EXTERNAL_EVIDENCE": (any_ext_n, EXPECTED_ANY_EXTERNAL),
        "NO_EXTERNAL_EVIDENCE": (no_ext_n, EXPECTED_NO_EXTERNAL),
    }
    for name, (observed, expected) in expected_checks.items():
        if observed != expected:
            raise RuntimeError(
                f"{name}_COUNT_MISMATCH expected={expected} observed={observed}"
            )

    # Recompute D8A1 annotation class counts independently.
    class_a = tar
    class_b = (~tar) & (ts | mdb_gt80)
    class_c = (~tar) & (~ts) & (~mdb_gt80)

    if int(class_a.sum()) != EXPECTED_CLASS_A:
        raise RuntimeError("D8A1_CLASS_A_RECOMPUTE_MISMATCH")
    if int(class_b.sum()) != EXPECTED_CLASS_B:
        raise RuntimeError("D8A1_CLASS_B_RECOMPUTE_MISMATCH")
    if int(class_c.sum()) != EXPECTED_CLASS_C:
        raise RuntimeError("D8A1_CLASS_C_RECOMPUTE_MISMATCH")

    # Also compare row-level D8A1 annotation class labels.
    recomputed_annotation = np.where(
        class_a,
        "A_EXPERIMENTAL_SUPPORTED",
        np.where(
            class_b,
            "B_MULTI_DATABASE_PREDICTED",
            "C_ASSOCIATION_ONLY",
        ),
    )
    if not np.array_equal(
        ev["evidence_class"].astype(str).to_numpy(),
        recomputed_annotation,
    ):
        raise RuntimeError(
            "D8A1_EVIDENCE_CLASS_ROWLEVEL_RECOMPUTE_MISMATCH"
        )

    # ------------------------------------------------------------
    # 5) Frozen D8 regulatory rule
    # ------------------------------------------------------------
    consensus = ts & mdb_gt80

    # R1: TarBase, not predictor consensus
    r1 = tar & (~consensus)
    # R2: predictor consensus, no TarBase
    r2 = (~tar) & consensus
    # R3: TarBase + predictor consensus
    r3 = tar & consensus
    # N: all remaining stable association edges
    nclass = ~(r1 | r2 | r3)

    reg_eligible = r1 | r2 | r3

    r1_n = int(r1.sum())
    r2_n = int(r2.sum())
    r3_n = int(r3.sum())
    nonreg_n = int(nclass.sum())
    reg_n = int(reg_eligible.sum())

    ts_mdb_with_tar = triple
    ts_mdb_without_tar = int((consensus & ~tar).sum())

    if ts_mdb_with_tar + ts_mdb_without_tar != EXPECTED_TS_MIRDB:
        raise RuntimeError("TS_MIRDB_PARTITION_FAILED")

    expected_unique_reg = (
        EXPECTED_TARBASE + EXPECTED_TS_MIRDB - triple
    )
    if reg_n != expected_unique_reg:
        raise RuntimeError(
            f"UNIQUE_REGULATORY_EDGE_FORMULA_MISMATCH "
            f"formula={expected_unique_reg} observed={reg_n}"
        )

    if r1_n + r2_n + r3_n + nonreg_n != EXPECTED_EDGES:
        raise RuntimeError("REGULATORY_CLASS_PARTITION_FAILED")

    # Predictor-only audit counts (regardless of TarBase)
    ts_only = ts & (~mdb_gt80)
    mdb_only = mdb_gt80 & (~ts)
    xor_pred = ts ^ mdb_gt80

    ts_only_n = int(ts_only.sum())
    mdb_only_n = int(mdb_only.sum())
    xor_pred_n = int(xor_pred.sum())

    # Mandatory safety gate:
    # single-predictor edges WITHOUT TarBase must never become regulatory.
    # Predictor-XOR edges with TarBase remain regulatory solely via Route A.
    single_predictor_nonexperimental = (~tar) & xor_pred
    single_predictor_wrongly_reg = int(
        (single_predictor_nonexperimental & reg_eligible).sum()
    )
    if single_predictor_wrongly_reg != 0:
        raise RuntimeError(
            "SINGLE_PREDICTOR_EDGES_CLASSIFIED_REGULATORY="
            f"{single_predictor_wrongly_reg}"
        )

    # ------------------------------------------------------------
    # 6) Build full classification and frozen subsets
    # ------------------------------------------------------------
    full = ev.copy()

    # Required alias
    full["miRDB_score"] = mdb_score
    full["TargetScan_and_miRDB_consensus"] = np.where(
        consensus, "YES", "NO"
    )
    full["regulatory_eligible"] = np.where(
        reg_eligible, "YES", "NO"
    )

    route = np.full(len(full), "NOT_REGULATORY_ELIGIBLE", dtype=object)
    route[r1.to_numpy()] = "ROUTE_A_TARBASE"
    route[r2.to_numpy()] = "ROUTE_B_TARGETSCAN_AND_MIRDB_GT80"
    route[r3.to_numpy()] = "ROUTE_A_AND_ROUTE_B"
    full["regulatory_route"] = route

    reg_class = np.full(
        len(full),
        "ASSOCIATION_ONLY_NOT_REGULATORY",
        dtype=object,
    )
    reg_class[r1.to_numpy()] = "REGULATORY_EXPERIMENTAL"
    reg_class[r2.to_numpy()] = "REGULATORY_PREDICTED_CONSENSUS"
    reg_class[r3.to_numpy()] = "REGULATORY_EXPERIMENTAL_AND_PREDICTED"
    full["regulatory_class"] = reg_class

    # The edge key and original row order remain authoritative.
    if full["miRNA_ID"].tolist() != ev["miRNA_ID"].tolist():
        raise RuntimeError("D8B_MIRNA_IDENTITY_CHANGED=YES")
    if full["mRNA_SYMBOL"].tolist() != ev["mRNA_SYMBOL"].tolist():
        raise RuntimeError("D8B_MRNA_SYMBOL_CHANGED=YES")
    if full.duplicated(["miRNA_ID", "mRNA_SYMBOL"]).any():
        raise RuntimeError("D8B_FULL_CLASSIFICATION_DUPLICATES")

    regulatory = full.loc[reg_eligible].copy()
    nonregulatory = full.loc[nclass].copy()

    dup_reg = int(
        regulatory.duplicated(["miRNA_ID", "mRNA_SYMBOL"]).sum()
    )
    dup_nonreg = int(
        nonregulatory.duplicated(["miRNA_ID", "mRNA_SYMBOL"]).sum()
    )
    if dup_reg != 0 or dup_nonreg != 0:
        raise RuntimeError(
            f"D8B_SUBSET_DUPLICATES reg={dup_reg} nonreg={dup_nonreg}"
        )
    if len(regulatory) + len(nonregulatory) != EXPECTED_EDGES:
        raise RuntimeError("FULL_EDGE_CONSERVATION_FAILED")

    reg_keys = set(
        zip(regulatory["miRNA_ID"], regulatory["mRNA_SYMBOL"])
    )
    nonreg_keys = set(
        zip(nonregulatory["miRNA_ID"], nonregulatory["mRNA_SYMBOL"])
    )
    if reg_keys & nonreg_keys:
        raise RuntimeError("REGULATORY_NONREGULATORY_KEY_OVERLAP")
    if reg_keys | nonreg_keys != set(
        zip(ev["miRNA_ID"], ev["mRNA_SYMBOL"])
    ):
        raise RuntimeError("FULL_EDGE_KEY_CONSERVATION_FAILED")

    # Place required columns first, preserve all other evidence columns after.
    required_first = [
        "miRNA_ID",
        "mRNA_SYMBOL",
        "association_score",
        "stability_score",
        "TarBase_support",
        "TargetScan_support",
        "miRDB_support",
        "miRDB_score",
        "TargetScan_and_miRDB_consensus",
        "regulatory_eligible",
        "regulatory_route",
        "regulatory_class",
    ]
    remaining = [c for c in full.columns if c not in required_first]
    full = full[required_first + remaining]
    regulatory = regulatory[required_first + remaining]
    nonregulatory = nonregulatory[required_first + remaining]

    full.to_csv(full_class_path, index=False, float_format="%.17g")
    regulatory.to_csv(
        reg_freeze_path, index=False, float_format="%.17g"
    )
    nonregulatory.to_csv(
        nonreg_path, index=False, float_format="%.17g"
    )

    # ------------------------------------------------------------
    # 7) Independent output round-trip conservation
    # ------------------------------------------------------------
    reg_rt = pd.read_csv(
        reg_freeze_path,
        dtype={"miRNA_ID": str, "mRNA_SYMBOL": str},
        float_precision="round_trip",
    )
    nonreg_rt = pd.read_csv(
        nonreg_path,
        dtype={"miRNA_ID": str, "mRNA_SYMBOL": str},
        float_precision="round_trip",
    )
    full_rt = pd.read_csv(
        full_class_path,
        dtype={"miRNA_ID": str, "mRNA_SYMBOL": str},
        float_precision="round_trip",
    )

    if len(full_rt) != EXPECTED_EDGES:
        raise RuntimeError("D8B_FULL_CLASSIFICATION_ROUNDTRIP_ROWS_CHANGED")
    if len(reg_rt) != reg_n:
        raise RuntimeError("D8B_REGULATORY_FREEZE_ROUNDTRIP_ROWS_CHANGED")
    if len(nonreg_rt) != nonreg_n:
        raise RuntimeError("D8B_NONREGULATORY_ROUNDTRIP_ROWS_CHANGED")
    if full_rt.duplicated(["miRNA_ID", "mRNA_SYMBOL"]).any():
        raise RuntimeError("D8B_FULL_ROUNDTRIP_DUPLICATES")
    if reg_rt.duplicated(["miRNA_ID", "mRNA_SYMBOL"]).any():
        raise RuntimeError("D8B_REGULATORY_ROUNDTRIP_DUPLICATES")
    if nonreg_rt.duplicated(["miRNA_ID", "mRNA_SYMBOL"]).any():
        raise RuntimeError("D8B_NONREGULATORY_ROUNDTRIP_DUPLICATES")

    # ------------------------------------------------------------
    # 8) Summary / overlap / conservation outputs
    # ------------------------------------------------------------
    pd.DataFrame([
        {
            "metric": "FULL_STABLE_MRNA_MIRNA_ASSOCIATION_LAYER",
            "value": EXPECTED_EDGES,
        },
        {
            "metric": "REGULATORY_ELIGIBLE_SUBSET",
            "value": reg_n,
        },
        {
            "metric": "NONREGULATORY_ASSOCIATION_EDGES",
            "value": nonreg_n,
        },
        {
            "metric": "REGULATORY_EXPERIMENTAL",
            "value": r1_n,
        },
        {
            "metric": "REGULATORY_PREDICTED_CONSENSUS",
            "value": r2_n,
        },
        {
            "metric": "REGULATORY_EXPERIMENTAL_AND_PREDICTED",
            "value": r3_n,
        },
    ]).to_csv(summary_path, index=False)

    overlap_metrics = [
        ("TARBASE_SUPPORTED", tar_n),
        ("TARGETSCAN_SUPPORTED", ts_n),
        ("MIRDB_GT80_SUPPORTED", mdb_n),
        ("TARGETSCAN_AND_MIRDB_SUPPORTED", ts_mdb_n),
        ("TARBASE_AND_TARGETSCAN", tar_ts),
        ("TARBASE_AND_MIRDB", tar_mdb),
        ("TARBASE_AND_TARGETSCAN_AND_MIRDB", triple),
        ("ANY_EXTERNAL_EVIDENCE", any_ext_n),
        ("NO_EXTERNAL_EVIDENCE", no_ext_n),
        ("TS_MIRDB_CONSENSUS_TOTAL", ts_mdb_n),
        ("TS_MIRDB_CONSENSUS_WITH_TARBASE", ts_mdb_with_tar),
        ("TS_MIRDB_CONSENSUS_WITHOUT_TARBASE", ts_mdb_without_tar),
        ("TARGETSCAN_ONLY_EDGES", ts_only_n),
        ("MIRDB_ONLY_EDGES", mdb_only_n),
        ("TARGETSCAN_OR_MIRDB_BUT_NOT_BOTH", xor_pred_n),
        (
            "SINGLE_PREDICTOR_NONEXPERIMENTAL_EDGES",
            int(single_predictor_nonexperimental.sum()),
        ),
        (
            "SINGLE_PREDICTOR_EDGES_CLASSIFIED_REGULATORY",
            single_predictor_wrongly_reg,
        ),
    ]
    pd.DataFrame(
        overlap_metrics, columns=["metric", "value"]
    ).to_csv(overlap_path, index=False)

    conservation = pd.DataFrame([
        {
            "check": "D8A1_V2_manifest_recertified",
            "expected": "14/14",
            "observed": f"{d8a1_rows}/14",
            "status": "PASS",
        },
        {
            "check": "D7C_manifest_recertified",
            "expected": "11/11",
            "observed": f"{d7c_rows}/11",
            "status": "PASS",
        },
        {
            "check": "full_edge_universe",
            "expected": EXPECTED_EDGES,
            "observed": len(full),
            "status": "PASS",
        },
        {
            "check": "regulatory_plus_nonregulatory",
            "expected": EXPECTED_EDGES,
            "observed": len(regulatory) + len(nonregulatory),
            "status": "PASS",
        },
        {
            "check": "duplicate_regulatory_edges",
            "expected": 0,
            "observed": dup_reg,
            "status": "PASS",
        },
        {
            "check": "duplicate_nonregulatory_edges",
            "expected": 0,
            "observed": dup_nonreg,
            "status": "PASS",
        },
        {
            "check": "miRNA_identity_changed",
            "expected": "NO",
            "observed": "NO",
            "status": "PASS",
        },
        {
            "check": "mRNA_symbol_changed",
            "expected": "NO",
            "observed": "NO",
            "status": "PASS",
        },
        {
            "check": "association_score_changed",
            "expected": "NO",
            "observed": "NO",
            "status": "PASS",
        },
        {
            "check": "stability_score_changed",
            "expected": "NO",
            "observed": "NO",
            "status": "PASS",
        },
        {
            "check": "gene_normalization_collisions",
            "expected": 0,
            "observed": collisions,
            "status": "PASS",
        },
        {
            "check": "single_predictor_nonexperimental_classified_regulatory",
            "expected": 0,
            "observed": single_predictor_wrongly_reg,
            "status": "PASS",
        },
    ])
    conservation.to_csv(conservation_path, index=False)

    spec = f"""GSE243219_D8B_EXECUTION_SPECIFICATION
MODE=INDEPENDENT_TARGET_EVIDENCE_AUDIT_AND_REGULATORY_EDGE_FREEZE
AUTHORITATIVE_D8A1_V2_RUN={d8a1_manifest.parent}
FULL_STABLE_MRNA_MIRNA_ASSOCIATION_LAYER=11531
MRNA_FEATURES=4467
MIRNA_FEATURES=41
D8B_REGULATORY_RULE=TARBASE OR (TARGETSCAN AND MIRDB_GT80)
ROUTE_A=TARBASE_SUPPORT_YES
ROUTE_B=TARGETSCAN_SUPPORT_YES_AND_MIRDB_SCORE_STRICTLY_GT_80
SINGLE_PREDICTOR_ONLY_ELIGIBLE=NO
D8A1_ANNOTATION_CLASS_B_USED_AS_REGULATORY_RULE=NO
GENE_IDENTITY=EXACT_FROZEN_PROJECT_GENE_SYMBOL
MIRNA_IDENTITY=VALIDATED_MATURE_MIRNA_ID
EDGE_REMOVAL_FROM_FULL_ASSOCIATION_LAYER=NO
EDGE_ADDITION_TO_FULL_ASSOCIATION_LAYER=NO
NETWORK_CONSTRUCTION_EXECUTED=NO
MULTILAYER_NETWORK_BUILDING_EXECUTED=NO
ACLA_EXECUTED=NO
MODULE_DETECTION_EXECUTED=NO
HUB_ANALYSIS_EXECUTED=NO
ENRICHMENT_EXECUTED=NO
DRUG_REPOSITIONING_EXECUTED=NO
RULE_CHANGE_ALLOWED_DOWNSTREAM=NO
STOP_AFTER_D8B=YES
"""
    spec_path.write_text(spec, encoding="utf-8")

    # ------------------------------------------------------------
    # 9) Result JSON used by PowerShell to create final status/manifest
    # ------------------------------------------------------------
    result = {
        "D8B_STATUS": "PASS",
        "INPUT_EDGES": EXPECTED_EDGES,
        "OUTPUT_EDGE_UNIVERSE": EXPECTED_EDGES,
        "MRNA_FEATURES": EXPECTED_MRNA,
        "MIRNA_FEATURES": EXPECTED_MIRNA,
        "TARBASE_SUPPORTED": tar_n,
        "TARGETSCAN_SUPPORTED": ts_n,
        "MIRDB_GT80_SUPPORTED": mdb_n,
        "TARGETSCAN_AND_MIRDB_SUPPORTED": ts_mdb_n,
        "TARBASE_AND_TARGETSCAN": tar_ts,
        "TARBASE_AND_MIRDB": tar_mdb,
        "TARBASE_AND_TARGETSCAN_AND_MIRDB": triple,
        "ANY_EXTERNAL_EVIDENCE": any_ext_n,
        "NO_EXTERNAL_EVIDENCE": no_ext_n,
        "TS_MIRDB_CONSENSUS_TOTAL": ts_mdb_n,
        "TS_MIRDB_CONSENSUS_WITH_TARBASE": ts_mdb_with_tar,
        "TS_MIRDB_CONSENSUS_WITHOUT_TARBASE": ts_mdb_without_tar,
        "TARGETSCAN_ONLY_EDGES": ts_only_n,
        "MIRDB_ONLY_EDGES": mdb_only_n,
        "TARGETSCAN_OR_MIRDB_BUT_NOT_BOTH": xor_pred_n,
        "UNIQUE_REGULATORY_EDGES": reg_n,
        "NONREGULATORY_ASSOCIATION_EDGES": nonreg_n,
        "REGULATORY_EXPERIMENTAL": r1_n,
        "REGULATORY_PREDICTED_CONSENSUS": r2_n,
        "REGULATORY_EXPERIMENTAL_AND_PREDICTED": r3_n,
        "FULL_EDGE_CONSERVATION": "PASS",
        "DUPLICATE_REGULATORY_EDGES": dup_reg,
        "DUPLICATE_NONREGULATORY_EDGES": dup_nonreg,
        "SINGLE_PREDICTOR_ONLY_ELIGIBLE": "NO",
        "SINGLE_PREDICTOR_EDGES_CLASSIFIED_REGULATORY":
            single_predictor_wrongly_reg,
        "MIRNA_IDENTITY_CHANGED": "NO",
        "MRNA_SYMBOL_CHANGED": "NO",
        "GENE_NORMALIZATION_COLLISIONS": collisions,
        "NETWORK_CONSTRUCTION_EXECUTED": "NO",
        "ACLA_EXECUTED": "NO",
        "READY_FOR_D9_MULTILAYER_NETWORK_CONSTRUCTION": "YES",
        "STOP": "YES",
    }
    result_json.write_text(
        json.dumps(result, indent=2, sort_keys=True),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
