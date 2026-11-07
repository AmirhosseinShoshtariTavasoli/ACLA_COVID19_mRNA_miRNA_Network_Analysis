$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D7B-V2 — BOOTSTRAP STABILITY EXECUTION
#
# Inputs:
#   - certified D7A full-data candidate associations: 11,576
#   - certified D3B TMM-normalized CPM matrices
#   - certified D7-V2 50-subject COV/H paired cohort
#
# Frozen D7-V2 stability rule:
#   candidate must already satisfy:
#       full-data BH FDR <= 0.05
#       AND abs(full-data partial Spearman rho) >= 0.30
#
#   then execute:
#       500 paired subject-level stratified bootstraps
#       seed = 243219
#       35 COVID draws + 15 HEALTHY draws per replicate
#       sampling WITH replacement within disease group
#       same subject draw applied to mRNA and miRNA
#
# Bootstrap statistic:
#   partial Spearman controlling disease status
#
# Bootstrap selection/support event:
#   bootstrap rho has SAME SIGN as full-data rho
#   AND abs(bootstrap rho) >= 0.30
#
# Stable edge:
#   bootstrap selection frequency >= 0.80
#   over ALL 500 replicates.
#
# Undefined bootstrap rho handling:
#   - if a resample produces zero residual rank variance for one
#     member of a pair, that replicate yields NA rho for that pair
#   - NA contributes NO support in the 500-replicate denominator
#   - finite-frequency is reported explicitly
#   - quantiles/median use finite bootstrap rho values only
#
# Additional descriptive annotations on final stable edges:
#   - COVID-only Spearman, n=35
#   - HEALTHY-only Spearman, n=15
#   These are descriptive only and cannot delete stable edges.
#
# D7B DOES NOT:
#   - alter full-data D7A results
#   - recompute BH FDR
#   - integrate target evidence
#   - infer regulatory direction
#   - construct the biological network
#   - execute A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'

$D3Root = Join-Path $Project '03_QC_AND_FILTERING'
$D6Root = Join-Path $Project '06_ASSOCIATION_AND_STABILITY'

$D3BRun = Join-Path $D3Root 'D3B_FILTER_TMM_SAMPLE_QC_20260905_092809'
$D3BManifest = Join-Path $D3BRun 'D3B_OUTPUT_SHA256_MANIFEST.csv'
$MrnaCpm = Join-Path $D3BRun 'D3B_MRNA_TMM_NORMALIZED_CPM_15083x72.csv.gz'
$MirnaCpm = Join-Path $D3BRun 'D3B_MIRNA_TMM_NORMALIZED_CPM_428x72.csv.gz'

$D7Run = Join-Path $D6Root 'D7_V2_ASSOCIATION_STABILITY_PREFLIGHT_20260905_104708'
$D7Manifest = Join-Path $D7Run 'D7_OUTPUT_SHA256_MANIFEST.csv'
$D7Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D7_V2_20260905_104708\PHASE_D7_SUMMARY.txt'
$AssocCohort = Join-Path $D7Run 'D7_PRIMARY_ASSOCIATION_COHORT_50.csv'
$FrozenDesign = Join-Path $D7Run 'D7_FROZEN_ASSOCIATION_AND_STABILITY_DESIGN.txt'

$D7ARun = Join-Path $D6Root 'D7A_PRIMARY_ASSOCIATION_EXECUTION_20260905_105352'
$D7AManifest = Join-Path $D7ARun 'D7A_OUTPUT_SHA256_MANIFEST.csv'
$D7AReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D7A_20260905_105352\PHASE_D7A_SUMMARY.txt'
$AllAssociations = Join-Path $D7ARun 'D7A_ALL_348705_PRIMARY_ASSOCIATIONS.csv.gz'
$CandidateAssociations = Join-Path $D7ARun 'D7A_FULL_DATA_ASSOCIATION_CANDIDATES.csv.gz'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D6Root ('D7B_V2_BOOTSTRAP_STABILITY_EXECUTION_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D7B_V2_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D7B_V2_BOOTSTRAP_STABILITY_EXECUTION.py'
$BootstrapAuditNpz = Join-Path $RunDir 'D7B_BOOTSTRAP_RHO_AND_DRAW_AUDIT_500x11576.npz'
$BootstrapDirectAudit = Join-Path $RunDir 'D7B_BOOTSTRAP_DIRECT_PAIR_AUDIT.csv'
$CandidateStability = Join-Path $RunDir 'D7B_ALL_11576_CANDIDATE_STABILITY.csv.gz'
$StableEdges = Join-Path $RunDir 'D7B_STABLE_ASSOCIATION_EDGES.csv.gz'
$StabilitySummary = Join-Path $RunDir 'D7B_STABILITY_SUMMARY.csv'
$ExecutionSpec = Join-Path $RunDir 'D7B_V2_BOOTSTRAP_EXECUTION_SPECIFICATION.txt'
$ResultJson = Join-Path $RunDir 'D7B_RESULT.json'

$PythonStdout = Join-Path $RunDir 'D7B_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D7B_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D7B_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D7B_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D7B_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D7B_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D7B — BOOTSTRAP STABILITY EXECUTION ==='
Write-Host 'MODE=FROZEN_BOOTSTRAP_STABILITY_EXECUTION'
Write-Host 'FULL_DATA_CANDIDATES=11576'
Write-Host 'FULL_DATA_POSITIVE_CANDIDATES=5255'
Write-Host 'FULL_DATA_NEGATIVE_CANDIDATES=6321'
Write-Host 'BOOTSTRAP_AUTHORIZED=YES'
Write-Host 'BOOTSTRAP_EXECUTED_AT_START=NO'
Write-Host 'BOOTSTRAP_REPLICATES=500'
Write-Host 'BOOTSTRAP_RANDOM_SEED=243219'
Write-Host 'BOOTSTRAP_STRATIFIED_BY_DISEASE=YES'
Write-Host 'BOOTSTRAP_COVID_DRAWS=35'
Write-Host 'BOOTSTRAP_HEALTHY_DRAWS=15'
Write-Host 'BOOTSTRAP_WITH_REPLACEMENT=YES'
Write-Host 'BOOTSTRAP_PAIRED_MRNA_MIRNA_DRAW=YES'
Write-Host 'BOOTSTRAP_SUPPORT_EVENT=SAME_SIGN_AND_ABS_RHO_GE_0.30'
Write-Host 'STABLE_EDGE_FREQUENCY_THRESHOLD=0.80'
Write-Host 'UNDEFINED_BOOTSTRAP_RHO_SUPPORT=NO'
Write-Host 'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $D3BManifest,$MrnaCpm,$MirnaCpm,
    $D7Manifest,$D7Report,$AssocCohort,$FrozenDesign,
    $D7AManifest,$D7AReport,$AllAssociations,$CandidateAssociations
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D7B_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D7BSHA256 {
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
        $hash = Get-D7BSHA256 $r.full_path

        if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
            $hash -ne $r.SHA256.ToLowerInvariant()) {
            throw ('{0}_OUTPUT_CHANGED={1}' -f $Label,$r.full_path)
        }
    }

    Write-Host ('{0}_OUTPUTS_RECERTIFIED={1}/{1}' -f $Label,$ExpectedRows)
}

