#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import importlib.metadata as md
import json
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

import certifi
import pandas as pd

EXPECTED_TARGETS=187
EXPECTED_QUERIES=374
EXPECTED_COMMUNITIES=8

NCBI_BASE="https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
EINFO_URL=NCBI_BASE+"/einfo.fcgi"
ESEARCH_URL=NCBI_BASE+"/esearch.fcgi"
EFETCH_URL=NCBI_BASE+"/efetch.fcgi"

FROZEN_CERTIFI_VERSION="2026.7.22"
FROZEN_TOOL="GSE243219_D10Q"
FROZEN_RETMAX=50
FROZEN_SORT="relevance"
FROZEN_MINDATE="1900/01/01"
FROZEN_MAXDATE="2026/09/07"
FROZEN_DATETYPE="pdat"
MAX_REQUESTS_PER_SECOND=2.0
MIN_REQUEST_INTERVAL=1.0/MAX_REQUESTS_PER_SECOND
HTTP_TIMEOUT_SECONDS=240
HTTP_MAX_ATTEMPTS=4
EFETCH_BATCH_SIZE=100

def sha256_file(path: Path, chunk=8*1024*1024):
    h=hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda:f.read(chunk),b""):
            h.update(b)
    return h.hexdigest()

def sha256_text(s: str):
    return hashlib.sha256(s.encode("utf-8")).hexdigest()

def require(cond,msg):
    if not cond:
        raise RuntimeError(msg)

def verify_manifest(path: Path):
    df=pd.read_csv(path,dtype=str,keep_default_na=False)
    required={"full_path","size_bytes","SHA256"}
    require(required.issubset(df.columns),f"MANIFEST_SCHEMA_INVALID={path}")
    bad=0
    for row in df.itertuples(index=False):
        p=Path(row.full_path)
        if not p.is_file():
            bad+=1; continue
        if int(p.stat().st_size)!=int(row.size_bytes):
            bad+=1; continue
        if sha256_file(p)!=str(row.SHA256).lower():
            bad+=1
    require(bad==0,f"MANIFEST_HASH_MISMATCHES={bad}")

def utc_now():
    return datetime.now(timezone.utc).isoformat()

class RateLimiter:
    def __init__(self, interval: float):
        self.interval=float(interval)
        self.last_start=0.0
    def wait(self):
        now=time.monotonic()
        remain=self.interval-(now-self.last_start)
        if remain>0:
            time.sleep(remain)
        self.last_start=time.monotonic()

class NCBIClient:
    def __init__(self, raw_dir: Path):
        self.raw_dir=raw_dir
        self.raw_dir.mkdir(parents=True,exist_ok=True)
        self.rate=RateLimiter(MIN_REQUEST_INTERVAL)
        self.ssl_context=ssl.create_default_context(cafile=certifi.where())
        require(self.ssl_context.verify_mode==ssl.CERT_REQUIRED,"TLS_VERIFY_NOT_CERT_REQUIRED")
        require(self.ssl_context.check_hostname is True,"TLS_HOSTNAME_CHECK_DISABLED")
        self.request_counter=0

    def post_form(self,url: str,params: dict,raw_name: str,expect_json=False):
        body=urllib.parse.urlencode(params,doseq=True).encode("utf-8")
        headers={
            "User-Agent":"GSE243219-D10Q/1.0",
            "Accept":"application/json" if expect_json else "application/xml,text/xml,*/*",
            "Content-Type":"application/x-www-form-urlencoded",
            "Expect":"",
        }
        last_detail=""
        for attempt in range(1,HTTP_MAX_ATTEMPTS+1):
            self.rate.wait()
            self.request_counter+=1
            try:
                req=urllib.request.Request(url=url,data=body,headers=headers,method="POST")
                with urllib.request.urlopen(
                    req,timeout=HTTP_TIMEOUT_SECONDS,context=self.ssl_context
                ) as r:
                    content=r.read()
                    status=getattr(r,"status",200)
                if not (200 <= status < 300):
                    raise RuntimeError(f"HTTP_STATUS={status}")
                raw_path=self.raw_dir/raw_name
                raw_path.write_bytes(content)
                if expect_json:
                    try:
                        return json.loads(content.decode("utf-8"))
                    except Exception as e:
                        raise RuntimeError(
                            f"JSON_DECODE_FAILED raw={raw_path} error={type(e).__name__}:{e}"
                        ) from e
                return content
            except urllib.error.HTTPError as e:
                try:
                    eb=e.read().decode("utf-8","replace")
                except Exception:
                    eb="<UNREADABLE>"
                last_detail=f"HTTPError code={e.code} reason={e.reason} body={eb[:5000]}"
            except urllib.error.URLError as e:
                last_detail=f"URLError reason={getattr(e,'reason',e)}"
            except Exception as e:
                last_detail=f"{type(e).__name__}:{e}"
            if attempt<HTTP_MAX_ATTEMPTS:
                time.sleep(2*attempt)
        raise RuntimeError(
            f"NCBI_REQUEST_FAILED url={url} attempts={HTTP_MAX_ATTEMPTS} {last_detail}"
        )

