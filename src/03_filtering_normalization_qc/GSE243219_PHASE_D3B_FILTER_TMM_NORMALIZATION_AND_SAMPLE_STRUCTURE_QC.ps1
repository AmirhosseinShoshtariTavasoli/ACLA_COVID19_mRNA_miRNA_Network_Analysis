$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D3B — FILTER APPLICATION + TMM NORMALIZATION
#             + SAMPLE-STRUCTURE QC
#
# Authorized:
#   - apply the D3A-frozen candidate feature masks
#   - retain all 72 paired subjects
#   - recompute library sizes after feature filtering
#   - use the exact D2E-V4-validated edge-style TMM function
#   - compute TMM factors and effective library sizes
#   - create normalized CPM and edge-style logCPM matrices
#     for descriptive/sample-structure QC
#   - PCA/sample-structure REVIEW flags only
#
# Prohibited:
#   - sample exclusion
#   - changing the frozen D3A feature mask
#   - mRNA count rounding
#   - DE
#   - network construction
#   - A-CLA
#
# IMPORTANT:
#   DE later must use filtered RAW counts + log(effective library
#   size) offsets through the already validated low-level edgepy
#   route. It must NOT use normalized CPM/logCPM as DE input.
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D2Root = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING'
$D3Root = Join-Path $Project '03_QC_AND_FILTERING'

$D2DRun = Join-Path $D2Root 'D2D_PREFLIGHT_20260904_195001'
$VenvPython = Join-Path $D2DRun 'venv\Scripts\python.exe'

$D2E4Run = Join-Path $D2Root 'D2E_V4_TMM_OFFLINE_VALIDATION_20260904_225425'
$D2E4Manifest = Join-Path $D2E4Run 'D2E_V4_OUTPUT_SHA256_MANIFEST.csv'
$D2E4ValidationPy = Join-Path $D2E4Run 'D2E_V4_OFFLINE_TMM_VALIDATION.py'
$D2E4Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D2E_V4_20260904_225425\PHASE_D2E_V4_SUMMARY.txt'

$D3Run = Join-Path $D3Root 'D3_V2_MATRIX_QC_20260904_231245'
$Metadata = Join-Path $D3Run 'D3_PAIRED_SAMPLE_METADATA.csv'
$MrnaRaw = Join-Path $D3Run 'D3_MRNA_RAW_COUNTS_26364x72.csv.gz'
$MirnaRawPrimary = Join-Path $D3Run 'D3_MIRNA_MATURE_MEDIAN_COUNTS_2656x72.csv.gz'

