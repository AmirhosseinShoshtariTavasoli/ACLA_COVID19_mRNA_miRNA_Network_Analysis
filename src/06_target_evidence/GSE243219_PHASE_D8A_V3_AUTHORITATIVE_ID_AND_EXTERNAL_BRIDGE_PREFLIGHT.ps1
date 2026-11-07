$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D8A-V3 — IDENTIFIER-REFERENCE CORRECTION
#                + miRDB REFSEQ BRIDGE PREFLIGHT
#
# This is a corrective PRE-INTEGRATION phase after D8A failed
# before any target-database edge matching.
#
# It fixes the remaining identifier-policy error after D8A-V2:
#   - the frozen GSE243219 mRNA gene symbol is the authoritative
#     project/node identity;
#   - the NCBI Gene-derived HGNC-equivalent table is an optional
#     unique identifier bridge, NOT an admission gate;
#   - ambiguous/unmatched external mappings never delete or rename
#     a frozen project feature;
#   - miRDB v6 column 2 remains correctly treated as RefSeq RNA.
#
# It does NOT change the frozen D8 evidence rule.
#
# D8A-V3 performs:
#   - D7C / D8-V6 recertification
#   - selected reusable asset SHA-256 recertification
#   - exact/unique reference-symbol mapping for 4,467 mRNA IDs
#   - miRBase 22.1 exact validation for 41 project miRNAs
#   - TargetScan Release-8 family-metadata audit
#   - miRDB native RefSeq accession audit
#   - generic human RefSeq->gene bridge construction using the
#     official NCBI GRCh38.p14 human feature table
#
# If the official human feature table is not already present in
# reusable/project reference assets, D8A-V3 downloads it from NCBI
# into this NEW project's target-evidence reference cache.
#
# IMPORTANT:
#   GRCh38.p14 is used ONLY to interpret miRDB's RefSeq target
#   identifiers. It does NOT reinterpret the GSE243217 hg19
#   expression feature identities or expression values.
#
# PROHIBITED IN D8A-V3:
#   target-database edge matching = NO
#   target-evidence overlap counts = NO
#   regulatory-edge classification = NO
#   network construction = NO
#   A-CLA = NO
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$Reusable = Join-Path $Parent '00_REUSABLE_ASSETS'

$D6Root = Join-Path $Project '06_ASSOCIATION_AND_STABILITY'
$D8Root = Join-Path $Project '07_TARGET_EVIDENCE'

$D7CRun = Join-Path $D6Root 'D7C_ASSOCIATION_STABILITY_AUDIT_EDGE_FREEZE_20260905_145214'
$D7CManifest = Join-Path $D7CRun 'D7C_OUTPUT_SHA256_MANIFEST.csv'
$StableEdges = Join-Path $D7CRun 'D7C_FROZEN_STABLE_ASSOCIATION_EDGES.csv.gz'

$D8Run = Join-Path $D8Root 'D8_V6_TARGET_EVIDENCE_PREFLIGHT_20260905_154552'
$D8Manifest = Join-Path $D8Run 'D8_OUTPUT_SHA256_MANIFEST.csv'
$D8Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D8_V6_20260905_154552\PHASE_D8_SUMMARY.txt'
$D8AssetInventory = Join-Path $D8Run 'D8_REUSABLE_TARGET_ASSET_INVENTORY.csv'
$D8FrozenStrategy = Join-Path $D8Run 'D8_FROZEN_TARGET_EVIDENCE_STRATEGY.txt'

