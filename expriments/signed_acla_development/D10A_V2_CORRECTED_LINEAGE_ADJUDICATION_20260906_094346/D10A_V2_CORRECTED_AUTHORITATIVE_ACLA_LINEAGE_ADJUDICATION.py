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
from datetime import datetime
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_NODES = 4508
EXPECTED_EDGES = 11531
EXPECTED_WEIGHT_MIN = -0.7753835531973502
EXPECTED_WEIGHT_MAX = 0.7428957195865319

TEXT_EXTS = {
    ".py",".ps1",".txt",".md",".csv",".json",".yaml",".yml",
    ".toml",".ini",".r",".R",".jl",".m",".xml",".log"
}
CODE_EXTS = {".py",".r",".R",".jl",".m"}
AUTHORITATIVE_EVIDENCE_WORDS = (
    "decision","status","summary","report","closure","validation","audit",
    "evidence","execution","preflight","result","manifest"
)
NONDECISION_WORDS = (
    "readme","specification","plan","prompt","template","required","requirements",
    "design_contract","contract","source_and_config"
)

KNOWN_FAMILY_ORDER = [
    "ORIGINAL_PUBLISHED_ACLA",
    "EARLY_REFINED_ACLA",
    "V1","V2","V3","V4","V5","V6",
    "B1","B1A","B1B","B1C",
    "R1_PROTOTYPE","R1_IMPLEMENTATION",
]

def sha256_file(path: Path, chunk=8*1024*1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda: f.read(chunk), b""):
            h.update(b)
    return h.hexdigest()

def recertify_manifest(path: Path, label: str):
    if not path.is_file():
        raise RuntimeError(f"{label}_MANIFEST_MISSING={path}")
    df = pd.read_csv(path, dtype=str, keep_default_na=False)
    need = {"full_path","size_bytes","SHA256"}
    miss = need - set(df.columns)
    if miss:
        raise RuntimeError(f"{label}_MANIFEST_COLUMNS_MISSING={sorted(miss)}")
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

class UF:
    def __init__(self, nodes):
        self.p = {n:n for n in nodes}
        self.sz = {n:1 for n in nodes}
    def find(self, x):
        if self.p[x] != x:
            self.p[x] = self.find(self.p[x])
        return self.p[x]
    def union(self, a, b):
        ra, rb = self.find(a), self.find(b)
        if ra == rb: return
        if self.sz[ra] < self.sz[rb]:
            ra, rb = rb, ra
        self.p[rb] = ra
        self.sz[ra] += self.sz[rb]

def comp_stats(nodes, edges):
    uf = UF(nodes)
    deg = Counter({n:0 for n in nodes})
    for s,t in zip(edges["source"], edges["target"]):
        uf.union(s,t)
        deg[s]+=1; deg[t]+=1
    sizes = defaultdict(int)
    for n in nodes:
        sizes[uf.find(n)] += 1
    ss = sorted(sizes.values(), reverse=True)
    return {
        "components": len(ss),
        "largest": ss[0] if ss else 0,
        "second": ss[1] if len(ss)>1 else 0,
        "isolated": sum(1 for n in nodes if deg[n]==0),
    }

def safe_text(path: Path, max_bytes=20_000_000):
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

def archive_members(path: Path, max_members=6000, max_text_bytes=3_000_000):
    out = []
    if path.suffix.lower() != ".zip":
        return out
    try:
        with zipfile.ZipFile(path) as z:
            for info in z.infolist()[:max_members]:
                name = info.filename
                low = name.lower()
                if not any(k in low for k in [
                    "acla","b1a","b1b","b1c","r1","candidate_v",
                    "decision","closure","execution","validation","benchmark"
                ]):
                    continue
                text = ""
                ext = Path(name).suffix
                if info.file_size <= max_text_bytes and ext in TEXT_EXTS:
                    try:
                        text = z.read(info).decode("utf-8", errors="replace")
                    except Exception:
                        pass
                out.append((name,text))
    except Exception:
        pass
    return out

def classify_family_from_path(path_text: str) -> str:
    # IMPORTANT: path/filename only. Never classify family from document body.
    s = path_text.lower().replace("\\","/")
    name = Path(path_text).name.lower()

    # R1 implementation/prototype must be checked before B1/B1C.
    if re.search(r"r1[_ -]?(?:final[_ -]?)?implementation|implementation[_ -]?r1", s):
        return "R1_IMPLEMENTATION"
    if re.search(r"r1[_ -]?prototype|prototype[_ -]?r1", s):
        return "R1_PROTOTYPE"

    if re.search(r"b1c(?:\d+|[-_ ]?\d+)?", s):
        return "B1C"
    if re.search(r"b1b(?:\d+|[-_ ]?\d+)?", s):
        return "B1B"
    if re.search(r"b1a(?:\d+|[-_ ]?\d+)?", s):
        return "B1A"
    if re.search(r"(^|[^a-z0-9])b1([^a-z0-9]|$)", s):
        return "B1"

    for v in range(6,0,-1):
        if re.search(rf"(candidate|acla)[^/\n]*[_ -]v{v}\b|[_ -]v{v}\b[^/\n]*(candidate|acla)", s):
            return f"V{v}"

    if "probability_action_remap" in s or "probability-remap" in s:
        return "EARLY_REFINED_ACLA"
    if "a-cla_refin" in s or "acla_refin" in s or "refined_probability" in s:
        return "EARLY_REFINED_ACLA"

    if name in {"a-cla.py","acla.py"} or "original_acla" in s or "published_acla" in s:
        return "ORIGINAL_PUBLISHED_ACLA"

    return "CROSS_STAGE_DOCUMENTATION_OR_UTILITY"

