$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D4 — NORMALIZATION CERTIFICATION
#            + DE INPUT BUNDLE FREEZE
#
# Creates a self-contained, immutable-by-manifest DE input bundle.
#
# Authorized:
#   - re-certify D2C, D2D1, D3B, D3C
#   - copy the already-filtered RAW count matrices byte-for-byte
#   - freeze the 72-subject cohort metadata
#   - certify TMM factors / effective library sizes
#   - compute log(effective library size) offset vectors
#   - freeze a no-intercept 3-group design matrix
#   - freeze the three planned pairwise contrast vectors
#
# Prohibited:
#   - count rounding
#   - re-filtering
#   - recomputing TMM factors
#   - sample exclusion
#   - DE
#   - network construction
#   - A-CLA
#
# Later DE input:
#   filtered RAW fractional counts
#   + design matrix
#   + contrast vector
#   + log(effective library size) offsets
#
# Normalized CPM/logCPM are QC-only and are NOT DE inputs.
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'

$D2Root = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING'
$D3Root = Join-Path $Project '03_QC_AND_FILTERING'
$D4Root = Join-Path $Project '04_NORMALIZATION'

$D2CRun = Join-Path $D2Root 'D2C_STRATEGY_20260904_194630'
$D2CManifest = Join-Path $D2CRun 'D2C_OUTPUT_SHA256_MANIFEST.csv'
$D2CReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D2C_20260904_194630\PHASE_D2C_SUMMARY.txt'

$D2D1Run = Join-Path $D2Root 'D2D1_LOW_LEVEL_PREFLIGHT_20260904_201625'
$D2D1Manifest = Join-Path $D2D1Run 'D2D1_OUTPUT_SHA256_MANIFEST.csv'
$D2D1Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D2D1_20260904_201625\PHASE_D2D1_SUMMARY.txt'

$D3BRun = Join-Path $D3Root 'D3B_FILTER_TMM_SAMPLE_QC_20260905_092809'
$D3BManifest = Join-Path $D3BRun 'D3B_OUTPUT_SHA256_MANIFEST.csv'
$D3BReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D3B_20260905_092809\PHASE_D3B_SUMMARY.txt'
$MrnaFilteredSource = Join-Path $D3BRun 'D3B_MRNA_FILTERED_RAW_COUNTS_15083x72.csv.gz'
$MirnaFilteredSource = Join-Path $D3BRun 'D3B_MIRNA_FILTERED_RAW_COUNTS_428x72.csv.gz'
$NormTableSource = Join-Path $D3BRun 'D3B_TMM_NORMALIZATION_FACTORS_AND_LIBRARY_SIZES.csv'

$D3CRun = Join-Path $D3Root 'D3C_COHORT_FREEZE_20260905_093415'
$D3CManifest = Join-Path $D3CRun 'D3C_OUTPUT_SHA256_MANIFEST.csv'
$D3CReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D3C_20260905_093415\PHASE_D3C_SUMMARY.txt'
$FrozenCohortSource = Join-Path $D3CRun 'D3C_FROZEN_ANALYSIS_COHORT.csv'
$CohortFreezeSource = Join-Path $D3CRun 'D3C_ANALYSIS_COHORT_FREEZE.txt'