$ReferenceCache = Join-Path $D8Root '00_REFERENCE_INPUTS\NCBI_GRCh38p14'
New-Item -ItemType Directory -Path $ReferenceCache -Force | Out-Null

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D8Root ('D8A_V3_IDENTIFIER_BRIDGE_PREFLIGHT_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D8A_V3_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D8A_V3_IDENTIFIER_REFERENCE_AND_REFSEQ_BRIDGE_PREFLIGHT.py'
$GeneAudit = Join-Path $RunDir 'D8A_V3_PROJECT_GENE_REFERENCE_MAPPING_AUDIT.csv'
$MiRNAValidation = Join-Path $RunDir 'D8A_V3_MIRBASE_41_PROJECT_MIRNA_VALIDATION.csv'
$TargetScanFamilyAudit = Join-Path $RunDir 'D8A_V3_TARGETSCAN_RELEASE8_FAMILY_METADATA_AUDIT.csv'
$TargetScanFamilyAsset = Join-Path $RunDir 'D8A_V3_TARGETSCAN_FAMILY_METADATA_ASSET.csv'
$MiRDBNativeAudit = Join-Path $RunDir 'D8A_V3_MIRDB_NATIVE_REFSEQ_AUDIT.csv'
$RefSeqBridge = Join-Path $RunDir 'D8A_V3_MIRDB_REFSEQ_TO_PROJECT_GENE_BRIDGE.csv.gz'
$RefSeqReferenceAudit = Join-Path $RunDir 'D8A_V3_NCBI_REFSEQ_REFERENCE_AUDIT.csv'
$CorrectedSpec = Join-Path $RunDir 'D8A_V3_CORRECTED_IDENTIFIER_INTEGRATION_SPECIFICATION.txt'
$ResultJson = Join-Path $RunDir 'D8A_V3_RESULT.json'

$PythonStdout = Join-Path $RunDir 'D8A_V3_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D8A_V3_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D8A_V3_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D8A_V3_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D8A_V3_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D8A_V3_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D8A-V3 — AUTHORITATIVE PROJECT-ID + EXTERNAL BRIDGE PREFLIGHT ==='
Write-Host 'MODE=CORRECTIVE_AUTHORITATIVE_ID_AND_BRIDGE_PREFLIGHT_ONLY'
Write-Host 'D8A_V1_FAILURE=HGNC_LITERAL_APPROVED_STATUS_FILTER_REJECTED_NCBI_GENE_DERIVED_REFERENCE'
Write-Host 'D8A_V3_CORRECTION_1=PROJECT_GENE_SYMBOL_IS_AUTHORITATIVE_NODE_ID'
Write-Host 'D8A_V3_CORRECTION_2=EXTERNAL_REFERENCE_IS_UNIQUE_BRIDGE_NOT_PROJECT_ADMISSION_GATE'
Write-Host 'FROZEN_STABLE_ASSOCIATION_EDGES=11531'
Write-Host 'FROZEN_STABLE_UNIQUE_MRNA_IDS=4467'
Write-Host 'FROZEN_STABLE_UNIQUE_MIRNA_IDS=41'
Write-Host 'MIRDB_HIGH_CONFIDENCE_RULE_UNCHANGED=SCORE_GT_80'
Write-Host 'TARGET_DATABASE_EDGE_MATCHING_EXECUTED=NO'
Write-Host 'TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED=NO'
Write-Host 'REGULATORY_EDGE_CLASSIFICATION_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)
Write-Host ('REFERENCE_CACHE={0}' -f $ReferenceCache)

foreach ($p in @(
    $D7CManifest,$StableEdges,
    $D8Manifest,$D8Report,$D8AssetInventory,$D8FrozenStrategy
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D8A_V3_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D8AV2SHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Recertify-Manifest {
    param([string]$ManifestPath,[int]$ExpectedRows,[string]$Label)
    $rows = @(Import-Csv -LiteralPath $ManifestPath)
    if ($rows.Count -ne $ExpectedRows) {
        throw ('{0}_MANIFEST_ROW_COUNT_CHANGED expected={1} observed={2}' -f $Label,$ExpectedRows,$rows.Count)
    }
    foreach ($r in $rows) {
        if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
            throw ('{0}_OUTPUT_MISSING={1}' -f $Label,$r.full_path)
        }
        $item = Get-Item -LiteralPath $r.full_path
        $hash = Get-D8AV2SHA256 $r.full_path
        if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or $hash -ne $r.SHA256.ToLowerInvariant()) {
            throw ('{0}_OUTPUT_CHANGED={1}' -f $Label,$r.full_path)
        }
    }
    Write-Host ('{0}_OUTPUTS_RECERTIFIED={1}/{1}' -f $Label,$ExpectedRows)
}

Recertify-Manifest -ManifestPath $D7CManifest -ExpectedRows 11 -Label 'D7C'
Write-Host 'D7C_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D8Manifest -ExpectedRows 10 -Label 'D8_V6'
Write-Host 'D8_V6_CERTIFICATION_GATE=PASS'

$d8 = Get-Content -LiteralPath $D8Report -Raw
foreach ($tok in @(
    'PHASE_D8_V6_STATUS=PASS',
    'FROZEN_STABLE_ASSOCIATION_EDGES=11531',
    'FROZEN_STABLE_UNIQUE_MRNA_IDS=4467',
    'FROZEN_STABLE_UNIQUE_MIRNA_IDS=41',
    'REUSABLE_TARGET_ASSET_TYPES_FOUND=5',
    'REUSABLE_TARGET_ASSET_SCHEMA_AUDIT=PASS',
    'TARGET_EVIDENCE_STRATEGY_FROZEN=YES',
    'MIRDB_HIGH_CONFIDENCE_RULE=SCORE_GT_80',
    'SINGLE_PREDICTOR_ONLY_ELIGIBLE=NO',
    'READY_FOR_D8A_TARGET_EVIDENCE_INTEGRATION=YES'
)) {
    if (-not $d8.Contains($tok)) {
        throw ('D8_V6_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$PythonExe = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING\D2D_PREFLIGHT_20260904_195001\venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw ('PYTHON_EXECUTABLE_MISSING={0}' -f $PythonExe)
}

$PythonVersion = & $PythonExe -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$PandasVersion = & $PythonExe -c "import pandas; print(pandas.__version__)"
$NumpyVersion = & $PythonExe -c "import numpy; print(numpy.__version__)"

Write-Host ('PYTHON_VERSION={0}' -f $PythonVersion)
Write-Host ('PANDAS_VERSION={0}' -f $PandasVersion)
Write-Host ('NUMPY_VERSION={0}' -f $NumpyVersion)

$PythonCode = @'
import csv
import gzip
import hashlib
import json
import os
import re
import sys
import time
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path

import numpy as np
import pandas as pd

REUSABLE=Path(sys.argv[1])
STABLE_EDGES=Path(sys.argv[2])
ASSET_INVENTORY=Path(sys.argv[3])
FROZEN_STRATEGY=Path(sys.argv[4])
REFERENCE_CACHE=Path(sys.argv[5])

GENE_AUDIT=Path(sys.argv[6])
MIRNA_VALIDATION=Path(sys.argv[7])
TS_FAMILY_AUDIT=Path(sys.argv[8])
TS_FAMILY_ASSET=Path(sys.argv[9])
MIRDB_NATIVE_AUDIT=Path(sys.argv[10])
REFSEQ_BRIDGE=Path(sys.argv[11])
REFSEQ_REFERENCE_AUDIT=Path(sys.argv[12])
CORRECTED_SPEC=Path(sys.argv[13])
RESULT_JSON=Path(sys.argv[14])

NCBI_FEATURE_URL=(
    "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/405/"
    "GCF_000001405.40_GRCh38.p14/"
    "GCF_000001405.40_GRCh38.p14_feature_table.txt.gz"
)
NCBI_FEATURE_NAME="GCF_000001405.40_GRCh38.p14_feature_table.txt.gz"
REFSEQ_PREFIXES=("NM_","NR_","XM_","XR_")

results={}
def put(k,v):
    results[k]=v
    print(f"{k}={v}",flush=True)

def sha256_stream(path,chunk=8*1024*1024):
    h=hashlib.sha256()
    with open(path,"rb") as f:
        while True:
            b=f.read(chunk)
            if not b: break
            h.update(b)
    return h.hexdigest()

def norm_col(x):
    return re.sub(r"[^a-z0-9]+","",str(x).lower())

def normalize_header(x):
    return re.sub(
        r"[^a-z0-9]+","_",str(x).lstrip("#").strip().lower()
    ).strip("_")

def strip_version(x):
    return str(x or "").strip().split(".")[0]

def split_multi(v):
    s=str(v or "").strip()
    if not s or s in {"-","nan","None"}:
        return []
    return [
        x.strip()
        for x in re.split(r"[|,;]+",s)
        if x.strip() and x.strip()!="-"
    ]

def download_resume(url,dest):
    dest.parent.mkdir(parents=True,exist_ok=True)
    if dest.is_file() and dest.stat().st_size>0:
        put("NCBI_FEATURE_TABLE_DOWNLOAD_ACTION","REUSE_EXISTING_COMPLETE_CANDIDATE")
        return

    part=dest.with_suffix(dest.suffix+".part")
    start=part.stat().st_size if part.exists() else 0
    headers={"User-Agent":"GSE243219-D8A-V3-RefSeqBridge/1.0"}
    if start:
        headers["Range"]=f"bytes={start}-"

    req=urllib.request.Request(url,headers=headers)
    with urllib.request.urlopen(req,timeout=180) as response:
        mode="ab" if start and getattr(response,"status",200)==206 else "wb"
        if mode=="wb":
            start=0
        with open(part,mode) as out:
            while True:
                block=response.read(8*1024*1024)
                if not block:
                    break
                out.write(block)
    part.replace(dest)
    put("NCBI_FEATURE_TABLE_DOWNLOAD_ACTION","DOWNLOADED")

def find_local_feature_table():
    candidates=[]
    roots=[REUSABLE,REFERENCE_CACHE]
    for root in roots:
        if not root.exists():
            continue
        for p in root.rglob(NCBI_FEATURE_NAME):
            if p.is_file() and p.stat().st_size>0:
                # Avoid any derived network-specific mapping artifact:
                low=str(p).lower()
                if "to_network_gene" in low:
                    continue
                candidates.append(p)
    if not candidates:
        return None
    candidates=sorted(
        candidates,
        key=lambda p:(
            1 if REFERENCE_CACHE in p.parents else 0,
            p.stat().st_size,
            str(p).lower(),
        ),
        reverse=True,
    )
    return candidates[0]

def validate_feature_table_schema(path):
    with gzip.open(
        path,"rt",encoding="utf-8-sig",errors="replace",newline=""
    ) as f:
        reader=csv.reader(f,delimiter="\t")
        header=next(reader)
    cols=[normalize_header(x) for x in header]
    cset=set(cols)
    product_ok=bool(
        {"product_accession","product_accession_version"} & cset
    )
    symbol_ok=bool({"symbol","gene_symbol"} & cset)
    geneid_ok=bool({"geneid","gene_id"} & cset)
    if not product_ok or not (symbol_ok or geneid_ok):
        raise RuntimeError(
            f"NCBI_FEATURE_TABLE_SCHEMA_UNEXPECTED columns={cols}"
        )
    return cols

# ------------------------------------------------------------
# A. Re-certify the exact D8-selected reusable assets
# ------------------------------------------------------------
inv=pd.read_csv(ASSET_INVENTORY,dtype=str,keep_default_na=False)
selected=inv.loc[inv["selected_primary"].astype(str).eq("YES")].copy()
required={
    "TARBASE_V9_HUMAN",
    "MIRDB_V6_HUMAN",
    "TARGETSCANHUMAN_8_DEFAULT",
    "MIRBASE_22_1_MATURE",
    "HGNC_COMPLETE_SET",
}
if set(selected["asset_kind"])!=required:
    raise RuntimeError(
        "D8_SELECTED_ASSET_KIND_SET_CHANGED="
        + repr(sorted(selected["asset_kind"].tolist()))
    )

assets={}
for _,r in selected.iterrows():
    kind=r["asset_kind"]
    p=Path(r["full_path"])
    if not p.is_file():
        raise RuntimeError(f"D8_SELECTED_ASSET_MISSING={kind}|{p}")
    observed=sha256_stream(p)
    expected=r["SHA256"].lower()
    if observed!=expected:
        raise RuntimeError(
            f"D8_SELECTED_ASSET_SHA256_CHANGED={kind}"
        )
    assets[kind]=p
put("D8_SELECTED_REUSABLE_ASSETS_RECERTIFIED","PASS")

# ------------------------------------------------------------
# B. Frozen stable edge identifiers
# ------------------------------------------------------------
stable=pd.read_csv(
    STABLE_EDGES,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
if stable.shape[0]!=11531:
    raise RuntimeError(
        f"STABLE_EDGE_ROWS_CHANGED observed={stable.shape[0]}"
    )
if stable.duplicated(["mRNA_id","miRNA_id"]).any():
    raise RuntimeError("STABLE_EDGE_PAIR_DUPLICATION_CHANGED")

stable["mRNA_id"]=stable["mRNA_id"].astype(str)
stable["miRNA_id"]=stable["miRNA_id"].astype(str)
stable["project_MIMAT"]=stable["miRNA_id"].str.split("|",n=1).str[0]
stable["project_mature_miRNA"]=stable["miRNA_id"].str.split("|",n=1).str[1]

unique_mrna=list(dict.fromkeys(stable["mRNA_id"].tolist()))
unique_mirna_ids=list(dict.fromkeys(stable["miRNA_id"].tolist()))
unique_mature=list(dict.fromkeys(stable["project_mature_miRNA"].tolist()))
unique_mimat=list(dict.fromkeys(stable["project_MIMAT"].tolist()))

if len(unique_mrna)!=4467:
    raise RuntimeError(
        f"UNIQUE_MRNA_COUNT_CHANGED observed={len(unique_mrna)}"
    )
if len(unique_mirna_ids)!=41:
    raise RuntimeError(
        f"UNIQUE_MIRNA_COUNT_CHANGED observed={len(unique_mirna_ids)}"
    )
put("FROZEN_STABLE_EDGE_IDENTIFIER_INPUT_RECERTIFIED","PASS")

# ------------------------------------------------------------
# C. Correct interpretation of reusable HGNC-equivalent reference
# ------------------------------------------------------------
ref_path=assets["HGNC_COMPLETE_SET"]
ref=pd.read_csv(
    ref_path,sep="\t",dtype=str,keep_default_na=False,low_memory=False
)
cols={norm_col(c):c for c in ref.columns}
required_ref={
    "hgncid","symbol","status","aliassymbol","prevsymbol",
    "entrezid","refseqaccession"
}
missing=sorted(required_ref-set(cols))
if missing:
    raise RuntimeError(
        f"NCBI_GENE_HGNC_EQUIVALENT_COLUMNS_MISSING={missing}"
    )

symbol_col=cols["symbol"]
status_col=cols["status"]
alias_col=cols["aliassymbol"]
prev_col=cols["prevsymbol"]
entrez_col=cols["entrezid"]
refseq_col=cols["refseqaccession"]
hgncid_col=cols["hgncid"]

status_counts=ref[status_col].astype(str).value_counts().to_dict()
status_text="|".join(sorted(status_counts.keys()))
if (
    "Approved nomenclature authority symbol" not in status_counts
    and "Current NCBI Gene symbol" not in status_counts
):
    raise RuntimeError(
        "REFERENCE_NOT_RECOGNIZED_AS_NCBI_GENE_HGNC_EQUIVALENT "
        f"status_values={list(status_counts)[:20]}"
    )
if len(ref)<30000:
    raise RuntimeError(
        f"NCBI_GENE_HGNC_EQUIVALENT_ROW_COUNT_TOO_SMALL={len(ref)}"
    )

reference_symbol_rows=defaultdict(list)
alias_to_reference=defaultdict(set)
prev_to_reference=defaultdict(set)
entrez_to_reference=defaultdict(set)
refseq_to_reference=defaultdict(set)

for i,r in ref.iterrows():
    sym=str(r[symbol_col]).strip()
    if not sym:
        continue
    reference_symbol_rows[sym].append(i)
    for a in split_multi(r[alias_col]):
        alias_to_reference[a].add(sym)
    for p in split_multi(r[prev_col]):
        prev_to_reference[p].add(sym)
    for e in split_multi(r[entrez_col]):
        entrez_to_reference[e.replace(".0","")].add(sym)
    for accession in split_multi(r[refseq_col]):
        key=strip_version(accession)
        if key.startswith(REFSEQ_PREFIXES):
            refseq_to_reference[key].add(sym)

def resolve_project_symbol(project_symbol):
    s=str(project_symbol).strip()
    if s in reference_symbol_rows:
        return s,"EXACT_REFERENCE_CURRENT_SYMBOL",False
    if s in prev_to_reference:
        vals=sorted(prev_to_reference[s])
        if len(vals)==1:
            return vals[0],"UNIQUE_EXACT_PREVIOUS_SYMBOL",False
        return "","AMBIGUOUS_PREVIOUS_SYMBOL",True
    if s in alias_to_reference:
        vals=sorted(alias_to_reference[s])
        if len(vals)==1:
            return vals[0],"UNIQUE_EXACT_ALIAS_SYMBOL",False
        return "","AMBIGUOUS_ALIAS_SYMBOL",True
    return "","UNMATCHED",False

gene_rows=[]
project_to_reference={}
project_gene_set=set(unique_mrna)

for sym in unique_mrna:
    mapped,route,amb=resolve_project_symbol(sym)
    project_to_reference[sym]=mapped

    if mapped:
        external_status="UNIQUE_EXTERNAL_REFERENCE_BRIDGE"
        alias_bridge="AUTHORIZED_UNIQUE_ONLY"
    elif amb:
        external_status="PROJECT_SYMBOL_ONLY_AMBIGUOUS_EXTERNAL_BRIDGE"
        alias_bridge="PROHIBITED_AMBIGUOUS"
    else:
        external_status="PROJECT_SYMBOL_ONLY_NO_EXTERNAL_REFERENCE_MATCH"
        alias_bridge="NOT_AVAILABLE"

    gene_rows.append({
        "project_mRNA_id":sym,
        "authoritative_project_node_id":sym,
        "reference_current_symbol":mapped,
        "external_mapping_route":route,
        "external_mapping_ambiguity":"YES" if amb else "NO",
        "external_reference_status":external_status,
        "exact_project_symbol_matching":"AUTHORIZED",
        "external_alias_bridge":alias_bridge,
        "project_feature_retained":"YES",
    })

gene_audit=pd.DataFrame(gene_rows)
gene_audit.to_csv(GENE_AUDIT,index=False)

resolved=int(gene_audit["reference_current_symbol"].ne("").sum())
external_unresolved=4467-resolved
ambiguous=int(
    gene_audit["external_mapping_ambiguity"].eq("YES").sum()
)
unmatched=external_unresolved-ambiguous

if unresolved := (resolved + external_unresolved != 4467):
    raise RuntimeError(
        "PROJECT_GENE_ACCOUNTING_INCONSISTENT "
        f"resolved={resolved} external_unresolved={external_unresolved}"
    )
if unmatched < 0:
    raise RuntimeError(
        "PROJECT_GENE_EXTERNAL_MAPPING_COUNTS_INCONSISTENT "
        f"unmatched={unmatched} ambiguous={ambiguous}"
    )

collision_counts=(
    gene_audit.loc[gene_audit["reference_current_symbol"].ne("")]
    .groupby("reference_current_symbol")["project_mRNA_id"]
    .nunique()
)
collisions=int((collision_counts>1).sum())

route_counts=gene_audit["external_mapping_route"].value_counts().to_dict()
coverage_pct=(resolved/4467.0)*100.0

put("GENE_REFERENCE_TYPE","NCBI_GENE_HGNC_EQUIVALENT")
put("GENE_REFERENCE_ROWS",len(ref))
put("GENE_REFERENCE_STATUS_APPROVED_NOMENCLATURE_ROWS",
    int(status_counts.get("Approved nomenclature authority symbol",0)))
put("GENE_REFERENCE_STATUS_CURRENT_NCBI_ROWS",
    int(status_counts.get("Current NCBI Gene symbol",0)))

put("PROJECT_GENE_RESOLUTION_TOTAL",4467)
put("PROJECT_GENE_AUTHORITATIVE_IDS_RETAINED",4467)
put("PROJECT_GENE_EXTERNAL_REFERENCE_RESOLVED",resolved)
put("PROJECT_GENE_EXTERNAL_REFERENCE_UNRESOLVED",external_unresolved)
put("PROJECT_GENE_EXTERNAL_REFERENCE_AMBIGUOUS",ambiguous)
put("PROJECT_GENE_EXTERNAL_REFERENCE_UNMATCHED",unmatched)
put("PROJECT_GENE_EXTERNAL_REFERENCE_COVERAGE_PERCENT",
    f"{coverage_pct:.12f}")
put("PROJECT_GENE_NORMALIZATION_COLLISIONS",collisions)
put("PROJECT_GENE_EXACT_REFERENCE_CURRENT",
    int(route_counts.get("EXACT_REFERENCE_CURRENT_SYMBOL",0)))
put("PROJECT_GENE_UNIQUE_PREVIOUS_SYMBOL",
    int(route_counts.get("UNIQUE_EXACT_PREVIOUS_SYMBOL",0)))
put("PROJECT_GENE_UNIQUE_ALIAS_SYMBOL",
    int(route_counts.get("UNIQUE_EXACT_ALIAS_SYMBOL",0)))

if collisions!=0:
    raise RuntimeError(
        "PROJECT_GENE_EXTERNAL_REFERENCE_COLLISION_REVIEW_REQUIRED "
        f"collisions={collisions} audit={GENE_AUDIT}"
    )

# The frozen project symbol is the authoritative biological/network identity.
# External nomenclature resources are bridges only. Failure to resolve a
# project symbol externally never deletes, renames, or merges that feature.
put("PROJECT_GENE_AUTHORITATIVE_IDENTITY","EXACT_FROZEN_PROJECT_GENE_SYMBOL")
put("EXACT_PROJECT_SYMBOL_MATCHING_PRIORITY","YES")
put("EXTERNAL_REFERENCE_ROLE","UNIQUE_IDENTIFIER_BRIDGE_ONLY")
put("EXTERNAL_REFERENCE_NONRESOLUTION_DELETES_PROJECT_GENE","NO")
put("AMBIGUOUS_EXTERNAL_ALIAS_BRIDGE_AUTHORIZED","NO")
put("PROJECT_GENE_IDENTITY_GATE","PASS")
put("PROJECT_GENE_EXTERNAL_REFERENCE_GATE",
    "PASS_WITH_PROJECT_SYMBOL_FALLBACK")

# Inverse reference-current-symbol -> project feature exists only for unique
# bridge results. Ambiguous/unmatched project symbols deliberately do not
# receive an alias bridge.
reference_to_project={}
for row in gene_rows:
    current=row["reference_current_symbol"]
    project=row["project_mRNA_id"]
    if not current:
        continue
    if current in reference_to_project and reference_to_project[current]!=project:
        raise RuntimeError(
            "REFERENCE_TO_PROJECT_COLLISION "
            f"reference={current} projects="
            f"{reference_to_project[current]}|{project}"
        )
    reference_to_project[current]=project

# ------------------------------------------------------------
# D. miRBase 22.1 exact validation of project mature identities
# ------------------------------------------------------------
mirbase_path=assets["MIRBASE_22_1_MATURE"]
mimat_to_names=defaultdict(set)
name_to_mimats=defaultdict(set)

with open(mirbase_path,"rt",encoding="utf-8",errors="replace") as f:
    for line in f:
        if not line.startswith(">"):
            continue
        mimats=re.findall(r"\bMIMAT\d+\b",line)
        names=re.findall(r"\bhsa-[^\s]+",line)
        for m in mimats:
            for n in names:
                mimat_to_names[m].add(n)
                name_to_mimats[n].add(m)

mir_rows=[]
for ident in unique_mirna_ids:
    mimat,mature=ident.split("|",1)
    exact=(
        mature in mimat_to_names.get(mimat,set())
        and mimat in name_to_mimats.get(mature,set())
    )
    mir_rows.append({
        "project_miRNA_id":ident,
        "MIMAT":mimat,
        "mature_name":mature,
        "exact_miRBase22_1_pair":"YES" if exact else "NO",
        "status":"PASS" if exact else "REVIEW_REQUIRED",
    })

mir_audit=pd.DataFrame(mir_rows)
mir_audit.to_csv(MIRNA_VALIDATION,index=False)
mir_valid=int(mir_audit["exact_miRBase22_1_pair"].eq("YES").sum())
put("MIRBASE22_1_PROJECT_MIRNA_EXACT_VALIDATED",mir_valid)

if mir_valid!=41:
    raise RuntimeError(
        f"MIRBASE22_1_PROJECT_MIRNA_REVIEW_REQUIRED={mir_valid}/41"
    )
put("MIRBASE22_1_PROJECT_MIRNA_GATE","PASS")

# ------------------------------------------------------------
# E. TargetScan Release-8 explicit family metadata
# ------------------------------------------------------------
family_candidates=[]
for base,dirs,files in os.walk(REUSABLE):
    dirs[:]=[
        d for d in dirs
        if d.lower() not in {".git","__pycache__",".ipynb_checkpoints"}
    ]
    for fn in files:
        if fn.lower() in {
            "mir_family_info.txt.zip","mir_family_info.txt",
            "mir_family_info.tsv.zip","mir_family_info.tsv"
        }:
            p=Path(base)/fn
            if p.is_file():
                family_candidates.append(p)

if not family_candidates:
    raise RuntimeError(
        "TARGETSCAN_RELEASE8_MIR_FAMILY_INFO_ASSET_NOT_FOUND"
    )

def fam_score(p):
    s=str(p).replace("\\","/").lower()
    score=0
    if "targetscan" in s: score+=100
    if "vert_80" in s or "8.0" in s or "release8" in s: score+=200
    if p.name.lower()=="mir_family_info.txt.zip": score+=100
    return score

family_candidates=sorted(
    family_candidates,
    key=lambda p:(fam_score(p),p.stat().st_size,str(p).lower()),
    reverse=True,
)
family_path=family_candidates[0]
family_hash=sha256_stream(family_path)

pd.DataFrame([{
    "selected_family_metadata_asset":str(family_path),
    "filename":family_path.name,
    "size_bytes":family_path.stat().st_size,
    "SHA256":family_hash,
    "candidate_count":len(family_candidates),
    "selection_rule":"canonical_miR_Family_Info_prefer_TargetScan_Release8_path",
}]).to_csv(TS_FAMILY_ASSET,index=False)

fam=pd.read_csv(
    family_path,
    sep="\t",
    compression="zip" if str(family_path).lower().endswith(".zip") else None,
    dtype=str,
    keep_default_na=False,
)
fam_cols={norm_col(c):c for c in fam.columns}

family_col=fam_cols.get("mirfamily") or fam_cols.get("mirnafamily") or fam_cols.get("family")
species_col=fam_cols.get("speciesid") or fam_cols.get("genetaxid") or fam_cols.get("taxid")
name_col=fam_cols.get("mirbaseid") or fam_cols.get("mirna") or fam_cols.get("maturemirna")
accession_col=fam_cols.get("mirbaseaccession") or fam_cols.get("mimat")

if family_col is None or species_col is None:
    raise RuntimeError(
        f"TARGETSCAN_FAMILY_METADATA_SCHEMA_UNEXPECTED={list(fam.columns)}"
    )
if name_col is None and accession_col is None:
    raise RuntimeError(
        "TARGETSCAN_FAMILY_METADATA_LACKS_MEMBER_NAME_AND_ACCESSION"
    )

project_name_set=set(unique_mature)
project_mimat_set=set(unique_mimat)
mimat_to_project_name={
    ident.split("|",1)[0]:ident.split("|",1)[1]
    for ident in unique_mirna_ids
}

family_rows=[]
mapped_project=set()

for _,r in fam.loc[
    fam[species_col].astype(str).str.strip().eq("9606")
].iterrows():
    family=str(r[family_col]).strip()
    raw_name=str(r[name_col]).strip() if name_col else ""
    raw_acc=str(r[accession_col]).strip() if accession_col else ""

    project_name=None
    if raw_acc in project_mimat_set:
        project_name=mimat_to_project_name[raw_acc]
        basis="EXPLICIT_RELEASE8_MIRBASE_ACCESSION"
    else:
        canonical=raw_name
        if canonical and not canonical.startswith("hsa-") and (
            canonical.startswith("miR-")
            or canonical.startswith("mir-")
            or canonical.startswith("let-")
        ):
            canonical="hsa-"+canonical
        if canonical in project_name_set:
            project_name=canonical
            basis="EXPLICIT_RELEASE8_MIRBASE_ID"
        else:
            continue

    mapped_project.add(project_name)
    family_rows.append({
        "project_mature_miRNA":project_name,
        "project_MIMAT":next(
            m for m,n in mimat_to_project_name.items()
            if n==project_name
        ),
        "targetscan_family":family,
        "targetscan_miRBase_ID_raw":raw_name,
        "targetscan_miRBase_accession_raw":raw_acc,
        "species_id":"9606",
        "mapping_basis":basis,
    })

family_audit=pd.DataFrame(family_rows)
if family_audit.empty:
    family_audit=pd.DataFrame(columns=[
        "project_mature_miRNA","project_MIMAT","targetscan_family",
        "targetscan_miRBase_ID_raw","targetscan_miRBase_accession_raw",
        "species_id","mapping_basis"
    ])
family_audit.to_csv(TS_FAMILY_AUDIT,index=False)

put("TARGETSCAN_RELEASE8_FAMILY_METADATA_ASSET_FOUND","YES")
put("TARGETSCAN_RELEASE8_FAMILY_METADATA_SHA256",family_hash)
put("TARGETSCAN_PROJECT_MIRNAS_WITH_EXPLICIT_FAMILY_METADATA",
    len(mapped_project))
put("TARGETSCAN_FAMILY_INFERENCE_FROM_NAME_OR_SEED_EXECUTED","NO")

# ------------------------------------------------------------
# F. Correct miRDB native schema: mature miRNA, RefSeq RNA, score
# ------------------------------------------------------------
mirdb_path=assets["MIRDB_V6_HUMAN"]
project_mirna_set=set(unique_mature)

native_counts=defaultdict(int)
native_max_score={}
human_rows=0
project_rows=0
invalid_project_scores=0

with gzip.open(
    mirdb_path,"rt",encoding="utf-8-sig",errors="replace"
) as f:
    for line in f:
        fields=line.rstrip("\r\n").split("\t")
        if len(fields)<3:
            continue
        mirna=fields[0].strip()
        accession=strip_version(fields[1])
        score_raw=fields[2].strip()

        if not mirna.startswith("hsa-"):
            continue
        human_rows+=1
        if mirna not in project_mirna_set:
            continue
        project_rows+=1

        try:
            score=float(score_raw)
        except Exception:
            invalid_project_scores+=1
            continue

        if not accession.startswith(REFSEQ_PREFIXES):
            raise RuntimeError(
                f"MIRDB_PROJECT_ROW_TARGET_NOT_REFSEQ_RNA="
                f"{mirna}|{fields[1]}"
            )
        if not (0.0<=score<=100.0):
            raise RuntimeError(
                f"MIRDB_PROJECT_ROW_SCORE_OUT_OF_RANGE="
                f"{mirna}|{accession}|{score}"
            )

        native_counts[accession]+=1
        old=native_max_score.get(accession,-np.inf)
        if score>old:
            native_max_score[accession]=score

if invalid_project_scores:
    raise RuntimeError(
        f"MIRDB_PROJECT_ROWS_WITH_NONNUMERIC_SCORE={invalid_project_scores}"
    )

needed_refseq=sorted(native_counts)
native_audit=pd.DataFrame([
    {
        "refseq_rna_accession":acc,
        "project_miRNA_record_count":native_counts[acc],
        "maximum_score_across_project_miRNAs":native_max_score[acc],
        "identifier_type":"RefSeq_RNA_transcript_accession",
    }
    for acc in needed_refseq
])
native_audit.to_csv(MIRDB_NATIVE_AUDIT,index=False)

put("MIRDB_NATIVE_SCHEMA",
    "MATURE_MIRNA_REFSEQ_RNA_ACCESSION_SCORE")
put("MIRDB_HUMAN_ROWS",human_rows)
put("MIRDB_PROJECT_MIRNA_ROWS",project_rows)
put("MIRDB_PROJECT_UNIQUE_REFSEQ_ACCESSIONS",len(needed_refseq))
put("MIRDB_COLUMN2_INTERPRETED_AS_ENTREZ","NO")

if project_rows<=0 or len(needed_refseq)<=0:
    raise RuntimeError(
        "MIRDB_PROJECT_MIRNA_NATIVE_ROWS_NOT_FOUND "
        f"project_rows={project_rows} "
        f"needed_refseq={len(needed_refseq)}"
    )

put("MIRDB_NATIVE_REFSEQ_AUDIT_GATE","PASS")

# ------------------------------------------------------------
# G. Acquire/reuse official NCBI human feature table
#    ONLY as miRDB RefSeq target identifier bridge
# ------------------------------------------------------------
feature_path=find_local_feature_table()
source_mode="LOCAL_REUSABLE_OR_PROJECT_REFERENCE"

if feature_path is None:
    feature_path=REFERENCE_CACHE/NCBI_FEATURE_NAME
    download_resume(NCBI_FEATURE_URL,feature_path)
    source_mode="NEW_PROJECT_NCBI_DOWNLOAD"
else:
    put("NCBI_FEATURE_TABLE_DOWNLOAD_ACTION","REUSE_LOCAL_GENERIC_REFERENCE")

if not feature_path.is_file() or feature_path.stat().st_size<=0:
    raise RuntimeError(
        f"NCBI_FEATURE_TABLE_MISSING_AFTER_ACQUISITION={feature_path}"
    )

feature_sha=sha256_stream(feature_path)
feature_cols=validate_feature_table_schema(feature_path)

put("NCBI_GRCH38P14_FEATURE_TABLE_AVAILABLE","YES")
put("NCBI_GRCH38P14_FEATURE_TABLE_SOURCE_MODE",source_mode)
put("NCBI_GRCH38P14_FEATURE_TABLE_SHA256",feature_sha)
put("NCBI_REFSEQ_BRIDGE_ROLE","MIRDB_DATABASE_IDENTIFIER_ONLY")
put("GSE243217_HG19_EXPRESSION_REINTERPRETATION_EXECUTED","NO")

# ------------------------------------------------------------
# H. Build complete RefSeq -> project-gene classification
#    from the official human feature table, with the NCBI-derived
#    HGNC-equivalent refseq field as an additional generic fallback.
# ------------------------------------------------------------
with gzip.open(
    feature_path,"rt",encoding="utf-8-sig",errors="replace",newline=""
) as f:
    reader=csv.reader(f,delimiter="\t")
    raw_header=next(reader)
    cols_norm=[normalize_header(x) for x in raw_header]
    idx={name:i for i,name in enumerate(cols_norm)}

    def first_idx(cands):
        for c in cands:
            if c in idx:
                return idx[c]
        return None

    product_idx=first_idx(["product_accession","product_accession_version"])
    symbol_idx=first_idx(["symbol","gene_symbol"])
    geneid_idx=first_idx(["geneid","gene_id"])
    feature_idx=first_idx(["feature","feature_class"])

    if product_idx is None:
        raise RuntimeError(
            f"NCBI_FEATURE_TABLE_PRODUCT_ACCESSION_MISSING={cols_norm}"
        )

    needed=set(needed_refseq)
    accession_records=defaultdict(list)
    total_rows=0
    rna_rows=0
    needed_rows=0

    for row in reader:
        total_rows+=1
        if len(row)<len(cols_norm):
            row=row+[""]*(len(cols_norm)-len(row))
        accession=strip_version(row[product_idx])
        if not accession.startswith(REFSEQ_PREFIXES):
            continue
        rna_rows+=1
        if accession not in needed:
            continue
        needed_rows+=1
        accession_records[accession].append({
            "symbol":row[symbol_idx].strip() if symbol_idx is not None else "",
            "geneid":row[geneid_idx].strip().replace(".0","")
                if geneid_idx is not None else "",
            "feature":row[feature_idx].strip()
                if feature_idx is not None else "",
        })

bridge_rows=[]
status_counts=defaultdict(int)
project_mapped_accessions=0
outside_project_accessions=0
ambiguous_accessions=0
unresolved_accessions=0
direct_exact_project_accessions=0

for accession in needed_refseq:
    records=accession_records.get(accession,[])
    reference_candidates=set()
    project_candidates=set()
    mapping_routes=set()
    raw_human_symbols=set()
    raw_geneids=set()

    for rec in records:
        raw_symbol=rec["symbol"]
        if raw_symbol:
            raw_human_symbols.add(raw_symbol)

            # Highest-priority route: the project feature symbol itself.
            if raw_symbol in project_gene_set:
                project_candidates.add(raw_symbol)
                mapping_routes.add(
                    "NCBI_FEATURE_TABLE_EXACT_FROZEN_PROJECT_SYMBOL"
                )

            # Secondary bridge: unique external-current/alias/previous symbol.
            mapped,route,amb=resolve_project_symbol(raw_symbol)
            if raw_symbol in reference_symbol_rows:
                reference_candidates.add(raw_symbol)
                mapping_routes.add("NCBI_FEATURE_TABLE_CURRENT_SYMBOL")
            elif mapped:
                reference_candidates.add(mapped)
                mapping_routes.add(
                    "NCBI_FEATURE_TABLE_UNIQUE_SYMBOL_BRIDGE"
                )

            if mapped and mapped in reference_to_project:
                project_candidates.add(reference_to_project[mapped])
                mapping_routes.add(
                    "NCBI_FEATURE_TABLE_SYMBOL_TO_UNIQUE_PROJECT_BRIDGE"
                )

        geneid=rec["geneid"]
        if geneid:
            raw_geneids.add(geneid)
            vals=entrez_to_reference.get(geneid,set())
            for v in vals:
                reference_candidates.add(v)
                mapping_routes.add(
                    "NCBI_FEATURE_TABLE_GENEID_TO_REFERENCE"
                )
                if v in reference_to_project:
                    project_candidates.add(reference_to_project[v])
                    mapping_routes.add(
                        "NCBI_FEATURE_TABLE_GENEID_TO_UNIQUE_PROJECT_BRIDGE"
                    )

    # Generic fallback from the preserved NCBI Gene-derived reference.
    if accession in refseq_to_reference:
        for v in refseq_to_reference[accession]:
            reference_candidates.add(v)
            mapping_routes.add(
                "NCBI_GENE_EQUIVALENT_REFSEQ_FALLBACK"
            )
            if v in reference_to_project:
                project_candidates.add(reference_to_project[v])
                mapping_routes.add(
                    "NCBI_GENE_REFSEQ_TO_UNIQUE_PROJECT_BRIDGE"
                )

    if len(project_candidates)==1:
        status="UNIQUE_PROJECT_GENE"
        mapped_project=next(iter(project_candidates))
        project_mapped_accessions+=1
        if (
            "NCBI_FEATURE_TABLE_EXACT_FROZEN_PROJECT_SYMBOL"
            in mapping_routes
        ):
            direct_exact_project_accessions+=1
    elif len(project_candidates)>1:
        status="AMBIGUOUS_MULTIPLE_PROJECT_GENES_NO_SUPPORT"
        mapped_project=""
        ambiguous_accessions+=1
    elif reference_candidates or raw_human_symbols or raw_geneids:
        status="RESOLVED_OUTSIDE_PROJECT_GENE_UNIVERSE_NO_SUPPORT"
        mapped_project=""
        outside_project_accessions+=1
    else:
        status="UNRESOLVED_REFSEQ_ACCESSION_NO_SUPPORT"
        mapped_project=""
        unresolved_accessions+=1

    status_counts[status]+=1

    bridge_rows.append({
        "refseq_rna_accession":accession,
        "project_miRNA_record_count":native_counts[accession],
        "maximum_miRDB_score_across_project_miRNAs":
            native_max_score[accession],
        "feature_table_record_count":len(records),
        "feature_table_raw_symbols":"|".join(
            sorted(raw_human_symbols)
        ),
        "feature_table_raw_geneids":"|".join(
            sorted(raw_geneids)
        ),
        "reference_candidate_symbols":"|".join(
            sorted(reference_candidates)
        ),
        "project_gene_candidates":"|".join(
            sorted(project_candidates)
        ),
        "mapped_project_gene_symbol":mapped_project,
        "mapping_routes":"|".join(sorted(mapping_routes)),
        "mapping_status":status,
        "mapping_ambiguity":"YES"
            if status=="AMBIGUOUS_MULTIPLE_PROJECT_GENES_NO_SUPPORT"
            else "NO",
        "eligible_to_support_miRDB_route":
            "YES" if status=="UNIQUE_PROJECT_GENE" else "NO",
        "nonunique_or_unresolved_policy":
            "NO_SUPPORT_NO_GUESSING",
    })

bridge=pd.DataFrame(bridge_rows)
bridge.to_csv(
    REFSEQ_BRIDGE,
    index=False,
    compression="gzip",
)

pd.DataFrame([{
    "reference_role":"miRDB RefSeq RNA identifier bridge only",
    "source_mode":source_mode,
    "source_url":NCBI_FEATURE_URL,
    "feature_table_path":str(feature_path),
    "feature_table_size_bytes":feature_path.stat().st_size,
    "feature_table_SHA256":feature_sha,
    "feature_table_columns":"|".join(feature_cols),
    "feature_table_total_rows":total_rows,
    "feature_table_RNA_product_rows":rna_rows,
    "feature_table_rows_for_needed_miRDB_accessions":needed_rows,
    "needed_unique_miRDB_refseq_accessions":len(needed_refseq),
    "unique_project_gene_mapped_accessions":project_mapped_accessions,
    "direct_exact_project_symbol_accessions":
        direct_exact_project_accessions,
    "resolved_outside_project_accessions":outside_project_accessions,
    "ambiguous_accessions_no_support":ambiguous_accessions,
    "unresolved_accessions_no_support":unresolved_accessions,
    "ambiguous_or_unresolved_support_policy":
        "NO_SUPPORT_NO_GUESSING",
    "expression_reference_reinterpretation":"NO",
}]).to_csv(REFSEQ_REFERENCE_AUDIT,index=False)

put("REFSEQ_BRIDGE_NEEDED_ACCESSIONS",len(needed_refseq))
put("REFSEQ_BRIDGE_UNIQUE_PROJECT_GENE_MAPPED",
    project_mapped_accessions)
put("REFSEQ_BRIDGE_DIRECT_EXACT_PROJECT_SYMBOL",
    direct_exact_project_accessions)
put("REFSEQ_BRIDGE_RESOLVED_OUTSIDE_PROJECT",
    outside_project_accessions)
put("REFSEQ_BRIDGE_AMBIGUOUS_NO_SUPPORT",ambiguous_accessions)
put("REFSEQ_BRIDGE_UNRESOLVED_NO_SUPPORT",unresolved_accessions)
put("MIRDB_REFSEQ_NONUNIQUE_OR_UNRESOLVED_POLICY",
    "NO_SUPPORT_NO_GUESSING")

# A nonzero ambiguous/unresolved count is not a false-positive risk because
# those accessions are explicitly ineligible to support Route B. However,
# zero uniquely mappable project accessions would indicate an unusable bridge.
if project_mapped_accessions<=0:
    raise RuntimeError(
        "MIRDB_REFSEQ_BRIDGE_HAS_ZERO_PROJECT_GENE_RECOVERY "
        f"needed={len(needed_refseq)} bridge={REFSEQ_BRIDGE}"
    )

put("MIRDB_REFSEQ_BRIDGE_GATE",
    "PASS_WITH_CONSERVATIVE_NON_SUPPORT")

# ------------------------------------------------------------
# I. Corrected integration specification — still no edge matching
# ------------------------------------------------------------
spec=[
    "GSE243219_D8A_V3_CORRECTED_IDENTIFIER_INTEGRATION_SPECIFICATION",
    "FROZEN_D8_EVIDENCE_RULE_CHANGED=NO",
    "FROZEN_STABLE_ASSOCIATION_EDGES=11531",
    "PROJECT_MRNA_FEATURE_IDENTITY=GENE_SYMBOL",
    "PROJECT_MRNA_AUTHORITATIVE_NODE_ID=EXACT_FROZEN_PROJECT_GENE_SYMBOL",
    "DATABASE_GENE_MATCH_PRIORITY_1=EXACT_DATABASE_SYMBOL_TO_EXACT_PROJECT_SYMBOL",
    "DATABASE_GENE_MATCH_PRIORITY_2=UNIQUE_EXTERNAL_REFERENCE_BRIDGE",
    "EXTERNAL_REFERENCE_TYPE=NCBI_GENE_HGNC_EQUIVALENT",
    "EXTERNAL_REFERENCE_ROLE=UNIQUE_IDENTIFIER_BRIDGE_ONLY",
    "EXTERNAL_REFERENCE_LITERAL_STATUS_APPROVED_FILTER=PROHIBITED",
    "EXTERNAL_REFERENCE_NONRESOLUTION_DELETES_PROJECT_FEATURE=NO",
    "AMBIGUOUS_EXTERNAL_ALIAS_OR_PREVIOUS_SYMBOL_BRIDGE=NO_SUPPORT",
    "CASE_INSENSITIVE_GENE_SYMBOL_GUESSING=PROHIBITED",
    "PROJECT_MIRNA_IDENTITY=MIMAT|mature-miRNA",
    "MIRBASE_IDENTIFIER_BRIDGE_VERSION=22.1",
    "TARGETSCAN_PRIMARY_MIRNA_MATCH=DIRECT_RELEASE8_MATURE_MIRNA_COLUMN_WHEN_PRESENT",
    "TARGETSCAN_FAMILY_MAPPING=EXPLICIT_RELEASE8_METADATA_ONLY",
    "TARGETSCAN_FAMILY_INFERENCE_FROM_NAME_OR_SEED=PROHIBITED",
    "MIRDB_NATIVE_FORMAT=MATURE_MIRNA|REFSEQ_RNA_ACCESSION|SCORE",
    "MIRDB_COLUMN2_IS_ENTREZ=NO",
    "MIRDB_HIGH_CONFIDENCE_RULE=SCORE_GT_80",
    "MIRDB_REFSEQ_BRIDGE_SOURCE=OFFICIAL_NCBI_GRCH38P14_HUMAN_FEATURE_TABLE_PLUS_NCBI_GENE_EQUIVALENT_FALLBACK",
    "MIRDB_REFSEQ_BRIDGE_ROLE=TARGET_DATABASE_IDENTIFIER_ONLY",
    "MIRDB_AMBIGUOUS_OR_UNRESOLVED_REFSEQ_POLICY=NO_SUPPORT_NO_GUESSING",
    "GSE243217_HG19_EXPRESSION_REINTERPRETATION=NO",
    "OLD_DATASET_SPECIFIC_REFSEQ_TO_NETWORK_MAPPING_REUSED=NO",
    "ROUTE_A=STABLE_ASSOCIATION_AND_TARBASE_V9",
    "ROUTE_B=STABLE_ASSOCIATION_AND_TARGETSCAN8_DEFAULT_AND_MIRDB6_SCORE_GT_80",
    "SINGLE_PREDICTOR_ONLY_ELIGIBLE=NO",
    "CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO",
    "TARGET_DATABASE_EDGE_MATCHING_EXECUTED_IN_D8A_V3=NO",
    "TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED_IN_D8A_V3=NO",
    "REGULATORY_EDGE_CLASSIFICATION_EXECUTED_IN_D8A_V3=NO",
    "NETWORK_EXECUTED_IN_D8A_V3=NO",
    "ACLA_EXECUTED_IN_D8A_V3=NO",
]
CORRECTED_SPEC.write_text("\n".join(spec)+"\n",encoding="utf-8")

put("CORRECTED_IDENTIFIER_INTEGRATION_SPECIFICATION_FROZEN","YES")
put("FROZEN_D8_EVIDENCE_RULE_CHANGED","NO")
put("DATABASE_GENE_MATCH_PRIORITY_1","EXACT_PROJECT_SYMBOL")
put("DATABASE_GENE_MATCH_PRIORITY_2","UNIQUE_EXTERNAL_BRIDGE")
put("EXTERNAL_NONRESOLUTION_DELETES_PROJECT_FEATURE","NO")
put("OLD_DATASET_SPECIFIC_REFSEQ_MAPPING_REUSED","NO")
put("TARGET_DATABASE_EDGE_MATCHING_EXECUTED","NO")
put("TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED","NO")
put("REGULATORY_EDGE_CLASSIFICATION_EXECUTED","NO")
put("NETWORK_EXECUTED","NO")
put("ACLA_EXECUTED","NO")
put("READY_FOR_D8A1_TARGET_EVIDENCE_INTEGRATION","YES")
put("NEXT_PHASE",
    "D8A1_TARGET_EVIDENCE_INTEGRATION_AND_REGULATORY_EDGE_CLASSIFICATION")

RESULT_JSON.write_text(
    json.dumps(
        {
            "results":results,
            "selected_assets":{k:str(v) for k,v in assets.items()},
            "targetscan_family_asset":str(family_path),
            "ncbi_refseq_feature_table":str(feature_path),
        },
        indent=2,
        sort_keys=True,
    ),
    encoding="utf-8",
)
'@

$PythonCode | Set-Content -LiteralPath $PyScript -Encoding UTF8
$env:PYTHONUTF8='1'
$env:PYTHONIOENCODING='utf-8'

$PythonArgs=@(
    '-u',$PyScript,
    $Reusable,
    $StableEdges,
    $D8AssetInventory,
    $D8FrozenStrategy,
    $ReferenceCache,
    $GeneAudit,
    $MiRNAValidation,
    $TargetScanFamilyAudit,
    $TargetScanFamilyAsset,
    $MiRDBNativeAudit,
    $RefSeqBridge,
    $RefSeqReferenceAudit,
    $CorrectedSpec,
    $ResultJson
)

$proc=Start-Process `
    -FilePath $PythonExe `
    -ArgumentList $PythonArgs `
    -Wait `
    -PassThru `
    -NoNewWindow `
    -RedirectStandardOutput $PythonStdout `
    -RedirectStandardError $PythonStderr

$PythonExit=[int]$proc.ExitCode
$stdoutLines=@()
$stderrLines=@()

if(Test-Path -LiteralPath $PythonStdout -PathType Leaf){
    $stdoutLines=@(Get-Content -LiteralPath $PythonStdout)
    foreach($line in $stdoutLines){Write-Host $line}
}
if(Test-Path -LiteralPath $PythonStderr -PathType Leaf){
    $stderrLines=@(Get-Content -LiteralPath $PythonStderr)
    if($stderrLines.Count -gt 0){
        Write-Host '=== D8A-V3 PYTHON STDERR ==='
        foreach($line in $stderrLines){Write-Host $line}
    }
}

@(
    '=== STDOUT ===',
    $stdoutLines,
    '',
    '=== STDERR ===',
    $stderrLines
) | Set-Content -LiteralPath $PythonLog -Encoding UTF8

if($PythonExit -ne 0){
    throw ('D8A_V3_PYTHON_FAILED exit={0} full_traceback={1}' -f `
        $PythonExit,$PythonStderr)
}

if(-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)){
    throw 'D8A_V3_RESULT_JSON_MISSING'
}

$result=Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json
function Cap { param([string]$Key) return [string]$result.results.$Key }

foreach($pair in @(
    @('D8_SELECTED_REUSABLE_ASSETS_RECERTIFIED','PASS'),
    @('FROZEN_STABLE_EDGE_IDENTIFIER_INPUT_RECERTIFIED','PASS'),
    @('GENE_REFERENCE_TYPE','NCBI_GENE_HGNC_EQUIVALENT'),
    @('PROJECT_GENE_RESOLUTION_TOTAL','4467'),
    @('PROJECT_GENE_AUTHORITATIVE_IDS_RETAINED','4467'),
    @('PROJECT_GENE_NORMALIZATION_COLLISIONS','0'),
    @('PROJECT_GENE_AUTHORITATIVE_IDENTITY','EXACT_FROZEN_PROJECT_GENE_SYMBOL'),
    @('EXACT_PROJECT_SYMBOL_MATCHING_PRIORITY','YES'),
    @('EXTERNAL_REFERENCE_ROLE','UNIQUE_IDENTIFIER_BRIDGE_ONLY'),
    @('EXTERNAL_REFERENCE_NONRESOLUTION_DELETES_PROJECT_GENE','NO'),
    @('AMBIGUOUS_EXTERNAL_ALIAS_BRIDGE_AUTHORIZED','NO'),
    @('PROJECT_GENE_IDENTITY_GATE','PASS'),
    @('PROJECT_GENE_EXTERNAL_REFERENCE_GATE','PASS_WITH_PROJECT_SYMBOL_FALLBACK'),
    @('MIRBASE22_1_PROJECT_MIRNA_EXACT_VALIDATED','41'),
    @('MIRBASE22_1_PROJECT_MIRNA_GATE','PASS'),
    @('TARGETSCAN_RELEASE8_FAMILY_METADATA_ASSET_FOUND','YES'),
    @('TARGETSCAN_FAMILY_INFERENCE_FROM_NAME_OR_SEED_EXECUTED','NO'),
    @('MIRDB_NATIVE_SCHEMA','MATURE_MIRNA_REFSEQ_RNA_ACCESSION_SCORE'),
    @('MIRDB_COLUMN2_INTERPRETED_AS_ENTREZ','NO'),
    @('MIRDB_NATIVE_REFSEQ_AUDIT_GATE','PASS'),
    @('NCBI_GRCH38P14_FEATURE_TABLE_AVAILABLE','YES'),
    @('NCBI_REFSEQ_BRIDGE_ROLE','MIRDB_DATABASE_IDENTIFIER_ONLY'),
    @('GSE243217_HG19_EXPRESSION_REINTERPRETATION_EXECUTED','NO'),
    @('MIRDB_REFSEQ_NONUNIQUE_OR_UNRESOLVED_POLICY','NO_SUPPORT_NO_GUESSING'),
    @('MIRDB_REFSEQ_BRIDGE_GATE','PASS_WITH_CONSERVATIVE_NON_SUPPORT'),
    @('CORRECTED_IDENTIFIER_INTEGRATION_SPECIFICATION_FROZEN','YES'),
    @('FROZEN_D8_EVIDENCE_RULE_CHANGED','NO'),
    @('DATABASE_GENE_MATCH_PRIORITY_1','EXACT_PROJECT_SYMBOL'),
    @('DATABASE_GENE_MATCH_PRIORITY_2','UNIQUE_EXTERNAL_BRIDGE'),
    @('EXTERNAL_NONRESOLUTION_DELETES_PROJECT_FEATURE','NO'),
    @('OLD_DATASET_SPECIFIC_REFSEQ_MAPPING_REUSED','NO'),
    @('TARGET_DATABASE_EDGE_MATCHING_EXECUTED','NO'),
    @('TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED','NO'),
    @('REGULATORY_EDGE_CLASSIFICATION_EXECUTED','NO'),
    @('NETWORK_EXECUTED','NO'),
    @('ACLA_EXECUTED','NO'),
    @('READY_FOR_D8A1_TARGET_EVIDENCE_INTEGRATION','YES'),
    @('NEXT_PHASE','D8A1_TARGET_EVIDENCE_INTEGRATION_AND_REGULATORY_EDGE_CLASSIFICATION')
)){
    $observed=Cap $pair[0]
    if($observed -ne $pair[1]){
        throw ('D8A_V3_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

@(
    'GSE243219_D8A_V3_DECISION',
    'PHASE_D8A_V3_STATUS=PASS',
    'MODE=CORRECTIVE_AUTHORITATIVE_ID_AND_BRIDGE_PREFLIGHT_ONLY',
    'D7C_CERTIFICATION_GATE=PASS',
    'D7C_OUTPUTS_RECERTIFIED=11/11',
    'D8_V6_CERTIFICATION_GATE=PASS',
    'D8_V6_OUTPUTS_RECERTIFIED=10/10',
    'D8A_V1_FAILURE_CAUSE=HGNC_LITERAL_APPROVED_STATUS_FILTER_INCOMPATIBLE_WITH_NCBI_GENE_DERIVED_HGNC_EQUIVALENT_REFERENCE',
    'D8A_V2_FAILURE_CAUSE=EXTERNAL_REFERENCE_MAPPING_WAS_INCORRECTLY_USED_AS_PROJECT_FEATURE_ADMISSION_GATE',
    'GENE_REFERENCE_TYPE=NCBI_GENE_HGNC_EQUIVALENT',
    ('GENE_REFERENCE_ROWS={0}' -f (Cap 'GENE_REFERENCE_ROWS')),
    'PROJECT_GENE_RESOLUTION_TOTAL=4467',
    'PROJECT_GENE_AUTHORITATIVE_IDS_RETAINED=4467',
    ('PROJECT_GENE_EXTERNAL_REFERENCE_RESOLVED={0}' -f `
        (Cap 'PROJECT_GENE_EXTERNAL_REFERENCE_RESOLVED')),
    ('PROJECT_GENE_EXTERNAL_REFERENCE_UNRESOLVED={0}' -f `
        (Cap 'PROJECT_GENE_EXTERNAL_REFERENCE_UNRESOLVED')),
    ('PROJECT_GENE_EXTERNAL_REFERENCE_AMBIGUOUS={0}' -f `
        (Cap 'PROJECT_GENE_EXTERNAL_REFERENCE_AMBIGUOUS')),
    ('PROJECT_GENE_EXTERNAL_REFERENCE_UNMATCHED={0}' -f `
        (Cap 'PROJECT_GENE_EXTERNAL_REFERENCE_UNMATCHED')),
    ('PROJECT_GENE_EXTERNAL_REFERENCE_COVERAGE_PERCENT={0}' -f `
        (Cap 'PROJECT_GENE_EXTERNAL_REFERENCE_COVERAGE_PERCENT')),
    'PROJECT_GENE_NORMALIZATION_COLLISIONS=0',
    'PROJECT_GENE_AUTHORITATIVE_IDENTITY=EXACT_FROZEN_PROJECT_GENE_SYMBOL',
    'EXACT_PROJECT_SYMBOL_MATCHING_PRIORITY=YES',
    'EXTERNAL_REFERENCE_ROLE=UNIQUE_IDENTIFIER_BRIDGE_ONLY',
    'EXTERNAL_REFERENCE_NONRESOLUTION_DELETES_PROJECT_GENE=NO',
    'AMBIGUOUS_EXTERNAL_ALIAS_BRIDGE_AUTHORIZED=NO',
    'PROJECT_GENE_IDENTITY_GATE=PASS',
    'PROJECT_GENE_EXTERNAL_REFERENCE_GATE=PASS_WITH_PROJECT_SYMBOL_FALLBACK',
    'MIRBASE22_1_PROJECT_MIRNA_EXACT_VALIDATED=41',
    'MIRBASE22_1_PROJECT_MIRNA_GATE=PASS',
    'TARGETSCAN_RELEASE8_FAMILY_METADATA_ASSET_FOUND=YES',
    ('TARGETSCAN_PROJECT_MIRNAS_WITH_EXPLICIT_FAMILY_METADATA={0}' -f `
        (Cap 'TARGETSCAN_PROJECT_MIRNAS_WITH_EXPLICIT_FAMILY_METADATA')),
    'TARGETSCAN_FAMILY_INFERENCE_FROM_NAME_OR_SEED_EXECUTED=NO',
    'MIRDB_NATIVE_SCHEMA=MATURE_MIRNA_REFSEQ_RNA_ACCESSION_SCORE',
    ('MIRDB_HUMAN_ROWS={0}' -f (Cap 'MIRDB_HUMAN_ROWS')),
    ('MIRDB_PROJECT_MIRNA_ROWS={0}' -f (Cap 'MIRDB_PROJECT_MIRNA_ROWS')),
    ('MIRDB_PROJECT_UNIQUE_REFSEQ_ACCESSIONS={0}' -f `
        (Cap 'MIRDB_PROJECT_UNIQUE_REFSEQ_ACCESSIONS')),
    'MIRDB_COLUMN2_INTERPRETED_AS_ENTREZ=NO',
    'MIRDB_NATIVE_REFSEQ_AUDIT_GATE=PASS',
    'NCBI_GRCH38P14_FEATURE_TABLE_AVAILABLE=YES',
    ('NCBI_GRCH38P14_FEATURE_TABLE_SOURCE_MODE={0}' -f `
        (Cap 'NCBI_GRCH38P14_FEATURE_TABLE_SOURCE_MODE')),
    ('NCBI_GRCH38P14_FEATURE_TABLE_SHA256={0}' -f `
        (Cap 'NCBI_GRCH38P14_FEATURE_TABLE_SHA256')),
    'NCBI_REFSEQ_BRIDGE_ROLE=MIRDB_DATABASE_IDENTIFIER_ONLY',
    'GSE243217_HG19_EXPRESSION_REINTERPRETATION_EXECUTED=NO',
    ('REFSEQ_BRIDGE_NEEDED_ACCESSIONS={0}' -f `
        (Cap 'REFSEQ_BRIDGE_NEEDED_ACCESSIONS')),
    ('REFSEQ_BRIDGE_UNIQUE_PROJECT_GENE_MAPPED={0}' -f `
        (Cap 'REFSEQ_BRIDGE_UNIQUE_PROJECT_GENE_MAPPED')),
    ('REFSEQ_BRIDGE_DIRECT_EXACT_PROJECT_SYMBOL={0}' -f `
        (Cap 'REFSEQ_BRIDGE_DIRECT_EXACT_PROJECT_SYMBOL')),
    ('REFSEQ_BRIDGE_RESOLVED_OUTSIDE_PROJECT={0}' -f `
        (Cap 'REFSEQ_BRIDGE_RESOLVED_OUTSIDE_PROJECT')),
    ('REFSEQ_BRIDGE_AMBIGUOUS_NO_SUPPORT={0}' -f `
        (Cap 'REFSEQ_BRIDGE_AMBIGUOUS_NO_SUPPORT')),
    ('REFSEQ_BRIDGE_UNRESOLVED_NO_SUPPORT={0}' -f `
        (Cap 'REFSEQ_BRIDGE_UNRESOLVED_NO_SUPPORT')),
    'MIRDB_REFSEQ_NONUNIQUE_OR_UNRESOLVED_POLICY=NO_SUPPORT_NO_GUESSING',
    'MIRDB_REFSEQ_BRIDGE_GATE=PASS_WITH_CONSERVATIVE_NON_SUPPORT',
    'FROZEN_D8_EVIDENCE_RULE_CHANGED=NO',
    'MIRDB_HIGH_CONFIDENCE_RULE=SCORE_GT_80',
    'DATABASE_GENE_MATCH_PRIORITY_1=EXACT_PROJECT_SYMBOL',
    'DATABASE_GENE_MATCH_PRIORITY_2=UNIQUE_EXTERNAL_BRIDGE',
    'OLD_DATASET_SPECIFIC_REFSEQ_MAPPING_REUSED=NO',
    'TARGET_DATABASE_EDGE_MATCHING_EXECUTED=NO',
    'TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED=NO',
    'REGULATORY_EDGE_CLASSIFICATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D8A1_TARGET_EVIDENCE_INTEGRATION=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D8A1_TARGET_EVIDENCE_INTEGRATION_AND_REGULATORY_EDGE_CLASSIFICATION',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

$outFiles=@(
    $PyScript,
    $GeneAudit,
    $MiRNAValidation,
    $TargetScanFamilyAudit,
    $TargetScanFamilyAsset,
    $MiRDBNativeAudit,
    $RefSeqBridge,
    $RefSeqReferenceAudit,
    $CorrectedSpec,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest=New-Object 'System.Collections.Generic.List[object]'
foreach($p in $outFiles){
    if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
        throw ('D8A_V3_OUTPUT_MISSING={0}' -f $p)
    }
    $item=Get-Item -LiteralPath $p
    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D8AV2SHA256 $item.FullName)
    })
}
$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

@(
    '=== GSE243219 PHASE D8A-V3 SUMMARY ===',
    'PHASE_D8A_V3_STATUS=PASS',
    'MODE=CORRECTIVE_AUTHORITATIVE_ID_AND_BRIDGE_PREFLIGHT_ONLY',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    'D7C_OUTPUTS_RECERTIFIED=11/11',
    'D7C_CERTIFICATION_GATE=PASS',
    'D8_V6_OUTPUTS_RECERTIFIED=10/10',
    'D8_V6_CERTIFICATION_GATE=PASS',
    'D8A_V2_FAILURE_CAUSE=EXTERNAL_REFERENCE_MAPPING_WAS_INCORRECTLY_USED_AS_PROJECT_FEATURE_ADMISSION_GATE',
    'PROJECT_GENE_RESOLUTION_TOTAL=4467',
    'PROJECT_GENE_AUTHORITATIVE_IDS_RETAINED=4467',
    ('PROJECT_GENE_EXTERNAL_REFERENCE_RESOLVED={0}' -f `
        (Cap 'PROJECT_GENE_EXTERNAL_REFERENCE_RESOLVED')),
    ('PROJECT_GENE_EXTERNAL_REFERENCE_UNRESOLVED={0}' -f `
        (Cap 'PROJECT_GENE_EXTERNAL_REFERENCE_UNRESOLVED')),
    ('PROJECT_GENE_EXTERNAL_REFERENCE_AMBIGUOUS={0}' -f `
        (Cap 'PROJECT_GENE_EXTERNAL_REFERENCE_AMBIGUOUS')),
    ('PROJECT_GENE_EXTERNAL_REFERENCE_UNMATCHED={0}' -f `
        (Cap 'PROJECT_GENE_EXTERNAL_REFERENCE_UNMATCHED')),
    ('PROJECT_GENE_EXTERNAL_REFERENCE_COVERAGE_PERCENT={0}' -f `
        (Cap 'PROJECT_GENE_EXTERNAL_REFERENCE_COVERAGE_PERCENT')),
    'PROJECT_GENE_NORMALIZATION_COLLISIONS=0',
    'PROJECT_GENE_AUTHORITATIVE_IDENTITY=EXACT_FROZEN_PROJECT_GENE_SYMBOL',
    'EXACT_PROJECT_SYMBOL_MATCHING_PRIORITY=YES',
    'EXTERNAL_REFERENCE_NONRESOLUTION_DELETES_PROJECT_GENE=NO',
    'AMBIGUOUS_EXTERNAL_ALIAS_BRIDGE_AUTHORIZED=NO',
    'PROJECT_GENE_IDENTITY_GATE=PASS',
    'PROJECT_GENE_EXTERNAL_REFERENCE_GATE=PASS_WITH_PROJECT_SYMBOL_FALLBACK',
    'MIRBASE22_1_PROJECT_MIRNA_EXACT_VALIDATED=41',
    'MIRBASE22_1_PROJECT_MIRNA_GATE=PASS',
    'TARGETSCAN_RELEASE8_FAMILY_METADATA_ASSET_FOUND=YES',
    ('TARGETSCAN_PROJECT_MIRNAS_WITH_EXPLICIT_FAMILY_METADATA={0}' -f `
        (Cap 'TARGETSCAN_PROJECT_MIRNAS_WITH_EXPLICIT_FAMILY_METADATA')),
    'TARGETSCAN_FAMILY_INFERENCE_FROM_NAME_OR_SEED_EXECUTED=NO',
    'MIRDB_NATIVE_SCHEMA=MATURE_MIRNA_REFSEQ_RNA_ACCESSION_SCORE',
    ('MIRDB_HUMAN_ROWS={0}' -f (Cap 'MIRDB_HUMAN_ROWS')),
    ('MIRDB_PROJECT_MIRNA_ROWS={0}' -f (Cap 'MIRDB_PROJECT_MIRNA_ROWS')),
    ('MIRDB_PROJECT_UNIQUE_REFSEQ_ACCESSIONS={0}' -f `
        (Cap 'MIRDB_PROJECT_UNIQUE_REFSEQ_ACCESSIONS')),
    'MIRDB_COLUMN2_INTERPRETED_AS_ENTREZ=NO',
    'MIRDB_NATIVE_REFSEQ_AUDIT_GATE=PASS',
    'NCBI_GRCH38P14_FEATURE_TABLE_AVAILABLE=YES',
    ('NCBI_GRCH38P14_FEATURE_TABLE_SOURCE_MODE={0}' -f `
        (Cap 'NCBI_GRCH38P14_FEATURE_TABLE_SOURCE_MODE')),
    ('NCBI_GRCH38P14_FEATURE_TABLE_SHA256={0}' -f `
        (Cap 'NCBI_GRCH38P14_FEATURE_TABLE_SHA256')),
    'NCBI_REFSEQ_BRIDGE_ROLE=MIRDB_DATABASE_IDENTIFIER_ONLY',
    'GSE243217_HG19_EXPRESSION_REINTERPRETATION_EXECUTED=NO',
    ('REFSEQ_BRIDGE_NEEDED_ACCESSIONS={0}' -f `
        (Cap 'REFSEQ_BRIDGE_NEEDED_ACCESSIONS')),
    ('REFSEQ_BRIDGE_UNIQUE_PROJECT_GENE_MAPPED={0}' -f `
        (Cap 'REFSEQ_BRIDGE_UNIQUE_PROJECT_GENE_MAPPED')),
    ('REFSEQ_BRIDGE_DIRECT_EXACT_PROJECT_SYMBOL={0}' -f `
        (Cap 'REFSEQ_BRIDGE_DIRECT_EXACT_PROJECT_SYMBOL')),
    ('REFSEQ_BRIDGE_RESOLVED_OUTSIDE_PROJECT={0}' -f `
        (Cap 'REFSEQ_BRIDGE_RESOLVED_OUTSIDE_PROJECT')),
    ('REFSEQ_BRIDGE_AMBIGUOUS_NO_SUPPORT={0}' -f `
        (Cap 'REFSEQ_BRIDGE_AMBIGUOUS_NO_SUPPORT')),
    ('REFSEQ_BRIDGE_UNRESOLVED_NO_SUPPORT={0}' -f `
        (Cap 'REFSEQ_BRIDGE_UNRESOLVED_NO_SUPPORT')),
    'MIRDB_REFSEQ_NONUNIQUE_OR_UNRESOLVED_POLICY=NO_SUPPORT_NO_GUESSING',
    'MIRDB_REFSEQ_BRIDGE_GATE=PASS_WITH_CONSERVATIVE_NON_SUPPORT',
    'CORRECTED_IDENTIFIER_INTEGRATION_SPECIFICATION_FROZEN=YES',
    'FROZEN_D8_EVIDENCE_RULE_CHANGED=NO',
    'MIRDB_HIGH_CONFIDENCE_RULE=SCORE_GT_80',
    'DATABASE_GENE_MATCH_PRIORITY_1=EXACT_PROJECT_SYMBOL',
    'DATABASE_GENE_MATCH_PRIORITY_2=UNIQUE_EXTERNAL_BRIDGE',
    'OLD_DATASET_SPECIFIC_REFSEQ_MAPPING_REUSED=NO',
    'TARGET_DATABASE_EDGE_MATCHING_EXECUTED=NO',
    'TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED=NO',
    'REGULATORY_EDGE_CLASSIFICATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D8A1_TARGET_EVIDENCE_INTEGRATION=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D8A1_TARGET_EVIDENCE_INTEGRATION_AND_REGULATORY_EDGE_CLASSIFICATION',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D8A_V3_GENE_AUDIT={0}' -f $GeneAudit)
Write-Host ('D8A_V3_MIRBASE_AUDIT={0}' -f $MiRNAValidation)
Write-Host ('D8A_V3_TARGETSCAN_FAMILY_AUDIT={0}' -f $TargetScanFamilyAudit)
Write-Host ('D8A_V3_MIRDB_NATIVE_AUDIT={0}' -f $MiRDBNativeAudit)
Write-Host ('D8A_V3_REFSEQ_BRIDGE={0}' -f $RefSeqBridge)
Write-Host ('D8A_V3_REFSEQ_REFERENCE_AUDIT={0}' -f $RefSeqReferenceAudit)
Write-Host ('D8A_V3_CORRECTED_SPEC={0}' -f $CorrectedSpec)
Write-Host ('D8A_V3_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D8A_V3_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D8A_V3=PASS'
Write-Host 'STOP=YES'
