$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D3 — REAL MATRIX CONSTRUCTION + QC PREFLIGHT
#
# First authorized read/construction of the real biological
# processed-count matrices.
#
# Authorized:
#   - read all 72 mRNA and 72 miRNA processed count files
#   - construct raw mRNA matrix (gene_symbol x 72)
#   - construct raw annotated miRNA matrix (2886 rows x 72)
#   - construct mature miRNA PRIMARY matrix using the frozen
#     MEDIAN-across-precursor rule
#   - construct mature miRNA SENSITIVITY matrix using MAX
#   - compute non-inferential per-sample QC/library metrics
#   - write deterministic manifests / hashes
#
# Prohibited:
#   - mRNA count rounding
#   - zero filling
#   - TMM or any normalization of real data
#   - feature filtering
#   - sample exclusion
#   - DE
#   - network construction
#   - A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'

$AcqRoot = Join-Path $Project '01_PROCESSED_DATA_ACQUISITION'
$D2Root = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING'
$D3Root = Join-Path $Project '03_QC_AND_FILTERING'

$D2CRun = Join-Path $D2Root 'D2C_STRATEGY_20260904_194630'
$D2CManifest = Join-Path $D2CRun 'D2C_OUTPUT_SHA256_MANIFEST.csv'
$D2CStrategy = Join-Path $D2CRun 'D2C_FROZEN_FEATURE_IDENTITY_AND_STATISTICAL_STRATEGY.txt'
$D2CReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D2C_20260904_194630\PHASE_D2C_SUMMARY.txt'

$D2E4Run = Join-Path $D2Root 'D2E_V4_TMM_OFFLINE_VALIDATION_20260904_225425'
$D2E4Manifest = Join-Path $D2E4Run 'D2E_V4_OUTPUT_SHA256_MANIFEST.csv'
$D2E4Decision = Join-Path $D2E4Run 'D2E_V4_DECISION.txt'
$D2E4Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D2E_V4_20260904_225425\PHASE_D2E_V4_SUMMARY.txt'