def plan_row_hash(row):
    keys=[
        "query_id","target_id","community_id","target_category","target_label",
        "disease_context","primary_query","fallback_query_if_primary_count_zero",
        "fallback_trigger","database","sort","retmax","datetype","mindate","maxdate"
    ]
    s=json.dumps({k:str(row[k]) for k in keys},sort_keys=True,separators=(",",":"))
    return sha256_text(s)

def esearch(client: NCBIClient, query: str, raw_name: str):
    params={
        "db":"pubmed",
        "term":query,
        "retmode":"json",
        "retmax":str(FROZEN_RETMAX),
        "sort":FROZEN_SORT,
        "datetype":FROZEN_DATETYPE,
        "mindate":FROZEN_MINDATE,
        "maxdate":FROZEN_MAXDATE,
        "tool":FROZEN_TOOL,
    }
    data=client.post_form(ESEARCH_URL,params,raw_name,expect_json=True)
    require("esearchresult" in data,f"ESEARCH_RESULT_MISSING raw={raw_name}")
    r=data["esearchresult"]
    count=int(r.get("count","0"))
    ids=[str(x) for x in r.get("idlist",[])]
    require(len(ids)<=FROZEN_RETMAX,f"ESEARCH_RETMAX_EXCEEDED={len(ids)}")
    return count,ids,data

def get_text(el, path):
    x=el.find(path)
    if x is None:
        return ""
    return "".join(x.itertext()).strip()

def all_text(el, path):
    vals=[]
    for x in el.findall(path):
        s="".join(x.itertext()).strip()
        if s:
            vals.append(s)
    return vals

