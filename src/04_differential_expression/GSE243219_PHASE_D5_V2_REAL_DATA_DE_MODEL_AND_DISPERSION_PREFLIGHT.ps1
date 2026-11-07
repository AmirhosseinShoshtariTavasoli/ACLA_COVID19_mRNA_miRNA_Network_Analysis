$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D5-V2 — REAL-DATA DE MODEL + DISPERSION PREFLIGHT
#
# Purpose:
#   Validate the REAL filtered count matrices through the exact
#   low-level InMoose edgepy model-fitting route BEFORE any
#   differential-expression hypothesis test is authorized.
#
# Frozen D5 implementation strategy:
#   - NO DGEList (known integer coercion)
#   - Cox-Reid COMMON negative-binomial dispersion
#   - explicit log(TMM effective library size) offset vector
#   - explicit AveLogCPM calculated using the offset
#   - glmQLFit with abundance_trend=True
#   - glmQLFit with robust=False
#   - robust squeezeVar path is explicitly prohibited because
#     InMoose 0.9.1 raises NotImplementedError for robust=True
#
# Critical edgeR/QL rule:
#   glmQLFit must receive a GLOBAL NB dispersion (common or
#   trended), NOT tagwise/genewise NB dispersions.
#
# Authorized:
#   - real common-dispersion estimation
#   - real QL model fitting
#   - model/dispersion diagnostic summaries
#
# Prohibited:
#   - glmQLFTest
#   - glmLRT
#   - p-values
#   - BH/FDR
#   - contrast testing
#   - sample exclusion
#   - count rounding
#   - refiltering
#   - TMM recomputation
#   - network construction
#   - A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D2Root = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING'
$D4Root = Join-Path $Project '04_NORMALIZATION'
$D5Root = Join-Path $Project '05_DIFFERENTIAL_EXPRESSION'

$D2DRun = Join-Path $D2Root 'D2D_PREFLIGHT_20260904_195001'
$VenvPython = Join-Path $D2DRun 'venv\Scripts\python.exe'

$D4Run = Join-Path $D4Root 'D4_DE_INPUT_BUNDLE_FREEZE_20260905_094110'
$D4Manifest = Join-Path $D4Run 'D4_OUTPUT_SHA256_MANIFEST.csv'
$D4Decision = Join-Path $D4Run 'D4_DECISION.txt'
$D4Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D4_20260905_094110\PHASE_D4_SUMMARY.txt'

