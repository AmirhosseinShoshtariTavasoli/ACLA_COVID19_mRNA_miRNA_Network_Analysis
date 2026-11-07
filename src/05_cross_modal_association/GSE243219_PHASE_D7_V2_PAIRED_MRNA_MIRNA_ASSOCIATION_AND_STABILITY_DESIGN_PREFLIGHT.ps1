$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D7-V2 — PAIRED mRNA-miRNA ASSOCIATION
#            + STABILITY DESIGN PREFLIGHT
#
# DESIGN/FREEZE ONLY.
# NO real mRNA-miRNA correlations are calculated in D7.
#
# Primary candidate universe (frozen in D6B):
#   mRNA  = 8,505 COV_vs_H BH-FDR <= 0.05
#   miRNA =    41 COV_vs_H BH-FDR <= 0.05
#   pairs = 348,705
#
# Primary association cohort:
#   COVID19 + HEALTHY only
#   35 COVID19 + 15 HEALTHY = 50 paired subjects
#
# Rationale:
#   Candidate features were selected on COVID-vs-healthy DE.
#   Naive pooled correlations can therefore be induced by the
#   disease-group mean shift itself.
#
# Frozen association statistic:
#   PARTIAL SPEARMAN controlling COV/H disease status:
#     1) take TMM-normalized CPM expression
#     2) rank-transform each feature across the same 50 subjects
#        using average ranks for ties
#     3) residualize each ranked feature against:
#          intercept + COVID19 indicator
#     4) Pearson correlation of residual rank vectors
#        = partial Spearman rho controlling disease group
#     5) two-sided t-test:
#          df = n - k - 2 = 50 - 1 - 2 = 47
#
# Multiple testing:
#   BH FDR across ALL 348,705 candidate mRNA-miRNA pairs.
#
# Full-data association candidate:
#   BH FDR <= 0.05
#   AND abs(partial Spearman rho) >= 0.30
#
# Bootstrap stability (performed later, NOT D7):
#   - only for full-data association candidates
#   - 500 paired subject-level stratified bootstraps
#   - preserve 35 COVID + 15 HEALTHY draws per replicate
#   - resample subjects WITH replacement within disease group
#   - identical sampled subject indices applied to mRNA and miRNA
#   - deterministic RNG seed 243219
#
# Stable association edge:
#   full-data FDR <= 0.05
#   AND abs(full-data rho) >= 0.30
#   AND bootstrap same-sign abs(rho)>=0.30 frequency >= 0.80
#
# Bootstrap summaries:
#   selection frequency
#   sign frequency
#   median rho
#   2.5th / 97.5th percentiles
#
# IMPORTANT:
#   - positive AND negative associations are retained
#   - correlation sign does NOT establish regulatory direction
#   - miRNA->mRNA direction must later come from target evidence
#   - negative correlation may be prioritized biologically but is
#     NOT required as an association-network gate
#
# Secondary descriptive annotations after stable-edge selection:
#   - COVID-only Spearman, n=35
#   - HEALTHY-only Spearman, n=15
#   These do NOT delete stable primary edges.
#
# Sepsis:
#   P_vs_H and COV_vs_P remain later specificity annotations.
#   Sepsis is NOT included in the primary COV/H association fit.
#
# Expression input:
#   D3B TMM-normalized CPM (not logCPM)
#   CPM is authorized for rank-based association only.
#   It remains prohibited as DE input.
#
# Prohibited in D7:
#   - real association execution
#   - p-values on real mRNA-miRNA pairs
#   - bootstrap execution
#   - network construction
#   - target evidence integration
#   - A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'

$D3Root = Join-Path $Project '03_QC_AND_FILTERING'
$D4Root = Join-Path $Project '04_NORMALIZATION'
$D5Root = Join-Path $Project '05_DIFFERENTIAL_EXPRESSION'
$D6Root = Join-Path $Project '06_ASSOCIATION_AND_STABILITY'

$D3BRun = Join-Path $D3Root 'D3B_FILTER_TMM_SAMPLE_QC_20260905_092809'
$D3BManifest = Join-Path $D3BRun 'D3B_OUTPUT_SHA256_MANIFEST.csv'
$MrnaCpm = Join-Path $D3BRun 'D3B_MRNA_TMM_NORMALIZED_CPM_15083x72.csv.gz'
$MirnaCpm = Join-Path $D3BRun 'D3B_MIRNA_TMM_NORMALIZED_CPM_428x72.csv.gz'

$D4Run = Join-Path $D4Root 'D4_DE_INPUT_BUNDLE_FREEZE_20260905_094110'
$D4Manifest = Join-Path $D4Run 'D4_OUTPUT_SHA256_MANIFEST.csv'
$Cohort = Join-Path $D4Run 'D4_FROZEN_ANALYSIS_COHORT_72.csv'

