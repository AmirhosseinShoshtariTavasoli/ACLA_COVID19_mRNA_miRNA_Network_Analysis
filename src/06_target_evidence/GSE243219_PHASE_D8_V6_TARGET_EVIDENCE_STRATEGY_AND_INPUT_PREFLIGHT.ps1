$ErrorActionPreference = 'Stop'

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$Reusable = Join-Path $Parent '00_REUSABLE_ASSETS'
$D6Root = Join-Path $Project '06_ASSOCIATION_AND_STABILITY'
$D8Root = Join-Path $Project '07_TARGET_EVIDENCE'

$D7CRun = Join-Path $D6Root 'D7C_ASSOCIATION_STABILITY_AUDIT_EDGE_FREEZE_20260905_145214'
$D7CManifest = Join-Path $D7CRun 'D7C_OUTPUT_SHA256_MANIFEST.csv'
$D7CReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D7C_20260905_145214\PHASE_D7C_SUMMARY.txt'
$StableEdges = Join-Path $D7CRun 'D7C_FROZEN_STABLE_ASSOCIATION_EDGES.csv.gz'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D8Root ('D8_V6_TARGET_EVIDENCE_PREFLIGHT_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D8_V6_{0}' -f $Stamp)
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D8_V6_TARGET_EVIDENCE_STRATEGY_AND_INPUT_PREFLIGHT.py'
$AssetInventory = Join-Path $RunDir 'D8_REUSABLE_TARGET_ASSET_INVENTORY.csv'
$AssetSchemaAudit = Join-Path $RunDir 'D8_REUSABLE_TARGET_ASSET_SCHEMA_AUDIT.csv'
$IdentifierAudit = Join-Path $RunDir 'D8_STABLE_EDGE_IDENTIFIER_AUDIT.csv'
$Strategy = Join-Path $RunDir 'D8_FROZEN_TARGET_EVIDENCE_STRATEGY.txt'
$ResultJson = Join-Path $RunDir 'D8_RESULT.json'
$PythonStdout = Join-Path $RunDir 'D8_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D8_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D8_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D8_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D8_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D8_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D8-V6 — TARGET-EVIDENCE STRATEGY + INPUT PREFLIGHT ==='
Write-Host 'MODE=DESIGN_IDENTIFIER_AND_REUSABLE_ASSET_PREFLIGHT_ONLY'
Write-Host 'FROZEN_STABLE_ASSOCIATION_EDGES_EXPECTED=11531'
Write-Host 'EXPERIMENTAL_SOURCE=DIANA_TARBASE_V9_HUMAN'
Write-Host 'PREDICTION_SOURCE_1=TARGETSCANHUMAN_8_DEFAULT_PREDICTIONS'
Write-Host 'PREDICTION_SOURCE_2=MIRDB_6_HUMAN'
Write-Host 'MIRDB_HIGH_CONFIDENCE_RULE=SCORE_GT_80'
Write-Host 'MIRBASE_IDENTIFIER_BRIDGE_VERSION=22.1'
Write-Host 'D8_V6_CORRECTION=MIRBASE_REGEX_ESCAPE_FIX'
Write-Host 'TARGET_DATABASE_EDGE_MATCHING_EXECUTED=NO'
Write-Host 'TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED=NO'
Write-Host 'REGULATORY_EDGE_CONSTRUCTION_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @($D7CManifest,$D7CReport,$StableEdges)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw ('REQUIRED_D8_INPUT_MISSING={0}' -f $p) }
}
if (-not (Test-Path -LiteralPath $Reusable -PathType Container)) { throw ('REUSABLE_ASSET_ROOT_MISSING={0}' -f $Reusable) }

function Get-D8SHA256 { param([string]$Path) return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }
function Recertify-Manifest {
    param([string]$ManifestPath,[int]$ExpectedRows,[string]$Label)
    $rows = @(Import-Csv -LiteralPath $ManifestPath)
    if ($rows.Count -ne $ExpectedRows) { throw ('{0}_MANIFEST_ROW_COUNT_CHANGED expected={1} observed={2}' -f $Label,$ExpectedRows,$rows.Count) }
    foreach ($r in $rows) {
        if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) { throw ('{0}_OUTPUT_MISSING={1}' -f $Label,$r.full_path) }
        $item = Get-Item -LiteralPath $r.full_path
        $hash = Get-D8SHA256 $r.full_path
        if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or $hash -ne $r.SHA256.ToLowerInvariant()) { throw ('{0}_OUTPUT_CHANGED={1}' -f $Label,$r.full_path) }
    }
    Write-Host ('{0}_OUTPUTS_RECERTIFIED={1}/{1}' -f $Label,$ExpectedRows)
}

Recertify-Manifest -ManifestPath $D7CManifest -ExpectedRows 11 -Label 'D7C'
Write-Host 'D7C_CERTIFICATION_GATE=PASS'
$d7c = Get-Content -LiteralPath $D7CReport -Raw
foreach ($tok in @(
    'PHASE_D7C_STATUS=PASS','FROZEN_STABLE_ASSOCIATION_EDGES=11531','REJECTED_UNSTABLE_ASSOCIATION_EDGES=45',
    'FROZEN_STABLE_POSITIVE_ASSOCIATION_EDGES=5225','FROZEN_STABLE_NEGATIVE_ASSOCIATION_EDGES=6306',
    'FROZEN_STABLE_EDGE_SET_BYTE_IDENTICAL_TO_D7B=YES','STABLE_ASSOCIATION_EDGE_SET_FROZEN=YES',
    'CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO','READY_FOR_D8_TARGET_EVIDENCE_STRATEGY_AND_INPUT_PREFLIGHT=YES'
)) { if (-not $d7c.Contains($tok)) { throw ('D7C_CERTIFICATION_TOKEN_MISSING={0}' -f $tok) } }

$PythonExe = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING\D2D_PREFLIGHT_20260904_195001\venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) { throw ('PYTHON_EXECUTABLE_MISSING={0}' -f $PythonExe) }
$PythonVersion = & $PythonExe -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$PandasVersion = & $PythonExe -c "import pandas; print(pandas.__version__)"
$NumpyVersion = & $PythonExe -c "import numpy; print(numpy.__version__)"
Write-Host ('PYTHON_VERSION={0}' -f $PythonVersion)
Write-Host ('PANDAS_VERSION={0}' -f $PandasVersion)
Write-Host ('NUMPY_VERSION={0}' -f $NumpyVersion)