$MrnaCounts = Join-Path $D4Run 'D4_MRNA_FILTERED_RAW_COUNTS_DE_INPUT_15083x72.csv.gz'
$MirnaCounts = Join-Path $D4Run 'D4_MIRNA_FILTERED_RAW_COUNTS_DE_INPUT_428x72.csv.gz'
$Cohort = Join-Path $D4Run 'D4_FROZEN_ANALYSIS_COHORT_72.csv'
$OffsetTable = Join-Path $D4Run 'D4_DE_EFFECTIVE_LIBRARY_AND_OFFSET_TABLE.csv'
$DesignMatrix = Join-Path $D4Run 'D4_DE_DESIGN_MATRIX_GROUP_MEANS_72x3.csv'
$ContrastMatrix = Join-Path $D4Run 'D4_DE_CONTRAST_MATRIX.csv'
$EngineSpec = Join-Path $D4Run 'D4_DE_ENGINE_AND_INPUT_SPECIFICATION.txt'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D5Root ('D5_V2_MODEL_DISPERSION_PREFLIGHT_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D5_V2_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D5_V2_REAL_DATA_MODEL_AND_DISPERSION_PREFLIGHT.py'
$ApiAudit = Join-Path $RunDir 'D5_LOCAL_INMOOSE_API_AND_SOURCE_AUDIT.txt'
$ModelSummary = Join-Path $RunDir 'D5_MODEL_DISPERSION_SUMMARY.csv'
$ModelDiagnostics = Join-Path $RunDir 'D5_QL_MODEL_DIAGNOSTICS.csv'
$ImplementationFreeze = Join-Path $RunDir 'D5_FROZEN_DE_MODEL_IMPLEMENTATION.txt'
$ResultJson = Join-Path $RunDir 'D5_RESULT.json'

$PythonStdout = Join-Path $RunDir 'D5_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D5_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D5_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D5_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D5_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D5_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D5 — REAL-DATA DE MODEL + DISPERSION PREFLIGHT ==='
Write-Host 'MODE=REAL_MODEL_FIT_PREFLIGHT_WITHOUT_HYPOTHESIS_TESTING'
Write-Host 'REAL_FILTERED_COUNTS_READ=YES'
Write-Host 'REAL_COMMON_DISPERSION_ESTIMATION_EXECUTED=YES'
Write-Host 'REAL_QL_MODEL_FIT_EXECUTED=YES'
Write-Host 'GLMQLFTEST_EXECUTED=NO'
Write-Host 'GLMLRT_EXECUTED=NO'
Write-Host 'CONTRAST_TESTING_EXECUTED=NO'
Write-Host 'PVALUES_COMPUTED=NO'
Write-Host 'FDR_COMPUTED=NO'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'FEATURE_REFILTERING_EXECUTED=NO'
Write-Host 'TMM_RECOMPUTATION_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $VenvPython,
    $D4Manifest,$D4Decision,$D4Report,
    $MrnaCounts,$MirnaCounts,$Cohort,$OffsetTable,
    $DesignMatrix,$ContrastMatrix,$EngineSpec
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D5_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D5SHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

# ------------------------------------------------------------
# 1. Re-certify D4 bundle
# ------------------------------------------------------------
$d4 = Get-Content -LiteralPath $D4Report -Raw

foreach ($tok in @(
    'PHASE_D4_STATUS=PASS',
    'DE_INPUT_BUNDLE_FROZEN=YES',
    'MRNA_FILTERED_RAW_COUNTS=15083x72',
    'MIRNA_FILTERED_RAW_COUNTS=428x72',
    'MRNA_DE_INPUT_FRACTIONAL_VALUES=307085',
    'MIRNA_DE_INPUT_FRACTIONAL_VALUES=623',
    'MRNA_FILTERED_RAW_BYTE_IDENTICAL_COPY=YES',
    'MIRNA_FILTERED_RAW_BYTE_IDENTICAL_COPY=YES',
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
    'NORMALIZED_CPM_AS_DE_INPUT=PROHIBITED',
    'LOGCPM_AS_DE_INPUT=PROHIBITED',
    'COUNT_ROUNDING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'READY_FOR_D5_DE_MODEL_PREFLIGHT=YES',
    'NEXT_PHASE=D5_DE_MODEL_AND_DISPERSION_PREFLIGHT'
)) {
    if ($d4 -notmatch [regex]::Escape($tok)) {
        throw ('D4_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$d4Rows = @(Import-Csv -LiteralPath $D4Manifest)

if ($d4Rows.Count -ne 14) {
    throw ('D4_MANIFEST_ROW_COUNT_CHANGED expected=14 observed={0}' -f $d4Rows.Count)
}

foreach ($r in $d4Rows) {
    if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
        throw ('D4_OUTPUT_MISSING={0}' -f $r.full_path)
    }

    $item = Get-Item -LiteralPath $r.full_path
    if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
        (Get-D5SHA256 $r.full_path) -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D4_OUTPUT_CHANGED={0}' -f $r.full_path)
    }
}

Write-Host 'D4_CERTIFICATION_GATE=PASS'
Write-Host 'D4_OUTPUTS_RECERTIFIED=14/14'

$PythonVersion = & $VenvPython -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$InMooseVersion = & $VenvPython -c "import importlib.metadata as m; print(m.version('inmoose'))"
$PandasVersion = & $VenvPython -c "import pandas; print(pandas.__version__)"
$NumpyVersion = & $VenvPython -c "import numpy; print(numpy.__version__)"
$ScipyVersion = & $VenvPython -c "import scipy; print(scipy.__version__)"

if ($PythonVersion -ne '3.12.3') {
    throw ('VALIDATED_PYTHON_CHANGED={0}' -f $PythonVersion)
}
if ($InMooseVersion.Trim() -ne '0.9.1') {
    throw ('INMOOSE_VERSION_CHANGED expected=0.9.1 observed={0}' -f $InMooseVersion)
}

Write-Host ('PYTHON_VERSION={0}' -f $PythonVersion)
Write-Host ('INMOOSE_VERSION={0}' -f $InMooseVersion)
Write-Host ('PANDAS_VERSION={0}' -f $PandasVersion)
Write-Host ('NUMPY_VERSION={0}' -f $NumpyVersion)
Write-Host ('SCIPY_VERSION={0}' -f $ScipyVersion)

# ------------------------------------------------------------
# 2. Python real-data model preflight
# ------------------------------------------------------------
$PythonCode = @'
import hashlib
import inspect
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

from inmoose.edgepy.aveLogCPM import aveLogCPM
from inmoose.edgepy.estimateGLMCommonDisp import estimateGLMCommonDisp
from inmoose.edgepy.glmQLFit import glmQLFit, glmQLFTest
from inmoose.edgepy.glmFit import glmLRT
from inmoose.edgepy.DGEList import DGEList


MRNA_COUNTS = Path(sys.argv[1])
MIRNA_COUNTS = Path(sys.argv[2])
COHORT = Path(sys.argv[3])
OFFSET_TABLE = Path(sys.argv[4])
DESIGN_MATRIX = Path(sys.argv[5])
CONTRAST_MATRIX = Path(sys.argv[6])
ENGINE_SPEC = Path(sys.argv[7])

API_AUDIT = Path(sys.argv[8])
MODEL_SUMMARY = Path(sys.argv[9])
MODEL_DIAGNOSTICS = Path(sys.argv[10])
IMPLEMENTATION_FREEZE = Path(sys.argv[11])
RESULT_JSON = Path(sys.argv[12])


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


def quantiles(x):
    x = np.asarray(x, dtype=np.float64).ravel()
    finite = x[np.isfinite(x)]
    if finite.size == 0:
        return {
            "min": np.nan,
            "q1": np.nan,
            "median": np.nan,
            "q3": np.nan,
            "max": np.nan,
        }
    return {
        "min": float(np.min(finite)),
        "q1": float(np.quantile(finite, 0.25)),
        "median": float(np.median(finite)),
        "q3": float(np.quantile(finite, 0.75)),
        "max": float(np.max(finite)),
    }


# ------------------------------------------------------------
# A. Audit exact LOCAL InMoose 0.9.1 low-level API/source
# ------------------------------------------------------------
api_items = {
    "estimateGLMCommonDisp": estimateGLMCommonDisp,
    "aveLogCPM": aveLogCPM,
    "glmQLFit": glmQLFit,
    "glmQLFTest": glmQLFTest,
    "glmLRT": glmLRT,
    "DGEList": DGEList,
}

audit_lines = [
    "GSE243219_D5_LOCAL_INMOOSE_API_AND_SOURCE_AUDIT",
]

for name, obj in api_items.items():
    sig = str(inspect.signature(obj))
    try:
        source_file = inspect.getsourcefile(obj) or ""
    except TypeError:
        source_file = ""

    source_hash = ""
    if source_file and Path(source_file).is_file():
        source_hash = sha256_file(source_file)

    audit_lines.extend([
        f"{name}_SIGNATURE={sig}",
        f"{name}_SOURCE_FILE={source_file}",
        f"{name}_SOURCE_SHA256={source_hash}",
    ])

sig_common = inspect.signature(estimateGLMCommonDisp)
sig_ave = inspect.signature(aveLogCPM)
sig_ql = inspect.signature(glmQLFit)
sig_qltest = inspect.signature(glmQLFTest)

required_common = {"y", "design", "offset", "method", "subset", "AveLogCPM", "weights"}
required_ave = {"y", "offset", "dispersion"}
required_ql = {
    "y", "design", "dispersion", "offset", "lib_size",
    "abundance_trend", "AveLogCPM", "robust", "winsor_tail_p"
}
required_qltest = {"glmfit", "contrast", "poisson_bound"}

if not required_common.issubset(sig_common.parameters):
    raise RuntimeError(
        f"COMMON_DISPERSION_API_MISMATCH observed={sig_common}"
    )
if not required_ave.issubset(sig_ave.parameters):
    raise RuntimeError(
        f"AVELOGCPM_API_MISMATCH observed={sig_ave}"
    )
if not required_ql.issubset(sig_ql.parameters):
    raise RuntimeError(
        f"GLMQLFIT_API_MISMATCH observed={sig_ql}"
    )
if not required_qltest.issubset(sig_qltest.parameters):
    raise RuntimeError(
        f"GLMQLFTEST_API_MISMATCH observed={sig_qltest}"
    )

# Audit source semantics important for this project.
ql_source = inspect.getsource(glmQLFit)
common_source = inspect.getsource(estimateGLMCommonDisp)
dge_source = inspect.getsource(DGEList.__init__)

global_dispersion_warning_detected = (
    "global model" in ql_source
    and "genewise dispersions" in ql_source
)
common_offset_vector_support_detected = (
    "offset" in sig_common.parameters
)

from inmoose.limma.squeezeVar import squeezeVar
squeeze_source = inspect.getsource(squeezeVar)
robust_squeezevar_notimplemented_detected = (
    "Robust estimation in squeezeVar is not implemented" in squeeze_source
)

dge_integer_cast_detected = (
    "astype(int)" in dge_source
    or "astype(np.int" in dge_source
)

audit_lines.extend([
    f"QL_GLOBAL_DISPERSION_REQUIREMENT_DETECTED={'YES' if global_dispersion_warning_detected else 'NO'}",
    f"COMMON_DISPERSION_EXPLICIT_OFFSET_API_DETECTED={'YES' if common_offset_vector_support_detected else 'NO'}",
    f"ROBUST_SQUEEZEVAR_NOTIMPLEMENTED_DETECTED={'YES' if robust_squeezevar_notimplemented_detected else 'NO'}",
    f"DGELIST_EXPLICIT_INTEGER_CAST_DETECTED={'YES' if dge_integer_cast_detected else 'NO'}",
    "GLMQLFTEST_CALLED_IN_D5_V2=NO",
    "GLMLRT_CALLED_IN_D5_V2=NO",
])

if not global_dispersion_warning_detected:
    raise RuntimeError("QL_GLOBAL_DISPERSION_REQUIREMENT_NOT_CONFIRMED_FROM_LOCAL_SOURCE")
if not common_offset_vector_support_detected:
    raise RuntimeError("COMMON_DISPERSION_OFFSET_API_NOT_CONFIRMED")
if not robust_squeezevar_notimplemented_detected:
    raise RuntimeError("ROBUST_SQUEEZEVAR_LIMITATION_NOT_CONFIRMED_FROM_LOCAL_SOURCE")
if not dge_integer_cast_detected:
    raise RuntimeError("EXPECTED_DGELIST_INTEGER_CAST_NOT_CONFIRMED")

API_AUDIT.write_text("\n".join(audit_lines) + "\n", encoding="utf-8")

put("LOCAL_INMOOSE_API_AUDIT", "PASS")
put("QL_GLOBAL_DISPERSION_REQUIREMENT_CONFIRMED", "YES")
put("ROBUST_SQUEEZEVAR_UNSUPPORTED_CONFIRMED", "YES")
put("DGELIST_INTEGER_CAST_RECONFIRMED", "YES")
put("DGELIST_USED_FOR_REAL_DATA", "NO")


# ------------------------------------------------------------
# B. Load frozen D4 inputs
# ------------------------------------------------------------
cohort = pd.read_csv(COHORT)
offset_table = pd.read_csv(OFFSET_TABLE)
design_df = pd.read_csv(DESIGN_MATRIX)
contrasts = pd.read_csv(CONTRAST_MATRIX)

mrna = pd.read_csv(
    MRNA_COUNTS,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
mirna = pd.read_csv(
    MIRNA_COUNTS,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)

if cohort.shape[0] != 72:
    raise RuntimeError(f"COHORT_ROWS_CHANGED observed={cohort.shape[0]}")
if mrna.shape != (15083, 72):
    raise RuntimeError(f"MRNA_SHAPE_CHANGED observed={mrna.shape}")
if mirna.shape != (428, 72):
    raise RuntimeError(f"MIRNA_SHAPE_CHANGED observed={mirna.shape}")

subjects = cohort["subject_id"].astype(str).tolist()

if list(mrna.columns) != subjects:
    raise RuntimeError("MRNA_SAMPLE_ORDER_CHANGED")
if list(mirna.columns) != subjects:
    raise RuntimeError("MIRNA_SAMPLE_ORDER_CHANGED")

X = design_df[["COVID19", "SEPSIS", "HEALTHY"]].to_numpy(dtype=np.float64)

if X.shape != (72, 3):
    raise RuntimeError(f"DESIGN_SHAPE_CHANGED observed={X.shape}")
if np.linalg.matrix_rank(X) != 3:
    raise RuntimeError("DESIGN_NOT_FULL_RANK")
if design_df["subject_id"].astype(str).tolist() != subjects:
    raise RuntimeError("DESIGN_SAMPLE_ORDER_CHANGED")

expected_contrasts = {
    "COV_vs_H": np.array([1.0, 0.0, -1.0]),
    "P_vs_H": np.array([0.0, 1.0, -1.0]),
    "COV_vs_P": np.array([1.0, -1.0, 0.0]),
}

for name, expected in expected_contrasts.items():
    row = contrasts.loc[contrasts["contrast_name"].astype(str) == name]
    if row.shape[0] != 1:
        raise RuntimeError(f"CONTRAST_MISSING_OR_DUPLICATE name={name}")
    observed = row[["COVID19", "SEPSIS", "HEALTHY"]].to_numpy(dtype=np.float64).ravel()
    if not np.array_equal(observed, expected):
        raise RuntimeError(
            f"CONTRAST_VECTOR_CHANGED name={name} observed={observed}"
        )

put("D4_REAL_INPUT_INTEGRITY", "PASS")


# ------------------------------------------------------------
# C. Synthetic standard non-robust QL path sanity test before full real fit
# ------------------------------------------------------------
rng = np.random.default_rng(243219)
syn = rng.gamma(shape=3.0, scale=20.0, size=(240, 18))
syn += ((np.arange(240)[:, None] + np.arange(18)[None, :]) % 4) * 0.25

syn_design = np.zeros((18, 3), dtype=np.float64)
syn_design[:6, 0] = 1.0
syn_design[6:12, 1] = 1.0
syn_design[12:, 2] = 1.0

syn_lib = np.sum(syn, axis=0)
syn_offset = np.log(syn_lib)

syn_disp = estimateGLMCommonDisp(
    syn,
    design=syn_design,
    offset=syn_offset,
    method="CoxReid",
    subset=240,
    AveLogCPM=None,
    verbose=False,
    weights=None,
)

if syn_disp is None or not np.isfinite(syn_disp) or syn_disp <= 0:
    raise RuntimeError(f"SYNTHETIC_COMMON_DISPERSION_FAILED observed={syn_disp}")

syn_ave = aveLogCPM(
    syn,
    offset=syn_offset,
    dispersion=syn_disp,
)

syn_fit = glmQLFit(
    syn,
    design=syn_design,
    dispersion=syn_disp,
    offset=syn_offset,
    lib_size=None,
    weights=None,
    abundance_trend=True,
    AveLogCPM=syn_ave,
    robust=False,
)

if not np.array_equal(np.asarray(syn_fit.counts), syn):
    raise RuntimeError("SYNTHETIC_NONROBUST_QL_COUNT_PRESERVATION_FAILED")

if np.any(~np.isfinite(np.asarray(syn_fit.coefficients, dtype=np.float64))):
    raise RuntimeError("SYNTHETIC_NONROBUST_QL_NONFINITE_COEFFICIENTS")

put("SYNTHETIC_NONROBUST_QL_PATH_PREFLIGHT", "PASS")


# ------------------------------------------------------------
# D. REAL dispersion/model preflight
# ------------------------------------------------------------
summary_rows = []
diagnostic_rows = []

def get_offsets(modality):
    m = offset_table[offset_table["modality"].astype(str) == modality].copy()

    if m.shape[0] != 72:
        raise RuntimeError(
            f"{modality}_OFFSET_ROWS_CHANGED observed={m.shape[0]}"
        )
    if m["subject_id"].astype(str).tolist() != subjects:
        raise RuntimeError(f"{modality}_OFFSET_SAMPLE_ORDER_CHANGED")

    offsets = m["log_effective_library_offset"].to_numpy(dtype=np.float64)
    effective = m["effective_library_size"].to_numpy(dtype=np.float64)

    if np.any(~np.isfinite(offsets)):
        raise RuntimeError(f"{modality}_NONFINITE_OFFSET")
    if np.any(~np.isfinite(effective)) or np.any(effective <= 0):
        raise RuntimeError(f"{modality}_INVALID_EFFECTIVE_LIBRARY")

    if not np.allclose(np.exp(offsets), effective, rtol=1e-12, atol=1e-8):
        raise RuntimeError(f"{modality}_OFFSET_EXP_EFFECTIVE_LIBRARY_MISMATCH")

    return offsets, effective


def fit_modality(matrix_df, offset_modality, output_label):
    y = matrix_df.to_numpy(dtype=np.float64)

    if np.any(~np.isfinite(y)) or np.any(y < 0):
        raise RuntimeError(f"{output_label}_INVALID_COUNTS")

    fractional_count = int(
        np.sum(np.abs(y - np.round(y)) > 1e-12)
    )

    offsets, effective = get_offsets(offset_modality)

    # Re-certify that explicit offset and explicit effective-library
    # routes give equivalent abundance values.
    ave_offset_005 = aveLogCPM(
        y,
        offset=offsets,
        dispersion=0.05,
    )
    ave_lib_005 = aveLogCPM(
        y,
        lib_size=effective,
        dispersion=0.05,
    )

    route_diff = float(
        np.max(
            np.abs(
                np.asarray(ave_offset_005, dtype=np.float64)
                - np.asarray(ave_lib_005, dtype=np.float64)
            )
        )
    )

    if route_diff > 1e-10:
        raise RuntimeError(
            f"{output_label}_AVELOGCPM_OFFSET_ROUTE_MISMATCH maxdiff={route_diff}"
        )

    raw_lib = np.sum(y, axis=0, dtype=np.float64)
    ave_raw_005 = aveLogCPM(
        y,
        lib_size=raw_lib,
        dispersion=0.05,
    )

    normalization_effect = float(
        np.max(
            np.abs(
                np.asarray(ave_offset_005, dtype=np.float64)
                - np.asarray(ave_raw_005, dtype=np.float64)
            )
        )
    )

    if normalization_effect <= 1e-12:
        raise RuntimeError(
            f"{output_label}_TMM_OFFSET_HAS_NO_NUMERICAL_EFFECT"
        )

    subset = min(10000, y.shape[0])

    common = estimateGLMCommonDisp(
        y,
        design=X,
        offset=offsets,
        method="CoxReid",
        subset=subset,
        AveLogCPM=None,
        verbose=False,
        weights=None,
    )

    if common is None or not np.isfinite(common) or common <= 0:
        raise RuntimeError(
            f"{output_label}_COMMON_DISPERSION_INVALID observed={common}"
        )

    bcv = float(np.sqrt(common))

    ave = aveLogCPM(
        y,
        offset=offsets,
        dispersion=common,
    )

    ave_arr = np.asarray(ave, dtype=np.float64)
    if ave_arr.shape != (y.shape[0],):
        raise RuntimeError(
            f"{output_label}_AVELOGCPM_SHAPE_WRONG observed={ave_arr.shape}"
        )
    if np.any(~np.isfinite(ave_arr)):
        raise RuntimeError(f"{output_label}_AVELOGCPM_NONFINITE")

    fit = glmQLFit(
        y,
        design=X,
        dispersion=common,
        offset=offsets,
        lib_size=None,
        weights=None,
        abundance_trend=True,
        AveLogCPM=ave_arr,
        robust=False,
    )

    fit_counts = np.asarray(fit.counts, dtype=np.float64)
    if not np.array_equal(fit_counts, y):
        raise RuntimeError(f"{output_label}_QLFIT_COUNTS_NOT_PRESERVED")

    fit_offset = np.asarray(fit.offset, dtype=np.float64)
    expected_offset = np.broadcast_to(offsets, y.shape)

    if fit_offset.shape != y.shape:
        raise RuntimeError(
            f"{output_label}_QLFIT_OFFSET_SHAPE_WRONG observed={fit_offset.shape}"
        )

    offset_diff = float(np.max(np.abs(fit_offset - expected_offset)))
    if offset_diff > 1e-12:
        raise RuntimeError(
            f"{output_label}_QLFIT_OFFSET_NOT_PRESERVED maxdiff={offset_diff}"
        )

    fit_design = np.asarray(fit.design, dtype=np.float64)
    if fit_design.shape != X.shape or not np.array_equal(fit_design, X):
        raise RuntimeError(f"{output_label}_QLFIT_DESIGN_NOT_PRESERVED")

    coef = np.asarray(fit.coefficients, dtype=np.float64)
    fitted = np.asarray(fit.fitted_values, dtype=np.float64)
    deviance = np.asarray(fit.deviance, dtype=np.float64)
    df_resid = np.asarray(fit.df_residual, dtype=np.float64)
    df_zero = np.asarray(fit.df_residual_zeros, dtype=np.float64)
    var_post = np.asarray(fit.var_post, dtype=np.float64)
    var_prior = np.asarray(fit.var_prior, dtype=np.float64)
    df_prior = np.asarray(fit.df_prior, dtype=np.float64)

    if coef.shape != (y.shape[0], 3):
        raise RuntimeError(
            f"{output_label}_COEFFICIENT_SHAPE_WRONG observed={coef.shape}"
        )
    if fitted.shape != y.shape:
        raise RuntimeError(
            f"{output_label}_FITTED_SHAPE_WRONG observed={fitted.shape}"
        )

    if np.any(~np.isfinite(coef)):
        raise RuntimeError(f"{output_label}_NONFINITE_COEFFICIENT")
    if np.any(~np.isfinite(fitted)) or np.any(fitted < 0):
        raise RuntimeError(f"{output_label}_INVALID_FITTED_VALUES")
    if np.any(~np.isfinite(deviance)) or np.any(deviance < -1e-10):
        raise RuntimeError(f"{output_label}_INVALID_DEVIANCE")
    if np.any(~np.isfinite(df_resid)) or np.any(df_resid < 0):
        raise RuntimeError(f"{output_label}_INVALID_DF_RESIDUAL")
    if np.any(~np.isfinite(df_zero)) or np.any(df_zero < 0):
        raise RuntimeError(f"{output_label}_INVALID_DF_RESIDUAL_ZEROS")
    if np.any(~np.isfinite(var_post)) or np.any(var_post < 0):
        raise RuntimeError(f"{output_label}_INVALID_VAR_POST")
    if np.any(np.isnan(var_prior)) or np.any(var_prior < 0):
        raise RuntimeError(f"{output_label}_INVALID_VAR_PRIOR")
    if np.any(np.isnan(df_prior)) or np.any(df_prior <= 0):
        raise RuntimeError(f"{output_label}_INVALID_DF_PRIOR")

    # The group-means design has 72 - 3 = 69 ordinary residual df.
    if not np.all(df_resid == 69):
        raise RuntimeError(
            f"{output_label}_UNEXPECTED_RESIDUAL_DF "
            f"observed_unique={np.unique(df_resid)}"
        )

    q_dev = quantiles(deviance)
    q_zero = quantiles(df_zero)
    q_vpost = quantiles(var_post)
    q_vprior = quantiles(var_prior)
    q_dfprior = quantiles(df_prior)
    q_ave = quantiles(ave_arr)

    summary_rows.append({
        "modality": output_label,
        "features": int(y.shape[0]),
        "samples": int(y.shape[1]),
        "fractional_values": fractional_count,
        "dispersion_method": "CoxReid_common",
        "dispersion_subset_rows": subset,
        "common_dispersion": float(common),
        "biological_coefficient_of_variation": bcv,
        "ql_abundance_trend": "YES",
        "ql_robust": "NO",
        "winsor_lower": np.nan,
        "winsor_upper": np.nan,
        "glm_fit_method": str(getattr(fit, "method", "")),
        "ordinary_residual_df": 69,
        "genes_with_zero_adjusted_residual_df_zero": int(np.sum(df_zero == 0)),
        "aveLogCPM_offset_vs_effective_lib_max_abs_diff": route_diff,
        "aveLogCPM_tmm_vs_raw_library_max_abs_diff": normalization_effect,
        "ql_fit_offset_max_abs_diff": offset_diff,
        "counts_preserved_exactly": "YES",
    })

    diagnostics = {
        "deviance": q_dev,
        "df_residual_zeros": q_zero,
        "var_post": q_vpost,
        "var_prior": q_vprior,
        "df_prior": q_dfprior,
        "AveLogCPM": q_ave,
    }

    for metric, q in diagnostics.items():
        diagnostic_rows.append({
            "modality": output_label,
            "metric": metric,
            **q,
        })

    put(f"{output_label}_COMMON_DISPERSION", float(common))
    put(f"{output_label}_BCV", bcv)
    put(f"{output_label}_QLFIT_COUNTS_PRESERVED", "YES")
    put(f"{output_label}_QLFIT_OFFSET_PRESERVED", "YES")
    put(f"{output_label}_QLFIT_DESIGN_PRESERVED", "YES")
    put(f"{output_label}_QLFIT_COEFFICIENTS_FINITE", "YES")
    put(f"{output_label}_QLFIT_VAR_POST_VALID", "YES")
    put(f"{output_label}_QLFIT_DF_PRIOR_VALID", "YES")
    put(f"{output_label}_AVELOGCPM_OFFSET_ROUTE_MAX_ABS_DIFF", route_diff)
    put(f"{output_label}_TMM_NORMALIZATION_NUMERICAL_EFFECT", normalization_effect)
    put(f"{output_label}_REAL_QL_MODEL_PREFLIGHT", "PASS")


fit_modality(
    mrna,
    "mRNA",
    "MRNA",
)

fit_modality(
    mirna,
    "miRNA_mature_median_primary",
    "MIRNA",
)

pd.DataFrame(summary_rows).to_csv(MODEL_SUMMARY, index=False)
pd.DataFrame(diagnostic_rows).to_csv(MODEL_DIAGNOSTICS, index=False)


# ------------------------------------------------------------
# E. Freeze exact DE model implementation for D6
# ------------------------------------------------------------
freeze_lines = [
    "GSE243219_D5_FROZEN_DE_MODEL_IMPLEMENTATION",
    "DE_ENGINE_FAMILY=EDGER_STYLE_NEGATIVE_BINOMIAL_QUASI_LIKELIHOOD",
    "PYTHON_IMPLEMENTATION=INMOOSE_0.9.1_EDGEPY_LOW_LEVEL",
    "DGELIST_USED=NO",
    "DGELIST_AUTHORIZED_FOR_FRACTIONAL_COUNTS=NO",
    "COUNT_INPUT=FILTERED_RAW_COUNTS",
    "COUNT_ROUNDING=PROHIBITED",
    "NORMALIZATION=TMM_EFFECTIVE_LIBRARY_SIZE_OFFSETS",
    "OFFSET=LOG_EFFECTIVE_LIBRARY_SIZE",
    "OFFSET_VECTOR_LENGTH=72",
    "NB_DISPERSION_METHOD=COX_REID_COMMON",
    "NB_DISPERSION_IS_GLOBAL=YES",
    "TAGWISE_NB_DISPERSION_FOR_QL=PROHIBITED",
    "QL_ABUNDANCE_TREND=TRUE",
    "QL_ROBUST=FALSE",
    "QL_WINSOR_TAIL_P=NOT_USED_ROBUST_FALSE",
    "AVELOGCPM_COMPUTATION=EXPLICIT_EFFECTIVE_LIBRARY_OFFSET",
    "GLMQLFIT_AVELOGCPM_EXPLICITLY_SUPPLIED=YES",
    "DESIGN_PARAMETERIZATION=NO_INTERCEPT_GROUP_MEANS",
    "DESIGN_COLUMNS=COVID19|SEPSIS|HEALTHY",
    "DESIGN_RANK=3",
    "PRIMARY_CONTRAST=COV_vs_H",
    "PRIMARY_CONTRAST_VECTOR=1|0|-1",
    "SEPSIS_COMPARATOR_CONTRAST=P_vs_H",
    "SEPSIS_COMPARATOR_VECTOR=0|1|-1",
    "COVID_SPECIFICITY_CONTRAST=COV_vs_P",
    "COVID_SPECIFICITY_VECTOR=1|-1|0",
    "QL_HYPOTHESIS_TEST=GLMQLFTEST",
    "POISSON_BOUND_PROSPECTIVE_SETTING=TRUE",
    "MULTIPLE_TESTING=BENJAMINI_HOCHBERG_FDR",
    "ROBUST_TRUE_SUPPORTED_BY_INMOOSE_0.9.1=NO",
    "ROBUST_TRUE_POLICY=PROHIBITED",
    "GLMQLFTEST_EXECUTED_IN_D5_V2=NO",
    "GLMLRT_EXECUTED_IN_D5_V2=NO",
    "PVALUES_COMPUTED_IN_D5_V2=NO",
    "DE_EXECUTED_IN_D5_V2=NO",
]
IMPLEMENTATION_FREEZE.write_text(
    "\n".join(freeze_lines) + "\n",
    encoding="utf-8",
)

put("COMMON_NB_DISPERSION_STRATEGY_FROZEN", "YES")
put("TAGWISE_NB_DISPERSION_FOR_QL", "PROHIBITED")
put("QL_ABUNDANCE_TREND", "TRUE")
put("QL_ROBUST", "FALSE")
put("QL_WINSOR_TAIL_P", "NOT_USED_ROBUST_FALSE")
put("GLMQLFTEST_EXECUTED", "NO")
put("GLMLRT_EXECUTED", "NO")
put("PVALUES_COMPUTED", "NO")
put("FDR_COMPUTED", "NO")
put("DE_EXECUTED", "NO")
put("ROBUST_TRUE_POLICY", "PROHIBITED")
put("REAL_DE_MODEL_DISPERSION_PREFLIGHT", "PASS")
put("READY_FOR_D6_DIFFERENTIAL_EXPRESSION_EXECUTION", "YES")
put("NEXT_PHASE", "D6_DIFFERENTIAL_EXPRESSION_EXECUTION")

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
    $MrnaCounts,
    $MirnaCounts,
    $Cohort,
    $OffsetTable,
    $DesignMatrix,
    $ContrastMatrix,
    $EngineSpec,
    $ApiAudit,
    $ModelSummary,
    $ModelDiagnostics,
    $ImplementationFreeze,
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
        Write-Host '=== D5 PYTHON STDERR ==='
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
    throw ('D5_PYTHON_FAILED exit={0} full_traceback={1}' -f $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D5_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('LOCAL_INMOOSE_API_AUDIT','PASS'),
    @('QL_GLOBAL_DISPERSION_REQUIREMENT_CONFIRMED','YES'),
    @('ROBUST_SQUEEZEVAR_UNSUPPORTED_CONFIRMED','YES'),
    @('DGELIST_INTEGER_CAST_RECONFIRMED','YES'),
    @('DGELIST_USED_FOR_REAL_DATA','NO'),
    @('D4_REAL_INPUT_INTEGRITY','PASS'),
    @('SYNTHETIC_NONROBUST_QL_PATH_PREFLIGHT','PASS'),
    @('MRNA_QLFIT_COUNTS_PRESERVED','YES'),
    @('MRNA_QLFIT_OFFSET_PRESERVED','YES'),
    @('MRNA_QLFIT_DESIGN_PRESERVED','YES'),
    @('MRNA_QLFIT_COEFFICIENTS_FINITE','YES'),
    @('MRNA_QLFIT_VAR_POST_VALID','YES'),
    @('MRNA_QLFIT_DF_PRIOR_VALID','YES'),
    @('MRNA_REAL_QL_MODEL_PREFLIGHT','PASS'),
    @('MIRNA_QLFIT_COUNTS_PRESERVED','YES'),
    @('MIRNA_QLFIT_OFFSET_PRESERVED','YES'),
    @('MIRNA_QLFIT_DESIGN_PRESERVED','YES'),
    @('MIRNA_QLFIT_COEFFICIENTS_FINITE','YES'),
    @('MIRNA_QLFIT_VAR_POST_VALID','YES'),
    @('MIRNA_QLFIT_DF_PRIOR_VALID','YES'),
    @('MIRNA_REAL_QL_MODEL_PREFLIGHT','PASS'),
    @('COMMON_NB_DISPERSION_STRATEGY_FROZEN','YES'),
    @('TAGWISE_NB_DISPERSION_FOR_QL','PROHIBITED'),
    @('QL_ABUNDANCE_TREND','TRUE'),
    @('QL_ROBUST','FALSE'),
    @('QL_WINSOR_TAIL_P','NOT_USED_ROBUST_FALSE'),
    @('GLMQLFTEST_EXECUTED','NO'),
    @('GLMLRT_EXECUTED','NO'),
    @('PVALUES_COMPUTED','NO'),
    @('FDR_COMPUTED','NO'),
    @('DE_EXECUTED','NO'),
    @('ROBUST_TRUE_POLICY','PROHIBITED'),
    @('REAL_DE_MODEL_DISPERSION_PREFLIGHT','PASS'),
    @('READY_FOR_D6_DIFFERENTIAL_EXPRESSION_EXECUTION','YES'),
    @('NEXT_PHASE','D6_DIFFERENTIAL_EXPRESSION_EXECUTION')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D5_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 3. Decision
# ------------------------------------------------------------
@(
    'GSE243219_D5_V2_DECISION',
    'PHASE_D5_V2_STATUS=PASS',
    'MODE=REAL_MODEL_FIT_PREFLIGHT_WITHOUT_HYPOTHESIS_TESTING',
    'QL_IMPLEMENTATION_REVISION=ROBUST_FALSE_DUE_INMOOSE_0.9.1_LIMITATION',
    'D4_CERTIFICATION_GATE=PASS',
    'D4_OUTPUTS_RECERTIFIED=14/14',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('INMOOSE_VERSION={0}' -f $InMooseVersion),
    'LOCAL_INMOOSE_API_AUDIT=PASS',
    'QL_GLOBAL_DISPERSION_REQUIREMENT_CONFIRMED=YES',
    'ROBUST_SQUEEZEVAR_UNSUPPORTED_CONFIRMED=YES',
    'ROBUST_TRUE_POLICY=PROHIBITED',
    'DGELIST_INTEGER_CAST_RECONFIRMED=YES',
    'DGELIST_USED_FOR_REAL_DATA=NO',
    'REAL_FILTERED_COUNTS_READ=YES',
    'REAL_COMMON_DISPERSION_ESTIMATION_EXECUTED=YES',
    'NB_DISPERSION_METHOD=COX_REID_COMMON',
    'NB_DISPERSION_IS_GLOBAL=YES',
    'TAGWISE_NB_DISPERSION_FOR_QL=PROHIBITED',
    ('MRNA_COMMON_DISPERSION={0}' -f (Cap 'MRNA_COMMON_DISPERSION')),
    ('MRNA_BCV={0}' -f (Cap 'MRNA_BCV')),
    ('MIRNA_COMMON_DISPERSION={0}' -f (Cap 'MIRNA_COMMON_DISPERSION')),
    ('MIRNA_BCV={0}' -f (Cap 'MIRNA_BCV')),
    'REAL_QL_MODEL_FIT_EXECUTED=YES',
    'QL_ABUNDANCE_TREND=TRUE',
    'QL_ROBUST=FALSE',
    'QL_WINSOR_TAIL_P=NOT_USED_ROBUST_FALSE',
    'AVELOGCPM_COMPUTATION=EXPLICIT_EFFECTIVE_LIBRARY_OFFSET',
    'MRNA_QLFIT_COUNTS_PRESERVED=YES',
    'MRNA_QLFIT_OFFSET_PRESERVED=YES',
    'MRNA_QLFIT_DESIGN_PRESERVED=YES',
    'MRNA_REAL_QL_MODEL_PREFLIGHT=PASS',
    'MIRNA_QLFIT_COUNTS_PRESERVED=YES',
    'MIRNA_QLFIT_OFFSET_PRESERVED=YES',
    'MIRNA_QLFIT_DESIGN_PRESERVED=YES',
    'MIRNA_REAL_QL_MODEL_PREFLIGHT=PASS',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'FEATURE_REFILTERING_EXECUTED=NO',
    'TMM_RECOMPUTATION_EXECUTED=NO',
    'GLMQLFTEST_EXECUTED=NO',
    'GLMLRT_EXECUTED=NO',
    'CONTRAST_TESTING_EXECUTED=NO',
    'PVALUES_COMPUTED=NO',
    'FDR_COMPUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'REAL_DE_MODEL_DISPERSION_PREFLIGHT=PASS',
    'READY_FOR_D6_DIFFERENTIAL_EXPRESSION_EXECUTION=YES',
    'READY_FOR_DE_EXECUTION=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D6_DIFFERENTIAL_EXPRESSION_EXECUTION',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Manifest
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $ApiAudit,
    $ModelSummary,
    $ModelDiagnostics,
    $ImplementationFreeze,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D5_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p

    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D5SHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D5-V2 SUMMARY ===',
    'PHASE_D5_V2_STATUS=PASS',
    'MODE=REAL_MODEL_FIT_PREFLIGHT_WITHOUT_HYPOTHESIS_TESTING',
    'QL_IMPLEMENTATION_REVISION=ROBUST_FALSE_DUE_INMOOSE_0.9.1_LIMITATION',
    'D4_CERTIFICATION_GATE=PASS',
    'D4_OUTPUTS_RECERTIFIED=14/14',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('INMOOSE_VERSION={0}' -f $InMooseVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    ('SCIPY_VERSION={0}' -f $ScipyVersion),
    'LOCAL_INMOOSE_API_AUDIT=PASS',
    'QL_GLOBAL_DISPERSION_REQUIREMENT_CONFIRMED=YES',
    'ROBUST_SQUEEZEVAR_UNSUPPORTED_CONFIRMED=YES',
    'ROBUST_TRUE_POLICY=PROHIBITED',
    'DGELIST_INTEGER_CAST_RECONFIRMED=YES',
    'DGELIST_USED_FOR_REAL_DATA=NO',
    'D4_REAL_INPUT_INTEGRITY=PASS',
    'SYNTHETIC_NONROBUST_QL_PATH_PREFLIGHT=PASS',
    'REAL_FILTERED_COUNTS_READ=YES',
    'REAL_COMMON_DISPERSION_ESTIMATION_EXECUTED=YES',
    'NB_DISPERSION_METHOD=COX_REID_COMMON',
    'NB_DISPERSION_IS_GLOBAL=YES',
    'TAGWISE_NB_DISPERSION_FOR_QL=PROHIBITED',
    ('MRNA_COMMON_DISPERSION={0}' -f (Cap 'MRNA_COMMON_DISPERSION')),
    ('MRNA_BCV={0}' -f (Cap 'MRNA_BCV')),
    ('MIRNA_COMMON_DISPERSION={0}' -f (Cap 'MIRNA_COMMON_DISPERSION')),
    ('MIRNA_BCV={0}' -f (Cap 'MIRNA_BCV')),
    'REAL_QL_MODEL_FIT_EXECUTED=YES',
    'QL_ABUNDANCE_TREND=TRUE',
    'QL_ROBUST=FALSE',
    'QL_WINSOR_TAIL_P=NOT_USED_ROBUST_FALSE',
    'AVELOGCPM_COMPUTATION=EXPLICIT_EFFECTIVE_LIBRARY_OFFSET',
    ('MRNA_AVELOGCPM_OFFSET_ROUTE_MAX_ABS_DIFF={0}' -f (Cap 'MRNA_AVELOGCPM_OFFSET_ROUTE_MAX_ABS_DIFF')),
    ('MRNA_TMM_NORMALIZATION_NUMERICAL_EFFECT={0}' -f (Cap 'MRNA_TMM_NORMALIZATION_NUMERICAL_EFFECT')),
    'MRNA_QLFIT_COUNTS_PRESERVED=YES',
    'MRNA_QLFIT_OFFSET_PRESERVED=YES',
    'MRNA_QLFIT_DESIGN_PRESERVED=YES',
    'MRNA_QLFIT_COEFFICIENTS_FINITE=YES',
    'MRNA_QLFIT_VAR_POST_VALID=YES',
    'MRNA_QLFIT_DF_PRIOR_VALID=YES',
    'MRNA_REAL_QL_MODEL_PREFLIGHT=PASS',
    ('MIRNA_AVELOGCPM_OFFSET_ROUTE_MAX_ABS_DIFF={0}' -f (Cap 'MIRNA_AVELOGCPM_OFFSET_ROUTE_MAX_ABS_DIFF')),
    ('MIRNA_TMM_NORMALIZATION_NUMERICAL_EFFECT={0}' -f (Cap 'MIRNA_TMM_NORMALIZATION_NUMERICAL_EFFECT')),
    'MIRNA_QLFIT_COUNTS_PRESERVED=YES',
    'MIRNA_QLFIT_OFFSET_PRESERVED=YES',
    'MIRNA_QLFIT_DESIGN_PRESERVED=YES',
    'MIRNA_QLFIT_COEFFICIENTS_FINITE=YES',
    'MIRNA_QLFIT_VAR_POST_VALID=YES',
    'MIRNA_QLFIT_DF_PRIOR_VALID=YES',
    'MIRNA_REAL_QL_MODEL_PREFLIGHT=PASS',
    'COMMON_NB_DISPERSION_STRATEGY_FROZEN=YES',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'FEATURE_REFILTERING_EXECUTED=NO',
    'TMM_RECOMPUTATION_EXECUTED=NO',
    'GLMQLFTEST_EXECUTED=NO',
    'GLMLRT_EXECUTED=NO',
    'CONTRAST_TESTING_EXECUTED=NO',
    'PVALUES_COMPUTED=NO',
    'FDR_COMPUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'REAL_DE_MODEL_DISPERSION_PREFLIGHT=PASS',
    'READY_FOR_D6_DIFFERENTIAL_EXPRESSION_EXECUTION=YES',
    'READY_FOR_DE_EXECUTION=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D6_DIFFERENTIAL_EXPRESSION_EXECUTION',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D5_LOCAL_INMOOSE_API_AUDIT={0}' -f $ApiAudit)
Write-Host ('D5_MODEL_DISPERSION_SUMMARY={0}' -f $ModelSummary)
Write-Host ('D5_MODEL_DIAGNOSTICS={0}' -f $ModelDiagnostics)
Write-Host ('D5_FROZEN_IMPLEMENTATION={0}' -f $ImplementationFreeze)
Write-Host ('D5_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D5_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D5_V2=PASS'
Write-Host 'STOP=YES'