$D6BRun = Join-Path $D5Root 'D6B_SELECTION_FREEZE_20260905_103809'
$D6BManifest = Join-Path $D6BRun 'D6B_OUTPUT_SHA256_MANIFEST.csv'
$D6BReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D6B_20260905_103809\PHASE_D6B_SUMMARY.txt'
$MrnaCandidates = Join-Path $D6BRun 'D6B_MRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES.csv.gz'
$MirnaCandidates = Join-Path $D6BRun 'D6B_MIRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES.csv.gz'
$SelectionFreeze = Join-Path $D6BRun 'D6B_DOWNSTREAM_FEATURE_SELECTION_FREEZE.txt'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D6Root ('D7_V2_ASSOCIATION_STABILITY_PREFLIGHT_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D7_V2_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D7_V2_ASSOCIATION_AND_STABILITY_DESIGN_PREFLIGHT.py'
$SampleCohort = Join-Path $RunDir 'D7_PRIMARY_ASSOCIATION_COHORT_50.csv'
$FeatureUniverse = Join-Path $RunDir 'D7_PRIMARY_ASSOCIATION_FEATURE_UNIVERSE.csv'
$CapabilityAudit = Join-Path $RunDir 'D7_PARTIAL_SPEARMAN_CAPABILITY_PREFLIGHT.csv'
$FrozenDesign = Join-Path $RunDir 'D7_FROZEN_ASSOCIATION_AND_STABILITY_DESIGN.txt'
$ResultJson = Join-Path $RunDir 'D7_RESULT.json'

$PythonStdout = Join-Path $RunDir 'D7_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D7_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D7_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D7_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D7_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D7_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D7 — PAIRED mRNA-miRNA ASSOCIATION + STABILITY DESIGN PREFLIGHT ==='
Write-Host 'MODE=DESIGN_AND_CAPABILITY_PREFLIGHT_ONLY'
Write-Host 'PRIMARY_ASSOCIATION_COHORT=COV_PLUS_H'
Write-Host 'PRIMARY_ASSOCIATION_SUBJECTS=50'
Write-Host 'PRIMARY_ASSOCIATION_COVID19=35'
Write-Host 'PRIMARY_ASSOCIATION_HEALTHY=15'
Write-Host 'PRIMARY_ASSOCIATION_STATISTIC=PARTIAL_SPEARMAN_CONTROL_DISEASE_STATUS'
Write-Host 'MULTIPLE_TESTING=BH_ACROSS_ALL_348705_PRIMARY_PAIRS'
Write-Host 'FULL_DATA_EFFECT_THRESHOLD=ABS_RHO_GE_0.30'
Write-Host 'FULL_DATA_FDR_THRESHOLD=0.05'
Write-Host 'BOOTSTRAP_REPLICATES=500'
Write-Host 'BOOTSTRAP_STRATIFIED_BY_DISEASE=YES'
Write-Host 'BOOTSTRAP_SEED=243219'
Write-Host 'STABLE_EDGE_BOOTSTRAP_FREQUENCY_THRESHOLD=0.80'
Write-Host 'REAL_ASSOCIATION_EXECUTED=NO'
Write-Host 'REAL_ASSOCIATION_PVALUES_COMPUTED=NO'
Write-Host 'BOOTSTRAP_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $D3BManifest,$MrnaCpm,$MirnaCpm,
    $D4Manifest,$Cohort,
    $D6BManifest,$D6BReport,
    $MrnaCandidates,$MirnaCandidates,$SelectionFreeze
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D7_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D7SHA256 {
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
        $hash = Get-D7SHA256 $r.full_path

        if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
            $hash -ne $r.SHA256.ToLowerInvariant()) {
            throw ('{0}_OUTPUT_CHANGED={1}' -f $Label,$r.full_path)
        }
    }

    Write-Host ('{0}_OUTPUTS_RECERTIFIED={1}/{1}' -f $Label,$ExpectedRows)
}

# ------------------------------------------------------------
# 1. Re-certify upstream artifacts
# ------------------------------------------------------------
Recertify-Manifest -ManifestPath $D3BManifest -ExpectedRows 18 -Label 'D3B'
Write-Host 'D3B_EXPRESSION_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D4Manifest -ExpectedRows 14 -Label 'D4'
Write-Host 'D4_COHORT_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D6BManifest -ExpectedRows 11 -Label 'D6B'
Write-Host 'D6B_SELECTION_CERTIFICATION_GATE=PASS'

