#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, re, sys, zipfile
from collections import defaultdict
from pathlib import Path
import pandas as pd

TITLE = "A-CLA: A Novel Adaptive Cellular Learning Automata Approach for Uncovering Communities in Complex Networks"
DOI = "10.1016/j.comnet.2026.112103"
TEXT_EXTS={".py",".ps1",".txt",".md",".csv",".json",".yaml",".yml",".toml",".ini",".log",".xml"}
EXCLUDE=[
 re.compile(r"(?i)(?:^|[^a-z0-9])candidate[_ -]?v[1-6](?:[^a-z0-9]|$)"),
 re.compile(r"(?i)(?:^|[^a-z0-9])b1(?:a|b|c)?(?:\d+)?(?:[^a-z0-9]|$)"),
 re.compile(r"(?i)r1[_ -]?(?:prototype|implementation|benchmark|diagnostic|redesign)"),
 re.compile(r"(?i)(?:refined|probability[_ -]?guided|action[_ -]?remap|hard[_ -]?action)")
]
ANCHOR_RE=re.compile(r"(?i)(A-CLA:\s*A Novel Adaptive Cellular Learning Automata Approach|10\.1016/j\.comnet\.2026\.112103|Computer Networks.{0,100}112103)")
BASE_NAME_RE=re.compile(r"(?i)^(?:a-cla|a_cla|acla)(?:[_ -]?(?:main|original|published|baseline|final))?\.py$")
RUNNER_RE=re.compile(r"(?i)^(?:run_)?(?:a-cla|a_cla|acla).*(?:\.py|\.ps1)$")

def sha_file(p,chunk=8*1024*1024):
    h=hashlib.sha256()
    with p.open("rb") as f:
        for b in iter(lambda:f.read(chunk),b""): h.update(b)
    return h.hexdigest()

def sha_bytes(b): return hashlib.sha256(b).hexdigest()

def excluded(s): return any(r.search(s.replace("\\","/")) for r in EXCLUDE)

def read_text(p,max_bytes=20_000_000):
    try:
        if p.stat().st_size>max_bytes:return ""
        if p.suffix.lower() in TEXT_EXTS:
            return p.read_text(encoding="utf-8",errors="replace")
    except Exception: pass
    return ""

def scan_zip(p,root_name,root):
    anchors=[];codes=[];manifests=[]
    rel=f"{root_name}/{str(p.relative_to(root)).replace(chr(92),'/')}"
    if excluded(rel): return anchors,codes,manifests
    try:
        with zipfile.ZipFile(p) as z:
            for info in z.infolist():
                name=info.filename
                logical=rel+"::"+name
                if excluded(logical): continue
                ext=Path(name).suffix.lower()
                data=None;text=""
                if info.file_size<=5_000_000 and ext in TEXT_EXTS:
                    try:
                        data=z.read(info); text=data.decode("utf-8",errors="replace")
                    except Exception: pass
                if text and ANCHOR_RE.search(text):
                    anchors.append({"source":str(p)+"::"+name,"logical":logical,"sha256":sha_file(p),"container":str(p),"member":name})
                if ext==".py" and (BASE_NAME_RE.match(Path(name).name) or RUNNER_RE.match(Path(name).name)):
                    if data is None:
                        try:data=z.read(info);text=data.decode("utf-8",errors="replace")
                        except Exception:continue
                    codes.append({"kind":"ZIP_MEMBER","source":str(p)+"::"+name,"logical":logical,"name":Path(name).name,"sha256":sha_bytes(data),"size":len(data),"archive":str(p),"member":name,"text":text})
                if text and any(k in Path(name).name.lower() for k in ["manifest","sha","hash","readme","provenance","source","publication","article"]):
                    manifests.append({"source":str(p)+"::"+name,"logical":logical,"text":text,"sha256":sha_file(p)})
    except Exception: pass
    return anchors,codes,manifests

def selftest():
    assert excluded("B1C41/RUN_ACLA_R1_PROTOTYPE_LOCKED.py")
    assert excluded("Candidate_V6/A-CLA.py")
    assert not excluded("PUBLISHED/A-CLA.py")
    assert BASE_NAME_RE.match("A-CLA.py")
    assert ANCHOR_RE.search("DOI: 10.1016/j.comnet.2026.112103")
    print("D10B_V2_INTERNAL_SELFTEST=PASS")
    print("PUBLICATION_ANCHOR_SELFTEST=PASS")
    print("LINEAGE_EXCLUSION_SELFTEST=PASS")
    return 0