def infer_role(path_text: str, is_archive_member=False):
    s = path_text.lower()
    if "final_decision" in s or re.search(r"(^|[_ -])decision([_. -]|$)", s):
        return "FINAL_DECISION"
    if "closure" in s:
        return "CLOSURE_REPORT"
    if "execution_report" in s or ("execution" in s and "report" in s):
        return "EXECUTION_REPORT"
    if "validation" in s or "validate" in s:
        return "VALIDATION_REPORT"
    if "benchmark" in s or "scalability" in s:
        return "BENCHMARK"
    if "preflight" in s:
        return "PREFLIGHT"
    if "evidence" in s and "report" in s:
        return "EVIDENCE_REPORT"
    if "audit" in s:
        return "AUDIT_REPORT"
    if "summary" in s or "status" in s:
        return "SUMMARY_STATUS"
    if "manifest" in s or "sha256" in s:
        return "MANIFEST"
    if Path(path_text).suffix.lower() == ".py":
        if "run_" in Path(path_text).name.lower():
            return "RUNNER_SOURCE"
        return "CORE_OR_HELPER_SOURCE"
    if Path(path_text).suffix.lower() == ".ps1":
        return "POWERSHELL_RUNNER"
    return "OTHER"

def evidence_authority(role: str, path_text: str):
    low = path_text.lower()
    if any(x in low for x in NONDECISION_WORDS):
        return "NONAUTHORITATIVE_DESIGN_OR_EXAMPLE"
    if role in {
        "FINAL_DECISION","CLOSURE_REPORT","EXECUTION_REPORT","VALIDATION_REPORT",
        "BENCHMARK","PREFLIGHT","EVIDENCE_REPORT","AUDIT_REPORT","SUMMARY_STATUS"
    }:
        return "DECISION_EVIDENCE"
    return "NONDECISION"

def scan_roots(roots):
    inventory = []
    evidence_units = []
    for root_name, root in roots.items():
        if not root.exists():
            raise RuntimeError(f"AUTHORIZED_SEARCH_ROOT_MISSING={root}")
        for p in root.rglob("*"):
            if not p.is_file():
                continue
            rel = str(p.relative_to(root)).replace("\\","/")
            rel_full = f"{root_name}/{rel}"
            text = safe_text(p)
            members = archive_members(p)

            probe = rel_full.lower()
            if text:
                probe += "\n" + text[:300000].lower()
            if members:
                probe += "\n" + "\n".join(x[0].lower() for x in members[:1000])

            if not any(k in probe for k in [
                "acla","a-cla","b1a","b1b","b1c","r1",
                "candidate_v1","candidate_v2","candidate_v3",
                "candidate_v4","candidate_v5","candidate_v6"
            ]):
                continue

            fam = classify_family_from_path(rel_full)
            role = infer_role(rel_full)
            auth = evidence_authority(role, rel_full)
            row = {
                "path": str(p),
                "relative_path": rel_full,
                "filename": p.name,
                "SHA256": sha256_file(p),
                "size_bytes": p.stat().st_size,
                "file_type": p.suffix.lower() or "<none>",
                "likely_role": role,
                "implementation_family": fam,
                "version_or_branch_label": fam,
                "status_evidence": "",
                "dependency_or_entrypoint_relationship": "",
                "evidence_authority": auth,
                "archive_relevant_members": len(members),
            }
            inventory.append(row)
            if text:
                evidence_units.append({
                    "source_path": str(p),
                    "relative_path": rel_full,
                    "family": fam,
                    "role": role,
                    "authority": auth,
                    "text": text,
                    "SHA256": row["SHA256"],
                })
            for member_name, member_text in members:
                mrel = f"{rel_full}::{member_name}"
                mfam = classify_family_from_path(mrel)
                mrole = infer_role(mrel, True)
                mauth = evidence_authority(mrole, mrel)
                evidence_units.append({
                    "source_path": f"{p}::{member_name}",
                    "relative_path": mrel,
                    "family": mfam,
                    "role": mrole,
                    "authority": mauth,
                    "text": member_text,
                    "SHA256": row["SHA256"],
                })
    return inventory, evidence_units

def parse_python(path: Path):
    text = safe_text(path)
    try:
        tree = ast.parse(text)
    except Exception as e:
        return {"compile":"FAIL","error":str(e),"text":text}
    imports=[]; funcs=[]; constants={}; main=False; argparse=False
    for n in ast.walk(tree):
        if isinstance(n, ast.Import):
            imports += [a.name for a in n.names]
        elif isinstance(n, ast.ImportFrom) and n.module:
            imports.append(n.module)
        elif isinstance(n, ast.FunctionDef):
            funcs.append(n.name)
        elif isinstance(n, ast.If):
            try: cond=ast.unparse(n.test)
            except Exception: cond=""
            if "__name__" in cond and "__main__" in cond: main=True
        elif isinstance(n, ast.Call):
            try: fn=ast.unparse(n.func)
            except Exception: fn=""
            if "ArgumentParser" in fn or "add_argument" in fn: argparse=True
        elif isinstance(n,(ast.Assign,ast.AnnAssign)):
            targets=n.targets if isinstance(n,ast.Assign) else [n.target]
            val=n.value
            for t in targets:
                if isinstance(t,ast.Name) and t.id.isupper():
                    try: constants[t.id]=ast.literal_eval(val)
                    except Exception:
                        try: constants[t.id]=ast.unparse(val)
                        except Exception: constants[t.id]="<NONLITERAL>"
    return {
        "compile":"PASS","error":"","text":text,
        "imports":sorted(set(imports)),
        "functions":sorted(set(funcs)),
        "constants":constants,
        "main_guard":main,
        "argparse":argparse,
    }

