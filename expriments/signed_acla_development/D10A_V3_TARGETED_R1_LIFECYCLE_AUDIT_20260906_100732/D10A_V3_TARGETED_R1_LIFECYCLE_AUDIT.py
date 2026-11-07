#!/usr/bin/env python3
from __future__ import annotations

import ast
import hashlib
import json
import math
import re
import sys
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_NODES = 4508
EXPECTED_EDGES = 11531
EXPECTED_COMPONENTS = 2
EXPECTED_LARGEST = 4502
EXPECTED_SECOND = 6
EXPECTED_WEIGHT_MIN = -0.7753835531973502
EXPECTED_WEIGHT_MAX = 0.7428957195865319

TEXT_EXTS = {
    ".py", ".ps1", ".txt", ".md", ".csv", ".json", ".yaml", ".yml",
    ".toml", ".ini", ".r", ".R", ".jl", ".m", ".xml", ".log"
}
CODE_EXTS = {".py", ".r", ".R", ".jl", ".m"}

# Filename/member-name driven targeting only. This is intentionally narrower
# than D10A-V2 family discovery.
TARGET_NAME_RE = re.compile(
    r"(?i)("
    r"\bB1B1?\b|CONCORDANCE|DIAGNOSTIC|"
    r"R1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)|"
    r"RUN[_ -]?(?:ACLA[_ -]?)?R1|ACLA[_ -]?R1|"
    r"B1C|"
    r"FINAL[_ -]?(?:DECISION|STATUS)|"
    r"READINESS|ACCEPTANCE|AUTHORIZED|READY[_ -]?FOR"
    r")"
)

# Broader content filter is allowed only after a file was targeted by name or
# was a targeted member inside a targeted ZIP.
R1_CONTEXT_RE = re.compile(r"(?i)\bR1\b|R1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)|A-CLA[_ -]?R1|ACLA[_ -]?R1")
B1B_CONTEXT_RE = re.compile(r"(?i)\bB1B1?\b|CONCORDANCE")
B1C_CONTEXT_RE = re.compile(r"(?i)\bB1C(?:[-_ ]?\d+)?\b")

AUTHORITATIVE_ROLES = {
    "EXECUTION", "BENCHMARK", "VALIDATION", "ACCEPTANCE"
}

ROLE_ORDER = [
    "DESIGN", "PREFLIGHT", "IMPLEMENTATION",
    "EXECUTION", "BENCHMARK", "VALIDATION", "ACCEPTANCE"
]

EXAMPLE_CONTEXT_RE = re.compile(
    r"(?i)\b(expected|example|template|require(?:d|ment)?|should report|"
    r"pass criteria|allowed outcomes|if pass|if accepted|possible valid evidence|"
    r"look for|report:|return:)\b"
)

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
    need = {"full_path", "size_bytes", "SHA256"}
    missing = need - set(df.columns)
    if missing:
        raise RuntimeError(f"{label}_MANIFEST_COLUMNS_MISSING={sorted(missing)}")
    bad = []
    for _, r in df.iterrows():
        p = Path(str(r["full_path"]))
        if not p.is_file():
            bad.append(f"MISSING:{p}")
            continue
        if p.stat().st_size != int(r["size_bytes"]):
            bad.append(f"SIZE:{p}")
            continue
        if sha256_file(p) != str(r["SHA256"]).lower():
            bad.append(f"SHA256:{p}")
    if bad:
        raise RuntimeError(
            f"{label}_HASH_MISMATCHES={len(bad)}|" + "||".join(bad[:20])
        )
    return df

class UnionFind:
    def __init__(self, nodes):
        self.parent = {n: n for n in nodes}
        self.size = {n: 1 for n in nodes}

    def find(self, x):
        if self.parent[x] != x:
            self.parent[x] = self.find(self.parent[x])
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
    deg = Counter({n: 0 for n in nodes})
    for s, t in zip(edges["source"], edges["target"]):
        uf.union(s, t)
        deg[s] += 1
        deg[t] += 1
    comp = defaultdict(int)
    for n in nodes:
        comp[uf.find(n)] += 1
    sizes = sorted(comp.values(), reverse=True)
    return {
        "components": len(sizes),
        "largest": sizes[0] if sizes else 0,
        "second": sizes[1] if len(sizes) > 1 else 0,
        "isolated": sum(1 for n in nodes if deg[n] == 0),
    }

def safe_text(path: Path, max_bytes: int = 25_000_000) -> str:
    try:
        if path.stat().st_size > max_bytes:
            return ""
        if path.suffix.lower() == ".docx":
            with zipfile.ZipFile(path) as z:
                xml = z.read("word/document.xml").decode("utf-8", errors="replace")
            xml = re.sub(r"</w:p>", "\n", xml)
            return re.sub(r"<[^>]+>", "", xml)
        if path.suffix in TEXT_EXTS:
            return path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return ""
    return ""

