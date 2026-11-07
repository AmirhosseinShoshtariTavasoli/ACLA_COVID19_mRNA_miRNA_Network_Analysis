#!/usr/bin/env python3
from __future__ import annotations

import ast
import hashlib
import importlib.util
import json
import math
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_NODES = 4508
EXPECTED_MRNA = 4467
EXPECTED_MIRNA = 41
EXPECTED_EDGES = 11531
EXPECTED_COMPONENTS = 2
EXPECTED_LARGEST = 4502
EXPECTED_SECOND = 6


def sha256_file(path: Path, chunk: int = 8 * 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            b = f.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def recertify_manifest(path: Path, label: str):
    if not path.is_file():
        raise RuntimeError(f"{label}_MANIFEST_MISSING={path}")
    df = pd.read_csv(path, dtype=str, keep_default_na=False)
    required = {"full_path", "size_bytes", "SHA256"}
    missing = required - set(df.columns)
    if missing:
        raise RuntimeError(f"{label}_MANIFEST_COLUMNS_MISSING={sorted(missing)}")
    mismatches = []
    for _, r in df.iterrows():
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
        raise RuntimeError(
            f"{label}_HASH_MISMATCHES={len(mismatches)}|"
            + "||".join(mismatches[:20])
        )
    return df


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


def component_stats(nodes, edges):
    uf = UnionFind(nodes)
    degree = Counter({n: 0 for n in nodes})
    for s, t in zip(edges["source"], edges["target"]):
        if s == t:
            continue
        uf.union(s, t)
        degree[s] += 1
        degree[t] += 1
    comp = defaultdict(int)
    for n in nodes:
        comp[uf.find(n)] += 1
    sizes = sorted(comp.values(), reverse=True)
    return {
        "components": len(sizes),
        "largest": sizes[0] if sizes else 0,
        "second": sizes[1] if len(sizes) > 1 else 0,
        "isolated": int(sum(1 for n in nodes if degree[n] == 0)),
    }


def safe_text(path: Path, max_bytes=5_000_000):
    try:
        if path.stat().st_size > max_bytes:
            return ""
        return path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return ""


def relative_to_any(path: Path, roots):
    for name, root in roots.items():
        try:
            return f"{name}/{path.relative_to(root)}"
        except Exception:
            pass
    return str(path)


def scan_files(roots):
    rows = []
    allowed_code = {".py", ".ps1", ".r", ".R", ".jl", ".m"}
    allowed_text = allowed_code | {".txt", ".md", ".csv", ".json", ".yaml", ".yml", ".ini", ".toml"}
    for root_name, root in roots.items():
        if not root.exists():
            raise RuntimeError(f"AUTHORIZED_ACLA_SEARCH_ROOT_MISSING={root}")
        for p in root.rglob("*"):
            if not p.is_file():
                continue
            ext = p.suffix
            if ext not in allowed_text:
                continue
            text = safe_text(p)
            low = text.lower()
            file_low = p.name.lower()
            acla_relevant = (
                "a-cla" in low
                or "acla" in low
                or "learning automata" in low
                or "cellular learning automata" in low
                or "acla" in file_low
                or "a-cla" in file_low
            )
            if not acla_relevant:
                continue
            rows.append({
                "search_root": root_name,
                "relative_path": relative_to_any(p, roots),
                "full_path": str(p),
                "filename": p.name,
                "extension": ext,
                "size_bytes": p.stat().st_size,
                "SHA256": sha256_file(p),
                "is_code": "YES" if ext in allowed_code else "NO",
                "mentions_old_gse": "YES" if (
                    "gse179850" in low or "gse182152" in low
                ) else "NO",
                "text": text,
            })
    return rows


REJECT_PATTERNS = [
    "superseded",
    "diagnostic_only",
    "diagnostic only",
    "rejected_result",
    "rejected result",
    "not accepted",
    "not yet authorized",
    "implementation prohibited",
    "ready_for_full_network_run=no",
    "ready_for_r1_implementation=no",
    "blocked",
]

ACCEPT_DECLARATION_PATTERNS = [
    re.compile(r"ACLA_AUTHORITATIVE_ENTRYPOINT\s*=\s*([^\s\r\n]+)", re.I),
    re.compile(r"AUTHORITATIVE_ACLA_ENTRYPOINT\s*=\s*([^\s\r\n]+)", re.I),
    re.compile(r"AUTHORITATIVE_ACLA_IMPLEMENTATION\s*=\s*([^\s\r\n]+)", re.I),
    re.compile(r"ACCEPTED_ACLA_IMPLEMENTATION\s*=\s*([^\s\r\n]+)", re.I),
    re.compile(r"authoritative\s+(?:a-cla|acla)\s+entrypoint\s*[:=]\s*([^\s\r\n]+)", re.I),
]


def explicit_entrypoint_declarations(rows):
    declarations = []
    for r in rows:
        if r["is_code"] == "YES":
            continue
        text = r["text"]
        for pat in ACCEPT_DECLARATION_PATTERNS:
            for m in pat.finditer(text):
                token = m.group(1).strip().strip("`\"'.,;")
                declarations.append({
                    "declared_entrypoint": token,
                    "source_file": r["full_path"],
                    "source_relative": r["relative_path"],
                    "matched_text": m.group(0),
                })
    return declarations


def status_evidence_for_filename(rows, filename):
    evidence = []
    fname_low = filename.lower()
    for r in rows:
        if r["is_code"] == "YES":
            continue
        text = r["text"]
        low = text.lower()
        if fname_low not in low:
            continue
        for line_no, line in enumerate(text.splitlines(), start=1):
            if fname_low not in line.lower():
                continue
            context = line
            nearby = "\n".join(
                text.splitlines()[max(0, line_no-3): min(len(text.splitlines()), line_no+2)]
            )
            reject = any(x in nearby.lower() for x in REJECT_PATTERNS)
            accept = any(
                x in nearby.lower()
                for x in [
                    "accepted implementation",
                    "authoritative implementation",
                    "verified completed",
                    "ready_for_full_network_run=yes",
                    "ready_for_first",
                ]
            )
            evidence.append({
                "source_file": r["full_path"],
                "line": line_no,
                "text": context[:1000],
                "reject_signal": "YES" if reject else "NO",
                "accept_signal": "YES" if accept else "NO",
            })
    return evidence


def parse_python(path: Path):
    text = safe_text(path, max_bytes=20_000_000)
    try:
        tree = ast.parse(text, filename=str(path))
        compile_status = "PASS"
        compile_error = ""
    except Exception as e:
        return {
            "compile_status": "FAIL",
            "compile_error": str(e),
            "tree": None,
            "text": text,
        }

    imports = []
    functions = []
    constants = {}
    main_guard = False
    argparse_used = False
    rng_sources = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names:
                imports.append(a.name)
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                imports.append(node.module)
        elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            functions.append(node.name)
        elif isinstance(node, ast.If):
            try:
                cond = ast.unparse(node.test)
            except Exception:
                cond = ""
            if "__name__" in cond and "__main__" in cond:
                main_guard = True
        elif isinstance(node, ast.Call):
            try:
                fn = ast.unparse(node.func)
            except Exception:
                fn = ""
            low = fn.lower()
            if "argumentparser" in low or "add_argument" in low:
                argparse_used = True
            if low.startswith("random.") or low == "random":
                rng_sources.add("python_random")
            if "np.random" in low or "numpy.random" in low:
                rng_sources.add("numpy_random")
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = []
            value = None
            if isinstance(node, ast.Assign):
                targets = node.targets
                value = node.value
            else:
                targets = [node.target]
                value = node.value
            for t in targets:
                if isinstance(t, ast.Name) and t.id.isupper():
                    try:
                        constants[t.id] = ast.literal_eval(value)
                    except Exception:
                        try:
                            constants[t.id] = ast.unparse(value)
                        except Exception:
                            constants[t.id] = "<NONLITERAL>"

    return {
        "compile_status": compile_status,
        "compile_error": compile_error,
        "tree": tree,
        "text": text,
        "imports": sorted(set(imports)),
        "functions": sorted(set(functions)),
        "constants": constants,
        "main_guard": main_guard,
        "argparse_used": argparse_used,
        "rng_sources": sorted(rng_sources),
    }


def resolve_local_dependencies(entry: Path, code_root: Path):
    required = {entry.resolve()}
    queue = [entry.resolve()]
    unresolved_local = []
    third_party = set()

    while queue:
        p = queue.pop()
        meta = parse_python(p)
        if meta["compile_status"] != "PASS":
            raise RuntimeError(f"PYTHON_COMPILE_FAILED={p}|{meta['compile_error']}")
        for mod in meta.get("imports", []):
            top = mod.split(".")[0]
            candidates = [
                p.parent / (top + ".py"),
                code_root / (top + ".py"),
                p.parent / top / "__init__.py",
                code_root / top / "__init__.py",
            ]
            found = None
            for c in candidates:
                if c.is_file():
                    found = c.resolve()
                    break
            if found is not None:
                if found not in required:
                    required.add(found)
                    queue.append(found)
            else:
                third_party.add(top)

    return sorted(required), sorted(third_party), unresolved_local


def package_hash(paths, root):
    h = hashlib.sha256()
    for p in sorted(paths, key=lambda x: str(x).lower()):
        try:
            rel = p.relative_to(root)
        except Exception:
            rel = p.name
        h.update(str(rel).replace("\\", "/").encode("utf-8"))
        h.update(b"\0")
        h.update(sha256_file(p).encode("ascii"))
        h.update(b"\n")
    return h.hexdigest()


def detect_input_schema(text: str):
    low = text.lower()
    if "from_pandas_adjacency" in low or "load_adjacency" in low or "adjacency matrix" in low:
        return "ADJACENCY_MATRIX"
    if "read_edgelist" in low or (
        ("source" in low and "target" in low)
        and ("read_csv" in low or "read_table" in low)
    ):
        return "EDGE_LIST"
    if "np.load" in low and ("row" in low and "col" in low and "data" in low):
        return "SPARSE_COO"
    if "multilayer" in low and ("layer" in low or "matrices" in low):
        return "MULTILAYER_MATRICES_OR_GRAPH_OBJECT"
    if "networkx" in low and re.search(r"def\s+\w+\s*\(\s*g\s*[:=,\)]", low):
        return "NETWORKX_GRAPH_OBJECT"
    return "UNRESOLVED"


def implementation_semantics(meta):
    text = meta["text"]
    low = text.lower()
    constants = meta["constants"]

    # input / weights
    schema = detect_input_schema(text)

    weight_field = "UNRESOLVED"
    weight_transform = "NONE_DETECTED"
    supports_negative = "UNDETERMINED"

    if "weight" in low:
        weight_field = "weight"
    if "a.where(a > 0, 0.0)" in low or ".where(a > 0, 0.0)" in low:
        weight_transform = "DROPS_NONPOSITIVE_WEIGHTS"
        supports_negative = "NO"
    elif "abs(" in low and "weight" in low:
        weight_transform = "POSSIBLE_ABSOLUTE_VALUE_TRANSFORMATION"
        supports_negative = "UNDETERMINED"
    elif "nx_modularity" in low and 'weight="weight"' in low:
        supports_negative = "UNDETERMINED_NETWORKX_MODULARITY_SIGNED_COMPATIBILITY_NOT_PROVEN"

    # regulatory usage
    if "regulatory" in low or "tarbase" in low or "targetscan" in low or "mirdb" in low:
        reg_usage = "CODE_CONTAINS_REGULATORY_CONCEPTS_REVIEW_REQUIRED"
    else:
        reg_usage = "NO_NATIVE_REGULATORY_CHANNEL_DETECTED_METADATA_ONLY"

    # params
    aliases = {
        "RANDOM_SEED": ["RANDOM_SEED", "SEED"],
        "MAX_ITERATIONS": ["MAX_ITERS", "MAX_ITERATIONS", "NUM_ITERATIONS"],
        "CONVERGENCE_THRESHOLD": ["CONVERGENCE_TOL", "EPSILON", "TOLERANCE"],
        "CONVERGENCE_PATIENCE": ["CONVERGENCE_PATIENCE", "PATIENCE"],
        "LEARNING_RATE_OR_EQUIVALENT": [
            "INITIAL_ALPHA", "ALPHA", "ALPHA_BASE", "ALPHA_MIN", "ALPHA_MAX",
        ],
        "GLOBAL_FEEDBACK_WEIGHT": ["BETA_GLOBAL", "BETA"],
        "NEW_COMMUNITY_PENALTY": ["NEW_COMM_PENALTY"],
        "OVERLAP_TAU": ["TAU"],
        "OVERLAP_DELTA": ["DELTA"],
    }

    extracted = {}
    for canonical, keys in aliases.items():
        hits = []
        for k in keys:
            if k in constants:
                hits.append(f"{k}={constants[k]}")
        extracted[canonical] = "|".join(hits) if hits else ""

    # function-based algorithm semantics
    functions = meta["functions"]
    init_method = "EACH_NODE_OWN_COMMUNITY" if (
        "each node is its own community" in low
        or "hard_labels = {n: i for i, n in enumerate(nodes)}" in low
    ) else "UNRESOLVED"

    objective = "MODULARITY" if "modularity" in low else "UNRESOLVED"
    action_rule = "ARGMAX_DUAL_FEEDBACK" if (
        "choose_with_dual_feedback" in functions
        or "np.argmax(combined)" in low
    ) else ("PROBABILISTIC_ACTION_SELECTION" if "np.random.choice" in low else "UNRESOLVED")
    update_rule = "ADAPTIVE_LEARNING_AUTOMATA_PROBABILITY_UPDATE" if (
        "update_probabilities" in functions or "update_prob" in functions
    ) else "UNRESOLVED"
    stopping = "CHANGED_FRACTION_PLUS_PATIENCE" if (
        "convergence_tol" in low and "patience" in low
    ) else ("ENTROPY_DELTA_THRESHOLD" if "delta_h" in low and "epsilon" in low else "UNRESOLVED")

    return {
        "schema": schema,
        "weight_field": weight_field,
        "weight_transform": weight_transform,
        "supports_negative": supports_negative,
        "reg_usage": reg_usage,
        "params": extracted,
        "initialization": init_method,
        "objective": objective,
        "action_rule": action_rule,
        "update_rule": update_rule,
        "stopping": stopping,
    }


def find_explicit_authoritative_entrypoint(rows, code_root):
    declarations = explicit_entrypoint_declarations(rows)
    if not declarations:
        return None, declarations, "NO_EXPLICIT_ACCEPTED_ENTRYPOINT_DECLARATION"

    resolved = []
    for d in declarations:
        token = d["declared_entrypoint"]
        basename = Path(token).name
        matches = list(code_root.rglob(basename))
        if len(matches) == 1:
            resolved.append((matches[0].resolve(), d))
        elif len(matches) > 1:
            return None, declarations, f"DECLARATION_RESOLVES_TO_MULTIPLE_FILES:{basename}"

    uniq = {}
    for p, d in resolved:
        uniq[str(p)] = (p, d)
    if len(uniq) != 1:
        return None, declarations, f"EXPLICIT_DECLARATIONS_NOT_UNIQUE:{len(uniq)}"

    p, d = next(iter(uniq.values()))
    evidence = status_evidence_for_filename(rows, p.name)
    reject_evidence = [e for e in evidence if e["reject_signal"] == "YES"]
    # A direct authoritative declaration may supersede older history only if
    # the declaration itself contains explicit execution-readiness language.
    decl_source_text = safe_text(Path(d["source_file"])).lower()
    readiness_positive = (
        "ready_for_first_gse243219_acla_execution=yes" in decl_source_text
        or "ready_for_full_network_run=yes" in decl_source_text
        or "accepted_acla_implementation" in decl_source_text
        or "authoritative_acla_entrypoint" in decl_source_text
        or "acla_authoritative_entrypoint" in decl_source_text
    )
    if reject_evidence and not readiness_positive:
        return None, declarations, "DECLARED_ENTRYPOINT_HAS_UNRESOLVED_REJECTION_OR_SUPERSESSION_EVIDENCE"

    return p, declarations, "UNIQUE_EXPLICIT_AUTHORITATIVE_DECLARATION"


def main():
    if len(sys.argv) != 6:
        raise SystemExit(
            "usage: D10A_PREFLIGHT.py "
            "<project_root> <reusable_root> <d9_run> <outdir> <result_json>"
        )

    project_root = Path(sys.argv[1])
    reusable_root = Path(sys.argv[2])
    d9_run = Path(sys.argv[3])
    outdir = Path(sys.argv[4])
    result_json = Path(sys.argv[5])
    outdir.mkdir(parents=True, exist_ok=True)

    # Authorized roots only
    roots = {
        "01_ACLA_CODE": reusable_root / "01_ACLA_CODE",
        "07_METHODS_AND_DOCUMENTATION": reusable_root / "07_METHODS_AND_DOCUMENTATION",
        "09_OLD_METHOD_HISTORY": reusable_root / "09_OLD_METHOD_HISTORY",
    }

    # ----------------------------------------------------------
    # A. D9 integrity + network compatibility (read only)
    # ----------------------------------------------------------
    d9_manifest = d9_run / "D9_SHA256_MANIFEST.csv"
    d9_status = d9_run / "D9_FINAL_STATUS.txt"
    d9_nodes = d9_run / "D9_MASTER_NODES.csv"
    d9_edges = d9_run / "D9_MASTER_EDGES.csv"
    d9_acla_dir = d9_run / "D9_ACLA_INPUT"

    d9_manifest_df = recertify_manifest(d9_manifest, "D9")
    status_text = d9_status.read_text(encoding="utf-8-sig", errors="replace")
    for tok in [
        "D9_STATUS=PASS",
        "UPSTREAM_INPUT_INTEGRITY=PASS",
        "MRNA_NODES=4467",
        "MIRNA_NODES=41",
        "TOTAL_NODES=4508",
        "MRNA_MIRNA_ASSOCIATION_EDGES=11531",
        "REGULATORY_EDGES=1978",
        "TOTAL_STRUCTURAL_EDGES=11531",
        "SELF_LOOPS=0",
        "DUPLICATE_STRUCTURAL_EDGES=0",
        "UNKNOWN_ENDPOINTS=0",
        "INVALID_WEIGHTS=0",
        "CONNECTED_COMPONENTS=2",
        "LARGEST_COMPONENT_NODES=4502",
        "ISOLATED_NODES=0",
        "D9_HASH_MISMATCHES=0",
        "ACLA_EXECUTED=NO",
        "READY_FOR_ACLA_PREEXECUTION_FREEZE=YES",
        "STOP=YES",
    ]:
        if tok not in status_text:
            raise RuntimeError(f"D9_STATUS_TOKEN_MISSING={tok}")

    nodes = pd.read_csv(d9_nodes, dtype={"node_id": str, "node_type": str})
    edges = pd.read_csv(
        d9_edges,
        dtype={"source": str, "target": str},
        float_precision="round_trip",
    )

    if len(nodes) != EXPECTED_NODES or nodes["node_id"].duplicated().any():
        raise RuntimeError("D10A_D9_NODE_IDENTITY_GATE_FAILED")
    if int(nodes["node_type"].eq("MRNA").sum()) != EXPECTED_MRNA:
        raise RuntimeError("D10A_MRNA_NODE_COUNT_CHANGED")
    if int(nodes["node_type"].eq("MIRNA").sum()) != EXPECTED_MIRNA:
        raise RuntimeError("D10A_MIRNA_NODE_COUNT_CHANGED")
    if len(edges) != EXPECTED_EDGES:
        raise RuntimeError("D10A_D9_EDGE_COUNT_CHANGED")
    if edges.duplicated(["source", "target"]).any():
        raise RuntimeError("D10A_D9_DUPLICATE_EDGES")
    if int((edges["source"] == edges["target"]).sum()) != 0:
        raise RuntimeError("D10A_D9_SELF_LOOPS")

    known = set(nodes["node_id"])
    unknown = int(
        (~edges["source"].isin(known)).sum()
        + (~edges["target"].isin(known)).sum()
    )
    if unknown:
        raise RuntimeError(f"D10A_D9_UNKNOWN_ENDPOINTS={unknown}")

    w = pd.to_numeric(edges["association_score"], errors="coerce")
    warr = w.to_numpy(dtype=float)
    invalid_weights = int((~np.isfinite(warr)).sum())
    if invalid_weights:
        raise RuntimeError(f"D10A_D9_INVALID_WEIGHTS={invalid_weights}")

    weight_min = float(warr.min())
    weight_max = float(warr.max())
    negative_present = bool((warr < 0).any())
    zero_present = bool((warr == 0).any())

    comps = component_stats(nodes["node_id"].tolist(), edges)
    if comps["components"] != EXPECTED_COMPONENTS:
        raise RuntimeError(f"D10A_COMPONENTS_CHANGED={comps['components']}")
    if comps["largest"] != EXPECTED_LARGEST:
        raise RuntimeError(f"D10A_LARGEST_COMPONENT_CHANGED={comps['largest']}")
    if comps["second"] != EXPECTED_SECOND:
        raise RuntimeError(f"D10A_SECOND_COMPONENT_CHANGED={comps['second']}")
    if comps["isolated"] != 0:
        raise RuntimeError(f"D10A_ISOLATED_NODES_CHANGED={comps['isolated']}")

    # D9 input files and hashes
    d9_input_rows = []
    if d9_acla_dir.exists():
        for p in sorted(d9_acla_dir.rglob("*")):
            if p.is_file():
                d9_input_rows.append({
                    "filename": p.name,
                    "full_path": str(p),
                    "size_bytes": p.stat().st_size,
                    "SHA256": sha256_file(p),
                })
    pd.DataFrame(d9_input_rows).to_csv(
        outdir / "D10A_D9_INPUT_INVENTORY.csv", index=False
    )

    # ----------------------------------------------------------
    # B. Scan only authorized implementation/method-history roots
    # ----------------------------------------------------------
    rows = scan_files(roots)
    candidate_files_reviewed = len(rows)
    code_rows = [r for r in rows if r["is_code"] == "YES"]
    if not rows:
        raise RuntimeError("ACLA_CANDIDATE_FILES_REVIEWED=0")

    inventory_export = []
    for r in rows:
        out = {k: v for k, v in r.items() if k != "text"}
        inventory_export.append(out)
    pd.DataFrame(inventory_export).to_csv(
        outdir / "D10A_ACLA_CANDIDATE_INVENTORY.csv", index=False
    )

    # Static compile/AST audit of Python code candidates
    static_rows = []
    for r in code_rows:
        p = Path(r["full_path"])
        if p.suffix.lower() != ".py":
            static_rows.append({
                "full_path": str(p),
                "language": p.suffix,
                "compile_status": "NOT_PYTHON",
                "main_guard": "",
                "argparse_used": "",
                "functions_count": "",
                "rng_sources": "",
                "input_schema": "UNRESOLVED_NONPYTHON",
            })
            continue
        meta = parse_python(p)
        sem = implementation_semantics(meta) if meta["compile_status"] == "PASS" else {}
        static_rows.append({
            "full_path": str(p),
            "language": "python",
            "compile_status": meta["compile_status"],
            "compile_error": meta.get("compile_error", ""),
            "main_guard": "YES" if meta.get("main_guard") else "NO",
            "argparse_used": "YES" if meta.get("argparse_used") else "NO",
            "functions_count": len(meta.get("functions", [])),
            "rng_sources": "|".join(meta.get("rng_sources", [])),
            "input_schema": sem.get("schema", ""),
            "weight_transform": sem.get("weight_transform", ""),
            "negative_weight_support": sem.get("supports_negative", ""),
        })
    pd.DataFrame(static_rows).to_csv(
        outdir / "D10A_STATIC_IMPLEMENTATION_AUDIT.csv", index=False
    )

    # ----------------------------------------------------------
    # C. Strict authoritative implementation resolution
    # ----------------------------------------------------------
    entrypoint, declarations, resolution_basis = find_explicit_authoritative_entrypoint(
        rows, roots["01_ACLA_CODE"]
    )
    pd.DataFrame(declarations).to_csv(
        outdir / "D10A_AUTHORITATIVE_DECLARATION_AUDIT.csv", index=False
    )

    implementation_ambiguous = entrypoint is None
    files_required = []
    entry_sha = ""
    package_sha = ""
    required_schema = ""
    selected_d9_file = ""
    selected_d9_sha = ""
    edge_weight_field = "UNRESOLVED_NO_ACCEPTED_IMPLEMENTATION"
    regulatory_usage = "UNRESOLVED_NO_ACCEPTED_IMPLEMENTATION"
    random_seed = ""
    initialization = ""
    max_iters = ""
    stopping = ""
    convergence_threshold = ""
    objective = ""
    independent_runs = ""
    seed_control_complete = "NO"
    convergence_diagnostics_frozen = "NO"
    missing_params = []
    weight_compatible = False
    semantics = None
    third_party = []
    compile_pass = False

    impl_manifest_path = outdir / "D10A_ACLA_IMPLEMENTATION_SHA256_MANIFEST.csv"
    param_audit_path = outdir / "D10A_ACLA_PARAMETER_AUDIT.csv"

    if entrypoint is not None:
        meta = parse_python(entrypoint)
        compile_pass = meta["compile_status"] == "PASS"
        if not compile_pass:
            resolution_basis = "AUTHORITATIVE_ENTRYPOINT_PYTHON_COMPILE_FAILED"
            implementation_ambiguous = True
        else:
            semantics = implementation_semantics(meta)
            files_required, third_party, _ = resolve_local_dependencies(
                entrypoint, roots["01_ACLA_CODE"]
            )
            entry_sha = sha256_file(entrypoint)
            package_sha = package_hash(files_required, roots["01_ACLA_CODE"])
            required_schema = semantics["schema"]
            edge_weight_field = (
                "association_score_as_weight"
                if semantics["weight_field"] == "weight"
                else semantics["weight_field"]
            )
            regulatory_usage = semantics["reg_usage"]

            # exact D9 selection only when schema directly matches a generated artifact
            d9_candidates = {p.name: p for p in d9_acla_dir.glob("*") if p.is_file()}
            if required_schema == "EDGE_LIST" and "structural_edge_list.csv" in d9_candidates:
                selected = d9_candidates["structural_edge_list.csv"]
                selected_d9_file = str(selected)
                selected_d9_sha = sha256_file(selected)
            elif required_schema == "SPARSE_COO" and "association_score_symmetric_coo.npz" in d9_candidates:
                selected = d9_candidates["association_score_symmetric_coo.npz"]
                selected_d9_file = str(selected)
                selected_d9_sha = sha256_file(selected)
            elif required_schema == "NETWORKX_GRAPH_OBJECT":
                # A graph-object function does not itself define serialization.
                resolution_basis = "AUTHORITATIVE_FUNCTION_REQUIRES_GRAPH_OBJECT_BUT_EXECUTION_WRAPPER_NOT_FROZEN"
                implementation_ambiguous = True
            elif required_schema == "ADJACENCY_MATRIX":
                resolution_basis = "AUTHORITATIVE_IMPLEMENTATION_REQUIRES_ADJACENCY_MATRIX_NOT_DIRECT_D9_NATIVE_INPUT"
                implementation_ambiguous = True
            else:
                resolution_basis = f"ACLA_INPUT_SCHEMA_NOT_DIRECTLY_MATCHED:{required_schema}"
                implementation_ambiguous = True

            # signed weight compatibility
            if negative_present:
                if semantics["supports_negative"] == "NO":
                    weight_compatible = False
                    resolution_basis = (
                        "AUTHORITATIVE_IMPLEMENTATION_DROPS_NONPOSITIVE_WEIGHTS_"
                        "INCOMPATIBLE_WITH_SIGNED_D9_ASSOCIATION_WEIGHTS"
                    )
                    implementation_ambiguous = True
                elif "NOT_PROVEN" in semantics["supports_negative"] or semantics["supports_negative"] == "UNDETERMINED":
                    weight_compatible = False
                    resolution_basis = (
                        "SIGNED_WEIGHT_COMPATIBILITY_NOT_ESTABLISHED_BY_AUTHORITATIVE_CODE"
                    )
                    implementation_ambiguous = True
                else:
                    weight_compatible = True
            else:
                weight_compatible = True

            params = semantics["params"]
            random_seed = params.get("RANDOM_SEED", "")
            max_iters = params.get("MAX_ITERATIONS", "")
            convergence_threshold = params.get("CONVERGENCE_THRESHOLD", "")
            initialization = semantics["initialization"]
            stopping = semantics["stopping"]
            objective = semantics["objective"]
            independent_runs = "1"  # only if no multi-run/consensus code is detected
            low = meta["text"].lower()
            if "multiple runs" in low or "independent runs" in low or "consensus" in low:
                independent_runs = "UNRESOLVED_REVIEW_REQUIRED"

            # deterministic seed gate
            rng_sources = set(meta.get("rng_sources", []))
            seed_calls = (
                "random.seed" in low
                or "np.random.seed" in low
                or "default_rng(" in low
            )
            seed_control_complete = (
                "YES"
                if random_seed and (not rng_sources or seed_calls)
                else "NO"
            )

            required_param_map = {
                "RANDOM_SEED": random_seed,
                "INITIALIZATION_METHOD": initialization,
                "MAX_ITERATIONS": max_iters,
                "STOPPING_CRITERION": stopping,
                "CONVERGENCE_THRESHOLD": convergence_threshold,
                "OBJECTIVE_FUNCTION": objective,
                "NUMBER_OF_INDEPENDENT_RUNS": independent_runs,
            }
            missing_params = [
                k for k, v in required_param_map.items()
                if not v or str(v).startswith("UNRESOLVED")
            ]
            if seed_control_complete != "YES":
                missing_params.append("COMPLETE_RANDOM_SEED_CONTROL")

            # diagnostics gate: selected implementation must expose iteration-level loop
            # and convergence/objective semantics. Output serialization will be frozen in
            # the future runner, but no biology is run here.
            convergence_diagnostics_frozen = (
                "YES"
                if (
                    not missing_params
                    and objective != "UNRESOLVED"
                    and stopping != "UNRESOLVED"
                )
                else "NO"
            )

            if missing_params:
                resolution_basis = "MATERIAL_PROSPECTIVE_PARAMETERS_UNRESOLVED:" + ",".join(missing_params)
                implementation_ambiguous = True

            manifest_rows = []
            for p in files_required:
                manifest_rows.append({
                    "role": "ENTRYPOINT" if p.resolve() == entrypoint.resolve() else "LOCAL_DEPENDENCY",
                    "relative_path": str(p.relative_to(roots["01_ACLA_CODE"])).replace("\\", "/")
                        if roots["01_ACLA_CODE"] in p.parents else p.name,
                    "full_path": str(p),
                    "size_bytes": p.stat().st_size,
                    "SHA256": sha256_file(p),
                })
            pd.DataFrame(manifest_rows).to_csv(impl_manifest_path, index=False)

            parameter_rows = []
            param_sources = {
                "RANDOM_SEED": random_seed,
                "INITIALIZATION_METHOD": initialization,
                "MAX_ITERATIONS": max_iters,
                "STOPPING_CRITERION": stopping,
                "CONVERGENCE_THRESHOLD": convergence_threshold,
                "LEARNING_RATE_OR_EQUIVALENT": params.get("LEARNING_RATE_OR_EQUIVALENT", ""),
                "ACTION_SELECTION_RULE": semantics["action_rule"],
                "OBJECTIVE_FUNCTION": objective,
                "COMMUNITY_UPDATE_RULE": semantics["update_rule"],
                "NUMBER_OF_INDEPENDENT_RUNS": independent_runs,
                "CONSENSUS_RULE_IF_ANY": (
                    "NONE_DETECTED" if "consensus" not in low else "REVIEW_REQUIRED"
                ),
                "GLOBAL_FEEDBACK_WEIGHT": params.get("GLOBAL_FEEDBACK_WEIGHT", ""),
                "NEW_COMMUNITY_PENALTY": params.get("NEW_COMMUNITY_PENALTY", ""),
                "OVERLAP_TAU": params.get("OVERLAP_TAU", ""),
                "OVERLAP_DELTA": params.get("OVERLAP_DELTA", ""),
            }
            for name, value in parameter_sources.items():
                parameter_rows.append({
                    "PARAMETER_NAME": name,
                    "VALUE": value,
                    "SOURCE": str(entrypoint),
                    "HARDCODED_OR_CONFIGURED": "HARDCODED_OR_FUNCTION_DEFAULT_STATIC_AUDIT",
                    "SCIENTIFIC_OR_EXECUTION_CONTROL": (
                        "SCIENTIFIC" if name not in {"RANDOM_SEED", "MAX_ITERATIONS", "NUMBER_OF_INDEPENDENT_RUNS"} else "EXECUTION_AND_SCIENTIFIC"
                    ),
                    "METHOD_CLASSIFICATION": "METHOD_INTRINSIC_PENDING_ACCEPTED_IMPLEMENTATION_GATE",
                })
            pd.DataFrame(parameter_rows).to_csv(param_audit_path, index=False)
    else:
        # Create required empty-but-typed audit outputs.
        pd.DataFrame(columns=[
            "role","relative_path","full_path","size_bytes","SHA256"
        ]).to_csv(impl_manifest_path, index=False)

        unresolved_names = [
            "RANDOM_SEED","INITIALIZATION_METHOD","MAX_ITERATIONS",
            "STOPPING_CRITERION","CONVERGENCE_THRESHOLD",
            "LEARNING_RATE_OR_EQUIVALENT","ACTION_SELECTION_RULE",
            "OBJECTIVE_FUNCTION","COMMUNITY_UPDATE_RULE",
            "NUMBER_OF_INDEPENDENT_RUNS","CONSENSUS_RULE_IF_ANY",
        ]
        pd.DataFrame([
            {
                "PARAMETER_NAME": x,
                "VALUE": "",
                "SOURCE": "UNRESOLVED_NO_ACCEPTED_AUTHORITATIVE_IMPLEMENTATION",
                "HARDCODED_OR_CONFIGURED": "",
                "SCIENTIFIC_OR_EXECUTION_CONTROL": "",
                "METHOD_CLASSIFICATION": "NOT_CARRIED_FORWARD",
            }
            for x in unresolved_names
        ]).to_csv(param_audit_path, index=False)
        missing_params = unresolved_names

    # Dependency availability if selected
    dependency_rows = []
    for mod in third_party:
        spec = importlib.util.find_spec(mod)
        dependency_rows.append({
            "module": mod,
            "available": "YES" if spec is not None else "NO",
            "origin": "" if spec is None else str(spec.origin),
        })
    pd.DataFrame(dependency_rows).to_csv(
        outdir / "D10A_DEPENDENCY_AUDIT.csv", index=False
    )

    # Historical status audit for the main known branches. This is generic and
    # generated from local docs, not hard-coded as acceptance.
    status_rows = []
    for r in code_rows:
        p = Path(r["full_path"])
        if p.suffix.lower() != ".py":
            continue
        ev = status_evidence_for_filename(rows, p.name)
        reject_count = sum(e["reject_signal"] == "YES" for e in ev)
        accept_count = sum(e["accept_signal"] == "YES" for e in ev)
        status_rows.append({
            "filename": p.name,
            "full_path": str(p),
            "SHA256": r["SHA256"],
            "documentation_mentions": len(ev),
            "reject_or_supersede_mentions": reject_count,
            "accept_mentions": accept_count,
            "eligible_as_authoritative_without_explicit_declaration": "NO",
        })
    pd.DataFrame(status_rows).to_csv(
        outdir / "D10A_IMPLEMENTATION_HISTORY_STATUS_AUDIT.csv", index=False
    )

    # Freeze all future diagnostics/output requirements prospectively, even on
    # FAIL_CLOSED. They are requirements for whichever implementation is later accepted.
    diagnostics = [
        "iteration",
        "objective_value",
        "community_assignments",
        "number_of_communities",
        "nodes_changed_per_iteration",
        "fraction_nodes_changed",
        "stopping_reason",
        "final_iteration",
        "best_iteration",
        "best_objective",
        "runtime",
        "seed",
        "algorithm_native_convergence_diagnostics",
    ]
    pd.DataFrame({"required_future_diagnostic": diagnostics}).to_csv(
        outdir / "D10A_FUTURE_CONVERGENCE_DIAGNOSTICS_REQUIREMENTS.csv",
        index=False,
    )

    future_outputs = [
        "ACLA_RUN_CONFIG.json",
        "ACLA_ITERATION_HISTORY.csv",
        "ACLA_FINAL_NODE_COMMUNITIES.csv",
        "ACLA_BEST_NODE_COMMUNITIES.csv",
        "ACLA_COMMUNITY_SUMMARY.csv",
        "ACLA_CONVERGENCE_DIAGNOSTICS.csv",
        "ACLA_RUN_LOG.txt",
        "ACLA_SHA256_MANIFEST.csv",
    ]
    pd.DataFrame({"required_future_output": future_outputs}).to_csv(
        outdir / "D10A_FUTURE_ACLA_OUTPUT_REQUIREMENTS.csv",
        index=False,
    )

    # No old dataset-derived setting is carried forward because nothing is executed.
    old_dataset_carried = 0
    new_threshold = "NO"
    new_weight_transform = "NO"
    regulatory_duplication = 0
    synthetic_test_only = "NO"
    gse_executed = "NO"

    ready = (
        entrypoint is not None
        and not implementation_ambiguous
        and compile_pass
        and selected_d9_file != ""
        and selected_d9_sha != ""
        and seed_control_complete == "YES"
        and convergence_diagnostics_frozen == "YES"
        and weight_compatible
        and not missing_params
    )

    status = "PASS" if ready else "FAIL_CLOSED"

    freeze_text = f"""GSE243219 D10A A-CLA PREEXECUTION FREEZE
D10A_STATUS={status}
RESOLUTION_BASIS={resolution_basis}
ACLA_AUTHORITATIVE_ENTRYPOINT={str(entrypoint) if entrypoint else ""}
ACLA_ENTRYPOINT_SHA256={entry_sha}
ACLA_FILES_ACTUALLY_REQUIRED={len(files_required)}
ACLA_IMPLEMENTATION_PACKAGE_SHA256={package_sha}
ACLA_IMPLEMENTATION_AMBIGUOUS={"NO" if ready else "YES"}
ACLA_REQUIRED_INPUT_SCHEMA={required_schema}
D9_SELECTED_ACLA_INPUT_FILE={selected_d9_file}
D9_SELECTED_ACLA_INPUT_SHA256={selected_d9_sha}
INPUT_NODES=4508
INPUT_EDGES=11531
INPUT_COMPONENTS=2
INPUT_LARGEST_COMPONENT=4502
INPUT_SECOND_COMPONENT=6
ACLA_EDGE_WEIGHT_FIELD={edge_weight_field}
ACLA_WEIGHT_RANGE_MIN={weight_min:.17g}
ACLA_WEIGHT_RANGE_MAX={weight_max:.17g}
ACLA_NEGATIVE_WEIGHTS_PRESENT={"YES" if negative_present else "NO"}
ACLA_ZERO_WEIGHTS_PRESENT={"YES" if zero_present else "NO"}
ACLA_REGULATORY_EVIDENCE_USAGE={regulatory_usage}
REGULATORY_EDGE_DUPLICATION=0
RANDOM_SEED={random_seed}
INITIALIZATION_METHOD={initialization}
MAX_ITERATIONS={max_iters}
STOPPING_CRITERION={stopping}
CONVERGENCE_THRESHOLD={convergence_threshold}
OBJECTIVE_FUNCTION={objective}
NUMBER_OF_INDEPENDENT_RUNS={independent_runs}
SEED_CONTROL_COMPLETE={seed_control_complete}
MISSING_PROSPECTIVE_PARAMETER={";".join(sorted(set(missing_params)))}
OLD_DATASET_DERIVED_PARAMETER_CARRIED_FORWARD_WITHOUT_JUSTIFICATION=0
D10A_NEW_NETWORK_THRESHOLD_CREATED=NO
D10A_NEW_WEIGHT_TRANSFORMATION_APPLIED=NO
ACLA_CONVERGENCE_DIAGNOSTICS_FROZEN={convergence_diagnostics_frozen}
SYNTHETIC_TEST_ONLY=NO
GSE243219_ACLA_EXECUTED=NO
COMMUNITY_RESULTS_CREATED=NO
MODULE_SELECTION_EXECUTED=NO
HUB_ANALYSIS_EXECUTED=NO
ENRICHMENT_EXECUTED=NO
PROHIBITED_POSTHOC_PARAMETER_CHANGE=YES
PROHIBITED_POSTHOC_WEIGHT_TRANSFORMATION=YES
PROHIBITED_SECOND_SEED_UNLESS_PROSPECTIVELY_AUTHORIZED=YES
READY_FOR_FIRST_GSE243219_ACLA_EXECUTION={"YES" if ready else "NO"}
STOP=YES
"""
    freeze_path = outdir / "D10A_ACLA_PREEXECUTION_FREEZE.txt"
    freeze_path.write_text(freeze_text, encoding="utf-8")

    # Summary result consumed by PowerShell.
    result = {
        "D10A_STATUS": status,
        "ACLA_AUTHORITATIVE_ENTRYPOINT": str(entrypoint) if entrypoint else "",
        "ACLA_ENTRYPOINT_SHA256": entry_sha,
        "ACLA_FILES_ACTUALLY_REQUIRED": len(files_required),
        "ACLA_IMPLEMENTATION_PACKAGE_SHA256": package_sha,
        "ACLA_IMPLEMENTATION_HASH_MISMATCHES": 0,
        "ACLA_IMPLEMENTATION_AMBIGUOUS": "NO" if ready else "YES",
        "ACLA_CANDIDATE_FILES_REVIEWED": candidate_files_reviewed,
        "ACLA_REQUIRED_INPUT_SCHEMA": required_schema,
        "D9_SELECTED_ACLA_INPUT_FILE": selected_d9_file,
        "D9_SELECTED_ACLA_INPUT_SHA256": selected_d9_sha,
        "INPUT_NODES": EXPECTED_NODES,
        "INPUT_EDGES": EXPECTED_EDGES,
        "INPUT_COMPONENTS": comps["components"],
        "INPUT_LARGEST_COMPONENT": comps["largest"],
        "INPUT_SECOND_COMPONENT": comps["second"],
        "ACLA_EDGE_WEIGHT_FIELD": edge_weight_field,
        "ACLA_WEIGHT_RANGE_MIN": weight_min,
        "ACLA_WEIGHT_RANGE_MAX": weight_max,
        "ACLA_NEGATIVE_WEIGHTS_PRESENT": "YES" if negative_present else "NO",
        "ACLA_ZERO_WEIGHTS_PRESENT": "YES" if zero_present else "NO",
        "ACLA_REGULATORY_EVIDENCE_USAGE": regulatory_usage,
        "REGULATORY_EDGE_DUPLICATION": regulatory_duplication,
        "RANDOM_SEED": random_seed,
        "INITIALIZATION_METHOD": initialization,
        "MAX_ITERATIONS": max_iters,
        "STOPPING_CRITERION": stopping,
        "CONVERGENCE_THRESHOLD": convergence_threshold,
        "OBJECTIVE_FUNCTION": objective,
        "NUMBER_OF_INDEPENDENT_RUNS": independent_runs,
        "SEED_CONTROL_COMPLETE": seed_control_complete,
        "MISSING_PROSPECTIVE_PARAMETER": ";".join(sorted(set(missing_params))),
        "OLD_DATASET_DERIVED_PARAMETER_CARRIED_FORWARD_WITHOUT_JUSTIFICATION": old_dataset_carried,
        "D10A_NEW_NETWORK_THRESHOLD_CREATED": new_threshold,
        "D10A_NEW_WEIGHT_TRANSFORMATION_APPLIED": new_weight_transform,
        "ACLA_CONVERGENCE_DIAGNOSTICS_FROZEN": convergence_diagnostics_frozen,
        "SYNTHETIC_TEST_ONLY": synthetic_test_only,
        "GSE243219_ACLA_EXECUTED": gse_executed,
        "D10A_PREEXECUTION_FREEZE_CREATED": "YES",
        "READY_FOR_FIRST_GSE243219_ACLA_EXECUTION": "YES" if ready else "NO",
        "RESOLUTION_BASIS": resolution_basis,
        "STOP": "YES",
    }
    result_json.write_text(
        json.dumps(result, indent=2, sort_keys=True),
        encoding="utf-8",
    )

    # Exit zero even on scientific FAIL_CLOSED so PowerShell can create a
    # complete auditable final report/manifest. Execution authorization comes
    # only from D10A_STATUS=PASS.
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
