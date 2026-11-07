#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.metadata as md
import importlib.util
import json
import sys
import traceback
from pathlib import Path

EXPECTED_SOURCE_SHA="ee3c3b735ba6593d5a6af155e599403e697f498b290dc75a39ff0e3ab90b07de"

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk), b""):
            h.update(b)
    return h.hexdigest()

def canonical_partition(part):
    groups={}
    for node,lab in part.items():
        groups.setdefault(lab,[]).append(node)
    return tuple(sorted(tuple(sorted(v)) for v in groups.values()))

def result_template():
    return {
        "D10I_E4_STATUS":"NOT_EVALUATED",
        "NETWORKX_IMPORT":"NO",
        "PYTHON_LOUVAIN_IMPORT":"NO",
        "NETWORKX_VERSION":"",
        "PYTHON_LOUVAIN_VERSION":"",
        "BEST_PARTITION_AVAILABLE":"NO",
        "NONE_RANDOM_STATE_DETERMINISM":"NOT_EVALUATED",
        "EXPLICIT_RANDOM_STATE_DETERMINISM":"NOT_EVALUATED",
        "EXACT_PARTITION_DICT_REPEAT":"NOT_EVALUATED",
        "CANONICAL_PARTITION_REPEAT":"NOT_EVALUATED",
        "PUBLICATION_SOURCE_IMPORT":"NOT_EVALUATED",
        "PUBLICATION_SOURCE_HAS_LOUVAIN":"NOT_EVALUATED",
        "SOURCE_CODE_CHANGED":"NO",
        "D9_FILES_MODIFIED":"NO",
        "D10H_TOPOLOGY_MODIFIED":"NO",
        "PARAMETER_VALUES_CHANGED":"NO",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "GSE243219_ACLA_EXECUTED":"NO",
        "COMMUNITY_RESULTS_CREATED":"NO",
        "FAILURE_STAGE":"",
        "FAILURE_REASON":"",
        "READY_TO_RERUN_D10I":"NO",
        "READY_FOR_D10J_ORIGINAL_ACLA_EXECUTION":"NO",
        "READY_FOR_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }

def main():
    if len(sys.argv)!=3:
        raise SystemExit("usage: diagnostic <publication_source.py> <result.json>")
    source=Path(sys.argv[1])
    out=Path(sys.argv[2])
    r=result_template()

    try:
        import numpy as np
        import networkx as nx
        from community import community_louvain
        r["NETWORKX_IMPORT"]="YES"
        r["PYTHON_LOUVAIN_IMPORT"]="YES"
        r["NETWORKX_VERSION"]=nx.__version__
        r["PYTHON_LOUVAIN_VERSION"]=md.version("python-louvain")
        r["BEST_PARTITION_AVAILABLE"]="YES" if callable(community_louvain.best_partition) else "NO"
        if not callable(community_louvain.best_partition):
            raise RuntimeError("best_partition is not callable")
    except Exception:
        r["D10I_E4_STATUS"]="FAIL_CLOSED"
        r["FAILURE_STAGE"]="DEPENDENCY_IMPORT"
        r["FAILURE_REASON"]=traceback.format_exc()
        out.write_text(json.dumps(r,indent=2),encoding="utf-8")
        return 0

    # This directly tests the exact random_state=None behavior that the publication
    # source uses, without running the GSE243219 network.
    try:
        G=nx.karate_club_graph()

        np.random.seed(42)
        a=community_louvain.best_partition(G, random_state=None)

        np.random.seed(42)
        b=community_louvain.best_partition(G, random_state=None)

        exact=(a==b)
        canon=(canonical_partition(a)==canonical_partition(b))
        r["EXACT_PARTITION_DICT_REPEAT"]="YES" if exact else "NO"
        r["CANONICAL_PARTITION_REPEAT"]="YES" if canon else "NO"
        r["NONE_RANDOM_STATE_DETERMINISM"]="PASS" if exact and canon else "FAIL"

        # Independent smoke test of explicit random_state API.
        c=community_louvain.best_partition(G, random_state=42)
        d=community_louvain.best_partition(G, random_state=42)
        r["EXPLICIT_RANDOM_STATE_DETERMINISM"]="PASS" if c==d and canonical_partition(c)==canonical_partition(d) else "FAIL"

        if r["NONE_RANDOM_STATE_DETERMINISM"]!="PASS":
            raise RuntimeError(
                "random_state=None did not reproduce exact partition after resetting np.random.seed(42)"
            )
        if r["EXPLICIT_RANDOM_STATE_DETERMINISM"]!="PASS":
            raise RuntimeError("explicit random_state=42 did not reproduce exact partition")
    except Exception:
        r["D10I_E4_STATUS"]="FAIL_CLOSED"
        r["FAILURE_STAGE"]="LOUVAIN_DETERMINISM_FIXTURE"
        r["FAILURE_REASON"]=traceback.format_exc()
        out.write_text(json.dumps(r,indent=2),encoding="utf-8")
        return 0

    # Import the exact publication-provenanced source. Importing only; no graph
    # loading and no A-CLA community detection.
    try:
        if not source.is_file():
            raise RuntimeError(f"publication source missing: {source}")
        actual=sha256_file(source)
        if actual!=EXPECTED_SOURCE_SHA:
            raise RuntimeError(
                f"publication source SHA mismatch expected={EXPECTED_SOURCE_SHA} actual={actual}"
            )
        spec=importlib.util.spec_from_file_location("acla_e4_import_audit",source)
        mod=importlib.util.module_from_spec(spec)
        sys.modules["acla_e4_import_audit"]=mod
        spec.loader.exec_module(mod)
        r["PUBLICATION_SOURCE_IMPORT"]="PASS"
        r["PUBLICATION_SOURCE_HAS_LOUVAIN"]="YES" if getattr(mod,"HAS_LOUVAIN",False) else "NO"
        if not getattr(mod,"HAS_LOUVAIN",False):
            raise RuntimeError("publication source imported but HAS_LOUVAIN is False")
    except Exception:
        r["D10I_E4_STATUS"]="FAIL_CLOSED"
        r["FAILURE_STAGE"]="PUBLICATION_SOURCE_IMPORT"
        r["FAILURE_REASON"]=traceback.format_exc()
        out.write_text(json.dumps(r,indent=2),encoding="utf-8")
        return 0

    r["D10I_E4_STATUS"]="PASS"
    r["READY_TO_RERUN_D10I"]="YES"
    out.write_text(json.dumps(r,indent=2),encoding="utf-8")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