def read_targeted_zip_members(path: Path, max_members=10000, max_text_bytes=4_000_000):
    out = []
    if path.suffix.lower() != ".zip":
        return out
    try:
        with zipfile.ZipFile(path) as z:
            for info in z.infolist()[:max_members]:
                member = info.filename
                if not TARGET_NAME_RE.search(member):
                    continue
                text = ""
                ext = Path(member).suffix
                if info.file_size <= max_text_bytes and ext in TEXT_EXTS:
                    try:
                        text = z.read(info).decode("utf-8", errors="replace")
                    except Exception:
                        pass
                out.append((member, text))
    except Exception:
        pass
    return out

def classify_roles(name: str, text: str) -> list[str]:
    low = name.lower()
    roles = set()

    # Filename/path first. Content only refines targeted artifacts.
    if any(k in low for k in ["design", "specification", "contract"]):
        roles.add("DESIGN")
    if "preflight" in low or "static_validation" in low or "syntax" in low:
        roles.add("PREFLIGHT")
    if any(k in low for k in ["prototype", "implementation"]) and (
        Path(name).suffix.lower() in CODE_EXTS
        or any(k in low for k in ["package", "runner", "source"])
    ):
        roles.add("IMPLEMENTATION")
    if any(k in low for k in ["execution", "run_", "runner", "result", "output", "log"]):
        roles.add("EXECUTION")
    if any(k in low for k in ["benchmark", "scalability", "fixture", "concordance"]):
        roles.add("BENCHMARK")
    if any(k in low for k in ["validation", "validate", "audit"]):
        roles.add("VALIDATION")
    if any(k in low for k in [
        "final_decision", "final_status", "closure", "acceptance",
        "readiness", "authorized", "ready_for"
    ]):
        roles.add("ACCEPTANCE")

    tlow = text.lower()
    if text:
        if "preflight" in tlow and not any(x in roles for x in ["EXECUTION","BENCHMARK"]):
            roles.add("PREFLIGHT")
        if R1_CONTEXT_RE.search(text) and (
            "exit_code" in tlow or "execution_status" in tlow or
            "run_status" in tlow or "runner completed" in tlow or
            "prototype completed" in tlow
        ):
            roles.add("EXECUTION")
        if R1_CONTEXT_RE.search(text) and any(
            k in tlow for k in [
                "benchmark", "baseline comparison", "reproducibility",
                "deterministic", "fixture", "scalability"
            ]
        ):
            roles.add("BENCHMARK")
        if R1_CONTEXT_RE.search(text) and any(
            k in tlow for k in [
                "accepted", "approved_for_use", "final_acceptance",
                "ready_for_production", "ready_for_full_network_run",
                "ready_for_biological_execution"
            ]
        ):
            roles.add("ACCEPTANCE")
    if not roles:
        roles.add("IMPLEMENTATION" if Path(name).suffix.lower() in CODE_EXTS else "DESIGN")
    return [r for r in ROLE_ORDER if r in roles]

def authority_level(name: str, roles: list[str]) -> str:
    low = name.lower()
    if any(k in low for k in ["readme", "specification", "template", "prompt", "requirements"]):
        return "NONAUTHORITATIVE_DESIGN_OR_EXAMPLE"
    if any(r in roles for r in ["EXECUTION","BENCHMARK","VALIDATION","ACCEPTANCE"]):
        if any(k in low for k in [
            "report", "summary", "status", "decision", "closure",
            "result", "log", "evidence", "output"
        ]):
            return "AUTHORITATIVE_OR_OPERATIONAL_EVIDENCE"
    if Path(name).suffix.lower() in CODE_EXTS:
        return "SOURCE_ONLY"
    return "SUPPORTING_EVIDENCE"

def targeted_scan(roots):
    inventory = []
    units = []
    for root_name, root in roots.items():
        if not root.exists():
            raise RuntimeError(f"TARGET_ROOT_MISSING={root}")
        for p in root.rglob("*"):
            if not p.is_file():
                continue
            rel = str(p.relative_to(root)).replace("\\", "/")
            logical = f"{root_name}/{rel}"

            top_targeted = bool(TARGET_NAME_RE.search(logical))
            members = read_targeted_zip_members(p) if p.suffix.lower() == ".zip" else []

            # Do not open ordinary unrelated files.
            if not top_targeted and not members:
                continue

            text = safe_text(p) if top_targeted else ""
            roles = classify_roles(logical, text)
            auth = authority_level(logical, roles)
            sha = sha256_file(p)

            inventory.append({
                "source_path": str(p),
                "logical_path": logical,
                "archive_member": "",
                "file_sha256": sha,
                "size_bytes": p.stat().st_size,
                "file_type": p.suffix.lower() or "<none>",
                "target_reason": "TOP_LEVEL_NAME_MATCH" if top_targeted else "TARGETED_ARCHIVE_MEMBER_ONLY",
                "artifact_class": "|".join(roles),
                "evidence_authority": auth,
            })
            if top_targeted:
                units.append({
                    "source_path": str(p),
                    "logical_path": logical,
                    "archive_member": "",
                    "file_sha256": sha,
                    "text": text,
                    "roles": roles,
                    "authority": auth,
                })

            for member, mtext in members:
                mlogical = f"{logical}::{member}"
                mroles = classify_roles(mlogical, mtext)
                mauth = authority_level(mlogical, mroles)
                inventory.append({
                    "source_path": str(p),
                    "logical_path": logical,
                    "archive_member": member,
                    "file_sha256": sha,
                    "size_bytes": "",
                    "file_type": Path(member).suffix.lower() or "<none>",
                    "target_reason": "ARCHIVE_MEMBER_NAME_MATCH",
                    "artifact_class": "|".join(mroles),
                    "evidence_authority": mauth,
                })
                units.append({
                    "source_path": f"{p}::{member}",
                    "logical_path": logical,
                    "archive_member": member,
                    "file_sha256": sha,
                    "text": mtext,
                    "roles": mroles,
                    "authority": mauth,
                })
    return inventory, units

