$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D6A — PRIMARY DE RESULT AUDIT
#              + miRNA MAX-CONSOLIDATION SENSITIVITY
#
# Purpose:
#   1) Independently audit the certified D6-V5 primary DE results.
#   2) Execute the prospectively frozen miRNA sensitivity analysis
#      using MAX across precursor rows per mature miRNA identity.
#
# Critical sensitivity principle:
#   The SAME 428 mature-miRNA feature identities selected by the
#   frozen D3A primary filter are retained for MAX sensitivity.
#   We do NOT re-filter using MAX counts because that would confound
#   the consolidation-method sensitivity with feature-selection changes.
#
# Sensitivity normalization/model:
#   - recompute library sizes on the MAX 428x72 matrix
#   - recompute TMM factors specifically for MAX sensitivity
#   - use the exact D2E-V4-validated TMM implementation
#   - estimate a NEW common Cox-Reid NB dispersion for the MAX matrix
#   - same frozen 72-subject cohort
#   - same frozen 72x3 numerical design + Patsy metadata
#   - same three frozen contrasts
#   - abundance_trend=True
#   - robust=False
#   - glmQLFTest(..., poisson_bound=True)
#   - BH FDR
#
# Primary median-based DE remains authoritative and immutable.
#
# Prohibited:
#   - modifying D6-V5 result files
#   - changing the primary 428-feature filter
#   - sample exclusion
#   - count rounding
#   - mRNA re-analysis
#   - network construction
#   - A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'

$D2Root = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING'
$D3Root = Join-Path $Project '03_QC_AND_FILTERING'
$D4Root = Join-Path $Project '04_NORMALIZATION'
$D5Root = Join-Path $Project '05_DIFFERENTIAL_EXPRESSION'

$D2DRun = Join-Path $D2Root 'D2D_PREFLIGHT_20260904_195001'
$VenvPython = Join-Path $D2DRun 'venv\Scripts\python.exe'

$D2E4Run = Join-Path $D2Root 'D2E_V4_TMM_OFFLINE_VALIDATION_20260904_225425'
$D2E4Manifest = Join-Path $D2E4Run 'D2E_V4_OUTPUT_SHA256_MANIFEST.csv'
$D2E4Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D2E_V4_20260904_225425\PHASE_D2E_V4_SUMMARY.txt'
$D2E4ValidationPy = Join-Path $D2E4Run 'D2E_V4_OFFLINE_TMM_VALIDATION.py'

$D3Run = Join-Path $D3Root 'D3_V2_MATRIX_QC_20260904_231245'
$D3Manifest = Join-Path $D3Run 'D3_OUTPUT_SHA256_MANIFEST.csv'
$MirnaMaxSource = Join-Path $D3Run 'D3_MIRNA_MATURE_MAX_SENSITIVITY_COUNTS_2656x72.csv.gz'

$D3ARun = Join-Path $D3Root 'D3A_QC_FILTER_DESIGN_20260905_092247'
$D3AManifest = Join-Path $D3ARun 'D3A_OUTPUT_SHA256_MANIFEST.csv'
$MirnaPrimaryMask = Join-Path $D3ARun 'D3A_MIRNA_FILTERBYEXPR_CANDIDATE.csv.gz'

$D4Run = Join-Path $D4Root 'D4_DE_INPUT_BUNDLE_FREEZE_20260905_094110'
$D4Manifest = Join-Path $D4Run 'D4_OUTPUT_SHA256_MANIFEST.csv'
$Cohort = Join-Path $D4Run 'D4_FROZEN_ANALYSIS_COHORT_72.csv'
$DesignMatrix = Join-Path $D4Run 'D4_DE_DESIGN_MATRIX_GROUP_MEANS_72x3.csv'
$ContrastMatrix = Join-Path $D4Run 'D4_DE_CONTRAST_MATRIX.csv'

$D5Run = Join-Path $D5Root 'D5_V2_MODEL_DISPERSION_PREFLIGHT_20260905_094850'
$D5Manifest = Join-Path $D5Run 'D5_OUTPUT_SHA256_MANIFEST.csv'
$D5Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D5_V2_20260905_094850\PHASE_D5_SUMMARY.txt'

$D6Run = Join-Path $D5Root 'D6_V5_PRIMARY_DE_EXECUTION_20260905_102127'
$D6Manifest = Join-Path $D6Run 'D6_OUTPUT_SHA256_MANIFEST.csv'
$D6Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D6_V5_20260905_102127\PHASE_D6_SUMMARY.txt'

$PrimaryMrnaCovH = Join-Path $D6Run 'D6_MRNA_COV_vs_H_FULL_RESULTS.csv.gz'
$PrimaryMrnaPH = Join-Path $D6Run 'D6_MRNA_P_vs_H_FULL_RESULTS.csv.gz'
$PrimaryMrnaCovP = Join-Path $D6Run 'D6_MRNA_COV_vs_P_FULL_RESULTS.csv.gz'
$PrimaryMirnaCovH = Join-Path $D6Run 'D6_MIRNA_COV_vs_H_FULL_RESULTS.csv.gz'
$PrimaryMirnaPH = Join-Path $D6Run 'D6_MIRNA_P_vs_H_FULL_RESULTS.csv.gz'
$PrimaryMirnaCovP = Join-Path $D6Run 'D6_MIRNA_COV_vs_P_FULL_RESULTS.csv.gz'
$PrimarySummary = Join-Path $D6Run 'D6_DE_CONTRAST_SUMMARY.csv'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D5Root ('D6A_DE_AUDIT_MIRNA_MAX_SENSITIVITY_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D6A_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D6A_PRIMARY_DE_AUDIT_AND_MIRNA_MAX_SENSITIVITY.py'

$PrimaryAudit = Join-Path $RunDir 'D6A_PRIMARY_DE_RESULT_AUDIT.csv'
$MirnaMaxFiltered = Join-Path $RunDir 'D6A_MIRNA_MAX_FILTERED_COUNTS_428x72.csv.gz'
$MirnaMaxNorm = Join-Path $RunDir 'D6A_MIRNA_MAX_TMM_NORMALIZATION.csv'
$MirnaMaxModel = Join-Path $RunDir 'D6A_MIRNA_MAX_MODEL_SUMMARY.csv'

$MaxCovH = Join-Path $RunDir 'D6A_MIRNA_MAX_COV_vs_H_FULL_RESULTS.csv.gz'
$MaxPH = Join-Path $RunDir 'D6A_MIRNA_MAX_P_vs_H_FULL_RESULTS.csv.gz'
$MaxCovP = Join-Path $RunDir 'D6A_MIRNA_MAX_COV_vs_P_FULL_RESULTS.csv.gz'

$MaxSummary = Join-Path $RunDir 'D6A_MIRNA_MAX_DE_SUMMARY.csv'
$Concordance = Join-Path $RunDir 'D6A_MIRNA_MEDIAN_VS_MAX_SENSITIVITY_CONCORDANCE.csv'
$SensitivitySpec = Join-Path $RunDir 'D6A_MIRNA_SENSITIVITY_SPECIFICATION.txt'

$ResultJson = Join-Path $RunDir 'D6A_RESULT.json'
$PythonStdout = Join-Path $RunDir 'D6A_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D6A_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D6A_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D6A_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D6A_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D6A_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D6A — PRIMARY DE AUDIT + miRNA MAX SENSITIVITY ==='
Write-Host 'MODE=RESULT_AUDIT_AND_PROSPECTIVE_SENSITIVITY'
Write-Host 'PRIMARY_D6_RESULTS_MODIFIED=NO'
Write-Host 'PRIMARY_MIRNA_CONSOLIDATION=MEDIAN'
Write-Host 'SENSITIVITY_MIRNA_CONSOLIDATION=MAX'
Write-Host 'SENSITIVITY_USES_SAME_428_FEATURE_IDENTITIES=YES'
Write-Host 'SENSITIVITY_REFILTERING_EXECUTED=NO'
Write-Host 'SENSITIVITY_TMM_RECOMPUTED=YES'
Write-Host 'SENSITIVITY_COMMON_DISPERSION_REESTIMATED=YES'
Write-Host 'SENSITIVITY_GLMQLFTEST_EXECUTED=YES'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'MRNA_REANALYSIS_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $VenvPython,
    $D2E4Manifest,$D2E4Report,$D2E4ValidationPy,
    $D3Manifest,$MirnaMaxSource,
    $D3AManifest,$MirnaPrimaryMask,
    $D4Manifest,$Cohort,$DesignMatrix,$ContrastMatrix,
    $D5Manifest,$D5Report,
    $D6Manifest,$D6Report,
    $PrimaryMrnaCovH,$PrimaryMrnaPH,$PrimaryMrnaCovP,
    $PrimaryMirnaCovH,$PrimaryMirnaPH,$PrimaryMirnaCovP,$PrimarySummary
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D6A_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D6ASHA256 {
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
        $hash = Get-D6ASHA256 $r.full_path

        if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
            $hash -ne $r.SHA256.ToLowerInvariant()) {
            throw ('{0}_OUTPUT_CHANGED={1}' -f $Label,$r.full_path)
        }
    }

    Write-Host ('{0}_OUTPUTS_RECERTIFIED={1}/{1}' -f $Label,$ExpectedRows)
}