$D3ARun = Join-Path $D3Root 'D3A_QC_FILTER_DESIGN_20260905_092247'
$D3AManifest = Join-Path $D3ARun 'D3A_OUTPUT_SHA256_MANIFEST.csv'
$D3AReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D3A_20260905_092247\PHASE_D3A_SUMMARY.txt'
$D3ADecision = Join-Path $D3ARun 'D3A_DECISION.txt'
$MrnaMask = Join-Path $D3ARun 'D3A_MRNA_FILTERBYEXPR_CANDIDATE.csv.gz'
$MirnaMask = Join-Path $D3ARun 'D3A_MIRNA_FILTERBYEXPR_CANDIDATE.csv.gz'
$D3AQcReview = Join-Path $D3ARun 'D3A_SAMPLE_QC_REVIEW.csv'
$D3AFrozenStrategy = Join-Path $D3ARun 'D3A_FROZEN_QC_AND_FILTER_STRATEGY.txt'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D3Root ('D3B_FILTER_TMM_SAMPLE_QC_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D3B_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D3B_FILTER_TMM_AND_SAMPLE_STRUCTURE_QC.py'

$MrnaFiltered = Join-Path $RunDir 'D3B_MRNA_FILTERED_RAW_COUNTS_15083x72.csv.gz'
$MirnaFiltered = Join-Path $RunDir 'D3B_MIRNA_FILTERED_RAW_COUNTS_428x72.csv.gz'

$NormTable = Join-Path $RunDir 'D3B_TMM_NORMALIZATION_FACTORS_AND_LIBRARY_SIZES.csv'

$MrnaCpm = Join-Path $RunDir 'D3B_MRNA_TMM_NORMALIZED_CPM_15083x72.csv.gz'
$MirnaCpm = Join-Path $RunDir 'D3B_MIRNA_TMM_NORMALIZED_CPM_428x72.csv.gz'
$MrnaLogCpm = Join-Path $RunDir 'D3B_MRNA_TMM_LOGCPM_PRIOR2_QC_15083x72.csv.gz'
$MirnaLogCpm = Join-Path $RunDir 'D3B_MIRNA_TMM_LOGCPM_PRIOR2_QC_428x72.csv.gz'

$PcaScores = Join-Path $RunDir 'D3B_PCA_SAMPLE_SCORES.csv'
$PcaVariance = Join-Path $RunDir 'D3B_PCA_EXPLAINED_VARIANCE.csv'
$StructureReview = Join-Path $RunDir 'D3B_SAMPLE_STRUCTURE_REVIEW.csv'

$MrnaPcaPng = Join-Path $RunDir 'D3B_MRNA_PCA_PC1_PC2.png'
$MirnaPcaPng = Join-Path $RunDir 'D3B_MIRNA_PCA_PC1_PC2.png'

$ResultJson = Join-Path $RunDir 'D3B_RESULT.json'
$PythonStdout = Join-Path $RunDir 'D3B_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D3B_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D3B_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D3B_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D3B_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D3B_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D3B — FILTER APPLICATION + TMM NORMALIZATION + SAMPLE-STRUCTURE QC ==='
Write-Host 'MODE=FILTER_NORMALIZE_AND_DESCRIPTIVE_SAMPLE_QC'
Write-Host 'REAL_BIOLOGICAL_MATRICES_READ=YES'
Write-Host 'FEATURE_FILTER_APPLICATION_EXECUTED=YES'
Write-Host 'TMM_NORMALIZATION_EXECUTED=YES'
Write-Host 'NORMALIZED_CPM_CREATED=YES'
Write-Host 'LOGCPM_QC_MATRIX_CREATED=YES'
Write-Host 'SAMPLE_STRUCTURE_PCA_EXECUTED=YES'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'ALL_72_SAMPLES_RETAINED=YES'
Write-Host 'MRNA_COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'DE_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $VenvPython,
    $D2E4Manifest,$D2E4ValidationPy,$D2E4Report,
    $Metadata,$MrnaRaw,$MirnaRawPrimary,
    $D3AManifest,$D3AReport,$D3ADecision,
    $MrnaMask,$MirnaMask,$D3AQcReview,$D3AFrozenStrategy
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D3B_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D3BSHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

# ------------------------------------------------------------
# 1. Re-certify D2E-V4 TMM validation
# ------------------------------------------------------------
$d2e = Get-Content -LiteralPath $D2E4Report -Raw

foreach ($tok in @(
    'PHASE_D2E_V4_STATUS=PASS',
    'PUBLISHED_TOY_REFERENCE_VALIDATION=PASS',
    'PROPORTIONAL_ORACLE_CONCORDANCE=PASS',
    'COMPOSITION_INTEGER_ORACLE_CONCORDANCE=PASS',
    'ZERO_CONTAINING_INTEGER_ORACLE_CONCORDANCE=PASS',
    'FRACTIONAL_ORACLE_CONCORDANCE=PASS',
    'FRACTIONAL_INPUT_UNCHANGED=YES',
    'CUSTOM_LIBSIZE_CAPABILITY=PASS',
    'ALL_OFFLINE_TMM_REFERENCE_CHECKS=PASS',
    'ALL_TMM_INVARIANTS=PASS',
    'PYTHON_TMM_REFERENCE_IMPLEMENTATION_VALIDATED=YES',
    'TMM_NORMALIZATION_ENGINE_STATUS=PASS'
)) {
    if ($d2e -notmatch [regex]::Escape($tok)) {
        throw ('D2E_V4_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$d2eRows = @(Import-Csv -LiteralPath $D2E4Manifest)
if ($d2eRows.Count -ne 6) {
    throw ('D2E_V4_MANIFEST_ROW_COUNT_CHANGED expected=6 observed={0}' -f $d2eRows.Count)
}

foreach ($r in $d2eRows) {
    if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
        throw ('D2E_V4_OUTPUT_MISSING={0}' -f $r.full_path)
    }

    $item = Get-Item -LiteralPath $r.full_path
    if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
        (Get-D3BSHA256 $r.full_path) -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D2E_V4_OUTPUT_CHANGED={0}' -f $r.full_path)
    }
}

Write-Host 'D2E_V4_CERTIFICATION_GATE=PASS'
Write-Host 'D2E_V4_OUTPUTS_RECERTIFIED=6/6'

# ------------------------------------------------------------
# 2. Re-certify D3A frozen QC/filter design
# ------------------------------------------------------------
$d3a = Get-Content -LiteralPath $D3AReport -Raw

foreach ($tok in @(
    'PHASE_D3A_STATUS=PASS',
    'FEATURE_FILTER_METHOD=EDGER_FILTERBYEXPR_DEFAULT_SPECIFICATION',
    'FILTER_MIN_COUNT=10',
    'FILTER_MIN_TOTAL_COUNT=15',
    'FILTER_LARGE_N=10',
    'FILTER_MIN_PROP=0.7',
    'SMALLEST_GROUP_SIZE=15',
    'FILTER_MIN_SAMPLE_SIZE_NUMERIC=13.5',
    'FILTER_EFFECTIVE_MIN_SAMPLES_INTEGER=14',
    'MRNA_CANDIDATE_KEEP_FEATURES=15083',
    'MRNA_CANDIDATE_DROP_FEATURES=11281',
    'MIRNA_CANDIDATE_KEEP_FEATURES=428',
    'MIRNA_CANDIDATE_DROP_FEATURES=2228',
    'QC_REVIEW_FLAGGED_SUBJECTS=2',
    'QC_REVIEW_FLAGGED_SUBJECT_IDS=H24|P25',
    'SAMPLE_EXCLUSION_AUTHORIZED=NO',
    'FEATURE_FILTER_STRATEGY_FROZEN=YES',
    'FEATURE_FILTER_APPLICATION_EXECUTED=NO',
    'TMM_NORMALIZATION_EXECUTED=NO',
    'READY_FOR_D3B_FILTER_APPLICATION_AND_TMM_QC=YES',
    'NEXT_PHASE=D3B_FILTER_APPLICATION_TMM_NORMALIZATION_AND_SAMPLE_STRUCTURE_QC'
)) {
    if ($d3a -notmatch [regex]::Escape($tok)) {
        throw ('D3A_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$d3aRows = @(Import-Csv -LiteralPath $D3AManifest)
if ($d3aRows.Count -ne 12) {
    throw ('D3A_MANIFEST_ROW_COUNT_CHANGED expected=12 observed={0}' -f $d3aRows.Count)
}

foreach ($r in $d3aRows) {
    if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
        throw ('D3A_OUTPUT_MISSING={0}' -f $r.full_path)
    }

    $item = Get-Item -LiteralPath $r.full_path
    if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
        (Get-D3BSHA256 $r.full_path) -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D3A_OUTPUT_CHANGED={0}' -f $r.full_path)
    }
}

Write-Host 'D3A_CERTIFICATION_GATE=PASS'
Write-Host 'D3A_OUTPUTS_RECERTIFIED=12/12'

$PythonVersion = & $VenvPython -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$PandasVersion = & $VenvPython -c "import pandas; print(pandas.__version__)"
$NumpyVersion = & $VenvPython -c "import numpy; print(numpy.__version__)"
$SklearnVersion = & $VenvPython -c "import sklearn; print(sklearn.__version__)"

if ($PythonVersion -ne '3.12.3') {
    throw ('VALIDATED_PYTHON_CHANGED={0}' -f $PythonVersion)
}

Write-Host ('PYTHON_VERSION={0}' -f $PythonVersion)
Write-Host ('PANDAS_VERSION={0}' -f $PandasVersion)
Write-Host ('NUMPY_VERSION={0}' -f $NumpyVersion)
Write-Host ('SKLEARN_VERSION={0}' -f $SklearnVersion)

# ------------------------------------------------------------
# 3. Python D3B execution
# ------------------------------------------------------------
$PythonCode = @'
import ast
import json
import math
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.decomposition import PCA


METADATA = Path(sys.argv[1])
MRNA_RAW = Path(sys.argv[2])
MIRNA_RAW = Path(sys.argv[3])
MRNA_MASK = Path(sys.argv[4])
MIRNA_MASK = Path(sys.argv[5])
D3A_QC_REVIEW = Path(sys.argv[6])
D2E_VALIDATION_PY = Path(sys.argv[7])

MRNA_FILTERED = Path(sys.argv[8])
MIRNA_FILTERED = Path(sys.argv[9])
NORM_TABLE = Path(sys.argv[10])
MRNA_CPM = Path(sys.argv[11])
MIRNA_CPM = Path(sys.argv[12])
MRNA_LOGCPM = Path(sys.argv[13])
MIRNA_LOGCPM = Path(sys.argv[14])
PCA_SCORES = Path(sys.argv[15])
PCA_VARIANCE = Path(sys.argv[16])
STRUCTURE_REVIEW = Path(sys.argv[17])
MRNA_PCA_PNG = Path(sys.argv[18])
MIRNA_PCA_PNG = Path(sys.argv[19])
RESULT_JSON = Path(sys.argv[20])


results = {}

def put(k, v):
    results[k] = v
    print(f"{k}={v}")


# ------------------------------------------------------------
# A. Load exact D2E-V4 validated TMM function from its source
#    via AST, rather than retyping/reimplementing it.
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


# Runtime production self-test against D2E-V4 published reference.
toy_sample_major = np.array(
    [
        [200, 300, 500, 2000, 7000],
        [400, 600, 1000, 4000, 14000],
        [200, 300, 500, 2000, 17000],
        [200, 300, 500, 2000, 2000],
    ],
    dtype=np.float64,
)

toy_expected = np.array([1.0, 1.0, 0.5, 2.0], dtype=np.float64)
toy_observed = edge_style_tmm(toy_sample_major.T)
toy_diff = float(np.max(np.abs(toy_observed - toy_expected)))

if toy_diff > 1e-12:
    raise RuntimeError(f"TMM_PRODUCTION_SELF_TEST_FAILED max_abs_diff={toy_diff}")

put("TMM_VALIDATED_SOURCE_FUNCTION_EXTRACTION", "PASS")
put("TMM_PRODUCTION_TOY_SELF_TEST", "PASS")
put("TMM_PRODUCTION_TOY_MAX_ABS_DIFF", toy_diff)


# ------------------------------------------------------------
# B. Load real matrices / metadata / frozen masks
# ------------------------------------------------------------
metadata = pd.read_csv(METADATA)

mrna = pd.read_csv(
    MRNA_RAW,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)

mirna = pd.read_csv(
    MIRNA_RAW,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)

mrna_mask = pd.read_csv(MRNA_MASK, compression="gzip")
mirna_mask = pd.read_csv(MIRNA_MASK, compression="gzip")
qc_review = pd.read_csv(D3A_QC_REVIEW)

if metadata.shape[0] != 72:
    raise RuntimeError(f"METADATA_ROWS_CHANGED observed={metadata.shape[0]}")
if mrna.shape != (26364, 72):
    raise RuntimeError(f"MRNA_RAW_SHAPE_CHANGED observed={mrna.shape}")
if mirna.shape != (2656, 72):
    raise RuntimeError(f"MIRNA_RAW_SHAPE_CHANGED observed={mirna.shape}")

subjects = metadata["subject_id"].astype(str).tolist()
disease = metadata["disease_state"].astype(str).tolist()

if list(mrna.columns) != subjects or list(mirna.columns) != subjects:
    raise RuntimeError("REAL_MATRIX_SAMPLE_ORDER_CHANGED")

if set(subjects) != set(qc_review["subject_id"].astype(str)):
    raise RuntimeError("D3A_QC_REVIEW_SUBJECT_SET_CHANGED")

if mrna_mask.shape[0] != 26364 or mirna_mask.shape[0] != 2656:
    raise RuntimeError("D3A_FILTER_MASK_ROW_COUNT_CHANGED")

if mrna_mask["feature_id"].astype(str).tolist() != mrna.index.astype(str).tolist():
    raise RuntimeError("MRNA_FILTER_MASK_FEATURE_ORDER_MISMATCH")

if mirna_mask["feature_id"].astype(str).tolist() != mirna.index.astype(str).tolist():
    raise RuntimeError("MIRNA_FILTER_MASK_FEATURE_ORDER_MISMATCH")

mrna_keep = mrna_mask["candidate_keep"].astype(str).eq("YES").to_numpy()
mirna_keep = mirna_mask["candidate_keep"].astype(str).eq("YES").to_numpy()

if int(np.sum(mrna_keep)) != 15083:
    raise RuntimeError(
        f"MRNA_KEEP_COUNT_CHANGED observed={int(np.sum(mrna_keep))}"
    )
if int(np.sum(mirna_keep)) != 428:
    raise RuntimeError(
        f"MIRNA_KEEP_COUNT_CHANGED observed={int(np.sum(mirna_keep))}"
    )

# Apply frozen masks only. Samples are never subset.
mrna_f = mrna.iloc[mrna_keep, :].copy()
mirna_f = mirna.iloc[mirna_keep, :].copy()

if mrna_f.shape != (15083, 72):
    raise RuntimeError(f"MRNA_FILTERED_SHAPE_WRONG observed={mrna_f.shape}")
if mirna_f.shape != (428, 72):
    raise RuntimeError(f"MIRNA_FILTERED_SHAPE_WRONG observed={mirna_f.shape}")

# Preserve raw fractional values; no rounding/coercion.
mrna_frac = int(np.sum(
    np.abs(mrna_f.to_numpy(dtype=np.float64)
           - np.round(mrna_f.to_numpy(dtype=np.float64))) > 1e-12
))
mirna_frac = int(np.sum(
    np.abs(mirna_f.to_numpy(dtype=np.float64)
           - np.round(mirna_f.to_numpy(dtype=np.float64))) > 1e-12
))

put("MRNA_FILTERED_ROWS", mrna_f.shape[0])
put("MIRNA_FILTERED_ROWS", mirna_f.shape[0])
put("FILTERED_SAMPLE_COUNT", mrna_f.shape[1])
put("MRNA_FILTERED_FRACTIONAL_VALUES", mrna_frac)
put("MIRNA_FILTERED_FRACTIONAL_VALUES", mirna_frac)

mrna_f.to_csv(MRNA_FILTERED, compression="gzip", float_format="%.17g")
mirna_f.to_csv(MIRNA_FILTERED, compression="gzip", float_format="%.17g")


# ------------------------------------------------------------
# C. Recompute post-filter library sizes, then TMM normalize
# ------------------------------------------------------------
def normalize_one(matrix, modality):
    x = matrix.to_numpy(dtype=np.float64)

    if np.any(~np.isfinite(x)):
        raise RuntimeError(f"{modality}_NONFINITE_FILTERED_COUNTS")
    if np.any(x < 0):
        raise RuntimeError(f"{modality}_NEGATIVE_FILTERED_COUNTS")

    lib = np.sum(x, axis=0, dtype=np.float64)
    if np.any(lib <= 0):
        raise RuntimeError(f"{modality}_NONPOSITIVE_FILTERED_LIBRARY")

    factors = edge_style_tmm(x, lib_size=lib)
    effective = lib * factors

    if np.any(~np.isfinite(factors)) or np.any(factors <= 0):
        raise RuntimeError(f"{modality}_INVALID_TMM_FACTORS")
    if np.any(~np.isfinite(effective)) or np.any(effective <= 0):
        raise RuntimeError(f"{modality}_INVALID_EFFECTIVE_LIBRARY")

    gm = float(np.exp(np.mean(np.log(factors))))
    if abs(gm - 1.0) > 1e-12:
        raise RuntimeError(
            f"{modality}_TMM_FACTOR_GEOMEAN_NOT_ONE observed={gm}"
        )

    # Standard normalized CPM using effective library sizes.
    cpm = x / effective[np.newaxis, :] * 1e6

    # edgeR-style logCPM for descriptive QC, prior.count=2:
    # y0_j = prior.count * L_j / median(L)
    # log2((y + y0)/(L + 2*y0) * 1e6)
    prior = 2.0
    y0 = prior * effective / np.median(effective)
    logcpm = np.log2(
        (x + y0[np.newaxis, :])
        / (effective[np.newaxis, :] + 2.0 * y0[np.newaxis, :])
        * 1e6
    )

    if np.any(~np.isfinite(cpm)) or np.any(~np.isfinite(logcpm)):
        raise RuntimeError(f"{modality}_NONFINITE_NORMALIZED_OUTPUT")

    return lib, factors, effective, cpm, logcpm, gm


mrna_lib, mrna_nf, mrna_eff, mrna_cpm, mrna_log, mrna_gm = normalize_one(
    mrna_f, "mRNA"
)
mirna_lib, mirna_nf, mirna_eff, mirna_cpm, mirna_log, mirna_gm = normalize_one(
    mirna_f, "miRNA"
)

put("MRNA_TMM_FACTOR_GEOMEAN", mrna_gm)
put("MIRNA_TMM_FACTOR_GEOMEAN", mirna_gm)
put("MRNA_TMM_FACTOR_MIN", float(np.min(mrna_nf)))
put("MRNA_TMM_FACTOR_MAX", float(np.max(mrna_nf)))
put("MIRNA_TMM_FACTOR_MIN", float(np.min(mirna_nf)))
put("MIRNA_TMM_FACTOR_MAX", float(np.max(mirna_nf)))

norm_rows = []
for i, subject in enumerate(subjects):
    norm_rows.append({
        "subject_id": subject,
        "disease_state": disease[i],
        "modality": "mRNA",
        "post_filter_raw_library_size": float(mrna_lib[i]),
        "tmm_norm_factor": float(mrna_nf[i]),
        "effective_library_size": float(mrna_eff[i]),
        "included_in_analysis": "YES",
    })
    norm_rows.append({
        "subject_id": subject,
        "disease_state": disease[i],
        "modality": "miRNA_mature_median_primary",
        "post_filter_raw_library_size": float(mirna_lib[i]),
        "tmm_norm_factor": float(mirna_nf[i]),
        "effective_library_size": float(mirna_eff[i]),
        "included_in_analysis": "YES",
    })

pd.DataFrame(norm_rows).to_csv(NORM_TABLE, index=False)

mrna_cpm_df = pd.DataFrame(mrna_cpm, index=mrna_f.index, columns=subjects)
mirna_cpm_df = pd.DataFrame(mirna_cpm, index=mirna_f.index, columns=subjects)
mrna_log_df = pd.DataFrame(mrna_log, index=mrna_f.index, columns=subjects)
mirna_log_df = pd.DataFrame(mirna_log, index=mirna_f.index, columns=subjects)

for df, idxname in (
    (mrna_cpm_df, mrna_f.index.name),
    (mirna_cpm_df, mirna_f.index.name),
    (mrna_log_df, mrna_f.index.name),
    (mirna_log_df, mirna_f.index.name),
):
    df.index.name = idxname

mrna_cpm_df.to_csv(MRNA_CPM, compression="gzip", float_format="%.17g")
mirna_cpm_df.to_csv(MIRNA_CPM, compression="gzip", float_format="%.17g")
mrna_log_df.to_csv(MRNA_LOGCPM, compression="gzip", float_format="%.17g")
mirna_log_df.to_csv(MIRNA_LOGCPM, compression="gzip", float_format="%.17g")


# ------------------------------------------------------------
# D. PCA/sample-structure QC — review only
# ------------------------------------------------------------
def robust_modified_z(values):
    values = np.asarray(values, dtype=np.float64)
    med = float(np.median(values))
    mad = float(np.median(np.abs(values - med)))

    if mad == 0:
        return np.zeros(values.size, dtype=np.float64)

    return 0.6744897501960817 * (values - med) / mad


def pca_qc(log_df, modality, png_path):
    X = log_df.T.to_numpy(dtype=np.float64)

    # PCA centers features; do not variance-scale genes.
    ncomp = min(10, X.shape[0] - 1, X.shape[1])
    pca = PCA(n_components=ncomp, svd_solver="full")
    scores = pca.fit_transform(X)

    score_rows = []
    for i, subject in enumerate(subjects):
        row = {
            "subject_id": subject,
            "disease_state": disease[i],
            "modality": modality,
        }
        for k in range(ncomp):
            row[f"PC{k+1}"] = float(scores[i, k])
        score_rows.append(row)

    var_rows = []
    for k in range(ncomp):
        var_rows.append({
            "modality": modality,
            "principal_component": f"PC{k+1}",
            "explained_variance_ratio": float(
                pca.explained_variance_ratio_[k]
            ),
        })

    # Review-only distance from within-disease centroid using first 5 PCs.
    use_k = min(5, ncomp)
    distances = np.zeros(len(subjects), dtype=np.float64)
    within_z = np.zeros(len(subjects), dtype=np.float64)

    disease_arr = np.asarray(disease, dtype=object)

    for group in sorted(set(disease)):
        idx = np.where(disease_arr == group)[0]
        group_scores = scores[idx, :use_k]
        centroid = np.mean(group_scores, axis=0)
        d = np.sqrt(np.sum((group_scores - centroid) ** 2, axis=1))
        distances[idx] = d
        within_z[idx] = robust_modified_z(d)

    structure_rows = []
    d3a_flagged = set(
        qc_review.loc[
            qc_review["qc_review_flag"].astype(str).eq("REVIEW"),
            "subject_id",
        ].astype(str)
    )

    for i, subject in enumerate(subjects):
        pca_review = abs(float(within_z[i])) >= 3.5
        d3a_review = subject in d3a_flagged

        structure_rows.append({
            "subject_id": subject,
            "disease_state": disease[i],
            "modality": modality,
            "distance_to_within_disease_centroid_PC1_to_PC5": float(distances[i]),
            "within_disease_distance_modified_z": float(within_z[i]),
            "pca_structure_review_flag": "REVIEW" if pca_review else "NO",
            "d3a_library_qc_review_flag": "REVIEW" if d3a_review else "NO",
            "sample_exclusion_authorized": "NO",
            "sample_included": "YES",
        })

    # One-panel PCA plot. Group markers differ; matplotlib chooses colors.
    marker_map = {"COVID19": "o", "SEPSIS": "s", "HEALTHY": "^"}

    plt.figure(figsize=(9, 7))
    for group in ["COVID19", "SEPSIS", "HEALTHY"]:
        idx = np.where(disease_arr == group)[0]
        plt.scatter(
            scores[idx, 0],
            scores[idx, 1],
            label=group,
            marker=marker_map[group],
            alpha=0.8,
        )

    # Label only D3A review subjects to avoid clutter.
    for i, subject in enumerate(subjects):
        if subject in d3a_flagged:
            plt.annotate(
                subject,
                (scores[i, 0], scores[i, 1]),
                xytext=(4, 4),
                textcoords="offset points",
                fontsize=8,
            )

    plt.xlabel(
        f"PC1 ({pca.explained_variance_ratio_[0]*100:.2f}% variance)"
    )
    plt.ylabel(
        f"PC2 ({pca.explained_variance_ratio_[1]*100:.2f}% variance)"
    )
    plt.title(f"{modality} — TMM logCPM sample structure")
    plt.legend()
    plt.tight_layout()
    plt.savefig(png_path, dpi=180)
    plt.close()

    return score_rows, var_rows, structure_rows


score_rows = []
variance_rows = []
structure_rows = []

for log_df, modality, png in (
    (mrna_log_df, "mRNA", MRNA_PCA_PNG),
    (mirna_log_df, "miRNA_mature_median_primary", MIRNA_PCA_PNG),
):
    s, v, r = pca_qc(log_df, modality, png)
    score_rows.extend(s)
    variance_rows.extend(v)
    structure_rows.extend(r)

scores_df = pd.DataFrame(score_rows)
variance_df = pd.DataFrame(variance_rows)
structure_df = pd.DataFrame(structure_rows)

scores_df.to_csv(PCA_SCORES, index=False)
variance_df.to_csv(PCA_VARIANCE, index=False)
structure_df.to_csv(STRUCTURE_REVIEW, index=False)

pca_review_subjects = sorted(set(
    structure_df.loc[
        structure_df["pca_structure_review_flag"].eq("REVIEW"),
        "subject_id",
    ].astype(str)
))

combined_review_subjects = sorted(set(
    structure_df.loc[
        structure_df["pca_structure_review_flag"].eq("REVIEW")
        | structure_df["d3a_library_qc_review_flag"].eq("REVIEW"),
        "subject_id",
    ].astype(str)
))

put("PCA_STRUCTURE_REVIEW_SUBJECTS", len(pca_review_subjects))
put(
    "PCA_STRUCTURE_REVIEW_SUBJECT_IDS",
    "|".join(pca_review_subjects) if pca_review_subjects else "NONE",
)
put("COMBINED_QC_REVIEW_SUBJECTS", len(combined_review_subjects))
put(
    "COMBINED_QC_REVIEW_SUBJECT_IDS",
    "|".join(combined_review_subjects) if combined_review_subjects else "NONE",
)


# ------------------------------------------------------------
# E. Hard safety / integrity gates
# ------------------------------------------------------------
# Round-trip filtered raw matrices exactly.
for path, original, expected_shape in (
    (MRNA_FILTERED, mrna_f, (15083, 72)),
    (MIRNA_FILTERED, mirna_f, (428, 72)),
):
    rt = pd.read_csv(
        path,
        index_col=0,
        compression="gzip",
        engine="c",
        float_precision="round_trip",
    )

    if rt.shape != expected_shape:
        raise RuntimeError(
            f"FILTERED_RAW_ROUNDTRIP_SHAPE_MISMATCH file={path.name}"
        )

    if list(rt.index.astype(str)) != list(original.index.astype(str)):
        raise RuntimeError(
            f"FILTERED_RAW_ROUNDTRIP_INDEX_MISMATCH file={path.name}"
        )

    if list(rt.columns) != subjects:
        raise RuntimeError(
            f"FILTERED_RAW_ROUNDTRIP_SAMPLE_MISMATCH file={path.name}"
        )

    if not np.array_equal(
        rt.to_numpy(dtype=np.float64),
        original.to_numpy(dtype=np.float64),
    ):
        raise RuntimeError(
            f"FILTERED_RAW_ROUNDTRIP_VALUE_MISMATCH file={path.name}"
        )

if set(subjects) != set(metadata["subject_id"].astype(str)):
    raise RuntimeError("SUBJECT_SET_CHANGED")

if len(subjects) != 72:
    raise RuntimeError("SAMPLE_COUNT_NOT_72")

put("FILTERED_RAW_MATRIX_ROUNDTRIP_INTEGRITY", "PASS")
put("ALL_72_SAMPLES_RETAINED", "YES")
put("D3A_REVIEW_SUBJECTS_H24_P25_RETAINED", "YES")
put("SAMPLE_EXCLUSION_EXECUTED", "NO")
put("SAMPLE_EXCLUSION_AUTHORIZED", "NO")
put("DE_EXECUTED", "NO")
put("READY_FOR_D3C_SAMPLE_STRUCTURE_REVIEW", "YES")
put("NEXT_PHASE", "D3C_SAMPLE_STRUCTURE_REVIEW_AND_ANALYSIS_COHORT_FREEZE")

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
    $Metadata,
    $MrnaRaw,
    $MirnaRawPrimary,
    $MrnaMask,
    $MirnaMask,
    $D3AQcReview,
    $D2E4ValidationPy,
    $MrnaFiltered,
    $MirnaFiltered,
    $NormTable,
    $MrnaCpm,
    $MirnaCpm,
    $MrnaLogCpm,
    $MirnaLogCpm,
    $PcaScores,
    $PcaVariance,
    $StructureReview,
    $MrnaPcaPng,
    $MirnaPcaPng,
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
        Write-Host '=== D3B PYTHON STDERR ==='
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
    throw ('D3B_PYTHON_FAILED exit={0} full_traceback={1}' -f $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D3B_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('TMM_VALIDATED_SOURCE_FUNCTION_EXTRACTION','PASS'),
    @('TMM_PRODUCTION_TOY_SELF_TEST','PASS'),
    @('MRNA_FILTERED_ROWS','15083'),
    @('MIRNA_FILTERED_ROWS','428'),
    @('FILTERED_SAMPLE_COUNT','72'),
    @('FILTERED_RAW_MATRIX_ROUNDTRIP_INTEGRITY','PASS'),
    @('ALL_72_SAMPLES_RETAINED','YES'),
    @('D3A_REVIEW_SUBJECTS_H24_P25_RETAINED','YES'),
    @('SAMPLE_EXCLUSION_EXECUTED','NO'),
    @('SAMPLE_EXCLUSION_AUTHORIZED','NO'),
    @('DE_EXECUTED','NO'),
    @('READY_FOR_D3C_SAMPLE_STRUCTURE_REVIEW','YES'),
    @('NEXT_PHASE','D3C_SAMPLE_STRUCTURE_REVIEW_AND_ANALYSIS_COHORT_FREEZE')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D3B_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 4. Decision
# ------------------------------------------------------------
@(
    'GSE243219_D3B_DECISION',
    'PHASE_D3B_STATUS=PASS',
    'MODE=FILTER_NORMALIZE_AND_DESCRIPTIVE_SAMPLE_QC',
    'D2E_V4_CERTIFICATION_GATE=PASS',
    'D2E_V4_OUTPUTS_RECERTIFIED=6/6',
    'D3A_CERTIFICATION_GATE=PASS',
    'D3A_OUTPUTS_RECERTIFIED=12/12',
    'FEATURE_FILTER_APPLICATION_EXECUTED=YES',
    'FILTER_METHOD=FROZEN_D3A_EDGER_FILTERBYEXPR_SPECIFICATION',
    'MRNA_INPUT_FEATURES=26364',
    'MRNA_FILTERED_FEATURES=15083',
    'MIRNA_INPUT_FEATURES=2656',
    'MIRNA_FILTERED_FEATURES=428',
    'POST_FILTER_LIBRARY_SIZES_RECOMPUTED=YES',
    'TMM_NORMALIZATION_EXECUTED=YES',
    'TMM_IMPLEMENTATION_SOURCE=D2E_V4_VALIDATED_EDGE_STYLE_FUNCTION',
    'TMM_VALIDATED_SOURCE_FUNCTION_EXTRACTION=PASS',
    'TMM_PRODUCTION_TOY_SELF_TEST=PASS',
    'EFFECTIVE_LIBRARY_SIZE_FORMULA=POST_FILTER_LIBRARY_SIZE_X_TMM_NORM_FACTOR',
    'NORMALIZED_CPM_CREATED=YES',
    'LOGCPM_QC_MATRIX_CREATED=YES',
    'LOGCPM_PRIOR_COUNT=2',
    'LOGCPM_USE=QC_ONLY_NOT_DE_INPUT',
    'SAMPLE_STRUCTURE_PCA_EXECUTED=YES',
    ('PCA_STRUCTURE_REVIEW_SUBJECTS={0}' -f (Cap 'PCA_STRUCTURE_REVIEW_SUBJECTS')),
    ('PCA_STRUCTURE_REVIEW_SUBJECT_IDS={0}' -f (Cap 'PCA_STRUCTURE_REVIEW_SUBJECT_IDS')),
    ('COMBINED_QC_REVIEW_SUBJECTS={0}' -f (Cap 'COMBINED_QC_REVIEW_SUBJECTS')),
    ('COMBINED_QC_REVIEW_SUBJECT_IDS={0}' -f (Cap 'COMBINED_QC_REVIEW_SUBJECT_IDS')),
    'ALL_72_SAMPLES_RETAINED=YES',
    'D3A_REVIEW_SUBJECTS_H24_P25_RETAINED=YES',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'SAMPLE_EXCLUSION_AUTHORIZED=NO',
    'MRNA_COUNT_ROUNDING_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D3C_SAMPLE_STRUCTURE_REVIEW=YES',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D3C_SAMPLE_STRUCTURE_REVIEW_AND_ANALYSIS_COHORT_FREEZE',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 5. Output manifest
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $MrnaFiltered,
    $MirnaFiltered,
    $NormTable,
    $MrnaCpm,
    $MirnaCpm,
    $MrnaLogCpm,
    $MirnaLogCpm,
    $PcaScores,
    $PcaVariance,
    $StructureReview,
    $MrnaPcaPng,
    $MirnaPcaPng,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D3B_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p

    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D3BSHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 6. Final summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D3B SUMMARY ===',
    'PHASE_D3B_STATUS=PASS',
    'MODE=FILTER_NORMALIZE_AND_DESCRIPTIVE_SAMPLE_QC',
    'D2E_V4_CERTIFICATION_GATE=PASS',
    'D2E_V4_OUTPUTS_RECERTIFIED=6/6',
    'D3A_CERTIFICATION_GATE=PASS',
    'D3A_OUTPUTS_RECERTIFIED=12/12',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    ('SKLEARN_VERSION={0}' -f $SklearnVersion),
    'FEATURE_FILTER_APPLICATION_EXECUTED=YES',
    'FILTER_METHOD=FROZEN_D3A_EDGER_FILTERBYEXPR_SPECIFICATION',
    'MRNA_INPUT_FEATURES=26364',
    'MRNA_FILTERED_FEATURES=15083',
    ('MRNA_FILTERED_FRACTIONAL_VALUES={0}' -f (Cap 'MRNA_FILTERED_FRACTIONAL_VALUES')),
    'MIRNA_INPUT_FEATURES=2656',
    'MIRNA_FILTERED_FEATURES=428',
    ('MIRNA_FILTERED_FRACTIONAL_VALUES={0}' -f (Cap 'MIRNA_FILTERED_FRACTIONAL_VALUES')),
    'FILTERED_SAMPLE_COUNT=72',
    'FILTERED_RAW_MATRIX_ROUNDTRIP_INTEGRITY=PASS',
    'POST_FILTER_LIBRARY_SIZES_RECOMPUTED=YES',
    'TMM_NORMALIZATION_EXECUTED=YES',
    'TMM_IMPLEMENTATION_SOURCE=D2E_V4_VALIDATED_EDGE_STYLE_FUNCTION',
    'TMM_VALIDATED_SOURCE_FUNCTION_EXTRACTION=PASS',
    'TMM_PRODUCTION_TOY_SELF_TEST=PASS',
    ('TMM_PRODUCTION_TOY_MAX_ABS_DIFF={0}' -f (Cap 'TMM_PRODUCTION_TOY_MAX_ABS_DIFF')),
    ('MRNA_TMM_FACTOR_GEOMEAN={0}' -f (Cap 'MRNA_TMM_FACTOR_GEOMEAN')),
    ('MRNA_TMM_FACTOR_MIN={0}' -f (Cap 'MRNA_TMM_FACTOR_MIN')),
    ('MRNA_TMM_FACTOR_MAX={0}' -f (Cap 'MRNA_TMM_FACTOR_MAX')),
    ('MIRNA_TMM_FACTOR_GEOMEAN={0}' -f (Cap 'MIRNA_TMM_FACTOR_GEOMEAN')),
    ('MIRNA_TMM_FACTOR_MIN={0}' -f (Cap 'MIRNA_TMM_FACTOR_MIN')),
    ('MIRNA_TMM_FACTOR_MAX={0}' -f (Cap 'MIRNA_TMM_FACTOR_MAX')),
    'EFFECTIVE_LIBRARY_SIZE_FORMULA=POST_FILTER_LIBRARY_SIZE_X_TMM_NORM_FACTOR',
    'NORMALIZED_CPM_CREATED=YES',
    'LOGCPM_QC_MATRIX_CREATED=YES',
    'LOGCPM_PRIOR_COUNT=2',
    'LOGCPM_USE=QC_ONLY_NOT_DE_INPUT',
    'SAMPLE_STRUCTURE_PCA_EXECUTED=YES',
    ('PCA_STRUCTURE_REVIEW_SUBJECTS={0}' -f (Cap 'PCA_STRUCTURE_REVIEW_SUBJECTS')),
    ('PCA_STRUCTURE_REVIEW_SUBJECT_IDS={0}' -f (Cap 'PCA_STRUCTURE_REVIEW_SUBJECT_IDS')),
    ('COMBINED_QC_REVIEW_SUBJECTS={0}' -f (Cap 'COMBINED_QC_REVIEW_SUBJECTS')),
    ('COMBINED_QC_REVIEW_SUBJECT_IDS={0}' -f (Cap 'COMBINED_QC_REVIEW_SUBJECT_IDS')),
    'ALL_72_SAMPLES_RETAINED=YES',
    'D3A_REVIEW_SUBJECTS_H24_P25_RETAINED=YES',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'SAMPLE_EXCLUSION_AUTHORIZED=NO',
    'MRNA_COUNT_ROUNDING_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D3C_SAMPLE_STRUCTURE_REVIEW=YES',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D3C_SAMPLE_STRUCTURE_REVIEW_AND_ANALYSIS_COHORT_FREEZE',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D3B_MRNA_FILTERED_RAW={0}' -f $MrnaFiltered)
Write-Host ('D3B_MIRNA_FILTERED_RAW={0}' -f $MirnaFiltered)
Write-Host ('D3B_TMM_NORMALIZATION_TABLE={0}' -f $NormTable)
Write-Host ('D3B_MRNA_NORMALIZED_CPM={0}' -f $MrnaCpm)
Write-Host ('D3B_MIRNA_NORMALIZED_CPM={0}' -f $MirnaCpm)
Write-Host ('D3B_MRNA_LOGCPM_QC={0}' -f $MrnaLogCpm)
Write-Host ('D3B_MIRNA_LOGCPM_QC={0}' -f $MirnaLogCpm)
Write-Host ('D3B_PCA_SCORES={0}' -f $PcaScores)
Write-Host ('D3B_PCA_VARIANCE={0}' -f $PcaVariance)
Write-Host ('D3B_SAMPLE_STRUCTURE_REVIEW={0}' -f $StructureReview)
Write-Host ('D3B_MRNA_PCA_PNG={0}' -f $MrnaPcaPng)
Write-Host ('D3B_MIRNA_PCA_PNG={0}' -f $MirnaPcaPng)
Write-Host ('D3B_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D3B_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D3B=PASS'
Write-Host 'STOP=YES'
