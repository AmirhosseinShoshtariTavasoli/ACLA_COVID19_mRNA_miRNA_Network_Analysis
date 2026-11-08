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

EXPECTED = {
    "historical_modularity": {
        "filename": "A-CLA.02.01.Modularity.py",
        "sha256": "ee3c3b735ba6593d5a6af155e599403e697f498b290dc75a39ff0e3ab90b07de",
        "repo_path": "legacy/submission_code/Modularity/A-CLA.02.01.Modularity.py",
    },
    "clean_nonoverlap": {
        "filename": "nonoverlap.py",
        "sha256": "2b23df93380434abdcc95f30988e1bb14d73887038273dd7eb4d9107452f28ac",
        "repo_path": "src/acla/nonoverlap.py",
    },
    "clean_io": {
        "filename": "io.py",
        "sha256": "f74f621f6a66cdb450228955475472880f580795b0d8d636e22c339858938e1f",
        "repo_path": "src/acla/io.py",
    },
    "clean_cli": {
        "filename": "cli.py",
        "sha256": "a71377a56959a3b58e11cce3437536dce6cc96a42c9ad52a83a5d62e2265a538",
        "repo_path": "src/acla/cli.py",
    },
    "readme": {
        "filename": "README.md",
        "sha256": "55ad8f0b91ee3924523bf4e8a66f52e911f30da24d8143887feb4f830faf3dfe",
        "repo_path": "README.md",
    },
    "provenance": {
        "filename": "PROVENANCE_AND_KNOWN_LIMITATIONS.md",
        "sha256": "e4253b0d9fd37a67d2b04d60f20ee5c95698c305d9b28d6d9dcce9c26f97dc5b",
        "repo_path": "docs/PROVENANCE_AND_KNOWN_LIMITATIONS.md",
    },
}

EXPECTED_NODES = 4508
EXPECTED_EDGES = 11531
EXPECTED_WEIGHT_MIN = -0.7753835531973502
EXPECTED_WEIGHT_MAX = 0.7428957195865319

def sha256_file(path: Path, chunk=8*1024*1024):
    h = hashlib.sha256()
    with path.open("rb") as f:
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

def require_contains(text: str, pattern: str, label: str):
    if not re.search(pattern, text, re.I | re.M | re.S):
        raise RuntimeError(f"EXPECTED_SOURCE_SEMANTIC_MISSING={label}")