# ------------------------------------------------------------
# 1. Re-certification gates
# ------------------------------------------------------------
Recertify-Manifest -ManifestPath $D2E4Manifest -ExpectedRows 6 -Label 'D2E_V4'
Write-Host 'D2E_V4_TMM_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D3Manifest -ExpectedRows 15 -Label 'D3_V2'
Write-Host 'D3_V2_MATRIX_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D3AManifest -ExpectedRows 12 -Label 'D3A'
Write-Host 'D3A_FILTER_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D4Manifest -ExpectedRows 14 -Label 'D4'
Write-Host 'D4_DESIGN_COHORT_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D5Manifest -ExpectedRows 10 -Label 'D5_V2'
Write-Host 'D5_V2_MODEL_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D6Manifest -ExpectedRows 16 -Label 'D6_V5'
Write-Host 'D6_V5_PRIMARY_DE_CERTIFICATION_GATE=PASS'

$d6 = Get-Content -LiteralPath $D6Report -Raw
foreach ($tok in @(
    'PHASE_D6_V5_STATUS=PASS',
    'PVALUES_COMPUTED=YES',
    'BH_FDR_COMPUTED=YES',
    'MRNA_COV_vs_H_FDR_LE_0_05=8505',
    'MRNA_P_vs_H_FDR_LE_0_05=8517',
    'MRNA_COV_vs_P_FDR_LE_0_05=4118',
    'MIRNA_COV_vs_H_FDR_LE_0_05=41',
    'MIRNA_P_vs_H_FDR_LE_0_05=191',
    'MIRNA_COV_vs_P_FDR_LE_0_05=203',
    'MRNA_CONTRAST_LOGFC_ALGEBRA=PASS',
    'MIRNA_CONTRAST_LOGFC_ALGEBRA=PASS',
    'ALL_SIX_DE_RESULT_TABLES_COMPLETE=YES',
    'ALL_DE_PVALUES_VALID=YES',
    'ALL_BH_FDR_VALID=YES',
    'DE_EXECUTION_COMPLETE=YES',
    'DE_RESULTS_PRIMARY_MEDIAN_MIRNA_COMPLETE=YES',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'FEATURE_REFILTERING_EXECUTED=NO',
    'TMM_RECOMPUTATION_EXECUTED=NO'
)) {
    if ($d6 -notmatch [regex]::Escape($tok)) {
        throw ('D6_V5_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$d5 = Get-Content -LiteralPath $D5Report -Raw
foreach ($tok in @(
    'PHASE_D5_V2_STATUS=PASS',
    'NB_DISPERSION_METHOD=COX_REID_COMMON',
    'NB_DISPERSION_IS_GLOBAL=YES',
    'TAGWISE_NB_DISPERSION_FOR_QL=PROHIBITED',
    'QL_ABUNDANCE_TREND=TRUE',
    'QL_ROBUST=FALSE',
    'REAL_DE_MODEL_DISPERSION_PREFLIGHT=PASS'
)) {
    if ($d5 -notmatch [regex]::Escape($tok)) {
        throw ('D5_V2_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

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
# 2. Python D6A
# ------------------------------------------------------------
$PythonCode = @'
import ast
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from patsy import DesignInfo, DesignMatrix
from scipy.stats import pearsonr, spearmanr

from inmoose.edgepy.aveLogCPM import aveLogCPM
from inmoose.edgepy.estimateGLMCommonDisp import estimateGLMCommonDisp
from inmoose.edgepy.glmQLFit import glmQLFit, glmQLFTest


D2E_VALIDATION_PY = Path(sys.argv[1])
MIRNA_MAX_SOURCE = Path(sys.argv[2])
MIRNA_MASK = Path(sys.argv[3])
COHORT = Path(sys.argv[4])
DESIGN = Path(sys.argv[5])
CONTRASTS = Path(sys.argv[6])

PRIMARY_MRNA_COV_H = Path(sys.argv[7])
PRIMARY_MRNA_P_H = Path(sys.argv[8])
PRIMARY_MRNA_COV_P = Path(sys.argv[9])
PRIMARY_MIRNA_COV_H = Path(sys.argv[10])
PRIMARY_MIRNA_P_H = Path(sys.argv[11])
PRIMARY_MIRNA_COV_P = Path(sys.argv[12])
PRIMARY_SUMMARY = Path(sys.argv[13])

PRIMARY_AUDIT = Path(sys.argv[14])
MIRNA_MAX_FILTERED = Path(sys.argv[15])
MIRNA_MAX_NORM = Path(sys.argv[16])
MIRNA_MAX_MODEL = Path(sys.argv[17])
MAX_COV_H = Path(sys.argv[18])
MAX_P_H = Path(sys.argv[19])
MAX_COV_P = Path(sys.argv[20])
MAX_SUMMARY = Path(sys.argv[21])
CONCORDANCE = Path(sys.argv[22])
SENSITIVITY_SPEC = Path(sys.argv[23])
RESULT_JSON = Path(sys.argv[24])


FDR_THRESHOLD = 0.05
ABS_LOGFC_THRESHOLD = 1.0

results = {}


def put(k, v):
    results[k] = v
    print(f"{k}={v}")


def bh_adjust(pvalues):
    p = np.asarray(pvalues, dtype=np.float64)
    if p.ndim != 1:
        raise RuntimeError("BH_INPUT_NOT_1D")
    if np.any(~np.isfinite(p)) or np.any((p < 0) | (p > 1)):
        raise RuntimeError("BH_INPUT_INVALID")
    n = p.size
    order = np.argsort(p, kind="mergesort")
    ps = p[order]
    adj = ps * n / np.arange(1, n + 1, dtype=np.float64)
    adj = np.minimum.accumulate(adj[::-1])[::-1]
    adj = np.clip(adj, 0.0, 1.0)
    out = np.empty(n, dtype=np.float64)
    out[order] = adj
    return out


# ------------------------------------------------------------
# A. Load exact D2E-V4 validated TMM implementation
# ------------------------------------------------------------
source = D2E_VALIDATION_PY.read_text(encoding="utf-8-sig")
tree = ast.parse(source)

required_names = {
    "average_rank",
    "factor_tmm_edge_style",
    "edge_style_tmm",
}

selected_nodes = [
    node for node in tree.body
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    and node.name in required_names
]

found = {node.name for node in selected_nodes}
if found != required_names:
    raise RuntimeError(
        f"VALIDATED_TMM_FUNCTION_EXTRACTION_FAILED "
        f"expected={sorted(required_names)} observed={sorted(found)}"
    )

module = ast.Module(body=selected_nodes, type_ignores=[])
ast.fix_missing_locations(module)
ns = {"np": np}
exec(compile(module, str(D2E_VALIDATION_PY), "exec"), ns)
edge_style_tmm = ns["edge_style_tmm"]

toy = np.array(
    [
        [200, 300, 500, 2000, 7000],
        [400, 600, 1000, 4000, 14000],
        [200, 300, 500, 2000, 17000],
        [200, 300, 500, 2000, 2000],
    ],
    dtype=np.float64,
)
toy_expected = np.array([1.0, 1.0, 0.5, 2.0], dtype=np.float64)
toy_observed = edge_style_tmm(toy.T)
toy_diff = float(np.max(np.abs(toy_observed - toy_expected)))
if toy_diff > 1e-12:
    raise RuntimeError(f"TMM_PRODUCTION_SELF_TEST_FAILED maxdiff={toy_diff}")

put("D2E_V4_TMM_FUNCTION_EXTRACTION", "PASS")
put("TMM_PRODUCTION_SELF_TEST", "PASS")
put("TMM_PRODUCTION_SELF_TEST_MAX_ABS_DIFF", toy_diff)


# ------------------------------------------------------------
# B. Primary D6-V5 result audit
# ------------------------------------------------------------
primary_files = {
    ("MRNA", "COV_vs_H"): PRIMARY_MRNA_COV_H,
    ("MRNA", "P_vs_H"): PRIMARY_MRNA_P_H,
    ("MRNA", "COV_vs_P"): PRIMARY_MRNA_COV_P,
    ("MIRNA", "COV_vs_H"): PRIMARY_MIRNA_COV_H,
    ("MIRNA", "P_vs_H"): PRIMARY_MIRNA_P_H,
    ("MIRNA", "COV_vs_P"): PRIMARY_MIRNA_COV_P,
}

expected_rows = {"MRNA": 15083, "MIRNA": 428}
expected_sig = {
    ("MRNA", "COV_vs_H"): 8505,
    ("MRNA", "P_vs_H"): 8517,
    ("MRNA", "COV_vs_P"): 4118,
    ("MIRNA", "COV_vs_H"): 41,
    ("MIRNA", "P_vs_H"): 191,
    ("MIRNA", "COV_vs_P"): 203,
}
expected_strict = {
    ("MRNA", "COV_vs_H"): 3618,
    ("MRNA", "P_vs_H"): 3944,
    ("MRNA", "COV_vs_P"): 945,
    ("MIRNA", "COV_vs_H"): 22,
    ("MIRNA", "P_vs_H"): 92,
    ("MIRNA", "COV_vs_P"): 83,
}

primary_tables = {}
audit_rows = []

for key, path in primary_files.items():
    modality, contrast = key
    df = pd.read_csv(
        path,
        compression="gzip",
        engine="c",
        float_precision="round_trip",
    )

    if df.shape[0] != expected_rows[modality]:
        raise RuntimeError(
            f"{modality}_{contrast}_ROW_COUNT_CHANGED observed={df.shape[0]}"
        )

    required = {
        "feature_id","contrast","logFC","logCPM","F","PValue","FDR",
        "statistically_significant_FDR_le_0_05",
        "significant_FDR_le_0_05_and_abs_log2FC_ge_1",
    }
    missing = sorted(required - set(df.columns))
    if missing:
        raise RuntimeError(
            f"{modality}_{contrast}_PRIMARY_RESULT_COLUMNS_MISSING={missing}"
        )

    if not df["contrast"].astype(str).eq(contrast).all():
        raise RuntimeError(f"{modality}_{contrast}_CONTRAST_LABEL_CHANGED")

    p = pd.to_numeric(df["PValue"], errors="raise").to_numpy(dtype=np.float64)
    fdr = pd.to_numeric(df["FDR"], errors="raise").to_numpy(dtype=np.float64)
    logfc = pd.to_numeric(df["logFC"], errors="raise").to_numpy(dtype=np.float64)

    bh = bh_adjust(p)
    bh_diff = float(np.max(np.abs(bh - fdr)))

    if bh_diff > 1e-12:
        raise RuntimeError(
            f"{modality}_{contrast}_BH_RECOMPUTATION_MISMATCH maxdiff={bh_diff}"
        )

    sig = fdr <= FDR_THRESHOLD
    strict = sig & (np.abs(logfc) >= ABS_LOGFC_THRESHOLD)

    if int(np.sum(sig)) != expected_sig[key]:
        raise RuntimeError(
            f"{modality}_{contrast}_SIG_COUNT_CHANGED "
            f"expected={expected_sig[key]} observed={int(np.sum(sig))}"
        )
    if int(np.sum(strict)) != expected_strict[key]:
        raise RuntimeError(
            f"{modality}_{contrast}_STRICT_COUNT_CHANGED "
            f"expected={expected_strict[key]} observed={int(np.sum(strict))}"
        )

    audit_rows.append({
        "modality": modality,
        "contrast": contrast,
        "rows": int(df.shape[0]),
        "bh_recompute_max_abs_diff": bh_diff,
        "FDR_le_0_05": int(np.sum(sig)),
        "FDR_le_0_05_abs_log2FC_ge_1": int(np.sum(strict)),
        "min_PValue": float(np.min(p)),
        "min_FDR": float(np.min(fdr)),
        "status": "PASS",
    })

    primary_tables[key] = df

# Primary contrast algebra.
for modality in ["MRNA", "MIRNA"]:
    a = primary_tables[(modality, "COV_vs_H")]["logFC"].to_numpy(dtype=np.float64)
    b = primary_tables[(modality, "P_vs_H")]["logFC"].to_numpy(dtype=np.float64)
    c = primary_tables[(modality, "COV_vs_P")]["logFC"].to_numpy(dtype=np.float64)

    diff = float(np.max(np.abs((a - b) - c)))
    if diff > 1e-10:
        raise RuntimeError(
            f"{modality}_PRIMARY_CONTRAST_ALGEBRA_FAILED maxdiff={diff}"
        )

pd.DataFrame(audit_rows).to_csv(PRIMARY_AUDIT, index=False)

put("PRIMARY_D6_RESULT_TABLES_AUDITED", "6/6")
put("PRIMARY_D6_BH_RECOMPUTATION", "PASS")
put("PRIMARY_D6_CONTRAST_ALGEBRA_REAUDIT", "PASS")
put("PRIMARY_D6_RESULTS_MODIFIED", "NO")


# ------------------------------------------------------------
# C. Load cohort/design/contrast and MAX-consolidation matrix
# ------------------------------------------------------------
cohort = pd.read_csv(COHORT)
design_df = pd.read_csv(DESIGN)
contrast_df = pd.read_csv(CONTRASTS)

if cohort.shape[0] != 72:
    raise RuntimeError(f"COHORT_ROWS_CHANGED observed={cohort.shape[0]}")

subjects = cohort["subject_id"].astype(str).tolist()
groups = cohort["disease_state"].astype(str).tolist()

expected_group_counts = {"COVID19": 35, "SEPSIS": 22, "HEALTHY": 15}
if pd.Series(groups).value_counts().to_dict() != expected_group_counts:
    raise RuntimeError("COHORT_GROUP_COUNTS_CHANGED")

X_numeric = design_df[
    ["COVID19","SEPSIS","HEALTHY"]
].to_numpy(dtype=np.float64)

if X_numeric.shape != (72, 3):
    raise RuntimeError(f"DESIGN_SHAPE_CHANGED observed={X_numeric.shape}")
if np.linalg.matrix_rank(X_numeric) != 3:
    raise RuntimeError("DESIGN_NOT_FULL_RANK")

X = DesignMatrix(
    X_numeric,
    design_info=DesignInfo(["COVID19","SEPSIS","HEALTHY"]),
)

contrast_vectors = {}
for _, row in contrast_df.iterrows():
    contrast_vectors[str(row["contrast_name"])] = row[
        ["COVID19","SEPSIS","HEALTHY"]
    ].to_numpy(dtype=np.float64)

expected_vectors = {
    "COV_vs_H": np.array([1.0, 0.0, -1.0]),
    "P_vs_H": np.array([0.0, 1.0, -1.0]),
    "COV_vs_P": np.array([1.0, -1.0, 0.0]),
}
for name, expected in expected_vectors.items():
    if name not in contrast_vectors:
        raise RuntimeError(f"CONTRAST_MISSING={name}")
    if not np.array_equal(contrast_vectors[name], expected):
        raise RuntimeError(f"CONTRAST_CHANGED={name}")

max_all = pd.read_csv(
    MIRNA_MAX_SOURCE,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
mask = pd.read_csv(MIRNA_MASK, compression="gzip")

if max_all.shape != (2656, 72):
    raise RuntimeError(f"MIRNA_MAX_SOURCE_SHAPE_CHANGED observed={max_all.shape}")
if list(max_all.columns) != subjects:
    raise RuntimeError("MIRNA_MAX_SAMPLE_ORDER_CHANGED")

if mask.shape[0] != 2656:
    raise RuntimeError(f"MIRNA_MASK_ROWS_CHANGED observed={mask.shape[0]}")
if mask["feature_id"].astype(str).tolist() != max_all.index.astype(str).tolist():
    raise RuntimeError("MIRNA_MAX_MASK_FEATURE_ORDER_MISMATCH")

keep = mask["candidate_keep"].astype(str).eq("YES").to_numpy()
if int(np.sum(keep)) != 428:
    raise RuntimeError(
        f"MIRNA_FROZEN_KEEP_COUNT_CHANGED observed={int(np.sum(keep))}"
    )

max_f = max_all.iloc[keep, :].copy()

if max_f.shape != (428, 72):
    raise RuntimeError(f"MIRNA_MAX_FILTERED_SHAPE_WRONG observed={max_f.shape}")

# Critical sensitivity isolation: same feature identities and order as primary.
primary_feature_order = primary_tables[
    ("MIRNA","COV_vs_H")
]["feature_id"].astype(str).tolist()

if max_f.index.astype(str).tolist() != primary_feature_order:
    raise RuntimeError(
        "MIRNA_MAX_FEATURE_IDENTITIES_NOT_IDENTICAL_TO_PRIMARY_428"
    )

max_numeric = max_f.to_numpy(dtype=np.float64)
if np.any(~np.isfinite(max_numeric)) or np.any(max_numeric < 0):
    raise RuntimeError("MIRNA_MAX_FILTERED_COUNTS_INVALID")

max_fractional = int(
    np.sum(np.abs(max_numeric - np.round(max_numeric)) > 1e-12)
)

max_f.to_csv(
    MIRNA_MAX_FILTERED,
    compression="gzip",
    float_format="%.17g",
)

rt = pd.read_csv(
    MIRNA_MAX_FILTERED,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
if not np.array_equal(
    rt.to_numpy(dtype=np.float64),
    max_numeric,
):
    raise RuntimeError("MIRNA_MAX_FILTERED_ROUNDTRIP_VALUE_MISMATCH")

put("MIRNA_MAX_SOURCE_FEATURES", 2656)
put("MIRNA_MAX_SENSITIVITY_FEATURES", 428)
put("MIRNA_MAX_SAME_PRIMARY_FEATURE_IDENTITIES", "YES")
put("MIRNA_MAX_SENSITIVITY_REFILTERING_EXECUTED", "NO")
put("MIRNA_MAX_FILTERED_FRACTIONAL_VALUES", max_fractional)
put("MIRNA_MAX_FILTERED_ROUNDTRIP_INTEGRITY", "PASS")


# ------------------------------------------------------------
# D. MAX sensitivity TMM normalization
# ------------------------------------------------------------
lib = np.sum(max_numeric, axis=0, dtype=np.float64)
if np.any(lib <= 0):
    raise RuntimeError("MIRNA_MAX_NONPOSITIVE_LIBRARY_SIZE")

tmm = edge_style_tmm(max_numeric, lib_size=lib)

if np.any(~np.isfinite(tmm)) or np.any(tmm <= 0):
    raise RuntimeError("MIRNA_MAX_INVALID_TMM_FACTORS")

gm = float(np.exp(np.mean(np.log(tmm))))
if abs(gm - 1.0) > 1e-12:
    raise RuntimeError(f"MIRNA_MAX_TMM_GEOMEAN_NOT_ONE observed={gm}")

effective = lib * tmm
offset = np.log(effective)

norm_df = pd.DataFrame({
    "subject_id": subjects,
    "disease_state": groups,
    "post_filter_raw_library_size": lib,
    "tmm_norm_factor": tmm,
    "effective_library_size": effective,
    "log_effective_library_offset": offset,
})
norm_df.to_csv(MIRNA_MAX_NORM, index=False)

put("MIRNA_MAX_TMM_FACTOR_GEOMEAN", gm)
put("MIRNA_MAX_TMM_FACTOR_MIN", float(np.min(tmm)))
put("MIRNA_MAX_TMM_FACTOR_MAX", float(np.max(tmm)))
put("MIRNA_MAX_TMM_NORMALIZATION", "PASS")


# ------------------------------------------------------------
# E. MAX sensitivity common dispersion + QL fit
# ------------------------------------------------------------
common = estimateGLMCommonDisp(
    max_f,
    design=X,
    offset=offset,
    method="CoxReid",
    subset=428,
    AveLogCPM=None,
    verbose=False,
    weights=None,
)

if common is None or not np.isfinite(common) or common <= 0:
    raise RuntimeError(
        f"MIRNA_MAX_COMMON_DISPERSION_INVALID observed={common}"
    )

bcv = float(np.sqrt(common))

ave = aveLogCPM(
    max_f,
    offset=offset,
    dispersion=common,
)
ave = np.asarray(ave, dtype=np.float64)

if ave.shape != (428,) or np.any(~np.isfinite(ave)):
    raise RuntimeError("MIRNA_MAX_AVELOGCPM_INVALID")

fit = glmQLFit(
    max_f,
    design=X,
    dispersion=common,
    offset=offset,
    lib_size=None,
    weights=None,
    abundance_trend=True,
    AveLogCPM=ave,
    robust=False,
)

if not isinstance(fit.counts, pd.DataFrame):
    raise RuntimeError("MIRNA_MAX_FIT_COUNTS_NOT_DATAFRAME")

if fit.counts.index.astype(str).tolist() != max_f.index.astype(str).tolist():
    raise RuntimeError("MIRNA_MAX_FIT_FEATURE_INDEX_CHANGED")
if fit.counts.columns.astype(str).tolist() != subjects:
    raise RuntimeError("MIRNA_MAX_FIT_SAMPLE_COLUMNS_CHANGED")
if not np.array_equal(
    fit.counts.to_numpy(dtype=np.float64),
    max_numeric,
):
    raise RuntimeError("MIRNA_MAX_FIT_COUNTS_CHANGED")

if not hasattr(fit.design, "design_info"):
    raise RuntimeError("MIRNA_MAX_FIT_PATSY_DESIGN_INFO_MISSING")
if list(fit.design.design_info.column_names) != [
    "COVID19","SEPSIS","HEALTHY"
]:
    raise RuntimeError("MIRNA_MAX_FIT_DESIGN_NAMES_CHANGED")

model_df = pd.DataFrame([{
    "features": 428,
    "samples": 72,
    "fractional_values": max_fractional,
    "common_dispersion": float(common),
    "BCV": bcv,
    "abundance_trend": "TRUE",
    "robust": "FALSE",
    "poisson_bound_for_tests": "TRUE",
    "tmm_factor_geomean": gm,
}])
model_df.to_csv(MIRNA_MAX_MODEL, index=False)

put("MIRNA_MAX_COMMON_DISPERSION", float(common))
put("MIRNA_MAX_BCV", bcv)
put("MIRNA_MAX_QL_MODEL_FIT", "PASS")


# ------------------------------------------------------------
# F. Discover local result schema using the first real sensitivity test
# ------------------------------------------------------------
max_outputs = {
    "COV_vs_H": MAX_COV_H,
    "P_vs_H": MAX_P_H,
    "COV_vs_P": MAX_COV_P,
}

max_tables = {}
max_summary_rows = []

local_schema = None
logfc_col = None
logcpm_col = None
stat_col = None
p_col = None

for contrast_name in ["COV_vs_H","P_vs_H","COV_vs_P"]:
    test = glmQLFTest(
        fit,
        contrast=contrast_vectors[contrast_name],
        poisson_bound=True,
    )
    table = pd.DataFrame(test).copy()

    if local_schema is None:
        if all(
            c in table.columns
            for c in ["logFC","logCPM","F","PValue"]
        ):
            local_schema = "LEGACY_EDGE_STYLE"
            logfc_col = "logFC"
            logcpm_col = "logCPM"
            stat_col = "F"
            p_col = "PValue"
        elif all(
            c in table.columns
            for c in ["log2FoldChange","logCPM","stat","pvalue"]
        ):
            local_schema = "INMOOSE_DESEQ_STYLE_NAMES"
            logfc_col = "log2FoldChange"
            logcpm_col = "logCPM"
            stat_col = "stat"
            p_col = "pvalue"
        else:
            raise RuntimeError(
                f"MIRNA_MAX_UNSUPPORTED_RESULT_SCHEMA "
                f"observed={list(table.columns)}"
            )

    required = [logfc_col,logcpm_col,stat_col,p_col]
    if any(c not in table.columns for c in required):
        raise RuntimeError(
            f"MIRNA_MAX_{contrast_name}_RESULT_SCHEMA_CHANGED"
        )

    if table.shape[0] != 428:
        raise RuntimeError(
            f"MIRNA_MAX_{contrast_name}_ROW_COUNT_WRONG "
            f"observed={table.shape[0]}"
        )

    if table.index.astype(str).tolist() != max_f.index.astype(str).tolist():
        raise RuntimeError(
            f"MIRNA_MAX_{contrast_name}_FEATURE_INDEX_CHANGED"
        )

    out = pd.DataFrame({
        "feature_id": max_f.index.astype(str).tolist(),
        "input_row_index_1based": np.arange(1, 429),
        "contrast": contrast_name,
        "local_inmoose_result_schema": local_schema,
        "logFC": pd.to_numeric(
            table[logfc_col], errors="raise"
        ).to_numpy(dtype=np.float64),
        "logCPM": pd.to_numeric(
            table[logcpm_col], errors="raise"
        ).to_numpy(dtype=np.float64),
        "F": pd.to_numeric(
            table[stat_col], errors="raise"
        ).to_numpy(dtype=np.float64),
        "PValue": pd.to_numeric(
            table[p_col], errors="raise"
        ).to_numpy(dtype=np.float64),
    })

    p = out["PValue"].to_numpy(dtype=np.float64)
    if np.any(~np.isfinite(p)) or np.any((p < 0) | (p > 1)):
        raise RuntimeError(
            f"MIRNA_MAX_{contrast_name}_INVALID_PVALUES"
        )

    fdr = bh_adjust(p)
    out["FDR"] = fdr

    logfc = out["logFC"].to_numpy(dtype=np.float64)
    sig = fdr <= FDR_THRESHOLD
    strict = sig & (np.abs(logfc) >= ABS_LOGFC_THRESHOLD)

    out["statistically_significant_FDR_le_0_05"] = np.where(
        sig,"YES","NO"
    )
    out["effect_size_abs_log2FC_ge_1"] = np.where(
        np.abs(logfc) >= ABS_LOGFC_THRESHOLD,"YES","NO"
    )
    out["significant_FDR_le_0_05_and_abs_log2FC_ge_1"] = np.where(
        strict,"YES","NO"
    )
    out["direction"] = np.where(
        logfc > 0,
        "UP_IN_CONTRAST_NUMERATOR",
        np.where(
            logfc < 0,
            "DOWN_IN_CONTRAST_NUMERATOR",
            "ZERO_OR_NEAR_ZERO",
        ),
    )

    out.to_csv(
        max_outputs[contrast_name],
        index=False,
        compression="gzip",
        float_format="%.17g",
    )

    max_tables[contrast_name] = out

    max_summary_rows.append({
        "contrast": contrast_name,
        "features_tested": 428,
        "common_dispersion": float(common),
        "BCV": bcv,
        "FDR_le_0_05": int(np.sum(sig)),
        "FDR_le_0_05_abs_log2FC_ge_1": int(np.sum(strict)),
        "min_PValue": float(np.min(p)),
        "min_FDR": float(np.min(fdr)),
    })

    put(
        f"MIRNA_MAX_{contrast_name}_FDR_LE_0_05",
        int(np.sum(sig)),
    )
    put(
        f"MIRNA_MAX_{contrast_name}_FDR_LE_0_05_ABS_LOG2FC_GE_1",
        int(np.sum(strict)),
    )

pd.DataFrame(max_summary_rows).to_csv(MAX_SUMMARY, index=False)

put("MIRNA_MAX_LOCAL_GLMQLFTEST_RESULT_SCHEMA", local_schema)
put("MIRNA_MAX_ALL_THREE_CONTRASTS_COMPLETE", "YES")


# ------------------------------------------------------------
# G. MAX contrast algebra
# ------------------------------------------------------------
a = max_tables["COV_vs_H"]["logFC"].to_numpy(dtype=np.float64)
b = max_tables["P_vs_H"]["logFC"].to_numpy(dtype=np.float64)
c = max_tables["COV_vs_P"]["logFC"].to_numpy(dtype=np.float64)

alg_diff = float(np.max(np.abs((a - b) - c)))
if alg_diff > 1e-10:
    raise RuntimeError(
        f"MIRNA_MAX_CONTRAST_ALGEBRA_FAILED maxdiff={alg_diff}"
    )

put("MIRNA_MAX_CONTRAST_LOGFC_ALGEBRA_MAX_ABS_DIFF", alg_diff)
put("MIRNA_MAX_CONTRAST_LOGFC_ALGEBRA", "PASS")


# ------------------------------------------------------------
# H. Primary MEDIAN vs sensitivity MAX concordance
# ------------------------------------------------------------
concordance_rows = []

for contrast_name in ["COV_vs_H","P_vs_H","COV_vs_P"]:
    med = primary_tables[("MIRNA",contrast_name)].copy()
    mx = max_tables[contrast_name].copy()

    if med["feature_id"].astype(str).tolist() != mx["feature_id"].astype(str).tolist():
        raise RuntimeError(
            f"MIRNA_{contrast_name}_MEDIAN_MAX_FEATURE_ORDER_MISMATCH"
        )

    med_fc = med["logFC"].to_numpy(dtype=np.float64)
    max_fc = mx["logFC"].to_numpy(dtype=np.float64)
    med_fdr = med["FDR"].to_numpy(dtype=np.float64)
    max_fdr = mx["FDR"].to_numpy(dtype=np.float64)

    pearson = float(pearsonr(med_fc, max_fc).statistic)
    spearman = float(spearmanr(med_fc, max_fc).statistic)

    same_sign = (
        np.sign(med_fc) == np.sign(max_fc)
    )
    sign_concordance = float(np.mean(same_sign))

    med_sig = med_fdr <= FDR_THRESHOLD
    max_sig = max_fdr <= FDR_THRESHOLD
    med_strict = med_sig & (np.abs(med_fc) >= ABS_LOGFC_THRESHOLD)
    max_strict = max_sig & (np.abs(max_fc) >= ABS_LOGFC_THRESHOLD)

    both_sig = med_sig & max_sig
    union_sig = med_sig | max_sig
    both_strict = med_strict & max_strict
    union_strict = med_strict | max_strict

    sig_jaccard = (
        float(np.sum(both_sig) / np.sum(union_sig))
        if np.sum(union_sig) > 0 else 1.0
    )
    strict_jaccard = (
        float(np.sum(both_strict) / np.sum(union_strict))
        if np.sum(union_strict) > 0 else 1.0
    )

    concordance_rows.append({
        "contrast": contrast_name,
        "features_compared": 428,
        "logFC_Pearson_r": pearson,
        "logFC_Spearman_rho": spearman,
        "all_feature_sign_concordance": sign_concordance,
        "median_FDR_le_0_05": int(np.sum(med_sig)),
        "max_FDR_le_0_05": int(np.sum(max_sig)),
        "both_FDR_le_0_05": int(np.sum(both_sig)),
        "median_only_FDR_le_0_05": int(np.sum(med_sig & ~max_sig)),
        "max_only_FDR_le_0_05": int(np.sum(max_sig & ~med_sig)),
        "FDR_le_0_05_Jaccard": sig_jaccard,
        "median_strict": int(np.sum(med_strict)),
        "max_strict": int(np.sum(max_strict)),
        "both_strict": int(np.sum(both_strict)),
        "strict_Jaccard": strict_jaccard,
        "median_abs_logFC_difference": float(
            np.median(np.abs(med_fc - max_fc))
        ),
        "max_abs_logFC_difference": float(
            np.max(np.abs(med_fc - max_fc))
        ),
        "sensitivity_interpretation_status": "QUANTITATIVE_REVIEW_REQUIRED",
    })

pd.DataFrame(concordance_rows).to_csv(CONCORDANCE, index=False)

put("MIRNA_MEDIAN_MAX_CONCORDANCE_ROWS", 3)
put("MIRNA_MAX_SENSITIVITY_INTERPRETATION_STATUS", "QUANTITATIVE_REVIEW_REQUIRED")


# ------------------------------------------------------------
# I. Freeze sensitivity specification
# ------------------------------------------------------------
spec_lines = [
    "GSE243219_D6A_MIRNA_SENSITIVITY_SPECIFICATION",
    "PRIMARY_MIRNA_CONSOLIDATION=MEDIAN_ACROSS_PRECURSOR_ROWS_PER_SAMPLE",
    "SENSITIVITY_MIRNA_CONSOLIDATION=MAX_ACROSS_PRECURSOR_ROWS_PER_SAMPLE",
    "PRIMARY_RESULT_AUTHORITY=UNCHANGED",
    "PRIMARY_D6_V5_RESULTS_MODIFIED=NO",
    "SENSITIVITY_FEATURE_SELECTION=SAME_D3A_FROZEN_428_IDENTITIES",
    "SENSITIVITY_REFILTERING=PROHIBITED",
    "RATIONALE=ISOLATE_CONSOLIDATION_METHOD_EFFECT",
    "SENSITIVITY_LIBRARY_SIZES=RECOMPUTED_AFTER_SAME_428_FEATURE_SELECTION",
    "SENSITIVITY_TMM=RECOMPUTED_FOR_MAX_MATRIX",
    "TMM_IMPLEMENTATION=D2E_V4_VALIDATED_EDGE_STYLE_FUNCTION",
    "SENSITIVITY_COMMON_DISPERSION=COX_REID_COMMON_REESTIMATED_FOR_MAX_MATRIX",
    "SENSITIVITY_QL_ABUNDANCE_TREND=TRUE",
    "SENSITIVITY_QL_ROBUST=FALSE",
    "SENSITIVITY_POISSON_BOUND=TRUE",
    "SENSITIVITY_CONTRASTS=COV_vs_H|P_vs_H|COV_vs_P",
    "SENSITIVITY_MULTIPLE_TESTING=BENJAMINI_HOCHBERG",
    "PRIMARY_STATISTICAL_CALL=FDR_LE_0.05",
    "SECONDARY_EFFECT_SIZE_ANNOTATION=FDR_LE_0.05_AND_ABS_LOG2FC_GE_1",
    "SENSITIVITY_ACCEPTANCE_THRESHOLD=NONE_PREDECLARED",
    "SENSITIVITY_CONCORDANCE_REQUIRES_QUANTITATIVE_REVIEW=YES",
    "SAMPLE_EXCLUSION_EXECUTED=NO",
    "COUNT_ROUNDING_EXECUTED=NO",
    "MRNA_REANALYSIS_EXECUTED=NO",
]
SENSITIVITY_SPEC.write_text(
    "\n".join(spec_lines) + "\n",
    encoding="utf-8",
)

put("PRIMARY_MIRNA_RESULT_AUTHORITY", "MEDIAN_UNCHANGED")
put("SENSITIVITY_ACCEPTANCE_THRESHOLD_PREDECLARED", "NO")
put("SENSITIVITY_QUANTITATIVE_REVIEW_REQUIRED", "YES")
put("SAMPLE_EXCLUSION_EXECUTED", "NO")
put("COUNT_ROUNDING_EXECUTED", "NO")
put("MRNA_REANALYSIS_EXECUTED", "NO")
put("NETWORK_EXECUTED", "NO")
put("ACLA_EXECUTED", "NO")
put("PHASE_D6A_COMPUTATION_COMPLETE", "YES")
put("READY_FOR_D6B_SENSITIVITY_REVIEW_AND_DOWNSTREAM_SELECTION_FREEZE", "YES")
put("NEXT_PHASE", "D6B_DE_SENSITIVITY_REVIEW_AND_DOWNSTREAM_SELECTION_FREEZE")

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
    $D2E4ValidationPy,
    $MirnaMaxSource,
    $MirnaPrimaryMask,
    $Cohort,
    $DesignMatrix,
    $ContrastMatrix,
    $PrimaryMrnaCovH,
    $PrimaryMrnaPH,
    $PrimaryMrnaCovP,
    $PrimaryMirnaCovH,
    $PrimaryMirnaPH,
    $PrimaryMirnaCovP,
    $PrimarySummary,
    $PrimaryAudit,
    $MirnaMaxFiltered,
    $MirnaMaxNorm,
    $MirnaMaxModel,
    $MaxCovH,
    $MaxPH,
    $MaxCovP,
    $MaxSummary,
    $Concordance,
    $SensitivitySpec,
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
        Write-Host '=== D6A PYTHON STDERR ==='
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
    throw ('D6A_PYTHON_FAILED exit={0} full_traceback={1}' -f `
        $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D6A_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('D2E_V4_TMM_FUNCTION_EXTRACTION','PASS'),
    @('TMM_PRODUCTION_SELF_TEST','PASS'),
    @('PRIMARY_D6_RESULT_TABLES_AUDITED','6/6'),
    @('PRIMARY_D6_BH_RECOMPUTATION','PASS'),
    @('PRIMARY_D6_CONTRAST_ALGEBRA_REAUDIT','PASS'),
    @('PRIMARY_D6_RESULTS_MODIFIED','NO'),
    @('MIRNA_MAX_SOURCE_FEATURES','2656'),
    @('MIRNA_MAX_SENSITIVITY_FEATURES','428'),
    @('MIRNA_MAX_SAME_PRIMARY_FEATURE_IDENTITIES','YES'),
    @('MIRNA_MAX_SENSITIVITY_REFILTERING_EXECUTED','NO'),
    @('MIRNA_MAX_FILTERED_ROUNDTRIP_INTEGRITY','PASS'),
    @('MIRNA_MAX_TMM_NORMALIZATION','PASS'),
    @('MIRNA_MAX_QL_MODEL_FIT','PASS'),
    @('MIRNA_MAX_ALL_THREE_CONTRASTS_COMPLETE','YES'),
    @('MIRNA_MAX_CONTRAST_LOGFC_ALGEBRA','PASS'),
    @('MIRNA_MEDIAN_MAX_CONCORDANCE_ROWS','3'),
    @('MIRNA_MAX_SENSITIVITY_INTERPRETATION_STATUS','QUANTITATIVE_REVIEW_REQUIRED'),
    @('PRIMARY_MIRNA_RESULT_AUTHORITY','MEDIAN_UNCHANGED'),
    @('SENSITIVITY_ACCEPTANCE_THRESHOLD_PREDECLARED','NO'),
    @('SENSITIVITY_QUANTITATIVE_REVIEW_REQUIRED','YES'),
    @('SAMPLE_EXCLUSION_EXECUTED','NO'),
    @('COUNT_ROUNDING_EXECUTED','NO'),
    @('MRNA_REANALYSIS_EXECUTED','NO'),
    @('NETWORK_EXECUTED','NO'),
    @('ACLA_EXECUTED','NO'),
    @('PHASE_D6A_COMPUTATION_COMPLETE','YES'),
    @('READY_FOR_D6B_SENSITIVITY_REVIEW_AND_DOWNSTREAM_SELECTION_FREEZE','YES'),
    @('NEXT_PHASE','D6B_DE_SENSITIVITY_REVIEW_AND_DOWNSTREAM_SELECTION_FREEZE')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D6A_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 3. Decision
# ------------------------------------------------------------
@(
    'GSE243219_D6A_DECISION',
    'PHASE_D6A_STATUS=PASS',
    'MODE=RESULT_AUDIT_AND_PROSPECTIVE_SENSITIVITY',
    'D2E_V4_TMM_CERTIFICATION_GATE=PASS',
    'D2E_V4_OUTPUTS_RECERTIFIED=6/6',
    'D3_V2_MATRIX_CERTIFICATION_GATE=PASS',
    'D3_V2_OUTPUTS_RECERTIFIED=15/15',
    'D3A_FILTER_CERTIFICATION_GATE=PASS',
    'D3A_OUTPUTS_RECERTIFIED=12/12',
    'D4_DESIGN_COHORT_CERTIFICATION_GATE=PASS',
    'D4_OUTPUTS_RECERTIFIED=14/14',
    'D5_V2_MODEL_CERTIFICATION_GATE=PASS',
    'D5_V2_OUTPUTS_RECERTIFIED=10/10',
    'D6_V5_PRIMARY_DE_CERTIFICATION_GATE=PASS',
    'D6_V5_OUTPUTS_RECERTIFIED=16/16',
    'PRIMARY_D6_RESULT_TABLES_AUDITED=6/6',
    'PRIMARY_D6_BH_RECOMPUTATION=PASS',
    'PRIMARY_D6_CONTRAST_ALGEBRA_REAUDIT=PASS',
    'PRIMARY_D6_RESULTS_MODIFIED=NO',
    'PRIMARY_MIRNA_CONSOLIDATION=MEDIAN',
    'SENSITIVITY_MIRNA_CONSOLIDATION=MAX',
    'MIRNA_MAX_SOURCE_FEATURES=2656',
    'MIRNA_MAX_SENSITIVITY_FEATURES=428',
    'MIRNA_MAX_SAME_PRIMARY_FEATURE_IDENTITIES=YES',
    'MIRNA_MAX_SENSITIVITY_REFILTERING_EXECUTED=NO',
    ('MIRNA_MAX_FILTERED_FRACTIONAL_VALUES={0}' -f (Cap 'MIRNA_MAX_FILTERED_FRACTIONAL_VALUES')),
    ('MIRNA_MAX_TMM_FACTOR_GEOMEAN={0}' -f (Cap 'MIRNA_MAX_TMM_FACTOR_GEOMEAN')),
    ('MIRNA_MAX_TMM_FACTOR_MIN={0}' -f (Cap 'MIRNA_MAX_TMM_FACTOR_MIN')),
    ('MIRNA_MAX_TMM_FACTOR_MAX={0}' -f (Cap 'MIRNA_MAX_TMM_FACTOR_MAX')),
    ('MIRNA_MAX_COMMON_DISPERSION={0}' -f (Cap 'MIRNA_MAX_COMMON_DISPERSION')),
    ('MIRNA_MAX_BCV={0}' -f (Cap 'MIRNA_MAX_BCV')),
    'MIRNA_MAX_QL_MODEL_FIT=PASS',
    ('MIRNA_MAX_LOCAL_GLMQLFTEST_RESULT_SCHEMA={0}' -f (Cap 'MIRNA_MAX_LOCAL_GLMQLFTEST_RESULT_SCHEMA')),
    ('MIRNA_MAX_COV_vs_H_FDR_LE_0_05={0}' -f (Cap 'MIRNA_MAX_COV_vs_H_FDR_LE_0_05')),
    ('MIRNA_MAX_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_MAX_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MIRNA_MAX_P_vs_H_FDR_LE_0_05={0}' -f (Cap 'MIRNA_MAX_P_vs_H_FDR_LE_0_05')),
    ('MIRNA_MAX_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_MAX_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MIRNA_MAX_COV_vs_P_FDR_LE_0_05={0}' -f (Cap 'MIRNA_MAX_COV_vs_P_FDR_LE_0_05')),
    ('MIRNA_MAX_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_MAX_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    'MIRNA_MAX_ALL_THREE_CONTRASTS_COMPLETE=YES',
    ('MIRNA_MAX_CONTRAST_LOGFC_ALGEBRA_MAX_ABS_DIFF={0}' -f (Cap 'MIRNA_MAX_CONTRAST_LOGFC_ALGEBRA_MAX_ABS_DIFF')),
    'MIRNA_MAX_CONTRAST_LOGFC_ALGEBRA=PASS',
    'MIRNA_MEDIAN_MAX_CONCORDANCE_ROWS=3',
    'SENSITIVITY_ACCEPTANCE_THRESHOLD_PREDECLARED=NO',
    'SENSITIVITY_QUANTITATIVE_REVIEW_REQUIRED=YES',
    'PRIMARY_MIRNA_RESULT_AUTHORITY=MEDIAN_UNCHANGED',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'MRNA_REANALYSIS_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D6B_SENSITIVITY_REVIEW_AND_DOWNSTREAM_SELECTION_FREEZE=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D6B_DE_SENSITIVITY_REVIEW_AND_DOWNSTREAM_SELECTION_FREEZE',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Manifest
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $PrimaryAudit,
    $MirnaMaxFiltered,
    $MirnaMaxNorm,
    $MirnaMaxModel,
    $MaxCovH,
    $MaxPH,
    $MaxCovP,
    $MaxSummary,
    $Concordance,
    $SensitivitySpec,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D6A_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p
    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D6ASHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D6A SUMMARY ===',
    'PHASE_D6A_STATUS=PASS',
    'MODE=RESULT_AUDIT_AND_PROSPECTIVE_SENSITIVITY',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('INMOOSE_VERSION={0}' -f $InMooseVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    ('SCIPY_VERSION={0}' -f $ScipyVersion),
    'D2E_V4_TMM_CERTIFICATION_GATE=PASS',
    'D3_V2_MATRIX_CERTIFICATION_GATE=PASS',
    'D3A_FILTER_CERTIFICATION_GATE=PASS',
    'D4_DESIGN_COHORT_CERTIFICATION_GATE=PASS',
    'D5_V2_MODEL_CERTIFICATION_GATE=PASS',
    'D6_V5_PRIMARY_DE_CERTIFICATION_GATE=PASS',
    'PRIMARY_D6_RESULT_TABLES_AUDITED=6/6',
    'PRIMARY_D6_BH_RECOMPUTATION=PASS',
    'PRIMARY_D6_CONTRAST_ALGEBRA_REAUDIT=PASS',
    'PRIMARY_D6_RESULTS_MODIFIED=NO',
    'PRIMARY_MIRNA_CONSOLIDATION=MEDIAN',
    'SENSITIVITY_MIRNA_CONSOLIDATION=MAX',
    'MIRNA_MAX_SOURCE_FEATURES=2656',
    'MIRNA_MAX_SENSITIVITY_FEATURES=428',
    'MIRNA_MAX_SAME_PRIMARY_FEATURE_IDENTITIES=YES',
    'MIRNA_MAX_SENSITIVITY_REFILTERING_EXECUTED=NO',
    ('MIRNA_MAX_FILTERED_FRACTIONAL_VALUES={0}' -f (Cap 'MIRNA_MAX_FILTERED_FRACTIONAL_VALUES')),
    'MIRNA_MAX_FILTERED_ROUNDTRIP_INTEGRITY=PASS',
    ('MIRNA_MAX_TMM_FACTOR_GEOMEAN={0}' -f (Cap 'MIRNA_MAX_TMM_FACTOR_GEOMEAN')),
    ('MIRNA_MAX_TMM_FACTOR_MIN={0}' -f (Cap 'MIRNA_MAX_TMM_FACTOR_MIN')),
    ('MIRNA_MAX_TMM_FACTOR_MAX={0}' -f (Cap 'MIRNA_MAX_TMM_FACTOR_MAX')),
    'MIRNA_MAX_TMM_NORMALIZATION=PASS',
    ('MIRNA_MAX_COMMON_DISPERSION={0}' -f (Cap 'MIRNA_MAX_COMMON_DISPERSION')),
    ('MIRNA_MAX_BCV={0}' -f (Cap 'MIRNA_MAX_BCV')),
    'MIRNA_MAX_QL_MODEL_FIT=PASS',
    ('MIRNA_MAX_LOCAL_GLMQLFTEST_RESULT_SCHEMA={0}' -f (Cap 'MIRNA_MAX_LOCAL_GLMQLFTEST_RESULT_SCHEMA')),
    ('MIRNA_MAX_COV_vs_H_FDR_LE_0_05={0}' -f (Cap 'MIRNA_MAX_COV_vs_H_FDR_LE_0_05')),
    ('MIRNA_MAX_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_MAX_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MIRNA_MAX_P_vs_H_FDR_LE_0_05={0}' -f (Cap 'MIRNA_MAX_P_vs_H_FDR_LE_0_05')),
    ('MIRNA_MAX_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_MAX_P_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    ('MIRNA_MAX_COV_vs_P_FDR_LE_0_05={0}' -f (Cap 'MIRNA_MAX_COV_vs_P_FDR_LE_0_05')),
    ('MIRNA_MAX_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1={0}' -f (Cap 'MIRNA_MAX_COV_vs_P_FDR_LE_0_05_ABS_LOG2FC_GE_1')),
    'MIRNA_MAX_ALL_THREE_CONTRASTS_COMPLETE=YES',
    ('MIRNA_MAX_CONTRAST_LOGFC_ALGEBRA_MAX_ABS_DIFF={0}' -f (Cap 'MIRNA_MAX_CONTRAST_LOGFC_ALGEBRA_MAX_ABS_DIFF')),
    'MIRNA_MAX_CONTRAST_LOGFC_ALGEBRA=PASS',
    'MIRNA_MEDIAN_MAX_CONCORDANCE_ROWS=3',
    'MIRNA_MAX_SENSITIVITY_INTERPRETATION_STATUS=QUANTITATIVE_REVIEW_REQUIRED',
    'SENSITIVITY_ACCEPTANCE_THRESHOLD_PREDECLARED=NO',
    'PRIMARY_MIRNA_RESULT_AUTHORITY=MEDIAN_UNCHANGED',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'MRNA_REANALYSIS_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'PHASE_D6A_COMPUTATION_COMPLETE=YES',
    'READY_FOR_D6B_SENSITIVITY_REVIEW_AND_DOWNSTREAM_SELECTION_FREEZE=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D6B_DE_SENSITIVITY_REVIEW_AND_DOWNSTREAM_SELECTION_FREEZE',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D6A_PRIMARY_DE_AUDIT={0}' -f $PrimaryAudit)
Write-Host ('D6A_MIRNA_MAX_FILTERED_COUNTS={0}' -f $MirnaMaxFiltered)
Write-Host ('D6A_MIRNA_MAX_NORMALIZATION={0}' -f $MirnaMaxNorm)
Write-Host ('D6A_MIRNA_MAX_MODEL_SUMMARY={0}' -f $MirnaMaxModel)
Write-Host ('D6A_MIRNA_MAX_COV_vs_H_RESULTS={0}' -f $MaxCovH)
Write-Host ('D6A_MIRNA_MAX_P_vs_H_RESULTS={0}' -f $MaxPH)
Write-Host ('D6A_MIRNA_MAX_COV_vs_P_RESULTS={0}' -f $MaxCovP)
Write-Host ('D6A_MIRNA_MAX_DE_SUMMARY={0}' -f $MaxSummary)
Write-Host ('D6A_MIRNA_MEDIAN_VS_MAX_CONCORDANCE={0}' -f $Concordance)
Write-Host ('D6A_SENSITIVITY_SPEC={0}' -f $SensitivitySpec)
Write-Host ('D6A_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D6A_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D6A=PASS'
Write-Host 'STOP=YES'