$D2DRun = Join-Path $D2Root 'D2D_PREFLIGHT_20260904_195001'
$VenvPython = Join-Path $D2DRun 'venv\Scripts\python.exe'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D3Root ('D3_V2_MATRIX_QC_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D3_V2_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D3_V2_BUILD_AND_AUDIT_REAL_MATRICES.py'

$SourceInventory = Join-Path $RunDir 'D3_SOURCE_COUNT_FILE_SHA256_INVENTORY.csv'
$SampleMetadata = Join-Path $RunDir 'D3_PAIRED_SAMPLE_METADATA.csv'
$MrnaMatrix = Join-Path $RunDir 'D3_MRNA_RAW_COUNTS_26364x72.csv.gz'
$MirnaRawMatrix = Join-Path $RunDir 'D3_MIRNA_RAW_ANNOTATION_COUNTS_2886x72.csv.gz'
$MirnaMedianMatrix = Join-Path $RunDir 'D3_MIRNA_MATURE_MEDIAN_COUNTS_2656x72.csv.gz'
$MirnaMaxMatrix = Join-Path $RunDir 'D3_MIRNA_MATURE_MAX_SENSITIVITY_COUNTS_2656x72.csv.gz'
$MirnaAnnotation = Join-Path $RunDir 'D3_MIRNA_MATURE_IDENTITY_ANNOTATION.csv'
$QcMetrics = Join-Path $RunDir 'D3_SAMPLE_QC_PREFLIGHT_METRICS.csv'
$MatrixSummary = Join-Path $RunDir 'D3_MATRIX_CONSTRUCTION_SUMMARY.csv'
$ResultJson = Join-Path $RunDir 'D3_RESULT.json'
$PythonLog = Join-Path $RunDir 'D3_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D3_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D3_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D3_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D3-V2 — REAL MATRIX CONSTRUCTION + QC PREFLIGHT ==='
Write-Host 'MODE=REAL_MATRIX_CONSTRUCTION_AND_NONINFERENTIAL_QC'
Write-Host 'REAL_BIOLOGICAL_COUNTS_READ=YES'
Write-Host 'MRNA_RAW_MATRIX_CONSTRUCTION_EXECUTED=YES'
Write-Host 'MIRNA_RAW_MATRIX_CONSTRUCTION_EXECUTED=YES'
Write-Host 'MIRNA_PRIMARY_MEDIAN_CONSOLIDATION_EXECUTED=YES'
Write-Host 'MIRNA_MAX_SENSITIVITY_CONSOLIDATION_EXECUTED=YES'
Write-Host 'MRNA_COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'ZERO_FILL_EXECUTED=NO'
Write-Host 'REAL_NORMALIZATION_EXECUTED=NO'
Write-Host 'FILTERING_EXECUTED=NO'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'DE_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $AcqRoot,
    $D2CManifest,$D2CStrategy,$D2CReport,
    $D2E4Manifest,$D2E4Decision,$D2E4Report,
    $VenvPython
)) {
    if (-not (Test-Path -LiteralPath $p)) {
        throw ('REQUIRED_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D3SHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

# ------------------------------------------------------------
# 1. Re-certify frozen D2C strategy
# ------------------------------------------------------------
$d2c = Get-Content -LiteralPath $D2CReport -Raw
foreach ($tok in @(
    'PHASE_D2C_V2_STATUS=PASS',
    'ADDITIONAL_SAMPLE_LEVEL_COVARIATES_AVAILABLE=NO',
    'DE_MODEL_METADATA_BASIS=DISEASE_STATE_ONLY',
    'MRNA_RAW_FEATURE_KEY=gene_symbol',
    'MRNA_FRACTIONAL_COUNTS_PRESERVED=YES',
    'MRNA_COUNT_ROUNDING_POLICY=PROHIBITED',
    'MIRNA_RAW_FEATURE_KEY=pre-miRNA|MIMAT|mature-miRNA',
    'MIRNA_REGULATORY_IDENTITY_KEY=MIMAT|mature-miRNA',
    'MIRNA_PRIMARY_CONSOLIDATION=MEDIAN_ACROSS_PRECURSOR_ROWS_PER_SAMPLE',
    'MIRNA_SENSITIVITY_CONSOLIDATION=MAX_ACROSS_PRECURSOR_ROWS_PER_SAMPLE',
    'MIRNA_SUM_CONSOLIDATION=PROHIBITED',
    'FEATURE_IDENTITY_STRATEGY_FROZEN=YES',
    'MIRNA_PRIMARY_CONSOLIDATION_FROZEN=YES'
)) {
    if ($d2c -notmatch [regex]::Escape($tok)) {
        throw ('D2C_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$d2cManifestRows = @(Import-Csv -LiteralPath $D2CManifest)
if ($d2cManifestRows.Count -ne 3) {
    throw ('D2C_MANIFEST_ROW_COUNT_CHANGED expected=3 observed={0}' -f $d2cManifestRows.Count)
}

foreach ($r in $d2cManifestRows) {
    if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
        throw ('D2C_OUTPUT_MISSING={0}' -f $r.full_path)
    }
    $item = Get-Item -LiteralPath $r.full_path
    if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
        (Get-D3SHA256 $r.full_path) -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D2C_OUTPUT_CHANGED={0}' -f $r.full_path)
    }
}

Write-Host 'D2C_STRATEGY_CERTIFICATION_GATE=PASS'
Write-Host 'D2C_OUTPUTS_RECERTIFIED=3/3'

# ------------------------------------------------------------
# 2. Re-certify D2E-V4 TMM gate / D3 authorization
# ------------------------------------------------------------
$d2e = Get-Content -LiteralPath $D2E4Report -Raw
foreach ($tok in @(
    'PHASE_D2E_V4_STATUS=PASS',
    'PUBLISHED_TOY_REFERENCE_VALIDATION=PASS',
    'ALL_OFFLINE_TMM_REFERENCE_CHECKS=PASS',
    'ALL_TMM_INVARIANTS=PASS',
    'PYTHON_TMM_REFERENCE_IMPLEMENTATION_VALIDATED=YES',
    'TMM_NORMALIZATION_ENGINE_STATUS=PASS',
    'DGELIST_AUTHORIZED_FOR_FRACTIONAL_REAL_DATA=NO',
    'READY_FOR_PHASE_D3_MATRIX_CONSTRUCTION=YES',
    'READY_FOR_REAL_NORMALIZATION=NO',
    'READY_FOR_REAL_DE=NO',
    'NEXT_PHASE=D3_MATRIX_CONSTRUCTION_AND_QC_PREFLIGHT'
)) {
    if ($d2e -notmatch [regex]::Escape($tok)) {
        throw ('D2E_V4_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$d2eManifestRows = @(Import-Csv -LiteralPath $D2E4Manifest)
if ($d2eManifestRows.Count -ne 6) {
    throw ('D2E_V4_MANIFEST_ROW_COUNT_CHANGED expected=6 observed={0}' -f $d2eManifestRows.Count)
}

foreach ($r in $d2eManifestRows) {
    if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
        throw ('D2E_V4_OUTPUT_MISSING={0}' -f $r.full_path)
    }
    $item = Get-Item -LiteralPath $r.full_path
    if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
        (Get-D3SHA256 $r.full_path) -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D2E_V4_OUTPUT_CHANGED={0}' -f $r.full_path)
    }
}

Write-Host 'D2E_V4_CERTIFICATION_GATE=PASS'
Write-Host 'D2E_V4_OUTPUTS_RECERTIFIED=6/6'

$PythonVersion = & $VenvPython -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$PandasVersion = & $VenvPython -c "import pandas; print(pandas.__version__)"
$NumpyVersion = & $VenvPython -c "import numpy; print(numpy.__version__)"

if ($PythonVersion -ne '3.12.3') {
    throw ('VALIDATED_PYTHON_CHANGED={0}' -f $PythonVersion)
}

Write-Host ('PYTHON_VERSION={0}' -f $PythonVersion)
Write-Host ('PANDAS_VERSION={0}' -f $PandasVersion)
Write-Host ('NUMPY_VERSION={0}' -f $NumpyVersion)

# ------------------------------------------------------------
# 3. Python real matrix construction
# ------------------------------------------------------------
$PythonCode = @'
import csv
import gzip
import hashlib
import json
import math
import re
import sys
from collections import OrderedDict
from pathlib import Path

import numpy as np
import pandas as pd


ACQ_ROOT = Path(sys.argv[1])

SOURCE_INVENTORY = Path(sys.argv[2])
SAMPLE_METADATA = Path(sys.argv[3])
MRNA_MATRIX = Path(sys.argv[4])
MIRNA_RAW_MATRIX = Path(sys.argv[5])
MIRNA_MEDIAN_MATRIX = Path(sys.argv[6])
MIRNA_MAX_MATRIX = Path(sys.argv[7])
MIRNA_ANNOTATION = Path(sys.argv[8])
QC_METRICS = Path(sys.argv[9])
MATRIX_SUMMARY = Path(sys.argv[10])
RESULT_JSON = Path(sys.argv[11])

MRNA_RE = re.compile(
    r"^(?P<gsm>GSM\d+)_(?P<subject>COV\d+|P\d+|H\d+)_raw_count\.txt\.gz$",
    flags=re.IGNORECASE,
)
MIRNA_RE = re.compile(
    r"^(?P<gsm>GSM\d+)_(?P<subject>COV\d+|P\d+|H\d+)_COUNT\.txt\.gz$",
    flags=re.IGNORECASE,
)

EXPECTED_GROUPS = {"COVID19": 35, "SEPSIS": 22, "HEALTHY": 15}

results = {}


def put(k, v):
    results[k] = v
    print(f"{k}={v}")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def subject_info(subject: str):
    s = subject.upper()
    if s.startswith("COV"):
        return "COVID19", int(s[3:]), 0
    if s.startswith("P"):
        return "SEPSIS", int(s[1:]), 1
    if s.startswith("H"):
        return "HEALTHY", int(s[1:]), 2
    raise ValueError(f"unrecognized subject {subject}")


def subject_sort_key(subject: str):
    disease, number, group_order = subject_info(subject)
    return (group_order, number, subject)


# ------------------------------------------------------------
# A. Discover exact processed-count inputs
# ------------------------------------------------------------
mrna_files = {}
mirna_files = {}

for p in ACQ_ROOT.rglob("*.gz"):
    if not p.is_file():
        continue

    m = MRNA_RE.match(p.name)
    if m:
        subject = m.group("subject").upper()
        if subject in mrna_files:
            raise RuntimeError(
                f"DUPLICATE_MRNA_SUBJECT_FILE subject={subject} "
                f"first={mrna_files[subject]} second={p}"
            )
        mrna_files[subject] = p
        continue

    m = MIRNA_RE.match(p.name)
    if m:
        subject = m.group("subject").upper()
        if subject in mirna_files:
            raise RuntimeError(
                f"DUPLICATE_MIRNA_SUBJECT_FILE subject={subject} "
                f"first={mirna_files[subject]} second={p}"
            )
        mirna_files[subject] = p


put("DISCOVERED_MRNA_COUNT_FILES", len(mrna_files))
put("DISCOVERED_MIRNA_COUNT_FILES", len(mirna_files))

if len(mrna_files) != 72:
    raise RuntimeError(f"MRNA_FILE_COUNT_NOT_72 observed={len(mrna_files)}")
if len(mirna_files) != 72:
    raise RuntimeError(f"MIRNA_FILE_COUNT_NOT_72 observed={len(mirna_files)}")

if set(mrna_files) != set(mirna_files):
    missing_mirna = sorted(set(mrna_files) - set(mirna_files))
    missing_mrna = sorted(set(mirna_files) - set(mrna_files))
    raise RuntimeError(
        f"CROSS_MODALITY_SUBJECT_SET_MISMATCH "
        f"missing_mirna={missing_mirna} missing_mrna={missing_mrna}"
    )

subjects = sorted(mrna_files, key=subject_sort_key)

group_counts = {"COVID19": 0, "SEPSIS": 0, "HEALTHY": 0}
for subject in subjects:
    disease, _, _ = subject_info(subject)
    group_counts[disease] += 1

if group_counts != EXPECTED_GROUPS:
    raise RuntimeError(
        f"PHENOTYPE_COUNTS_CHANGED expected={EXPECTED_GROUPS} observed={group_counts}"
    )

put("PAIRED_SUBJECTS", len(subjects))
put("PHENOTYPE_COUNTS", "COVID19=35|SEPSIS=22|HEALTHY=15")


# ------------------------------------------------------------
# B. Source file hash inventory + paired sample metadata
# ------------------------------------------------------------
inventory_rows = []
metadata_rows = []

for subject in subjects:
    disease, subject_number, _ = subject_info(subject)

    for modality, p, regex in (
        ("mRNA", mrna_files[subject], MRNA_RE),
        ("miRNA", mirna_files[subject], MIRNA_RE),
    ):
        m = regex.match(p.name)
        gsm = m.group("gsm").upper()

        inventory_rows.append(
            {
                "modality": modality,
                "subject_id": subject,
                "gsm": gsm,
                "filename": p.name,
                "full_path": str(p),
                "size_bytes": p.stat().st_size,
                "SHA256": sha256_file(p),
            }
        )

    metadata_rows.append(
        {
            "subject_id": subject,
            "subject_number": subject_number,
            "disease_state": disease,
            "mRNA_gsm": MRNA_RE.match(mrna_files[subject].name).group("gsm").upper(),
            "miRNA_gsm": MIRNA_RE.match(mirna_files[subject].name).group("gsm").upper(),
            "mRNA_file": str(mrna_files[subject]),
            "miRNA_file": str(mirna_files[subject]),
        }
    )

pd.DataFrame(inventory_rows).to_csv(SOURCE_INVENTORY, index=False)
pd.DataFrame(metadata_rows).to_csv(SAMPLE_METADATA, index=False)


# ------------------------------------------------------------
# C. mRNA: construct exact raw feature matrix
# ------------------------------------------------------------
mrna_features = None
mrna_columns = OrderedDict()
qc_rows = []

mrna_fractional_total = 0
mrna_negative_total = 0
mrna_nonfinite_total = 0

for idx, subject in enumerate(subjects, start=1):
    p = mrna_files[subject]
    df = pd.read_csv(p, sep="\t", compression="gzip", dtype={0: "string"})

    if df.shape[1] != 2:
        raise RuntimeError(
            f"MRNA_COLUMN_COUNT_NOT_2 subject={subject} observed={df.shape[1]}"
        )

    feature_col = df.columns[0]
    count_col = df.columns[1]

    features = df[feature_col].astype(str).tolist()
    counts = pd.to_numeric(df[count_col], errors="raise").to_numpy(dtype=np.float64)

    if len(features) != 26364:
        raise RuntimeError(
            f"MRNA_FEATURE_COUNT_CHANGED subject={subject} observed={len(features)}"
        )
    if len(set(features)) != len(features):
        raise RuntimeError(f"MRNA_DUPLICATE_FEATURES subject={subject}")
    if any(x == "" or x.lower() == "nan" for x in features):
        raise RuntimeError(f"MRNA_EMPTY_FEATURE subject={subject}")

    if not np.isfinite(counts).all():
        mrna_nonfinite_total += int(np.sum(~np.isfinite(counts)))
        raise RuntimeError(f"MRNA_NONFINITE_COUNT subject={subject}")
    if np.any(counts < 0):
        mrna_negative_total += int(np.sum(counts < 0))
        raise RuntimeError(f"MRNA_NEGATIVE_COUNT subject={subject}")

    if mrna_features is None:
        mrna_features = features
    elif features != mrna_features:
        raise RuntimeError(f"MRNA_FEATURE_ORDER_CHANGED subject={subject}")

    frac_n = int(np.sum(np.abs(counts - np.round(counts)) > 1e-12))
    mrna_fractional_total += frac_n

    mrna_columns[subject] = counts

    disease, _, _ = subject_info(subject)
    qc_rows.append(
        {
            "subject_id": subject,
            "disease_state": disease,
            "modality": "mRNA_raw",
            "feature_count": counts.size,
            "library_sum": float(np.sum(counts)),
            "nonzero_features": int(np.sum(counts > 0)),
            "zero_features": int(np.sum(counts == 0)),
            "zero_fraction": float(np.mean(counts == 0)),
            "min_count": float(np.min(counts)),
            "median_count": float(np.median(counts)),
            "max_count": float(np.max(counts)),
            "fractional_values": frac_n,
        }
    )

    if idx % 12 == 0:
        print(f"MRNA_MATRIX_PROGRESS={idx}/72")


mrna_df = pd.DataFrame(mrna_columns, index=mrna_features)
mrna_df.index.name = "gene_symbol"

if mrna_df.shape != (26364, 72):
    raise RuntimeError(f"MRNA_MATRIX_DIMENSION_WRONG observed={mrna_df.shape}")

# Use 17 significant digits for lossless float64 round-trip.
mrna_df.to_csv(
    MRNA_MATRIX,
    compression="gzip",
    float_format="%.17g",
)

# Round-trip verification.
mrna_rt = pd.read_csv(
    MRNA_MATRIX,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
if list(mrna_rt.index.astype(str)) != mrna_features:
    raise RuntimeError("MRNA_MATRIX_ROUNDTRIP_FEATURE_MISMATCH")
if list(mrna_rt.columns) != subjects:
    raise RuntimeError("MRNA_MATRIX_ROUNDTRIP_SAMPLE_MISMATCH")
if not np.array_equal(
    mrna_rt.to_numpy(dtype=np.float64),
    mrna_df.to_numpy(dtype=np.float64),
):
    maxdiff = float(
        np.max(
            np.abs(
                mrna_rt.to_numpy(dtype=np.float64)
                - mrna_df.to_numpy(dtype=np.float64)
            )
        )
    )
    raise RuntimeError(f"MRNA_MATRIX_ROUNDTRIP_VALUE_MISMATCH maxdiff={maxdiff}")


# ------------------------------------------------------------
# D. miRNA raw annotated matrix + frozen mature consolidations
# ------------------------------------------------------------
raw_keys = None
raw_annotation = None
mirna_raw_columns = OrderedDict()

regulatory_order = None
regulatory_precursors = None
mirna_median_columns = OrderedDict()
mirna_max_columns = OrderedDict()

mirna_raw_fractional_total = 0
mirna_primary_fractional_total = 0

for idx, subject in enumerate(subjects, start=1):
    p = mirna_files[subject]
    df = pd.read_csv(p, sep="\t", compression="gzip", dtype="string")

    if df.shape[1] != 4:
        raise RuntimeError(
            f"MIRNA_COLUMN_COUNT_NOT_4 subject={subject} observed={df.shape[1]}"
        )

    pre_col, mimat_col, mature_col, count_col = list(df.columns)

    pre = df[pre_col].astype(str).tolist()
    mimat = df[mimat_col].astype(str).tolist()
    mature = df[mature_col].astype(str).tolist()
    counts = pd.to_numeric(df[count_col], errors="raise").to_numpy(dtype=np.float64)

    if len(pre) != 2886:
        raise RuntimeError(
            f"MIRNA_RAW_ROW_COUNT_CHANGED subject={subject} observed={len(pre)}"
        )
    if not np.isfinite(counts).all():
        raise RuntimeError(f"MIRNA_NONFINITE_COUNT subject={subject}")
    if np.any(counts < 0):
        raise RuntimeError(f"MIRNA_NEGATIVE_COUNT subject={subject}")

    raw_frac_n = int(np.sum(np.abs(counts - np.round(counts)) > 1e-12))
    mirna_raw_fractional_total += raw_frac_n

    full_keys = [f"{a}|{b}|{c}" for a, b, c in zip(pre, mimat, mature)]
    if len(set(full_keys)) != 2886:
        raise RuntimeError(f"MIRNA_FULL_ANNOTATION_KEY_NOT_UNIQUE subject={subject}")

    if raw_keys is None:
        raw_keys = full_keys
        raw_annotation = list(zip(pre, mimat, mature))
    elif full_keys != raw_keys:
        raise RuntimeError(f"MIRNA_RAW_ANNOTATION_ORDER_CHANGED subject={subject}")

    mirna_raw_columns[subject] = counts

    # Preserve first occurrence order of mature regulatory identity.
    groups = OrderedDict()
    precursor_map = OrderedDict()

    for row_i, (pre_i, mimat_i, mature_i) in enumerate(zip(pre, mimat, mature)):
        reg = f"{mimat_i}|{mature_i}"
        if reg not in groups:
            groups[reg] = []
            precursor_map[reg] = []
        groups[reg].append(row_i)
        precursor_map[reg].append(pre_i)

    current_order = list(groups.keys())

    if len(current_order) != 2656:
        raise RuntimeError(
            f"MIRNA_REGULATORY_IDENTITY_COUNT_CHANGED "
            f"subject={subject} observed={len(current_order)}"
        )

    if regulatory_order is None:
        regulatory_order = current_order
        regulatory_precursors = {
            reg: list(precursor_map[reg]) for reg in current_order
        }
    elif current_order != regulatory_order:
        raise RuntimeError(f"MIRNA_REGULATORY_IDENTITY_ORDER_CHANGED subject={subject}")

    med = np.empty(len(regulatory_order), dtype=np.float64)
    mx = np.empty(len(regulatory_order), dtype=np.float64)

    for out_i, reg in enumerate(regulatory_order):
        vals = counts[groups[reg]]
        med[out_i] = float(np.median(vals))
        mx[out_i] = float(np.max(vals))

    med_frac_n = int(np.sum(np.abs(med - np.round(med)) > 1e-12))
    mirna_primary_fractional_total += med_frac_n

    mirna_median_columns[subject] = med
    mirna_max_columns[subject] = mx

    disease, _, _ = subject_info(subject)

    qc_rows.append(
        {
            "subject_id": subject,
            "disease_state": disease,
            "modality": "miRNA_raw_2886",
            "feature_count": counts.size,
            "library_sum": float(np.sum(counts)),
            "nonzero_features": int(np.sum(counts > 0)),
            "zero_features": int(np.sum(counts == 0)),
            "zero_fraction": float(np.mean(counts == 0)),
            "min_count": float(np.min(counts)),
            "median_count": float(np.median(counts)),
            "max_count": float(np.max(counts)),
            "fractional_values": raw_frac_n,
        }
    )

    qc_rows.append(
        {
            "subject_id": subject,
            "disease_state": disease,
            "modality": "miRNA_mature_median_primary",
            "feature_count": med.size,
            "library_sum": float(np.sum(med)),
            "nonzero_features": int(np.sum(med > 0)),
            "zero_features": int(np.sum(med == 0)),
            "zero_fraction": float(np.mean(med == 0)),
            "min_count": float(np.min(med)),
            "median_count": float(np.median(med)),
            "max_count": float(np.max(med)),
            "fractional_values": med_frac_n,
        }
    )

    qc_rows.append(
        {
            "subject_id": subject,
            "disease_state": disease,
            "modality": "miRNA_mature_max_sensitivity",
            "feature_count": mx.size,
            "library_sum": float(np.sum(mx)),
            "nonzero_features": int(np.sum(mx > 0)),
            "zero_features": int(np.sum(mx == 0)),
            "zero_fraction": float(np.mean(mx == 0)),
            "min_count": float(np.min(mx)),
            "median_count": float(np.median(mx)),
            "max_count": float(np.max(mx)),
            "fractional_values": int(
                np.sum(np.abs(mx - np.round(mx)) > 1e-12)
            ),
        }
    )

    if idx % 12 == 0:
        print(f"MIRNA_MATRIX_PROGRESS={idx}/72")


mirna_raw_df = pd.DataFrame(mirna_raw_columns, index=raw_keys)
mirna_raw_df.index.name = "pre-miRNA|MIMAT|mature-miRNA"

mirna_median_df = pd.DataFrame(mirna_median_columns, index=regulatory_order)
mirna_median_df.index.name = "MIMAT|mature-miRNA"

mirna_max_df = pd.DataFrame(mirna_max_columns, index=regulatory_order)
mirna_max_df.index.name = "MIMAT|mature-miRNA"

if mirna_raw_df.shape != (2886, 72):
    raise RuntimeError(f"MIRNA_RAW_MATRIX_DIMENSION_WRONG observed={mirna_raw_df.shape}")
if mirna_median_df.shape != (2656, 72):
    raise RuntimeError(
        f"MIRNA_PRIMARY_MATRIX_DIMENSION_WRONG observed={mirna_median_df.shape}"
    )
if mirna_max_df.shape != (2656, 72):
    raise RuntimeError(
        f"MIRNA_MAX_MATRIX_DIMENSION_WRONG observed={mirna_max_df.shape}"
    )

mirna_raw_df.to_csv(
    MIRNA_RAW_MATRIX,
    compression="gzip",
    float_format="%.17g",
)
mirna_median_df.to_csv(
    MIRNA_MEDIAN_MATRIX,
    compression="gzip",
    float_format="%.17g",
)
mirna_max_df.to_csv(
    MIRNA_MAX_MATRIX,
    compression="gzip",
    float_format="%.17g",
)

# Mature identity annotation map.
annotation_rows = []
for reg in regulatory_order:
    mimat, mature = reg.split("|", 1)
    precursors = regulatory_precursors[reg]
    annotation_rows.append(
        {
            "regulatory_identity": reg,
            "MIMAT": mimat,
            "mature_miRNA": mature,
            "precursor_row_count": len(precursors),
            "precursor_ids": "|".join(precursors),
            "is_repeated_across_precursors": "YES" if len(precursors) > 1 else "NO",
        }
    )

annotation_df = pd.DataFrame(annotation_rows)
annotation_df.to_csv(MIRNA_ANNOTATION, index=False)

repeated_identity_count = int(
    np.sum(annotation_df["precursor_row_count"].to_numpy(dtype=int) > 1)
)
if repeated_identity_count != 166:
    raise RuntimeError(
        f"MIRNA_REPEATED_IDENTITY_COUNT_CHANGED observed={repeated_identity_count}"
    )

# Round-trip verification for miRNA matrices.
for path, original, expected_rows, expected_index in (
    (MIRNA_RAW_MATRIX, mirna_raw_df, 2886, raw_keys),
    (MIRNA_MEDIAN_MATRIX, mirna_median_df, 2656, regulatory_order),
    (MIRNA_MAX_MATRIX, mirna_max_df, 2656, regulatory_order),
):
    rt = pd.read_csv(
        path,
        index_col=0,
        compression="gzip",
        engine="c",
        float_precision="round_trip",
    )

    if rt.shape != (expected_rows, 72):
        raise RuntimeError(f"MIRNA_MATRIX_ROUNDTRIP_SHAPE_MISMATCH file={path.name}")
    if list(rt.index.astype(str)) != expected_index:
        raise RuntimeError(f"MIRNA_MATRIX_ROUNDTRIP_INDEX_MISMATCH file={path.name}")
    if list(rt.columns) != subjects:
        raise RuntimeError(f"MIRNA_MATRIX_ROUNDTRIP_SAMPLE_MISMATCH file={path.name}")

    if not np.array_equal(
        rt.to_numpy(dtype=np.float64),
        original.to_numpy(dtype=np.float64),
    ):
        maxdiff = float(
            np.max(
                np.abs(
                    rt.to_numpy(dtype=np.float64)
                    - original.to_numpy(dtype=np.float64)
                )
            )
        )
        raise RuntimeError(
            f"MIRNA_MATRIX_ROUNDTRIP_VALUE_MISMATCH file={path.name} maxdiff={maxdiff}"
        )


# ------------------------------------------------------------
# E. QC outputs (descriptive only; no thresholds/exclusions)
# ------------------------------------------------------------
qc_df = pd.DataFrame(qc_rows)
qc_df.to_csv(QC_METRICS, index=False)

summary_rows = [
    {
        "matrix": "mRNA_raw",
        "feature_rows": 26364,
        "samples": 72,
        "feature_identity": "gene_symbol",
        "consolidation": "NONE",
        "normalization": "NONE",
        "fractional_values": mrna_fractional_total,
    },
    {
        "matrix": "miRNA_raw_annotation",
        "feature_rows": 2886,
        "samples": 72,
        "feature_identity": "pre-miRNA|MIMAT|mature-miRNA",
        "consolidation": "NONE",
        "normalization": "NONE",
        "fractional_values": mirna_raw_fractional_total,
    },
    {
        "matrix": "miRNA_mature_median_primary",
        "feature_rows": 2656,
        "samples": 72,
        "feature_identity": "MIMAT|mature-miRNA",
        "consolidation": "MEDIAN_ACROSS_PRECURSOR_ROWS_PER_SAMPLE",
        "normalization": "NONE",
        "fractional_values": mirna_primary_fractional_total,
    },
    {
        "matrix": "miRNA_mature_max_sensitivity",
        "feature_rows": 2656,
        "samples": 72,
        "feature_identity": "MIMAT|mature-miRNA",
        "consolidation": "MAX_ACROSS_PRECURSOR_ROWS_PER_SAMPLE",
        "normalization": "NONE",
        "fractional_values": 0,
    },
]
pd.DataFrame(summary_rows).to_csv(MATRIX_SUMMARY, index=False)


# ------------------------------------------------------------
# F. Final hard gates
# ------------------------------------------------------------
if mrna_fractional_total != 355532:
    raise RuntimeError(
        f"MRNA_FRACTIONAL_VALUE_COUNT_CHANGED "
        f"expected=355532 observed={mrna_fractional_total}"
    )

if mirna_raw_fractional_total != 0:
    raise RuntimeError(
        f"MIRNA_RAW_FRACTIONAL_VALUES_UNEXPECTED observed={mirna_raw_fractional_total}"
    )

if subjects != list(mrna_df.columns):
    raise RuntimeError("MRNA_SAMPLE_ORDER_MISMATCH")
if subjects != list(mirna_median_df.columns):
    raise RuntimeError("MIRNA_PRIMARY_SAMPLE_ORDER_MISMATCH")

put("SOURCE_COUNT_FILES_HASHED", 144)
put("MRNA_MATRIX_ROWS", 26364)
put("MRNA_MATRIX_SAMPLES", 72)
put("MRNA_FRACTIONAL_VALUES", mrna_fractional_total)
put("MIRNA_RAW_MATRIX_ROWS", 2886)
put("MIRNA_RAW_MATRIX_SAMPLES", 72)
put("MIRNA_RAW_FRACTIONAL_VALUES", mirna_raw_fractional_total)
put("MIRNA_MATURE_PRIMARY_ROWS", 2656)
put("MIRNA_REPEATED_REGULATORY_IDENTITIES", repeated_identity_count)
put("MIRNA_PRIMARY_MEDIAN_FRACTIONAL_VALUES", mirna_primary_fractional_total)
put("MIRNA_MATURE_MAX_SENSITIVITY_ROWS", 2656)
put("CROSS_MODALITY_MATRIX_SAMPLE_ORDER_IDENTICAL", "YES")
put("MATRIX_ROUNDTRIP_INTEGRITY", "PASS")
put("QC_METRICS_ROWS", int(qc_df.shape[0]))
put("REAL_NORMALIZATION_EXECUTED", "NO")
put("FILTERING_EXECUTED", "NO")
put("SAMPLE_EXCLUSION_EXECUTED", "NO")
put("DE_EXECUTED", "NO")

RESULT_JSON.write_text(
    json.dumps({"results": results}, indent=2, sort_keys=True),
    encoding="utf-8",
)
'@

$PythonCode | Set-Content -LiteralPath $PyScript -Encoding UTF8

$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

# Use redirected native-process streams so PowerShell cannot truncate
# Python tracebacks into a single NativeCommandError line.
$PythonStdout = Join-Path $RunDir 'D3_V2_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D3_V2_PYTHON_STDERR.txt'

$PythonArgs = @(
    '-u',
    $PyScript,
    $AcqRoot,
    $SourceInventory,
    $SampleMetadata,
    $MrnaMatrix,
    $MirnaRawMatrix,
    $MirnaMedianMatrix,
    $MirnaMaxMatrix,
    $MirnaAnnotation,
    $QcMetrics,
    $MatrixSummary,
    $ResultJson
)

$proc = Start-Process `
    -FilePath $VenvPython `
    -ArgumentList $PythonArgs `
    -Wait `
    -PassThru `
    -NoNewWindow `
    -RedirectStandardOutput $PythonStdout `
    -RedirectStandardError $PythonStderr

$PythonExit = [int]$proc.ExitCode

$stdoutLines = @()
$stderrLines = @()

if (Test-Path -LiteralPath $PythonStdout -PathType Leaf) {
    $stdoutLines = @(Get-Content -LiteralPath $PythonStdout)
    foreach ($line in $stdoutLines) {
        Write-Host $line
    }
}

if (Test-Path -LiteralPath $PythonStderr -PathType Leaf) {
    $stderrLines = @(Get-Content -LiteralPath $PythonStderr)
    if ($stderrLines.Count -gt 0) {
        Write-Host '=== D3-V2 PYTHON STDERR ==='
        foreach ($line in $stderrLines) {
            Write-Host $line
        }
    }
}

@(
    '=== STDOUT ==='
    $stdoutLines
    ''
    '=== STDERR ==='
    $stderrLines
) | Set-Content -LiteralPath $PythonLog -Encoding UTF8

if ($PythonExit -ne 0) {
    throw ('D3_V2_PYTHON_MATRIX_CONSTRUCTION_FAILED exit={0} full_traceback={1}' -f $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D3_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('SOURCE_COUNT_FILES_HASHED','144'),
    @('MRNA_MATRIX_ROWS','26364'),
    @('MRNA_MATRIX_SAMPLES','72'),
    @('MRNA_FRACTIONAL_VALUES','355532'),
    @('MIRNA_RAW_MATRIX_ROWS','2886'),
    @('MIRNA_RAW_MATRIX_SAMPLES','72'),
    @('MIRNA_RAW_FRACTIONAL_VALUES','0'),
    @('MIRNA_MATURE_PRIMARY_ROWS','2656'),
    @('MIRNA_REPEATED_REGULATORY_IDENTITIES','166'),
    @('MIRNA_MATURE_MAX_SENSITIVITY_ROWS','2656'),
    @('CROSS_MODALITY_MATRIX_SAMPLE_ORDER_IDENTICAL','YES'),
    @('MATRIX_ROUNDTRIP_INTEGRITY','PASS'),
    @('REAL_NORMALIZATION_EXECUTED','NO'),
    @('FILTERING_EXECUTED','NO'),
    @('SAMPLE_EXCLUSION_EXECUTED','NO'),
    @('DE_EXECUTED','NO')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D3_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 4. D3 decision
# ------------------------------------------------------------
@(
    'GSE243219_D3_V2_DECISION',
    'PHASE_D3_V2_STATUS=PASS',
    'MODE=REAL_MATRIX_CONSTRUCTION_AND_NONINFERENTIAL_QC',
    'REAL_BIOLOGICAL_COUNTS_READ=YES',
    'MRNA_RAW_MATRIX_CONSTRUCTION_EXECUTED=YES',
    'MIRNA_RAW_MATRIX_CONSTRUCTION_EXECUTED=YES',
    'MIRNA_PRIMARY_MEDIAN_CONSOLIDATION_EXECUTED=YES',
    'MIRNA_MAX_SENSITIVITY_CONSOLIDATION_EXECUTED=YES',
    'MRNA_COUNT_ROUNDING_EXECUTED=NO',
    'ZERO_FILL_EXECUTED=NO',
    'REAL_NORMALIZATION_EXECUTED=NO',
    'FILTERING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'D2C_STRATEGY_CERTIFICATION_GATE=PASS',
    'D2E_V4_CERTIFICATION_GATE=PASS',
    ('MRNA_MATRIX_ROWS={0}' -f (Cap 'MRNA_MATRIX_ROWS')),
    ('MRNA_MATRIX_SAMPLES={0}' -f (Cap 'MRNA_MATRIX_SAMPLES')),
    ('MRNA_FRACTIONAL_VALUES={0}' -f (Cap 'MRNA_FRACTIONAL_VALUES')),
    ('MIRNA_RAW_MATRIX_ROWS={0}' -f (Cap 'MIRNA_RAW_MATRIX_ROWS')),
    ('MIRNA_MATURE_PRIMARY_ROWS={0}' -f (Cap 'MIRNA_MATURE_PRIMARY_ROWS')),
    ('MIRNA_REPEATED_REGULATORY_IDENTITIES={0}' -f (Cap 'MIRNA_REPEATED_REGULATORY_IDENTITIES')),
    ('MIRNA_PRIMARY_MEDIAN_FRACTIONAL_VALUES={0}' -f (Cap 'MIRNA_PRIMARY_MEDIAN_FRACTIONAL_VALUES')),
    'MIRNA_PRIMARY_CONSOLIDATION=MEDIAN_ACROSS_PRECURSOR_ROWS_PER_SAMPLE',
    'MIRNA_SENSITIVITY_CONSOLIDATION=MAX_ACROSS_PRECURSOR_ROWS_PER_SAMPLE',
    'MIRNA_SUM_CONSOLIDATION=PROHIBITED',
    'CROSS_MODALITY_MATRIX_SAMPLE_ORDER_IDENTICAL=YES',
    'MATRIX_ROUNDTRIP_INTEGRITY=PASS',
    'CSV_FLOAT_ROUNDTRIP_PARSER=PANDAS_C_ENGINE_ROUND_TRIP',
    'MATRIX_CONSTRUCTION_COMPLETE=YES',
    'QC_PREFLIGHT_METRICS_COMPLETE=YES',
    'READY_FOR_QC_REVIEW_AND_FILTER_DESIGN=YES',
    'READY_FOR_REAL_NORMALIZATION=NO',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D3A_QC_REVIEW_AND_PROSPECTIVE_FILTER_DESIGN',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 5. Hash all D3 outputs
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $SourceInventory,
    $SampleMetadata,
    $MrnaMatrix,
    $MirnaRawMatrix,
    $MirnaMedianMatrix,
    $MirnaMaxMatrix,
    $MirnaAnnotation,
    $QcMetrics,
    $MatrixSummary,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D3_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p

    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D3SHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 6. Final summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D3-V2 SUMMARY ===',
    'PHASE_D3_V2_STATUS=PASS',
    'MODE=REAL_MATRIX_CONSTRUCTION_AND_NONINFERENTIAL_QC',
    'REAL_BIOLOGICAL_COUNTS_READ=YES',
    'MRNA_RAW_MATRIX_CONSTRUCTION_EXECUTED=YES',
    'MIRNA_RAW_MATRIX_CONSTRUCTION_EXECUTED=YES',
    'MIRNA_PRIMARY_MEDIAN_CONSOLIDATION_EXECUTED=YES',
    'MIRNA_MAX_SENSITIVITY_CONSOLIDATION_EXECUTED=YES',
    'MRNA_COUNT_ROUNDING_EXECUTED=NO',
    'ZERO_FILL_EXECUTED=NO',
    'REAL_NORMALIZATION_EXECUTED=NO',
    'FILTERING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'D2C_STRATEGY_CERTIFICATION_GATE=PASS',
    'D2C_OUTPUTS_RECERTIFIED=3/3',
    'D2E_V4_CERTIFICATION_GATE=PASS',
    'D2E_V4_OUTPUTS_RECERTIFIED=6/6',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    ('SOURCE_COUNT_FILES_HASHED={0}' -f (Cap 'SOURCE_COUNT_FILES_HASHED')),
    'PAIRED_SUBJECTS=72',
    'PHENOTYPE_COUNTS=COVID19=35|SEPSIS=22|HEALTHY=15',
    ('MRNA_MATRIX_ROWS={0}' -f (Cap 'MRNA_MATRIX_ROWS')),
    ('MRNA_MATRIX_SAMPLES={0}' -f (Cap 'MRNA_MATRIX_SAMPLES')),
    ('MRNA_FRACTIONAL_VALUES={0}' -f (Cap 'MRNA_FRACTIONAL_VALUES')),
    ('MIRNA_RAW_MATRIX_ROWS={0}' -f (Cap 'MIRNA_RAW_MATRIX_ROWS')),
    ('MIRNA_RAW_MATRIX_SAMPLES={0}' -f (Cap 'MIRNA_RAW_MATRIX_SAMPLES')),
    ('MIRNA_RAW_FRACTIONAL_VALUES={0}' -f (Cap 'MIRNA_RAW_FRACTIONAL_VALUES')),
    ('MIRNA_MATURE_PRIMARY_ROWS={0}' -f (Cap 'MIRNA_MATURE_PRIMARY_ROWS')),
    ('MIRNA_REPEATED_REGULATORY_IDENTITIES={0}' -f (Cap 'MIRNA_REPEATED_REGULATORY_IDENTITIES')),
    ('MIRNA_PRIMARY_MEDIAN_FRACTIONAL_VALUES={0}' -f (Cap 'MIRNA_PRIMARY_MEDIAN_FRACTIONAL_VALUES')),
    ('MIRNA_MATURE_MAX_SENSITIVITY_ROWS={0}' -f (Cap 'MIRNA_MATURE_MAX_SENSITIVITY_ROWS')),
    'CROSS_MODALITY_MATRIX_SAMPLE_ORDER_IDENTICAL=YES',
    'MATRIX_ROUNDTRIP_INTEGRITY=PASS',
    ('QC_METRICS_ROWS={0}' -f (Cap 'QC_METRICS_ROWS')),
    'MATRIX_CONSTRUCTION_COMPLETE=YES',
    'QC_PREFLIGHT_METRICS_COMPLETE=YES',
    'READY_FOR_QC_REVIEW_AND_FILTER_DESIGN=YES',
    'READY_FOR_REAL_NORMALIZATION=NO',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D3A_QC_REVIEW_AND_PROSPECTIVE_FILTER_DESIGN',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D3_SOURCE_INVENTORY={0}' -f $SourceInventory)
Write-Host ('D3_SAMPLE_METADATA={0}' -f $SampleMetadata)
Write-Host ('D3_MRNA_RAW_MATRIX={0}' -f $MrnaMatrix)
Write-Host ('D3_MIRNA_RAW_MATRIX={0}' -f $MirnaRawMatrix)
Write-Host ('D3_MIRNA_PRIMARY_MEDIAN_MATRIX={0}' -f $MirnaMedianMatrix)
Write-Host ('D3_MIRNA_MAX_SENSITIVITY_MATRIX={0}' -f $MirnaMaxMatrix)
Write-Host ('D3_MIRNA_ANNOTATION={0}' -f $MirnaAnnotation)
Write-Host ('D3_QC_METRICS={0}' -f $QcMetrics)
Write-Host ('D3_MATRIX_SUMMARY={0}' -f $MatrixSummary)
Write-Host ('D3_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D3_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D3_V2=PASS'
Write-Host 'STOP=YES'