$PythonCode = @'
import gzip, hashlib, io, json, os, re, sys, zipfile
from pathlib import Path
import pandas as pd

REUSABLE=Path(sys.argv[1]); STABLE_EDGES=Path(sys.argv[2])
ASSET_INVENTORY=Path(sys.argv[3]); ASSET_SCHEMA_AUDIT=Path(sys.argv[4])
IDENTIFIER_AUDIT=Path(sys.argv[5]); STRATEGY=Path(sys.argv[6]); RESULT_JSON=Path(sys.argv[7])
results={}
def put(k,v): results[k]=v; print(f"{k}={v}")
def sha256_stream(path,chunk=8*1024*1024):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        while True:
            b=f.read(chunk)
            if not b: break
            h.update(b)
    return h.hexdigest()
def open_text(path):
    p=str(path).lower()
    if p.endswith('.gz'):
        return gzip.open(path,'rt',encoding='utf-8',errors='replace')
    return open(path,'rt',encoding='utf-8',errors='replace')

def sniff(path,n=100):
    """Read first non-empty text lines from plain/gzip/ZIP assets.

    ZIP handling is required for the preserved TargetScanHuman 8.0
    default-prediction archive. Validation JSON sidecars are never
    opened as prediction tables.
    """
    out=[]
    pstr=str(path).lower()
    if pstr.endswith('.zip'):
        with zipfile.ZipFile(path,'r') as zf:
            members=[x for x in zf.namelist() if not x.endswith('/')]
            if not members:
                raise RuntimeError(f'ZIP_ASSET_EMPTY={path}')
            preferred=[x for x in members if 'default_predictions' in x.lower() and x.lower().endswith(('.txt','.tsv','.csv'))]
            if not preferred:
                preferred=[x for x in members if x.lower().endswith(('.txt','.tsv','.csv'))]
            if not preferred:
                raise RuntimeError(f'ZIP_TEXT_MEMBER_NOT_FOUND={path}')
            member=sorted(preferred,key=lambda x:(0 if 'default_predictions' in x.lower() else 1,len(x),x.lower()))[0]
            with zf.open(member,'r') as raw:
                with io.TextIOWrapper(raw,encoding='utf-8',errors='replace') as f:
                    for line in f:
                        s=line.rstrip('\r\n')
                        if s.strip(): out.append(s)
                        if len(out)>=n: break
        return out
    with open_text(path) as f:
        for line in f:
            s=line.rstrip('\r\n')
            if s.strip(): out.append(s)
            if len(out)>=n: break
    return out

files=[]
for base,dirs,names in os.walk(REUSABLE):
    dirs[:]=[d for d in dirs if d.lower() not in {'.git','__pycache__','.ipynb_checkpoints'}]
    for name in names:
        p=Path(base)/name
        try: size=p.stat().st_size
        except OSError: continue
        if size>0: files.append((p,size))
if not files: raise RuntimeError('REUSABLE_ASSET_ROOT_EMPTY')
def lp(p):
    return str(p).replace('\\','/').lower()

def textish_name(name):
    n=name.lower()
    return any(n.endswith(x) for x in [
        '.tsv','.txt','.csv','.tsv.gz','.txt.gz','.csv.gz',
        '.fa','.fasta','.fa.gz','.fasta.gz'
    ])

def safe_sniff(path,n=8):
    try:
        return sniff(path,n)
    except Exception:
        return []

def tab_header_signature(path):
    lines=safe_sniff(path,3)
    if not lines:
        return []
    return [x.strip().lower() for x in lines[0].split('\t')]

def mirdb_content_signature(path):
    # miRDB v6.0 is a headerless multi-species 3-column file:
    # miRNA, target identifier, prediction score.
    # Do NOT require hsa- among the first records; human rows may occur later.
    lines=[x for x in safe_sniff(path,30) if not x.lstrip().startswith('#')]
    checked=0
    for line in lines:
        f=line.split('\t')
        if len(f) < 3:
            continue
        try:
            score=float(f[2].strip())
        except Exception:
            continue
        if not f[0].strip() or not f[1].strip():
            continue
        if 0 <= score <= 100:
            checked += 1
    return checked >= 3
    for line in lines:
        f=line.split('\t')
        if len(f) < 3:
            continue
        if not f[0].strip().lower().startswith('hsa-'):
            continue
        try:
            score=float(f[2].strip())
        except Exception:
            continue
        if 0 <= score <= 100:
            return True
    return False

def mirbase_content_signature(path):
    # miRBase mature FASTA headers can place the mature miRNA name
    # before the MIMAT accession. Require both tokens in the same
    # FASTA header, but do not assume their order.
    lines=safe_sniff(path,4000)
    headers=[x for x in lines if x.startswith('>')]
    return any(
        re.search(r'\bMIMAT\d+\b', x)
        and re.search(r'\bhsa-[^\s]+', x)
        for x in headers
    )

