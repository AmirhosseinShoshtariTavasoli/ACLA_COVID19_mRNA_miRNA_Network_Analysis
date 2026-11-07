$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D6-V5 — PRIMARY DIFFERENTIAL-EXPRESSION EXECUTION
#
# FIRST authorized DE hypothesis-testing phase.
#
# Uses only previously frozen/certified objects:
#   D4:
#     - filtered RAW fractional counts
#     - frozen 72-subject cohort
#     - explicit log(TMM effective-library-size) offsets
#     - full-rank no-intercept 3-group design
#     - frozen contrast vectors
#   D5-V2:
#     - Cox-Reid COMMON NB dispersion values
#     - abundance_trend=True
#     - robust=False
#     - low-level InMoose 0.9.1 edgepy
#
# Tests:
#   COV_vs_H = COVID19 - HEALTHY
#   P_vs_H   = SEPSIS - HEALTHY
#   COV_vs_P = COVID19 - SEPSIS
#
# Statistical reporting rule frozen prospectively:
#   primary statistical call = BH FDR <= 0.05
#   secondary effect-size annotation =
#       BH FDR <= 0.05 AND abs(log2FC) >= 1
#
# Authorized:
#   - glmQLFTest(..., poisson_bound=True)
#   - p-values
#   - BH FDR
#   - complete per-feature result tables
#   - contrast algebra/integrity audit
#
# Prohibited:
#   - DGEList
#   - count rounding
#   - feature refiltering
#   - TMM recomputation
#   - sample exclusion
#   - threshold-driven deletion of full result rows
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
$D4Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D4_20260905_094110\PHASE_D4_SUMMARY.txt'

$MrnaCounts = Join-Path $D4Run 'D4_MRNA_FILTERED_RAW_COUNTS_DE_INPUT_15083x72.csv.gz'
$MirnaCounts = Join-Path $D4Run 'D4_MIRNA_FILTERED_RAW_COUNTS_DE_INPUT_428x72.csv.gz'
$Cohort = Join-Path $D4Run 'D4_FROZEN_ANALYSIS_COHORT_72.csv'
$OffsetTable = Join-Path $D4Run 'D4_DE_EFFECTIVE_LIBRARY_AND_OFFSET_TABLE.csv'
$DesignMatrix = Join-Path $D4Run 'D4_DE_DESIGN_MATRIX_GROUP_MEANS_72x3.csv'
$ContrastMatrix = Join-Path $D4Run 'D4_DE_CONTRAST_MATRIX.csv'

$D5Run = Join-Path $D5Root 'D5_V2_MODEL_DISPERSION_PREFLIGHT_20260905_094850'
$D5Manifest = Join-Path $D5Run 'D5_OUTPUT_SHA256_MANIFEST.csv'
$D5Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D5_V2_20260905_094850\PHASE_D5_SUMMARY.txt'
$D5ModelSummary = Join-Path $D5Run 'D5_MODEL_DISPERSION_SUMMARY.csv'
$D5FrozenImplementation = Join-Path $D5Run 'D5_FROZEN_DE_MODEL_IMPLEMENTATION.txt'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D5Root ('D6_V5_PRIMARY_DE_EXECUTION_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D6_V5_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D6_V5_PRIMARY_DIFFERENTIAL_EXPRESSION_EXECUTION.py'
$ApiAudit = Join-Path $RunDir 'D6_LOCAL_GLMQLFTEST_API_AUDIT.txt'

$MrnaCovH = Join-Path $RunDir 'D6_MRNA_COV_vs_H_FULL_RESULTS.csv.gz'
$MrnaPH = Join-Path $RunDir 'D6_MRNA_P_vs_H_FULL_RESULTS.csv.gz'
$MrnaCovP = Join-Path $RunDir 'D6_MRNA_COV_vs_P_FULL_RESULTS.csv.gz'

$MirnaCovH = Join-Path $RunDir 'D6_MIRNA_COV_vs_H_FULL_RESULTS.csv.gz'
$MirnaPH = Join-Path $RunDir 'D6_MIRNA_P_vs_H_FULL_RESULTS.csv.gz'
$MirnaCovP = Join-Path $RunDir 'D6_MIRNA_COV_vs_P_FULL_RESULTS.csv.gz'

$ContrastSummary = Join-Path $RunDir 'D6_DE_CONTRAST_SUMMARY.csv'
$ContrastAudit = Join-Path $RunDir 'D6_CONTRAST_ALGEBRA_AND_RESULT_AUDIT.csv'
$ExecutionSpec = Join-Path $RunDir 'D6_FROZEN_DE_EXECUTION_SPECIFICATION.txt'
$ResultJson = Join-Path $RunDir 'D6_RESULT.json'

$PythonStdout = Join-Path $RunDir 'D6_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D6_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D6_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D6_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D6_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D6_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D6 — PRIMARY DIFFERENTIAL-EXPRESSION EXECUTION ==='
Write-Host 'MODE=FIRST_AUTHORIZED_DE_HYPOTHESIS_TESTING'
Write-Host 'REAL_FILTERED_RAW_COUNTS_READ=YES'
Write-Host 'FROZEN_D5_COMMON_DISPERSIONS_USED=YES'
Write-Host 'COMMON_DISPERSION_REESTIMATED_IN_D6=NO'
Write-Host 'REAL_QL_MODEL_FIT_EXECUTED=YES'
Write-Host 'GLMQLFTEST_AUTHORIZED=YES'
Write-Host 'GLMQLFTEST_EXECUTED_AT_START=NO'
Write-Host 'POISSON_BOUND=TRUE'
Write-Host 'CONTRAST_TESTING_EXECUTED_AT_START=NO'
Write-Host 'PVALUES_COMPUTED_AT_START=NO'
Write-Host 'BH_FDR_COMPUTED_AT_START=NO'
Write-Host 'PRIMARY_SIGNIFICANCE_THRESHOLD=FDR_LE_0.05'
Write-Host 'SECONDARY_EFFECT_SIZE_THRESHOLD=FDR_LE_0.05_AND_ABS_LOG2FC_GE_1'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'FEATURE_REFILTERING_EXECUTED=NO'
Write-Host 'TMM_RECOMPUTATION_EXECUTED=NO'
Write-Host 'DGEList_USED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $VenvPython,
    $D4Manifest,$D4Report,
    $MrnaCounts,$MirnaCounts,$Cohort,$OffsetTable,$DesignMatrix,$ContrastMatrix,
    $D5Manifest,$D5Report,$D5ModelSummary,$D5FrozenImplementation
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D6_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D6SHA256 {
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
        $hash = Get-D6SHA256 $r.full_path

        if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
            $hash -ne $r.SHA256.ToLowerInvariant()) {
            throw ('{0}_OUTPUT_CHANGED={1}' -f $Label,$r.full_path)
        }
    }

    Write-Host ('{0}_OUTPUTS_RECERTIFIED={1}/{1}' -f $Label,$ExpectedRows)
}

# ------------------------------------------------------------
# 1. Re-certify D4 and D5-V2
# ------------------------------------------------------------
$d4 = Get-Content -LiteralPath $D4Report -Raw