# ------------------------------------------------------------
# 1. Re-certify frozen upstream inputs
# ------------------------------------------------------------
Recertify-Manifest -ManifestPath $D3BManifest -ExpectedRows 18 -Label 'D3B'
Write-Host 'D3B_EXPRESSION_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D7Manifest -ExpectedRows 10 -Label 'D7_V2'
Write-Host 'D7_V2_DESIGN_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D7AManifest -ExpectedRows 11 -Label 'D7A'
Write-Host 'D7A_ASSOCIATION_CERTIFICATION_GATE=PASS'

$d7 = Get-Content -LiteralPath $D7Report -Raw

# The D7 summary is used only for phase-level certification.
# Exact bootstrap parameters are certified from the hash-recertified
# frozen-design artifact below. This avoids false-negative dependence
# on presentation-only summary formatting.
foreach ($tok in @(
    'PHASE_D7_V2_STATUS=PASS',
    'PRIMARY_ASSOCIATION_SUBJECTS=50',
    'PRIMARY_ASSOCIATION_COVID19=35',
    'PRIMARY_ASSOCIATION_HEALTHY=15',
    'PRIMARY_ASSOCIATION_STATISTIC=PARTIAL_SPEARMAN_CONTROL_DISEASE_STATUS',
    'ASSOCIATION_DESIGN_FROZEN=YES',
    'REAL_ASSOCIATION_EXECUTED=NO',
    'READY_FOR_D7A_PRIMARY_ASSOCIATION_EXECUTION=YES'
)) {
    if (-not $d7.Contains($tok)) {
        throw ('D7_V2_PHASE_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$d7Frozen = Get-Content -LiteralPath $FrozenDesign -Raw

foreach ($tok in @(
    'GSE243219_D7_FROZEN_ASSOCIATION_AND_STABILITY_DESIGN',
    'PRIMARY_ASSOCIATION_COHORT_SUBJECTS=50',
    'PRIMARY_ASSOCIATION_COHORT_COVID19=35',
    'PRIMARY_ASSOCIATION_COHORT_HEALTHY=15',
    'PRIMARY_ASSOCIATION_MRNA_FEATURES=8505',
    'PRIMARY_ASSOCIATION_MIRNA_FEATURES=41',
    'PRIMARY_ASSOCIATION_PAIR_COUNT=348705',
    'ASSOCIATION_STATISTIC=PARTIAL_SPEARMAN',
    'PARTIAL_SPEARMAN_CONTROL_VARIABLE=COVID19_BINARY_DISEASE_STATUS',
    'FULL_DATA_ASSOCIATION_FDR_THRESHOLD=0.05',
    'FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD=0.30',
    'FULL_DATA_ASSOCIATION_CANDIDATE_RULE=FDR_LE_0.05_AND_ABS_RHO_GE_0.30',
    'BOOTSTRAP_SCOPE=FULL_DATA_ASSOCIATION_CANDIDATES_ONLY',
    'BOOTSTRAP_REPLICATES=500',
    'BOOTSTRAP_RANDOM_SEED=243219',
    'BOOTSTRAP_RESAMPLING_UNIT=PAIRED_SUBJECT',
    'BOOTSTRAP_WITH_REPLACEMENT=YES',
    'BOOTSTRAP_STRATIFIED_BY_DISEASE=YES',
    'BOOTSTRAP_COVID_DRAWS_PER_REPLICATE=35',
    'BOOTSTRAP_HEALTHY_DRAWS_PER_REPLICATE=15',
    'BOOTSTRAP_MRNA_MIRNA_USE_IDENTICAL_SUBJECT_DRAW=YES',
    'BOOTSTRAP_SELECTION_EVENT=SAME_SIGN_AND_ABS_RHO_GE_0.30',
    'STABLE_EDGE_BOOTSTRAP_FREQUENCY_THRESHOLD=0.80',
    'POSITIVE_ASSOCIATIONS_RETAINED=YES',
    'NEGATIVE_ASSOCIATIONS_RETAINED=YES',
    'CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO',
    'WITHIN_GROUP_SPEARMAN_CAN_DELETE_PRIMARY_STABLE_EDGE=NO'
)) {
    if (-not $d7Frozen.Contains($tok)) {
        throw ('D7_V2_FROZEN_DESIGN_TOKEN_MISSING={0}' -f $tok)
    }
}

Write-Host 'D7_V2_PHASE_SUMMARY_CERTIFICATION=PASS'
Write-Host 'D7_V2_FROZEN_BOOTSTRAP_DESIGN_CERTIFICATION=PASS'
$D7PhaseSummaryCertified = $true
$D7FrozenBootstrapDesignCertified = $true

$d7a = Get-Content -LiteralPath $D7AReport -Raw
foreach ($tok in @(
    'PHASE_D7A_STATUS=PASS',
    'PRIMARY_ASSOCIATION_PAIR_COUNT=348705',
    'FULL_DATA_ASSOCIATION_FDR_THRESHOLD=0.05',
    'FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD=0.30',
    'PAIRS_FDR_LE_0_05=11576',
    'FULL_DATA_ASSOCIATION_CANDIDATES=11576',
    'FULL_DATA_POSITIVE_CANDIDATES=5255',
    'FULL_DATA_NEGATIVE_CANDIDATES=6321',
    'VECTORIZED_DIRECT_PAIR_AUDIT=PASS',
    'ALL_348705_ASSOCIATION_ROWS_SAVED=YES',
    'ALL_ASSOCIATION_ROUNDTRIP_INTEGRITY=PASS',
    'READY_FOR_D7B_BOOTSTRAP_STABILITY_EXECUTION=YES'
)) {
    if ($d7a -notmatch [regex]::Escape($tok)) {
        throw ('D7A_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$PythonExe = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING\D2D_PREFLIGHT_20260904_195001\venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw ('PYTHON_EXECUTABLE_MISSING={0}' -f $PythonExe)
}

$PythonVersion = & $PythonExe -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$PandasVersion = & $PythonExe -c "import pandas; print(pandas.__version__)"
$NumpyVersion = & $PythonExe -c "import numpy; print(numpy.__version__)"
$ScipyVersion = & $PythonExe -c "import scipy; print(scipy.__version__)"

Write-Host ('PYTHON_VERSION={0}' -f $PythonVersion)
Write-Host ('PANDAS_VERSION={0}' -f $PandasVersion)
Write-Host ('NUMPY_VERSION={0}' -f $NumpyVersion)
Write-Host ('SCIPY_VERSION={0}' -f $ScipyVersion)

if (-not $D7PhaseSummaryCertified) {
    throw 'D7_V2_PHASE_SUMMARY_CERTIFICATION_NOT_REACHED'
}
if (-not $D7FrozenBootstrapDesignCertified) {
    throw 'D7_V2_FROZEN_BOOTSTRAP_DESIGN_CERTIFICATION_NOT_REACHED'
}

# ------------------------------------------------------------
# 2. Python D7B bootstrap execution
# ------------------------------------------------------------
$PythonCode = @'
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import rankdata


MRNA_CPM = Path(sys.argv[1])
MIRNA_CPM = Path(sys.argv[2])
ASSOC_COHORT = Path(sys.argv[3])
ALL_ASSOC = Path(sys.argv[4])
CAND_ASSOC = Path(sys.argv[5])

BOOT_AUDIT_NPZ = Path(sys.argv[6])
BOOT_DIRECT_AUDIT = Path(sys.argv[7])
CAND_STABILITY = Path(sys.argv[8])
STABLE_EDGES = Path(sys.argv[9])
STABILITY_SUMMARY = Path(sys.argv[10])
EXECUTION_SPEC = Path(sys.argv[11])
RESULT_JSON = Path(sys.argv[12])


N_BOOT = 500
SEED = 243219
RHO_THRESHOLD = 0.30
STABILITY_THRESHOLD = 0.80
N_CAND = 11576

results = {}


def put(k, v):
    results[k] = v
    print(f"{k}={v}")


def rank_rows(x):
    return rankdata(
        np.asarray(x, dtype=np.float64),
        method="average",
        axis=1,
    ).astype(np.float64)


def residualize_by_binary_group_means(ranks, n_cov=35, n_h=15):
    """
    Exact residualization for design [intercept, binary group]
    when bootstrap order is [35 COVID draws, 15 HEALTHY draws].
    This is algebraically equivalent to OLS residualization:
    subtract the mean rank within each disease group.
    """
    r = np.asarray(ranks, dtype=np.float64).copy()

    cov_mean = np.mean(r[:, :n_cov], axis=1, keepdims=True)
    h_mean = np.mean(r[:, n_cov:n_cov+n_h], axis=1, keepdims=True)

    r[:, :n_cov] -= cov_mean
    r[:, n_cov:n_cov+n_h] -= h_mean

    return r


def normalize_rows_allow_zero(resid):
    r = np.asarray(resid, dtype=np.float64)
    norms = np.sqrt(np.sum(r * r, axis=1))

    unit = np.full_like(r, np.nan, dtype=np.float64)

    good = np.isfinite(norms) & (norms > 1e-14)
    unit[good, :] = r[good, :] / norms[good, None]

    return unit, good, norms


def direct_bootstrap_partial_spearman(x, y):
    rx = rankdata(np.asarray(x, dtype=np.float64), method="average")
    ry = rankdata(np.asarray(y, dtype=np.float64), method="average")

    # bootstrap order is fixed:
    # first 35 COVID, then 15 HEALTHY
    rx[:35] -= np.mean(rx[:35])
    rx[35:] -= np.mean(rx[35:])

    ry[:35] -= np.mean(ry[:35])
    ry[35:] -= np.mean(ry[35:])

    nx = float(np.sqrt(np.sum(rx * rx)))
    ny = float(np.sqrt(np.sum(ry * ry)))

    if nx <= 1e-14 or ny <= 1e-14:
        return np.nan

    return float(
        np.clip(np.sum(rx * ry) / (nx * ny), -1.0, 1.0)
    )


def plain_spearman(x, y):
    rx = rankdata(np.asarray(x, dtype=np.float64), method="average")
    ry = rankdata(np.asarray(y, dtype=np.float64), method="average")

    rx = rx - np.mean(rx)
    ry = ry - np.mean(ry)

    nx = float(np.sqrt(np.sum(rx * rx)))
    ny = float(np.sqrt(np.sum(ry * ry)))

    if nx <= 1e-14 or ny <= 1e-14:
        return np.nan

    return float(
        np.clip(np.sum(rx * ry) / (nx * ny), -1.0, 1.0)
    )


# ------------------------------------------------------------
# A. Load and certify exact inputs
# ------------------------------------------------------------
mrna = pd.read_csv(
    MRNA_CPM,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
mirna = pd.read_csv(
    MIRNA_CPM,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
cohort = pd.read_csv(ASSOC_COHORT)

all_assoc = pd.read_csv(
    ALL_ASSOC,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
cand = pd.read_csv(
    CAND_ASSOC,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)

if mrna.shape != (15083,72):
    raise RuntimeError(f"MRNA_CPM_SHAPE_CHANGED observed={mrna.shape}")
if mirna.shape != (428,72):
    raise RuntimeError(f"MIRNA_CPM_SHAPE_CHANGED observed={mirna.shape}")
if cohort.shape[0] != 50:
    raise RuntimeError(
        f"ASSOCIATION_COHORT_ROWS_CHANGED observed={cohort.shape[0]}"
    )
if all_assoc.shape[0] != 348705:
    raise RuntimeError(
        f"ALL_ASSOCIATION_ROWS_CHANGED observed={all_assoc.shape[0]}"
    )
if cand.shape[0] != N_CAND:
    raise RuntimeError(
        f"CANDIDATE_ROWS_CHANGED observed={cand.shape[0]}"
    )

if cohort["disease_state"].value_counts().to_dict() != {
    "COVID19":35,
    "HEALTHY":15,
}:
    raise RuntimeError("ASSOCIATION_COHORT_GROUP_COUNTS_CHANGED")

subjects = cohort["subject_id"].astype(str).tolist()

if len(subjects) != len(set(subjects)):
    raise RuntimeError("ASSOCIATION_COHORT_SUBJECTS_NOT_UNIQUE")

required_cand = {
    "pair_index_1based",
    "mRNA_id",
    "miRNA_id",
    "partial_spearman_rho",
    "PValue",
    "FDR",
    "association_sign",
}
missing = sorted(required_cand - set(cand.columns))
if missing:
    raise RuntimeError(f"CANDIDATE_COLUMNS_MISSING={missing}")

full_rho = cand["partial_spearman_rho"].to_numpy(dtype=np.float64)
full_fdr = cand["FDR"].to_numpy(dtype=np.float64)

if np.any(~np.isfinite(full_rho)):
    raise RuntimeError("CANDIDATE_FULL_RHO_NONFINITE")
if np.any(~np.isfinite(full_fdr)):
    raise RuntimeError("CANDIDATE_FULL_FDR_NONFINITE")

if np.any(full_fdr > 0.05 + 1e-15):
    raise RuntimeError("CANDIDATE_CONTAINS_FDR_GT_0.05")
if np.any(np.abs(full_rho) < 0.30 - 1e-15):
    raise RuntimeError("CANDIDATE_CONTAINS_ABS_RHO_LT_0.30")

if int(np.sum(full_rho > 0)) != 5255:
    raise RuntimeError(
        f"POSITIVE_CANDIDATE_COUNT_CHANGED observed={int(np.sum(full_rho>0))}"
    )
if int(np.sum(full_rho < 0)) != 6321:
    raise RuntimeError(
        f"NEGATIVE_CANDIDATE_COUNT_CHANGED observed={int(np.sum(full_rho<0))}"
    )

# Verify candidate rows are exact subset of the full table by pair index.
pair_idx0 = cand["pair_index_1based"].to_numpy(dtype=np.int64) - 1

if np.any(pair_idx0 < 0) or np.any(pair_idx0 >= 348705):
    raise RuntimeError("CANDIDATE_PAIR_INDEX_OUT_OF_RANGE")

all_subset = all_assoc.iloc[pair_idx0, :]

if all_subset["pair_index_1based"].to_numpy(dtype=np.int64).tolist() != \
   cand["pair_index_1based"].to_numpy(dtype=np.int64).tolist():
    raise RuntimeError("CANDIDATE_PAIR_INDEX_MAPPING_CHANGED")

for col in ["mRNA_id","miRNA_id"]:
    if all_subset[col].astype(str).tolist() != cand[col].astype(str).tolist():
        raise RuntimeError(f"CANDIDATE_SUBSET_ID_MISMATCH column={col}")

if not np.allclose(
    all_subset["partial_spearman_rho"].to_numpy(dtype=np.float64),
    full_rho,
    rtol=0.0,
    atol=1e-15,
):
    raise RuntimeError("CANDIDATE_FULL_RHO_MISMATCH_TO_ALL_TABLE")

put("D7B_INPUT_INTEGRITY", "PASS")
put("D7A_CANDIDATE_SUBSET_RECERTIFIED", "PASS")


# ------------------------------------------------------------
# B. Candidate feature extraction and mapping
# ------------------------------------------------------------
cand_mrna_ids = cand["mRNA_id"].astype(str).tolist()
cand_mirna_ids = cand["miRNA_id"].astype(str).tolist()

unique_mrna_ids = list(dict.fromkeys(cand_mrna_ids))
unique_mirna_ids = list(dict.fromkeys(cand_mirna_ids))

missing_m = sorted(set(unique_mrna_ids) - set(mrna.index.astype(str)))
missing_mi = sorted(set(unique_mirna_ids) - set(mirna.index.astype(str)))

if missing_m:
    raise RuntimeError(
        f"CANDIDATE_MRNA_MISSING_FROM_CPM count={len(missing_m)}"
    )
if missing_mi:
    raise RuntimeError(
        f"CANDIDATE_MIRNA_MISSING_FROM_CPM count={len(missing_mi)}"
    )

m_expr = mrna.loc[unique_mrna_ids, subjects].to_numpy(dtype=np.float64)
mi_expr = mirna.loc[unique_mirna_ids, subjects].to_numpy(dtype=np.float64)

if np.any(~np.isfinite(m_expr)):
    raise RuntimeError("CANDIDATE_MRNA_EXPRESSION_NONFINITE")
if np.any(~np.isfinite(mi_expr)):
    raise RuntimeError("CANDIDATE_MIRNA_EXPRESSION_NONFINITE")

m_map = {fid:i for i,fid in enumerate(unique_mrna_ids)}
mi_map = {fid:i for i,fid in enumerate(unique_mirna_ids)}

cand_m_idx = np.fromiter(
    (m_map[x] for x in cand_mrna_ids),
    dtype=np.int64,
    count=N_CAND,
)
cand_mi_idx = np.fromiter(
    (mi_map[x] for x in cand_mirna_ids),
    dtype=np.int64,
    count=N_CAND,
)

put("BOOTSTRAP_UNIQUE_MRNA_FEATURES", len(unique_mrna_ids))
put("BOOTSTRAP_UNIQUE_MIRNA_FEATURES", len(unique_mirna_ids))


# ------------------------------------------------------------
# C. Build exact deterministic stratified paired draws
# ------------------------------------------------------------
g = cohort["disease_indicator_COVID19"].to_numpy(dtype=np.int64)

cov_idx = np.where(g == 1)[0]
h_idx = np.where(g == 0)[0]

if cov_idx.size != 35 or h_idx.size != 15:
    raise RuntimeError(
        f"ASSOCIATION_COHORT_INDEX_COUNTS_CHANGED "
        f"cov={cov_idx.size} healthy={h_idx.size}"
    )

rng = np.random.default_rng(SEED)

draws = np.empty((N_BOOT,50), dtype=np.int16)

for b in range(N_BOOT):
    cov_draw = rng.choice(cov_idx, size=35, replace=True)
    h_draw = rng.choice(h_idx, size=15, replace=True)

    draws[b,:35] = cov_draw.astype(np.int16)
    draws[b,35:] = h_draw.astype(np.int16)

if np.any(draws[:,:35] < 0) or np.any(draws[:,:35] >= 50):
    raise RuntimeError("COVID_BOOTSTRAP_DRAW_OUT_OF_RANGE")
if np.any(draws[:,35:] < 0) or np.any(draws[:,35:] >= 50):
    raise RuntimeError("HEALTHY_BOOTSTRAP_DRAW_OUT_OF_RANGE")

if not np.all(g[draws[:,:35]] == 1):
    raise RuntimeError("COVID_BOOTSTRAP_STRATIFICATION_FAILED")
if not np.all(g[draws[:,35:]] == 0):
    raise RuntimeError("HEALTHY_BOOTSTRAP_STRATIFICATION_FAILED")

put("BOOTSTRAP_DRAW_MATRIX_CREATED", "YES")
put("BOOTSTRAP_DRAW_MATRIX_SHAPE", "500x50")
put("BOOTSTRAP_STRATIFICATION_AUDIT", "PASS")


# ------------------------------------------------------------
# D. Execute 500 paired stratified bootstraps
# ------------------------------------------------------------
boot_rho = np.full(
    (N_BOOT,N_CAND),
    np.nan,
    dtype=np.float64,
)

for b in range(N_BOOT):
    idx = draws[b,:].astype(np.int64)

    m_boot = m_expr[:, idx]
    mi_boot = mi_expr[:, idx]

    m_rank = rank_rows(m_boot)
    mi_rank = rank_rows(mi_boot)

    m_resid = residualize_by_binary_group_means(m_rank)
    mi_resid = residualize_by_binary_group_means(mi_rank)

    m_unit, m_good, _ = normalize_rows_allow_zero(m_resid)
    mi_unit, mi_good, _ = normalize_rows_allow_zero(mi_resid)

    good_pair = m_good[cand_m_idx] & mi_good[cand_mi_idx]

    rho_b = np.full(N_CAND, np.nan, dtype=np.float64)

    if np.any(good_pair):
        rho_b[good_pair] = np.sum(
            m_unit[cand_m_idx[good_pair], :]
            * mi_unit[cand_mi_idx[good_pair], :],
            axis=1,
        )
        rho_b[good_pair] = np.clip(
            rho_b[good_pair],
            -1.0,
            1.0,
        )

    boot_rho[b,:] = rho_b

    if (b + 1) % 50 == 0 or b == 0:
        print(f"BOOTSTRAP_PROGRESS={b+1}/{N_BOOT}", flush=True)

put("BOOTSTRAP_EXECUTED", "YES")
put("BOOTSTRAP_REPLICATES_COMPLETED", N_BOOT)


# ------------------------------------------------------------
# E. Save full bootstrap evidence before summaries
# ------------------------------------------------------------
np.savez_compressed(
    BOOT_AUDIT_NPZ,
    bootstrap_rho=boot_rho,
    draw_indices_0based=draws,
    candidate_pair_index_1based=
        cand["pair_index_1based"].to_numpy(dtype=np.int64),
    full_data_rho=full_rho,
    bootstrap_seed=np.array([SEED],dtype=np.int64),
)

with np.load(BOOT_AUDIT_NPZ, allow_pickle=False) as z:
    if z["bootstrap_rho"].shape != (N_BOOT,N_CAND):
        raise RuntimeError(
            f"BOOTSTRAP_NPZ_RHO_SHAPE_WRONG "
            f"observed={z['bootstrap_rho'].shape}"
        )
    if z["draw_indices_0based"].shape != (N_BOOT,50):
        raise RuntimeError(
            f"BOOTSTRAP_NPZ_DRAW_SHAPE_WRONG "
            f"observed={z['draw_indices_0based'].shape}"
        )

    if not np.array_equal(
        z["draw_indices_0based"],
        draws,
    ):
        raise RuntimeError("BOOTSTRAP_NPZ_DRAW_ROUNDTRIP_MISMATCH")

    if not np.allclose(
        z["bootstrap_rho"],
        boot_rho,
        rtol=0.0,
        atol=0.0,
        equal_nan=True,
    ):
        raise RuntimeError("BOOTSTRAP_NPZ_RHO_ROUNDTRIP_MISMATCH")

put("BOOTSTRAP_FULL_EVIDENCE_SAVED", "YES")
put("BOOTSTRAP_NPZ_ROUNDTRIP_INTEGRITY", "PASS")


# ------------------------------------------------------------
# F. Direct-vs-vectorized bootstrap audit
# ------------------------------------------------------------
audit_rng = np.random.default_rng(7243219)

audit_boot = audit_rng.choice(
    N_BOOT,
    size=16,
    replace=False,
)
audit_pair = audit_rng.choice(
    N_CAND,
    size=32,
    replace=False,
)

audit_rows = []
max_diff = 0.0

for b in audit_boot:
    idx = draws[b,:].astype(np.int64)

    # audit two independently selected pairs per chosen replicate
    pair_choices = audit_rng.choice(
        audit_pair,
        size=2,
        replace=False,
    )

    for pidx in pair_choices:
        x = m_expr[cand_m_idx[pidx], idx]
        y = mi_expr[cand_mi_idx[pidx], idx]

        direct = direct_bootstrap_partial_spearman(x,y)
        vectorized = float(boot_rho[b,pidx])

        if np.isnan(direct) and np.isnan(vectorized):
            diff = 0.0
            status = "PASS"
        elif np.isfinite(direct) and np.isfinite(vectorized):
            diff = abs(direct - vectorized)
            status = "PASS" if diff <= 1e-12 else "FAIL"
        else:
            diff = np.inf
            status = "FAIL"

        max_diff = max(max_diff, diff)

        audit_rows.append({
            "bootstrap_replicate_1based": int(b+1),
            "candidate_row_1based": int(pidx+1),
            "pair_index_1based": int(
                cand.iloc[pidx]["pair_index_1based"]
            ),
            "mRNA_id": cand_mrna_ids[pidx],
            "miRNA_id": cand_mirna_ids[pidx],
            "vectorized_bootstrap_rho": vectorized,
            "direct_bootstrap_rho": direct,
            "abs_difference": diff,
            "status": status,
        })

audit_df = pd.DataFrame(audit_rows)

if audit_df.shape[0] != 32:
    raise RuntimeError(
        f"BOOTSTRAP_DIRECT_AUDIT_ROWS_WRONG observed={audit_df.shape[0]}"
    )
if not audit_df["status"].eq("PASS").all():
    raise RuntimeError(
        f"BOOTSTRAP_DIRECT_AUDIT_FAILED maxdiff={max_diff}"
    )

audit_df.to_csv(BOOT_DIRECT_AUDIT,index=False)

put("BOOTSTRAP_DIRECT_PAIR_AUDIT", "PASS")
put("BOOTSTRAP_DIRECT_PAIR_AUDIT_ROWS", 32)
put("BOOTSTRAP_DIRECT_PAIR_RHO_MAX_ABS_DIFF", float(max_diff))


# ------------------------------------------------------------
# G. Candidate-level stability summaries
# ------------------------------------------------------------
finite = np.isfinite(boot_rho)
finite_count = np.sum(finite, axis=0)

full_sign = np.sign(full_rho)[None,:]
boot_sign = np.sign(boot_rho)

same_sign = finite & (boot_sign == full_sign)

support = (
    same_sign
    & (np.abs(boot_rho) >= RHO_THRESHOLD)
)

support_count = np.sum(support, axis=0)
same_sign_count = np.sum(same_sign, axis=0)

selection_frequency = support_count / float(N_BOOT)
finite_frequency = finite_count / float(N_BOOT)
same_sign_frequency_all = same_sign_count / float(N_BOOT)

same_sign_frequency_finite = np.divide(
    same_sign_count,
    finite_count,
    out=np.zeros_like(
        same_sign_count,
        dtype=np.float64,
    ),
    where=finite_count > 0,
)

# Finite-only distribution summaries.
median_rho = np.full(N_CAND,np.nan,dtype=np.float64)
p025_rho = np.full(N_CAND,np.nan,dtype=np.float64)
p975_rho = np.full(N_CAND,np.nan,dtype=np.float64)

for j in range(N_CAND):
    vals = boot_rho[:,j]
    vals = vals[np.isfinite(vals)]

    if vals.size > 0:
        median_rho[j] = float(np.median(vals))
        p025_rho[j] = float(np.quantile(vals,0.025))
        p975_rho[j] = float(np.quantile(vals,0.975))

stable = selection_frequency >= STABILITY_THRESHOLD

cand_stab = cand.copy()

cand_stab["bootstrap_replicates"] = N_BOOT
cand_stab["bootstrap_finite_rho_count"] = finite_count
cand_stab["bootstrap_finite_rho_frequency"] = finite_frequency
cand_stab["bootstrap_same_sign_count"] = same_sign_count
cand_stab["bootstrap_same_sign_frequency_all_500"] = same_sign_frequency_all
cand_stab["bootstrap_same_sign_frequency_among_finite"] = same_sign_frequency_finite
cand_stab["bootstrap_support_count_same_sign_abs_rho_ge_0_30"] = support_count
cand_stab["bootstrap_selection_frequency"] = selection_frequency
cand_stab["bootstrap_median_rho"] = median_rho
cand_stab["bootstrap_rho_p2_5"] = p025_rho
cand_stab["bootstrap_rho_p97_5"] = p975_rho
cand_stab["stable_edge_frequency_ge_0_80"] = np.where(
    stable,
    "YES",
    "NO",
)
cand_stab["undefined_bootstrap_rho_counts_as_support"] = "NO"
cand_stab["correlation_sign_establishes_regulatory_direction"] = "NO"

cand_stab.to_csv(
    CAND_STABILITY,
    index=False,
    compression="gzip",
    float_format="%.17g",
)

put("ALL_11576_CANDIDATE_STABILITY_ROWS_SAVED", "YES")


# ------------------------------------------------------------
# H. Stable-edge descriptive within-group Spearman
# ------------------------------------------------------------
stable_df = cand_stab.loc[stable].copy()

n_stable = int(stable_df.shape[0])
n_stable_pos = int(
    np.sum(
        stable_df["partial_spearman_rho"].to_numpy(dtype=np.float64) > 0
    )
)
n_stable_neg = int(
    np.sum(
        stable_df["partial_spearman_rho"].to_numpy(dtype=np.float64) < 0
    )
)

# Compute annotations only for stable edges.
if n_stable > 0:
    stable_m_ids = stable_df["mRNA_id"].astype(str).tolist()
    stable_mi_ids = stable_df["miRNA_id"].astype(str).tolist()

    # Original 50-subject association cohort order.
    cov_orig = np.where(g == 1)[0]
    h_orig = np.where(g == 0)[0]

    stable_cov_rho = np.empty(n_stable,dtype=np.float64)
    stable_h_rho = np.empty(n_stable,dtype=np.float64)

    for i,(mid,miid) in enumerate(zip(stable_m_ids,stable_mi_ids)):
        mx = mrna.loc[mid, subjects].to_numpy(dtype=np.float64)
        my = mirna.loc[miid, subjects].to_numpy(dtype=np.float64)

        stable_cov_rho[i] = plain_spearman(
            mx[cov_orig],
            my[cov_orig],
        )
        stable_h_rho[i] = plain_spearman(
            mx[h_orig],
            my[h_orig],
        )

    stable_df["COVID_only_Spearman_rho_n35"] = stable_cov_rho
    stable_df["HEALTHY_only_Spearman_rho_n15"] = stable_h_rho
    stable_df["within_group_Spearman_role"] = "DESCRIPTIVE_ANNOTATION_ONLY"
    stable_df["within_group_Spearman_can_delete_stable_edge"] = "NO"
else:
    stable_df["COVID_only_Spearman_rho_n35"] = pd.Series(dtype=float)
    stable_df["HEALTHY_only_Spearman_rho_n15"] = pd.Series(dtype=float)
    stable_df["within_group_Spearman_role"] = pd.Series(dtype=str)
    stable_df["within_group_Spearman_can_delete_stable_edge"] = pd.Series(dtype=str)

stable_df.to_csv(
    STABLE_EDGES,
    index=False,
    compression="gzip",
    float_format="%.17g",
)

put("STABLE_ASSOCIATION_EDGES", n_stable)
put("STABLE_POSITIVE_ASSOCIATION_EDGES", n_stable_pos)
put("STABLE_NEGATIVE_ASSOCIATION_EDGES", n_stable_neg)


# ------------------------------------------------------------
# I. Summary metrics
# ------------------------------------------------------------
undefined_any = np.any(~finite, axis=0)
n_any_undefined = int(np.sum(undefined_any))
n_total_undefined = int(np.sum(~finite))

summary_rows = [
    {
        "metric":"full_data_candidates_input",
        "count":N_CAND,
        "fraction":1.0,
    },
    {
        "metric":"stable_edges_selection_frequency_ge_0.80",
        "count":n_stable,
        "fraction":float(n_stable/N_CAND),
    },
    {
        "metric":"stable_positive_edges",
        "count":n_stable_pos,
        "fraction":float(n_stable_pos/N_CAND),
    },
    {
        "metric":"stable_negative_edges",
        "count":n_stable_neg,
        "fraction":float(n_stable_neg/N_CAND),
    },
    {
        "metric":"candidate_edges_with_any_undefined_bootstrap_rho",
        "count":n_any_undefined,
        "fraction":float(n_any_undefined/N_CAND),
    },
    {
        "metric":"undefined_bootstrap_pair_replicates",
        "count":n_total_undefined,
        "fraction":float(n_total_undefined/(N_CAND*N_BOOT)),
    },
]

pd.DataFrame(summary_rows).to_csv(
    STABILITY_SUMMARY,
    index=False,
)

put("CANDIDATES_WITH_ANY_UNDEFINED_BOOTSTRAP_RHO", n_any_undefined)
put("TOTAL_UNDEFINED_BOOTSTRAP_PAIR_REPLICATES", n_total_undefined)
put("MIN_BOOTSTRAP_SELECTION_FREQUENCY", float(np.min(selection_frequency)))
put("MEDIAN_BOOTSTRAP_SELECTION_FREQUENCY", float(np.median(selection_frequency)))
put("MAX_BOOTSTRAP_SELECTION_FREQUENCY", float(np.max(selection_frequency)))


# ------------------------------------------------------------
# J. Freeze execution specification
# ------------------------------------------------------------
spec_lines = [
    "GSE243219_D7B_BOOTSTRAP_STABILITY_EXECUTION_SPECIFICATION",
    "FULL_DATA_CANDIDATES_INPUT=11576",
    "FULL_DATA_POSITIVE_CANDIDATES=5255",
    "FULL_DATA_NEGATIVE_CANDIDATES=6321",
    "BOOTSTRAP_REPLICATES=500",
    "BOOTSTRAP_RANDOM_SEED=243219",
    "BOOTSTRAP_RESAMPLING_UNIT=PAIRED_SUBJECT",
    "BOOTSTRAP_STRATIFIED_BY_DISEASE=YES",
    "BOOTSTRAP_WITH_REPLACEMENT=YES",
    "BOOTSTRAP_COVID_DRAWS_PER_REPLICATE=35",
    "BOOTSTRAP_HEALTHY_DRAWS_PER_REPLICATE=15",
    "BOOTSTRAP_MRNA_MIRNA_USE_IDENTICAL_SUBJECT_DRAW=YES",
    "BOOTSTRAP_STATISTIC=PARTIAL_SPEARMAN_CONTROL_DISEASE_STATUS",
    "BOOTSTRAP_RANK_METHOD=AVERAGE_TIES",
    "BOOTSTRAP_RESIDUALIZATION=SUBTRACT_WITHIN_DISEASE_MEAN_RANK_EQUIVALENT_TO_OLS_INTERCEPT_PLUS_BINARY_GROUP",
    "BOOTSTRAP_SUPPORT_EVENT=SAME_SIGN_AS_FULL_DATA_AND_ABS_RHO_GE_0.30",
    "STABLE_EDGE_BOOTSTRAP_FREQUENCY_THRESHOLD=0.80",
    "STABILITY_DENOMINATOR=ALL_500_REPLICATES",
    "UNDEFINED_BOOTSTRAP_RHO_COUNTS_AS_SUPPORT=NO",
    "BOOTSTRAP_MEDIAN_AND_QUANTILES=FINITE_RHO_ONLY",
    "BOOTSTRAP_FULL_RHO_MATRIX_SAVED=YES",
    "BOOTSTRAP_DRAW_INDEX_MATRIX_SAVED=YES",
    "COVID_ONLY_SPEARMAN_ROLE=DESCRIPTIVE_ANNOTATION_ON_STABLE_EDGES",
    "HEALTHY_ONLY_SPEARMAN_ROLE=DESCRIPTIVE_ANNOTATION_ON_STABLE_EDGES",
    "WITHIN_GROUP_SPEARMAN_CAN_DELETE_STABLE_EDGE=NO",
    "POSITIVE_ASSOCIATIONS_RETAINED=YES",
    "NEGATIVE_ASSOCIATIONS_RETAINED=YES",
    "CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO",
    "TARGET_EVIDENCE_INTEGRATION_EXECUTED_IN_D7B=NO",
    "NETWORK_EXECUTED_IN_D7B=NO",
    "ACLA_EXECUTED_IN_D7B=NO",
]
EXECUTION_SPEC.write_text(
    "\n".join(spec_lines) + "\n",
    encoding="utf-8",
)

put("BOOTSTRAP_STABILITY_EXECUTION_COMPLETE", "YES")
put("TARGET_EVIDENCE_INTEGRATION_EXECUTED", "NO")
put("NETWORK_EXECUTED", "NO")
put("ACLA_EXECUTED", "NO")
put("READY_FOR_D7C_ASSOCIATION_STABILITY_AUDIT_AND_EDGE_FREEZE", "YES")
put("NEXT_PHASE", "D7C_ASSOCIATION_STABILITY_AUDIT_AND_EDGE_FREEZE")

RESULT_JSON.write_text(
    json.dumps({"results":results},indent=2,sort_keys=True),
    encoding="utf-8",
)
'@

$PythonCode | Set-Content -LiteralPath $PyScript -Encoding UTF8

$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

$PythonArgs = @(
    '-u',
    $PyScript,
    $MrnaCpm,
    $MirnaCpm,
    $AssocCohort,
    $AllAssociations,
    $CandidateAssociations,
    $BootstrapAuditNpz,
    $BootstrapDirectAudit,
    $CandidateStability,
    $StableEdges,
    $StabilitySummary,
    $ExecutionSpec,
    $ResultJson
)

$proc = Start-Process `
    -FilePath $PythonExe `
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
        Write-Host '=== D7B PYTHON STDERR ==='
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
    throw ('D7B_PYTHON_FAILED exit={0} full_traceback={1}' -f `
        $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D7B_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('D7B_INPUT_INTEGRITY','PASS'),
    @('D7A_CANDIDATE_SUBSET_RECERTIFIED','PASS'),
    @('BOOTSTRAP_DRAW_MATRIX_CREATED','YES'),
    @('BOOTSTRAP_DRAW_MATRIX_SHAPE','500x50'),
    @('BOOTSTRAP_STRATIFICATION_AUDIT','PASS'),
    @('BOOTSTRAP_EXECUTED','YES'),
    @('BOOTSTRAP_REPLICATES_COMPLETED','500'),
    @('BOOTSTRAP_FULL_EVIDENCE_SAVED','YES'),
    @('BOOTSTRAP_NPZ_ROUNDTRIP_INTEGRITY','PASS'),
    @('BOOTSTRAP_DIRECT_PAIR_AUDIT','PASS'),
    @('BOOTSTRAP_DIRECT_PAIR_AUDIT_ROWS','32'),
    @('ALL_11576_CANDIDATE_STABILITY_ROWS_SAVED','YES'),
    @('BOOTSTRAP_STABILITY_EXECUTION_COMPLETE','YES'),
    @('TARGET_EVIDENCE_INTEGRATION_EXECUTED','NO'),
    @('NETWORK_EXECUTED','NO'),
    @('ACLA_EXECUTED','NO'),
    @('READY_FOR_D7C_ASSOCIATION_STABILITY_AUDIT_AND_EDGE_FREEZE','YES'),
    @('NEXT_PHASE','D7C_ASSOCIATION_STABILITY_AUDIT_AND_EDGE_FREEZE')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D7B_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 3. Decision
# ------------------------------------------------------------
@(
    'GSE243219_D7B_V2_DECISION',
    'PHASE_D7B_V2_STATUS=PASS',
    'MODE=FROZEN_BOOTSTRAP_STABILITY_EXECUTION',
    'D3B_EXPRESSION_CERTIFICATION_GATE=PASS',
    'D3B_OUTPUTS_RECERTIFIED=18/18',
    'D7_V2_DESIGN_CERTIFICATION_GATE=PASS',
    'D7B_V2_CORRECTION=BOOTSTRAP_RULES_CERTIFIED_FROM_HASH_RECERTIFIED_FROZEN_DESIGN_ARTIFACT',
    'D7_V2_PHASE_SUMMARY_CERTIFICATION=PASS',
    'D7_V2_FROZEN_BOOTSTRAP_DESIGN_CERTIFICATION=PASS',
    'D7_V2_OUTPUTS_RECERTIFIED=10/10',
    'D7A_ASSOCIATION_CERTIFICATION_GATE=PASS',
    'D7A_OUTPUTS_RECERTIFIED=11/11',
    'FULL_DATA_CANDIDATES_INPUT=11576',
    'FULL_DATA_POSITIVE_CANDIDATES=5255',
    'FULL_DATA_NEGATIVE_CANDIDATES=6321',
    ('BOOTSTRAP_UNIQUE_MRNA_FEATURES={0}' -f (Cap 'BOOTSTRAP_UNIQUE_MRNA_FEATURES')),
    ('BOOTSTRAP_UNIQUE_MIRNA_FEATURES={0}' -f (Cap 'BOOTSTRAP_UNIQUE_MIRNA_FEATURES')),
    'BOOTSTRAP_REPLICATES=500',
    'BOOTSTRAP_RANDOM_SEED=243219',
    'BOOTSTRAP_STRATIFICATION_AUDIT=PASS',
    'BOOTSTRAP_EXECUTED=YES',
    'BOOTSTRAP_FULL_EVIDENCE_SAVED=YES',
    'BOOTSTRAP_NPZ_ROUNDTRIP_INTEGRITY=PASS',
    'BOOTSTRAP_DIRECT_PAIR_AUDIT=PASS',
    ('BOOTSTRAP_DIRECT_PAIR_RHO_MAX_ABS_DIFF={0}' -f (Cap 'BOOTSTRAP_DIRECT_PAIR_RHO_MAX_ABS_DIFF')),
    'BOOTSTRAP_SUPPORT_EVENT=SAME_SIGN_AND_ABS_RHO_GE_0.30',
    'STABLE_EDGE_FREQUENCY_THRESHOLD=0.80',
    'STABILITY_DENOMINATOR=ALL_500_REPLICATES',
    'UNDEFINED_BOOTSTRAP_RHO_SUPPORT=NO',
    ('CANDIDATES_WITH_ANY_UNDEFINED_BOOTSTRAP_RHO={0}' -f (Cap 'CANDIDATES_WITH_ANY_UNDEFINED_BOOTSTRAP_RHO')),
    ('TOTAL_UNDEFINED_BOOTSTRAP_PAIR_REPLICATES={0}' -f (Cap 'TOTAL_UNDEFINED_BOOTSTRAP_PAIR_REPLICATES')),
    ('STABLE_ASSOCIATION_EDGES={0}' -f (Cap 'STABLE_ASSOCIATION_EDGES')),
    ('STABLE_POSITIVE_ASSOCIATION_EDGES={0}' -f (Cap 'STABLE_POSITIVE_ASSOCIATION_EDGES')),
    ('STABLE_NEGATIVE_ASSOCIATION_EDGES={0}' -f (Cap 'STABLE_NEGATIVE_ASSOCIATION_EDGES')),
    ('MIN_BOOTSTRAP_SELECTION_FREQUENCY={0}' -f (Cap 'MIN_BOOTSTRAP_SELECTION_FREQUENCY')),
    ('MEDIAN_BOOTSTRAP_SELECTION_FREQUENCY={0}' -f (Cap 'MEDIAN_BOOTSTRAP_SELECTION_FREQUENCY')),
    ('MAX_BOOTSTRAP_SELECTION_FREQUENCY={0}' -f (Cap 'MAX_BOOTSTRAP_SELECTION_FREQUENCY')),
    'COVID_ONLY_SPEARMAN_ROLE=DESCRIPTIVE_ANNOTATION_ONLY',
    'HEALTHY_ONLY_SPEARMAN_ROLE=DESCRIPTIVE_ANNOTATION_ONLY',
    'CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO',
    'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D7C_ASSOCIATION_STABILITY_AUDIT_AND_EDGE_FREEZE=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D7C_ASSOCIATION_STABILITY_AUDIT_AND_EDGE_FREEZE',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Manifest
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $BootstrapAuditNpz,
    $BootstrapDirectAudit,
    $CandidateStability,
    $StableEdges,
    $StabilitySummary,
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
        throw ('D7B_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p

    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D7BSHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D7B-V2 SUMMARY ===',
    'PHASE_D7B_V2_STATUS=PASS',
    'MODE=FROZEN_BOOTSTRAP_STABILITY_EXECUTION',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    ('SCIPY_VERSION={0}' -f $ScipyVersion),
    'D3B_EXPRESSION_CERTIFICATION_GATE=PASS',
    'D7_V2_DESIGN_CERTIFICATION_GATE=PASS',
    'D7B_V2_CORRECTION=BOOTSTRAP_RULES_CERTIFIED_FROM_HASH_RECERTIFIED_FROZEN_DESIGN_ARTIFACT',
    'D7_V2_PHASE_SUMMARY_CERTIFICATION=PASS',
    'D7_V2_FROZEN_BOOTSTRAP_DESIGN_CERTIFICATION=PASS',
    'D7A_ASSOCIATION_CERTIFICATION_GATE=PASS',
    'FULL_DATA_CANDIDATES_INPUT=11576',
    'FULL_DATA_POSITIVE_CANDIDATES=5255',
    'FULL_DATA_NEGATIVE_CANDIDATES=6321',
    ('BOOTSTRAP_UNIQUE_MRNA_FEATURES={0}' -f (Cap 'BOOTSTRAP_UNIQUE_MRNA_FEATURES')),
    ('BOOTSTRAP_UNIQUE_MIRNA_FEATURES={0}' -f (Cap 'BOOTSTRAP_UNIQUE_MIRNA_FEATURES')),
    'BOOTSTRAP_REPLICATES=500',
    'BOOTSTRAP_RANDOM_SEED=243219',
    'BOOTSTRAP_STRATIFIED_BY_DISEASE=YES',
    'BOOTSTRAP_COVID_DRAWS=35',
    'BOOTSTRAP_HEALTHY_DRAWS=15',
    'BOOTSTRAP_WITH_REPLACEMENT=YES',
    'BOOTSTRAP_PAIRED_MRNA_MIRNA_DRAW=YES',
    'BOOTSTRAP_EXECUTED=YES',
    'BOOTSTRAP_FULL_EVIDENCE_SAVED=YES',
    'BOOTSTRAP_NPZ_ROUNDTRIP_INTEGRITY=PASS',
    'BOOTSTRAP_DIRECT_PAIR_AUDIT=PASS',
    ('BOOTSTRAP_DIRECT_PAIR_RHO_MAX_ABS_DIFF={0}' -f (Cap 'BOOTSTRAP_DIRECT_PAIR_RHO_MAX_ABS_DIFF')),
    'BOOTSTRAP_SUPPORT_EVENT=SAME_SIGN_AND_ABS_RHO_GE_0.30',
    'STABLE_EDGE_FREQUENCY_THRESHOLD=0.80',
    'STABILITY_DENOMINATOR=ALL_500_REPLICATES',
    'UNDEFINED_BOOTSTRAP_RHO_SUPPORT=NO',
    ('CANDIDATES_WITH_ANY_UNDEFINED_BOOTSTRAP_RHO={0}' -f (Cap 'CANDIDATES_WITH_ANY_UNDEFINED_BOOTSTRAP_RHO')),
    ('TOTAL_UNDEFINED_BOOTSTRAP_PAIR_REPLICATES={0}' -f (Cap 'TOTAL_UNDEFINED_BOOTSTRAP_PAIR_REPLICATES')),
    ('STABLE_ASSOCIATION_EDGES={0}' -f (Cap 'STABLE_ASSOCIATION_EDGES')),
    ('STABLE_POSITIVE_ASSOCIATION_EDGES={0}' -f (Cap 'STABLE_POSITIVE_ASSOCIATION_EDGES')),
    ('STABLE_NEGATIVE_ASSOCIATION_EDGES={0}' -f (Cap 'STABLE_NEGATIVE_ASSOCIATION_EDGES')),
    ('MIN_BOOTSTRAP_SELECTION_FREQUENCY={0}' -f (Cap 'MIN_BOOTSTRAP_SELECTION_FREQUENCY')),
    ('MEDIAN_BOOTSTRAP_SELECTION_FREQUENCY={0}' -f (Cap 'MEDIAN_BOOTSTRAP_SELECTION_FREQUENCY')),
    ('MAX_BOOTSTRAP_SELECTION_FREQUENCY={0}' -f (Cap 'MAX_BOOTSTRAP_SELECTION_FREQUENCY')),
    'COVID_ONLY_SPEARMAN_ROLE=DESCRIPTIVE_ANNOTATION_ONLY',
    'HEALTHY_ONLY_SPEARMAN_ROLE=DESCRIPTIVE_ANNOTATION_ONLY',
    'CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO',
    'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'BOOTSTRAP_STABILITY_EXECUTION_COMPLETE=YES',
    'READY_FOR_D7C_ASSOCIATION_STABILITY_AUDIT_AND_EDGE_FREEZE=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D7C_ASSOCIATION_STABILITY_AUDIT_AND_EDGE_FREEZE',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D7B_BOOTSTRAP_AUDIT_NPZ={0}' -f $BootstrapAuditNpz)
Write-Host ('D7B_BOOTSTRAP_DIRECT_AUDIT={0}' -f $BootstrapDirectAudit)
Write-Host ('D7B_CANDIDATE_STABILITY={0}' -f $CandidateStability)
Write-Host ('D7B_STABLE_EDGES={0}' -f $StableEdges)
Write-Host ('D7B_STABILITY_SUMMARY={0}' -f $StabilitySummary)
Write-Host ('D7B_EXECUTION_SPEC={0}' -f $ExecutionSpec)
Write-Host ('D7B_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D7B_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D7B_V2=PASS'
Write-Host 'STOP=YES'