def score(kind,p,size):
    name=p.name.lower(); path=lp(p)

    if kind=='TARBASE_V9_HUMAN':
        # Canonical TarBase-v9 bulk human names include, for example,
        # Homo_sapiens_TarBase-v9.tsv.gz. Older preserved workflows may
        # also use Homo_sapiens.tsv.
        if name in {
            'homo_sapiens_tarbase-v9.tsv.gz',
            'homo_sapiens_tarbase-v9.tsv',
            'homo_sapiens.tsv',
            'homo_sapiens.tsv.gz'
        }:
            return 1200 + min(size/1_000_000,200)
        if 'tarbase' in name and ('homo' in name or 'human' in name):
            return 1100 + (100 if 'v9' in name or '9.0' in name else 0) + min(size/1_000_000,200)
        if ('tarbase' in path or 'diana' in path) and ('homo_sapiens' in name or 'human' in name):
            return 950 + min(size/1_000_000,200)
        if ('tarbase' in path or 'diana' in path) and size > 50_000_000 and textish_name(name):
            hdr=tab_header_signature(p)
            if any('mirna' in x or 'micro' in x for x in hdr) and any('gene' in x or 'ensembl' in x or 'target' in x for x in hdr):
                return 850 + min(size/1_000_000,200)
        # Last-resort schema discovery among large tabular reusable files.
        if size > 50_000_000 and textish_name(name):
            hdr=tab_header_signature(p)
            if any('mirna' in x or 'micro' in x for x in hdr) and any('gene' in x or 'ensembl' in x or 'target' in x for x in hdr):
                return 600 + min(size/1_000_000,200)

    if kind=='MIRDB_V6_HUMAN':
        if 'mirdb' in name or 'mirdb' in path:
            if textish_name(name):
                return 900 + (100 if ('v6' in path or '6.0' in path or 'v6' in name or '6.0' in name) else 0) + (100 if ('prediction' in name or 'predict' in name) else 0) + min(size/1_000_000,100)
        if textish_name(name) and size > 1_000_000 and mirdb_content_signature(p):
            return 550 + min(size/1_000_000,100)

    if kind=='TARGETSCANHUMAN_8_DEFAULT':
        # Explicitly exclude validation/metadata sidecars. The actual
        # TargetScan Release 8 asset may be a ZIP archive containing the
        # default_predictions text file.
        if name.endswith('.json') or '.validation.' in name or name.endswith('.sha256'):
            return None
        canonical={
            'predicted_targets_context_scores.default_predictions.txt.zip',
            'predicted_targets_context_scores.default_predictions.txt',
            'predicted_targets_context_scores.default_predictions.txt.gz'
        }
        if name in canonical:
            return 1600 + (100 if name.endswith('.zip') else 50) + min(size/1_000_000,100)
        if 'default_predictions' in name and name.endswith(('.zip','.txt','.txt.gz','.tsv','.tsv.gz','.csv','.csv.gz')):
            return 1400 + (100 if 'targetscan' in path else 0) + (100 if ('8.0' in path or 'vert_80' in path or '80' in name) else 0) + min(size/1_000_000,100)
        if ('predicted_targets_context_scores' in name or ('context' in name and 'predicted' in name)) and name.endswith(('.zip','.txt','.txt.gz','.tsv','.tsv.gz','.csv','.csv.gz')):
            return 1100 + (100 if 'targetscan' in path else 0) + min(size/1_000_000,100)
        if 'targetscan' in path and textish_name(name):
            hdr=tab_header_signature(p)
            if any('gene symbol' in x or x=='gene_symbol' for x in hdr) and any('mirna' in x for x in hdr) and any('context' in x for x in hdr):
                return 800 + min(size/1_000_000,100)

    if kind=='MIRBASE_22_1_MATURE':
        # Never select an arbitrary file merely because it is named mature.fa.
        # The candidate must exhibit a miRBase mature-FASTA content signature.
        if name in {'mature.fa','mature.fa.gz','mature.fasta','mature.fasta.gz'} and mirbase_content_signature(p):
            return (
                1200
                + (200 if 'mirbase' in path else 0)
                + (300 if ('22.1' in path or '/22.1/' in path or '/22/' in path or '22_1' in path) else 0)
            )
        if textish_name(name) and ('mirbase' in path or 'mature' in name) and mirbase_content_signature(p):
            return 800 + (300 if ('22.1' in path or '/22.1/' in path or '/22/' in path or '22_1' in path) else 0)

    if kind=='HGNC_COMPLETE_SET':
        if name in {
            'hgnc_complete_set.txt','hgnc_complete_set.tsv',
            'hgnc_complete_set.txt.gz','hgnc_complete_set.tsv.gz'
        }:
            return 1200 + (100 if 'hgnc' in path else 0)
        if 'hgnc' in path and textish_name(name):
            hdr=set(tab_header_signature(p))
            req={'hgnc_id','symbol','status','alias_symbol','prev_symbol'}
            if req.issubset(hdr):
                return 800 + min(size/1_000_000,100)

    return None

kinds=['TARBASE_V9_HUMAN','MIRDB_V6_HUMAN','TARGETSCANHUMAN_8_DEFAULT','MIRBASE_22_1_MATURE','HGNC_COMPLETE_SET']
selected={}; inv=[]; missing_kinds=[]
for kind in kinds:
    cand=[]
    for p,size in files:
        s=score(kind,p,size)
        if s is not None:
            cand.append((s,size,p))
    cand.sort(key=lambda x:(x[0],x[1],str(x[2]).lower()),reverse=True)
    if not cand:
        missing_kinds.append(kind)
        inv.append({
            'asset_kind':kind,'candidate_rank':0,'selected_primary':'NO',
            'selection_score':'','filename':'','full_path':'',
            'size_bytes':'','SHA256':'','discovery_status':'NOT_FOUND'
        })
        continue
    selected[kind]=cand[0][2]
    for rank,(s,size,p) in enumerate(cand,1):
        inv.append({
            'asset_kind':kind,'candidate_rank':rank,
            'selected_primary':'YES' if p==selected[kind] else 'NO',
            'selection_score':float(s),'filename':p.name,'full_path':str(p),
            'size_bytes':int(size),
            'SHA256':sha256_stream(p) if p==selected[kind] else '',
            'discovery_status':'SELECTED' if p==selected[kind] else 'ALTERNATE'
        })

# Always write discovery evidence before any fail-closed termination.
pd.DataFrame(inv).to_csv(ASSET_INVENTORY,index=False)
put('REUSABLE_FILES_DISCOVERED',len(files))
put('ASSET_DISCOVERY_INVENTORY_WRITTEN','YES')

if missing_kinds:
    raise RuntimeError(
        'REQUIRED_REUSABLE_TARGET_ASSETS_NOT_FOUND='+'|'.join(missing_kinds)
    )

put('REUSABLE_TARGET_ASSET_TYPES_FOUND',5)
for kind in kinds:
    put(f'{kind}_ASSET_FOUND','YES')
    put(f'{kind}_SELECTED_FILENAME',selected[kind].name)
put('SELECTED_REUSABLE_ASSETS_SHA256_COMPUTED','YES')