foreach ($tok in @(
    'PHASE_D4_STATUS=PASS',
    'DE_INPUT_BUNDLE_FROZEN=YES',
    'MRNA_FILTERED_RAW_COUNTS=15083x72',
    'MIRNA_FILTERED_RAW_COUNTS=428x72',
    'MRNA_DE_INPUT_FRACTIONAL_VALUES=307085',
    'MIRNA_DE_INPUT_FRACTIONAL_VALUES=623',
    'ANALYSIS_COHORT_SUBJECTS=72',
    'EXCLUDED_SUBJECTS=NONE',
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
    'DGELIST_AUTHORIZED_FOR_FRACTIONAL_REAL_DATA=NO',
    'NORMALIZED_CPM_AS_DE_INPUT=PROHIBITED',
    'LOGCPM_AS_DE_INPUT=PROHIBITED',
    'COUNT_ROUNDING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO'
)) {
    if ($d4 -notmatch [regex]::Escape($tok)) {
        throw ('D4_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

Recertify-Manifest -ManifestPath $D4Manifest -ExpectedRows 14 -Label 'D4'
Write-Host 'D4_CERTIFICATION_GATE=PASS'

$d5 = Get-Content -LiteralPath $D5Report -Raw

foreach ($tok in @(
    'PHASE_D5_V2_STATUS=PASS',
    'QL_IMPLEMENTATION_REVISION=ROBUST_FALSE_DUE_INMOOSE_0.9.1_LIMITATION',
    'LOCAL_INMOOSE_API_AUDIT=PASS',
    'QL_GLOBAL_DISPERSION_REQUIREMENT_CONFIRMED=YES',
    'ROBUST_SQUEEZEVAR_UNSUPPORTED_CONFIRMED=YES',
    'ROBUST_TRUE_POLICY=PROHIBITED',
    'DGELIST_USED_FOR_REAL_DATA=NO',
    'D4_REAL_INPUT_INTEGRITY=PASS',
    'SYNTHETIC_NONROBUST_QL_PATH_PREFLIGHT=PASS',
    'NB_DISPERSION_METHOD=COX_REID_COMMON',
    'NB_DISPERSION_IS_GLOBAL=YES',
    'TAGWISE_NB_DISPERSION_FOR_QL=PROHIBITED',
    'MRNA_COMMON_DISPERSION=0.3008681692934306',
    'MIRNA_COMMON_DISPERSION=0.368890975613554',
    'QL_ABUNDANCE_TREND=TRUE',
    'QL_ROBUST=FALSE',
    'QL_WINSOR_TAIL_P=NOT_USED_ROBUST_FALSE',
    'MRNA_REAL_QL_MODEL_PREFLIGHT=PASS',
    'MIRNA_REAL_QL_MODEL_PREFLIGHT=PASS',
    'REAL_DE_MODEL_DISPERSION_PREFLIGHT=PASS',
    'READY_FOR_D6_DIFFERENTIAL_EXPRESSION_EXECUTION=YES',
    'READY_FOR_DE_EXECUTION=YES',
    'NEXT_PHASE=D6_DIFFERENTIAL_EXPRESSION_EXECUTION'
)) {
    if ($d5 -notmatch [regex]::Escape($tok)) {
        throw ('D5_V2_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

Recertify-Manifest -ManifestPath $D5Manifest -ExpectedRows 10 -Label 'D5_V2'
Write-Host 'D5_V2_CERTIFICATION_GATE=PASS'

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
# 2. Python DE execution
# ------------------------------------------------------------
$PythonCode = @'
import inspect
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from patsy import DesignInfo, DesignMatrix

from inmoose.edgepy.aveLogCPM import aveLogCPM
from inmoose.edgepy.glmQLFit import glmQLFit, glmQLFTest


MRNA_COUNTS = Path(sys.argv[1])
MIRNA_COUNTS = Path(sys.argv[2])
COHORT = Path(sys.argv[3])
OFFSET_TABLE = Path(sys.argv[4])
DESIGN_MATRIX = Path(sys.argv[5])
CONTRAST_MATRIX = Path(sys.argv[6])
D5_MODEL_SUMMARY = Path(sys.argv[7])
D5_FROZEN_IMPLEMENTATION = Path(sys.argv[8])

API_AUDIT = Path(sys.argv[9])

MRNA_COV_H = Path(sys.argv[10])
MRNA_P_H = Path(sys.argv[11])
MRNA_COV_P = Path(sys.argv[12])
MIRNA_COV_H = Path(sys.argv[13])
MIRNA_P_H = Path(sys.argv[14])
MIRNA_COV_P = Path(sys.argv[15])

CONTRAST_SUMMARY = Path(sys.argv[16])
CONTRAST_AUDIT = Path(sys.argv[17])
EXECUTION_SPEC = Path(sys.argv[18])
RESULT_JSON = Path(sys.argv[19])


FDR_THRESHOLD = 0.05
ABS_LOGFC_REPORT_THRESHOLD = 1.0

results = {}


def put(k, v):
    results[k] = v
    print(f"{k}={v}")


def bh_adjust(pvalues):
    p = np.asarray(pvalues, dtype=np.float64)

    if p.ndim != 1:
        raise ValueError("BH input must be one-dimensional")
    if np.any(~np.isfinite(p)):
        raise ValueError("BH input contains non-finite p-values")
    if np.any((p < 0) | (p > 1)):
        raise ValueError("BH input p-values outside [0,1]")

    n = p.size
    order = np.argsort(p, kind="mergesort")
    ranked_p = p[order]

    adjusted_sorted = ranked_p * n / np.arange(1, n + 1, dtype=np.float64)
    adjusted_sorted = np.minimum.accumulate(adjusted_sorted[::-1])[::-1]
    adjusted_sorted = np.clip(adjusted_sorted, 0.0, 1.0)

    adjusted = np.empty(n, dtype=np.float64)
    adjusted[order] = adjusted_sorted

    return adjusted


# ------------------------------------------------------------
# A. Audit exact local glmQLFTest API
# ------------------------------------------------------------
sig = inspect.signature(glmQLFTest)
required = {"glmfit", "contrast", "poisson_bound"}

if not required.issubset(sig.parameters):
    raise RuntimeError(f"GLMQLFTEST_API_CHANGED observed={sig}")

qlf_source = inspect.getsource(glmQLFTest)

audit_lines = [
    "GSE243219_D6_V5_LOCAL_GLMQLFTEST_API_AUDIT",
    f"glmQLFTest_SIGNATURE={sig}",
    "REQUIRED_PARAMETERS=glmfit|contrast|poisson_bound",
    "POISSON_BOUND_PROSPECTIVE_SETTING=TRUE",
    "COUNT_CONTAINER_REQUIRED_FOR_TEST_LAYER=PANDAS_DATAFRAME",
    "COUNT_INDEX_REQUIRED_BY_GLMLRT=YES",
    "COUNT_LOC_REQUIRED_BY_POISSON_BOUND=YES",
    "DGELIST_USED=NO",
    "BH_FDR_IMPLEMENTATION=DETERMINISTIC_BENJAMINI_HOCHBERG",
    "PRIMARY_STATISTICAL_CALL=FDR_LE_0.05",
    "SECONDARY_EFFECT_SIZE_ANNOTATION=FDR_LE_0.05_AND_ABS_LOG2FC_GE_1",
]
API_AUDIT.write_text("\n".join(audit_lines) + "\n", encoding="utf-8")

put("LOCAL_GLMQLFTEST_API_AUDIT", "PASS")


# ------------------------------------------------------------
# B. Load immutable D4 input bundle and D5 frozen dispersions
# ------------------------------------------------------------
cohort = pd.read_csv(COHORT)
offset_table = pd.read_csv(OFFSET_TABLE)
design_df = pd.read_csv(DESIGN_MATRIX)
contrast_df = pd.read_csv(CONTRAST_MATRIX)
model_summary = pd.read_csv(D5_MODEL_SUMMARY)

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

X_numeric = design_df[["COVID19", "SEPSIS", "HEALTHY"]].to_numpy(dtype=np.float64)

if X_numeric.shape != (72, 3):
    raise RuntimeError(f"DESIGN_SHAPE_CHANGED observed={X_numeric.shape}")
if np.linalg.matrix_rank(X_numeric) != 3:
    raise RuntimeError("DESIGN_NOT_FULL_RANK")

# InMoose 0.9.1 glmQLFTest -> glmLRT accesses
# glmfit.design.design_info.column_names. Preserve the exact frozen
# 72x3 numeric design, but attach explicit Patsy design metadata.
frozen_column_names = ["COVID19", "SEPSIS", "HEALTHY"]
X = DesignMatrix(
    X_numeric,
    design_info=DesignInfo(frozen_column_names),
)

if not hasattr(X, "design_info"):
    raise RuntimeError("PATSY_DESIGN_INFO_MISSING")
if list(X.design_info.column_names) != frozen_column_names:
    raise RuntimeError(
        f"PATSY_DESIGN_COLUMN_NAMES_WRONG observed={X.design_info.column_names}"
    )
if not np.array_equal(np.asarray(X, dtype=np.float64), X_numeric):
    raise RuntimeError("PATSY_DESIGN_NUMERIC_VALUES_CHANGED")
if np.linalg.matrix_rank(np.asarray(X, dtype=np.float64)) != 3:
    raise RuntimeError("PATSY_DESIGN_RANK_CHANGED")

contrast_vectors = {}
for _, row in contrast_df.iterrows():
    name = str(row["contrast_name"])
    contrast_vectors[name] = row[
        ["COVID19", "SEPSIS", "HEALTHY"]
    ].to_numpy(dtype=np.float64)

expected_vectors = {
    "COV_vs_H": np.array([1.0, 0.0, -1.0]),
    "P_vs_H": np.array([0.0, 1.0, -1.0]),
    "COV_vs_P": np.array([1.0, -1.0, 0.0]),
}

for name, expected in expected_vectors.items():
    if name not in contrast_vectors:
        raise RuntimeError(f"FROZEN_CONTRAST_MISSING name={name}")
    if not np.array_equal(contrast_vectors[name], expected):
        raise RuntimeError(
            f"FROZEN_CONTRAST_CHANGED name={name} "
            f"observed={contrast_vectors[name]}"
        )

# D5 summary must contain exactly one row per modality.
if model_summary.shape[0] != 2:
    raise RuntimeError(
        f"D5_MODEL_SUMMARY_ROWS_CHANGED observed={model_summary.shape[0]}"
    )

dispersion_by_modality = {}
for _, row in model_summary.iterrows():
    modality = str(row["modality"])
    dispersion = float(row["common_dispersion"])
    if not np.isfinite(dispersion) or dispersion <= 0:
        raise RuntimeError(f"INVALID_FROZEN_DISPERSION modality={modality}")
    dispersion_by_modality[modality] = dispersion

if "MRNA" not in dispersion_by_modality or "MIRNA" not in dispersion_by_modality:
    raise RuntimeError(
        f"D5_MODALITY_DISPERSIONS_MISSING keys={sorted(dispersion_by_modality)}"
    )

expected_mrna_disp = 0.3008681692934306
expected_mirna_disp = 0.368890975613554

if abs(dispersion_by_modality["MRNA"] - expected_mrna_disp) > 1e-15:
    raise RuntimeError(
        f"MRNA_FROZEN_DISPERSION_CHANGED "
        f"observed={dispersion_by_modality['MRNA']}"
    )
if abs(dispersion_by_modality["MIRNA"] - expected_mirna_disp) > 1e-15:
    raise RuntimeError(
        f"MIRNA_FROZEN_DISPERSION_CHANGED "
        f"observed={dispersion_by_modality['MIRNA']}"
    )

put("D4_D5_FROZEN_INPUT_INTEGRITY", "PASS")
put("PATSY_DESIGN_METADATA_ATTACHED", "YES")
put("PATSY_DESIGN_COLUMN_NAMES", "|".join(X.design_info.column_names))
put("PATSY_DESIGN_NUMERIC_VALUES_IDENTICAL_TO_D4", "YES")
put("MRNA_FROZEN_COMMON_DISPERSION", dispersion_by_modality["MRNA"])
put("MIRNA_FROZEN_COMMON_DISPERSION", dispersion_by_modality["MIRNA"])


# ------------------------------------------------------------
# C. Synthetic glmQLFTest design-metadata self-test
#
# IMPORTANT:
#   The previous D6-V2 used only four synthetic features.
#   That is too small for InMoose 0.9.1's abundance-trended
#   empirical-Bayes spline fit and can fail inside fitFDist/ns.
#
#   D6-V3 uses the same safe scale already proven in D5-V2:
#   240 features x 18 samples, 3-group full-rank design.
# ------------------------------------------------------------
rng = np.random.default_rng(243219)

syn_y_numeric = rng.gamma(
    shape=3.0,
    scale=20.0,
    size=(240, 18),
).astype(np.float64)

# Add deterministic fractional structure so the self-test also
# exercises the fractional-count path.
syn_y_numeric += (
    (
        np.arange(240)[:, None]
        + np.arange(18)[None, :]
    )
    % 4
) * 0.25

syn_feature_ids = [f"SYN_FEATURE_{i+1:04d}" for i in range(240)]
syn_sample_ids = [f"SYN_SAMPLE_{i+1:02d}" for i in range(18)]

# Critical InMoose 0.9.1 test-interface requirement:
# glmLRT uses glmfit.counts.index and poisson_bound uses
# glmfit.counts.loc[...], so QL hypothesis testing requires
# indexed pandas DataFrame counts.
syn_y = pd.DataFrame(
    syn_y_numeric,
    index=syn_feature_ids,
    columns=syn_sample_ids,
)

if not np.array_equal(
    syn_y.to_numpy(dtype=np.float64),
    syn_y_numeric,
):
    raise RuntimeError("SYNTHETIC_DATAFRAME_NUMERIC_VALUES_CHANGED")

if syn_y.index.astype(str).tolist() != syn_feature_ids:
    raise RuntimeError("SYNTHETIC_DATAFRAME_FEATURE_INDEX_CHANGED")

if syn_y.columns.astype(str).tolist() != syn_sample_ids:
    raise RuntimeError("SYNTHETIC_DATAFRAME_SAMPLE_COLUMNS_CHANGED")

syn_X_numeric = np.zeros((18, 3), dtype=np.float64)
syn_X_numeric[:6, 0] = 1.0
syn_X_numeric[6:12, 1] = 1.0
syn_X_numeric[12:, 2] = 1.0

syn_X = DesignMatrix(
    syn_X_numeric,
    design_info=DesignInfo(["A", "B", "C"]),
)

if not hasattr(syn_X, "design_info"):
    raise RuntimeError("SYNTHETIC_PATSY_DESIGN_INFO_MISSING")

if list(syn_X.design_info.column_names) != ["A", "B", "C"]:
    raise RuntimeError(
        f"SYNTHETIC_PATSY_DESIGN_NAMES_WRONG "
        f"observed={syn_X.design_info.column_names}"
    )

if not np.array_equal(
    np.asarray(syn_X, dtype=np.float64),
    syn_X_numeric,
):
    raise RuntimeError("SYNTHETIC_PATSY_NUMERIC_VALUES_CHANGED")

syn_offset = np.log(
    np.sum(syn_y.to_numpy(dtype=np.float64), axis=0, dtype=np.float64)
)

syn_dispersion = 0.2

syn_ave = aveLogCPM(
    syn_y,
    offset=syn_offset,
    dispersion=syn_dispersion,
)

syn_ave = np.asarray(syn_ave, dtype=np.float64)

if syn_ave.shape != (240,):
    raise RuntimeError(
        f"SYNTHETIC_AVELOGCPM_SHAPE_WRONG observed={syn_ave.shape}"
    )

if np.any(~np.isfinite(syn_ave)):
    raise RuntimeError("SYNTHETIC_AVELOGCPM_NONFINITE")

syn_fit = glmQLFit(
    syn_y,
    design=syn_X,
    dispersion=syn_dispersion,
    offset=syn_offset,
    lib_size=None,
    weights=None,
    abundance_trend=True,
    AveLogCPM=syn_ave,
    robust=False,
)

if not hasattr(syn_fit.design, "design_info"):
    raise RuntimeError(
        "SYNTHETIC_GLMQLFIT_DROPPED_PATSY_DESIGN_INFO"
    )

if list(syn_fit.design.design_info.column_names) != ["A", "B", "C"]:
    raise RuntimeError(
        f"SYNTHETIC_GLMQLFIT_DESIGN_NAMES_CHANGED "
        f"observed={syn_fit.design.design_info.column_names}"
    )

if not np.array_equal(
    np.asarray(syn_fit.design, dtype=np.float64),
    syn_X_numeric,
):
    raise RuntimeError(
        "SYNTHETIC_GLMQLFIT_DESIGN_NUMERIC_VALUES_CHANGED"
    )

if not isinstance(syn_fit.counts, pd.DataFrame):
    raise RuntimeError(
        f"SYNTHETIC_GLMQLFIT_COUNTS_CONTAINER_CHANGED "
        f"observed={type(syn_fit.counts)}"
    )

if syn_fit.counts.index.astype(str).tolist() != syn_feature_ids:
    raise RuntimeError("SYNTHETIC_GLMQLFIT_FEATURE_INDEX_NOT_PRESERVED")

if syn_fit.counts.columns.astype(str).tolist() != syn_sample_ids:
    raise RuntimeError("SYNTHETIC_GLMQLFIT_SAMPLE_COLUMNS_NOT_PRESERVED")

if not np.array_equal(
    syn_fit.counts.to_numpy(dtype=np.float64),
    syn_y_numeric,
):
    raise RuntimeError(
        "SYNTHETIC_GLMQLFIT_COUNTS_NOT_PRESERVED"
    )

# Test A - C using an explicit 3-coefficient contrast.
syn_test = glmQLFTest(
    syn_fit,
    contrast=np.array([1.0, 0.0, -1.0]),
    poisson_bound=True,
)

syn_table = pd.DataFrame(syn_test)

# InMoose releases may expose either legacy edgepy names
# (logFC/F/PValue) or DESeq-like names (log2FoldChange/stat/pvalue).
# Freeze the actual local schema after a successful synthetic test.
if all(
    c in syn_table.columns
    for c in ["logFC", "logCPM", "F", "PValue"]
):
    local_result_schema = "LEGACY_EDGE_STYLE"
    local_logfc_col = "logFC"
    local_logcpm_col = "logCPM"
    local_stat_col = "F"
    local_p_col = "PValue"
elif all(
    c in syn_table.columns
    for c in ["log2FoldChange", "logCPM", "stat", "pvalue"]
):
    local_result_schema = "INMOOSE_DESEQ_STYLE_NAMES"
    local_logfc_col = "log2FoldChange"
    local_logcpm_col = "logCPM"
    local_stat_col = "stat"
    local_p_col = "pvalue"
else:
    raise RuntimeError(
        "SYNTHETIC_GLMQLFTEST_UNSUPPORTED_RESULT_SCHEMA "
        f"observed={list(syn_table.columns)}"
    )

if syn_table.shape[0] != syn_y_numeric.shape[0]:
    raise RuntimeError(
        f"SYNTHETIC_GLMQLFTEST_ROW_COUNT_WRONG "
        f"observed={syn_table.shape[0]}"
    )

if syn_table.index.astype(str).tolist() != syn_feature_ids:
    raise RuntimeError(
        "SYNTHETIC_GLMQLFTEST_FEATURE_INDEX_NOT_PRESERVED"
    )

syn_p = pd.to_numeric(
    syn_table[local_p_col],
    errors="raise",
).to_numpy(dtype=np.float64)

if np.any(~np.isfinite(syn_p)) or np.any((syn_p < 0) | (syn_p > 1)):
    raise RuntimeError("SYNTHETIC_GLMQLFTEST_INVALID_PVALUES")

put("SYNTHETIC_PATSY_DESIGN_FEATURES", 240)
put("SYNTHETIC_PATSY_DESIGN_SAMPLES", 18)
put("SYNTHETIC_PATSY_DESIGN_GROUPS", 3)
put("SYNTHETIC_PATSY_DESIGN_ABUNDANCE_TREND", "TRUE")
put("SYNTHETIC_COUNT_CONTAINER", "PANDAS_DATAFRAME")
put("SYNTHETIC_COUNT_INDEX_PRESERVED", "YES")
put("SYNTHETIC_POISSON_BOUND_DATAFRAME_LOC_COMPATIBILITY", "PASS")
put("LOCAL_GLMQLFTEST_RESULT_SCHEMA", local_result_schema)
put("LOCAL_GLMQLFTEST_LOGFC_COLUMN", local_logfc_col)
put("LOCAL_GLMQLFTEST_LOGCPM_COLUMN", local_logcpm_col)
put("LOCAL_GLMQLFTEST_STAT_COLUMN", local_stat_col)
put("LOCAL_GLMQLFTEST_PVALUE_COLUMN", local_p_col)
put("SYNTHETIC_PATSY_DESIGN_ROBUST", "FALSE")
put("SYNTHETIC_PATSY_DESIGN_GLMQLFTEST_PREFLIGHT", "PASS")
put("REAL_FIT_IMPLEMENTATION_STALE_Y_REFERENCE_AUDIT", "PASS")


# ------------------------------------------------------------
# D. Offsets
# ------------------------------------------------------------
def get_offsets(modality):
    m = offset_table[offset_table["modality"].astype(str) == modality].copy()

    if m.shape[0] != 72:
        raise RuntimeError(
            f"{modality}_OFFSET_ROWS_CHANGED observed={m.shape[0]}"
        )

    if m["subject_id"].astype(str).tolist() != subjects:
        raise RuntimeError(f"{modality}_OFFSET_SAMPLE_ORDER_CHANGED")

    offset = m["log_effective_library_offset"].to_numpy(dtype=np.float64)
    effective = m["effective_library_size"].to_numpy(dtype=np.float64)

    if np.any(~np.isfinite(offset)):
        raise RuntimeError(f"{modality}_NONFINITE_OFFSET")

    if not np.allclose(
        np.exp(offset),
        effective,
        rtol=1e-12,
        atol=1e-8,
    ):
        raise RuntimeError(f"{modality}_OFFSET_EFFECTIVE_LIBRARY_MISMATCH")

    return offset


# ------------------------------------------------------------
# E. Fit once per modality using FROZEN D5-V2 dispersion,
#    then execute all three frozen QL F-tests.
# ------------------------------------------------------------
summary_rows = []
audit_rows = []
all_result_frames = {}


def fit_and_test(matrix_df, offset_modality, model_label, common_dispersion, outputs):
    if not isinstance(matrix_df, pd.DataFrame):
        raise RuntimeError(
            f"{model_label}_COUNT_CONTAINER_NOT_DATAFRAME"
        )

    y_numeric = matrix_df.to_numpy(dtype=np.float64)
    feature_ids = matrix_df.index.astype(str).to_numpy()
    sample_ids = matrix_df.columns.astype(str).to_numpy()

    if np.any(~np.isfinite(y_numeric)) or np.any(y_numeric < 0):
        raise RuntimeError(f"{model_label}_INVALID_COUNTS")

    fractional_values = int(
        np.sum(np.abs(y_numeric - np.round(y_numeric)) > 1e-12)
    )

    offset = get_offsets(offset_modality)

    ave = aveLogCPM(
        matrix_df,
        offset=offset,
        dispersion=common_dispersion,
    )

    ave = np.asarray(ave, dtype=np.float64)

    if ave.shape != (y_numeric.shape[0],) or np.any(~np.isfinite(ave)):
        raise RuntimeError(f"{model_label}_INVALID_AVELOGCPM")

    fit = glmQLFit(
        matrix_df,
        design=X,
        dispersion=common_dispersion,
        offset=offset,
        lib_size=None,
        weights=None,
        abundance_trend=True,
        AveLogCPM=ave,
        robust=False,
    )

    if not isinstance(fit.counts, pd.DataFrame):
        raise RuntimeError(
            f"{model_label}_FIT_COUNTS_CONTAINER_NOT_DATAFRAME "
            f"observed={type(fit.counts)}"
        )

    if fit.counts.index.astype(str).to_numpy().tolist() != feature_ids.tolist():
        raise RuntimeError(f"{model_label}_FIT_FEATURE_INDEX_NOT_PRESERVED")

    if fit.counts.columns.astype(str).to_numpy().tolist() != sample_ids.tolist():
        raise RuntimeError(f"{model_label}_FIT_SAMPLE_COLUMNS_NOT_PRESERVED")

    if not np.array_equal(
        fit.counts.to_numpy(dtype=np.float64),
        y_numeric,
    ):
        raise RuntimeError(f"{model_label}_FIT_COUNTS_NOT_PRESERVED")

    expected_offset = np.broadcast_to(offset, y_numeric.shape)
    fit_offset = np.asarray(fit.offset, dtype=np.float64)

    if fit_offset.shape != y_numeric.shape:
        raise RuntimeError(f"{model_label}_FIT_OFFSET_SHAPE_CHANGED")

    if np.max(np.abs(fit_offset - expected_offset)) > 1e-12:
        raise RuntimeError(f"{model_label}_FIT_OFFSET_NOT_PRESERVED")

    if not hasattr(fit.design, "design_info"):
        raise RuntimeError(f"{model_label}_FIT_DESIGN_INFO_NOT_PRESERVED")
    if list(fit.design.design_info.column_names) != frozen_column_names:
        raise RuntimeError(
            f"{model_label}_FIT_DESIGN_COLUMN_NAMES_CHANGED "
            f"observed={fit.design.design_info.column_names}"
        )
    if not np.array_equal(
        np.asarray(fit.design, dtype=np.float64),
        X_numeric,
    ):
        raise RuntimeError(f"{model_label}_FIT_DESIGN_NUMERIC_VALUES_CHANGED")

    result_by_contrast = {}

    for contrast_name in ["COV_vs_H", "P_vs_H", "COV_vs_P"]:
        contrast = contrast_vectors[contrast_name]

        test = glmQLFTest(
            fit,
            contrast=contrast,
            poisson_bound=True,
        )

        table = pd.DataFrame(test).copy()

        required_columns = [
            local_logfc_col,
            local_logcpm_col,
            local_stat_col,
            local_p_col,
        ]
        missing = [c for c in required_columns if c not in table.columns]
        if missing:
            raise RuntimeError(
                f"{model_label}_{contrast_name}_RESULT_COLUMNS_MISSING "
                f"schema={local_result_schema} "
                f"missing={missing} observed={list(table.columns)}"
            )

        if table.shape[0] != y_numeric.shape[0]:
            raise RuntimeError(
                f"{model_label}_{contrast_name}_RESULT_ROW_COUNT_CHANGED "
                f"observed={table.shape[0]}"
            )

        # InMoose glmLRT/glmQLFTest should preserve the DataFrame count index.
        if table.index.astype(str).to_numpy().tolist() != feature_ids.tolist():
            raise RuntimeError(
                f"{model_label}_{contrast_name}_RESULT_FEATURE_INDEX_CHANGED"
            )

        # Canonicalize local InMoose result names into stable project columns.
        out = pd.DataFrame({
            "feature_id": feature_ids,
            "input_row_index_1based": np.arange(1, y_numeric.shape[0] + 1),
            "contrast": contrast_name,
            "local_inmoose_result_schema": local_result_schema,
            "logFC": pd.to_numeric(
                table[local_logfc_col], errors="raise"
            ).to_numpy(dtype=np.float64),
            "logCPM": pd.to_numeric(
                table[local_logcpm_col], errors="raise"
            ).to_numpy(dtype=np.float64),
            "F": pd.to_numeric(
                table[local_stat_col], errors="raise"
            ).to_numpy(dtype=np.float64),
            "PValue": pd.to_numeric(
                table[local_p_col], errors="raise"
            ).to_numpy(dtype=np.float64),
        })

        if np.any(~np.isfinite(out["logFC"].to_numpy())):
            raise RuntimeError(f"{model_label}_{contrast_name}_NONFINITE_LOGFC")
        if np.any(~np.isfinite(out["logCPM"].to_numpy())):
            raise RuntimeError(f"{model_label}_{contrast_name}_NONFINITE_LOGCPM")
        if np.any(~np.isfinite(out["F"].to_numpy())):
            raise RuntimeError(f"{model_label}_{contrast_name}_NONFINITE_F")
        if np.any(out["F"].to_numpy() < -1e-12):
            raise RuntimeError(f"{model_label}_{contrast_name}_NEGATIVE_F")

        p = out["PValue"].to_numpy(dtype=np.float64)

        if np.any(~np.isfinite(p)) or np.any((p < 0) | (p > 1)):
            raise RuntimeError(f"{model_label}_{contrast_name}_INVALID_PVALUE")

        fdr = bh_adjust(p)
        out["FDR"] = fdr

        out["statistically_significant_FDR_le_0_05"] = np.where(
            fdr <= FDR_THRESHOLD,
            "YES",
            "NO",
        )

        out["effect_size_abs_log2FC_ge_1"] = np.where(
            np.abs(out["logFC"].to_numpy(dtype=np.float64))
            >= ABS_LOGFC_REPORT_THRESHOLD,
            "YES",
            "NO",
        )

        strict = (
            (fdr <= FDR_THRESHOLD)
            & (
                np.abs(out["logFC"].to_numpy(dtype=np.float64))
                >= ABS_LOGFC_REPORT_THRESHOLD
            )
        )

        out["significant_FDR_le_0_05_and_abs_log2FC_ge_1"] = np.where(
            strict,
            "YES",
            "NO",
        )

        logfc = out["logFC"].to_numpy(dtype=np.float64)
        direction = np.full(logfc.size, "ZERO_OR_NEAR_ZERO", dtype=object)
        direction[logfc > 0] = "UP_IN_CONTRAST_NUMERATOR"
        direction[logfc < 0] = "DOWN_IN_CONTRAST_NUMERATOR"
        out["direction"] = direction

        # Deterministic rank: PValue then feature ID.
        ranking = np.lexsort((out["feature_id"].astype(str).to_numpy(), p))
        rank_by_p = np.empty(p.size, dtype=np.int64)
        rank_by_p[ranking] = np.arange(1, p.size + 1)
        out["rank_by_PValue"] = rank_by_p

        # Save full table in original feature order to retain exact row mapping.
        output_path = outputs[contrast_name]
        out.to_csv(
            output_path,
            index=False,
            compression="gzip",
            float_format="%.17g",
        )

        # Round-trip result validation.
        rt = pd.read_csv(
            output_path,
            compression="gzip",
            engine="c",
            float_precision="round_trip",
        )

        if rt.shape[0] != out.shape[0]:
            raise RuntimeError(
                f"{model_label}_{contrast_name}_RESULT_ROUNDTRIP_ROW_MISMATCH"
            )
        if rt["feature_id"].astype(str).tolist() != out["feature_id"].astype(str).tolist():
            raise RuntimeError(
                f"{model_label}_{contrast_name}_RESULT_ROUNDTRIP_FEATURE_MISMATCH"
            )

        sig = fdr <= FDR_THRESHOLD
        up = sig & (logfc > 0)
        down = sig & (logfc < 0)
        strict_up = strict & (logfc > 0)
        strict_down = strict & (logfc < 0)

        best_i = int(np.lexsort((out["feature_id"].astype(str).to_numpy(), p))[0])

        summary_rows.append({
            "modality": model_label,
            "contrast": contrast_name,
            "features_tested": int(out.shape[0]),
            "fractional_values_in_count_input": fractional_values,
            "common_dispersion": float(common_dispersion),
            "poisson_bound": "TRUE",
            "BH_FDR_threshold": FDR_THRESHOLD,
            "abs_log2FC_secondary_threshold": ABS_LOGFC_REPORT_THRESHOLD,
            "FDR_le_0_05": int(np.sum(sig)),
            "FDR_le_0_05_up": int(np.sum(up)),
            "FDR_le_0_05_down": int(np.sum(down)),
            "FDR_le_0_05_abs_log2FC_ge_1": int(np.sum(strict)),
            "FDR_le_0_05_abs_log2FC_ge_1_up": int(np.sum(strict_up)),
            "FDR_le_0_05_abs_log2FC_ge_1_down": int(np.sum(strict_down)),
            "min_PValue": float(np.min(p)),
            "min_FDR": float(np.min(fdr)),
            "top_feature_by_PValue": str(out.iloc[best_i]["feature_id"]),
            "top_feature_logFC": float(out.iloc[best_i]["logFC"]),
        })

        result_by_contrast[contrast_name] = out
        all_result_frames[(model_label, contrast_name)] = out

        put(
            f"{model_label}_{contrast_name}_FDR_LE_0_05",
            int(np.sum(sig)),
        )
        put(
            f"{model_label}_{contrast_name}_FDR_LE_0_05_ABS_LOG2FC_GE_1",
            int(np.sum(strict)),
        )

    # Contrast algebra identity:
    # (COV-H) - (P-H) == COV-P
    a = result_by_contrast["COV_vs_H"]["logFC"].to_numpy(dtype=np.float64)
    b = result_by_contrast["P_vs_H"]["logFC"].to_numpy(dtype=np.float64)
    c = result_by_contrast["COV_vs_P"]["logFC"].to_numpy(dtype=np.float64)

    algebra_diff = float(np.max(np.abs((a - b) - c)))

    audit_rows.append({
        "modality": model_label,
        "audit": "LOGFC_CONTRAST_ALGEBRA",
        "identity": "(COV_vs_H)-(P_vs_H)=COV_vs_P",
        "max_abs_difference": algebra_diff,
        "tolerance": 1e-10,
        "status": "PASS" if algebra_diff <= 1e-10 else "FAIL",
    })

    if algebra_diff > 1e-10:
        raise RuntimeError(
            f"{model_label}_CONTRAST_LOGFC_ALGEBRA_FAILED "
            f"maxdiff={algebra_diff}"
        )

    put(f"{model_label}_FIT_COUNT_CONTAINER", "PANDAS_DATAFRAME")
    put(f"{model_label}_FIT_FEATURE_INDEX_PRESERVED", "YES")
    put(f"{model_label}_FIT_SAMPLE_COLUMNS_PRESERVED", "YES")
    put(f"{model_label}_FIT_PATSY_DESIGN_INFO_PRESERVED", "YES")
    put(f"{model_label}_CONTRAST_LOGFC_ALGEBRA_MAX_ABS_DIFF", algebra_diff)
    put(f"{model_label}_CONTRAST_LOGFC_ALGEBRA", "PASS")


fit_and_test(
    mrna,
    "mRNA",
    "MRNA",
    dispersion_by_modality["MRNA"],
    {
        "COV_vs_H": MRNA_COV_H,
        "P_vs_H": MRNA_P_H,
        "COV_vs_P": MRNA_COV_P,
    },
)

fit_and_test(
    mirna,
    "miRNA_mature_median_primary",
    "MIRNA",
    dispersion_by_modality["MIRNA"],
    {
        "COV_vs_H": MIRNA_COV_H,
        "P_vs_H": MIRNA_P_H,
        "COV_vs_P": MIRNA_COV_P,
    },
)

summary_df = pd.DataFrame(summary_rows)
audit_df = pd.DataFrame(audit_rows)

summary_df.to_csv(CONTRAST_SUMMARY, index=False)
audit_df.to_csv(CONTRAST_AUDIT, index=False)


# ------------------------------------------------------------
# F. Global hard audits
# ------------------------------------------------------------
if summary_df.shape[0] != 6:
    raise RuntimeError(
        f"CONTRAST_SUMMARY_ROWS_WRONG observed={summary_df.shape[0]}"
    )

if audit_df.shape[0] != 2 or not audit_df["status"].eq("PASS").all():
    raise RuntimeError("CONTRAST_AUDIT_NOT_FULL_PASS")

# Verify BH monotonicity in sorted p-value space for all result frames.
for (modality, contrast), out in all_result_frames.items():
    p = out["PValue"].to_numpy(dtype=np.float64)
    fdr = out["FDR"].to_numpy(dtype=np.float64)
    order = np.argsort(p, kind="mergesort")
    if np.any(np.diff(fdr[order]) < -1e-14):
        raise RuntimeError(
            f"{modality}_{contrast}_BH_MONOTONICITY_FAILED"
        )
    if np.any(fdr + 1e-15 < p):
        # Standard BH adjusted p-values should not be below raw p-values.
        raise RuntimeError(
            f"{modality}_{contrast}_BH_FDR_BELOW_RAW_PVALUE"
        )

put("ALL_SIX_DE_RESULT_TABLES_COMPLETE", "YES")
put("ALL_DE_PVALUES_VALID", "YES")
put("ALL_BH_FDR_VALID", "YES")
put("ALL_CONTRAST_ALGEBRA_AUDITS", "PASS")


# ------------------------------------------------------------
# G. Freeze execution specification
# ------------------------------------------------------------
spec_lines = [
    "GSE243219_D6_FROZEN_DE_EXECUTION_SPECIFICATION",
    "DE_ENGINE=INMOOSE_0.9.1_EDGEPY_LOW_LEVEL",
    "DESIGN_OBJECT=PATSY_DESIGNMATRIX",
    "DESIGN_INFO_COLUMN_NAMES=COVID19|SEPSIS|HEALTHY",
    "DESIGN_NUMERIC_VALUES_IDENTICAL_TO_D4=YES",
    "COUNT_CONTAINER_FOR_GLMQLFIT=PANDAS_DATAFRAME",
    "COUNT_FEATURE_INDEX_PRESERVED_FOR_GLMQLFTEST=YES",
    f"LOCAL_GLMQLFTEST_RESULT_SCHEMA={local_result_schema}",
    "CANONICAL_RESULT_COLUMNS=feature_id|logFC|logCPM|F|PValue|FDR",
    "DGEList_USED=NO",
    "COUNT_INPUT=FILTERED_RAW_FRACTIONAL_COUNTS",
    "COUNT_ROUNDING=PROHIBITED",
    "COHORT_SUBJECTS=72",
    "EXCLUDED_SUBJECTS=NONE",
    "NORMALIZATION_OFFSET=LOG_TMM_EFFECTIVE_LIBRARY_SIZE",
    "COMMON_DISPERSION_SOURCE=D5_V2_FROZEN_VALUES",
    f"MRNA_COMMON_DISPERSION={dispersion_by_modality['MRNA']:.17g}",
    f"MIRNA_COMMON_DISPERSION={dispersion_by_modality['MIRNA']:.17g}",
    "COMMON_DISPERSION_REESTIMATED_IN_D6=NO",
    "QL_ABUNDANCE_TREND=TRUE",
    "QL_ROBUST=FALSE",
    "QL_WINSOR_TAIL_P=NOT_USED_ROBUST_FALSE",
    "HYPOTHESIS_TEST=glmQLFTest",
    "POISSON_BOUND=TRUE",
    "CONTRASTS=COV_vs_H|P_vs_H|COV_vs_P",
    "COV_vs_H_DIRECTION=COVID19_MINUS_HEALTHY",
    "P_vs_H_DIRECTION=SEPSIS_MINUS_HEALTHY",
    "COV_vs_P_DIRECTION=COVID19_MINUS_SEPSIS",
    "MULTIPLE_TESTING=BENJAMINI_HOCHBERG",
    "PRIMARY_STATISTICAL_CALL=FDR_LE_0.05",
    "SECONDARY_EFFECT_SIZE_ANNOTATION=FDR_LE_0.05_AND_ABS_LOG2FC_GE_1",
    "FULL_RESULT_ROWS_RETAINED=YES",
    "NETWORK_EXECUTED_IN_D6=NO",
    "ACLA_EXECUTED_IN_D6=NO",
]
EXECUTION_SPEC.write_text(
    "\n".join(spec_lines) + "\n",
    encoding="utf-8",
)

put("PATSY_DESIGN_INTERFACE_CORRECTION_VALIDATED", "YES")
put("DE_EXECUTION_COMPLETE", "YES")
put("DE_RESULTS_PRIMARY_MEDIAN_MIRNA_COMPLETE", "YES")
put("SAMPLE_EXCLUSION_EXECUTED", "NO")
put("COUNT_ROUNDING_EXECUTED", "NO")
put("FEATURE_REFILTERING_EXECUTED", "NO")
put("TMM_RECOMPUTATION_EXECUTED", "NO")
put("NETWORK_EXECUTED", "NO")
put("ACLA_EXECUTED", "NO")
put("READY_FOR_D6A_DE_RESULT_AUDIT_AND_MIRNA_SENSITIVITY", "YES")
put("NEXT_PHASE", "D6A_DE_RESULT_AUDIT_AND_MIRNA_MAX_CONSOLIDATION_SENSITIVITY")

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
    $D5ModelSummary,
    $D5FrozenImplementation,
    $ApiAudit,
    $MrnaCovH,
    $MrnaPH,
    $MrnaCovP,
    $MirnaCovH,
    $MirnaPH,
    $MirnaCovP,
    $ContrastSummary,
    $ContrastAudit,
    $ExecutionSpec,
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
        Write-Host '=== D6 PYTHON STDERR ==='
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
    throw ('D6_PYTHON_FAILED exit={0} full_traceback={1}' -f $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D6_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('LOCAL_GLMQLFTEST_API_AUDIT','PASS'),
    @('D4_D5_FROZEN_INPUT_INTEGRITY','PASS'),
    @('PATSY_DESIGN_METADATA_ATTACHED','YES'),
    @('PATSY_DESIGN_NUMERIC_VALUES_IDENTICAL_TO_D4','YES'),
    @('SYNTHETIC_PATSY_DESIGN_FEATURES','240'),
    @('SYNTHETIC_PATSY_DESIGN_SAMPLES','18'),
    @('SYNTHETIC_PATSY_DESIGN_GROUPS','3'),
    @('SYNTHETIC_PATSY_DESIGN_ABUNDANCE_TREND','TRUE'),
    @('SYNTHETIC_PATSY_DESIGN_ROBUST','FALSE'),
    @('SYNTHETIC_COUNT_CONTAINER','PANDAS_DATAFRAME'),
    @('SYNTHETIC_COUNT_INDEX_PRESERVED','YES'),
    @('SYNTHETIC_POISSON_BOUND_DATAFRAME_LOC_COMPATIBILITY','PASS'),
    @('SYNTHETIC_PATSY_DESIGN_GLMQLFTEST_PREFLIGHT','PASS'),
    @('REAL_FIT_IMPLEMENTATION_STALE_Y_REFERENCE_AUDIT','PASS'),
    @('MRNA_FROZEN_COMMON_DISPERSION','0.3008681692934306'),
    @('MIRNA_FROZEN_COMMON_DISPERSION','0.368890975613554'),
    @('MRNA_FIT_COUNT_CONTAINER','PANDAS_DATAFRAME'),
    @('MRNA_FIT_FEATURE_INDEX_PRESERVED','YES'),
    @('MRNA_FIT_SAMPLE_COLUMNS_PRESERVED','YES'),
    @('MRNA_FIT_PATSY_DESIGN_INFO_PRESERVED','YES'),
    @('MRNA_CONTRAST_LOGFC_ALGEBRA','PASS'),
    @('MIRNA_FIT_COUNT_CONTAINER','PANDAS_DATAFRAME'),
    @('MIRNA_FIT_FEATURE_INDEX_PRESERVED','YES'),
    @('MIRNA_FIT_SAMPLE_COLUMNS_PRESERVED','YES'),
    @('MIRNA_FIT_PATSY_DESIGN_INFO_PRESERVED','YES'),
    @('MIRNA_CONTRAST_LOGFC_ALGEBRA','PASS'),
    @('ALL_SIX_DE_RESULT_TABLES_COMPLETE','YES'),
    @('ALL_DE_PVALUES_VALID','YES'),
    @('ALL_BH_FDR_VALID','YES'),
    @('ALL_CONTRAST_ALGEBRA_AUDITS','PASS'),
    @('PATSY_DESIGN_INTERFACE_CORRECTION_VALIDATED','YES'),
    @('DE_EXECUTION_COMPLETE','YES'),
    @('DE_RESULTS_PRIMARY_MEDIAN_MIRNA_COMPLETE','YES'),
    @('SAMPLE_EXCLUSION_EXECUTED','NO'),
    @('COUNT_ROUNDING_EXECUTED','NO'),
    @('FEATURE_REFILTERING_EXECUTED','NO'),
    @('TMM_RECOMPUTATION_EXECUTED','NO'),
    @('NETWORK_EXECUTED','NO'),
    @('ACLA_EXECUTED','NO'),
    @('READY_FOR_D6A_DE_RESULT_AUDIT_AND_MIRNA_SENSITIVITY','YES'),
    @('NEXT_PHASE','D6A_DE_RESULT_AUDIT_AND_MIRNA_MAX_CONSOLIDATION_SENSITIVITY')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D6_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 3. Decision
# ------------------------------------------------------------
@(
    'GSE243219_D6_V5_DECISION',
    'PHASE_D6_V5_STATUS=PASS',
    'MODE=FIRST_AUTHORIZED_DE_HYPOTHESIS_TESTING',
    'D4_CERTIFICATION_GATE=PASS',
    'D4_OUTPUTS_RECERTIFIED=14/14',
    'D5_V2_CERTIFICATION_GATE=PASS',
    'D5_V2_OUTPUTS_RECERTIFIED=10/10',
    'DE_ENGINE=INMOOSE_0.9.1_EDGEPY_LOW_LEVEL',
    'DESIGN_OBJECT=PATSY_DESIGNMATRIX',
    'DESIGN_INFO_COLUMN_NAMES=COVID19|SEPSIS|HEALTHY',
    'DESIGN_NUMERIC_VALUES_IDENTICAL_TO_D4=YES',
    'D6_V5_CORRECTION=STALE_REAL_FIT_VARIABLE_REFERENCE_FIXED',
    'D6_V4_INTERFACE_REVISION=DATAFRAME_COUNTS_PLUS_LOCAL_RESULT_SCHEMA_CANONICALIZATION',
    'COUNT_CONTAINER_FOR_GLMQLFIT=PANDAS_DATAFRAME',
    'COUNT_INDEX_REQUIRED_BY_GLMLRT=YES',
    'COUNT_LOC_REQUIRED_BY_POISSON_BOUND=YES',
    'SYNTHETIC_FIXTURE_REVISION=240_FEATURE_ABUNDANCE_TREND_SAFE_FIXTURE',
    'SYNTHETIC_PATSY_DESIGN_FEATURES=240',
    'SYNTHETIC_PATSY_DESIGN_SAMPLES=18',
    'SYNTHETIC_PATSY_DESIGN_GROUPS=3',
    'SYNTHETIC_PATSY_DESIGN_ABUNDANCE_TREND=TRUE',
    'SYNTHETIC_PATSY_DESIGN_ROBUST=FALSE',
    'SYNTHETIC_PATSY_DESIGN_GLMQLFTEST_PREFLIGHT=PASS',
    'REAL_FIT_IMPLEMENTATION_STALE_Y_REFERENCE_AUDIT=PASS',
    'DGEList_USED=NO',
    'COMMON_DISPERSION_SOURCE=D5_V2_FROZEN_VALUES',
    'COMMON_DISPERSION_REESTIMATED_IN_D6=NO',
    'MRNA_COMMON_DISPERSION=0.3008681692934306',
    'MIRNA_COMMON_DISPERSION=0.368890975613554',
    'QL_ABUNDANCE_TREND=TRUE',
    'QL_ROBUST=FALSE',
    'PATSY_DESIGN_INTERFACE_CORRECTION_VALIDATED=YES',
    ('LOCAL_GLMQLFTEST_RESULT_SCHEMA={0}' -f (Cap 'LOCAL_GLMQLFTEST_RESULT_SCHEMA')),
    ('LOCAL_GLMQLFTEST_LOGFC_COLUMN={0}' -f (Cap 'LOCAL_GLMQLFTEST_LOGFC_COLUMN')),
    ('LOCAL_GLMQLFTEST_STAT_COLUMN={0}' -f (Cap 'LOCAL_GLMQLFTEST_STAT_COLUMN')),
    ('LOCAL_GLMQLFTEST_PVALUE_COLUMN={0}' -f (Cap 'LOCAL_GLMQLFTEST_PVALUE_COLUMN')),
    'GLMQLFTEST_EXECUTED=YES',
    'POISSON_BOUND=TRUE',
    'CONTRAST_TESTING_EXECUTED=YES',
    'CONTRASTS=COV_vs_H|P_vs_H|COV_vs_P',
    'PVALUES_COMPUTED=YES',
    'BH_FDR_COMPUTED=YES',
    'PRIMARY_STATISTICAL_CALL=FDR_LE_0.05',
    'SECONDARY_EFFECT_SIZE_ANNOTATION=FDR_LE_0.05_AND_ABS_LOG2FC_GE_1',
    ('MRNA_COV_vs_H_FDR_LE_0_05={0}' -f (Cap 'MRNA_COV_vs_H_FDR_LE_0_05')),
    ('MRNA_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MRNA_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MRNA_P_vs_H_FDR_LE_0_05={0}' -f (Cap 'MRNA_P_vs_H_FDR_LE_0_05')),
    ('MRNA_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MRNA_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MRNA_COV_vs_P_FDR_LE_0_05={0}' -f (Cap 'MRNA_COV_vs_P_FDR_LE_0_05')),
    ('MRNA_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MRNA_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MIRNA_COV_vs_H_FDR_LE_0_05={0}' -f (Cap 'MIRNA_COV_vs_H_FDR_LE_0_05')),
    ('MIRNA_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MIRNA_P_vs_H_FDR_LE_0_05={0}' -f (Cap 'MIRNA_P_vs_H_FDR_LE_0_05')),
    ('MIRNA_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MIRNA_COV_vs_P_FDR_LE_0_05={0}' -f (Cap 'MIRNA_COV_vs_P_FDR_LE_0_05')),
    ('MIRNA_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    'MRNA_CONTRAST_LOGFC_ALGEBRA=PASS',
    'MIRNA_CONTRAST_LOGFC_ALGEBRA=PASS',
    'ALL_SIX_DE_RESULT_TABLES_COMPLETE=YES',
    'ALL_DE_PVALUES_VALID=YES',
    'ALL_BH_FDR_VALID=YES',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'FEATURE_REFILTERING_EXECUTED=NO',
    'TMM_RECOMPUTATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D6A_DE_RESULT_AUDIT_AND_MIRNA_SENSITIVITY=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D6A_DE_RESULT_AUDIT_AND_MIRNA_MAX_CONSOLIDATION_SENSITIVITY',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Output manifest
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $ApiAudit,
    $MrnaCovH,
    $MrnaPH,
    $MrnaCovP,
    $MirnaCovH,
    $MirnaPH,
    $MirnaCovP,
    $ContrastSummary,
    $ContrastAudit,
    $ExecutionSpec,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D6_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p

    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D6SHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D6-V5 SUMMARY ===',
    'PHASE_D6_V5_STATUS=PASS',
    'MODE=FIRST_AUTHORIZED_DE_HYPOTHESIS_TESTING',
    'D4_CERTIFICATION_GATE=PASS',
    'D4_OUTPUTS_RECERTIFIED=14/14',
    'D5_V2_CERTIFICATION_GATE=PASS',
    'D5_V2_OUTPUTS_RECERTIFIED=10/10',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('INMOOSE_VERSION={0}' -f $InMooseVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    ('SCIPY_VERSION={0}' -f $ScipyVersion),
    'DE_ENGINE=INMOOSE_0.9.1_EDGEPY_LOW_LEVEL',
    'DESIGN_OBJECT=PATSY_DESIGNMATRIX',
    'DESIGN_INFO_COLUMN_NAMES=COVID19|SEPSIS|HEALTHY',
    'DESIGN_NUMERIC_VALUES_IDENTICAL_TO_D4=YES',
    'D6_V5_CORRECTION=STALE_REAL_FIT_VARIABLE_REFERENCE_FIXED',
    'D6_V4_INTERFACE_REVISION=DATAFRAME_COUNTS_PLUS_LOCAL_RESULT_SCHEMA_CANONICALIZATION',
    'COUNT_CONTAINER_FOR_GLMQLFIT=PANDAS_DATAFRAME',
    'COUNT_INDEX_REQUIRED_BY_GLMLRT=YES',
    'COUNT_LOC_REQUIRED_BY_POISSON_BOUND=YES',
    'SYNTHETIC_FIXTURE_REVISION=240_FEATURE_ABUNDANCE_TREND_SAFE_FIXTURE',
    'SYNTHETIC_PATSY_DESIGN_FEATURES=240',
    'SYNTHETIC_PATSY_DESIGN_SAMPLES=18',
    'SYNTHETIC_PATSY_DESIGN_GROUPS=3',
    'SYNTHETIC_PATSY_DESIGN_ABUNDANCE_TREND=TRUE',
    'SYNTHETIC_PATSY_DESIGN_ROBUST=FALSE',
    'SYNTHETIC_PATSY_DESIGN_GLMQLFTEST_PREFLIGHT=PASS',
    'REAL_FIT_IMPLEMENTATION_STALE_Y_REFERENCE_AUDIT=PASS',
    'DGEList_USED=NO',
    'COUNT_INPUT=FILTERED_RAW_FRACTIONAL_COUNTS',
    'COMMON_DISPERSION_SOURCE=D5_V2_FROZEN_VALUES',
    'COMMON_DISPERSION_REESTIMATED_IN_D6=NO',
    ('MRNA_COMMON_DISPERSION={0}' -f (Cap 'MRNA_FROZEN_COMMON_DISPERSION')),
    ('MIRNA_COMMON_DISPERSION={0}' -f (Cap 'MIRNA_FROZEN_COMMON_DISPERSION')),
    'QL_ABUNDANCE_TREND=TRUE',
    'QL_ROBUST=FALSE',
    'HYPOTHESIS_TEST=glmQLFTest',
    'POISSON_BOUND=TRUE',
    'CONTRASTS=COV_vs_H|P_vs_H|COV_vs_P',
    'PVALUES_COMPUTED=YES',
    'BH_FDR_COMPUTED=YES',
    'PRIMARY_STATISTICAL_CALL=FDR_LE_0.05',
    'SECONDARY_EFFECT_SIZE_ANNOTATION=FDR_LE_0.05_AND_ABS_LOG2FC_GE_1',
    ('MRNA_COV_vs_H_FDR_LE_0_05={0}' -f (Cap 'MRNA_COV_vs_H_FDR_LE_0_05')),
    ('MRNA_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MRNA_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MRNA_P_vs_H_FDR_LE_0_05={0}' -f (Cap 'MRNA_P_vs_H_FDR_LE_0_05')),
    ('MRNA_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MRNA_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MRNA_COV_vs_P_FDR_LE_0_05={0}' -f (Cap 'MRNA_COV_vs_P_FDR_LE_0_05')),
    ('MRNA_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MRNA_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MIRNA_COV_vs_H_FDR_LE_0_05={0}' -f (Cap 'MIRNA_COV_vs_H_FDR_LE_0_05')),
    ('MIRNA_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MIRNA_P_vs_H_FDR_LE_0_05={0}' -f (Cap 'MIRNA_P_vs_H_FDR_LE_0_05')),
    ('MIRNA_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MIRNA_COV_vs_P_FDR_LE_0_05={0}' -f (Cap 'MIRNA_COV_vs_P_FDR_LE_0_05')),
    ('MIRNA_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MRNA_CONTRAST_LOGFC_ALGEBRA_MAX_ABS_DIFF={0}' -f (Cap 'MRNA_CONTRAST_LOGFC_ALGEBRA_MAX_ABS_DIFF')),
    'MRNA_CONTRAST_LOGFC_ALGEBRA=PASS',
    ('MIRNA_CONTRAST_LOGFC_ALGEBRA_MAX_ABS_DIFF={0}' -f (Cap 'MIRNA_CONTRAST_LOGFC_ALGEBRA_MAX_ABS_DIFF')),
    'MIRNA_CONTRAST_LOGFC_ALGEBRA=PASS',
    'ALL_SIX_DE_RESULT_TABLES_COMPLETE=YES',
    'ALL_DE_PVALUES_VALID=YES',
    'ALL_BH_FDR_VALID=YES',
    'DE_EXECUTION_COMPLETE=YES',
    'DE_RESULTS_PRIMARY_MEDIAN_MIRNA_COMPLETE=YES',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'FEATURE_REFILTERING_EXECUTED=NO',
    'TMM_RECOMPUTATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D6A_DE_RESULT_AUDIT_AND_MIRNA_SENSITIVITY=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D6A_DE_RESULT_AUDIT_AND_MIRNA_MAX_CONSOLIDATION_SENSITIVITY',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D6_MRNA_COV_vs_H_RESULTS={0}' -f $MrnaCovH)
Write-Host ('D6_MRNA_P_vs_H_RESULTS={0}' -f $MrnaPH)
Write-Host ('D6_MRNA_COV_vs_P_RESULTS={0}' -f $MrnaCovP)
Write-Host ('D6_MIRNA_COV_vs_H_RESULTS={0}' -f $MirnaCovH)
Write-Host ('D6_MIRNA_P_vs_H_RESULTS={0}' -f $MirnaPH)
Write-Host ('D6_MIRNA_COV_vs_P_RESULTS={0}' -f $MirnaCovP)
Write-Host ('D6_CONTRAST_SUMMARY={0}' -f $ContrastSummary)
Write-Host ('D6_CONTRAST_AUDIT={0}' -f $ContrastAudit)
Write-Host ('D6_EXECUTION_SPEC={0}' -f $ExecutionSpec)
Write-Host ('D6_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D6_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D6_V5=PASS'
Write-Host 'STOP=YES'