$D2DRun = Join-Path $D2Root 'D2D_PREFLIGHT_20260904_195001'
$VenvPython = Join-Path $D2DRun 'venv\Scripts\python.exe'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D4Root ('D4_DE_INPUT_BUNDLE_FREEZE_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D4_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D4_NORMALIZATION_CERTIFICATION_AND_DE_INPUT_BUNDLE_FREEZE.py'

$MrnaBundle = Join-Path $RunDir 'D4_MRNA_FILTERED_RAW_COUNTS_DE_INPUT_15083x72.csv.gz'
$MirnaBundle = Join-Path $RunDir 'D4_MIRNA_FILTERED_RAW_COUNTS_DE_INPUT_428x72.csv.gz'
$CohortBundle = Join-Path $RunDir 'D4_FROZEN_ANALYSIS_COHORT_72.csv'
$OffsetTable = Join-Path $RunDir 'D4_DE_EFFECTIVE_LIBRARY_AND_OFFSET_TABLE.csv'
$DesignMatrix = Join-Path $RunDir 'D4_DE_DESIGN_MATRIX_GROUP_MEANS_72x3.csv'
$ContrastMatrix = Join-Path $RunDir 'D4_DE_CONTRAST_MATRIX.csv'
$EngineSpec = Join-Path $RunDir 'D4_DE_ENGINE_AND_INPUT_SPECIFICATION.txt'
$BundleInventory = Join-Path $RunDir 'D4_DE_INPUT_BUNDLE_INVENTORY.csv'

$ResultJson = Join-Path $RunDir 'D4_RESULT.json'
$PythonStdout = Join-Path $RunDir 'D4_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D4_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D4_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D4_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D4_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D4_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D4 — NORMALIZATION CERTIFICATION + DE INPUT BUNDLE FREEZE ==='
Write-Host 'MODE=CERTIFICATION_AND_BUNDLE_FREEZE_ONLY'
Write-Host 'REAL_FILTERED_RAW_COUNTS_READ=YES'
Write-Host 'REAL_FILTERED_RAW_COUNTS_COPIED_BYTE_FOR_BYTE=YES'
Write-Host 'TMM_FACTORS_RECOMPUTED=NO'
Write-Host 'TMM_FACTORS_CERTIFIED=YES'
Write-Host 'EFFECTIVE_LIBRARY_OFFSETS_COMPUTED=YES'
Write-Host 'DESIGN_MATRIX_FROZEN=YES'
Write-Host 'CONTRAST_MATRIX_FROZEN=YES'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'MRNA_COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'DE_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $D2CManifest,$D2CReport,
    $D2D1Manifest,$D2D1Report,
    $D3BManifest,$D3BReport,
    $MrnaFilteredSource,$MirnaFilteredSource,$NormTableSource,
    $D3CManifest,$D3CReport,$FrozenCohortSource,$CohortFreezeSource,
    $VenvPython
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D4_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D4SHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Recertify-Manifest {
    param(
        [string]$ManifestPath,
        [int]$ExpectedRows,
        [string]$Label
    )

    $rows = @(Import-Csv -LiteralPath $ManifestPath)

    if ($rows.Count -ne $ExpectedRows) {
        throw ('{0}_MANIFEST_ROW_COUNT_CHANGED expected={1} observed={2}' -f `
            $Label,$ExpectedRows,$rows.Count)
    }

    foreach ($r in $rows) {
        if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
            throw ('{0}_OUTPUT_MISSING={1}' -f $Label,$r.full_path)
        }

        $item = Get-Item -LiteralPath $r.full_path
        $hash = Get-D4SHA256 $r.full_path

        if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
            $hash -ne $r.SHA256.ToLowerInvariant()) {
            throw ('{0}_OUTPUT_CHANGED={1}' -f $Label,$r.full_path)
        }
    }

    Write-Host ('{0}_OUTPUTS_RECERTIFIED={1}/{1}' -f $Label,$ExpectedRows)
}

# ------------------------------------------------------------
# 1. Re-certify frozen strategy / engine / data / cohort
# ------------------------------------------------------------
$d2c = Get-Content -LiteralPath $D2CReport -Raw
foreach ($tok in @(
    'PHASE_D2C_V2_STATUS=PASS',
    'DE_MODEL_METADATA_BASIS=DISEASE_STATE_ONLY',
    'PRIMARY_CONTRAST=COV_vs_H',
    'SEPSIS_COMPARATOR_CONTRAST=P_vs_H',
    'COVID_SPECIFICITY_CONTRAST=COV_vs_P',
    'MRNA_FRACTIONAL_COUNTS_PRESERVED=YES',
    'MRNA_COUNT_ROUNDING_POLICY=PROHIBITED',
    'MIRNA_PRIMARY_CONSOLIDATION=MEDIAN_ACROSS_PRECURSOR_ROWS_PER_SAMPLE',
    'PRIMARY_DE_STATISTICAL_FAMILY=EDGER_STYLE_NEGATIVE_BINOMIAL_QUASI_LIKELIHOOD',
    'NORMALIZATION_TARGET=TMM_STYLE_EFFECTIVE_LIBRARY_SIZE',
    'DESEQ2_PYDESEQ2_PRIMARY_ENGINE=NO',
    'FEATURE_IDENTITY_STRATEGY_FROZEN=YES',
    'DE_STATISTICAL_FAMILY_FROZEN=YES'
)) {
    if ($d2c -notmatch [regex]::Escape($tok)) {
        throw ('D2C_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}
Recertify-Manifest -ManifestPath $D2CManifest -ExpectedRows 3 -Label 'D2C'
Write-Host 'D2C_STRATEGY_CERTIFICATION_GATE=PASS'

$d2d1 = Get-Content -LiteralPath $D2D1Report -Raw
foreach ($tok in @(
    'PHASE_D2D1_STATUS=PASS',
    'DGELIST_AUTHORIZED_FOR_FRACTIONAL_REAL_DATA=NO',
    'LOW_LEVEL_GLMFIT_FRACTIONAL_COUNTS_PRESERVED=YES',
    'LOW_LEVEL_GLMFIT_FRACTIONAL_NUMERICAL_EFFECT_VERIFIED=YES',
    'LOW_LEVEL_EFFECTIVE_LIBRARY_OFFSET_PRESERVED=YES',
    'LOW_LEVEL_COMMON_DISPERSION_FRACTIONAL=PASS',
    'LOW_LEVEL_GLMQLFIT_FRACTIONAL=PASS',
    'LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_TRUE=PASS',
    'LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_FALSE=PASS',
    'LOW_LEVEL_FRACTIONAL_QL_PIPELINE_CAPABILITY_VERIFIED=YES'
)) {
    if ($d2d1 -notmatch [regex]::Escape($tok)) {
        throw ('D2D1_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}
Recertify-Manifest -ManifestPath $D2D1Manifest -ExpectedRows 5 -Label 'D2D1'
Write-Host 'D2D1_ENGINE_CERTIFICATION_GATE=PASS'

$d3b = Get-Content -LiteralPath $D3BReport -Raw
foreach ($tok in @(
    'PHASE_D3B_STATUS=PASS',
    'MRNA_FILTERED_FEATURES=15083',
    'MIRNA_FILTERED_FEATURES=428',
    'FILTERED_SAMPLE_COUNT=72',
    'FILTERED_RAW_MATRIX_ROUNDTRIP_INTEGRITY=PASS',
    'POST_FILTER_LIBRARY_SIZES_RECOMPUTED=YES',
    'TMM_NORMALIZATION_EXECUTED=YES',
    'TMM_IMPLEMENTATION_SOURCE=D2E_V4_VALIDATED_EDGE_STYLE_FUNCTION',
    'MRNA_TMM_FACTOR_GEOMEAN=1.0',
    'MIRNA_TMM_FACTOR_GEOMEAN=1.0',
    'ALL_72_SAMPLES_RETAINED=YES',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'MRNA_COUNT_ROUNDING_EXECUTED=NO',
    'DE_EXECUTED=NO'
)) {
    if ($d3b -notmatch [regex]::Escape($tok)) {
        throw ('D3B_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}
Recertify-Manifest -ManifestPath $D3BManifest -ExpectedRows 18 -Label 'D3B'
Write-Host 'D3B_DATA_NORMALIZATION_CERTIFICATION_GATE=PASS'

$d3c = Get-Content -LiteralPath $D3CReport -Raw
foreach ($tok in @(
    'PHASE_D3C_STATUS=PASS',
    'HARD_MATRIX_INTEGRITY_GATE=PASS',
    'TRACEABLE_TECHNICAL_FAILURE_AVAILABLE=NO',
    'HARD_INTEGRITY_FAILURES=0',
    'ANALYSIS_COHORT_FROZEN=YES',
    'ANALYSIS_COHORT_SUBJECTS=72',
    'ANALYSIS_COHORT_COVID19=35',
    'ANALYSIS_COHORT_SEPSIS=22',
    'ANALYSIS_COHORT_HEALTHY=15',
    'EXCLUDED_SUBJECTS=NONE',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'FEATURE_FILTER_CHANGED=NO',
    'TMM_FACTORS_CHANGED=NO',
    'READY_FOR_D4_DE_INPUT_BUNDLE_FREEZE=YES',
    'NEXT_PHASE=D4_NORMALIZATION_CERTIFICATION_AND_DE_INPUT_BUNDLE_FREEZE'
)) {
    if ($d3c -notmatch [regex]::Escape($tok)) {
        throw ('D3C_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}
Recertify-Manifest -ManifestPath $D3CManifest -ExpectedRows 11 -Label 'D3C'
Write-Host 'D3C_COHORT_CERTIFICATION_GATE=PASS'

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
# 2. Python D4 bundle freeze
# ------------------------------------------------------------
$PythonCode = @'
import hashlib
import json
import shutil
import sys
from pathlib import Path

import numpy as np
import pandas as pd


MRNA_SOURCE = Path(sys.argv[1])
MIRNA_SOURCE = Path(sys.argv[2])
NORM_SOURCE = Path(sys.argv[3])
COHORT_SOURCE = Path(sys.argv[4])

MRNA_BUNDLE = Path(sys.argv[5])
MIRNA_BUNDLE = Path(sys.argv[6])
COHORT_BUNDLE = Path(sys.argv[7])
OFFSET_TABLE = Path(sys.argv[8])
DESIGN_MATRIX = Path(sys.argv[9])
CONTRAST_MATRIX = Path(sys.argv[10])
ENGINE_SPEC = Path(sys.argv[11])
BUNDLE_INVENTORY = Path(sys.argv[12])
RESULT_JSON = Path(sys.argv[13])


results = {}


def put(k, v):
    results[k] = v
    print(f"{k}={v}")


def sha256_file(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


# ------------------------------------------------------------
# A. Byte-for-byte frozen copies of filtered RAW count matrices
# ------------------------------------------------------------
shutil.copyfile(MRNA_SOURCE, MRNA_BUNDLE)
shutil.copyfile(MIRNA_SOURCE, MIRNA_BUNDLE)

mrna_source_hash = sha256_file(MRNA_SOURCE)
mrna_bundle_hash = sha256_file(MRNA_BUNDLE)
mirna_source_hash = sha256_file(MIRNA_SOURCE)
mirna_bundle_hash = sha256_file(MIRNA_BUNDLE)

if mrna_source_hash != mrna_bundle_hash:
    raise RuntimeError("MRNA_BYTE_FOR_BYTE_COPY_HASH_MISMATCH")
if mirna_source_hash != mirna_bundle_hash:
    raise RuntimeError("MIRNA_BYTE_FOR_BYTE_COPY_HASH_MISMATCH")

put("MRNA_FILTERED_RAW_BYTE_IDENTICAL_COPY", "YES")
put("MIRNA_FILTERED_RAW_BYTE_IDENTICAL_COPY", "YES")


# ------------------------------------------------------------
# B. Read frozen cohort and DE count matrices
# ------------------------------------------------------------
cohort = pd.read_csv(COHORT_SOURCE)

mrna = pd.read_csv(
    MRNA_BUNDLE,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
mirna = pd.read_csv(
    MIRNA_BUNDLE,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)

if cohort.shape[0] != 72:
    raise RuntimeError(f"FROZEN_COHORT_ROWS_CHANGED observed={cohort.shape[0]}")
if mrna.shape != (15083, 72):
    raise RuntimeError(f"MRNA_DE_INPUT_SHAPE_CHANGED observed={mrna.shape}")
if mirna.shape != (428, 72):
    raise RuntimeError(f"MIRNA_DE_INPUT_SHAPE_CHANGED observed={mirna.shape}")

subjects = cohort["subject_id"].astype(str).tolist()
groups = cohort["disease_state"].astype(str).tolist()

if not cohort["analysis_cohort_included"].astype(str).eq("YES").all():
    raise RuntimeError("FROZEN_COHORT_CONTAINS_EXCLUSION")

if list(mrna.columns) != subjects:
    raise RuntimeError("MRNA_DE_INPUT_SAMPLE_ORDER_MISMATCH")
if list(mirna.columns) != subjects:
    raise RuntimeError("MIRNA_DE_INPUT_SAMPLE_ORDER_MISMATCH")

expected_groups = {"COVID19": 35, "SEPSIS": 22, "HEALTHY": 15}
observed_groups = pd.Series(groups).value_counts().to_dict()
if observed_groups != expected_groups:
    raise RuntimeError(f"GROUP_COUNTS_CHANGED observed={observed_groups}")

mrna_x = mrna.to_numpy(dtype=np.float64)
mirna_x = mirna.to_numpy(dtype=np.float64)

if np.any(~np.isfinite(mrna_x)) or np.any(mrna_x < 0):
    raise RuntimeError("MRNA_DE_COUNTS_INVALID")
if np.any(~np.isfinite(mirna_x)) or np.any(mirna_x < 0):
    raise RuntimeError("MIRNA_DE_COUNTS_INVALID")

mrna_fractional = int(
    np.sum(np.abs(mrna_x - np.round(mrna_x)) > 1e-12)
)
mirna_fractional = int(
    np.sum(np.abs(mirna_x - np.round(mirna_x)) > 1e-12)
)

if mrna_fractional != 307085:
    raise RuntimeError(
        f"MRNA_FILTERED_FRACTIONAL_COUNT_CHANGED "
        f"expected=307085 observed={mrna_fractional}"
    )
if mirna_fractional != 623:
    raise RuntimeError(
        f"MIRNA_FILTERED_FRACTIONAL_COUNT_CHANGED "
        f"expected=623 observed={mirna_fractional}"
    )

put("MRNA_DE_INPUT_ROWS", mrna.shape[0])
put("MIRNA_DE_INPUT_ROWS", mirna.shape[0])
put("DE_INPUT_SAMPLES", mrna.shape[1])
put("MRNA_DE_INPUT_FRACTIONAL_VALUES", mrna_fractional)
put("MIRNA_DE_INPUT_FRACTIONAL_VALUES", mirna_fractional)


# ------------------------------------------------------------
# C. Freeze cohort bundle
# ------------------------------------------------------------
cohort.to_csv(COHORT_BUNDLE, index=False)

cohort_rt = pd.read_csv(COHORT_BUNDLE)

if cohort_rt["subject_id"].astype(str).tolist() != subjects:
    raise RuntimeError("COHORT_BUNDLE_ROUNDTRIP_SAMPLE_ORDER_MISMATCH")

put("FROZEN_COHORT_BUNDLE_ROWS", cohort_rt.shape[0])


# ------------------------------------------------------------
# D. Certify TMM factors / post-filter library sizes / offsets
# ------------------------------------------------------------
norm = pd.read_csv(NORM_SOURCE)

if norm.shape[0] != 144:
    raise RuntimeError(f"NORM_TABLE_ROWS_CHANGED observed={norm.shape[0]}")

expected_modalities = {
    "mRNA",
    "miRNA_mature_median_primary",
}
if set(norm["modality"].astype(str)) != expected_modalities:
    raise RuntimeError(
        f"NORM_TABLE_MODALITIES_CHANGED "
        f"observed={sorted(set(norm['modality'].astype(str)))}"
    )

offset_rows = []

for modality, matrix in (
    ("mRNA", mrna),
    ("miRNA_mature_median_primary", mirna),
):
    m = norm[norm["modality"].astype(str) == modality].copy()

    if m.shape[0] != 72:
        raise RuntimeError(f"{modality}_NORM_ROWS_NOT_72 observed={m.shape[0]}")

    if m["subject_id"].astype(str).tolist() != subjects:
        raise RuntimeError(f"{modality}_NORM_SAMPLE_ORDER_MISMATCH")

    raw_lib_recomputed = np.sum(
        matrix.to_numpy(dtype=np.float64),
        axis=0,
        dtype=np.float64,
    )

    raw_lib_stored = m["post_filter_raw_library_size"].to_numpy(dtype=np.float64)
    factors = m["tmm_norm_factor"].to_numpy(dtype=np.float64)
    effective_stored = m["effective_library_size"].to_numpy(dtype=np.float64)

    if np.any(~np.isfinite(raw_lib_stored)) or np.any(raw_lib_stored <= 0):
        raise RuntimeError(f"{modality}_INVALID_STORED_LIBRARY_SIZE")
    if np.any(~np.isfinite(factors)) or np.any(factors <= 0):
        raise RuntimeError(f"{modality}_INVALID_TMM_FACTOR")
    if np.any(~np.isfinite(effective_stored)) or np.any(effective_stored <= 0):
        raise RuntimeError(f"{modality}_INVALID_EFFECTIVE_LIBRARY")

    if not np.allclose(
        raw_lib_recomputed,
        raw_lib_stored,
        rtol=1e-12,
        atol=1e-8,
    ):
        maxdiff = float(np.max(np.abs(raw_lib_recomputed - raw_lib_stored)))
        raise RuntimeError(
            f"{modality}_POST_FILTER_LIBRARY_SIZE_MISMATCH maxdiff={maxdiff}"
        )

    effective_recomputed = raw_lib_stored * factors

    if not np.allclose(
        effective_recomputed,
        effective_stored,
        rtol=1e-12,
        atol=1e-8,
    ):
        maxdiff = float(np.max(np.abs(effective_recomputed - effective_stored)))
        raise RuntimeError(
            f"{modality}_EFFECTIVE_LIBRARY_SIZE_MISMATCH maxdiff={maxdiff}"
        )

    factor_gm = float(np.exp(np.mean(np.log(factors))))
    if abs(factor_gm - 1.0) > 1e-12:
        raise RuntimeError(
            f"{modality}_TMM_FACTOR_GEOMEAN_NOT_ONE observed={factor_gm}"
        )

    offsets = np.log(effective_stored)

    if np.any(~np.isfinite(offsets)):
        raise RuntimeError(f"{modality}_NONFINITE_LOG_EFFECTIVE_LIBRARY_OFFSET")

    for i, subject in enumerate(subjects):
        offset_rows.append({
            "subject_id": subject,
            "disease_state": groups[i],
            "modality": modality,
            "post_filter_raw_library_size": float(raw_lib_stored[i]),
            "tmm_norm_factor": float(factors[i]),
            "effective_library_size": float(effective_stored[i]),
            "log_effective_library_offset": float(offsets[i]),
            "offset_authorized_for_low_level_edgepy": "YES",
        })

    put(
        f"{modality}_TMM_FACTOR_GEOMEAN".replace(
            "miRNA_mature_median_primary", "MIRNA"
        ).replace("mRNA", "MRNA"),
        factor_gm,
    )

offset_df = pd.DataFrame(offset_rows)
offset_df.to_csv(OFFSET_TABLE, index=False)

put("DE_OFFSET_TABLE_ROWS", offset_df.shape[0])
put("DE_OFFSET_FORMULA_CERTIFIED", "log(post_filter_library_size*tmm_norm_factor)")


# ------------------------------------------------------------
# E. Freeze no-intercept group-means design matrix
#
# Columns deliberately fixed:
#   COVID19, SEPSIS, HEALTHY
# ------------------------------------------------------------
design = pd.DataFrame({
    "subject_id": subjects,
    "disease_state": groups,
    "COVID19": [1 if g == "COVID19" else 0 for g in groups],
    "SEPSIS": [1 if g == "SEPSIS" else 0 for g in groups],
    "HEALTHY": [1 if g == "HEALTHY" else 0 for g in groups],
})

X = design[["COVID19", "SEPSIS", "HEALTHY"]].to_numpy(dtype=np.float64)

if not np.all(np.sum(X, axis=1) == 1):
    raise RuntimeError("DESIGN_NOT_ONE_HOT")
if np.linalg.matrix_rank(X) != 3:
    raise RuntimeError(
        f"DESIGN_NOT_FULL_RANK rank={np.linalg.matrix_rank(X)}"
    )

design.to_csv(DESIGN_MATRIX, index=False)

put("DESIGN_MATRIX_ROWS", design.shape[0])
put("DESIGN_MATRIX_MODEL_COLUMNS", 3)
put("DESIGN_MATRIX_RANK", int(np.linalg.matrix_rank(X)))
put("DESIGN_MATRIX_PARAMETERIZATION", "NO_INTERCEPT_GROUP_MEANS")


# ------------------------------------------------------------
# F. Freeze planned contrasts
#
# beta order = [COVID19, SEPSIS, HEALTHY]
# ------------------------------------------------------------
contrasts = pd.DataFrame([
    {
        "contrast_name": "COV_vs_H",
        "COVID19": 1.0,
        "SEPSIS": 0.0,
        "HEALTHY": -1.0,
        "interpretation": "COVID19_minus_HEALTHY",
        "role": "PRIMARY_COVID_SIGNAL",
    },
    {
        "contrast_name": "P_vs_H",
        "COVID19": 0.0,
        "SEPSIS": 1.0,
        "HEALTHY": -1.0,
        "interpretation": "SEPSIS_minus_HEALTHY",
        "role": "SEPSIS_COMPARATOR",
    },
    {
        "contrast_name": "COV_vs_P",
        "COVID19": 1.0,
        "SEPSIS": -1.0,
        "HEALTHY": 0.0,
        "interpretation": "COVID19_minus_SEPSIS",
        "role": "COVID_SPECIFICITY",
    },
])

C = contrasts[["COVID19", "SEPSIS", "HEALTHY"]].to_numpy(dtype=np.float64)

if C.shape != (3, 3):
    raise RuntimeError("CONTRAST_MATRIX_SHAPE_WRONG")
if np.any(np.abs(np.sum(C, axis=1)) > 1e-12):
    raise RuntimeError("PAIRWISE_CONTRAST_DOES_NOT_SUM_TO_ZERO")

expected_names = ["COV_vs_H", "P_vs_H", "COV_vs_P"]
if contrasts["contrast_name"].tolist() != expected_names:
    raise RuntimeError("CONTRAST_ORDER_CHANGED")

contrasts.to_csv(CONTRAST_MATRIX, index=False)

put("FROZEN_CONTRASTS", "COV_vs_H|P_vs_H|COV_vs_P")
put("PRIMARY_CONTRAST_VECTOR", "1|0|-1")
put("SEPSIS_COMPARATOR_VECTOR", "0|1|-1")
put("COVID_SPECIFICITY_VECTOR", "1|-1|0")


# ------------------------------------------------------------
# G. Freeze DE engine/input specification
# ------------------------------------------------------------
engine_lines = [
    "GSE243219_D4_DE_ENGINE_AND_INPUT_SPECIFICATION",
    "DE_ENGINE_FAMILY=EDGER_STYLE_NEGATIVE_BINOMIAL_QUASI_LIKELIHOOD",
    "PYTHON_IMPLEMENTATION_TARGET=INMOOSE_EDGEPY_LOW_LEVEL",
    "INMOOSE_VERSION_TARGET=0.9.1",
    "DGELIST_AUTHORIZED_FOR_FRACTIONAL_REAL_DATA=NO",
    "DESEQ2_PYDESEQ2_PRIMARY_ENGINE=NO",
    "COUNT_INPUT=FILTERED_RAW_NONNEGATIVE_COUNTS",
    "MRNA_FRACTIONAL_COUNTS_PRESERVED=YES",
    "MIRNA_MEDIAN_CONSOLIDATION_FRACTIONAL_COUNTS_PRESERVED=YES",
    "COUNT_ROUNDING=PROHIBITED",
    "NORMALIZATION_METHOD=TMM",
    "TMM_FACTORS_RECOMPUTED_IN_D4=NO",
    "DE_OFFSET=LOG_EFFECTIVE_LIBRARY_SIZE",
    "EFFECTIVE_LIBRARY_SIZE=POST_FILTER_RAW_LIBRARY_SIZE_X_TMM_FACTOR",
    "OFFSET_VECTOR_LENGTH_PER_MODALITY=72",
    "DESIGN_PARAMETERIZATION=NO_INTERCEPT_GROUP_MEANS",
    "DESIGN_COLUMNS=COVID19|SEPSIS|HEALTHY",
    "PRIMARY_CONTRAST=COV_vs_H",
    "PRIMARY_CONTRAST_VECTOR=1|0|-1",
    "SEPSIS_COMPARATOR_CONTRAST=P_vs_H",
    "SEPSIS_COMPARATOR_VECTOR=0|1|-1",
    "COVID_SPECIFICITY_CONTRAST=COV_vs_P",
    "COVID_SPECIFICITY_VECTOR=1|-1|0",
    "MULTIPLE_TESTING=BENJAMINI_HOCHBERG_FDR",
    "NORMALIZED_CPM_AS_DE_INPUT=PROHIBITED",
    "LOGCPM_AS_DE_INPUT=PROHIBITED",
    "FROZEN_ANALYSIS_COHORT_SUBJECTS=72",
    "EXCLUDED_SUBJECTS=NONE",
    "DE_EXECUTED_IN_D4=NO",
]
ENGINE_SPEC.write_text("\n".join(engine_lines) + "\n", encoding="utf-8")


# ------------------------------------------------------------
# H. Bundle inventory
# ------------------------------------------------------------
inventory = pd.DataFrame([
    {
        "artifact_role": "MRNA_FILTERED_RAW_COUNTS",
        "source_path": str(MRNA_SOURCE),
        "source_sha256": mrna_source_hash,
        "bundle_path": str(MRNA_BUNDLE),
        "bundle_sha256": mrna_bundle_hash,
        "byte_identical_to_source": "YES",
    },
    {
        "artifact_role": "MIRNA_FILTERED_RAW_COUNTS",
        "source_path": str(MIRNA_SOURCE),
        "source_sha256": mirna_source_hash,
        "bundle_path": str(MIRNA_BUNDLE),
        "bundle_sha256": mirna_bundle_hash,
        "byte_identical_to_source": "YES",
    },
    {
        "artifact_role": "FROZEN_COHORT",
        "source_path": str(COHORT_SOURCE),
        "source_sha256": sha256_file(COHORT_SOURCE),
        "bundle_path": str(COHORT_BUNDLE),
        "bundle_sha256": sha256_file(COHORT_BUNDLE),
        "byte_identical_to_source": "NO_CANONICAL_CSV_REWRITE",
    },
    {
        "artifact_role": "DE_OFFSET_TABLE",
        "source_path": str(NORM_SOURCE),
        "source_sha256": sha256_file(NORM_SOURCE),
        "bundle_path": str(OFFSET_TABLE),
        "bundle_sha256": sha256_file(OFFSET_TABLE),
        "byte_identical_to_source": "DERIVED_CERTIFIED_OFFSETS",
    },
    {
        "artifact_role": "DESIGN_MATRIX",
        "source_path": str(COHORT_SOURCE),
        "source_sha256": sha256_file(COHORT_SOURCE),
        "bundle_path": str(DESIGN_MATRIX),
        "bundle_sha256": sha256_file(DESIGN_MATRIX),
        "byte_identical_to_source": "DERIVED_FROZEN_DESIGN",
    },
    {
        "artifact_role": "CONTRAST_MATRIX",
        "source_path": "D2C_FROZEN_STRATEGY",
        "source_sha256": "",
        "bundle_path": str(CONTRAST_MATRIX),
        "bundle_sha256": sha256_file(CONTRAST_MATRIX),
        "byte_identical_to_source": "DERIVED_FROZEN_CONTRASTS",
    },
])

inventory.to_csv(BUNDLE_INVENTORY, index=False)

put("DE_INPUT_BUNDLE_ARTIFACTS", inventory.shape[0])
put("NORMALIZED_CPM_AS_DE_INPUT", "PROHIBITED")
put("LOGCPM_AS_DE_INPUT", "PROHIBITED")
put("COUNT_ROUNDING_EXECUTED", "NO")
put("SAMPLE_EXCLUSION_EXECUTED", "NO")
put("DE_EXECUTED", "NO")
put("DE_INPUT_BUNDLE_FROZEN", "YES")
put("READY_FOR_D5_DE_MODEL_PREFLIGHT", "YES")
put("NEXT_PHASE", "D5_DE_MODEL_AND_DISPERSION_PREFLIGHT")

RESULT_JSON.write_text(
    json.dumps({"results": results}, indent=2, sort_keys=True),
    encoding="utf-8",
)
'@

$PythonCode | Set-Content -LiteralPath $PyScript -Encoding UTF8

$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

$PythonArgs = @(
    '-u',
    $PyScript,
    $MrnaFilteredSource,
    $MirnaFilteredSource,
    $NormTableSource,
    $FrozenCohortSource,
    $MrnaBundle,
    $MirnaBundle,
    $CohortBundle,
    $OffsetTable,
    $DesignMatrix,
    $ContrastMatrix,
    $EngineSpec,
    $BundleInventory,
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
    foreach ($line in $stdoutLines) { Write-Host $line }
}

if (Test-Path -LiteralPath $PythonStderr -PathType Leaf) {
    $stderrLines = @(Get-Content -LiteralPath $PythonStderr)
    if ($stderrLines.Count -gt 0) {
        Write-Host '=== D4 PYTHON STDERR ==='
        foreach ($line in $stderrLines) { Write-Host $line }
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
    throw ('D4_PYTHON_FAILED exit={0} full_traceback={1}' -f $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D4_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('MRNA_FILTERED_RAW_BYTE_IDENTICAL_COPY','YES'),
    @('MIRNA_FILTERED_RAW_BYTE_IDENTICAL_COPY','YES'),
    @('MRNA_DE_INPUT_ROWS','15083'),
    @('MIRNA_DE_INPUT_ROWS','428'),
    @('DE_INPUT_SAMPLES','72'),
    @('MRNA_DE_INPUT_FRACTIONAL_VALUES','307085'),
    @('MIRNA_DE_INPUT_FRACTIONAL_VALUES','623'),
    @('FROZEN_COHORT_BUNDLE_ROWS','72'),
    @('DE_OFFSET_TABLE_ROWS','144'),
    @('DESIGN_MATRIX_ROWS','72'),
    @('DESIGN_MATRIX_MODEL_COLUMNS','3'),
    @('DESIGN_MATRIX_RANK','3'),
    @('DESIGN_MATRIX_PARAMETERIZATION','NO_INTERCEPT_GROUP_MEANS'),
    @('FROZEN_CONTRASTS','COV_vs_H|P_vs_H|COV_vs_P'),
    @('PRIMARY_CONTRAST_VECTOR','1|0|-1'),
    @('SEPSIS_COMPARATOR_VECTOR','0|1|-1'),
    @('COVID_SPECIFICITY_VECTOR','1|-1|0'),
    @('NORMALIZED_CPM_AS_DE_INPUT','PROHIBITED'),
    @('LOGCPM_AS_DE_INPUT','PROHIBITED'),
    @('COUNT_ROUNDING_EXECUTED','NO'),
    @('SAMPLE_EXCLUSION_EXECUTED','NO'),
    @('DE_EXECUTED','NO'),
    @('DE_INPUT_BUNDLE_FROZEN','YES'),
    @('READY_FOR_D5_DE_MODEL_PREFLIGHT','YES'),
    @('NEXT_PHASE','D5_DE_MODEL_AND_DISPERSION_PREFLIGHT')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D4_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 3. D4 decision
# ------------------------------------------------------------
@(
    'GSE243219_D4_DECISION',
    'PHASE_D4_STATUS=PASS',
    'MODE=CERTIFICATION_AND_BUNDLE_FREEZE_ONLY',
    'D2C_STRATEGY_CERTIFICATION_GATE=PASS',
    'D2C_OUTPUTS_RECERTIFIED=3/3',
    'D2D1_ENGINE_CERTIFICATION_GATE=PASS',
    'D2D1_OUTPUTS_RECERTIFIED=5/5',
    'D3B_DATA_NORMALIZATION_CERTIFICATION_GATE=PASS',
    'D3B_OUTPUTS_RECERTIFIED=18/18',
    'D3C_COHORT_CERTIFICATION_GATE=PASS',
    'D3C_OUTPUTS_RECERTIFIED=11/11',
    'DE_INPUT_BUNDLE_FROZEN=YES',
    'MRNA_FILTERED_RAW_COUNTS=15083x72',
    'MIRNA_FILTERED_RAW_COUNTS=428x72',
    'MRNA_FILTERED_RAW_BYTE_IDENTICAL_COPY=YES',
    'MIRNA_FILTERED_RAW_BYTE_IDENTICAL_COPY=YES',
    'MRNA_DE_INPUT_FRACTIONAL_VALUES=307085',
    'MIRNA_DE_INPUT_FRACTIONAL_VALUES=623',
    'ANALYSIS_COHORT_SUBJECTS=72',
    'ANALYSIS_COHORT_COVID19=35',
    'ANALYSIS_COHORT_SEPSIS=22',
    'ANALYSIS_COHORT_HEALTHY=15',
    'EXCLUDED_SUBJECTS=NONE',
    'TMM_FACTORS_RECOMPUTED=NO',
    'TMM_FACTORS_CERTIFIED=YES',
    'DE_OFFSET=LOG_EFFECTIVE_LIBRARY_SIZE',
    'DESIGN_MATRIX_PARAMETERIZATION=NO_INTERCEPT_GROUP_MEANS',
    'DESIGN_COLUMNS=COVID19|SEPSIS|HEALTHY',
    'DESIGN_MATRIX_RANK=3',
    'PRIMARY_CONTRAST=COV_vs_H',
    'PRIMARY_CONTRAST_VECTOR=1|0|-1',
    'SEPSIS_COMPARATOR_CONTRAST=P_vs_H',
    'SEPSIS_COMPARATOR_VECTOR=0|1|-1',
    'COVID_SPECIFICITY_CONTRAST=COV_vs_P',
    'COVID_SPECIFICITY_VECTOR=1|-1|0',
    'DE_ENGINE_FAMILY=EDGER_STYLE_NEGATIVE_BINOMIAL_QUASI_LIKELIHOOD',
    'DE_IMPLEMENTATION_TARGET=INMOOSE_EDGEPY_LOW_LEVEL',
    'DGELIST_AUTHORIZED_FOR_FRACTIONAL_REAL_DATA=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'NORMALIZED_CPM_AS_DE_INPUT=PROHIBITED',
    'LOGCPM_AS_DE_INPUT=PROHIBITED',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D5_DE_MODEL_PREFLIGHT=YES',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D5_DE_MODEL_AND_DISPERSION_PREFLIGHT',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Manifest
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $MrnaBundle,
    $MirnaBundle,
    $CohortBundle,
    $OffsetTable,
    $DesignMatrix,
    $ContrastMatrix,
    $EngineSpec,
    $BundleInventory,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D4_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p

    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D4SHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D4 SUMMARY ===',
    'PHASE_D4_STATUS=PASS',
    'MODE=CERTIFICATION_AND_BUNDLE_FREEZE_ONLY',
    'D2C_STRATEGY_CERTIFICATION_GATE=PASS',
    'D2C_OUTPUTS_RECERTIFIED=3/3',
    'D2D1_ENGINE_CERTIFICATION_GATE=PASS',
    'D2D1_OUTPUTS_RECERTIFIED=5/5',
    'D3B_DATA_NORMALIZATION_CERTIFICATION_GATE=PASS',
    'D3B_OUTPUTS_RECERTIFIED=18/18',
    'D3C_COHORT_CERTIFICATION_GATE=PASS',
    'D3C_OUTPUTS_RECERTIFIED=11/11',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    'DE_INPUT_BUNDLE_FROZEN=YES',
    'MRNA_FILTERED_RAW_COUNTS=15083x72',
    'MIRNA_FILTERED_RAW_COUNTS=428x72',
    ('MRNA_DE_INPUT_FRACTIONAL_VALUES={0}' -f (Cap 'MRNA_DE_INPUT_FRACTIONAL_VALUES')),
    ('MIRNA_DE_INPUT_FRACTIONAL_VALUES={0}' -f (Cap 'MIRNA_DE_INPUT_FRACTIONAL_VALUES')),
    'MRNA_FILTERED_RAW_BYTE_IDENTICAL_COPY=YES',
    'MIRNA_FILTERED_RAW_BYTE_IDENTICAL_COPY=YES',
    'ANALYSIS_COHORT_SUBJECTS=72',
    'ANALYSIS_COHORT_COVID19=35',
    'ANALYSIS_COHORT_SEPSIS=22',
    'ANALYSIS_COHORT_HEALTHY=15',
    'EXCLUDED_SUBJECTS=NONE',
    'TMM_FACTORS_RECOMPUTED=NO',
    'TMM_FACTORS_CERTIFIED=YES',
    ('MRNA_TMM_FACTOR_GEOMEAN={0}' -f (Cap 'MRNA_TMM_FACTOR_GEOMEAN')),
    ('MIRNA_TMM_FACTOR_GEOMEAN={0}' -f (Cap 'MIRNA_TMM_FACTOR_GEOMEAN')),
    'EFFECTIVE_LIBRARY_SIZE=POST_FILTER_RAW_LIBRARY_SIZE_X_TMM_FACTOR',
    'DE_OFFSET=LOG_EFFECTIVE_LIBRARY_SIZE',
    'DE_OFFSET_VECTOR_LENGTH_PER_MODALITY=72',
    'DESIGN_MATRIX_PARAMETERIZATION=NO_INTERCEPT_GROUP_MEANS',
    'DESIGN_COLUMNS=COVID19|SEPSIS|HEALTHY',
    'DESIGN_MATRIX_RANK=3',
    'PRIMARY_CONTRAST=COV_vs_H',
    'PRIMARY_CONTRAST_VECTOR=1|0|-1',
    'SEPSIS_COMPARATOR_CONTRAST=P_vs_H',
    'SEPSIS_COMPARATOR_VECTOR=0|1|-1',
    'COVID_SPECIFICITY_CONTRAST=COV_vs_P',
    'COVID_SPECIFICITY_VECTOR=1|-1|0',
    'DE_ENGINE_FAMILY=EDGER_STYLE_NEGATIVE_BINOMIAL_QUASI_LIKELIHOOD',
    'DE_IMPLEMENTATION_TARGET=INMOOSE_EDGEPY_LOW_LEVEL',
    'DGELIST_AUTHORIZED_FOR_FRACTIONAL_REAL_DATA=NO',
    'MULTIPLE_TESTING=BENJAMINI_HOCHBERG_FDR',
    'NORMALIZED_CPM_AS_DE_INPUT=PROHIBITED',
    'LOGCPM_AS_DE_INPUT=PROHIBITED',
    'COUNT_ROUNDING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D5_DE_MODEL_PREFLIGHT=YES',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D5_DE_MODEL_AND_DISPERSION_PREFLIGHT',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D4_MRNA_DE_INPUT={0}' -f $MrnaBundle)
Write-Host ('D4_MIRNA_DE_INPUT={0}' -f $MirnaBundle)
Write-Host ('D4_FROZEN_COHORT={0}' -f $CohortBundle)
Write-Host ('D4_DE_OFFSET_TABLE={0}' -f $OffsetTable)
Write-Host ('D4_DESIGN_MATRIX={0}' -f $DesignMatrix)
Write-Host ('D4_CONTRAST_MATRIX={0}' -f $ContrastMatrix)
Write-Host ('D4_ENGINE_SPEC={0}' -f $EngineSpec)
Write-Host ('D4_BUNDLE_INVENTORY={0}' -f $BundleInventory)
Write-Host ('D4_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D4_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D4=PASS'
Write-Host 'STOP=YES'