stable=pd.read_csv(STABLE_EDGES,compression='gzip',engine='c',float_precision='round_trip')
if stable.shape[0]!=11531: raise RuntimeError(f'STABLE_EDGE_ROWS_CHANGED observed={stable.shape[0]}')
for col in ['mRNA_id','miRNA_id','partial_spearman_rho','FDR','bootstrap_selection_frequency']:
    if col not in stable.columns: raise RuntimeError(f'STABLE_EDGE_COLUMN_MISSING={col}')
if stable.duplicated(['mRNA_id','miRNA_id']).any(): raise RuntimeError('STABLE_EDGE_DUPLICATE_PAIR')
unique_mrna=list(dict.fromkeys(stable['mRNA_id'].astype(str).tolist()))
unique_mirna=list(dict.fromkeys(stable['miRNA_id'].astype(str).tolist()))
audit=[]
for ident in unique_mirna:
    parts=ident.split('|')
    if len(parts)!=2: raise RuntimeError(f'MIRNA_PROJECT_IDENTITY_NOT_TWO_PART={ident}')
    mimat=parts[0].strip(); mature=parts[1].strip()
    if not re.fullmatch(r'MIMAT\d+',mimat) or not mature.startswith('hsa-'): raise RuntimeError(f'MIRNA_PROJECT_IDENTITY_INVALID={ident}')
    audit.append({'identifier_type':'miRNA','project_identity':ident,'MIMAT':mimat,'mature_name':mature,'status':'PASS'})
audit.append({'identifier_type':'miRNA_SUMMARY','project_identity':'','MIMAT':'','mature_name':'','status':'PASS','unique_identifier_count':len(unique_mirna)})
audit.append({'identifier_type':'mRNA_SUMMARY','project_identity':'','MIMAT':'','mature_name':'','status':'PASS','unique_identifier_count':len(unique_mrna)})
pd.DataFrame(audit).to_csv(IDENTIFIER_AUDIT,index=False)
put('STABLE_EDGE_IDENTIFIER_STRUCTURE_AUDIT','PASS'); put('FROZEN_STABLE_ASSOCIATION_EDGES',11531)
put('FROZEN_STABLE_UNIQUE_MRNA_IDS',len(unique_mrna)); put('FROZEN_STABLE_UNIQUE_MIRNA_IDS',len(unique_mirna)); put('MIRNA_PROJECT_IDENTITY_FORMAT','MIMAT|MATURE_NAME')

schema=[]
tar=selected['TARBASE_V9_HUMAN']; h=sniff(tar,5)[0]; f=[x.strip().lower() for x in h.split('\t')]
if len(f)<3 or not any('mirna' in x or 'micro' in x for x in f) or not any('gene' in x or 'ensembl' in x or 'target' in x for x in f): raise RuntimeError(f'TARBASE_SCHEMA_UNEXPECTED header={h[:500]}')
schema.append({'asset_kind':'TARBASE_V9_HUMAN','path':str(tar),'schema_status':'PASS','header_or_format':h[:1000]})

mirdb=selected['MIRDB_V6_HUMAN']; lines=[x for x in sniff(mirdb,30) if not x.lstrip().startswith('#')]
valid_mirdb_rows=0
for line in lines:
    f=line.split('\t')
    if len(f) < 3: continue
    try: score=float(f[2].strip())
    except Exception: continue
    if f[0].strip() and f[1].strip() and 0 <= score <= 100: valid_mirdb_rows += 1
if valid_mirdb_rows < 3: raise RuntimeError(f'MIRDB_THREE_COLUMN_NUMERIC_SCORE_SCHEMA_NOT_CONFIRMED valid_rows={valid_mirdb_rows}')
schema.append({'asset_kind':'MIRDB_V6_HUMAN','path':str(mirdb),'schema_status':'PASS','header_or_format':'headerless multi-species tab-delimited miRNA|target|score; numeric score confirmed; human filtering deferred to D8A'})
put('MIRDB_SCHEMA_SPECIES_AGNOSTIC_PREFLIGHT','PASS')
put('MIRDB_HUMAN_FILTERING_EXECUTED','NO')

ts=selected['TARGETSCANHUMAN_8_DEFAULT']
if ts.name.lower().endswith('.json') or '.validation.' in ts.name.lower(): raise RuntimeError(f'TARGETSCAN_SIDECAR_SELECTED_IN_ERROR={ts}')
h=sniff(ts,5)[0]
f=[x.strip().lower() for x in h.split('\t')]
normalized={re.sub(r'[^a-z0-9]+',' ',x).strip() for x in f}

# TargetScanHuman 8.0 default-prediction files use "Gene Tax ID"
# as the organism/taxon field. D8-V3 incorrectly required a literal
# field containing the word "species". Accept only explicit taxon
# labels; do not infer species from gene/miRNA names.
if not any(x in {'gene symbol','gene_symbol'} or 'gene symbol' in x for x in f):
    raise RuntimeError(f'TARGETSCAN_GENE_SYMBOL_FIELD_MISSING header={h[:500]}')
if not any('mirna' in x for x in f):
    raise RuntimeError(f'TARGETSCAN_MIRNA_FIELD_MISSING header={h[:500]}')
taxon_ok = any(
    x in {
        'gene tax id','gene taxid','tax id','taxid',
        'species','species id','species tax id'
    }
    for x in normalized
)
if not taxon_ok:
    raise RuntimeError(f'TARGETSCAN_TAXON_FIELD_MISSING header={h[:500]}')
if not any('context' in x for x in f):
    raise RuntimeError(f'TARGETSCAN_CONTEXT_FIELD_MISSING header={h[:500]}')

# The selected Release-8 default-prediction table must expose the core
# fields needed later for explicit human filtering and pair mapping.
required_exact={'gene id','gene symbol','transcript id','gene tax id','mirna','site type'}
missing_exact=sorted(required_exact-normalized)
if missing_exact:
    raise RuntimeError(
        f'TARGETSCAN_RELEASE8_CORE_FIELDS_MISSING={missing_exact} header={h[:500]}'
    )

