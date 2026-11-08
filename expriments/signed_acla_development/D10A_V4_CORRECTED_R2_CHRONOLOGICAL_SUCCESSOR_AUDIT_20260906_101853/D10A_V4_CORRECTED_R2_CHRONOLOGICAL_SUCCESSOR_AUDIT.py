#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import re
import sys
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd

EXPECTED_NODES = 4508
EXPECTED_EDGES = 11531
EXPECTED_WEIGHT_MIN = -0.7753835531973502
EXPECTED_WEIGHT_MAX = 0.7428957195865319

TEXT_EXTS = {
    ".py",".ps1",".txt",".md",".csv",".json",".yaml",".yml",
    ".toml",".ini",".log",".xml",".r",".R",".jl",".m"
}

# Only B1C/R1 successor lineage.
SUCCESSOR_NAME_RE = re.compile(
    r"(?i)("
    r"B1C(?:[-_ ]?\d+)?|"
    r"R1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)|"
    r"RUN[_ -]?(?:ACLA[_ -]?)?R1|"
    r"ACLA[_ -]?R1|"
    r"FINAL[_ -]?(?:DECISION|STATUS)|"
    r"CLOSURE|ACCEPTANCE|READINESS|READY[_ -]?FOR"
    r")"
)
B1C_STAGE_RE = re.compile(r"(?i)\bB1C[-_ ]?(\d+)(?!\d)")

EXAMPLE_RE = re.compile(
    r"(?i)\b(expected|example|template|required|required output|"
    r"should report|pass criteria|possible valid evidence|if pass|"
    r"if accepted|look for|report:|return:)\b"
)