def context_around(text: str, start: int, end: int, lines_before=2, lines_after=2):
    lines = text.splitlines()
    line_no = text.count("\n", 0, start) + 1
    a = max(0, line_no - 1 - lines_before)
    b = min(len(lines), line_no + lines_after)
    return line_no, " | ".join(lines[a:b])[:3500]

def is_example_context(context: str) -> bool:
    return bool(EXAMPLE_CONTEXT_RE.search(context))

def find_signals(units, stage: str, patterns, require_context=None, roles=None):
    rows = []
    for u in units:
        if roles and not any(r in u["roles"] for r in roles):
            continue
        text = u["text"]
        if not text:
            continue
        if require_context and not require_context.search(u["source_path"] + "\n" + text[:300000]):
            continue
        for label, polarity, rgx in patterns:
            for m in rgx.finditer(text):
                ln, ctx = context_around(text, m.start(), m.end())
                if is_example_context(ctx):
                    continue
                rows.append({
                    "stage": stage,
                    "signal_label": label,
                    "polarity": polarity,
                    "source_path": u["source_path"],
                    "file_sha256": u["file_sha256"],
                    "artifact_class": "|".join(u["roles"]),
                    "evidence_authority": u["authority"],
                    "line_number": ln,
                    "matched_text": m.group(0)[:1500],
                    "context": ctx,
                })
    return rows

B1B_PATTERNS = [
    ("MORE_DIAGNOSTIC_DATA_REQUIRED", "POSITIVE",
     re.compile(r"(?i)\bMORE[_ ]DIAGNOSTIC[_ ]DATA[_ ]REQUIRED\b")),
    ("B1B_STATUS_PASS", "POSITIVE",
     re.compile(r"(?i)\bB1B(?:1)?[_ -]?(?:STATUS|DECISION|DIAGNOSTIC_DECISION)\s*=\s*PASS\b")),
]