$d6b = Get-Content -LiteralPath $D6BReport -Raw
foreach ($tok in @(
    'PHASE_D6B_STATUS=PASS',
    'PRIMARY_MIRNA_AUTHORITY=MEDIAN_UNCHANGED',
    'PRIMARY_DOWNSTREAM_CONTRAST=COV_vs_H',
    'PRIMARY_DOWNSTREAM_SELECTION=BH_FDR_LE_0.05',
    'MRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES=8505',
    'MIRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES=41',
    'ASSOCIATION_INPUT_FEATURE_UNIVERSE_FROZEN=YES',
    'ASSOCIATION_INPUT_MRNA_FEATURES=8505',
    'ASSOCIATION_INPUT_MIRNA_FEATURES=41',
    'SEPSIS_CONTRASTS_USED_AS_DELETION_GATE=NO',
    'ABS_LOG2FC_GE_1_USED_AS_PRIMARY_ASSOCIATION_GATE=NO',
    'ASSOCIATION_EXECUTED=NO',
    'READY_FOR_D7_ASSOCIATION_AND_STABILITY_DESIGN_PREFLIGHT=YES'
)) {
    if ($d6b -notmatch [regex]::Escape($tok)) {
        throw ('D6B_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
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

# ------------------------------------------------------------
# 2. Python D7 design/capability preflight
# ------------------------------------------------------------
$PythonCode = @'
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import rankdata, t as student_t


MRNA_CPM = Path(sys.argv[1])
MIRNA_CPM = Path(sys.argv[2])
COHORT = Path(sys.argv[3])
MRNA_CANDIDATES = Path(sys.argv[4])
MIRNA_CANDIDATES = Path(sys.argv[5])

SAMPLE_COHORT = Path(sys.argv[6])
FEATURE_UNIVERSE = Path(sys.argv[7])
CAPABILITY_AUDIT = Path(sys.argv[8])
FROZEN_DESIGN = Path(sys.argv[9])
RESULT_JSON = Path(sys.argv[10])


results = {}


def put(k, v):
    results[k] = v
    print(f"{k}={v}")


def residualize_rank_vector(values, disease_indicator):
    values = np.asarray(values, dtype=np.float64)
    disease_indicator = np.asarray(disease_indicator, dtype=np.float64)

    ranks = rankdata(values, method="average").astype(np.float64)

    Z = np.column_stack([
        np.ones(values.size, dtype=np.float64),
        disease_indicator,
    ])

    beta, _, _, _ = np.linalg.lstsq(Z, ranks, rcond=None)
    residuals = ranks - Z @ beta

    return residuals


def partial_spearman_binary_group(x, y, disease_indicator):
    rx = residualize_rank_vector(x, disease_indicator)
    ry = residualize_rank_vector(y, disease_indicator)

    sx = float(np.sqrt(np.sum(rx * rx)))
    sy = float(np.sqrt(np.sum(ry * ry)))

    if sx == 0 or sy == 0:
        return np.nan, np.nan, 47

    rho = float(np.sum(rx * ry) / (sx * sy))
    rho = float(np.clip(rho, -1.0, 1.0))

    n = len(x)
    k = 1
    df = n - k - 2

    if abs(rho) >= 1.0:
        p = 0.0
    else:
        stat = rho * np.sqrt(df / (1.0 - rho * rho))
        p = float(2.0 * student_t.sf(abs(stat), df=df))

    return rho, p, df


# ------------------------------------------------------------
# A. Read certified expression matrices and candidate universes
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
cohort = pd.read_csv(COHORT)

m_candidates = pd.read_csv(MRNA_CANDIDATES, compression="gzip")
mi_candidates = pd.read_csv(MIRNA_CANDIDATES, compression="gzip")

if mrna.shape != (15083, 72):
    raise RuntimeError(f"MRNA_CPM_SHAPE_CHANGED observed={mrna.shape}")
if mirna.shape != (428, 72):
    raise RuntimeError(f"MIRNA_CPM_SHAPE_CHANGED observed={mirna.shape}")
if cohort.shape[0] != 72:
    raise RuntimeError(f"COHORT_ROWS_CHANGED observed={cohort.shape[0]}")
if m_candidates.shape[0] != 8505:
    raise RuntimeError(
        f"MRNA_CANDIDATE_ROWS_CHANGED observed={m_candidates.shape[0]}"
    )
if mi_candidates.shape[0] != 41:
    raise RuntimeError(
        f"MIRNA_CANDIDATE_ROWS_CHANGED observed={mi_candidates.shape[0]}"
    )

subjects = cohort["subject_id"].astype(str).tolist()
groups = cohort["disease_state"].astype(str).tolist()

if list(mrna.columns) != subjects:
    raise RuntimeError("MRNA_CPM_SAMPLE_ORDER_CHANGED")
if list(mirna.columns) != subjects:
    raise RuntimeError("MIRNA_CPM_SAMPLE_ORDER_CHANGED")

m_ids = m_candidates["feature_id"].astype(str).tolist()
mi_ids = mi_candidates["feature_id"].astype(str).tolist()

if len(set(m_ids)) != 8505:
    raise RuntimeError("MRNA_CANDIDATE_IDS_NOT_UNIQUE")
if len(set(mi_ids)) != 41:
    raise RuntimeError("MIRNA_CANDIDATE_IDS_NOT_UNIQUE")

missing_m = sorted(set(m_ids) - set(mrna.index.astype(str)))
missing_mi = sorted(set(mi_ids) - set(mirna.index.astype(str)))

if missing_m:
    raise RuntimeError(
        f"MRNA_CANDIDATES_MISSING_FROM_CPM count={len(missing_m)}"
    )
if missing_mi:
    raise RuntimeError(
        f"MIRNA_CANDIDATES_MISSING_FROM_CPM count={len(missing_mi)}"
    )

put("EXPRESSION_INPUT_INTEGRITY", "PASS")


# ------------------------------------------------------------
# B. Freeze 50-subject primary association cohort
# ------------------------------------------------------------
keep = cohort["disease_state"].astype(str).isin(["COVID19","HEALTHY"])
assoc_cohort = cohort.loc[keep].copy()

if assoc_cohort.shape[0] != 50:
    raise RuntimeError(
        f"PRIMARY_ASSOCIATION_COHORT_NOT_50 observed={assoc_cohort.shape[0]}"
    )

counts = assoc_cohort["disease_state"].value_counts().to_dict()
if counts != {"COVID19":35, "HEALTHY":15}:
    raise RuntimeError(
        f"PRIMARY_ASSOCIATION_GROUP_COUNTS_CHANGED observed={counts}"
    )

assoc_subjects = assoc_cohort["subject_id"].astype(str).tolist()

assoc_cohort["primary_association_included"] = "YES"
assoc_cohort["primary_association_role"] = np.where(
    assoc_cohort["disease_state"].astype(str).eq("COVID19"),
    "COVID_CASE",
    "HEALTHY_CONTROL",
)
assoc_cohort["disease_indicator_COVID19"] = np.where(
    assoc_cohort["disease_state"].astype(str).eq("COVID19"),
    1,
    0,
)
assoc_cohort.to_csv(SAMPLE_COHORT, index=False)

mrna_50 = mrna.loc[m_ids, assoc_subjects]
mirna_50 = mirna.loc[mi_ids, assoc_subjects]

if mrna_50.shape != (8505,50):
    raise RuntimeError(
        f"MRNA_PRIMARY_ASSOCIATION_SHAPE_WRONG observed={mrna_50.shape}"
    )
if mirna_50.shape != (41,50):
    raise RuntimeError(
        f"MIRNA_PRIMARY_ASSOCIATION_SHAPE_WRONG observed={mirna_50.shape}"
    )

if np.any(~np.isfinite(mrna_50.to_numpy(dtype=np.float64))):
    raise RuntimeError("MRNA_ASSOCIATION_CPM_NONFINITE")
if np.any(~np.isfinite(mirna_50.to_numpy(dtype=np.float64))):
    raise RuntimeError("MIRNA_ASSOCIATION_CPM_NONFINITE")

put("PRIMARY_ASSOCIATION_COHORT_FROZEN", "YES")
put("PRIMARY_ASSOCIATION_SUBJECTS", 50)
put("PRIMARY_ASSOCIATION_COVID19", 35)
put("PRIMARY_ASSOCIATION_HEALTHY", 15)
put("PRIMARY_ASSOCIATION_MRNA_FEATURES", 8505)
put("PRIMARY_ASSOCIATION_MIRNA_FEATURES", 41)
put("PRIMARY_ASSOCIATION_PAIR_COUNT", 8505 * 41)


# ------------------------------------------------------------
# C. Feature-universe manifest
# ------------------------------------------------------------
feature_rows = []

for i, fid in enumerate(m_ids, 1):
    feature_rows.append({
        "modality": "mRNA",
        "feature_order_1based": i,
        "feature_id": fid,
        "selection_source": "D6B_COV_vs_H_BH_FDR_LE_0.05",
        "primary_association_included": "YES",
    })

for i, fid in enumerate(mi_ids, 1):
    feature_rows.append({
        "modality": "miRNA",
        "feature_order_1based": i,
        "feature_id": fid,
        "selection_source": "D6B_MEDIAN_COV_vs_H_BH_FDR_LE_0.05",
        "primary_association_included": "YES",
    })

pd.DataFrame(feature_rows).to_csv(FEATURE_UNIVERSE, index=False)


# ------------------------------------------------------------
# D. Synthetic partial-Spearman capability tests
# ------------------------------------------------------------
audit_rows = []

# Test 1: group-induced pooled correlation should shrink after adjustment.
#
# D7-V1 mistakenly used perfectly reverse-ordered y values within each
# disease group. That fixture contained a genuine within-group rho ~= -1,
# so disease adjustment correctly exposed a near-perfect negative partial
# correlation. D7-V2 instead creates:
#   - a strong between-group shift in both x and y
#   - near-zero within-group rank correlation by deterministic permutations
# This specifically tests removal of disease-group-driven pooled association.
g = np.array([0]*15 + [1]*35, dtype=np.float64)

x0 = np.arange(1,16,dtype=np.float64)
x1 = np.arange(101,136,dtype=np.float64)

# Deterministic permutations selected prospectively for the fixture only.
# Their within-group rank correlations with x are approximately zero.
y0 = np.array(
    [11,10,1,9,7,14,12,3,6,8,2,5,15,4,13],
    dtype=np.float64,
)
y1_local = np.array(
    [23,5,32,7,35,31,2,14,4,24,19,6,30,10,33,11,28,18,
     25,13,3,17,29,8,16,22,20,34,26,21,9,1,27,12,15],
    dtype=np.float64,
)
y1 = 100.0 + y1_local

x = np.concatenate([x0,x1])
y = np.concatenate([y0,y1])

within_h = float(np.corrcoef(rankdata(x0), rankdata(y0))[0,1])
within_cov = float(
    np.corrcoef(rankdata(x1), rankdata(y1))[0,1]
)

if abs(within_h) >= 0.10:
    raise RuntimeError(
        f"SYNTHETIC_HEALTHY_WITHIN_GROUP_CORRELATION_TOO_LARGE "
        f"rho={within_h}"
    )
if abs(within_cov) >= 0.10:
    raise RuntimeError(
        f"SYNTHETIC_COVID_WITHIN_GROUP_CORRELATION_TOO_LARGE "
        f"rho={within_cov}"
    )

naive_rank_x = rankdata(x, method="average")
naive_rank_y = rankdata(y, method="average")
naive = float(np.corrcoef(naive_rank_x, naive_rank_y)[0,1])

partial, p_partial, df = partial_spearman_binary_group(x,y,g)

if not np.isfinite(naive) or not np.isfinite(partial) or not np.isfinite(p_partial):
    raise RuntimeError("SYNTHETIC_PARTIAL_SPEARMAN_NONFINITE")

# Capability-test thresholds only; NOT biological association thresholds.
if abs(naive) <= 0.50:
    raise RuntimeError(
        f"SYNTHETIC_GROUP_SHIFT_NOT_STRONG_ENOUGH naive={naive}"
    )
if abs(partial) >= 0.10:
    raise RuntimeError(
        f"DISEASE_ADJUSTMENT_DID_NOT_REMOVE_GROUP_DRIVEN_ASSOCIATION "
        f"naive={naive} partial={partial}"
    )
if abs(partial) >= abs(naive):
    raise RuntimeError(
        f"DISEASE_ADJUSTMENT_DID_NOT_REDUCE_GROUP_DRIVEN_ASSOCIATION "
        f"naive={naive} partial={partial}"
    )

audit_rows.append({
    "test": "GROUP_SHIFT_ADJUSTMENT",
    "healthy_within_group_spearman": within_h,
    "covid_within_group_spearman": within_cov,
    "naive_spearman": naive,
    "partial_spearman": partial,
    "pvalue": p_partial,
    "df": df,
    "status": "PASS",
})

# Test 2: monotonic transformation invariance of Spearman ranking.
rng = np.random.default_rng(243219)
x2 = rng.normal(size=50)
y2 = 0.6*x2 + rng.normal(scale=0.6,size=50)
g2 = np.array([0]*15 + [1]*35,dtype=np.float64)

r1,p1,df1 = partial_spearman_binary_group(x2,y2,g2)
r2,p2,df2 = partial_spearman_binary_group(
    np.exp(x2),
    np.exp(y2),
    g2,
)

if abs(r1-r2) > 1e-12:
    raise RuntimeError(
        f"PARTIAL_SPEARMAN_MONOTONIC_INVARIANCE_FAILED diff={abs(r1-r2)}"
    )
if df1 != 47 or df2 != 47:
    raise RuntimeError(
        f"PARTIAL_SPEARMAN_DF_WRONG observed={df1}|{df2}"
    )

audit_rows.append({
    "test": "MONOTONIC_INVARIANCE",
    "naive_spearman": np.nan,
    "partial_spearman": r1,
    "pvalue": p1,
    "df": df1,
    "status": "PASS",
})

# Test 3: paired-bootstrap index semantics.
cov_idx = np.arange(35,dtype=np.int64)
h_idx = np.arange(35,50,dtype=np.int64)

boot_rng = np.random.default_rng(243219)
cov_draw = boot_rng.choice(cov_idx,size=35,replace=True)
h_draw = boot_rng.choice(h_idx,size=15,replace=True)
boot_idx = np.concatenate([cov_draw,h_draw])

if boot_idx.shape[0] != 50:
    raise RuntimeError("BOOTSTRAP_DRAW_LENGTH_WRONG")
if np.sum(boot_idx < 35) != 35 or np.sum(boot_idx >= 35) != 15:
    raise RuntimeError("BOOTSTRAP_STRATIFICATION_WRONG")

audit_rows.append({
    "test": "PAIRED_STRATIFIED_BOOTSTRAP_INDEX_SEMANTICS",
    "naive_spearman": np.nan,
    "partial_spearman": np.nan,
    "pvalue": np.nan,
    "df": np.nan,
    "status": "PASS",
})

pd.DataFrame(audit_rows).to_csv(CAPABILITY_AUDIT,index=False)

put("PARTIAL_SPEARMAN_SYNTHETIC_CAPABILITY", "PASS")
put("SYNTHETIC_GROUP_SHIFT_NAIVE_SPEARMAN", naive)
put("SYNTHETIC_GROUP_ADJUSTED_PARTIAL_SPEARMAN", partial)
put("SYNTHETIC_HEALTHY_WITHIN_GROUP_SPEARMAN", within_h)
put("SYNTHETIC_COVID_WITHIN_GROUP_SPEARMAN", within_cov)
put("SYNTHETIC_GROUP_SHIFT_REMOVAL_FIXTURE", "PASS")
put("PARTIAL_SPEARMAN_DF", 47)
put("PAIRED_STRATIFIED_BOOTSTRAP_INDEX_PREFLIGHT", "PASS")


# ------------------------------------------------------------
# E. Freeze complete association/stability design
# ------------------------------------------------------------
design_lines = [
    "GSE243219_D7_FROZEN_ASSOCIATION_AND_STABILITY_DESIGN",
    "PRIMARY_ASSOCIATION_BIOLOGICAL_SCOPE=COVID19_VS_HEALTHY",
    "PRIMARY_ASSOCIATION_COHORT_SUBJECTS=50",
    "PRIMARY_ASSOCIATION_COHORT_COVID19=35",
    "PRIMARY_ASSOCIATION_COHORT_HEALTHY=15",
    "SEPSIS_INCLUDED_IN_PRIMARY_ASSOCIATION=NO",
    "PRIMARY_ASSOCIATION_MRNA_FEATURES=8505",
    "PRIMARY_ASSOCIATION_MIRNA_FEATURES=41",
    "PRIMARY_ASSOCIATION_PAIR_COUNT=348705",
    "EXPRESSION_INPUT=TMM_NORMALIZED_CPM",
    "LOGCPM_USED_FOR_ASSOCIATION=NO",
    "CPM_USED_AS_DE_INPUT=NO",
    "ASSOCIATION_STATISTIC=PARTIAL_SPEARMAN",
    "PARTIAL_SPEARMAN_RANK_METHOD=AVERAGE_TIES",
    "PARTIAL_SPEARMAN_CONTROL_VARIABLE=COVID19_BINARY_DISEASE_STATUS",
    "PARTIAL_SPEARMAN_RESIDUALIZATION=OLS_ON_INTERCEPT_PLUS_DISEASE_INDICATOR",
    "PARTIAL_SPEARMAN_CORRELATION=PEARSON_OF_RANK_RESIDUALS",
    "PARTIAL_SPEARMAN_TWO_SIDED_TEST=YES",
    "PARTIAL_SPEARMAN_DF=47",
    "MULTIPLE_TESTING=BENJAMINI_HOCHBERG",
    "MULTIPLE_TESTING_FAMILY=ALL_348705_PRIMARY_PAIRS",
    "FULL_DATA_ASSOCIATION_FDR_THRESHOLD=0.05",
    "FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD=0.30",
    "FULL_DATA_ASSOCIATION_CANDIDATE_RULE=FDR_LE_0.05_AND_ABS_RHO_GE_0.30",
    "POSITIVE_ASSOCIATIONS_RETAINED=YES",
    "NEGATIVE_ASSOCIATIONS_RETAINED=YES",
    "CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO",
    "MIRNA_TO_MRNA_DIRECTION_SOURCE=LATER_TARGET_EVIDENCE",
    "NEGATIVE_CORRELATION_REQUIRED_FOR_EDGE=NO",
    "BOOTSTRAP_SCOPE=FULL_DATA_ASSOCIATION_CANDIDATES_ONLY",
    "BOOTSTRAP_REPLICATES=500",
    "BOOTSTRAP_RANDOM_SEED=243219",
    "BOOTSTRAP_RESAMPLING_UNIT=PAIRED_SUBJECT",
    "BOOTSTRAP_WITH_REPLACEMENT=YES",
    "BOOTSTRAP_STRATIFIED_BY_DISEASE=YES",
    "BOOTSTRAP_COVID_DRAWS_PER_REPLICATE=35",
    "BOOTSTRAP_HEALTHY_DRAWS_PER_REPLICATE=15",
    "BOOTSTRAP_MRNA_MIRNA_USE_IDENTICAL_SUBJECT_DRAW=YES",
    "BOOTSTRAP_SELECTION_EVENT=SAME_SIGN_AND_ABS_RHO_GE_0.30",
    "STABLE_EDGE_BOOTSTRAP_FREQUENCY_THRESHOLD=0.80",
    "BOOTSTRAP_SUMMARY=SELECTION_FREQUENCY|SIGN_FREQUENCY|MEDIAN_RHO|P2.5_RHO|P97.5_RHO",
    "STABLE_ASSOCIATION_EDGE_RULE=FULL_FDR_LE_0.05_AND_FULL_ABS_RHO_GE_0.30_AND_BOOTSTRAP_SELECTION_FREQUENCY_GE_0.80",
    "COVID_ONLY_SPEARMAN_ROLE=SECONDARY_DESCRIPTIVE_ANNOTATION",
    "COVID_ONLY_SAMPLES=35",
    "HEALTHY_ONLY_SPEARMAN_ROLE=SECONDARY_DESCRIPTIVE_ANNOTATION",
    "HEALTHY_ONLY_SAMPLES=15",
    "WITHIN_GROUP_SPEARMAN_CAN_DELETE_PRIMARY_STABLE_EDGE=NO",
    "P_vs_H_ROLE=LATER_SEPSIS_COMPARATOR_ANNOTATION",
    "COV_vs_P_ROLE=LATER_COVID_SPECIFICITY_ANNOTATION",
    "ASSOCIATION_PVALUES_ARE_CONDITIONAL_ON_DE_PRESELECTION=YES",
    "NETWORK_CONSTRUCTION_EXECUTED_IN_D7=NO",
    "TARGET_EVIDENCE_INTEGRATION_EXECUTED_IN_D7=NO",
    "ACLA_EXECUTED_IN_D7=NO",
]
FROZEN_DESIGN.write_text(
    "\n".join(design_lines) + "\n",
    encoding="utf-8",
)

put("ASSOCIATION_DESIGN_FROZEN", "YES")
put("PRIMARY_ASSOCIATION_STATISTIC", "PARTIAL_SPEARMAN_CONTROL_DISEASE_STATUS")
put("MULTIPLE_TESTING_PAIR_FAMILY", 348705)
put("FULL_DATA_ASSOCIATION_FDR_THRESHOLD", 0.05)
put("FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD", 0.30)
put("BOOTSTRAP_REPLICATES", 500)
put("BOOTSTRAP_RANDOM_SEED", 243219)
put("STABLE_EDGE_BOOTSTRAP_FREQUENCY_THRESHOLD", 0.80)
put("POSITIVE_ASSOCIATIONS_RETAINED", "YES")
put("NEGATIVE_ASSOCIATIONS_RETAINED", "YES")
put("CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION", "NO")
put("REAL_ASSOCIATION_EXECUTED", "NO")
put("REAL_ASSOCIATION_PVALUES_COMPUTED", "NO")
put("BOOTSTRAP_EXECUTED", "NO")
put("NETWORK_EXECUTED", "NO")
put("TARGET_EVIDENCE_INTEGRATION_EXECUTED", "NO")
put("ACLA_EXECUTED", "NO")
put("READY_FOR_D7A_PRIMARY_ASSOCIATION_EXECUTION", "YES")
put("NEXT_PHASE", "D7A_PRIMARY_PARTIAL_SPEARMAN_ASSOCIATION_EXECUTION")

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
    $Cohort,
    $MrnaCandidates,
    $MirnaCandidates,
    $SampleCohort,
    $FeatureUniverse,
    $CapabilityAudit,
    $FrozenDesign,
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
        Write-Host '=== D7 PYTHON STDERR ==='
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
    throw ('D7_PYTHON_FAILED exit={0} full_traceback={1}' -f `
        $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D7_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('EXPRESSION_INPUT_INTEGRITY','PASS'),
    @('PRIMARY_ASSOCIATION_COHORT_FROZEN','YES'),
    @('PRIMARY_ASSOCIATION_SUBJECTS','50'),
    @('PRIMARY_ASSOCIATION_COVID19','35'),
    @('PRIMARY_ASSOCIATION_HEALTHY','15'),
    @('PRIMARY_ASSOCIATION_MRNA_FEATURES','8505'),
    @('PRIMARY_ASSOCIATION_MIRNA_FEATURES','41'),
    @('PRIMARY_ASSOCIATION_PAIR_COUNT','348705'),
    @('PARTIAL_SPEARMAN_SYNTHETIC_CAPABILITY','PASS'),
    @('SYNTHETIC_GROUP_SHIFT_REMOVAL_FIXTURE','PASS'),
    @('PARTIAL_SPEARMAN_DF','47'),
    @('PAIRED_STRATIFIED_BOOTSTRAP_INDEX_PREFLIGHT','PASS'),
    @('ASSOCIATION_DESIGN_FROZEN','YES'),
    @('PRIMARY_ASSOCIATION_STATISTIC','PARTIAL_SPEARMAN_CONTROL_DISEASE_STATUS'),
    @('MULTIPLE_TESTING_PAIR_FAMILY','348705'),
    @('FULL_DATA_ASSOCIATION_FDR_THRESHOLD','0.05'),
    @('FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD','0.3'),
    @('BOOTSTRAP_REPLICATES','500'),
    @('BOOTSTRAP_RANDOM_SEED','243219'),
    @('STABLE_EDGE_BOOTSTRAP_FREQUENCY_THRESHOLD','0.8'),
    @('POSITIVE_ASSOCIATIONS_RETAINED','YES'),
    @('NEGATIVE_ASSOCIATIONS_RETAINED','YES'),
    @('CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION','NO'),
    @('REAL_ASSOCIATION_EXECUTED','NO'),
    @('REAL_ASSOCIATION_PVALUES_COMPUTED','NO'),
    @('BOOTSTRAP_EXECUTED','NO'),
    @('NETWORK_EXECUTED','NO'),
    @('TARGET_EVIDENCE_INTEGRATION_EXECUTED','NO'),
    @('ACLA_EXECUTED','NO'),
    @('READY_FOR_D7A_PRIMARY_ASSOCIATION_EXECUTION','YES'),
    @('NEXT_PHASE','D7A_PRIMARY_PARTIAL_SPEARMAN_ASSOCIATION_EXECUTION')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D7_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 3. Decision
# ------------------------------------------------------------
@(
    'GSE243219_D7_V2_DECISION',
    'PHASE_D7_V2_STATUS=PASS',
    'MODE=DESIGN_AND_CAPABILITY_PREFLIGHT_ONLY',
    'D3B_EXPRESSION_CERTIFICATION_GATE=PASS',
    'D3B_OUTPUTS_RECERTIFIED=18/18',
    'D4_COHORT_CERTIFICATION_GATE=PASS',
    'D4_OUTPUTS_RECERTIFIED=14/14',
    'D6B_SELECTION_CERTIFICATION_GATE=PASS',
    'D6B_OUTPUTS_RECERTIFIED=11/11',
    'PRIMARY_ASSOCIATION_COHORT=COV_PLUS_H',
    'PRIMARY_ASSOCIATION_SUBJECTS=50',
    'PRIMARY_ASSOCIATION_COVID19=35',
    'PRIMARY_ASSOCIATION_HEALTHY=15',
    'PRIMARY_ASSOCIATION_MRNA_FEATURES=8505',
    'PRIMARY_ASSOCIATION_MIRNA_FEATURES=41',
    'PRIMARY_ASSOCIATION_PAIR_COUNT=348705',
    'EXPRESSION_INPUT=TMM_NORMALIZED_CPM',
    'PRIMARY_ASSOCIATION_STATISTIC=PARTIAL_SPEARMAN_CONTROL_DISEASE_STATUS',
    'PARTIAL_SPEARMAN_DF=47',
    'MULTIPLE_TESTING=BH_ACROSS_ALL_348705_PRIMARY_PAIRS',
    'FULL_DATA_ASSOCIATION_FDR_THRESHOLD=0.05',
    'FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD=0.30',
    'BOOTSTRAP_SCOPE=FULL_DATA_ASSOCIATION_CANDIDATES_ONLY',
    'BOOTSTRAP_REPLICATES=500',
    'BOOTSTRAP_RANDOM_SEED=243219',
    'BOOTSTRAP_STRATIFIED_BY_DISEASE=YES',
    'STABLE_EDGE_BOOTSTRAP_FREQUENCY_THRESHOLD=0.80',
    'POSITIVE_ASSOCIATIONS_RETAINED=YES',
    'NEGATIVE_ASSOCIATIONS_RETAINED=YES',
    'CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO',
    'MIRNA_TO_MRNA_DIRECTION_SOURCE=LATER_TARGET_EVIDENCE',
    'COVID_ONLY_SPEARMAN_ROLE=SECONDARY_DESCRIPTIVE_ANNOTATION',
    'HEALTHY_ONLY_SPEARMAN_ROLE=SECONDARY_DESCRIPTIVE_ANNOTATION',
    'SEPSIS_INCLUDED_IN_PRIMARY_ASSOCIATION=NO',
    'ASSOCIATION_PVALUES_ARE_CONDITIONAL_ON_DE_PRESELECTION=YES',
    'ASSOCIATION_DESIGN_FROZEN=YES',
    'REAL_ASSOCIATION_EXECUTED=NO',
    'REAL_ASSOCIATION_PVALUES_COMPUTED=NO',
    'BOOTSTRAP_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D7A_PRIMARY_ASSOCIATION_EXECUTION=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D7A_PRIMARY_PARTIAL_SPEARMAN_ASSOCIATION_EXECUTION',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Manifest
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $SampleCohort,
    $FeatureUniverse,
    $CapabilityAudit,
    $FrozenDesign,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D7_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p
    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D7SHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D7-V2 SUMMARY ===',
    'PHASE_D7_V2_STATUS=PASS',
    'MODE=DESIGN_AND_CAPABILITY_PREFLIGHT_ONLY',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    ('SCIPY_VERSION={0}' -f $ScipyVersion),
    'D3B_EXPRESSION_CERTIFICATION_GATE=PASS',
    'D4_COHORT_CERTIFICATION_GATE=PASS',
    'D6B_SELECTION_CERTIFICATION_GATE=PASS',
    'PRIMARY_ASSOCIATION_COHORT=COV_PLUS_H',
    'PRIMARY_ASSOCIATION_SUBJECTS=50',
    'PRIMARY_ASSOCIATION_COVID19=35',
    'PRIMARY_ASSOCIATION_HEALTHY=15',
    'PRIMARY_ASSOCIATION_MRNA_FEATURES=8505',
    'PRIMARY_ASSOCIATION_MIRNA_FEATURES=41',
    'PRIMARY_ASSOCIATION_PAIR_COUNT=348705',
    'EXPRESSION_INPUT=TMM_NORMALIZED_CPM',
    'D7_V2_CORRECTION=GROUP_SHIFT_SYNTHETIC_FIXTURE_REMOVED_ARTIFICIAL_WITHIN_GROUP_ANTICORRELATION',
    ('SYNTHETIC_GROUP_SHIFT_NAIVE_SPEARMAN={0}' -f (Cap 'SYNTHETIC_GROUP_SHIFT_NAIVE_SPEARMAN')),
    ('SYNTHETIC_GROUP_ADJUSTED_PARTIAL_SPEARMAN={0}' -f (Cap 'SYNTHETIC_GROUP_ADJUSTED_PARTIAL_SPEARMAN')),
    ('SYNTHETIC_HEALTHY_WITHIN_GROUP_SPEARMAN={0}' -f (Cap 'SYNTHETIC_HEALTHY_WITHIN_GROUP_SPEARMAN')),
    ('SYNTHETIC_COVID_WITHIN_GROUP_SPEARMAN={0}' -f (Cap 'SYNTHETIC_COVID_WITHIN_GROUP_SPEARMAN')),
    'SYNTHETIC_GROUP_SHIFT_REMOVAL_FIXTURE=PASS',
    'PARTIAL_SPEARMAN_SYNTHETIC_CAPABILITY=PASS',
    'PRIMARY_ASSOCIATION_STATISTIC=PARTIAL_SPEARMAN_CONTROL_DISEASE_STATUS',
    'PARTIAL_SPEARMAN_DF=47',
    'MULTIPLE_TESTING=BH_ACROSS_ALL_348705_PRIMARY_PAIRS',
    'FULL_DATA_ASSOCIATION_FDR_THRESHOLD=0.05',
    'FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD=0.30',
    'BOOTSTRAP_SCOPE=FULL_DATA_ASSOCIATION_CANDIDATES_ONLY',
    'BOOTSTRAP_REPLICATES=500',
    'BOOTSTRAP_RANDOM_SEED=243219',
    'PAIRED_STRATIFIED_BOOTSTRAP_INDEX_PREFLIGHT=PASS',
    'STABLE_EDGE_BOOTSTRAP_FREQUENCY_THRESHOLD=0.80',
    'POSITIVE_ASSOCIATIONS_RETAINED=YES',
    'NEGATIVE_ASSOCIATIONS_RETAINED=YES',
    'CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO',
    'MIRNA_TO_MRNA_DIRECTION_SOURCE=LATER_TARGET_EVIDENCE',
    'COVID_ONLY_SPEARMAN_ROLE=SECONDARY_DESCRIPTIVE_ANNOTATION',
    'HEALTHY_ONLY_SPEARMAN_ROLE=SECONDARY_DESCRIPTIVE_ANNOTATION',
    'SEPSIS_INCLUDED_IN_PRIMARY_ASSOCIATION=NO',
    'ASSOCIATION_PVALUES_ARE_CONDITIONAL_ON_DE_PRESELECTION=YES',
    'ASSOCIATION_DESIGN_FROZEN=YES',
    'REAL_ASSOCIATION_EXECUTED=NO',
    'REAL_ASSOCIATION_PVALUES_COMPUTED=NO',
    'BOOTSTRAP_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D7A_PRIMARY_ASSOCIATION_EXECUTION=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D7A_PRIMARY_PARTIAL_SPEARMAN_ASSOCIATION_EXECUTION',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D7_PRIMARY_ASSOCIATION_COHORT={0}' -f $SampleCohort)
Write-Host ('D7_PRIMARY_ASSOCIATION_FEATURE_UNIVERSE={0}' -f $FeatureUniverse)
Write-Host ('D7_PARTIAL_SPEARMAN_CAPABILITY_PREFLIGHT={0}' -f $CapabilityAudit)
Write-Host ('D7_FROZEN_ASSOCIATION_DESIGN={0}' -f $FrozenDesign)
Write-Host ('D7_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D7_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D7_V2=PASS'
Write-Host 'STOP=YES'