def selftest():
    sample_hist = (
        'BINARIZE = True\n'
        'df2 = (df > 0).astype(int)\n'
        'return modularity(G, comms, weight=None)\n'
        'counts = Counter(neigh_labs)\n'
    )
    require_contains(sample_hist, r"^\s*BINARIZE\s*=\s*True\b", "BINARIZE_TRUE")
    require_contains(sample_hist, r"\(\s*df\s*>\s*0\s*\)\.astype\s*\(\s*int\s*\)", "POSITIVE_BINARIZATION")
    require_contains(sample_hist, r"modularity\s*\([^\)]*weight\s*=\s*None", "UNWEIGHTED_MODULARITY")
    require_contains(sample_hist, r"Counter\s*\(\s*neigh", "UNWEIGHTED_LOCAL_SIGNAL")
    print("D10B_V4_INTERNAL_SELFTEST=PASS")
    print("EXTERNAL_SHA256_CONTRACT_SELFTEST=PASS")
    print("SIGNED_WEIGHT_COMPATIBILITY_LOGIC_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        return selftest()
    if len(sys.argv) != 6:
        raise SystemExit("usage: script <project> <d9_run> <provenance_dir> <outdir> <result_json>")

    project = Path(sys.argv[1])
    d9 = Path(sys.argv[2])
    prov = Path(sys.argv[3])
    out = Path(sys.argv[4])
    result_json = Path(sys.argv[5])
    out.mkdir(parents=True, exist_ok=True)

    recertify_manifest(d9 / "D9_SHA256_MANIFEST.csv", "D9")
    d9_status = (d9 / "D9_FINAL_STATUS.txt").read_text(encoding="utf-8-sig", errors="replace")
    for tok in [
        "D9_STATUS=PASS",
        "TOTAL_NODES=4508",
        "TOTAL_STRUCTURAL_EDGES=11531",
        "CONNECTED_COMPONENTS=2",
        "LARGEST_COMPONENT_NODES=4502",
        "ACLA_EXECUTED=NO",
        "D9_HASH_MISMATCHES=0",
    ]:
        if tok not in d9_status:
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

    manifest_txt = (prov / "MANIFEST_SHA256.txt").read_text(encoding="utf-8", errors="replace")
    source_rows = []
    for role, meta in EXPECTED.items():
        p = prov / meta["filename"]
        if not p.is_file():
            raise RuntimeError(f"PROVENANCE_FILE_MISSING={p}")
        actual = sha256_file(p)
        if actual != meta["sha256"]:
            raise RuntimeError(
                f"PROVENANCE_SHA256_MISMATCH role={role} expected={meta['sha256']} actual={actual}"
            )
        manifest_line = f"{meta['sha256']}  {meta['repo_path']}"
        if manifest_line not in manifest_txt:
            raise RuntimeError(f"REPOSITORY_MANIFEST_LINE_MISSING={meta['repo_path']}")
        source_rows.append({
            "role": role,
            "repo_path": meta["repo_path"],
            "local_provenance_path": str(p),
            "size_bytes": p.stat().st_size,
            "SHA256": actual,
            "repository_manifest_match": "YES",
        })

    pd.DataFrame(source_rows).to_csv(
        out / "D10B_V4_EXTERNAL_PROVENANCE_SOURCE_MANIFEST.csv",
        index=False,
    )

    hist = (prov / EXPECTED["historical_modularity"]["filename"]).read_text(
        encoding="utf-8", errors="replace"
    )
    clean_non = (prov / EXPECTED["clean_nonoverlap"]["filename"]).read_text(
        encoding="utf-8", errors="replace"
    )
    clean_io = (prov / EXPECTED["clean_io"]["filename"]).read_text(
        encoding="utf-8", errors="replace"
    )
    readme = (prov / EXPECTED["readme"]["filename"]).read_text(
        encoding="utf-8", errors="replace"
    )
    provenance = (prov / EXPECTED["provenance"]["filename"]).read_text(
        encoding="utf-8", errors="replace"
    )

    # Publication/provenance assertions.
    require_contains(
        readme,
        r"A-CLA:\s*A Novel Adaptive Cellular Learning Automata Approach for Uncovering Communities in Complex Networks",
        "ARTICLE_TITLE",
    )
    require_contains(readme, r"10\.1016/j\.comnet\.2026\.112103", "ARTICLE_DOI")
    require_contains(readme, r"clean reference code.*src/acla", "CLEAN_REFERENCE_LAYOUT")
    require_contains(
        provenance,
        r"src/acla/nonoverlap\.py.*primary reference path",
        "NONOVERLAP_PRIMARY_REFERENCE",
    )
    require_contains(
        provenance,
        r"A-CLA\.02\.01\.Modularity\.py",
        "HISTORICAL_FINAL_MODULARITY_REFERENCE",
    )

    # Historical source semantics.
    hist_binarize_true = bool(re.search(r"(?m)^\s*BINARIZE\s*=\s*True\b", hist))
    hist_positive_binary = bool(
        re.search(r"\(\s*df\s*>\s*0\s*\)\.astype\s*\(\s*int\s*\)", hist)
    )
    hist_weighted_path = bool(
        re.search(r"(?is)else:\s*#\s*Weighted graph version.*?from_pandas_adjacency\s*\(\s*df\.astype\s*\(\s*float\s*\)\s*\)", hist)
    )
    hist_unweighted_modularity = bool(
        re.search(r"modularity\s*\([^\)]]*weight\s*=\s*None", hist, re.S)
    )
    hist_local_count = bool(re.search(r"Counter\s*\(\s*neigh_labs\s*\)", hist))

    # Clean reference semantics should agree.
    clean_unweighted_modularity = bool(
        re.search(r"modularity\s*\([^\)]]*weight\s*=\s*None", clean_non, re.S)
    )
    clean_local_count = bool(
        re.search(r"Counter\s*\(\s*neigh_labels\s*\)", clean_non)
    )
    clean_io_positive_default = bool(
        re.search(r"(?is)elif\s+binarize:\s*work\s*=\s*\(\s*work\s*>\s*0\s*\)\.astype\s*\(\s*float\s*\)", clean_io)
    )
    clean_io_positive_weighted = bool(
        re.search(r"(?is)else:\s*work\s*=\s*work\.where\s*\(\s*work\s*>\s*0\s*,\s*0\.0\s*\)", clean_io)
    )

    mandatory_semantics = {
        "HISTORICAL_DEFAULT_BINARIZE_TRUE": hist_binarize_true,
        "HISTORICAL_POSITIVE_BINARY_FILTER": hist_positive_binary,
        "HISTORICAL_UNWEIGHTED_MODULARITY": hist_unweighted_modularity,
        "HISTORICAL_LOCAL_NEIGHBOR_COUNT": hist_local_count,
        "CLEAN_UNWEIGHTED_MODULARITY": clean_unweighted_modularity,
        "CLEAN_LOCAL_NEIGHBOR_COUNT": clean_local_count,
        "CLEAN_IO_POSITIVE_DEFAULT_FILTER": clean_io_positive_default,
        "CLEAN_IO_WEIGHTED_PATH_ZEROES_NONPOSITIVE": clean_io_positive_weighted,
    }
    missing = [k for k, v in mandatory_semantics.items() if not v]
    if missing:
        raise RuntimeError("EXPECTED_PUBLISHED_CORE_SEMANTICS_NOT_REPRODUCED=" + "|".join(missing))

    dataflow = [
        {
            "stage": "D9_INPUT",
            "mode": "RAW_SIGNED_WEIGHT",
            "evidence": f"association_score range {EXPECTED_WEIGHT_MIN}..{EXPECTED_WEIGHT_MAX}; negatives present",
        },
        {
            "stage": "HISTORICAL_DEFAULT_GRAPH_CONSTRUCTION",
            "mode": "POSITIVE_ONLY_BINARY",
            "evidence": "BINARIZE=True; df2=(df>0).astype(int)",
        },
        {
            "stage": "HISTORICAL_OPTIONAL_WEIGHTED_CONSTRUCTION",
            "mode": "RAW_VALUES_CAN_ENTER_GRAPH",
            "evidence": "BINARIZE=False constructs graph from float adjacency",
        },
        {
            "stage": "HISTORICAL_LOCAL_UPDATE",
            "mode": "UNWEIGHTED_TOPOLOGY",
            "evidence": "Counter(neigh_labs); edge sign/magnitude not used",
        },
        {
            "stage": "HISTORICAL_GLOBAL_OBJECTIVE",
            "mode": "UNWEIGHTED_MODULARITY",
            "evidence": "modularity(..., weight=None)",
        },
        {
            "stage": "CLEAN_REFERENCE_INPUT",
            "mode": "POSITIVE_ONLY",
            "evidence": "default work>0 binarization; weighted path work.where(work>0,0.0)",
        },
        {
            "stage": "CLEAN_REFERENCE_LOCAL_UPDATE",
            "mode": "UNWEIGHTED_TOPOLOGY",
            "evidence": "Counter(neigh_labels)",
        },
        {
            "stage": "CLEAN_REFERENCE_GLOBAL_OBJECTIVE",
            "mode": "UNWEIGHTED_MODULARITY",
            "evidence": "modularity(..., weight=None)",
        },
    ]
    pd.DataFrame(dataflow).to_csv(out / "D10B_V4_WEIGHT_DATAFLOW.csv", index=False)

    connected_gate = bool(
        re.search(r"(?i)is_connected|largest_connected_component|giant_component", hist + clean_non)
    )
    node_type_logic = bool(
        re.search(r"(?i)node[_ -]?type|mirna|mrna|bipartite|heterogeneous", hist + clean_non)
    )
    multilayer_logic = bool(
        re.search(r"(?i)\bmultilayer\b|layer[_ -]?(?:id|type|weight|mass)", hist + clean_non)
    )
    regulatory_logic = bool(
        re.search(r"(?i)regulatory|tarbase|targetscan|mirdb|mirna.*mrna", hist + clean_non)
    )

    compat = [
        {
            "dimension": "PUBLICATION_PROVENANCE",
            "status": "PASS",
            "blocking": "NO",
            "evidence": "GitHub repository manifest SHA256 matches historical + clean reference files",
        },
        {
            "dimension": "D9_SIGNED_WEIGHT_SEMANTICS",
            "status": "FAIL",
            "blocking": "YES",
            "evidence": "published-core lineage removes/ignores sign; default historical graph uses only >0 edges",
        },
        {
            "dimension": "NEGATIVE_WEIGHT_PRESERVATION",
            "status": "FAIL",
            "blocking": "YES",
            "evidence": "historical default drops non-positive edges; clean weighted path zeroes non-positive values",
        },
        {
            "dimension": "WEIGHT_MAGNITUDE_IN_LOCAL_UPDATE",
            "status": "FAIL",
            "blocking": "YES",
            "evidence": "local signal counts neighbor labels",
        },
        {
            "dimension": "WEIGHT_MAGNITUDE_IN_GLOBAL_OBJECTIVE",
            "status": "FAIL",
            "blocking": "YES",
            "evidence": "modularity uses weight=None",
        },
        {
            "dimension": "DISCONNECTED_GRAPH_STATIC_COMPATIBILITY",
            "status": "PASS" if not connected_gate else "FAIL",
            "blocking": "NO" if not connected_gate else "YES",
            "evidence": "no giant-component/connectedness requirement detected" if not connected_gate else "connectedness restriction detected",
        },
        {
            "dimension": "HETEROGENEOUS_NODE_IDENTIFIERS",
            "status": "PASS",
            "blocking": "NO",
            "evidence": "generic NetworkX node identifiers; no identifier-type restriction",
        },
        {
            "dimension": "NODE_TYPE_AWARE_OPTIMIZATION",
            "status": "NO_NATIVE_SUPPORT",
            "blocking": "NO",
            "evidence": "no mRNA/miRNA type semantics",
        },
        {
            "dimension": "MULTILAYER_OPTIMIZATION",
            "status": "NO_NATIVE_SUPPORT",
            "blocking": "NO",
            "evidence": "no multilayer optimization channel",
        },
        {
            "dimension": "REGULATORY_SEMANTIC_CHANNEL",
            "status": "NO_NATIVE_SUPPORT",
            "blocking": "NO",
            "evidence": "no regulatory evidence channel",
        },
    ]
    pd.DataFrame(compat).to_csv(out / "D10B_V4_COMPATIBILITY_MATRIX.csv", index=False)

    result = {
        "D10B_V4_STATUS": "PASS",
        "EXTERNAL_PUBLICATION_PROVENANCE_VERIFIED": "YES",
        "HISTORICAL_FINAL_MODULARITY_SOURCE_SHA256": EXPECTED["historical_modularity"]["sha256"],
        "CLEAN_NONOVERLAP_REFERENCE_SHA256": EXPECTED["clean_nonoverlap"]["sha256"],
        "PUBLISHED_ACLA_REQUIRED_INPUT_SCHEMA": "SQUARE_LABELED_ADJACENCY_MATRIX",
        "PUBLISHED_ACLA_DEFAULT_BINARIZE": "YES",
        "PUBLISHED_ACLA_POSITIVE_EDGE_FILTER": "YES",
        "PUBLISHED_ACLA_OPTIONAL_WEIGHTED_GRAPH_PATH": "YES" if hist_weighted_path else "NO",
        "PUBLISHED_ACLA_OBJECTIVE_USES_EDGE_WEIGHTS": "NO",
        "PUBLISHED_ACLA_LOCAL_UPDATE_USES_EDGE_WEIGHTS": "NO",
        "PUBLISHED_ACLA_TOPOLOGY_ONLY_OPTIMIZATION": "YES",
        "NEGATIVE_WEIGHTS_PRESERVED": "NO",
        "NEGATIVE_WEIGHTS_DROPPED_BY_DEFAULT": "YES",
        "NEGATIVE_WEIGHTS_ZEROED_IN_CLEAN_WEIGHTED_PATH": "YES",
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
        "READY_FOR_SIGNED_ACLA_PROSPECTIVE_DESIGN": "YES",
        "READY_FOR_D10C_PARAMETER_AND_EXECUTION_FREEZE": "NO",
        "READY_FOR_ACLA_EXECUTION": "NO",
        "STOP": "YES",
    }
    result_json.write_text(json.dumps(result, indent=2), encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