EXEC_POS = [
    ("R1_EXECUTED_YES", re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?EXECUTED\s*=\s*YES\b")),
    ("EXECUTION_STATUS_PASS", re.compile(r"(?i)\b(?:R1[_ -]?)?(?:PROTOTYPE[_ -]?)?EXECUTION[_ -]?(?:STATUS|DECISION)\s*=\s*(?:PASS|SUCCESS|COMPLETED)\b")),
    ("RUN_STATUS_PASS", re.compile(r"(?i)\bRUN[_ -]?STATUS\s*=\s*(?:PASS|SUCCESS|COMPLETED)\b")),
    ("EXIT_CODE_ZERO", re.compile(r"(?i)\bEXIT[_ -]?CODE\s*=\s*0\b")),
    ("EXECUTION_COMPLETED", re.compile(r"(?i)\b(?:R1|prototype|runner)[^\n]{0,100}\b(?:completed successfully|execution completed|run completed)\b")),
]
EXEC_NEG = [
    ("R1_EXECUTED_NO", re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?EXECUTED\s*=\s*NO\b")),
    ("READY_FOR_EXECUTION_NO", re.compile(r"(?i)\bREADY[_ -]?FOR[_ -]?R1[_ -]?(?:PROTOTYPE[_ -]?)?EXECUTION\s*=\s*NO\b")),
    ("NO_EXECUTION", re.compile(r"(?i)\b(?:not executed|never executed|execution did not occur|blocked before execution)\b")),
]
BENCH_POS = [
    ("BENCHMARK_PASS", re.compile(r"(?i)\bR1[^\n]{0,80}\bBENCHMARK(?:[_ -]?(?:STATUS|DECISION|VALIDATION))?\s*=\s*PASS\b")),
    ("BENCHMARKED_YES", re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?BENCHMARKED\s*=\s*YES\b")),
    ("BENCHMARK_RESULT_PASS", re.compile(r"(?i)\b(?:benchmark|fixture|reproducibility|deterministic|scalability)[^\n]{0,120}\b(?:PASS|PASSED|SUCCESS)\b")),
]
BENCH_NEG = [
    ("BENCHMARKED_NO", re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?BENCHMARKED\s*=\s*NO\b")),
    ("NO_BENCHMARK", re.compile(r"(?i)\b(?:not benchmarked|benchmark not performed|benchmarking did not occur)\b")),
]
ACCEPT_POS = [
    ("R1_ACCEPTED_YES", re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?(?:ACCEPTED|VALIDATED|APPROVED)\s*=\s*YES\b")),
    ("R1_VALIDATION_PASS", re.compile(r"(?i)\bR1[_ -]?(?:VALIDATION|FINAL_DECISION|FINAL_STATUS)(?:[_ -]?(?:STATUS|DECISION))?\s*=\s*PASS\b")),
    ("READY_FOR_FULL_RUN_YES", re.compile(r"(?i)\bREADY[_ -]?FOR[_ -]?(?:BIOLOGICAL[_ -]?EXECUTION|PRODUCTION|FULL[_ -]?NETWORK[_ -]?RUN)\s*=\s*YES\b")),
    ("FINAL_ACCEPTANCE", re.compile(r"(?i)\bFINAL[_ -]?ACCEPTANCE\s*=\s*(?:YES|PASS|ACCEPTED)\b")),
]
ACCEPT_NEG = [
    ("R1_REJECTED", re.compile(r"(?i)\bR1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)[_ -]?REJECTED\s*=\s*YES\b")),
    ("READY_FOR_FULL_RUN_NO", re.compile(r"(?i)\bREADY[_ -]?FOR[_ -]?(?:BIOLOGICAL[_ -]?EXECUTION|PRODUCTION|FULL[_ -]?NETWORK[_ -]?RUN)\s*=\s*NO\b")),
    ("R1_FAIL_CLOSED", re.compile(r"(?i)\bR1[^\n]{0,100}\bFAIL[_ -]?CLOSED\b")),
    ("R1_REANALYSIS_REQUIRED", re.compile(r"(?i)\bR1[^\n]{0,100}\bREANALYSIS[_ -]?REQUIRED\b")),
]

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        while True:
            b=f.read(chunk)
            if not b: break
            h.update(b)
    return h.hexdigest()

def recertify_manifest(path: Path, label: str):
    if not path.is_file():
        raise RuntimeError(f"{label}_MANIFEST_MISSING={path}")
    df=pd.read_csv(path,dtype=str,keep_default_na=False)
    required={"full_path","size_bytes","SHA256"}
    missing=required-set(df.columns)
    if missing:
        raise RuntimeError(f"{label}_MANIFEST_COLUMNS_MISSING={sorted(missing)}")
    bad=[]
    for _,r in df.iterrows():
        p=Path(r["full_path"])
        if not p.is_file():
            bad.append(f"MISSING:{p}"); continue
        if p.stat().st_size!=int(r["size_bytes"]):
            bad.append(f"SIZE:{p}"); continue
        if sha256_file(p)!=r["SHA256"].lower():
            bad.append(f"SHA256:{p}")
    if bad:
        raise RuntimeError(f"{label}_HASH_MISMATCHES={len(bad)}|"+"||".join(bad[:20]))

def safe_text(path: Path, max_bytes=25_000_000):
    try:
        if path.stat().st_size>max_bytes: return ""
        if path.suffix.lower() in TEXT_EXTS:
            return path.read_text(encoding="utf-8",errors="replace")
    except Exception:
        return ""
    return ""

def zip_members(path: Path, max_members=10000, max_text_bytes=4_000_000):
    out=[]
    if path.suffix.lower()!=".zip": return out
    try:
        with zipfile.ZipFile(path) as z:
            for info in z.infolist()[:max_members]:
                if not SUCCESSOR_NAME_RE.search(info.filename): continue
                text=""
                if info.file_size<=max_text_bytes and Path(info.filename).suffix in TEXT_EXTS:
                    try: text=z.read(info).decode("utf-8",errors="replace")
                    except Exception: pass
                out.append((info.filename,text))
    except Exception:
        pass
    return out

def stage_number(name: str):
    nums=[int(x) for x in B1C_STAGE_RE.findall(name)]
    return max(nums) if nums else None

def classify_artifact(name: str, text: str):
    low=name.lower()
    roles=[]
    if any(k in low for k in ["design","contract","specification"]): roles.append("DESIGN")
    if any(k in low for k in ["preflight","static_validation","code_validation","syntax"]): roles.append("PREFLIGHT")
    if any(k in low for k in ["prototype","implementation"]) and Path(name).suffix.lower() in {".py",".ps1"}:
        roles.append("IMPLEMENTATION")
    if any(k in low for k in ["execution","run_","runner","result","output","log"]): roles.append("EXECUTION")
    if any(k in low for k in ["benchmark","fixture","concordance","scalability"]): roles.append("BENCHMARK")
    if any(k in low for k in ["validation","validate","audit"]): roles.append("VALIDATION")
    if any(k in low for k in ["final_decision","final_status","closure","acceptance","readiness","ready_for"]): roles.append("ACCEPTANCE")
    if not roles: roles=["SUPPORTING"]
    authoritative=(
        "YES" if any(r in roles for r in ["EXECUTION","BENCHMARK","VALIDATION","ACCEPTANCE"])
        and any(k in low for k in ["report","summary","status","decision","closure","result","log","evidence","output"])
        else "NO"
    )
    return "|".join(dict.fromkeys(roles)), authoritative

def scan(roots):
    rows=[]; units=[]
    for root_name,root in roots.items():
        if not root.exists():
            raise RuntimeError(f"ROOT_MISSING={root}")
        for p in root.rglob("*"):
            if not p.is_file(): continue
            rel=str(p.relative_to(root)).replace("\\","/")
            logical=f"{root_name}/{rel}"
            top=bool(SUCCESSOR_NAME_RE.search(logical))
            members=zip_members(p) if p.suffix.lower()==".zip" else []
            if not top and not members: continue

            if top:
                text=safe_text(p)
                st=stage_number(logical)
                roles,auth=classify_artifact(logical,text)
                rows.append({
                    "source_path":str(p),"logical_path":logical,"archive_member":"",
                    "stage_number":st if st is not None else "",
                    "artifact_class":roles,"authoritative_candidate":auth,
                    "file_sha256":sha256_file(p),"size_bytes":p.stat().st_size,
                })
                units.append({
                    "source_path":str(p),"logical_path":logical,"stage_number":st,
                    "roles":roles,"authoritative":auth,"sha256":sha256_file(p),"text":text
                })
            for member,mtext in members:
                mlogical=f"{logical}::{member}"
                st=stage_number(mlogical)
                roles,auth=classify_artifact(mlogical,mtext)
                rows.append({
                    "source_path":str(p),"logical_path":logical,"archive_member":member,
                    "stage_number":st if st is not None else "",
                    "artifact_class":roles,"authoritative_candidate":auth,
                    "file_sha256":sha256_file(p),"size_bytes":"",
                })
                units.append({
                    "source_path":f"{p}::{member}","logical_path":mlogical,"stage_number":st,
                    "roles":roles,"authoritative":auth,"sha256":sha256_file(p),"text":mtext
                })
    return rows,units

def context(text,start,window=2):
    lines=text.splitlines()
    ln=text.count("\n",0,start)+1
    a=max(0,ln-1-window);b=min(len(lines),ln+window)
    return ln," | ".join(lines[a:b])[:3500]

def signals(units, stage_name, pos_patterns, neg_patterns):
    out=[]
    for u in units:
        text=u["text"]
        if not text: continue
        # Ignore unrelated R1 references in broad docs by requiring either stage>=1
        # or explicit R1 naming in path.
        if u["stage_number"] is None and not re.search(r"(?i)R1[_ -]?(?:PROTOTYPE|IMPLEMENTATION)|RUN[_ -]?(?:ACLA[_ -]?)?R1",u["logical_path"]):
            continue
        for polarity,patterns in [("POSITIVE",pos_patterns),("NEGATIVE",neg_patterns)]:
            for label,rgx in patterns:
                for m in rgx.finditer(text):
                    ln,ctx=context(text,m.start())
                    if EXAMPLE_RE.search(ctx): continue
                    out.append({
                        "lifecycle_stage":stage_name,
                        "polarity":polarity,
                        "signal_label":label,
                        "b1c_stage_number":u["stage_number"] if u["stage_number"] is not None else "",
                        "source_path":u["source_path"],
                        "file_sha256":u["sha256"],
                        "artifact_class":u["roles"],
                        "authoritative_candidate":u["authoritative"],
                        "line_number":ln,
                        "matched_text":m.group(0)[:1200],
                        "context":ctx,
                    })
    return out

def choose_latest_authoritative(sigrows, lifecycle_stage):
    rows=[r for r in sigrows if r["lifecycle_stage"]==lifecycle_stage and r["authoritative_candidate"]=="YES"]
    if not rows:
        return "UNRESOLVED",None,"NO_AUTHORITATIVE_SUCCESSOR_EVIDENCE"
    def key(r):
        st=r["b1c_stage_number"]
        st=int(st) if str(st).isdigit() else -1
        # Later B1C stage wins; within stage, negative/positive conflict remains unresolved.
        return st
    maxstage=max(key(r) for r in rows)
    latest=[r for r in rows if key(r)==maxstage]
    pol=set(r["polarity"] for r in latest)
    if len(pol)>1:
        return "UNRESOLVED",latest[0],f"CONFLICTING_AUTHORITATIVE_EVIDENCE_AT_B1C_STAGE_{maxstage}"
    state="YES" if next(iter(pol))=="POSITIVE" else "NO"
    return state,latest[0],""

def self_test():
    # Exact filename patterns seen in the preserved assets.
    assert stage_number("4c2b3ce45a8e__ACLA_B1C1_code_validation_report.txt") == 1
    assert stage_number("RUN_ACLA_B1C12_EXACT_EXECUTION_LOCKED.ps1") == 12
    assert stage_number("ACLA_B1C41_final_evidence_and_close_chapter.txt") == 41

    fake=[
        {"lifecycle_stage":"EXECUTION","polarity":"NEGATIVE","signal_label":"NO","b1c_stage_number":1,
         "source_path":"B1C1.txt","file_sha256":"0"*64,"artifact_class":"VALIDATION","authoritative_candidate":"YES",
         "line_number":1,"matched_text":"NO","context":"NO"},
        {"lifecycle_stage":"EXECUTION","polarity":"POSITIVE","signal_label":"YES","b1c_stage_number":12,
         "source_path":"B1C12.txt","file_sha256":"1"*64,"artifact_class":"EXECUTION","authoritative_candidate":"YES",
         "line_number":1,"matched_text":"YES","context":"YES"},
    ]
    s,ev,_=choose_latest_authoritative(fake,"EXECUTION")
    assert s=="YES" and ev["b1c_stage_number"]==12
    s,ev,_=choose_latest_authoritative([],"EXECUTION")
    assert s=="UNRESOLVED"
    print("D10A_V4_INTERNAL_SELFTEST=PASS")
    print("B1C_STAGE_FILENAME_PARSER=PASS")
    print("LATER_STAGE_SUPERSEDES_EARLIER_STAGE=PASS")
    print("ABSENCE_DOES_NOT_EQUAL_NO=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test":
        return self_test()
    if len(sys.argv)!=5:
        raise SystemExit("usage: script <reusable_root> <d9_run> <outdir> <result_json>")
    reusable=Path(sys.argv[1]);d9=Path(sys.argv[2]);out=Path(sys.argv[3]);result_path=Path(sys.argv[4])
    out.mkdir(parents=True,exist_ok=True)

    # D9 integrity only; no mutation.
    recertify_manifest(d9/"D9_SHA256_MANIFEST.csv","D9")
    stat=(d9/"D9_FINAL_STATUS.txt").read_text(encoding="utf-8-sig",errors="replace")
    for tok in ["D9_STATUS=PASS","TOTAL_NODES=4508","TOTAL_STRUCTURAL_EDGES=11531","ACLA_EXECUTED=NO","D9_HASH_MISMATCHES=0"]:
        if tok not in stat: raise RuntimeError(f"D9_STATUS_TOKEN_MISSING={tok}")
    nodes=pd.read_csv(d9/"D9_MASTER_NODES.csv",dtype={"node_id":str})
    edges=pd.read_csv(d9/"D9_MASTER_EDGES.csv",dtype={"source":str,"target":str},float_precision="round_trip")
    if len(nodes)!=EXPECTED_NODES or len(edges)!=EXPECTED_EDGES: raise RuntimeError("D9_SIZE_GATE_FAILED")
    w=pd.to_numeric(edges["association_score"],errors="coerce").to_numpy(float)
    if (~np.isfinite(w)).sum(): raise RuntimeError("D9_INVALID_WEIGHTS")
    if not math.isclose(float(w.min()),EXPECTED_WEIGHT_MIN,rel_tol=0,abs_tol=1e-15): raise RuntimeError("D9_WEIGHT_MIN_CHANGED")
    if not math.isclose(float(w.max()),EXPECTED_WEIGHT_MAX,rel_tol=0,abs_tol=1e-15): raise RuntimeError("D9_WEIGHT_MAX_CHANGED")

    roots={
        "01_ACLA_CODE":reusable/"01_ACLA_CODE",
        "07_METHODS_AND_DOCUMENTATION":reusable/"07_METHODS_AND_DOCUMENTATION",
        "09_OLD_METHOD_HISTORY":reusable/"09_OLD_METHOD_HISTORY",
    }
    inv,units=scan(roots)
    if not inv: raise RuntimeError("SUCCESSOR_ARTIFACTS_REVIEWED=0")
    pd.DataFrame(inv).to_csv(out/"D10A_V4_SUCCESSOR_ARTIFACT_INVENTORY.csv",index=False)

    execs=signals(units,"EXECUTION",EXEC_POS,EXEC_NEG)
    bench=signals(units,"BENCHMARK",BENCH_POS,BENCH_NEG)
    accept=signals(units,"ACCEPTANCE",ACCEPT_POS,ACCEPT_NEG)
    allsig=execs+bench+accept
    pd.DataFrame(allsig).to_csv(out/"D10A_V4_CHRONOLOGICAL_EVIDENCE.csv",index=False)

    exec_state,exec_ev,exec_reason=choose_latest_authoritative(allsig,"EXECUTION")
    bench_state,bench_ev,bench_reason=choose_latest_authoritative(allsig,"BENCHMARK")
    accept_state,accept_ev,accept_reason=choose_latest_authoritative(allsig,"ACCEPTANCE")

    # Lifecycle ordering. A later benchmark cannot be certified if execution is not YES.
    if exec_state!="YES" and bench_state=="YES":
        bench_state="UNRESOLVED";bench_reason="BENCHMARK_SIGNAL_EXISTS_BUT_EXECUTION_NOT_CERTIFIED"
    if bench_state!="YES" and accept_state=="YES":
        accept_state="UNRESOLVED";accept_reason="ACCEPTANCE_SIGNAL_EXISTS_BUT_BENCHMARK_NOT_CERTIFIED"

    # B1C1 anchor evidence for explicit comparison.
    b1c1_neg=[r for r in execs if r["b1c_stage_number"]==1 and r["polarity"]=="NEGATIVE"]
    anchor=b1c1_neg[0] if b1c1_neg else None
    later_exec=[r for r in execs if str(r["b1c_stage_number"]).isdigit() and int(r["b1c_stage_number"])>1 and r["authoritative_candidate"]=="YES"]
    later_exec_pos=[r for r in later_exec if r["polarity"]=="POSITIVE"]
    later_exec_neg=[r for r in later_exec if r["polarity"]=="NEGATIVE"]

    chronology_rows=[]
    for r in sorted(
        [x for x in allsig if str(x["b1c_stage_number"]).isdigit()],
        key=lambda x:(int(x["b1c_stage_number"]),x["lifecycle_stage"],x["source_path"])
    ):
        chronology_rows.append(r)
    pd.DataFrame(chronology_rows).to_csv(out/"D10A_V4_B1C_STAGE_CHRONOLOGY.csv",index=False)

    if exec_state=="YES" and bench_state=="YES" and accept_state=="YES":
        status="PASS";failure_stage="";failure_reason=""
    elif exec_state=="NO":
        # Only decisive if the latest authoritative execution evidence is negative.
        status="FAIL_CLOSED";failure_stage="R1_IMPLEMENTED_BUT_NOT_EXECUTED"
        failure_reason=exec_ev["context"] if exec_ev else exec_reason
    elif exec_state=="YES" and bench_state=="NO":
        status="FAIL_CLOSED";failure_stage="R1_EXECUTED_BUT_NOT_BENCHMARKED"
        failure_reason=bench_ev["context"] if bench_ev else bench_reason
    elif exec_state=="YES" and bench_state=="YES" and accept_state=="NO":
        status="FAIL_CLOSED";failure_stage="R1_BENCHMARKED_BUT_NOT_ACCEPTED"
        failure_reason=accept_ev["context"] if accept_ev else accept_reason
    else:
        status="REVIEW_REQUIRED"
        if exec_state=="UNRESOLVED":
            failure_stage="R1_EXECUTION_UNRESOLVED_AFTER_SUCCESSOR_AUDIT";failure_reason=exec_reason
        elif bench_state=="UNRESOLVED":
            failure_stage="R1_BENCHMARK_UNRESOLVED_AFTER_SUCCESSOR_AUDIT";failure_reason=bench_reason
        else:
            failure_stage="R1_ACCEPTANCE_UNRESOLVED_AFTER_SUCCESSOR_AUDIT";failure_reason=accept_reason

    result={
        "D10A_V4_STATUS":status,
        "SUCCESSOR_ARTIFACTS_REVIEWED":len(inv),
        "B1C1_NEGATIVE_EXECUTION_ANCHOR_FOUND":"YES" if anchor else "NO",
        "B1C1_NEGATIVE_EXECUTION_ANCHOR_FILE":anchor["source_path"] if anchor else "",
        "LATER_B1C_EXECUTION_EVIDENCE_FOUND":"YES" if later_exec else "NO",
        "LATER_B1C_POSITIVE_EXECUTION_EVIDENCE_FOUND":"YES" if later_exec_pos else "NO",
        "LATER_B1C_NEGATIVE_EXECUTION_EVIDENCE_FOUND":"YES" if later_exec_neg else "NO",
        "R1_IMPLEMENTATION_EXECUTED":exec_state,
        "R1_EXECUTION_LATEST_EVIDENCE_STAGE":exec_ev["b1c_stage_number"] if exec_ev else "",
        "R1_EXECUTION_LATEST_EVIDENCE_FILE":exec_ev["source_path"] if exec_ev else "",
        "R1_EXECUTION_LATEST_DECISION":exec_ev["matched_text"] if exec_ev else "",
        "R1_IMPLEMENTATION_BENCHMARKED":bench_state,
        "R1_BENCHMARK_LATEST_EVIDENCE_STAGE":bench_ev["b1c_stage_number"] if bench_ev else "",
        "R1_BENCHMARK_LATEST_EVIDENCE_FILE":bench_ev["source_path"] if bench_ev else "",
        "R1_BENCHMARK_LATEST_DECISION":bench_ev["matched_text"] if bench_ev else "",
        "R1_IMPLEMENTATION_ACCEPTED":accept_state,
        "R1_ACCEPTANCE_LATEST_EVIDENCE_STAGE":accept_ev["b1c_stage_number"] if accept_ev else "",
        "R1_ACCEPTANCE_LATEST_EVIDENCE_FILE":accept_ev["source_path"] if accept_ev else "",
        "R1_ACCEPTANCE_LATEST_DECISION":accept_ev["matched_text"] if accept_ev else "",
        "FAILURE_STAGE":failure_stage,
        "FAILURE_REASON":failure_reason,
        "SIGNED_WEIGHTS_PRESENT":"YES",
        "D9_SIGNED_WEIGHT_COMPATIBLE":"NOT_TESTED",
        "SIGNED_WEIGHT_COMPATIBILITY_BLOCKER":"NOT_TESTED",
        "GSE243219_ACLA_EXECUTED":"NO",
        "NETWORK_CHANGED":"NO",
        "WEIGHT_TRANSFORMATION_APPLIED":"NO",
        "PARAMETER_TUNING_EXECUTED":"NO",
        "READY_FOR_ACLA_PARAMETER_FREEZE":"NO",
        "READY_FOR_ACLA_EXECUTION":"NO",
        "STOP":"YES",
    }
    result_path.write_text(json.dumps(result,indent=2,sort_keys=True),encoding="utf-8")

    # Human-readable targeted evidence.
    def write_ev(path,title,state,ev,reason):
        lines=[title,f"STATE={state}",f"REASON={reason}"]
        if ev:
            lines += [
                f"B1C_STAGE={ev['b1c_stage_number']}",
                f"EVIDENCE_FILE={ev['source_path']}",
                f"EVIDENCE_SHA256={ev['file_sha256']}",
                f"EVIDENCE_SIGNAL={ev['matched_text']}",
                f"EVIDENCE_CONTEXT={ev['context']}",
            ]
        path.write_text("\n".join(lines)+"\n",encoding="utf-8")
    write_ev(out/"D10A_V4_EXECUTION_SUCCESSOR_DECISION.txt","R1 EXECUTION SUCCESSOR DECISION",exec_state,exec_ev,exec_reason)
    write_ev(out/"D10A_V4_BENCHMARK_SUCCESSOR_DECISION.txt","R1 BENCHMARK SUCCESSOR DECISION",bench_state,bench_ev,bench_reason)
    write_ev(out/"D10A_V4_ACCEPTANCE_SUCCESSOR_DECISION.txt","R1 ACCEPTANCE SUCCESSOR DECISION",accept_state,accept_ev,accept_reason)
    return 0

if __name__=="__main__":
    raise SystemExit(main())