def semantics(path: Path):
    m = parse_python(path)
    if m["compile"] != "PASS":
        return None
    low = m["text"].lower()
    if "read_edgelist" in low or ("read_csv" in low and "source" in low and "target" in low):
        schema="EDGE_LIST"
    elif "adjacency" in low and ("read_csv" in low or "from_pandas_adjacency" in low):
        schema="ADJACENCY_MATRIX"
    elif "np.load" in low and "row" in low and "col" in low:
        schema="SPARSE_COO_OR_NPZ"
    elif "networkx" in low and re.search(r"def\s+\w+\s*\(\s*g\b", low):
        schema="NETWORKX_GRAPH_OBJECT"
    else:
        schema="UNRESOLVED"

    drop = bool(
        re.search(r"\.where\(\s*[^)]*>\s*0\s*,\s*0", low)
        or re.search(r"\bweight\s*>\s*0\b", low)
    )
    absolutize = "np.abs(" in low or bool(re.search(r"\babs\s*\([^)]*weight", low))
    clip = "np.clip(" in low and "weight" in low
    if drop:
        signed="DROPS_OR_ZEROS_NONPOSITIVE_WEIGHTS"; neg="NO"
    elif absolutize:
        signed="ABSOLUTIZES_SIGNED_WEIGHTS"; neg="NO"
    elif clip:
        signed="CLIPS_WEIGHTS_REVIEW_REQUIRED"; neg="NO_OR_UNCERTAIN"
    elif "weight" in low:
        signed="NO_SIGN_REMOVAL_TRANSFORM_DETECTED_STATIC_ONLY"; neg="YES_STATIC_ONLY"
    else:
        signed="WEIGHT_USAGE_UNRESOLVED"; neg="UNRESOLVED"

    objective="MODULARITY_OR_DERIVED" if "modularity" in low else "UNRESOLVED"
    init="EACH_NODE_OWN_COMMUNITY" if (
        "each node is its own community" in low
        or re.search(r"hard_labels\s*=\s*\{n:\s*i", m["text"])
    ) else "UNRESOLVED"
    stop="TOLERANCE_PLUS_PATIENCE" if "patience" in low and ("tol" in low or "converg" in low) else (
        "MAX_ITERATIONS_OR_CUSTOM" if "max_iter" in low else "UNRESOLVED"
    )
    return {
        "input_schema":schema,
        "objective_function":objective,
        "initialization":init,
        "stopping_rule":stop,
        "signed_weight_policy":signed,
        "negative_edges_preserved":neg,
        "regulatory_layer_handling":(
            "NATIVE_REGULATORY_CHANNEL_REFERENCED"
            if any(k in low for k in ["regulatory","tarbase","targetscan","mirdb"])
            else "NO_NATIVE_REGULATORY_CHANNEL_DETECTED"
        ),
        "multilayer_handling":(
            "NATIVE_MULTILAYER_LOGIC_DETECTED"
            if "multilayer" in low or "layer_mass" in low or "within_layer" in low
            else "NO_NATIVE_MULTILAYER_LOGIC_DETECTED"
        ),
        "randomness":(
            "|".join(x for x in ["random.seed","np.random.seed","default_rng"]
                     if x in low)
            or "NO_EXPLICIT_RANDOM_CALL_DETECTED"
        ),
        "constants":m["constants"],
        "compile":"PASS",
    }

def local_deps(entry: Path, root: Path):
    req={entry.resolve()}; q=[entry.resolve()]
    while q:
        p=q.pop()
        m=parse_python(p)
        if m["compile"]!="PASS": continue
        for mod in m["imports"]:
            top=mod.split(".")[0]
            cands=[p.parent/f"{top}.py",root/f"{top}.py",p.parent/top/"__init__.py",root/top/"__init__.py"]
            found=next((c for c in cands if c.is_file()),None)
            if found:
                found=found.resolve()
                if found not in req:
                    req.add(found); q.append(found)
    return sorted(req,key=lambda p:str(p).lower())

def candidate_entrypoints(family_rows):
    scored=[]
    for r in family_rows:
        p=Path(r["path"])
        if p.suffix.lower()!=".py": continue
        low=p.name.lower()
        if any(k in low for k in ["test_","validate","audit","review","benchmark","preflight"]):
            continue
        m=parse_python(p)
        if m["compile"]!="PASS": continue
        score=0
        if m.get("main_guard"): score+=5
        if m.get("argparse"): score+=3
        if low.startswith("run_acla"): score+=4
        if "prototype" in low: score+=3
        if "implementation" in low: score+=3
        if "acla" in low: score+=1
        scored.append((score,p))
    scored.sort(key=lambda x:(-x[0],str(x[1]).lower()))
    return scored

def decision_units(evidence_units, family=None):
    out=[]
    for e in evidence_units:
        if family and e["family"]!=family: continue
        if e["authority"]!="DECISION_EVIDENCE": continue
        if not e["text"]: continue
        out.append(e)
    return out