EXEC_PATTERNS = [
    ("R1_EXECUTION_EXPLICIT_YES", "POSITIVE",
     re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?EXECUTED\s*=\s*YES\b")),
    ("EXECUTION_STATUS_PASS", "POSITIVE",
     re.compile(r"(?i)\b(?:R1[_ -]?)?(?:PROTOTYPE[_ -]?)?EXECUTION[_ -]?(?:STATUS|DECISION)\s*=\s*(?:PASS|SUCCESS|COMPLETED)\b")),
    ("RUN_STATUS_PASS", "POSITIVE",
     re.compile(r"(?i)\bRUN[_ -]?STATUS\s*=\s*(?:PASS|SUCCESS|COMPLETED)\b")),
    ("EXIT_CODE_ZERO", "POSITIVE",
     re.compile(r"(?i)\bEXIT[_ -]?CODE\s*=\s*0\b")),
    ("RUNNER_COMPLETED", "POSITIVE",
     re.compile(r"(?i)\b(?:prototype|r1|runner)[^\n]{0,100}\bcompleted successfully\b|\brunner completed\b|\bprototype completed\b")),
    ("EXECUTION_EXPLICIT_NO", "NEGATIVE",
     re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?EXECUTED\s*=\s*NO\b")),
    ("EXECUTION_NOT_OCCURRED", "NEGATIVE",
     re.compile(r"(?i)\b(?:not executed|never executed|execution did not occur|no r1 execution|r1 execution prohibited|blocked before execution)\b")),
]

BENCH_PATTERNS = [
    ("R1_BENCHMARK_PASS", "POSITIVE",
     re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)?[_ -]?BENCHMARK(?:[_ -]?(?:STATUS|DECISION|VALIDATION))?\s*=\s*PASS\b")),
    ("BENCHMARKED_YES", "POSITIVE",
     re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?BENCHMARKED\s*=\s*YES\b")),
    ("BENCHMARK_COMPLETED_PASS", "POSITIVE",
     re.compile(r"(?i)\b(?:benchmark|scalability|fixture|reproducibility)[^\n]{0,120}\b(?:PASS|PASSED|SUCCESS)\b")),
    ("BENCHMARK_EXPLICIT_NO", "NEGATIVE",
     re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?BENCHMARKED\s*=\s*NO\b")),
    ("BENCHMARK_NOT_OCCURRED", "NEGATIVE",
     re.compile(r"(?i)\b(?:not benchmarked|benchmark not performed|no r1 benchmark|benchmarking did not occur)\b")),
]

ACCEPT_PATTERNS = [
    ("R1_ACCEPTED_YES", "POSITIVE",
     re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?(?:ACCEPTED|VALIDATED|APPROVED)\s*=\s*YES\b")),
    ("R1_VALIDATION_PASS", "POSITIVE",
     re.compile(r"(?i)\bR1[_ -]?(?:VALIDATION|FINAL_DECISION|FINAL_STATUS)(?:[_ -]?(?:STATUS|DECISION))?\s*=\s*PASS\b")),
    ("READY_FOR_PRODUCTION", "POSITIVE",
     re.compile(r"(?i)\bREADY[_ -]?FOR[_ -]?(?:BIOLOGICAL[_ -]?EXECUTION|PRODUCTION|FULL[_ -]?NETWORK[_ -]?RUN)\s*=\s*YES\b")),
    ("FINAL_ACCEPTANCE", "POSITIVE",
     re.compile(r"(?i)\bFINAL[_ -]?ACCEPTANCE\s*=\s*(?:YES|PASS|ACCEPTED)\b")),
    ("R1_REJECTED", "NEGATIVE",
     re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?(?:REJECTED|ACCEPTED)\s*=\s*(?:YES|NO)\b")),
    ("R1_FAIL_CLOSED", "NEGATIVE",
     re.compile(r"(?i)\bR1[^\n]{0,80}\bFAIL[_ -]?CLOSED\b")),
    ("R1_REANALYSIS_REQUIRED", "NEGATIVE",
     re.compile(r"(?i)\bR1[^\n]{0,100}\bREANALYSIS[_ -]?REQUIRED\b")),
    ("R1_NOT_READY", "NEGATIVE",
     re.compile(r"(?i)\bREADY[_ -]?FOR[_ -]?(?:BIOLOGICAL[_ -]?EXECUTION|PRODUCTION|FULL[_ -]?NETWORK[_ -]?RUN)\s*=\s*NO\b")),
]

def decision_from_signals(signals, stage: str):
    stage_rows = [r for r in signals if r["stage"] == stage]
    auth_rows = [
        r for r in stage_rows
        if r["evidence_authority"] == "AUTHORITATIVE_OR_OPERATIONAL_EVIDENCE"
    ]
    pos = [r for r in auth_rows if r["polarity"] == "POSITIVE"]
    neg = [r for r in auth_rows if r["polarity"] == "NEGATIVE"]
    if pos and neg:
        return "UNRESOLVED", pos[0], "CONFLICTING_AUTHORITATIVE_EVIDENCE"
    if pos:
        return "YES", pos[0], ""
    if neg:
        return "NO", neg[0], ""
    # Supporting/source evidence can never prove NO. It may support REVIEW_REQUIRED,
    # but no authoritative positive => unresolved.
    pos_support = [r for r in stage_rows if r["polarity"] == "POSITIVE"]
    if pos_support:
        return "UNRESOLVED", pos_support[0], "POSITIVE_SIGNAL_NOT_IN_AUTHORITATIVE_EXECUTION_DECISION_ARTIFACT"
    return "UNRESOLVED", None, "NO_AUTHORITATIVE_STAGE_DECISION_FOUND"

def parse_python(path: Path):
    text = safe_text(path)
    try:
        tree = ast.parse(text)
    except Exception:
        return None
    imports, funcs = [], []
    main_guard = False
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            imports.extend(a.name for a in n.names)
        elif isinstance(n, ast.ImportFrom) and n.module:
            imports.append(n.module)
        elif isinstance(n, ast.FunctionDef):
            funcs.append(n.name)
        elif isinstance(n, ast.If):
            try:
                cond = ast.unparse(n.test)
            except Exception:
                cond = ""
            if "__name__" in cond and "__main__" in cond:
                main_guard = True
    return {
        "text": text,
        "imports": sorted(set(imports)),
        "functions": sorted(set(funcs)),
        "main_guard": main_guard,
    }

def identify_r1_sources(inventory, units):
    candidates = []
    referenced_names = Counter()
    for u in units:
        text = u["text"]
        if not text:
            continue
        for m in re.finditer(r"(?i)\b(?:RUN_)?ACLA_R1[A-Za-z0-9_. -]*\.py\b|\bR1[A-Za-z0-9_. -]*(?:prototype|implementation)[A-Za-z0-9_. -]*\.py\b", text):
            referenced_names[Path(m.group(0).strip()).name.lower()] += 1

    seen = set()
    for r in inventory:
        if r["archive_member"]:
            continue
        p = Path(r["source_path"])
        if p in seen or p.suffix.lower() != ".py":
            continue
        seen.add(p)
        logical = r["logical_path"]
        if not R1_CONTEXT_RE.search(logical):
            continue
        low = p.name.lower()
        if any(k in low for k in ["test_", "validate", "audit", "review", "benchmark", "preflight"]):
            continue
        meta = parse_python(p)
        if meta is None:
            continue
        score = 0
        if meta["main_guard"]:
            score += 5
        if low.startswith("run_acla_r1") or low.startswith("run_r1"):
            score += 6
        if "prototype" in low:
            score += 4
        if "implementation" in low:
            score += 4
        score += min(5, referenced_names[p.name.lower()])
        if "acla" in meta["text"].lower():
            score += 1
        candidates.append({
            "path": str(p),
            "sha256": sha256_file(p),
            "score": score,
            "main_guard": "YES" if meta["main_guard"] else "NO",
            "reference_count": referenced_names[p.name.lower()],
        })
    candidates.sort(key=lambda x: (-x["score"], x["path"].lower()))
    return candidates

def local_dependencies(entry: Path, code_root: Path):
    req = {entry.resolve()}
    queue = [entry.resolve()]
    while queue:
        p = queue.pop()
        meta = parse_python(p)
        if not meta:
            continue
        for mod in meta["imports"]:
            top = mod.split(".")[0]
            cands = [
                p.parent / f"{top}.py",
                code_root / f"{top}.py",
                p.parent / top / "__init__.py",
                code_root / top / "__init__.py",
            ]
            found = next((c for c in cands if c.is_file()), None)
            if found:
                found = found.resolve()
                if found not in req:
                    req.add(found)
                    queue.append(found)
    return sorted(req, key=lambda p: str(p).lower())

def signed_weight_audit(entry: Path):
    text = safe_text(entry).lower()
    drop = bool(
        re.search(r"\.where\(\s*[^)]*>\s*0\s*,\s*0", text)
        or re.search(r"\bif\s+[^\n:]*weight[^\n:]*>\s*0", text)
        or "positive weights only" in text
    )
    absolutize = bool(
        "np.abs(" in text
        or re.search(r"\babs\s*\([^)]*weight", text)
    )
    clip = bool(
        ("np.clip(" in text or ".clip(" in text) and "weight" in text
    )
    weight_used = "weight" in text
    if drop:
        return {
            "policy": "DROPS_OR_ZEROS_NONPOSITIVE_WEIGHTS",
            "preserved": "NO",
            "dropped": "YES",
            "absolutized": "NO",
            "compatible": "NO",
            "blocker": "YES",
        }
    if absolutize:
        return {
            "policy": "ABSOLUTIZES_SIGNED_WEIGHTS",
            "preserved": "NO",
            "dropped": "NO",
            "absolutized": "YES",
            "compatible": "NO",
            "blocker": "YES",
        }
    if clip:
        return {
            "policy": "WEIGHT_CLIPPING_DETECTED",
            "preserved": "NO",
            "dropped": "NO",
            "absolutized": "NO",
            "compatible": "NO",
            "blocker": "YES",
        }
    if weight_used:
        return {
            "policy": "NO_SIGN_REMOVAL_TRANSFORMATION_DETECTED_STATIC_AUDIT",
            "preserved": "YES",
            "dropped": "NO",
            "absolutized": "NO",
            "compatible": "YES",
            "blocker": "NO",
        }
    return {
        "policy": "WEIGHT_USAGE_NOT_DEMONSTRATED",
        "preserved": "NO",
        "dropped": "NO",
        "absolutized": "NO",
        "compatible": "NO",
        "blocker": "YES",
    }

def write_evidence_text(path: Path, title: str, state: str, evidence, reason: str):
    lines = [
        title,
        f"STATE={state}",
        f"REASON={reason}",
    ]
    if evidence:
        lines += [
            f"EVIDENCE_FILE={evidence['source_path']}",
            f"EVIDENCE_SHA256={evidence['file_sha256']}",
            f"EVIDENCE_SIGNAL={evidence['signal_label']}",
            f"EVIDENCE_LINE={evidence['line_number']}",
            f"EVIDENCE_MATCH={evidence['matched_text']}",
            f"EVIDENCE_CONTEXT={evidence['context']}",
        ]
    else:
        lines += [
            "EVIDENCE_FILE=",
            "EVIDENCE_SHA256=",
        ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")

def self_test():
    # Key rule: absence of a token does NOT become NO.
    state, ev, reason = decision_from_signals([], "EXECUTION")
    assert state == "UNRESOLVED"
    # Explicit authoritative negative can become NO.
    fake = [{
        "stage":"EXECUTION","signal_label":"EXECUTION_EXPLICIT_NO","polarity":"NEGATIVE",
        "source_path":"final_status.txt","file_sha256":"0"*64,
        "artifact_class":"ACCEPTANCE","evidence_authority":"AUTHORITATIVE_OR_OPERATIONAL_EVIDENCE",
        "line_number":1,"matched_text":"R1_IMPLEMENTATION_EXECUTED=NO",
        "context":"R1_IMPLEMENTATION_EXECUTED=NO",
    }]
    state, _, _ = decision_from_signals(fake, "EXECUTION")
    assert state == "NO"
    print("D10A_V3_INTERNAL_SELFTEST=PASS")
    print("ABSENCE_DOES_NOT_EQUAL_NO=PASS")
    return 0

def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        return self_test()
    if len(sys.argv) != 6:
        raise SystemExit(
            "usage: D10A_V3.py <reusable_root> <d9_run> <outdir> <result_json> <project_root>"
        )

    reusable = Path(sys.argv[1])
    d9_run = Path(sys.argv[2])
    outdir = Path(sys.argv[3])
    result_json = Path(sys.argv[4])
    project_root = Path(sys.argv[5])
    outdir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------
    # D9 read-only recertification
    # ------------------------------------------------------
    recertify_manifest(d9_run / "D9_SHA256_MANIFEST.csv", "D9")
    d9_status = (d9_run / "D9_FINAL_STATUS.txt").read_text(
        encoding="utf-8-sig", errors="replace"
    )
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

    nodes = pd.read_csv(d9_run / "D9_MASTER_NODES.csv", dtype={"node_id": str})
    edges = pd.read_csv(
        d9_run / "D9_MASTER_EDGES.csv",
        dtype={"source": str, "target": str},
        float_precision="round_trip",
    )
    if len(nodes) != EXPECTED_NODES or nodes["node_id"].duplicated().any():
        raise RuntimeError("D9_NODE_GATE_FAILED")
    if len(edges) != EXPECTED_EDGES or edges.duplicated(["source","target"]).any():
        raise RuntimeError("D9_EDGE_GATE_FAILED")

    w = pd.to_numeric(edges["association_score"], errors="coerce").to_numpy(float)
    if (~np.isfinite(w)).sum():
        raise RuntimeError("D9_INVALID_WEIGHTS")
    wmin, wmax = float(w.min()), float(w.max())
    if not math.isclose(wmin, EXPECTED_WEIGHT_MIN, rel_tol=0, abs_tol=1e-15):
        raise RuntimeError(f"D9_WEIGHT_MIN_CHANGED={wmin}")
    if not math.isclose(wmax, EXPECTED_WEIGHT_MAX, rel_tol=0, abs_tol=1e-15):
        raise RuntimeError(f"D9_WEIGHT_MAX_CHANGED={wmax}")

    comps = component_stats(nodes["node_id"].tolist(), edges)
    if comps != {
        "components": EXPECTED_COMPONENTS,
        "largest": EXPECTED_LARGEST,
        "second": EXPECTED_SECOND,
        "isolated": 0,
    }:
        raise RuntimeError(f"D9_COMPONENT_GATE_FAILED={comps}")

    # ------------------------------------------------------
    # Targeted scan only
    # ------------------------------------------------------
    roots = {
        "01_ACLA_CODE": reusable / "01_ACLA_CODE",
        "07_METHODS_AND_DOCUMENTATION": reusable / "07_METHODS_AND_DOCUMENTATION",
        "09_OLD_METHOD_HISTORY": reusable / "09_OLD_METHOD_HISTORY",
    }
    inventory, units = targeted_scan(roots)
    if not inventory:
        raise RuntimeError("TARGETED_FILES_REVIEWED=0")

    inv_df = pd.DataFrame(inventory)
    inv_df.to_csv(outdir / "D10A_V3_TARGETED_ARTIFACT_INVENTORY.csv", index=False)

    # ------------------------------------------------------
    # B1B evidence
    # ------------------------------------------------------
    b1b_rows = find_signals(
        units, "B1B", B1B_PATTERNS,
        require_context=B1B_CONTEXT_RE,
        roles=["BENCHMARK","VALIDATION","ACCEPTANCE","EXECUTION"],
    )
    b1b_auth = [
        r for r in b1b_rows
        if r["evidence_authority"] == "AUTHORITATIVE_OR_OPERATIONAL_EVIDENCE"
    ]
    b1b_found = bool(b1b_auth)
    b1b_ev = b1b_auth[0] if b1b_auth else None
    b1b_decision = (
        b1b_ev["matched_text"] if b1b_ev else ""
    )

    # ------------------------------------------------------
    # R1 implementation source
    # ------------------------------------------------------
    source_candidates = identify_r1_sources(inventory, units)
    source_found = bool(source_candidates)
    entrypoint = Path(source_candidates[0]["path"]) if source_candidates else None
    entry_sha = source_candidates[0]["sha256"] if source_candidates else ""

    # Avoid pretending uniqueness if tied top candidates differ.
    source_ambiguous = False
    if len(source_candidates) > 1 and source_candidates[1]["score"] == source_candidates[0]["score"]:
        if source_candidates[1]["sha256"] != source_candidates[0]["sha256"]:
            source_ambiguous = True
            entrypoint = None
            entry_sha = ""

    # ------------------------------------------------------
    # Execution / benchmark / acceptance evidence
    # ------------------------------------------------------
    exec_rows = find_signals(
        units, "EXECUTION", EXEC_PATTERNS,
        require_context=R1_CONTEXT_RE,
        roles=["EXECUTION","VALIDATION","ACCEPTANCE"],
    )
    bench_rows = find_signals(
        units, "BENCHMARK", BENCH_PATTERNS,
        require_context=R1_CONTEXT_RE,
        roles=["BENCHMARK","VALIDATION","ACCEPTANCE"],
    )
    accept_rows = find_signals(
        units, "ACCEPTANCE", ACCEPT_PATTERNS,
        require_context=R1_CONTEXT_RE,
        roles=["ACCEPTANCE","VALIDATION"],
    )

    all_evidence = b1b_rows + exec_rows + bench_rows + accept_rows
    pd.DataFrame(all_evidence).to_csv(
        outdir / "D10A_V3_R1_LIFECYCLE_EVIDENCE.csv", index=False
    )

    exec_state, exec_ev, exec_reason = decision_from_signals(all_evidence, "EXECUTION")
    bench_state, bench_ev, bench_reason = decision_from_signals(all_evidence, "BENCHMARK")
    accept_state, accept_ev, accept_reason = decision_from_signals(all_evidence, "ACCEPTANCE")

    # Lifecycle ordering: later YES cannot override an earlier unresolved/NO gate.
    if exec_state != "YES" and bench_state == "YES":
        bench_state = "UNRESOLVED"
        bench_reason = "BENCHMARK_SIGNAL_EXISTS_BUT_EXECUTION_NOT_CERTIFIED"
    if bench_state != "YES" and accept_state == "YES":
        accept_state = "UNRESOLVED"
        accept_reason = "ACCEPTANCE_SIGNAL_EXISTS_BUT_BENCHMARK_NOT_CERTIFIED"

    write_evidence_text(
        outdir / "D10A_V3_R1_EXECUTION_EVIDENCE.txt",
        "D10A-V3 R1 EXECUTION EVIDENCE",
        exec_state, exec_ev, exec_reason
    )
    write_evidence_text(
        outdir / "D10A_V3_R1_BENCHMARK_EVIDENCE.txt",
        "D10A-V3 R1 BENCHMARK EVIDENCE",
        bench_state, bench_ev, bench_reason
    )
    write_evidence_text(
        outdir / "D10A_V3_R1_ACCEPTANCE_EVIDENCE.txt",
        "D10A-V3 R1 ACCEPTANCE EVIDENCE",
        accept_state, accept_ev, accept_reason
    )

    # ------------------------------------------------------
    # Final adjudication
    # ------------------------------------------------------
    r1_design_validated = "YES"  # inherited certified upstream state

    authoritative_found = (
        source_found
        and not source_ambiguous
        and exec_state == "YES"
        and bench_state == "YES"
        and accept_state == "YES"
        and entrypoint is not None
    )

    explicit_reject = (
        accept_state == "NO"
        and accept_ev is not None
        and accept_ev["signal_label"] in {
            "R1_REJECTED","R1_FAIL_CLOSED","R1_REANALYSIS_REQUIRED"
        }
    )

    failure_stage = ""
    failure_reason = ""
    status = ""

    if authoritative_found:
        status = "PASS"
    elif explicit_reject:
        status = "FAIL_CLOSED"
        failure_stage = "R1_EXPLICITLY_REJECTED"
        failure_reason = accept_ev["context"]
    elif source_found and exec_state == "NO":
        status = "FAIL_CLOSED"
        failure_stage = "R1_IMPLEMENTED_BUT_NOT_EXECUTED"
        failure_reason = exec_reason or (exec_ev["context"] if exec_ev else "")
    elif exec_state == "YES" and bench_state == "NO":
        status = "FAIL_CLOSED"
        failure_stage = "R1_EXECUTED_BUT_NOT_BENCHMARKED"
        failure_reason = bench_reason or (bench_ev["context"] if bench_ev else "")
    elif bench_state == "YES" and accept_state == "NO":
        status = "FAIL_CLOSED"
        failure_stage = "R1_BENCHMARKED_BUT_NOT_ACCEPTED"
        failure_reason = accept_reason or (accept_ev["context"] if accept_ev else "")
    else:
        status = "REVIEW_REQUIRED"
        if source_ambiguous:
            failure_stage = "R1_IMPLEMENTATION_ENTRYPOINT_AMBIGUOUS"
            failure_reason = "Multiple top-scoring R1 implementation entrypoints remain with different hashes."
        elif not source_found:
            failure_stage = "R1_IMPLEMENTATION_SOURCE_UNRESOLVED"
            failure_reason = "No targeted runnable R1 implementation source was identified."
        elif exec_state == "UNRESOLVED":
            failure_stage = "R1_EXECUTION_UNRESOLVED"
            failure_reason = exec_reason
        elif bench_state == "UNRESOLVED":
            failure_stage = "R1_BENCHMARK_UNRESOLVED"
            failure_reason = bench_reason
        elif accept_state == "UNRESOLVED":
            failure_stage = "R1_ACCEPTANCE_UNRESOLVED"
            failure_reason = accept_reason
        else:
            failure_stage = "R1_LIFECYCLE_UNRESOLVED"
            failure_reason = "Targeted evidence did not support a unique final lifecycle decision."

    # ------------------------------------------------------
    # Signed-weight audit only if accepted
    # ------------------------------------------------------
    signed_policy = ""
    neg_preserved = ""
    neg_dropped = ""
    neg_abs = ""
    d9_signed = "NOT_TESTED"
    signed_blocker = "NOT_TESTED"

    auth_manifest = outdir / "D10A_V3_AUTHORITATIVE_R1_IMPLEMENTATION_MANIFEST.csv"
    if authoritative_found and entrypoint is not None:
        sw = signed_weight_audit(entrypoint)
        signed_policy = sw["policy"]
        neg_preserved = sw["preserved"]
        neg_dropped = sw["dropped"]
        neg_abs = sw["absolutized"]
        d9_signed = sw["compatible"]
        signed_blocker = sw["blocker"]

        required = local_dependencies(entrypoint, roots["01_ACLA_CODE"])
        rows = []
        for p in required:
            rows.append({
                "role": "ENTRYPOINT" if p.resolve() == entrypoint.resolve() else "DEPENDENCY",
                "full_path": str(p),
                "size_bytes": p.stat().st_size,
                "SHA256": sha256_file(p),
            })
        pd.DataFrame(rows).to_csv(auth_manifest, index=False)
    elif auth_manifest.exists():
        auth_manifest.unlink()

    ready_parameter_freeze = (
        "YES"
        if authoritative_found and d9_signed == "YES" and signed_blocker == "NO"
        else "NO"
    )

    # Best available execution exit status is exact matched signal.
    exec_exit = ""
    if exec_ev:
        if exec_ev["signal_label"] == "EXIT_CODE_ZERO":
            exec_exit = "EXIT_CODE=0"
        elif exec_ev["polarity"] == "POSITIVE":
            exec_exit = exec_ev["matched_text"]
        else:
            exec_exit = exec_ev["matched_text"]

    result = {
        "D10A_V3_STATUS": status,
        "TARGETED_FILES_REVIEWED": len(inventory),
        "B1B_EVIDENCE_FOUND": "YES" if b1b_found else "NO",
        "B1B_DECISION": b1b_decision,
        "B1B_EVIDENCE_FILE": b1b_ev["source_path"] if b1b_ev else "",
        "B1B_EVIDENCE_SHA256": b1b_ev["file_sha256"] if b1b_ev else "",
        "R1_DESIGN_VALIDATED": r1_design_validated,
        "R1_IMPLEMENTATION_FOUND": "YES" if source_found else "NO",
        "R1_IMPLEMENTATION_ENTRYPOINT": str(entrypoint) if entrypoint else "",
        "R1_IMPLEMENTATION_SHA256": entry_sha,
        "R1_IMPLEMENTATION_SOURCE_FILES": "|".join(x["path"] for x in source_candidates[:20]),
        "R1_IMPLEMENTATION_EXECUTED": exec_state,
        "R1_EXECUTION_EVIDENCE_FILE": exec_ev["source_path"] if exec_ev else "",
        "R1_EXECUTION_EVIDENCE_SHA256": exec_ev["file_sha256"] if exec_ev else "",
        "R1_EXECUTION_ENTRYPOINT": str(entrypoint) if entrypoint and exec_state == "YES" else "",
        "R1_EXECUTION_EXIT_STATUS": exec_exit,
        "R1_EXECUTION_OUTPUTS_PRESENT": "YES" if exec_state == "YES" and exec_ev and any(
            k in exec_ev["context"].lower() for k in ["output","result","created","saved","written"]
        ) else ("NO" if exec_state == "NO" else "UNRESOLVED"),
        "R1_IMPLEMENTATION_BENCHMARKED": bench_state,
        "R1_BENCHMARK_EVIDENCE_FILE": bench_ev["source_path"] if bench_ev else "",
        "R1_BENCHMARK_EVIDENCE_SHA256": bench_ev["file_sha256"] if bench_ev else "",
        "R1_BENCHMARK_DECISION": bench_ev["matched_text"] if bench_ev else "",
        "R1_IMPLEMENTATION_ACCEPTED": accept_state,
        "R1_ACCEPTANCE_EVIDENCE_FILE": accept_ev["source_path"] if accept_ev else "",
        "R1_ACCEPTANCE_EVIDENCE_SHA256": accept_ev["file_sha256"] if accept_ev else "",
        "R1_ACCEPTANCE_DECISION": accept_ev["matched_text"] if accept_ev else "",
        "AUTHORITATIVE_ACLA_IMPLEMENTATION_FOUND": "YES" if authoritative_found else "NO",
        "FAILURE_STAGE": failure_stage,
        "FAILURE_REASON": failure_reason,
        "SIGNED_WEIGHTS_PRESENT": "YES",
        "D9_WEIGHT_MIN": wmin,
        "D9_WEIGHT_MAX": wmax,
        "R1_SIGNED_WEIGHT_POLICY": signed_policy,
        "NEGATIVE_WEIGHTS_PRESERVED": neg_preserved,
        "NEGATIVE_WEIGHTS_DROPPED": neg_dropped,
        "NEGATIVE_WEIGHTS_ABSOLUTIZED": neg_abs,
        "D9_SIGNED_WEIGHT_COMPATIBLE": d9_signed,
        "SIGNED_WEIGHT_COMPATIBILITY_BLOCKER": signed_blocker,
        "GSE243219_ACLA_EXECUTED": "NO",
        "NETWORK_CHANGED": "NO",
        "WEIGHT_TRANSFORMATION_APPLIED": "NO",
        "PARAMETER_TUNING_EXECUTED": "NO",
        "READY_FOR_ACLA_PARAMETER_FREEZE": ready_parameter_freeze,
        "READY_FOR_ACLA_EXECUTION": "NO",
        "STOP": "YES",
    }

    result_json.write_text(
        json.dumps(result, indent=2, sort_keys=True),
        encoding="utf-8"
    )
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