def parse_pubmed_xml(xml_bytes: bytes):
    root=ET.fromstring(xml_bytes)
    rows=[]

    # Standard journal-article records.
    for art in root.findall(".//PubmedArticle"):
        cit=art.find("./MedlineCitation")
        article=cit.find("./Article") if cit is not None else None
        pubmeddata=art.find("./PubmedData")
        pmid=get_text(cit,"./PMID") if cit is not None else ""
        if not pmid:
            continue
        title=get_text(article,"./ArticleTitle") if article is not None else ""
        abstract=" ".join(all_text(article,"./Abstract/AbstractText")) if article is not None else ""
        journal=get_text(article,"./Journal/Title") if article is not None else ""
        journal_iso=get_text(article,"./Journal/ISOAbbreviation") if article is not None else ""
        pub_types=all_text(article,"./PublicationTypeList/PublicationType") if article is not None else []
        authors=[]
        if article is not None:
            for a in article.findall("./AuthorList/Author"):
                collective=get_text(a,"./CollectiveName")
                if collective:
                    authors.append(collective)
                    continue
                last=get_text(a,"./LastName")
                fore=get_text(a,"./ForeName")
                name=" ".join([x for x in [fore,last] if x]).strip()
                if name:
                    authors.append(name)
        doi=""
        pmc=""
        if pubmeddata is not None:
            for aid in pubmeddata.findall("./ArticleIdList/ArticleId"):
                typ=aid.attrib.get("IdType","")
                val="".join(aid.itertext()).strip()
                if typ=="doi":
                    doi=val
                elif typ=="pmc":
                    pmc=val

        year=month=day=""
        if article is not None:
            ad=article.find("./ArticleDate")
            if ad is not None:
                year=get_text(ad,"./Year")
                month=get_text(ad,"./Month")
                day=get_text(ad,"./Day")
            if not year:
                pd_el=article.find("./Journal/JournalIssue/PubDate")
                if pd_el is not None:
                    year=get_text(pd_el,"./Year")
                    month=get_text(pd_el,"./Month")
                    day=get_text(pd_el,"./Day")
                    if not year:
                        medline=get_text(pd_el,"./MedlineDate")
                        m=re.search(r"(19|20)\d{2}",medline)
                        year=m.group(0) if m else ""
        mesh=all_text(cit,"./MeshHeadingList/MeshHeading/DescriptorName") if cit is not None else []
        rows.append({
            "pmid":pmid,
            "record_type":"PubmedArticle",
            "title":title,
            "abstract":abstract,
            "journal":journal,
            "journal_iso":journal_iso,
            "publication_year":year,
            "publication_month":month,
            "publication_day":day,
            "publication_types":"; ".join(pub_types),
            "authors":"; ".join(authors),
            "doi":doi,
            "pmc":pmc,
            "mesh_terms":"; ".join(mesh),
            "abstract_available":"YES" if abstract else "NO",
        })

    # PubMed can also return book citations. The PubMed DTD defines
    # PubmedBookArticle -> BookDocument, including PMID, ArticleTitle,
    # Abstract, AuthorList, PublicationType and Book/PubDate.
    for art in root.findall(".//PubmedBookArticle"):
        doc=art.find("./BookDocument")
        bookdata=art.find("./PubmedBookData")
        if doc is None:
            continue
        pmid=get_text(doc,"./PMID")
        if not pmid:
            continue
        title=get_text(doc,"./ArticleTitle")
        if not title:
            title=get_text(doc,"./Book/BookTitle")
        abstract=" ".join(all_text(doc,"./Abstract/AbstractText"))
        journal=get_text(doc,"./Book/BookTitle")
        journal_iso=""
        pub_types=all_text(doc,"./PublicationType")
        authors=[]
        for a in doc.findall("./AuthorList/Author"):
            collective=get_text(a,"./CollectiveName")
            if collective:
                authors.append(collective)
                continue
            last=get_text(a,"./LastName")
            fore=get_text(a,"./ForeName")
            name=" ".join([x for x in [fore,last] if x]).strip()
            if name:
                authors.append(name)
        doi=""
        pmc=""
        for parent in [doc.find("./ArticleIdList"), bookdata.find("./ArticleIdList") if bookdata is not None else None]:
            if parent is None:
                continue
            for aid in parent.findall("./ArticleId"):
                typ=aid.attrib.get("IdType","")
                val="".join(aid.itertext()).strip()
                if typ=="doi" and not doi:
                    doi=val
                elif typ=="pmc" and not pmc:
                    pmc=val
        pd_el=doc.find("./Book/PubDate")
        year=month=day=""
        if pd_el is not None:
            year=get_text(pd_el,"./Year")
            month=get_text(pd_el,"./Month")
            day=get_text(pd_el,"./Day")
            if not year:
                medline=get_text(pd_el,"./MedlineDate")
                m=re.search(r"(19|20)\d{2}",medline)
                year=m.group(0) if m else ""
        rows.append({
            "pmid":pmid,
            "record_type":"PubmedBookArticle",
            "title":title,
            "abstract":abstract,
            "journal":journal,
            "journal_iso":journal_iso,
            "publication_year":year,
            "publication_month":month,
            "publication_day":day,
            "publication_types":"; ".join(pub_types),
            "authors":"; ".join(authors),
            "doi":doi,
            "pmc":pmc,
            "mesh_terms":"",
            "abstract_available":"YES" if abstract else "NO",
        })

    return rows