schema.append({
    'asset_kind':'TARGETSCANHUMAN_8_DEFAULT',
    'path':str(ts),
    'schema_status':'PASS',
    'header_or_format':h[:1000],
    'notes':'Release-8 default predictions; Gene Tax ID accepted as explicit taxon field; human filtering deferred to D8A'
})
put('TARGETSCAN_ACTUAL_PREDICTION_TABLE_SELECTED','YES')
put('TARGETSCAN_VALIDATION_JSON_SELECTED','NO')
put('TARGETSCAN_GENE_TAX_ID_SCHEMA_PREFLIGHT','PASS')
put('TARGETSCAN_HUMAN_FILTERING_EXECUTED','NO')

mb=selected['MIRBASE_22_1_MATURE']; headers=[x for x in sniff(mb,100000) if x.startswith('>')]
mimat_headers=[x for x in headers if re.search(r'\bMIMAT\d+\b',x)]
human_headers=[x for x in headers if re.search(r'\bhsa-[^\s]+',x)]
paired_headers=[
    x for x in headers
    if re.search(r'\bMIMAT\d+\b',x)
    and re.search(r'\bhsa-[^\s]+',x)
]
if not mimat_headers: raise RuntimeError('MIRBASE_MIMAT_HEADERS_NOT_FOUND')
if not human_headers: raise RuntimeError('MIRBASE_HUMAN_MATURE_HEADERS_NOT_FOUND_IN_SNIFF')
if not paired_headers: raise RuntimeError('MIRBASE_HUMAN_MATURE_AND_MIMAT_NOT_COLOCATED_IN_HEADER')
schema.append({
    'asset_kind':'MIRBASE_22_1_MATURE',
    'path':str(mb),
    'schema_status':'PASS',
    'header_or_format':'FASTA mature miRNA; MIMAT accession and hsa mature name detected in same header; order not assumed',
    'notes':'identifier bridge only; no stable-edge/database matching executed'
})
put('MIRBASE_REGEX_ESCAPE_VALIDATION','PASS')
put('MIRBASE_FASTA_HEADER_ORDER_INDEPENDENT_PREFLIGHT','PASS')
put('MIRBASE_HUMAN_MIMAT_COLOCATED_HEADER_PREFLIGHT','PASS')
put('MIRBASE_STABLE_EDGE_IDENTIFIER_MATCHING_EXECUTED','NO')

hg=selected['HGNC_COMPLETE_SET']; h=sniff(hg,3)[0]; f={x.strip().lower() for x in h.split('\t')}; req={'hgnc_id','symbol','status','alias_symbol','prev_symbol'}; miss=sorted(req-f)
if miss: raise RuntimeError(f'HGNC_COMPLETE_SET_COLUMNS_MISSING={miss}')
schema.append({'asset_kind':'HGNC_COMPLETE_SET','path':str(hg),'schema_status':'PASS','header_or_format':h[:1000]})
pd.DataFrame(schema).to_csv(ASSET_SCHEMA_AUDIT,index=False)
put('REUSABLE_TARGET_ASSET_SCHEMA_AUDIT','PASS'); put('TARGET_DATABASE_EDGE_MATCHING_EXECUTED','NO'); put('TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED','NO')

strategy=[
'GSE243219_D8_FROZEN_TARGET_EVIDENCE_STRATEGY','FROZEN_STABLE_ASSOCIATION_INPUT_EDGES=11531',f'FROZEN_STABLE_UNIQUE_MRNA_IDS={len(unique_mrna)}',f'FROZEN_STABLE_UNIQUE_MIRNA_IDS={len(unique_mirna)}',
'PRIMARY_MIRNA_PROJECT_IDENTITY=MIMAT|mature-miRNA','MIRBASE_IDENTIFIER_BRIDGE_VERSION=22.1','MIRBASE_IDENTIFIER_BRIDGE_ROLE=VALIDATION_AND_ALIAS_BRIDGE_ONLY','MIRBASE_RELEASE_MIGRATION_EXECUTED=NO',
'GENE_PRIMARY_IDENTITY=ORIGINAL_EXPRESSION_GENE_SYMBOL','HGNC_MAPPING_STEP_1=EXACT_APPROVED_SYMBOL','HGNC_MAPPING_STEP_2=UNIQUE_EXACT_PREVIOUS_SYMBOL','HGNC_MAPPING_STEP_3=UNIQUE_EXACT_ALIAS_SYMBOL','HGNC_CASE_INSENSITIVE_GUESSING=PROHIBITED','HGNC_AMBIGUOUS_ALIAS_AUTO_MAPPING=PROHIBITED','HGNC_UNMATCHED_SYMBOL_AUTO_MAPPING=PROHIBITED','HGNC_AMBIGUOUS_OR_UNMATCHED_STATUS=REVIEW_REQUIRED',
'EXPERIMENTAL_EVIDENCE_SOURCE=DIANA_TARBASE_V9_HOMO_SAPIENS','EXPERIMENTAL_ROUTE_A_RULE=ANY_MATCHED_TARBASE_V9_EXPERIMENTALLY_SUPPORTED_MIRNA_GENE_PAIR','TARBASE_METHOD_METADATA_RETAINED=YES','TARBASE_METHOD_CLASS_USED_AS_EXCLUSION_GATE=NO',
'PREDICTION_SOURCE_1=TARGETSCANHUMAN_8_0_DEFAULT_PREDICTIONS','TARGETSCAN_ADDITIONAL_CONTEXT_SCORE_THRESHOLD=NONE','TARGETSCAN_FAMILY_OR_MEMBER_MAPPING=EXPLICIT_RELEASE_METADATA_ONLY','TARGETSCAN_FAMILY_INFERENCE_FROM_NAME=PROHIBITED','TARGETSCAN_FAMILY_INFERENCE_FROM_SEED_SEQUENCE=PROHIBITED',
'PREDICTION_SOURCE_2=MIRDB_6_0_HUMAN','MIRDB_HIGH_CONFIDENCE_RULE=SCORE_GT_80','PREDICTION_ROUTE_B_RULE=TARGETSCAN_DEFAULT_SUPPORT_AND_MIRDB_SCORE_GT_80','SINGLE_TARGETSCAN_SUPPORT_ONLY=ANNOTATION_NOT_ELIGIBILITY','SINGLE_MIRDB_SUPPORT_ONLY=ANNOTATION_NOT_ELIGIBILITY',
'REGULATORY_EDGE_ELIGIBILITY=STABLE_ASSOCIATION_AND_TARBASE_ROUTE_A_OR_PREDICTION_ROUTE_B','WITHIN_SOURCE_DUPLICATE_RECORDS=COLLAPSE_TO_UNIQUE_MIRNA_GENE_PAIR_WITH_METADATA_COUNTS_RETAINED','CROSS_SOURCE_EVIDENCE=COMBINE_AT_UNIQUE_MIRNA_GENE_PAIR_LEVEL',
'POSITIVE_STABLE_ASSOCIATIONS_CAN_BE_REGULATORY_ELIGIBLE=YES','NEGATIVE_STABLE_ASSOCIATIONS_CAN_BE_REGULATORY_ELIGIBLE=YES','CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO','TARGET_EVIDENCE_ESTABLISHES_DIRECTION=miRNA_TO_mRNA',
'TARGET_DATABASE_EDGE_MATCHING_EXECUTED_IN_D8=NO','TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED_IN_D8=NO','REGULATORY_EDGE_CONSTRUCTION_EXECUTED_IN_D8=NO','NETWORK_CONSTRUCTION_EXECUTED_IN_D8=NO','ACLA_EXECUTED_IN_D8=NO']
STRATEGY.write_text('\n'.join(strategy)+'\n',encoding='utf-8')
put('TARGET_EVIDENCE_STRATEGY_FROZEN','YES'); put('EXPERIMENTAL_ROUTE_A_SOURCE','DIANA_TARBASE_V9_HUMAN'); put('PREDICTION_ROUTE_B','TARGETSCAN8_DEFAULT_AND_MIRDB_SCORE_GT_80'); put('SINGLE_PREDICTOR_ONLY_ELIGIBLE','NO'); put('MIRBASE_IDENTIFIER_BRIDGE_VERSION','22.1'); put('REGULATORY_DIRECTION_SOURCE','TARGET_EVIDENCE_NOT_CORRELATION_SIGN'); put('REGULATORY_EDGE_CONSTRUCTION_EXECUTED','NO'); put('NETWORK_EXECUTED','NO'); put('ACLA_EXECUTED','NO'); put('READY_FOR_D8A_TARGET_EVIDENCE_INTEGRATION','YES'); put('NEXT_PHASE','D8A_TARGET_EVIDENCE_INTEGRATION_AND_REGULATORY_EDGE_CLASSIFICATION')
RESULT_JSON.write_text(json.dumps({'results':results,'selected_assets':{k:str(v) for k,v in selected.items()}},indent=2,sort_keys=True),encoding='utf-8')
'@

