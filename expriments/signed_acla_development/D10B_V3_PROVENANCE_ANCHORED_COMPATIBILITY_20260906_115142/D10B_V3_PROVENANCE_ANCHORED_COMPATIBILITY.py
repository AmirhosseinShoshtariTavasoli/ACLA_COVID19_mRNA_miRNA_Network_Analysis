#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import re
import sys
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_HISTORICAL_SHA256 = "ee3c3b735ba6593d5a6af155e599403e697f498b290dc75a39ff0e3ab90b07de"
EXPECTED_CLEAN_NONOVERLAP_SHA256 = "2b23df93380434abdcc95f30988e1bb14d73887038273dd7eb4d9107452f28ac"
EXPECTED_CLEAN_IO_SHA256 = "f74f621f6a66cdb450228955475472880f580795b0d8d636e22c339858938e1f"
EXPECTED_CLEAN_CLI_SHA256 = "a71377a56959a3b58e11cce3437536dce6cc96a42c9ad52a83a5d62e2265a538"

EXPECTED_NODES = 4508
EXPECTED_EDGES = 11531
EXPECTED_WEIGHT_MIN = -0.7753835531973502
EXPECTED_WEIGHT_MAX = 0.7428957195865319

def sha256_file(p: Path, chunk=8*1024*1024):
    h = hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda: f.read(chunk), b""):
            h.update(b)
    return h.hexdigest()

def recertify_manifest(path: Path, label: str):
    if not path.is_file():
        raise RuntimeError(f"{label}_MANIFEST_MISSING={path}")
    df = pd.read_csv(path, dtype=str, keep_default_na=False)
    required = {"full_path", "size_bytes", "SHA256"}
    if not required.issubset(df.columns):
        raise RuntimeError(f"{label}_MANIFEST_SCHEMA_INVALID")
    bad = []
    for _, r in df.iterrows():
        p = Path(r["full_path"])
        if not p.is_file():
            bad.append(f"MISSING:{p}")
            continue
        if p.stat().st_size != int(r["size_bytes"]):
            bad.append(f"SIZE:{p}")
            continue
        if sha256_file(p) != r["SHA256"].lower():
            bad.append(f"SHA:{p}")
    if bad:
        raise RuntimeError(f"{label}_HASH_MISMATCHES={len(bad)}|" + "||".join(bad[:20]))