def main():
    if len(sys.argv)!=7:
        raise SystemExit(
            "usage: D10Q <d10p_status> <d10p_manifest> <contract_json> "
            "<targets_csv> <query_plan_csv> <outdir>"
        )

    status_path=Path(sys.argv[1])
    manifest_path=Path(sys.argv[2])
    contract_path=Path(sys.argv[3])
    targets_path=Path(sys.argv[4])
    plan_path=Path(sys.argv[5])
    outdir=Path(sys.argv[6])
    outdir.mkdir(parents=True,exist_ok=True)

    stage_path=outdir/"D10Q_STAGE.txt"
    stage_path.write_text("UPSTREAM_VALIDATION\n",encoding="utf-8")

    t=status_path.read_text(encoding="utf-8-sig",errors="replace")
    for tok in [
        "D10P_STATUS=PASS",
        "COMMUNITIES_FROZEN=8",
        "ALL_COMMUNITIES_INCLUDED=YES",
        "LITERATURE_TARGETS=187",
        "PUBMED_QUERIES_PLANNED=374",
        "PUBMED_DATABASE=pubmed",
        "PUBMED_ESEARCH_SORT=relevance",
        "PUBMED_RETMAX=50",
        "PUBMED_MIN_DATE=1900/01/01",
        "PUBMED_MAX_DATE=2026/09/07",
        "MAX_REQUESTS_PER_SECOND=2.0",
        "GENE_ALIAS_EXPANSION=PROHIBITED",
        "D10Q_SCOPE=SEARCH_RETRIEVAL_AND_PROVENANCE_ONLY",
        "D10Q_BIOLOGICAL_NARRATIVE=PROHIBITED",
        "READY_FOR_D10Q_PUBMED_RETRIEVAL=YES",
    ]:
        require(tok in t,f"D10P_AUTHORITY_TOKEN_MISSING={tok}")

    verify_manifest(manifest_path)

    contract=json.loads(contract_path.read_text(encoding="utf-8"))
    require(contract["D10P_STATUS"]=="PASS","D10P_CONTRACT_NOT_PASS")
    require(int(contract["LITERATURE_TARGETS"])==EXPECTED_TARGETS,"TARGET_COUNT_CHANGED")
    require(int(contract["PUBMED_QUERIES_PLANNED"])==EXPECTED_QUERIES,"QUERY_COUNT_CHANGED")
    require(contract["PUBMED_ESEARCH_SORT"]==FROZEN_SORT,"PUBMED_SORT_CHANGED")
    require(int(contract["PUBMED_RETMAX"])==FROZEN_RETMAX,"PUBMED_RETMAX_CHANGED")
    require(contract["PUBMED_MIN_DATE"]==FROZEN_MINDATE,"PUBMED_MINDATE_CHANGED")
    require(contract["PUBMED_MAX_DATE"]==FROZEN_MAXDATE,"PUBMED_MAXDATE_CHANGED")
    require(float(contract["MAX_REQUESTS_PER_SECOND"])==MAX_REQUESTS_PER_SECOND,"RATE_LIMIT_CHANGED")

    certifi_version=md.version("certifi")
    require(
        certifi_version==FROZEN_CERTIFI_VERSION,
        f"CERTIFI_VERSION_MISMATCH expected={FROZEN_CERTIFI_VERSION} actual={certifi_version}"
    )
    ca_path=Path(certifi.where())
    require(ca_path.is_file(),f"CERTIFI_BUNDLE_MISSING={ca_path}")
    ca_sha=sha256_file(ca_path)

    targets=pd.read_csv(targets_path,dtype=str,keep_default_na=False)
    plan=pd.read_csv(plan_path,dtype=str,keep_default_na=False)
    require(len(targets)==EXPECTED_TARGETS,f"TARGET_ROWS={len(targets)}")
    require(len(plan)==EXPECTED_QUERIES,f"PLAN_ROWS={len(plan)}")
    require(targets["target_id"].nunique()==EXPECTED_TARGETS,"DUPLICATE_TARGET_IDS")
    require(plan["query_id"].nunique()==EXPECTED_QUERIES,"DUPLICATE_QUERY_IDS")
    require(set(plan["target_id"])==set(targets["target_id"]),"PLAN_TARGET_SET_MISMATCH")
    require(set(pd.to_numeric(plan["community_id"]).astype(int))==set(range(1,9)),
            "PLAN_NOT_ALL_8_COMMUNITIES")

    # Revalidate all frozen constant fields in query plan.
    require(set(plan["database"])=={"pubmed"},"PLAN_DATABASE_CHANGED")
    require(set(plan["sort"])=={FROZEN_SORT},"PLAN_SORT_CHANGED")
    require(set(plan["retmax"].astype(str))=={str(FROZEN_RETMAX)},"PLAN_RETMAX_CHANGED")
    require(set(plan["datetype"])=={FROZEN_DATETYPE},"PLAN_DATETYPE_CHANGED")
    require(set(plan["mindate"])=={FROZEN_MINDATE},"PLAN_MINDATE_CHANGED")
    require(set(plan["maxdate"])=={FROZEN_MAXDATE},"PLAN_MAXDATE_CHANGED")
    require(set(plan["fallback_trigger"])=={"PRIMARY_ESEARCH_COUNT_EQUALS_ZERO_ONLY"},
            "FALLBACK_TRIGGER_CHANGED")

    raw_dir=outdir/"RAW_NCBI"
    query_raw_dir=raw_dir/"ESEARCH"
    fetch_raw_dir=raw_dir/"EFETCH"
    query_ckpt_dir=outdir/"QUERY_CHECKPOINTS"
    for d in [raw_dir,query_raw_dir,fetch_raw_dir,query_ckpt_dir]:
        d.mkdir(parents=True,exist_ok=True)

    client=NCBIClient(raw_dir)

    # Snapshot PubMed EInfo before retrieval.
    stage_path.write_text("NCBI_EINFO\n",encoding="utf-8")
    einfo_params={
        "db":"pubmed",
        "retmode":"json",
        "tool":FROZEN_TOOL,
    }
    einfo=client.post_form(EINFO_URL,einfo_params,"EINFO_pubmed.json",expect_json=True)
    require("einforesult" in einfo,"EINFO_RESULT_MISSING")

    # Execute frozen ESearch plan with exact-query checkpoints.
    stage_path.write_text("ESEARCH\n",encoding="utf-8")
    result_rows=[]
    mapping_rows=[]
    primary_zero=0
    fallback_used=0

    for idx,row in plan.iterrows():
        qid=str(row["query_id"])
        ckpt=query_ckpt_dir/f"{qid}.json"
        ph=plan_row_hash(row)

        if ckpt.is_file():
            saved=json.loads(ckpt.read_text(encoding="utf-8"))
            require(saved.get("plan_row_sha256")==ph,f"CHECKPOINT_PLAN_HASH_MISMATCH query={qid}")
            require(saved.get("query_id")==qid,f"CHECKPOINT_QUERY_ID_MISMATCH={qid}")
            rec=saved
        else:
            primary_query=str(row["primary_query"])
            primary_raw=f"ESEARCH/{qid}_primary.json"
            pcount,pids,_=esearch(client,primary_query,primary_raw)
            used_fallback=False
            chosen_query=primary_query
            chosen_count=pcount
            chosen_ids=pids
            fallback_count=None

            if pcount==0:
                primary_zero+=1
                fallback_used+=1
                used_fallback=True
                fallback_query=str(row["fallback_query_if_primary_count_zero"])
                fallback_raw=f"ESEARCH/{qid}_fallback.json"
                fcount,fids,_=esearch(client,fallback_query,fallback_raw)
                fallback_count=fcount
                chosen_query=fallback_query
                chosen_count=fcount
                chosen_ids=fids

            rec={
                "query_id":qid,
                "target_id":str(row["target_id"]),
                "community_id":int(row["community_id"]),
                "target_category":str(row["target_category"]),
                "target_label":str(row["target_label"]),
                "disease_context":str(row["disease_context"]),
                "plan_row_sha256":ph,
                "primary_query":primary_query,
                "primary_count":int(pcount),
                "fallback_used":"YES" if used_fallback else "NO",
                "fallback_query":str(row["fallback_query_if_primary_count_zero"]) if used_fallback else "",
                "fallback_count":int(fallback_count) if fallback_count is not None else "",
                "chosen_query":chosen_query,
                "chosen_count":int(chosen_count),
                "returned_pmids":[str(x) for x in chosen_ids],
                "returned_pmid_count":len(chosen_ids),
                "retmax":FROZEN_RETMAX,
                "sort":FROZEN_SORT,
                "mindate":FROZEN_MINDATE,
                "maxdate":FROZEN_MAXDATE,
                "completed_utc":utc_now(),
            }
            ckpt.write_text(json.dumps(rec,indent=2),encoding="utf-8")

        # Count saved checkpoint flags too for complete totals.
        if int(rec["primary_count"])==0:
            primary_zero+=0 if not ckpt.is_file() else 0
        result_rows.append({k:v for k,v in rec.items() if k!="returned_pmids"})
        for rank,pmid in enumerate(rec["returned_pmids"],1):
            mapping_rows.append({
                "query_id":qid,
                "target_id":rec["target_id"],
                "community_id":rec["community_id"],
                "target_category":rec["target_category"],
                "target_label":rec["target_label"],
                "disease_context":rec["disease_context"],
                "fallback_used":rec["fallback_used"],
                "pmid_rank":rank,
                "pmid":str(pmid),
            })

    result_df=pd.DataFrame(result_rows)
    mapping_df=pd.DataFrame(mapping_rows)
    result_df.to_csv(outdir/"D10Q_QUERY_RESULTS.csv",index=False)
    if len(mapping_df)==0:
        mapping_df=pd.DataFrame(columns=[
            "query_id","target_id","community_id","target_category","target_label",
            "disease_context","fallback_used","pmid_rank","pmid"
        ])
    mapping_df.to_csv(outdir/"D10Q_QUERY_PMID_MAPPING.csv",index=False)

    require(len(result_df)==EXPECTED_QUERIES,f"QUERY_RESULT_ROWS={len(result_df)}")
    require(result_df["query_id"].nunique()==EXPECTED_QUERIES,"QUERY_RESULTS_DUPLICATE_IDS")
    require(set(result_df["query_id"])==set(plan["query_id"]),"QUERY_RESULTS_PLAN_SET_MISMATCH")

    # Fallback integrity: exactly iff primary count == 0.
    calc_fb=(pd.to_numeric(result_df["primary_count"])==0)
    flag_fb=result_df["fallback_used"].eq("YES")
    require((calc_fb==flag_fb).all(),"FALLBACK_POLICY_VIOLATION")

    unique_pmids=sorted(set(mapping_df["pmid"].astype(str))) if len(mapping_df) else []
    (outdir/"D10Q_UNIQUE_PMIDS.txt").write_text(
        "\n".join(unique_pmids)+("\n" if unique_pmids else ""),encoding="utf-8"
    )

    # Retrieve each unique PMID once in deterministic 100-PMID batches.
    stage_path.write_text("EFETCH\n",encoding="utf-8")
    article_rows=[]
    fetched_pmids=set()
    fetch_batch_rows=[]

    for batch_index,start in enumerate(range(0,len(unique_pmids),EFETCH_BATCH_SIZE),1):
        ids=unique_pmids[start:start+EFETCH_BATCH_SIZE]
        batch_file=fetch_raw_dir/f"EFETCH_batch_{batch_index:04d}.xml"
        batch_meta=fetch_raw_dir/f"EFETCH_batch_{batch_index:04d}.json"

        expected_id_hash=sha256_text("\n".join(ids))
        if batch_file.is_file() and batch_meta.is_file():
            meta=json.loads(batch_meta.read_text(encoding="utf-8"))
            require(meta.get("pmid_list_sha256")==expected_id_hash,
                    f"EFETCH_CHECKPOINT_HASH_MISMATCH batch={batch_index}")
            xml_bytes=batch_file.read_bytes()
        else:
            params={
                "db":"pubmed",
                "id":",".join(ids),
                "retmode":"xml",
                "tool":FROZEN_TOOL,
            }
            xml_bytes=client.post_form(
                EFETCH_URL,params,f"EFETCH/EFETCH_batch_{batch_index:04d}.xml",
                expect_json=False
            )
            meta={
                "batch_index":batch_index,
                "pmid_count_requested":len(ids),
                "pmid_list_sha256":expected_id_hash,
                "pmids":ids,
                "completed_utc":utc_now(),
            }
            batch_meta.write_text(json.dumps(meta,indent=2),encoding="utf-8")

        parsed=parse_pubmed_xml(xml_bytes)
        parsed_ids={str(x["pmid"]) for x in parsed}
        require(parsed_ids.issubset(set(ids)),f"EFETCH_UNEXPECTED_PMID batch={batch_index}")
        fetched_pmids |= parsed_ids
        article_rows.extend(parsed)
        fetch_batch_rows.append({
            "batch_index":batch_index,
            "requested_pmids":len(ids),
            "parsed_pubmed_articles":len(parsed),
            "pmid_list_sha256":expected_id_hash,
            "raw_xml_file":str(batch_file),
        })

    missing_fetch=set(unique_pmids)-fetched_pmids
    require(len(missing_fetch)==0,
            f"EFETCH_MISSING_PMIDS count={len(missing_fetch)} sample={sorted(missing_fetch)[:10]}")

    articles=pd.DataFrame(article_rows)
    if len(articles)==0:
        articles=pd.DataFrame(columns=[
            "pmid","record_type","title","abstract","journal","journal_iso","publication_year",
            "publication_month","publication_day","publication_types","authors","doi",
            "pmc","mesh_terms","abstract_available"
        ])
    else:
        articles=articles.drop_duplicates(subset=["pmid"],keep="first")
    require(len(articles)==len(unique_pmids),
            f"UNIQUE_ARTICLE_COUNT_MISMATCH expected={len(unique_pmids)} actual={len(articles)}")
    articles.to_csv(outdir/"D10Q_PUBMED_RECORDS.csv",index=False)
    pd.DataFrame(fetch_batch_rows).to_csv(outdir/"D10Q_EFETCH_BATCH_AUDIT.csv",index=False)

    # Query/article join for later screening; duplicates by query are intentional.
    joined=mapping_df.merge(articles,on="pmid",how="left",validate="many_to_one")
    if len(joined):
        require(joined["title"].notna().all(),"QUERY_ARTICLE_JOIN_MISSING_METADATA")
    joined.to_csv(outdir/"D10Q_QUERY_ARTICLE_CANDIDATES.csv",index=False)

    # Deduplicated PMID-to-target mapping preserves every target/query association.
    pmid_target=(
        mapping_df.groupby("pmid",dropna=False)
        .agg(
            query_count=("query_id","nunique"),
            target_count=("target_id","nunique"),
            communities=("community_id",lambda x:";".join(map(str,sorted(set(map(int,x)))))),
            query_ids=("query_id",lambda x:";".join(sorted(set(map(str,x))))),
            target_ids=("target_id",lambda x:";".join(sorted(set(map(str,x))))),
            disease_contexts=("disease_context",lambda x:";".join(sorted(set(map(str,x))))),
        )
        .reset_index()
        if len(mapping_df) else
        pd.DataFrame(columns=[
            "pmid","query_count","target_count","communities","query_ids",
            "target_ids","disease_contexts"
        ])
    )
    pmid_target.to_csv(outdir/"D10Q_PMID_TARGET_INDEX.csv",index=False)

    # Coverage audit for all 374 frozen queries, including zero-hit queries.
    coverage=(
        result_df.groupby(["community_id","disease_context"],dropna=False)
        .agg(
            queries=("query_id","count"),
            zero_primary_queries=("primary_count",lambda x:int((pd.to_numeric(x)==0).sum())),
            fallback_queries=("fallback_used",lambda x:int((x=="YES").sum())),
            zero_final_queries=("chosen_count",lambda x:int((pd.to_numeric(x)==0).sum())),
            total_search_count=("chosen_count",lambda x:int(pd.to_numeric(x).sum())),
            returned_pmids=("returned_pmid_count",lambda x:int(pd.to_numeric(x).sum())),
        )
        .reset_index()
    )
    coverage.to_csv(outdir/"D10Q_RETRIEVAL_COVERAGE_AUDIT.csv",index=False)

    # Retrieval provenance.
    plan_sha=sha256_file(plan_path)
    targets_sha=sha256_file(targets_path)
    contract_sha=sha256_file(contract_path)
    provenance={
        "D10Q_STATUS":"PASS",
        "COMMUNITIES_COVERED":8,
        "LITERATURE_TARGETS":EXPECTED_TARGETS,
        "FROZEN_QUERIES_EXECUTED":EXPECTED_QUERIES,
        "QUERY_RESULTS_ROWS":len(result_df),
        "QUERIES_USING_FALLBACK":int(flag_fb.sum()),
        "QUERIES_WITH_ZERO_FINAL_RESULTS":int((pd.to_numeric(result_df["chosen_count"])==0).sum()),
        "QUERY_PMID_MAPPING_ROWS":len(mapping_df),
        "UNIQUE_PMIDS":len(unique_pmids),
        "PUBMED_RECORDS_RETRIEVED":len(articles),
        "RECORDS_WITH_ABSTRACT":int((articles["abstract_available"]=="YES").sum()) if len(articles) else 0,
        "RECORDS_WITHOUT_ABSTRACT":int((articles["abstract_available"]=="NO").sum()) if len(articles) else 0,
        "NCBI_REQUESTS_THIS_INVOCATION":client.request_counter,
        "PUBMED_DATABASE":"pubmed",
        "PUBMED_ESEARCH_SORT":FROZEN_SORT,
        "PUBMED_RETMAX":FROZEN_RETMAX,
        "PUBMED_DATETYPE":FROZEN_DATETYPE,
        "PUBMED_MINDATE":FROZEN_MINDATE,
        "PUBMED_MAXDATE":FROZEN_MAXDATE,
        "MAX_REQUESTS_PER_SECOND":MAX_REQUESTS_PER_SECOND,
        "NCBI_TOOL":FROZEN_TOOL,
        "TLS_VERIFICATION_POLICY":"CERTIFI_MOZILLA_CA_BUNDLE_REQUIRED",
        "TLS_CERTIFICATE_VERIFICATION_DISABLED":"NO",
        "CERTIFI_VERSION":certifi_version,
        "CERTIFI_CA_BUNDLE_SHA256":ca_sha,
        "D10P_QUERY_PLAN_SHA256":plan_sha,
        "D10P_TARGETS_SHA256":targets_sha,
        "D10P_CONTRACT_SHA256":contract_sha,
        "GENE_ALIAS_EXPANSION_EXECUTED":"NO",
        "BIOLOGICAL_NARRATIVE_EXECUTED":"NO",
        "LITERATURE_SCREENING_EXECUTED":"NO",
        "LITERATURE_CAN_CHANGE_COMMUNITIES":"NO",
        "LITERATURE_CAN_CHANGE_HUB_STATUS":"NO",
        "LITERATURE_CAN_CHANGE_ENRICHMENT":"NO",
        "CONTRADICTORY_EVIDENCE_FILTERING_EXECUTED":"NO",
        "LITERATURE_CONCORDANCE_COUNTS_AS_ACLA_VALIDATION":"NO",
        "READY_FOR_D10R_LITERATURE_SCREENING_DESIGN":"YES",
        "STOP":"YES",
    }
    (outdir/"D10Q_SUMMARY.json").write_text(json.dumps(provenance,indent=2),encoding="utf-8")

    stage_path.write_text("PASS\n",encoding="utf-8")
    incomplete=outdir/"D10Q_INCOMPLETE.marker"
    if incomplete.exists():
        incomplete.unlink()
    return 0