$PythonCode | Set-Content -LiteralPath $PyScript -Encoding UTF8
$env:PYTHONUTF8='1'; $env:PYTHONIOENCODING='utf-8'
$PythonArgs=@('-u',$PyScript,$Reusable,$StableEdges,$AssetInventory,$AssetSchemaAudit,$IdentifierAudit,$Strategy,$ResultJson)
$proc=Start-Process -FilePath $PythonExe -ArgumentList $PythonArgs -Wait -PassThru -NoNewWindow -RedirectStandardOutput $PythonStdout -RedirectStandardError $PythonStderr
$PythonExit=[int]$proc.ExitCode
$stdoutLines=@(); $stderrLines=@()
if (Test-Path -LiteralPath $PythonStdout -PathType Leaf) { $stdoutLines=@(Get-Content -LiteralPath $PythonStdout); foreach($line in $stdoutLines){Write-Host $line} }
if (Test-Path -LiteralPath $PythonStderr -PathType Leaf) { $stderrLines=@(Get-Content -LiteralPath $PythonStderr); if($stderrLines.Count -gt 0){ Write-Host '=== D8 PYTHON STDERR ==='; foreach($line in $stderrLines){Write-Host $line} } }
@('=== STDOUT ===',$stdoutLines,'','=== STDERR ===',$stderrLines) | Set-Content -LiteralPath $PythonLog -Encoding UTF8
if($PythonExit -ne 0){throw ('D8_PYTHON_FAILED exit={0} full_traceback={1}' -f $PythonExit,$PythonStderr)}
if(-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)){throw 'D8_RESULT_JSON_MISSING'}
$result=Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json
function Cap { param([string]$Key) return [string]$result.results.$Key }
foreach($pair in @(
@('ASSET_DISCOVERY_INVENTORY_WRITTEN','YES'),
@('REUSABLE_TARGET_ASSET_TYPES_FOUND','5'),@('TARBASE_V9_HUMAN_ASSET_FOUND','YES'),@('MIRDB_V6_HUMAN_ASSET_FOUND','YES'),@('TARGETSCANHUMAN_8_DEFAULT_ASSET_FOUND','YES'),@('MIRBASE_22_1_MATURE_ASSET_FOUND','YES'),@('HGNC_COMPLETE_SET_ASSET_FOUND','YES'),@('SELECTED_REUSABLE_ASSETS_SHA256_COMPUTED','YES'),@('STABLE_EDGE_IDENTIFIER_STRUCTURE_AUDIT','PASS'),@('FROZEN_STABLE_ASSOCIATION_EDGES','11531'),@('MIRNA_PROJECT_IDENTITY_FORMAT','MIMAT|MATURE_NAME'),@('MIRBASE_REGEX_ESCAPE_VALIDATION','PASS'),@('MIRBASE_FASTA_HEADER_ORDER_INDEPENDENT_PREFLIGHT','PASS'),@('MIRBASE_HUMAN_MIMAT_COLOCATED_HEADER_PREFLIGHT','PASS'),@('MIRBASE_STABLE_EDGE_IDENTIFIER_MATCHING_EXECUTED','NO'),@('REUSABLE_TARGET_ASSET_SCHEMA_AUDIT','PASS'),
@('MIRDB_SCHEMA_SPECIES_AGNOSTIC_PREFLIGHT','PASS'),
@('MIRDB_HUMAN_FILTERING_EXECUTED','NO'),
@('TARGETSCAN_ACTUAL_PREDICTION_TABLE_SELECTED','YES'),
@('TARGETSCAN_VALIDATION_JSON_SELECTED','NO'),
@('TARGETSCAN_GENE_TAX_ID_SCHEMA_PREFLIGHT','PASS'),
@('TARGETSCAN_HUMAN_FILTERING_EXECUTED','NO'),@('TARGET_DATABASE_EDGE_MATCHING_EXECUTED','NO'),@('TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED','NO'),@('TARGET_EVIDENCE_STRATEGY_FROZEN','YES'),@('EXPERIMENTAL_ROUTE_A_SOURCE','DIANA_TARBASE_V9_HUMAN'),@('PREDICTION_ROUTE_B','TARGETSCAN8_DEFAULT_AND_MIRDB_SCORE_GT_80'),@('SINGLE_PREDICTOR_ONLY_ELIGIBLE','NO'),@('MIRBASE_IDENTIFIER_BRIDGE_VERSION','22.1'),@('REGULATORY_DIRECTION_SOURCE','TARGET_EVIDENCE_NOT_CORRELATION_SIGN'),@('REGULATORY_EDGE_CONSTRUCTION_EXECUTED','NO'),@('NETWORK_EXECUTED','NO'),@('ACLA_EXECUTED','NO'),@('READY_FOR_D8A_TARGET_EVIDENCE_INTEGRATION','YES'),@('NEXT_PHASE','D8A_TARGET_EVIDENCE_INTEGRATION_AND_REGULATORY_EDGE_CLASSIFICATION')
)){ $observed=Cap $pair[0]; if($observed -ne $pair[1]){throw ('D8_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f $pair[0],$pair[1],$observed)} }

@(
'GSE243219_D8_V6_DECISION','PHASE_D8_V6_STATUS=PASS','MODE=DESIGN_IDENTIFIER_AND_REUSABLE_ASSET_PREFLIGHT_ONLY',
'D8_V4_CORRECTION=TARGETSCAN_GENE_TAX_ID_SCHEMA_ACCEPTED',
'D8_V2_CORRECTION=CONTENT_AND_CANONICAL_FILENAME_BASED_REUSABLE_ASSET_DISCOVERY','D7C_CERTIFICATION_GATE=PASS','D7C_OUTPUTS_RECERTIFIED=11/11','FROZEN_STABLE_ASSOCIATION_EDGES=11531',('FROZEN_STABLE_UNIQUE_MRNA_IDS={0}' -f (Cap 'FROZEN_STABLE_UNIQUE_MRNA_IDS')),('FROZEN_STABLE_UNIQUE_MIRNA_IDS={0}' -f (Cap 'FROZEN_STABLE_UNIQUE_MIRNA_IDS')),'REUSABLE_TARGET_ASSET_TYPES_FOUND=5','TARBASE_V9_HUMAN_ASSET_FOUND=YES','MIRDB_V6_HUMAN_ASSET_FOUND=YES','TARGETSCANHUMAN_8_DEFAULT_ASSET_FOUND=YES',
'TARGETSCAN_GENE_TAX_ID_SCHEMA_PREFLIGHT=PASS',
'TARGETSCAN_HUMAN_FILTERING_EXECUTED=NO','MIRBASE_REGEX_ESCAPE_VALIDATION=PASS','MIRBASE_FASTA_HEADER_ORDER_INDEPENDENT_PREFLIGHT=PASS','MIRBASE_HUMAN_MIMAT_COLOCATED_HEADER_PREFLIGHT=PASS','MIRBASE_STABLE_EDGE_IDENTIFIER_MATCHING_EXECUTED=NO','MIRBASE_22_1_MATURE_ASSET_FOUND=YES','HGNC_COMPLETE_SET_ASSET_FOUND=YES','SELECTED_REUSABLE_ASSETS_SHA256_COMPUTED=YES','REUSABLE_TARGET_ASSET_SCHEMA_AUDIT=PASS',
'D8_V3_CORRECTION=MIRDB_SCHEMA_SPECIES_AGNOSTIC_AND_TARGETSCAN_ZIP_DATA_TABLE_SELECTION',
'MIRDB_SCHEMA_SPECIES_AGNOSTIC_PREFLIGHT=PASS',
'MIRDB_HUMAN_FILTERING_EXECUTED=NO',
'TARGETSCAN_ACTUAL_PREDICTION_TABLE_SELECTED=YES',
'TARGETSCAN_VALIDATION_JSON_SELECTED=NO','STABLE_EDGE_IDENTIFIER_STRUCTURE_AUDIT=PASS','PRIMARY_MIRNA_PROJECT_IDENTITY=MIMAT|mature-miRNA','MIRBASE_IDENTIFIER_BRIDGE_VERSION=22.1','HGNC_MAPPING=EXACT_APPROVED_THEN_UNIQUE_PREVIOUS_THEN_UNIQUE_ALIAS','HGNC_CASE_INSENSITIVE_GUESSING=PROHIBITED','EXPERIMENTAL_SOURCE=DIANA_TARBASE_V9_HUMAN','PREDICTION_SOURCE_1=TARGETSCANHUMAN_8_DEFAULT_PREDICTIONS','TARGETSCAN_ADDITIONAL_CONTEXT_SCORE_THRESHOLD=NONE','PREDICTION_SOURCE_2=MIRDB_6_HUMAN','MIRDB_HIGH_CONFIDENCE_RULE=SCORE_GT_80','REGULATORY_ELIGIBILITY=STABLE_ASSOCIATION_AND_TARBASE_OR_TARGETSCAN_PLUS_MIRDB_GT80','SINGLE_PREDICTOR_ONLY_ELIGIBLE=NO','CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO','TARGET_EVIDENCE_ESTABLISHES_DIRECTION=miRNA_TO_mRNA','TARGET_DATABASE_EDGE_MATCHING_EXECUTED=NO','TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED=NO','REGULATORY_EDGE_CONSTRUCTION_EXECUTED=NO','NETWORK_EXECUTED=NO','ACLA_EXECUTED=NO','READY_FOR_D8A_TARGET_EVIDENCE_INTEGRATION=YES','READY_FOR_NETWORK=NO','READY_FOR_ACLA=NO','NEXT_PHASE=D8A_TARGET_EVIDENCE_INTEGRATION_AND_REGULATORY_EDGE_CLASSIFICATION','STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

$outFiles=@($PyScript,$AssetInventory,$AssetSchemaAudit,$IdentifierAudit,$Strategy,$ResultJson,$PythonStdout,$PythonStderr,$PythonLog,$DecisionTxt)
$manifest=New-Object 'System.Collections.Generic.List[object]'
foreach($p in $outFiles){ if(-not (Test-Path -LiteralPath $p -PathType Leaf)){throw ('D8_OUTPUT_MISSING={0}' -f $p)}; $item=Get-Item -LiteralPath $p; [void]$manifest.Add([pscustomobject]@{filename=$item.Name;full_path=$item.FullName;size_bytes=[Int64]$item.Length;SHA256=(Get-D8SHA256 $item.FullName)}) }
$manifest | Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

@(
'=== GSE243219 PHASE D8-V6 SUMMARY ===','PHASE_D8_V6_STATUS=PASS','MODE=DESIGN_IDENTIFIER_AND_REUSABLE_ASSET_PREFLIGHT_ONLY',
'D8_V4_CORRECTION=TARGETSCAN_GENE_TAX_ID_SCHEMA_ACCEPTED',
'D8_V2_CORRECTION=CONTENT_AND_CANONICAL_FILENAME_BASED_REUSABLE_ASSET_DISCOVERY',('PYTHON_VERSION={0}' -f $PythonVersion),('PANDAS_VERSION={0}' -f $PandasVersion),('NUMPY_VERSION={0}' -f $NumpyVersion),'D7C_CERTIFICATION_GATE=PASS','FROZEN_STABLE_ASSOCIATION_EDGES=11531',('FROZEN_STABLE_UNIQUE_MRNA_IDS={0}' -f (Cap 'FROZEN_STABLE_UNIQUE_MRNA_IDS')),('FROZEN_STABLE_UNIQUE_MIRNA_IDS={0}' -f (Cap 'FROZEN_STABLE_UNIQUE_MIRNA_IDS')),'REUSABLE_TARGET_ASSET_TYPES_FOUND=5','TARBASE_V9_HUMAN_ASSET_FOUND=YES','MIRDB_V6_HUMAN_ASSET_FOUND=YES','TARGETSCANHUMAN_8_DEFAULT_ASSET_FOUND=YES',
'TARGETSCAN_GENE_TAX_ID_SCHEMA_PREFLIGHT=PASS',
'TARGETSCAN_HUMAN_FILTERING_EXECUTED=NO','MIRBASE_REGEX_ESCAPE_VALIDATION=PASS','MIRBASE_FASTA_HEADER_ORDER_INDEPENDENT_PREFLIGHT=PASS','MIRBASE_HUMAN_MIMAT_COLOCATED_HEADER_PREFLIGHT=PASS','MIRBASE_STABLE_EDGE_IDENTIFIER_MATCHING_EXECUTED=NO','MIRBASE_22_1_MATURE_ASSET_FOUND=YES','HGNC_COMPLETE_SET_ASSET_FOUND=YES','SELECTED_REUSABLE_ASSETS_SHA256_COMPUTED=YES','REUSABLE_TARGET_ASSET_SCHEMA_AUDIT=PASS',
'D8_V3_CORRECTION=MIRDB_SCHEMA_SPECIES_AGNOSTIC_AND_TARGETSCAN_ZIP_DATA_TABLE_SELECTION',
'MIRDB_SCHEMA_SPECIES_AGNOSTIC_PREFLIGHT=PASS',
'MIRDB_HUMAN_FILTERING_EXECUTED=NO',
'TARGETSCAN_ACTUAL_PREDICTION_TABLE_SELECTED=YES',
'TARGETSCAN_VALIDATION_JSON_SELECTED=NO','STABLE_EDGE_IDENTIFIER_STRUCTURE_AUDIT=PASS','PRIMARY_MIRNA_PROJECT_IDENTITY=MIMAT|mature-miRNA','MIRBASE_IDENTIFIER_BRIDGE_VERSION=22.1','EXPERIMENTAL_SOURCE=DIANA_TARBASE_V9_HUMAN','PREDICTION_SOURCE_1=TARGETSCANHUMAN_8_DEFAULT_PREDICTIONS','PREDICTION_SOURCE_2=MIRDB_6_HUMAN','MIRDB_HIGH_CONFIDENCE_RULE=SCORE_GT_80','REGULATORY_ELIGIBILITY=STABLE_ASSOCIATION_AND_TARBASE_OR_TARGETSCAN_PLUS_MIRDB_GT80','SINGLE_PREDICTOR_ONLY_ELIGIBLE=NO','TARGET_DATABASE_EDGE_MATCHING_EXECUTED=NO','TARGET_EVIDENCE_OVERLAP_COUNTS_COMPUTED=NO','REGULATORY_EDGE_CONSTRUCTION_EXECUTED=NO','NETWORK_EXECUTED=NO','ACLA_EXECUTED=NO','TARGET_EVIDENCE_STRATEGY_FROZEN=YES','READY_FOR_D8A_TARGET_EVIDENCE_INTEGRATION=YES','READY_FOR_NETWORK=NO','READY_FOR_ACLA=NO','NEXT_PHASE=D8A_TARGET_EVIDENCE_INTEGRATION_AND_REGULATORY_EDGE_CLASSIFICATION','STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''; Get-Content -LiteralPath $SummaryTxt; Write-Host ''
Write-Host ('D8_ASSET_INVENTORY={0}' -f $AssetInventory)
Write-Host ('D8_ASSET_SCHEMA_AUDIT={0}' -f $AssetSchemaAudit)
Write-Host ('D8_IDENTIFIER_AUDIT={0}' -f $IdentifierAudit)
Write-Host ('D8_FROZEN_STRATEGY={0}' -f $Strategy)
Write-Host ('D8_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D8_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D8_V6=PASS'
Write-Host 'STOP=YES'