def main():
    if len(sys.argv)==2 and sys.argv[1]=="--self-test": return selftest()
    if len(sys.argv)!=5: raise SystemExit("usage: script <reusable> <outdir> <result_json> <project>")
    reusable=Path(sys.argv[1]);out=Path(sys.argv[2]);result_path=Path(sys.argv[3]);project=Path(sys.argv[4])
    out.mkdir(parents=True,exist_ok=True)
    roots={
      "01_ACLA_CODE":reusable/"01_ACLA_CODE",
      "07_METHODS_AND_DOCUMENTATION":reusable/"07_METHODS_AND_DOCUMENTATION",
      "09_OLD_METHOD_HISTORY":reusable/"09_OLD_METHOD_HISTORY",
    }
    for r in roots.values():
        if not r.is_dir(): raise RuntimeError(f"SEARCH_ROOT_MISSING={r}")

    anchors=[];codes=[];prov=[]
    for rn,root in roots.items():
        for p in root.rglob("*"):
            if not p.is_file():continue
            rel=f"{rn}/{str(p.relative_to(root)).replace(chr(92),'/')}"
            if excluded(rel):continue
            if p.suffix.lower()==".zip":
                a,c,m=scan_zip(p,rn,root);anchors+=a;codes+=c;prov+=m
                continue
            txt=""
            if p.suffix.lower() in TEXT_EXTS:
                txt=read_text(p)
            if txt and ANCHOR_RE.search(txt):
                anchors.append({"source":str(p),"logical":rel,"sha256":sha_file(p),"container":str(p),"member":""})
            if p.suffix.lower()==".py" and (BASE_NAME_RE.match(p.name) or RUNNER_RE.match(p.name)):
                codes.append({"kind":"FILE","source":str(p),"logical":rel,"name":p.name,"sha256":sha_file(p),"size":p.stat().st_size,"archive":"","member":"","text":txt})
            if txt and any(k in p.name.lower() for k in ["manifest","sha","hash","readme","provenance","source","publication","article"]):
                prov.append({"source":str(p),"logical":rel,"text":txt,"sha256":sha_file(p)})

    # For every code candidate, collect exact publication/provenance associations.
    rows=[]
    for c in codes:
        rel=c["logical"].replace("\\","/")
        parent="/".join(rel.split("/")[:-1])
        evid=[]
        score=0
        # Exact anchor in source.
        if ANCHOR_RE.search(c["text"]):
            evid.append("ARTICLE_ANCHOR_IN_SOURCE");score+=100
        # Anchor in same directory or ancestor bundle.
        for a in anchors:
            al=a["logical"].replace("\\","/")
            aparent="/".join(al.split("/")[:-1])
            if parent==aparent or parent.startswith(aparent+"/") or aparent.startswith(parent+"/"):
                evid.append("ARTICLE_ANCHOR_NEARBY:"+a["source"]);score+=30
        # Manifest/readme association: filename and, preferably, hash.
        for p in prov:
            t=p["text"].lower()
            if c["name"].lower() in t:
                if c["sha256"].lower() in t:
                    evid.append("MANIFEST_FILENAME_AND_SHA:"+p["source"]);score+=200
                elif ANCHOR_RE.search(p["text"]):
                    evid.append("PUBLICATION_README_FILENAME:"+p["source"]);score+=80
        if BASE_NAME_RE.match(c["name"]): score+=20;evid.append("BASELINE_FILENAME")
        rows.append({
          "source":c["source"],"kind":c["kind"],"logical_path":c["logical"],"filename":c["name"],
          "SHA256":c["sha256"],"size_bytes":c["size"],"provenance_score":score,
          "provenance_evidence":"|".join(dict.fromkeys(evid))
        })

    rdf=pd.DataFrame(rows,columns=["source","kind","logical_path","filename","SHA256","size_bytes","provenance_score","provenance_evidence"])
    rdf.to_csv(out/"D10B_V2_BASELINE_CANDIDATES.csv",index=False)
    pd.DataFrame([{k:v for k,v in a.items() if k not in {"container","member"}} for a in anchors],
                 columns=["source","logical","sha256"]).to_csv(out/"D10B_V2_PUBLICATION_ANCHORS.csv",index=False)

    if rdf.empty:
        distinct=0; selected=None; reason="NO_BASELINE_CODE_CANDIDATES_FOUND"
    else:
        distinct=rdf["SHA256"].nunique()
        # Unique exact-hash provenance dominates.
        exact=rdf[rdf["provenance_evidence"].str.contains("MANIFEST_FILENAME_AND_SHA",na=False)]
        if exact["SHA256"].nunique()==1 and len(exact)>0:
            sh=exact.iloc[0]["SHA256"]; subset=rdf[rdf["SHA256"].eq(sh)].sort_values(["provenance_score","source"],ascending=[False,True])
            selected=subset.iloc[0];reason=""
        else:
            # Otherwise require one unique hash among candidates with publication association.
            assoc=rdf[rdf["provenance_score"]>=50]
            if len(assoc)>0 and assoc["SHA256"].nunique()==1:
                sh=assoc.iloc[0]["SHA256"];subset=rdf[rdf["SHA256"].eq(sh)].sort_values(["provenance_score","source"],ascending=[False,True])
                selected=subset.iloc[0];reason=""
            else:
                selected=None
                reason="MULTIPLE_DISTINCT_BASELINE_HASHES" if distinct>1 else "PUBLICATION_PROVENANCE_INSUFFICIENT"

    # Hash summary.
    hs=[]
    if not rdf.empty:
        for sh,g in rdf.groupby("SHA256"):
            hs.append({
              "SHA256":sh,"copy_count":len(g),"max_provenance_score":int(g["provenance_score"].max()),
              "example_path":g.sort_values("provenance_score",ascending=False).iloc[0]["source"],
              "publication_associated":"YES" if (g["provenance_score"]>=50).any() else "NO",
              "exact_manifest_hash_association":"YES" if g["provenance_evidence"].str.contains("MANIFEST_FILENAME_AND_SHA",na=False).any() else "NO"
            })
    pd.DataFrame(hs,columns=["SHA256","copy_count","max_provenance_score","example_path","publication_associated","exact_manifest_hash_association"]).to_csv(
        out/"D10B_V2_DISTINCT_BASELINE_HASHES.csv",index=False)

    found=selected is not None
    sel_path=str(selected["source"]) if found else ""
    sel_sha=str(selected["SHA256"]) if found else ""
    sel_basis=str(selected["provenance_evidence"]) if found else ""

    # If selected ZIP member, snapshot bytes for next static compatibility phase.
    snapshot=""
    if found and str(selected["kind"])=="ZIP_MEMBER":
        source=str(selected["source"]);archive,member=source.split("::",1)
        snapdir=out/"D10B_V2_SELECTED_PUBLISHED_SOURCE_SNAPSHOT";snapdir.mkdir(exist_ok=True)
        with zipfile.ZipFile(archive) as z:data=z.read(member)
        target=snapdir/Path(member).name;target.write_bytes(data);snapshot=str(target)
        if sha_file(target)!=sel_sha: raise RuntimeError("SELECTED_SOURCE_SNAPSHOT_HASH_MISMATCH")

    status="PASS" if found else "FAIL_CLOSED"
    result={
      "D10B_V2_STATUS":status,
      "PUBLICATION_ANCHORS_FOUND":len(anchors),
      "BASELINE_CODE_CANDIDATES_FOUND":len(rdf),
      "DISTINCT_BASELINE_IMPLEMENTATION_HASHES":distinct,
      "PUBLISHED_ACLA_IMPLEMENTATION_FOUND":"YES" if found else "NO",
      "PUBLISHED_ACLA_ENTRYPOINT":sel_path,
      "PUBLISHED_ACLA_ENTRYPOINT_SHA256":sel_sha,
      "PUBLISHED_ACLA_SELECTION_BASIS":sel_basis,
      "PUBLISHED_ACLA_SOURCE_SNAPSHOT":snapshot,
      "FAILURE_REASON":reason,
      "COMPATIBILITY_ANALYSIS_EXECUTED":"NO",
      "SIGNED_WEIGHT_ANALYSIS_EXECUTED":"NO",
      "NETWORK_CHANGED":"NO",
      "D9_FILES_MODIFIED":"NO",
      "WEIGHT_TRANSFORMATION_APPLIED":"NO",
      "PARAMETER_FREEZE_EXECUTED":"NO",
      "PARAMETER_TUNING_EXECUTED":"NO",
      "GSE243219_ACLA_EXECUTED":"NO",
      "READY_FOR_D10B_V3_COMPATIBILITY_AUDIT":"YES" if found else "NO",
      "READY_FOR_D10C_PARAMETER_AND_EXECUTION_FREEZE":"NO",
      "READY_FOR_ACLA_EXECUTION":"NO",
      "STOP":"YES"
    }
    result_path.write_text(json.dumps(result,indent=2,sort_keys=True),encoding="utf-8")
    return 0

if __name__=="__main__": raise SystemExit(main())