if __name__=="__main__":
    try:
        raise SystemExit(main())
    except SystemExit:
        raise
    except Exception:
        import traceback
        tb=traceback.format_exc()
        try:
            outdir=Path(sys.argv[6]) if len(sys.argv)>=7 else Path.cwd()
            outdir.mkdir(parents=True,exist_ok=True)
            (outdir/"D10Q_FAILURE_TRACEBACK.txt").write_text(tb,encoding="utf-8")
            stage=(outdir/"D10Q_STAGE.txt").read_text(encoding="utf-8").strip() \
                if (outdir/"D10Q_STAGE.txt").is_file() else "UNKNOWN"
            failure={
                "D10Q_STATUS":"NOT_EVALUATED",
                "FAILURE_STAGE":stage,
                "FAILURE_MESSAGE":str(sys.exc_info()[1]),
                "TRACEBACK_FILE":"D10Q_FAILURE_TRACEBACK.txt",
                "BIOLOGICAL_NARRATIVE_EXECUTED":"NO",
                "LITERATURE_SCREENING_EXECUTED":"NO",
                "READY_FOR_D10R_LITERATURE_SCREENING_DESIGN":"NO",
                "STOP":"YES",
            }
            (outdir/"D10Q_FAILURE.json").write_text(json.dumps(failure,indent=2),encoding="utf-8")
        except Exception:
            pass
        sys.stderr.write(tb)
        raise SystemExit(1)