def token_evidence(units, regexes, label):
    rec=[]
    for u in units:
        text=u["text"]
        for rgx in regexes:
            for m in rgx.finditer(text):
                line_no=text.count("\n",0,m.start())+1
                lines=text.splitlines()
                line=lines[line_no-1] if line_no-1<len(lines) else ""
                # Reject explicit example/expected/required statements near the match.
                context="\n".join(lines[max(0,line_no-3):min(len(lines),line_no+2)])
                if re.search(r"(?i)\b(expected|example|required|template|should report|if pass|pass criteria)\b",context):
                    continue
                rec.append({
                    "evidence_type":label,
                    "source_path":u["source_path"],
                    "relative_path":u["relative_path"],
                    "family":u["family"],
                    "role":u["role"],
                    "line_number":line_no,
                    "matched_text":m.group(0)[:1000],
                    "line_text":line[:1500],
                    "SHA256":u["SHA256"],
                })
    return rec

def any_valid(records, label):
    return any(r["evidence_type"]==label for r in records)

def main():
    if len(sys.argv)!=7:
        raise SystemExit(
            "usage: script <project> <reusable> <d9_run> <v2_run_or_NONE> <outdir> <result_json>"
        )
    project=Path(sys.argv[1]); reusable=Path(sys.argv[2]); d9=Path(sys.argv[3])
    v2=None if sys.argv[4]=="NONE" else Path(sys.argv[4])
    out=Path(sys.argv[5]); result_path=Path(sys.argv[6]); out.mkdir(parents=True,exist_ok=True)

    # --- D9 integrity ---
    recertify_manifest(d9/"D9_SHA256_MANIFEST.csv","D9")
    d9text=(d9/"D9_FINAL_STATUS.txt").read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D9_STATUS=PASS","TOTAL_NODES=4508","TOTAL_STRUCTURAL_EDGES=11531",
        "CONNECTED_COMPONENTS=2","LARGEST_COMPONENT_NODES=4502",
        "ACLA_EXECUTED=NO","D9_HASH_MISMATCHES=0"
    ]:
        if tok not in d9text: raise RuntimeError(f"D9_STATUS_TOKEN_MISSING={tok}")
    nodes=pd.read_csv(d9/"D9_MASTER_NODES.csv",dtype={"node_id":str})
    edges=pd.read_csv(d9/"D9_MASTER_EDGES.csv",dtype={"source":str,"target":str},float_precision="round_trip")
    if len(nodes)!=EXPECTED_NODES or nodes["node_id"].duplicated().any(): raise RuntimeError("D9_NODE_GATE_FAILED")
    if len(edges)!=EXPECTED_EDGES or edges.duplicated(["source","target"]).any(): raise RuntimeError("D9_EDGE_GATE_FAILED")
    w=pd.to_numeric(edges["association_score"],errors="coerce").to_numpy(float)
    if (~np.isfinite(w)).sum(): raise RuntimeError("D9_INVALID_WEIGHTS")
    wmin,wmax=float(w.min()),float(w.max())
    if not math.isclose(wmin,EXPECTED_WEIGHT_MIN,rel_tol=0,abs_tol=1e-15): raise RuntimeError("D9_WEIGHT_MIN_CHANGED")
    if not math.isclose(wmax,EXPECTED_WEIGHT_MAX,rel_tol=0,abs_tol=1e-15): raise RuntimeError("D9_WEIGHT_MAX_CHANGED")
    cs=comp_stats(nodes["node_id"].tolist(),edges)
    if cs!={"components":2,"largest":4502,"second":6,"isolated":0}: raise RuntimeError(f"D9_COMPONENT_GATE_FAILED={cs}")

    # prior V2 provenance only
    prior_v2_recertified="NO"
    if v2 and (v2/"D10A_V2_SHA256_MANIFEST.csv").is_file():
        recertify_manifest(v2/"D10A_V2_SHA256_MANIFEST.csv","D10A_V2_PREVIOUS")
        prior_v2_recertified="YES"

    roots={
        "01_ACLA_CODE":reusable/"01_ACLA_CODE",
        "07_METHODS_AND_DOCUMENTATION":reusable/"07_METHODS_AND_DOCUMENTATION",
        "08_REPRODUCIBILITY_UTILITIES":reusable/"08_REPRODUCIBILITY_UTILITIES",
        "09_OLD_METHOD_HISTORY":reusable/"09_OLD_METHOD_HISTORY",
    }
    inv,eunits=scan_roots(roots)
    if not inv: raise RuntimeError("DISCOVERED_ACLA_FILES=0")
    invdf=pd.DataFrame(inv)
    invdf.to_csv(out/"D10A_V2_ACLA_FILE_INVENTORY.csv",index=False)

    # --- stage evidence, decision/report only ---
    all_decision=decision_units(eunits)
    records=[]

    records += token_evidence(all_decision,[
        re.compile(r"(?i)\bB1A(?:[-_ ]?0)?[_ -]?(?:PREFLIGHT|STATUS|DECISION)[^=\n]{0,80}=\s*PASS\b"),
        re.compile(r"(?i)\bB1A\b[^\n]{0,120}\bPREFLIGHT\b[^\n]{0,80}\bPASS\b"),
    ],"B1A_PREFLIGHT_PASS")
    records += token_evidence(all_decision,[
        re.compile(r"(?i)\bB1A[-_ ]?1\b[^\n]{0,160}\bPASS\b"),
        re.compile(r"(?i)\bB1A(?:_FINAL)?_ANALYSIS[^=\n]{0,80}=\s*PASS\b"),
    ],"B1A1_ANALYSIS_PASS")
    records += token_evidence(all_decision,[
        re.compile(r"(?i)\bB1B(?:[-_ ]?1)?\b[^\n]{0,180}MORE_DIAGNOSTIC_DATA_REQUIRED"),
        re.compile(r"(?i)MORE_DIAGNOSTIC_DATA_REQUIRED[^\n]{0,180}\bB1B\b"),
    ],"B1B_MORE_DIAGNOSTIC_DATA_REQUIRED")
    records += token_evidence(all_decision,[
        re.compile(r"(?i)\bB1C[-_ ]?0\b[^\n]{0,180}\bPASS\b"),
        re.compile(r"(?i)\bPREFLIGHT_DECISION\s*=\s*READY_FOR_R1_PROTOTYPE_IMPLEMENTATION\b"),
        re.compile(r"(?i)\bFROZEN_R1_DESIGN_HASH\s*=\s*f0d4ce5f[0-9a-f]*\b"),
    ],"B1C0_R1_DESIGN_PASS")

    # R1 implementation lifecycle: stage-specific authoritative evidence only.
    r1_units=[
        u for u in all_decision
        if u["family"] in {"R1_PROTOTYPE","R1_IMPLEMENTATION","B1C"}
        and (
            "r1" in u["relative_path"].lower()
            or "prototype" in u["text"].lower()
            or "implementation" in u["text"].lower()
        )
    ]
    records += token_evidence(r1_units,[
        re.compile(r"(?i)\bR1_(?:PROTOTYPE|IMPLEMENTATION)_(?:CREATED|IMPLEMENTED)\s*=\s*YES\b"),
        re.compile(r"(?i)\bIMPLEMENTATION_CREATED\s*=\s*YES\b"),
    ],"R1_IMPLEMENTATION_CREATED")
    records += token_evidence(r1_units,[
        re.compile(r"(?i)\bR1_(?:PROTOTYPE|IMPLEMENTATION)_EXECUTED\s*=\s*YES\b"),
        re.compile(r"(?i)\bPROTOTYPE_EXECUTION_STATUS\s*=\s*PASS\b"),
        re.compile(r"(?i)\bR1_IMPLEMENTATION_EXECUTION_STATUS\s*=\s*PASS\b"),
    ],"R1_IMPLEMENTATION_EXECUTED")
    records += token_evidence(r1_units,[
        re.compile(r"(?i)\bR1_(?:PROTOTYPE|IMPLEMENTATION)_BENCHMARKED\s*=\s*YES\b"),
        re.compile(r"(?i)\bR1_(?:PROTOTYPE|IMPLEMENTATION)_BENCHMARK(?:_STATUS|_DECISION)?\s*=\s*PASS\b"),
        re.compile(r"(?i)\bR1_BENCHMARK_VALIDATION\s*=\s*PASS\b"),
    ],"R1_IMPLEMENTATION_BENCHMARKED")
    records += token_evidence(r1_units,[
        re.compile(r"(?i)\bR1_(?:PROTOTYPE|IMPLEMENTATION)_ACCEPTED\s*=\s*YES\b"),
        re.compile(r"(?i)\bR1_VALIDATION(?:_STATUS|_DECISION)?\s*=\s*PASS\b"),
        re.compile(r"(?i)\bREADY_FOR_FULL_NETWORK_RUN\s*=\s*YES\b"),
    ],"R1_ACCEPTANCE_SIGNAL")

    pd.DataFrame(records).to_csv(out/"D10A_V2_VALIDATION_EVIDENCE.csv",index=False)

    b1a=any_valid(records,"B1A_PREFLIGHT_PASS") or any_valid(records,"B1A1_ANALYSIS_PASS")
    b1b=any_valid(records,"B1B_MORE_DIAGNOSTIC_DATA_REQUIRED")
    b1c=any_valid(records,"B1C0_R1_DESIGN_PASS")
    r1design=b1c

    # --- collapse to a small, actual family set ---
    family_rows=[]
    sem_rows=[]
    family_sources={}
    for fam in KNOWN_FAMILY_ORDER:
        rows=invdf[invdf["implementation_family"].eq(fam)].to_dict("records")
        if not rows: continue
        family_sources[fam]=rows
        cands=candidate_entrypoints(rows)
        entry=cands[0][1] if cands else None
        sem=semantics(entry) if entry else None

        if fam=="ORIGINAL_PUBLISHED_ACLA":
            status="PUBLISHED_BASELINE"
        elif fam in {"V5"}:
            status="DIAGNOSTIC_ONLY"
        elif fam in {"V6"}:
            status="REJECTED"
        elif fam in {"V1","V2","V3","V4","EARLY_REFINED_ACLA"}:
            status="SUPERSEDED"
        elif fam=="B1":
            status="DIAGNOSTIC_ONLY"
        elif fam=="B1A":
            status="VALIDATED" if b1a else "UNKNOWN"
        elif fam=="B1B":
            status="DIAGNOSTIC_ONLY" if b1b else "UNKNOWN"
        elif fam=="B1C":
            status="PROSPECTIVE_DESIGN_ONLY" if b1c else "UNKNOWN"
        elif fam in {"R1_PROTOTYPE","R1_IMPLEMENTATION"}:
            status="IMPLEMENTED_UNVALIDATED"
        else:
            status="UNKNOWN"

        family_rows.append({
            "FAMILY_ID":fam,
            "ENTRYPOINT_CANDIDATES":"|".join(str(x[1]) for x in cands[:20]),
            "FAMILY_ENTRYPOINT":str(entry) if entry else "",
            "ENTRYPOINT_SHA256":sha256_file(entry) if entry else "",
            "CORE_SOURCE_FILES":"|".join(r["path"] for r in rows if r["is_code"]=="YES"),
            "DEPENDENCIES":"",
            "FIRST_TIMESTAMP":"",
            "LAST_TIMESTAMP":"",
            "SCIENTIFIC_STATUS":status,
            "STATUS_EVIDENCE_FILES":"|".join(sorted(set(
                r["source_path"] for r in records if r["family"]==fam
            ))),
            "ARTIFACT_COUNT":len(rows),
        })
        if sem:
            sem_rows.append({
                "FAMILY_ID":fam,"SCIENTIFIC_STATUS":status,"ENTRYPOINT":str(entry),
                "objective_function":sem["objective_function"],
                "initialization":sem["initialization"],
                "stopping_rule":sem["stopping_rule"],
                "randomness":sem["randomness"],
                "SIGNED_WEIGHT_POLICY":sem["signed_weight_policy"],
                "NEGATIVE_EDGES_PRESERVED":sem["negative_edges_preserved"],
                "regulatory_layer_handling":sem["regulatory_layer_handling"],
                "multilayer_handling":sem["multilayer_handling"],
                "input_schema":sem["input_schema"],
            })

    fdf=pd.DataFrame(family_rows)
    fdf.to_csv(out/"D10A_V2_IMPLEMENTATION_FAMILIES.csv",index=False)
    pd.DataFrame(sem_rows).to_csv(out/"D10A_V2_ALGORITHM_SEMANTIC_COMPARISON.csv",index=False)

    # --- R1 source existence independent of acceptance ---
    r1_source_rows=invdf[
        invdf["implementation_family"].isin(["R1_PROTOTYPE","R1_IMPLEMENTATION"])
        & invdf["is_code"].eq("YES")
    ].copy()
    # exclude validators/tests/reviews/benchmarks; runners/core count.
    if not r1_source_rows.empty:
        mask=~r1_source_rows["filename"].str.lower().str.contains(
            r"test_|validate|audit|review|benchmark|preflight",regex=True
        )
        r1_source_rows=r1_source_rows[mask]
    r1found=len(r1_source_rows)>0

    r1exec_signal=any_valid(records,"R1_IMPLEMENTATION_EXECUTED")
    r1bench_signal=any_valid(records,"R1_IMPLEMENTATION_BENCHMARKED")
    accept_signal=any_valid(records,"R1_ACCEPTANCE_SIGNAL")

    # hard lifecycle ordering: acceptance is impossible without execution + benchmark.
    r1exec = r1found and r1exec_signal
    r1bench = r1exec and r1bench_signal
    r1accept = r1bench and accept_signal
    invalid_accept_signal = accept_signal and not r1accept

    lifecycle=pd.DataFrame([
        {"gate":"R1_DESIGN_VALIDATED","value":"YES" if r1design else "NO"},
        {"gate":"R1_IMPLEMENTATION_FOUND","value":"YES" if r1found else "NO"},
        {"gate":"R1_IMPLEMENTATION_EXECUTED","value":"YES" if r1exec else "NO"},
        {"gate":"R1_IMPLEMENTATION_BENCHMARKED","value":"YES" if r1bench else "NO"},
        {"gate":"R1_IMPLEMENTATION_ACCEPTED","value":"YES" if r1accept else "NO"},
        {"gate":"ACCEPTANCE_SIGNAL_PRESENT_BUT_INVALID_WITHOUT_PRIOR_GATES","value":"YES" if invalid_accept_signal else "NO"},
    ])
    lifecycle.to_csv(out/"D10A_V2_R1_LIFECYCLE_GATE_AUDIT.csv",index=False)

    # timeline
    trows=[]
    for fam in KNOWN_FAMILY_ORDER:
        rr=fdf[fdf["FAMILY_ID"].eq(fam)]
        if rr.empty: continue
        r=rr.iloc[0]
        trows.append({
            "lineage_stage":fam,
            "scientific_status":r["SCIENTIFIC_STATUS"],
            "entrypoint":r["FAMILY_ENTRYPOINT"],
            "evidence":r["STATUS_EVIDENCE_FILES"],
        })
    pd.DataFrame(trows).to_csv(out/"D10A_V2_LINEAGE_TIMELINE.csv",index=False)

    # --- outcome ---
    authfound=False; ambiguous=False; authfam=""; authentry=None
    failure_stage=""; failure_reason=""; selection_basis=""
    if r1design:
        if not r1found:
            failure_stage="R1_IMPLEMENTATION_NOT_FOUND"
            failure_reason="Prospective R1 design evidence exists, but no executable R1 prototype/implementation source was found."
        elif not r1exec:
            failure_stage="R1_IMPLEMENTED_BUT_NOT_EXECUTED"
            failure_reason="Executable R1 source exists, but no authoritative decision/execution report demonstrates R1 implementation execution."
        elif not r1bench:
            failure_stage="R1_IMPLEMENTED_BUT_NOT_BENCHMARKED"
            failure_reason="R1 implementation execution is evidenced, but no authoritative benchmark validation PASS was found."
        elif not r1accept:
            failure_stage="R1_VALIDATION_NOT_ACCEPTED"
            failure_reason="R1 implementation was benchmarked, but no valid acceptance decision survived lifecycle ordering."
        else:
            # Accepted: resolve source family and uniqueness.
            possible=[]
            for fam in ["R1_IMPLEMENTATION","R1_PROTOTYPE"]:
                rr=fdf[fdf["FAMILY_ID"].eq(fam)]
                if rr.empty: continue
                ep=rr.iloc[0]["FAMILY_ENTRYPOINT"]
                if ep: possible.append((fam,Path(ep)))
            if len(possible)==1:
                authfam,authentry=possible[0]; authfound=True
                selection_basis="PROSPECTIVE_R1_DESIGN_IMPLEMENTED_EXECUTED_BENCHMARKED_ACCEPTED"
            elif len(possible)>1:
                # compare signed/input semantics fingerprint; if exact equivalent prefer implementation.
                fps={}
                for fam,p in possible:
                    s=semantics(p) or {}
                    fp=json.dumps({
                        k:s.get(k) for k in [
                            "input_schema","objective_function","initialization",
                            "stopping_rule","signed_weight_policy",
                            "regulatory_layer_handling","multilayer_handling"
                        ]
                    },sort_keys=True)
                    fps.setdefault(fp,[]).append((fam,p))
                if len(fps)==1:
                    chosen=next(iter(fps.values()))
                    authfam,authentry=next(
                        ((f,p) for f,p in chosen if f=="R1_IMPLEMENTATION"),
                        chosen[0]
                    )
                    authfound=True
                    selection_basis="EQUIVALENT_ACCEPTED_R1_SOURCES_PREFER_IMPLEMENTATION_LABEL"
                else:
                    ambiguous=True
                    failure_stage="MULTIPLE_INCOMPATIBLE_ACCEPTED_R1_IMPLEMENTATIONS"
                    failure_reason="More than one accepted R1 executable remains and static semantics differ."
            else:
                failure_stage="ACCEPTED_R1_WITHOUT_RESOLVABLE_ENTRYPOINT"
                failure_reason="Lifecycle evidence reached acceptance, but no executable R1 entrypoint could be resolved."
    else:
        failure_stage="R1_DESIGN_VALIDATION_NOT_ESTABLISHED"
        failure_reason="B1C-0 prospective R1 design PASS was not established from authoritative decision evidence."

    # compatibility only if authfound
    auth_sha=""; package_sha=""; required=[]; signed_policy=""
    d9_signed=d9_schema=d9_comp=d9_reg="NOT_TESTED"; signed_blocker="NO"
    auth_manifest=out/"D10A_V2_AUTHORITATIVE_ACLA_IMPLEMENTATION_MANIFEST.csv"
    if authfound:
        auth_sha=sha256_file(authentry)
        required=local_deps(authentry,roots["01_ACLA_CODE"])
        h=hashlib.sha256(); mrows=[]
        for p in required:
            try: rel=str(p.relative_to(roots["01_ACLA_CODE"])).replace("\\","/")
            except Exception: rel=p.name
            sh=sha256_file(p)
            h.update(rel.encode()); h.update(b"\0"); h.update(sh.encode()); h.update(b"\n")
            mrows.append({
                "role":"ENTRYPOINT" if p.resolve()==authentry.resolve() else "DEPENDENCY",
                "path":str(p),"relative_path":rel,"SHA256":sh,"size_bytes":p.stat().st_size
            })
        package_sha=h.hexdigest()
        pd.DataFrame(mrows).to_csv(auth_manifest,index=False)

        s=semantics(authentry) or {}
        signed_policy=s.get("signed_weight_policy","UNRESOLVED")
        if s.get("negative_edges_preserved","").startswith("YES"):
            d9_signed="YES"
        else:
            d9_signed="NO"; signed_blocker="YES"

        idir=d9/"D9_ACLA_INPUT"
        schema=s.get("input_schema","UNRESOLVED")
        if schema=="EDGE_LIST":
            d9_schema="YES" if (idir/"structural_edge_list.csv").is_file() else "NO"
        elif schema=="SPARSE_COO_OR_NPZ":
            d9_schema="YES" if (idir/"association_score_symmetric_coo.npz").is_file() else "NO"
        else:
            d9_schema="NO"
        d9_comp="YES"  # no network modification; exact runtime compatibility remains parameter-freeze concern.
        d9_reg="YES" if (
            s.get("regulatory_layer_handling")=="NO_NATIVE_REGULATORY_CHANNEL_DETECTED"
            or (idir/"regulatory_semantic_edge_list.csv").is_file()
        ) else "NO"
    elif auth_manifest.exists():
        auth_manifest.unlink()

    # parameter provenance: do not carry anything forward yet
    prows=[]
    for fam,entry in [
        (r["FAMILY_ID"],Path(r["FAMILY_ENTRYPOINT"]))
        for _,r in fdf.iterrows() if r["FAMILY_ENTRYPOINT"]
    ]:
        s=semantics(entry) or {}
        for name,val in s.get("constants",{}).items():
            if re.search(r"(?i)(seed|iter|alpha|beta|tol|patience|tau|delta|penalty|epsilon|threshold|run)",name):
                if fam in {"V5","V6","B1","B1A","B1B"}:
                    prov="DIAGNOSTIC_ONLY"
                elif fam in {"R1_PROTOTYPE","R1_IMPLEMENTATION"} and r1accept:
                    prov="PROSPECTIVELY_VALIDATED_R1"
                else:
                    prov="UNKNOWN"
                prows.append({
                    "FAMILY_ID":fam,"PARAMETER_NAME":name,"VALUE":val,
                    "PROVENANCE_CLASS":prov,
                    "CARRIED_FORWARD_TO_GSE243219":"NO",
                    "SOURCE_ENTRYPOINT":str(entry),
                })
    pd.DataFrame(prows).to_csv(out/"D10A_V2_PARAMETER_PROVENANCE_AUDIT.csv",index=False)

    status="PASS" if authfound else "FAIL_CLOSED"
    ready="YES" if authfound else "NO"

    # concise family status lists only from actual collapsed families
    def fams_with(stat):
        return "|".join(fdf.loc[fdf["SCIENTIFIC_STATUS"].eq(stat),"FAMILY_ID"].tolist())
    result={
        "D10A_V2_STATUS":status,
        "DISCOVERED_ACLA_FILES":len(inv),
        "IMPLEMENTATION_FAMILIES_IDENTIFIED":len(fdf),
        "PUBLISHED_BASELINE_FAMILY":fams_with("PUBLISHED_BASELINE"),
        "SUPERSEDED_FAMILIES":fams_with("SUPERSEDED"),
        "DIAGNOSTIC_ONLY_FAMILIES":fams_with("DIAGNOSTIC_ONLY"),
        "REJECTED_FAMILIES":fams_with("REJECTED"),
        "B1A_EVIDENCE_FOUND":"YES" if b1a else "NO",
        "B1B_EVIDENCE_FOUND":"YES" if b1b else "NO",
        "B1C0_R1_DESIGN_EVIDENCE_FOUND":"YES" if b1c else "NO",
        "R1_DESIGN_VALIDATED":"YES" if r1design else "NO",
        "R1_IMPLEMENTATION_FOUND":"YES" if r1found else "NO",
        "R1_IMPLEMENTATION_EXECUTED":"YES" if r1exec else "NO",
        "R1_IMPLEMENTATION_BENCHMARKED":"YES" if r1bench else "NO",
        "R1_IMPLEMENTATION_ACCEPTED":"YES" if r1accept else "NO",
        "ACCEPTANCE_SIGNAL_PRESENT_BUT_INVALID_WITHOUT_PRIOR_GATES":"YES" if invalid_accept_signal else "NO",
        "AUTHORITATIVE_ACLA_IMPLEMENTATION_FOUND":"YES" if authfound else "NO",
        "ACLA_IMPLEMENTATION_AMBIGUOUS":"YES" if ambiguous else "NO",
        "ACLA_AUTHORITATIVE_FAMILY":authfam,
        "ACLA_AUTHORITATIVE_ENTRYPOINT":str(authentry) if authfound else "",
        "ACLA_ENTRYPOINT_SHA256":auth_sha,
        "ACLA_IMPLEMENTATION_PACKAGE_SHA256":package_sha,
        "ACLA_REQUIRED_FILES":len(required),
        "AUTHORITATIVE_SELECTION_BASIS":selection_basis,
        "INPUT_NODES":EXPECTED_NODES,
        "INPUT_EDGES":EXPECTED_EDGES,
        "SIGNED_WEIGHTS_PRESENT":"YES",
        "INPUT_WEIGHT_MIN":wmin,
        "INPUT_WEIGHT_MAX":wmax,
        "AUTHORITATIVE_SIGNED_WEIGHT_POLICY":signed_policy,
        "D9_SIGNED_WEIGHT_COMPATIBLE":d9_signed,
        "D9_SCHEMA_COMPATIBLE":d9_schema,
        "D9_COMPONENT_STRUCTURE_COMPATIBLE":d9_comp,
        "D9_REGULATORY_CHANNEL_COMPATIBLE":d9_reg,
        "SIGNED_WEIGHT_COMPATIBILITY_BLOCKER":signed_blocker,
        "OLD_DATASET_DERIVED_PARAMETER_CARRIED_FORWARD":"NO",
        "NETWORK_CHANGED":"NO",
        "WEIGHT_TRANSFORMATION_APPLIED":"NO",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "GSE243219_ACLA_EXECUTED":"NO",
        "COMMUNITY_RESULTS_CREATED":"NO",
        "FAILURE_STAGE":failure_stage,
        "FAILURE_REASON":failure_reason,
        "READY_FOR_ACLA_PARAMETER_FREEZE":ready,
        "READY_FOR_ACLA_EXECUTION":"NO",
        "PRIOR_D10A_V2_RECERTIFIED":prior_v2_recertified,
        "STOP":"YES",
    }
    result_path.write_text(json.dumps(result,indent=2,sort_keys=True),encoding="utf-8")
    (out/"D10A_V2_ADJUDICATION_SPECIFICATION.txt").write_text(
        "MODE=CORRECTED_LINEAGE_ADJUDICATION\n"
        "FAMILY_ASSIGNMENT=PATH_FILENAME_FIRST_ONLY\n"
        "DECISION_EVIDENCE=REPORT_DECISION_STATUS_CLOSURE_EXECUTION_VALIDATION_ONLY\n"
        "ACCEPTANCE_REQUIRES_IMPLEMENTATION_FOUND_EXECUTED_BENCHMARKED_ACCEPTANCE_SIGNAL\n"
        "OLD_DATASET_DERIVED_PARAMETER_CARRIED_FORWARD=NO\n"
        "NETWORK_CHANGED=NO\n"
        "WEIGHT_TRANSFORMATION_APPLIED=NO\n"
        "PARAMETER_TUNING_EXECUTED=NO\n"
        "GSE243219_ACLA_EXECUTED=NO\n"
        "STOP=YES\n",
        encoding="utf-8"
    )
    return 0

if __name__=="__main__":
    raise SystemExit(main())