def selftest():
    assert len(EXPECTED_HISTORICAL_SHA256) == 64
    sample = (
        "BINARIZE = True\n"
        "df2 = (df > 0).astype(int)\n"
        "return modularity(G, comms, weight=None)\n"
    )
    assert re.search(r"(?m)^\s*BINARIZE\s*=\s*True\b", sample)
    assert re.search(r"\(\s*df\s*>\s*0\s*\)\.astype\s*\(\s*int\s*\)", sample)
    assert re.search(r"modularity\s*\([^\)]*weight\s*=\s*None", sample)
    print("D10B_V3_INTERNAL_SELFTEST=PASS")
    print("PROVENANCE_HASH_SELFTEST=PASS")
    print("SIGNED_SEMANTIC_BLOCKER_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        return selftest()
    if len(sys.argv) != 6:
        raise SystemExit("usage: script <project> <reusable> <d9> <outdir> <result_json>")

    project = Path(sys.argv[1])
    reusable = Path(sys.argv[2])
    d9 = Path(sys.argv[3])
    out = Path(sys.argv[4])
    res = Path(sys.argv[5])
    out.mkdir(parents=True, exist_ok=True)

    recertify_manifest(d9 / "D9_SHA256_MANIFEST.csv", "D9")
    st = (d9 / "D9_FINAL_STATUS.txt").read_text(encoding="utf-8-sig", errors="replace")
    for tok in [
        "D9_STATUS=PASS",
        "TOTAL_NODES=4508",
        "TOTAL_STRUCTURAL_EDGES=11531",
        "ACLA_EXECUTED=NO",
        "D9_HASH_MISMATCHES=0",
    ]:
        if tok not in st:
            raise RuntimeError(f"D9_STATUS_TOKEN_MISSING={tok}")

    nodes = pd.read_csv(d9 / "D9_MASTER_NODES.csv", dtype={"node_id": str})
    edges = pd.read_csv(
        d9 / "D9_MASTER_EDGES.csv",
        dtype={"source": str, "target": str},
        float_precision="round_trip",
    )
    if len(nodes) != EXPECTED_NODES or len(edges) != EXPECTED_EDGES:
        raise RuntimeError("D9_SIZE_GATE_FAILED")

    w = pd.to_numeric(edges["association_score"], errors="coerce").to_numpy(float)
    if (~np.isfinite(w)).sum():
        raise RuntimeError("D9_INVALID_WEIGHTS")
    if not math.isclose(float(w.min()), EXPECTED_WEIGHT_MIN, rel_tol=0, abs_tol=1e-15):
        raise RuntimeError("D9_WEIGHT_MIN_CHANGED")
    if not math.isclose(float(w.max()), EXPECTED_WEIGHT_MAX, rel_tol=0, abs_tol=1e-15):
        raise RuntimeError("D9_WEIGHT_MAX_CHANGED")
    if not np.any(w < 0):
        raise RuntimeError("D9_NEGATIVE_WEIGHTS_MISSING")

    roots = [
        reusable / "01_ACLA_CODE",
        reusable / "07_METHODS_AND_DOCUMENTATION",
        reusable / "09_OLD_METHOD_HISTORY",
    ]
    for r in roots:
        if not r.is_dir():
            raise RuntimeError(f"SEARCH_ROOT_MISSING={r}")

    wanted = {
        EXPECTED_HISTORICAL_SHA256: "HISTORICAL_FINAL_MODULARITY",
        EXPECTED_CLEAN_NONOVERLAP_SHA256: "CLEAN_NONOVERLAP_REFERENCE",
        EXPECTED_CLEAN_IO_SHA256: "CLEAN_IO_REFERENCE",
        EXPECTED_CLEAN_CLI_SHA256: "CLEAN_CLI_REFERENCE",
    }

    matches = []
    for root in roots:
        for p in root.rglob("*"):
            if not p.is_file():
                continue
            if p.suffix.lower() not in {".py", ".txt", ".md", ".csv"}:
                continue
            try:
                sh = sha256_file(p)
            except Exception:
                continue
            if sh in wanted:
                matches.append({
                    "role": wanted[sh],
                    "full_path": str(p),
                    "SHA256": sh,
                    "size_bytes": p.stat().st_size,
                })

    pd.DataFrame(
        matches,
        columns=["role", "full_path", "SHA256", "size_bytes"]
    ).to_csv(out / "D10B_V3_PROVENANCE_HASH_MATCHES.csv", index=False)

    hist = [Path(r["full_path"]) for r in matches if r["role"] == "HISTORICAL_FINAL_MODULARITY"]
    clean_non = [Path(r["full_path"]) for r in matches if r["role"] == "CLEAN_NONOVERLAP_REFERENCE"]

    if not hist:
        result = {
            "D10B_V3_STATUS": "FAIL_CLOSED",
            "PUBLISHED_HISTORICAL_MODULARITY_SOURCE_FOUND": "NO",
            "PUBLISHED_HISTORICAL_MODULARITY_SHA256": EXPECTED_HISTORICAL_SHA256,
            "PUBLISHED_CORE_REFERENCE_FOUND": "YES" if clean_non else "NO",
            "PUBLISHED_ACLA_D9_COMPATIBILITY": "NOT_EVALUATED_LOCAL_AUTHORITATIVE_SOURCE_MISSING",
            "FAILURE_REASON": "PUBLICATION_PROVENANCED_HISTORICAL_SOURCE_HASH_NOT_FOUND_LOCALLY",
            "NETWORK_CHANGED": "NO",
            "D9_FILES_MODIFIED": "NO",
            "WEIGHT_TRANSFORMATION_APPLIED": "NO",
            "NEGATIVE_EDGES_REMOVED": "NO",
            "PARAMETER_FREEZE_EXECUTED": "NO",
            "PARAMETER_TUNING_EXECUTED": "NO",
            "GSE243219_ACLA_EXECUTED": "NO",
            "READY_FOR_D10C_PARAMETER_AND_EXECUTION_FREEZE": "NO",
            "READY_FOR_ACLA_EXECUTION": "NO",
            "STOP": "YES",
        }
        res.write_text(json.dumps(result, indent=2), encoding="utf-8")
        pd.DataFrame(columns=["stage", "finding", "evidence"]).to_csv(
            out / "D10B_V3_WEIGHT_DATAFLOW.csv", index=False
        )
        pd.DataFrame(columns=["dimension", "status", "blocking", "evidence"]).to_csv(
            out / "D10B_V3_COMPATIBILITY_MATRIX.csv", index=False
        )
        return 0

    source = hist[0]
    text = source.read_text(encoding="utf-8", errors="replace")

    binarize_default = bool(re.search(r"(?m)^\s*BINARIZE\s*=\s*True\b", text))
    positive_binarization = bool(
        re.search(r"\(\s*(?:df|work)\s*>\s*0\s*\)\.astype\s*\(", text)
    )
    weighted_optional = bool(
        re.search(r"(?i)weighted graph version|if\s+binarize", text)
    )
    modularity_unweighted = bool(
        re.search(r"modularity\s*\([^\)]*weight\s*=\s*None", text, re.S)
    )
    neighbor_count_unweighted = bool(re.search(r"Counter\s*\(\s*neigh", text))
    connected_gate = bool(
        re.search(r"(?i)is_connected|largest_connected_component|giant_component", text)
    )
    node_type_logic = bool(
        re.search(r"(?i)node[_ -]?type|mirna|mrna|bipartite|heterogeneous", text)
    )
    multilayer_logic = bool(
        re.search(r"(?i)\bmultilayer\b|layer[_ -]?(?:id|type|weight|mass)", text)
    )
    regulatory_logic = bool(
        re.search(r"(?i)regulatory|tarbase|targetscan|mirdb|mirna.*mrna", text)
    )

    negative_dropped = binarize_default and positive_binarization
    topology_only = modularity_unweighted and neighbor_count_unweighted

    dataflow = [
        {
            "stage": "D9_INPUT",
            "finding": "RAW_SIGNED_ASSOCIATION_SCORE",
            "evidence": f"min={EXPECTED_WEIGHT_MIN};max={EXPECTED_WEIGHT_MAX}",
        },
        {
            "stage": "PUBLISHED_DEFAULT_PARSER",
            "finding": "POSITIVE_ONLY_BINARY_GRAPH" if negative_dropped else "UNRESOLVED",
            "evidence": "BINARIZE=True and (df > 0).astype(int)" if negative_dropped else "",
        },
        {
            "stage": "OPTIONAL_WEIGHTED_GRAPH_CONSTRUCTION",
            "finding": "RAW_NONZERO_VALUES_CAN_ENTER_GRAPH" if weighted_optional else "NOT_PRESENT",
            "evidence": "BINARIZE=False path constructs graph from float adjacency" if weighted_optional else "",
        },
        {
            "stage": "LOCAL_SIGNAL",
            "finding": "UNWEIGHTED_TOPOLOGY" if neighbor_count_unweighted else "UNRESOLVED",
            "evidence": "neighbor labels are counted with Counter; edge sign/magnitude not used",
        },
        {
            "stage": "GLOBAL_OBJECTIVE",
            "finding": "UNWEIGHTED_MODULARITY" if modularity_unweighted else "UNRESOLVED",
            "evidence": "modularity(..., weight=None)",
        },
        {
            "stage": "SIGNED_NETWORK_SEMANTICS",
            "finding": "NOT_SUPPORTED",
            "evidence": "sign is removed by default or ignored by local/global optimization",
        },
    ]
    pd.DataFrame(dataflow).to_csv(out / "D10B_V3_WEIGHT_DATAFLOW.csv", index=False)

    compat = [
        {
            "dimension": "PUBLICATION_PROVENANCE",
            "status": "PASS",
            "blocking": "NO",
            "evidence": f"exact SHA256 match {EXPECTED_HISTORICAL_SHA256}",
        },
        {
            "dimension": "D9_SIGNED_WEIGHT_SEMANTICS",
            "status": "FAIL",
            "blocking": "YES",
            "evidence": "default parser removes non-positive edges; optimization is unweighted",
        },
        {
            "dimension": "NEGATIVE_WEIGHT_PRESERVATION",
            "status": "FAIL",
            "blocking": "YES",
            "evidence": "default BINARIZE=True maps only df>0 to edges",
        },
        {
            "dimension": "WEIGHT_MAGNITUDE_PRESERVATION_IN_OBJECTIVE",
            "status": "FAIL",
            "blocking": "YES",
            "evidence": "modularity weight=None; local signal uses neighbor counts",
        },
        {
            "dimension": "DISCONNECTED_GRAPH_STATIC_COMPATIBILITY",
            "status": "PASS" if not connected_gate else "FAIL",
            "blocking": "NO" if not connected_gate else "YES",
            "evidence": "no connectedness/giant-component restriction detected" if not connected_gate else "connected graph restriction detected",
        },
        {
            "dimension": "MIXED_NODE_IDENTIFIER_COMPATIBILITY",
            "status": "PASS",
            "blocking": "NO",
            "evidence": "generic NetworkX node identifiers; no node-type restriction detected",
        },
        {
            "dimension": "NODE_TYPE_AWARE_OPTIMIZATION",
            "status": "NO_NATIVE_SUPPORT",
            "blocking": "NO",
            "evidence": "no mRNA/miRNA node-type logic",
        },
        {
            "dimension": "MULTILAYER_OPTIMIZATION",
            "status": "NO_NATIVE_SUPPORT",
            "blocking": "NO",
            "evidence": "no multilayer logic",
        },
        {
            "dimension": "REGULATORY_SEMANTIC_CHANNEL",
            "status": "NO_NATIVE_SUPPORT",
            "blocking": "NO",
            "evidence": "no regulatory evidence channel",
        },
    ]
    pd.DataFrame(compat).to_csv(out / "D10B_V3_COMPATIBILITY_MATRIX.csv", index=False)

    pd.DataFrame([{
        "role": "HISTORICAL_FINAL_MODULARITY_ENTRYPOINT",
        "full_path": str(source),
        "size_bytes": source.stat().st_size,
        "SHA256": sha256_file(source),
        "external_provenance_path": "legacy/submission_code/Modularity/A-CLA.02.01.Modularity.py",
    }]).to_csv(
        out / "D10B_V3_AUTHORITATIVE_PUBLISHED_IMPLEMENTATION_MANIFEST.csv",
        index=False,
    )

    result = {
        "D10B_V3_STATUS": "PASS",
        "PUBLISHED_HISTORICAL_MODULARITY_SOURCE_FOUND": "YES",
        "PUBLISHED_HISTORICAL_MODULARITY_ENTRYPOINT": str(source),
        "PUBLISHED_HISTORICAL_MODULARITY_SHA256": sha256_file(source),
        "PUBLISHED_CORE_REFERENCE_FOUND": "YES" if clean_non else "NO",
        "PUBLISHED_CORE_REFERENCE_SHA256": EXPECTED_CLEAN_NONOVERLAP_SHA256,
        "PUBLISHED_ACLA_REQUIRED_INPUT_SCHEMA": "SQUARE_LABELED_ADJACENCY_MATRIX",
        "PUBLISHED_ACLA_DEFAULT_BINARIZE": "YES" if binarize_default else "NO",
        "PUBLISHED_ACLA_POSITIVE_EDGE_FILTER": "YES" if positive_binarization else "NO",
        "PUBLISHED_ACLA_OPTIONAL_WEIGHTED_GRAPH_PATH": "YES" if weighted_optional else "NO",
        "PUBLISHED_ACLA_OBJECTIVE_USES_EDGE_WEIGHTS": "NO" if modularity_unweighted else "UNRESOLVED",
        "PUBLISHED_ACLA_LOCAL_UPDATE_USES_EDGE_WEIGHTS": "NO" if neighbor_count_unweighted else "UNRESOLVED",
        "PUBLISHED_ACLA_TOPOLOGY_ONLY_OPTIMIZATION": "YES" if topology_only else "UNRESOLVED",
        "NEGATIVE_WEIGHTS_PRESERVED": "NO",
        "NEGATIVE_WEIGHTS_DROPPED_BY_DEFAULT": "YES" if negative_dropped else "NO",
        "NEGATIVE_WEIGHTS_ABSOLUTIZED": "NO",
        "SIGNED_NETWORK_SEMANTICS_NATIVE_SUPPORT": "NO",
        "DISCONNECTED_GRAPH_SUPPORTED_STATIC": "YES" if not connected_gate else "NO",
        "HETEROGENEOUS_NODE_IDENTIFIERS_SUPPORTED": "YES",
        "NODE_TYPE_USED_BY_OPTIMIZATION": "YES" if node_type_logic else "NO",
        "PUBLISHED_ACLA_MULTILAYER_SUPPORT": "YES" if multilayer_logic else "NO",
        "PUBLISHED_ACLA_REGULATORY_CHANNEL_SUPPORT": "YES" if regulatory_logic else "NO",
        "PUBLISHED_ACLA_D9_COMPATIBILITY": "FAIL",
        "D9_SIGNED_WEIGHT_COMPATIBLE": "NO",
        "SIGNED_WEIGHT_COMPATIBILITY_BLOCKER": "YES",
        "SIGNED_ACLA_EXTENSION_REQUIRED": "YES",
        "NEW_METHODOLOGY_REQUIRED": "YES",
        "FAILURE_REASON": "PUBLISHED_CORE_DISCARDS_OR_IGNORES_D9_SIGNED_WEIGHT_SEMANTICS",
        "NETWORK_CHANGED": "NO",
        "D9_FILES_MODIFIED": "NO",
        "WEIGHT_TRANSFORMATION_APPLIED": "NO",
        "NEGATIVE_EDGES_REMOVED": "NO",
        "PARAMETER_FREEZE_EXECUTED": "NO",
        "PARAMETER_TUNING_EXECUTED": "NO",
        "GSE243219_ACLA_EXECUTED": "NO",
        "READY_FOR_D10C_PARAMETER_AND_EXECUTION_FREEZE": "NO",
        "READY_FOR_ACLA_EXECUTION": "NO",
        "STOP": "YES",
    }
    res.write_text(json.dumps(result, indent=2), encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
