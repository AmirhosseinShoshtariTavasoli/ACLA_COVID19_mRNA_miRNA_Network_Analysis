$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D7A — PRIMARY PARTIAL-SPEARMAN ASSOCIATION EXECUTION
#
# First authorized real mRNA-miRNA association execution.
#
# Frozen D7-V2 design:
#   cohort:
#     35 COVID19 + 15 HEALTHY = 50 paired subjects
#
#   candidate features:
#     mRNA  = 8,505
#     miRNA =    41
#     pairs = 348,705
#
#   statistic:
#     disease-adjusted partial Spearman
#
#   implementation:
#     - average-rank each feature across the same 50 subjects
#     - residualize ranks on intercept + COVID19 indicator
#     - Pearson correlation of residual rank vectors
#     - two-sided t-test, df = 47
#
#   multiplicity:
#     BH across ALL 348,705 primary pairs
#
#   full-data candidate:
#     FDR <= 0.05
#     AND abs(rho) >= 0.30
#
# D7A DOES NOT:
#   - bootstrap
#   - integrate target databases
#   - infer miRNA->mRNA regulatory direction
#   - construct a network
#   - execute A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'

$D3Root = Join-Path $Project '03_QC_AND_FILTERING'
$D5Root = Join-Path $Project '05_DIFFERENTIAL_EXPRESSION'
$D6Root = Join-Path $Project '06_ASSOCIATION_AND_STABILITY'

$D3BRun = Join-Path $D3Root 'D3B_FILTER_TMM_SAMPLE_QC_20260905_092809'
$D3BManifest = Join-Path $D3BRun 'D3B_OUTPUT_SHA256_MANIFEST.csv'
$MrnaCpm = Join-Path $D3BRun 'D3B_MRNA_TMM_NORMALIZED_CPM_15083x72.csv.gz'
$MirnaCpm = Join-Path $D3BRun 'D3B_MIRNA_TMM_NORMALIZED_CPM_428x72.csv.gz'

$D6BRun = Join-Path $D5Root 'D6B_SELECTION_FREEZE_20260905_103809'
$D6BManifest = Join-Path $D6BRun 'D6B_OUTPUT_SHA256_MANIFEST.csv'
$MrnaCandidates = Join-Path $D6BRun 'D6B_MRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES.csv.gz'
$MirnaCandidates = Join-Path $D6BRun 'D6B_MIRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES.csv.gz'

$D7Run = Join-Path $D6Root 'D7_V2_ASSOCIATION_STABILITY_PREFLIGHT_20260905_104708'
$D7Manifest = Join-Path $D7Run 'D7_OUTPUT_SHA256_MANIFEST.csv'
$D7Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D7_V2_20260905_104708\PHASE_D7_SUMMARY.txt'
$AssocCohort = Join-Path $D7Run 'D7_PRIMARY_ASSOCIATION_COHORT_50.csv'
$FeatureUniverse = Join-Path $D7Run 'D7_PRIMARY_ASSOCIATION_FEATURE_UNIVERSE.csv'
$FrozenDesign = Join-Path $D7Run 'D7_FROZEN_ASSOCIATION_AND_STABILITY_DESIGN.txt'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D6Root ('D7A_PRIMARY_ASSOCIATION_EXECUTION_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D7A_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D7A_PRIMARY_PARTIAL_SPEARMAN_ASSOCIATION_EXECUTION.py'
$ImplementationAudit = Join-Path $RunDir 'D7A_VECTORIZED_PARTIAL_SPEARMAN_AUDIT.csv'
$AllAssociations = Join-Path $RunDir 'D7A_ALL_348705_PRIMARY_ASSOCIATIONS.csv.gz'
$CandidateAssociations = Join-Path $RunDir 'D7A_FULL_DATA_ASSOCIATION_CANDIDATES.csv.gz'
$AssociationSummary = Join-Path $RunDir 'D7A_ASSOCIATION_SUMMARY.csv'
$ExecutionSpec = Join-Path $RunDir 'D7A_EXECUTION_SPECIFICATION.txt'
$ResultJson = Join-Path $RunDir 'D7A_RESULT.json'

$PythonStdout = Join-Path $RunDir 'D7A_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D7A_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D7A_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D7A_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D7A_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D7A_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D7A — PRIMARY PARTIAL-SPEARMAN ASSOCIATION EXECUTION ==='
Write-Host 'MODE=FIRST_AUTHORIZED_REAL_ASSOCIATION_EXECUTION'
Write-Host 'PRIMARY_ASSOCIATION_SUBJECTS=50'
Write-Host 'PRIMARY_ASSOCIATION_COVID19=35'
Write-Host 'PRIMARY_ASSOCIATION_HEALTHY=15'
Write-Host 'PRIMARY_ASSOCIATION_MRNA_FEATURES=8505'
Write-Host 'PRIMARY_ASSOCIATION_MIRNA_FEATURES=41'
Write-Host 'PRIMARY_ASSOCIATION_PAIR_COUNT=348705'
Write-Host 'PRIMARY_ASSOCIATION_STATISTIC=PARTIAL_SPEARMAN_CONTROL_DISEASE_STATUS'
Write-Host 'MULTIPLE_TESTING=BH_ACROSS_ALL_348705_PRIMARY_PAIRS'
Write-Host 'FULL_DATA_ASSOCIATION_FDR_THRESHOLD=0.05'
Write-Host 'FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD=0.30'
Write-Host 'REAL_ASSOCIATION_EXECUTED=YES'
Write-Host 'REAL_ASSOCIATION_PVALUES_COMPUTED=YES'
Write-Host 'BH_FDR_COMPUTED=YES'
Write-Host 'BOOTSTRAP_EXECUTED=NO'
Write-Host 'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $D3BManifest,$MrnaCpm,$MirnaCpm,
    $D6BManifest,$MrnaCandidates,$MirnaCandidates,
    $D7Manifest,$D7Report,$AssocCohort,$FeatureUniverse,$FrozenDesign
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D7A_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D7ASHA256 {
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
        $hash = Get-D7ASHA256 $r.full_path

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

Recertify-Manifest -ManifestPath $D6BManifest -ExpectedRows 11 -Label 'D6B'
Write-Host 'D6B_SELECTION_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D7Manifest -ExpectedRows 10 -Label 'D7_V2'
Write-Host 'D7_V2_DESIGN_CERTIFICATION_GATE=PASS'

$d7 = Get-Content -LiteralPath $D7Report -Raw

foreach ($tok in @(
    'PHASE_D7_V2_STATUS=PASS',
    'PRIMARY_ASSOCIATION_SUBJECTS=50',
    'PRIMARY_ASSOCIATION_COVID19=35',
    'PRIMARY_ASSOCIATION_HEALTHY=15',
    'PRIMARY_ASSOCIATION_MRNA_FEATURES=8505',
    'PRIMARY_ASSOCIATION_MIRNA_FEATURES=41',
    'PRIMARY_ASSOCIATION_PAIR_COUNT=348705',
    'PRIMARY_ASSOCIATION_STATISTIC=PARTIAL_SPEARMAN_CONTROL_DISEASE_STATUS',
    'PARTIAL_SPEARMAN_DF=47',
    'MULTIPLE_TESTING=BH_ACROSS_ALL_348705_PRIMARY_PAIRS',
    'FULL_DATA_ASSOCIATION_FDR_THRESHOLD=0.05',
    'FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD=0.30',
    'BOOTSTRAP_REPLICATES=500',
    'BOOTSTRAP_RANDOM_SEED=243219',
    'STABLE_EDGE_BOOTSTRAP_FREQUENCY_THRESHOLD=0.80',
    'ASSOCIATION_DESIGN_FROZEN=YES',
    'REAL_ASSOCIATION_EXECUTED=NO',
    'READY_FOR_D7A_PRIMARY_ASSOCIATION_EXECUTION=YES'
)) {
    if ($d7 -notmatch [regex]::Escape($tok)) {
        throw ('D7_V2_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
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
# 2. Python real association execution
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
ASSOC_COHORT = Path(sys.argv[3])
FEATURE_UNIVERSE = Path(sys.argv[4])
MRNA_CANDIDATES = Path(sys.argv[5])
MIRNA_CANDIDATES = Path(sys.argv[6])

IMPLEMENTATION_AUDIT = Path(sys.argv[7])
ALL_ASSOCIATIONS = Path(sys.argv[8])
CANDIDATE_ASSOCIATIONS = Path(sys.argv[9])
ASSOCIATION_SUMMARY = Path(sys.argv[10])
EXECUTION_SPEC = Path(sys.argv[11])
RESULT_JSON = Path(sys.argv[12])


N_SUBJECTS = 50
N_COV = 35
N_H = 15
N_MRNA = 8505
N_MIRNA = 41
N_PAIRS = 348705
DF = 47

FDR_THRESHOLD = 0.05
ABS_RHO_THRESHOLD = 0.30

results = {}


def put(k, v):
    results[k] = v
    print(f"{k}={v}")


def bh_adjust(pvalues):
    p = np.asarray(pvalues, dtype=np.float64)

    if p.ndim != 1:
        raise RuntimeError("BH_INPUT_NOT_1D")
    if p.size != N_PAIRS:
        raise RuntimeError(
            f"BH_PAIR_FAMILY_SIZE_CHANGED observed={p.size}"
        )
    if np.any(~np.isfinite(p)) or np.any((p < 0) | (p > 1)):
        raise RuntimeError("BH_INPUT_INVALID")

    order = np.argsort(p, kind="mergesort")
    ps = p[order]

    adj = ps * p.size / np.arange(1, p.size + 1, dtype=np.float64)
    adj = np.minimum.accumulate(adj[::-1])[::-1]
    adj = np.clip(adj, 0.0, 1.0)

    out = np.empty_like(adj)
    out[order] = adj

    return out


def rank_rows(matrix):
    x = np.asarray(matrix, dtype=np.float64)

    if x.ndim != 2:
        raise RuntimeError("RANK_INPUT_NOT_2D")
    if np.any(~np.isfinite(x)):
        raise RuntimeError("RANK_INPUT_NONFINITE")

    # scipy rankdata supports row-wise ranking with average ties.
    return rankdata(
        x,
        method="average",
        axis=1,
    ).astype(np.float64)


def residualize_rows_against_group(ranks, disease_indicator):
    ranks = np.asarray(ranks, dtype=np.float64)
    disease_indicator = np.asarray(disease_indicator, dtype=np.float64)

    if ranks.shape[1] != disease_indicator.size:
        raise RuntimeError("RESIDUALIZATION_SAMPLE_SIZE_MISMATCH")

    Z = np.column_stack([
        np.ones(disease_indicator.size, dtype=np.float64),
        disease_indicator,
    ])

    if np.linalg.matrix_rank(Z) != 2:
        raise RuntimeError("RESIDUALIZATION_DESIGN_NOT_FULL_RANK")

    # Residual-maker matrix M = I - H.
    ZtZ_inv = np.linalg.inv(Z.T @ Z)
    H = Z @ ZtZ_inv @ Z.T
    M = np.eye(disease_indicator.size, dtype=np.float64) - H

    resid = ranks @ M

    # Numerical orthogonality audit:
    ortho = np.max(np.abs(resid @ Z))
    if ortho > 1e-9:
        raise RuntimeError(
            f"RANK_RESIDUALS_NOT_ORTHOGONAL_TO_GROUP_DESIGN max={ortho}"
        )

    return resid, ortho


def normalize_residual_rows(resid, label):
    resid = np.asarray(resid, dtype=np.float64)
    norms = np.sqrt(np.sum(resid * resid, axis=1))

    if np.any(~np.isfinite(norms)):
        raise RuntimeError(f"{label}_RESIDUAL_NORM_NONFINITE")

    zero = norms <= 1e-14
    if np.any(zero):
        idx = np.where(zero)[0][:10].tolist()
        raise RuntimeError(
            f"{label}_ZERO_RESIDUAL_VARIANCE_FEATURES "
            f"count={int(np.sum(zero))} first_indices={idx}"
        )

    return resid / norms[:, None], norms


def direct_partial_spearman(x, y, disease_indicator):
    x = np.asarray(x, dtype=np.float64)
    y = np.asarray(y, dtype=np.float64)
    g = np.asarray(disease_indicator, dtype=np.float64)

    rx = rankdata(x, method="average").astype(np.float64)
    ry = rankdata(y, method="average").astype(np.float64)

    Z = np.column_stack([
        np.ones(x.size, dtype=np.float64),
        g,
    ])

    bx, _, _, _ = np.linalg.lstsq(Z, rx, rcond=None)
    by, _, _, _ = np.linalg.lstsq(Z, ry, rcond=None)

    ex = rx - Z @ bx
    ey = ry - Z @ by

    nx = float(np.sqrt(np.sum(ex * ex)))
    ny = float(np.sqrt(np.sum(ey * ey)))

    if nx <= 1e-14 or ny <= 1e-14:
        raise RuntimeError("DIRECT_PARTIAL_SPEARMAN_ZERO_VARIANCE")

    rho = float(np.sum(ex * ey) / (nx * ny))
    rho = float(np.clip(rho, -1.0, 1.0))

    if abs(rho) >= 1.0:
        p = 0.0
        tstat = np.sign(rho) * np.inf
    else:
        tstat = float(
            rho * np.sqrt(DF / (1.0 - rho * rho))
        )
        p = float(
            2.0 * student_t.sf(abs(tstat), df=DF)
        )

    return rho, tstat, p


# ------------------------------------------------------------
# A. Read and validate frozen inputs
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
feature_universe = pd.read_csv(FEATURE_UNIVERSE)

m_candidates = pd.read_csv(
    MRNA_CANDIDATES,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
mi_candidates = pd.read_csv(
    MIRNA_CANDIDATES,
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
if feature_universe.shape[0] != N_MRNA + N_MIRNA:
    raise RuntimeError(
        f"FEATURE_UNIVERSE_ROWS_CHANGED observed={feature_universe.shape[0]}"
    )
if m_candidates.shape[0] != N_MRNA:
    raise RuntimeError(
        f"MRNA_CANDIDATES_ROWS_CHANGED observed={m_candidates.shape[0]}"
    )
if mi_candidates.shape[0] != N_MIRNA:
    raise RuntimeError(
        f"MIRNA_CANDIDATES_ROWS_CHANGED observed={mi_candidates.shape[0]}"
    )

if cohort["disease_state"].value_counts().to_dict() != {
    "COVID19":35,
    "HEALTHY":15,
}:
    raise RuntimeError("ASSOCIATION_COHORT_GROUP_COUNTS_CHANGED")

subjects = cohort["subject_id"].astype(str).tolist()

if len(subjects) != len(set(subjects)):
    raise RuntimeError("ASSOCIATION_COHORT_SUBJECTS_NOT_UNIQUE")

m_ids = m_candidates["feature_id"].astype(str).tolist()
mi_ids = mi_candidates["feature_id"].astype(str).tolist()

univ_m = feature_universe.loc[
    feature_universe["modality"].astype(str).eq("mRNA"),
    "feature_id",
].astype(str).tolist()
univ_mi = feature_universe.loc[
    feature_universe["modality"].astype(str).eq("miRNA"),
    "feature_id",
].astype(str).tolist()

if univ_m != m_ids:
    raise RuntimeError("MRNA_D6B_D7_FEATURE_UNIVERSE_MISMATCH")
if univ_mi != mi_ids:
    raise RuntimeError("MIRNA_D6B_D7_FEATURE_UNIVERSE_MISMATCH")

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

m50 = mrna.loc[m_ids, subjects].to_numpy(dtype=np.float64)
mi50 = mirna.loc[mi_ids, subjects].to_numpy(dtype=np.float64)

if m50.shape != (N_MRNA,N_SUBJECTS):
    raise RuntimeError(f"MRNA_ASSOCIATION_MATRIX_SHAPE_WRONG={m50.shape}")
if mi50.shape != (N_MIRNA,N_SUBJECTS):
    raise RuntimeError(f"MIRNA_ASSOCIATION_MATRIX_SHAPE_WRONG={mi50.shape}")

if np.any(~np.isfinite(m50)):
    raise RuntimeError("MRNA_ASSOCIATION_MATRIX_NONFINITE")
if np.any(~np.isfinite(mi50)):
    raise RuntimeError("MIRNA_ASSOCIATION_MATRIX_NONFINITE")

g = cohort["disease_indicator_COVID19"].to_numpy(dtype=np.float64)

if not np.array_equal(np.unique(g), np.array([0.0,1.0])):
    raise RuntimeError("DISEASE_INDICATOR_NOT_BINARY")
if int(np.sum(g == 1.0)) != N_COV or int(np.sum(g == 0.0)) != N_H:
    raise RuntimeError("DISEASE_INDICATOR_COUNTS_CHANGED")

put("D7A_INPUT_INTEGRITY", "PASS")


# ------------------------------------------------------------
# B. Vectorized partial-Spearman calculation
# ------------------------------------------------------------
m_rank = rank_rows(m50)
mi_rank = rank_rows(mi50)

m_resid, m_ortho = residualize_rows_against_group(m_rank, g)
mi_resid, mi_ortho = residualize_rows_against_group(mi_rank, g)

m_unit, m_norms = normalize_residual_rows(m_resid, "MRNA")
mi_unit, mi_norms = normalize_residual_rows(mi_resid, "MIRNA")

rho_matrix = m_unit @ mi_unit.T
rho_matrix = np.clip(rho_matrix, -1.0, 1.0)

if rho_matrix.shape != (N_MRNA,N_MIRNA):
    raise RuntimeError(
        f"RHO_MATRIX_SHAPE_WRONG observed={rho_matrix.shape}"
    )

rho = rho_matrix.reshape(-1, order="C")

if rho.size != N_PAIRS:
    raise RuntimeError(
        f"RHO_PAIR_COUNT_WRONG observed={rho.size}"
    )
if np.any(~np.isfinite(rho)):
    raise RuntimeError("RHO_NONFINITE")
if np.any(np.abs(rho) > 1.0 + 1e-12):
    raise RuntimeError("RHO_OUT_OF_RANGE")

denom = 1.0 - rho * rho

# No exact +/-1 is expected after disease adjustment across 50 samples,
# but handle it deterministically if it occurs.
tstat = np.empty_like(rho)
pvalue = np.empty_like(rho)

perfect = denom <= 0.0
normal = ~perfect

tstat[perfect] = np.sign(rho[perfect]) * np.inf
pvalue[perfect] = 0.0

tstat[normal] = rho[normal] * np.sqrt(
    DF / denom[normal]
)
pvalue[normal] = 2.0 * student_t.sf(
    np.abs(tstat[normal]),
    df=DF,
)

if np.any(~np.isfinite(pvalue)):
    raise RuntimeError("PVALUE_NONFINITE")
if np.any((pvalue < 0) | (pvalue > 1)):
    raise RuntimeError("PVALUE_OUT_OF_RANGE")

fdr = bh_adjust(pvalue)

if np.any(~np.isfinite(fdr)):
    raise RuntimeError("FDR_NONFINITE")
if np.any((fdr < 0) | (fdr > 1)):
    raise RuntimeError("FDR_OUT_OF_RANGE")

put("REAL_PARTIAL_SPEARMAN_MATRIX_COMPUTED", "YES")
put("REAL_ASSOCIATION_PVALUES_COMPUTED", "YES")
put("BH_FDR_COMPUTED_ACROSS_ALL_PAIRS", "YES")
put("MRNA_RANK_RESIDUAL_ORTHOGONALITY_MAX_ABS", float(m_ortho))
put("MIRNA_RANK_RESIDUAL_ORTHOGONALITY_MAX_ABS", float(mi_ortho))


# ------------------------------------------------------------
# C. Deterministic direct-vs-vectorized audit
# ------------------------------------------------------------
audit_rng = np.random.default_rng(243219)
audit_flat = audit_rng.choice(
    N_PAIRS,
    size=64,
    replace=False,
)

audit_rows = []
max_rho_diff = 0.0
max_p_diff = 0.0

for flat_idx in audit_flat:
    mi = int(flat_idx // N_MIRNA)
    mj = int(flat_idx % N_MIRNA)

    drho, dt, dp = direct_partial_spearman(
        m50[mi,:],
        mi50[mj,:],
        g,
    )

    vrho = float(rho_matrix[mi,mj])
    vp = float(pvalue[flat_idx])

    rho_diff = abs(drho - vrho)
    p_diff = abs(dp - vp)

    max_rho_diff = max(max_rho_diff, rho_diff)
    max_p_diff = max(max_p_diff, p_diff)

    audit_rows.append({
        "flat_pair_index_0based": int(flat_idx),
        "mRNA_index_0based": mi,
        "miRNA_index_0based": mj,
        "mRNA_id": m_ids[mi],
        "miRNA_id": mi_ids[mj],
        "vectorized_rho": vrho,
        "direct_rho": drho,
        "abs_rho_difference": rho_diff,
        "vectorized_pvalue": vp,
        "direct_pvalue": dp,
        "abs_pvalue_difference": p_diff,
        "status": (
            "PASS"
            if rho_diff <= 1e-12 and p_diff <= 1e-12
            else "FAIL"
        ),
    })

audit_df = pd.DataFrame(audit_rows)

if not audit_df["status"].eq("PASS").all():
    raise RuntimeError(
        f"VECTORIZED_DIRECT_AUDIT_FAILED "
        f"rho_max={max_rho_diff} p_max={max_p_diff}"
    )

audit_df.to_csv(IMPLEMENTATION_AUDIT,index=False)

put("VECTORIZED_DIRECT_PAIR_AUDIT", "PASS")
put("VECTORIZED_DIRECT_AUDIT_PAIRS", 64)
put("VECTORIZED_DIRECT_RHO_MAX_ABS_DIFF", float(max_rho_diff))
put("VECTORIZED_DIRECT_PVALUE_MAX_ABS_DIFF", float(max_p_diff))


# ------------------------------------------------------------
# D. Construct all 348,705 result rows
# ------------------------------------------------------------
mrna_col = np.repeat(np.asarray(m_ids,dtype=object), N_MIRNA)
mirna_col = np.tile(np.asarray(mi_ids,dtype=object), N_MRNA)

candidate = (
    (fdr <= FDR_THRESHOLD)
    & (np.abs(rho) >= ABS_RHO_THRESHOLD)
)

direction = np.where(
    rho > 0,
    "POSITIVE_ASSOCIATION",
    np.where(
        rho < 0,
        "NEGATIVE_ASSOCIATION",
        "ZERO_ASSOCIATION",
    ),
)

all_df = pd.DataFrame({
    "pair_index_1based": np.arange(1,N_PAIRS+1,dtype=np.int64),
    "mRNA_id": mrna_col,
    "miRNA_id": mirna_col,
    "partial_spearman_rho": rho,
    "abs_partial_spearman_rho": np.abs(rho),
    "t_statistic": tstat,
    "df": DF,
    "PValue": pvalue,
    "FDR": fdr,
    "association_sign": direction,
    "full_data_candidate_FDR_le_0_05_and_abs_rho_ge_0_30": np.where(
        candidate,
        "YES",
        "NO",
    ),
    "regulatory_direction_inferred_from_correlation": "NO",
})

if all_df.shape[0] != N_PAIRS:
    raise RuntimeError(
        f"ALL_ASSOCIATION_ROWS_WRONG observed={all_df.shape[0]}"
    )

all_df.to_csv(
    ALL_ASSOCIATIONS,
    index=False,
    compression="gzip",
    float_format="%.17g",
)

# Round-trip structural audit.
rt = pd.read_csv(
    ALL_ASSOCIATIONS,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)

if rt.shape[0] != N_PAIRS:
    raise RuntimeError(
        f"ALL_ASSOCIATION_ROUNDTRIP_ROWS_WRONG observed={rt.shape[0]}"
    )

for col in ["partial_spearman_rho","PValue","FDR"]:
    if not np.allclose(
        rt[col].to_numpy(dtype=np.float64),
        all_df[col].to_numpy(dtype=np.float64),
        rtol=0.0,
        atol=1e-15,
        equal_nan=False,
    ):
        raise RuntimeError(
            f"ALL_ASSOCIATION_ROUNDTRIP_VALUE_MISMATCH column={col}"
        )

put("ALL_348705_ASSOCIATION_ROWS_SAVED", "YES")
put("ALL_ASSOCIATION_ROUNDTRIP_INTEGRITY", "PASS")


# ------------------------------------------------------------
# E. Candidate subset + DE annotations
# ------------------------------------------------------------
candidate_df = all_df.loc[candidate].copy()

# Join compact D6B annotations only on candidate rows.
m_annot_cols = [
    "feature_id",
    "COV_vs_H_logFC",
    "COV_vs_H_FDR",
    "COV_vs_H_strict_priority",
    "P_vs_H_logFC",
    "P_vs_H_FDR",
    "COV_vs_P_logFC",
    "COV_vs_P_FDR",
]
mi_annot_cols = [
    "feature_id",
    "MEDIAN_COV_vs_H_logFC",
    "MEDIAN_COV_vs_H_FDR",
    "MEDIAN_COV_vs_H_strict_priority",
    "MEDIAN_P_vs_H_logFC",
    "MEDIAN_P_vs_H_FDR",
    "MEDIAN_COV_vs_P_logFC",
    "MEDIAN_COV_vs_P_FDR",
    "MAX_COV_vs_H_FDR",
    "MEDIAN_MAX_COV_vs_H_same_direction",
    "MAX_sensitivity_status_for_primary_COV_vs_H_candidate",
]

m_ann = m_candidates[m_annot_cols].copy()
m_ann = m_ann.rename(columns={
    "feature_id":"mRNA_id",
    "COV_vs_H_logFC":"mRNA_COV_vs_H_logFC",
    "COV_vs_H_FDR":"mRNA_COV_vs_H_FDR",
    "COV_vs_H_strict_priority":"mRNA_COV_vs_H_strict_priority",
    "P_vs_H_logFC":"mRNA_P_vs_H_logFC",
    "P_vs_H_FDR":"mRNA_P_vs_H_FDR",
    "COV_vs_P_logFC":"mRNA_COV_vs_P_logFC",
    "COV_vs_P_FDR":"mRNA_COV_vs_P_FDR",
})

mi_ann = mi_candidates[mi_annot_cols].copy()
mi_ann = mi_ann.rename(columns={
    "feature_id":"miRNA_id",
    "MEDIAN_COV_vs_H_logFC":"miRNA_COV_vs_H_logFC",
    "MEDIAN_COV_vs_H_FDR":"miRNA_COV_vs_H_FDR",
    "MEDIAN_COV_vs_H_strict_priority":"miRNA_COV_vs_H_strict_priority",
    "MEDIAN_P_vs_H_logFC":"miRNA_P_vs_H_logFC",
    "MEDIAN_P_vs_H_FDR":"miRNA_P_vs_H_FDR",
    "MEDIAN_COV_vs_P_logFC":"miRNA_COV_vs_P_logFC",
    "MEDIAN_COV_vs_P_FDR":"miRNA_COV_vs_P_FDR",
    "MAX_COV_vs_H_FDR":"miRNA_MAX_COV_vs_H_FDR",
    "MEDIAN_MAX_COV_vs_H_same_direction":"miRNA_MEDIAN_MAX_COV_vs_H_same_direction",
    "MAX_sensitivity_status_for_primary_COV_vs_H_candidate":
        "miRNA_MAX_sensitivity_status",
})

candidate_df = candidate_df.merge(
    m_ann,
    on="mRNA_id",
    how="left",
    validate="many_to_one",
)
candidate_df = candidate_df.merge(
    mi_ann,
    on="miRNA_id",
    how="left",
    validate="many_to_one",
)

candidate_df.to_csv(
    CANDIDATE_ASSOCIATIONS,
    index=False,
    compression="gzip",
    float_format="%.17g",
)

n_candidate = int(candidate_df.shape[0])
n_pos_candidate = int(
    np.sum(candidate_df["partial_spearman_rho"].to_numpy(dtype=np.float64) > 0)
)
n_neg_candidate = int(
    np.sum(candidate_df["partial_spearman_rho"].to_numpy(dtype=np.float64) < 0)
)

put("FULL_DATA_ASSOCIATION_CANDIDATES", n_candidate)
put("FULL_DATA_POSITIVE_CANDIDATES", n_pos_candidate)
put("FULL_DATA_NEGATIVE_CANDIDATES", n_neg_candidate)


# ------------------------------------------------------------
# F. Summary metrics
# ------------------------------------------------------------
fdr_only = fdr <= FDR_THRESHOLD
rho_only = np.abs(rho) >= ABS_RHO_THRESHOLD

summary_df = pd.DataFrame([
    {
        "metric":"all_primary_pairs",
        "count":N_PAIRS,
        "fraction":1.0,
    },
    {
        "metric":"BH_FDR_le_0.05",
        "count":int(np.sum(fdr_only)),
        "fraction":float(np.mean(fdr_only)),
    },
    {
        "metric":"abs_rho_ge_0.30",
        "count":int(np.sum(rho_only)),
        "fraction":float(np.mean(rho_only)),
    },
    {
        "metric":"full_data_candidates_FDR_le_0.05_and_abs_rho_ge_0.30",
        "count":n_candidate,
        "fraction":float(n_candidate / N_PAIRS),
    },
    {
        "metric":"full_data_positive_candidates",
        "count":n_pos_candidate,
        "fraction":float(n_pos_candidate / N_PAIRS),
    },
    {
        "metric":"full_data_negative_candidates",
        "count":n_neg_candidate,
        "fraction":float(n_neg_candidate / N_PAIRS),
    },
])

summary_df.to_csv(ASSOCIATION_SUMMARY,index=False)

put("PAIRS_FDR_LE_0_05", int(np.sum(fdr_only)))
put("PAIRS_ABS_RHO_GE_0_30", int(np.sum(rho_only)))
put("MIN_PVALUE", float(np.min(pvalue)))
put("MIN_FDR", float(np.min(fdr)))
put("MAX_ABS_RHO", float(np.max(np.abs(rho))))
put("MEDIAN_ABS_RHO", float(np.median(np.abs(rho))))


# ------------------------------------------------------------
# G. Freeze execution specification
# ------------------------------------------------------------
spec_lines = [
    "GSE243219_D7A_PRIMARY_ASSOCIATION_EXECUTION_SPECIFICATION",
    "PRIMARY_ASSOCIATION_COHORT_SUBJECTS=50",
    "PRIMARY_ASSOCIATION_COVID19=35",
    "PRIMARY_ASSOCIATION_HEALTHY=15",
    "PRIMARY_ASSOCIATION_MRNA_FEATURES=8505",
    "PRIMARY_ASSOCIATION_MIRNA_FEATURES=41",
    "PRIMARY_ASSOCIATION_PAIR_COUNT=348705",
    "EXPRESSION_INPUT=TMM_NORMALIZED_CPM",
    "ASSOCIATION_STATISTIC=PARTIAL_SPEARMAN",
    "PARTIAL_SPEARMAN_RANK_METHOD=AVERAGE_TIES",
    "PARTIAL_SPEARMAN_CONTROL_VARIABLE=COVID19_BINARY_DISEASE_STATUS",
    "PARTIAL_SPEARMAN_RESIDUALIZATION=OLS_ON_INTERCEPT_PLUS_DISEASE_INDICATOR",
    "PARTIAL_SPEARMAN_CORRELATION=PEARSON_OF_RANK_RESIDUALS",
    "PARTIAL_SPEARMAN_TWO_SIDED_TEST=YES",
    "PARTIAL_SPEARMAN_DF=47",
    "MULTIPLE_TESTING=BENJAMINI_HOCHBERG",
    "MULTIPLE_TESTING_PAIR_FAMILY=348705",
    "FULL_DATA_ASSOCIATION_FDR_THRESHOLD=0.05",
    "FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD=0.30",
    "FULL_DATA_ASSOCIATION_CANDIDATE_RULE=FDR_LE_0.05_AND_ABS_RHO_GE_0.30",
    "POSITIVE_ASSOCIATIONS_RETAINED=YES",
    "NEGATIVE_ASSOCIATIONS_RETAINED=YES",
    "CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO",
    "FULL_RESULT_ROWS_RETAINED=YES",
    "BOOTSTRAP_EXECUTED_IN_D7A=NO",
    "TARGET_EVIDENCE_INTEGRATION_EXECUTED_IN_D7A=NO",
    "NETWORK_EXECUTED_IN_D7A=NO",
    "ACLA_EXECUTED_IN_D7A=NO",
]
EXECUTION_SPEC.write_text(
    "\n".join(spec_lines) + "\n",
    encoding="utf-8",
)

put("PRIMARY_ASSOCIATION_EXECUTION_COMPLETE", "YES")
put("BOOTSTRAP_EXECUTED", "NO")
put("TARGET_EVIDENCE_INTEGRATION_EXECUTED", "NO")
put("NETWORK_EXECUTED", "NO")
put("ACLA_EXECUTED", "NO")
put("READY_FOR_D7B_BOOTSTRAP_STABILITY_EXECUTION", "YES")
put("NEXT_PHASE", "D7B_BOOTSTRAP_STABILITY_EXECUTION")

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
    $FeatureUniverse,
    $MrnaCandidates,
    $MirnaCandidates,
    $ImplementationAudit,
    $AllAssociations,
    $CandidateAssociations,
    $AssociationSummary,
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
        Write-Host '=== D7A PYTHON STDERR ==='
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
    throw ('D7A_PYTHON_FAILED exit={0} full_traceback={1}' -f `
        $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D7A_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('D7A_INPUT_INTEGRITY','PASS'),
    @('REAL_PARTIAL_SPEARMAN_MATRIX_COMPUTED','YES'),
    @('REAL_ASSOCIATION_PVALUES_COMPUTED','YES'),
    @('BH_FDR_COMPUTED_ACROSS_ALL_PAIRS','YES'),
    @('VECTORIZED_DIRECT_PAIR_AUDIT','PASS'),
    @('VECTORIZED_DIRECT_AUDIT_PAIRS','64'),
    @('ALL_348705_ASSOCIATION_ROWS_SAVED','YES'),
    @('ALL_ASSOCIATION_ROUNDTRIP_INTEGRITY','PASS'),
    @('PRIMARY_ASSOCIATION_EXECUTION_COMPLETE','YES'),
    @('BOOTSTRAP_EXECUTED','NO'),
    @('TARGET_EVIDENCE_INTEGRATION_EXECUTED','NO'),
    @('NETWORK_EXECUTED','NO'),
    @('ACLA_EXECUTED','NO'),
    @('READY_FOR_D7B_BOOTSTRAP_STABILITY_EXECUTION','YES'),
    @('NEXT_PHASE','D7B_BOOTSTRAP_STABILITY_EXECUTION')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D7A_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 3. Decision
# ------------------------------------------------------------
@(
    'GSE243219_D7A_DECISION',
    'PHASE_D7A_STATUS=PASS',
    'MODE=FIRST_AUTHORIZED_REAL_ASSOCIATION_EXECUTION',
    'D3B_EXPRESSION_CERTIFICATION_GATE=PASS',
    'D3B_OUTPUTS_RECERTIFIED=18/18',
    'D6B_SELECTION_CERTIFICATION_GATE=PASS',
    'D6B_OUTPUTS_RECERTIFIED=11/11',
    'D7_V2_DESIGN_CERTIFICATION_GATE=PASS',
    'D7_V2_OUTPUTS_RECERTIFIED=10/10',
    'PRIMARY_ASSOCIATION_SUBJECTS=50',
    'PRIMARY_ASSOCIATION_COVID19=35',
    'PRIMARY_ASSOCIATION_HEALTHY=15',
    'PRIMARY_ASSOCIATION_MRNA_FEATURES=8505',
    'PRIMARY_ASSOCIATION_MIRNA_FEATURES=41',
    'PRIMARY_ASSOCIATION_PAIR_COUNT=348705',
    'PRIMARY_ASSOCIATION_STATISTIC=PARTIAL_SPEARMAN_CONTROL_DISEASE_STATUS',
    'PARTIAL_SPEARMAN_DF=47',
    'MULTIPLE_TESTING=BH_ACROSS_ALL_348705_PRIMARY_PAIRS',
    'FULL_DATA_ASSOCIATION_FDR_THRESHOLD=0.05',
    'FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD=0.30',
    'REAL_ASSOCIATION_EXECUTED=YES',
    'REAL_ASSOCIATION_PVALUES_COMPUTED=YES',
    'BH_FDR_COMPUTED=YES',
    ('PAIRS_FDR_LE_0_05={0}' -f (Cap 'PAIRS_FDR_LE_0_05')),
    ('PAIRS_ABS_RHO_GE_0_30={0}' -f (Cap 'PAIRS_ABS_RHO_GE_0_30')),
    ('FULL_DATA_ASSOCIATION_CANDIDATES={0}' -f (Cap 'FULL_DATA_ASSOCIATION_CANDIDATES')),
    ('FULL_DATA_POSITIVE_CANDIDATES={0}' -f (Cap 'FULL_DATA_POSITIVE_CANDIDATES')),
    ('FULL_DATA_NEGATIVE_CANDIDATES={0}' -f (Cap 'FULL_DATA_NEGATIVE_CANDIDATES')),
    ('MIN_PVALUE={0}' -f (Cap 'MIN_PVALUE')),
    ('MIN_FDR={0}' -f (Cap 'MIN_FDR')),
    ('MAX_ABS_RHO={0}' -f (Cap 'MAX_ABS_RHO')),
    ('MEDIAN_ABS_RHO={0}' -f (Cap 'MEDIAN_ABS_RHO')),
    'VECTORIZED_DIRECT_PAIR_AUDIT=PASS',
    ('VECTORIZED_DIRECT_RHO_MAX_ABS_DIFF={0}' -f (Cap 'VECTORIZED_DIRECT_RHO_MAX_ABS_DIFF')),
    ('VECTORIZED_DIRECT_PVALUE_MAX_ABS_DIFF={0}' -f (Cap 'VECTORIZED_DIRECT_PVALUE_MAX_ABS_DIFF')),
    'ALL_348705_ASSOCIATION_ROWS_SAVED=YES',
    'ALL_ASSOCIATION_ROUNDTRIP_INTEGRITY=PASS',
    'CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO',
    'BOOTSTRAP_EXECUTED=NO',
    'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D7B_BOOTSTRAP_STABILITY_EXECUTION=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D7B_BOOTSTRAP_STABILITY_EXECUTION',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Manifest
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $ImplementationAudit,
    $AllAssociations,
    $CandidateAssociations,
    $AssociationSummary,
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
        throw ('D7A_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p
    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D7ASHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D7A SUMMARY ===',
    'PHASE_D7A_STATUS=PASS',
    'MODE=FIRST_AUTHORIZED_REAL_ASSOCIATION_EXECUTION',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    ('SCIPY_VERSION={0}' -f $ScipyVersion),
    'D3B_EXPRESSION_CERTIFICATION_GATE=PASS',
    'D6B_SELECTION_CERTIFICATION_GATE=PASS',
    'D7_V2_DESIGN_CERTIFICATION_GATE=PASS',
    'PRIMARY_ASSOCIATION_SUBJECTS=50',
    'PRIMARY_ASSOCIATION_COVID19=35',
    'PRIMARY_ASSOCIATION_HEALTHY=15',
    'PRIMARY_ASSOCIATION_MRNA_FEATURES=8505',
    'PRIMARY_ASSOCIATION_MIRNA_FEATURES=41',
    'PRIMARY_ASSOCIATION_PAIR_COUNT=348705',
    'PRIMARY_ASSOCIATION_STATISTIC=PARTIAL_SPEARMAN_CONTROL_DISEASE_STATUS',
    'PARTIAL_SPEARMAN_DF=47',
    'MULTIPLE_TESTING=BH_ACROSS_ALL_348705_PRIMARY_PAIRS',
    'FULL_DATA_ASSOCIATION_FDR_THRESHOLD=0.05',
    'FULL_DATA_ASSOCIATION_ABS_RHO_THRESHOLD=0.30',
    'REAL_ASSOCIATION_EXECUTED=YES',
    'REAL_ASSOCIATION_PVALUES_COMPUTED=YES',
    'BH_FDR_COMPUTED=YES',
    ('PAIRS_FDR_LE_0_05={0}' -f (Cap 'PAIRS_FDR_LE_0_05')),
    ('PAIRS_ABS_RHO_GE_0_30={0}' -f (Cap 'PAIRS_ABS_RHO_GE_0_30')),
    ('FULL_DATA_ASSOCIATION_CANDIDATES={0}' -f (Cap 'FULL_DATA_ASSOCIATION_CANDIDATES')),
    ('FULL_DATA_POSITIVE_CANDIDATES={0}' -f (Cap 'FULL_DATA_POSITIVE_CANDIDATES')),
    ('FULL_DATA_NEGATIVE_CANDIDATES={0}' -f (Cap 'FULL_DATA_NEGATIVE_CANDIDATES')),
    ('MIN_PVALUE={0}' -f (Cap 'MIN_PVALUE')),
    ('MIN_FDR={0}' -f (Cap 'MIN_FDR')),
    ('MAX_ABS_RHO={0}' -f (Cap 'MAX_ABS_RHO')),
    ('MEDIAN_ABS_RHO={0}' -f (Cap 'MEDIAN_ABS_RHO')),
    ('MRNA_RANK_RESIDUAL_ORTHOGONALITY_MAX_ABS={0}' -f (Cap 'MRNA_RANK_RESIDUAL_ORTHOGONALITY_MAX_ABS')),
    ('MIRNA_RANK_RESIDUAL_ORTHOGONALITY_MAX_ABS={0}' -f (Cap 'MIRNA_RANK_RESIDUAL_ORTHOGONALITY_MAX_ABS')),
    'VECTORIZED_DIRECT_PAIR_AUDIT=PASS',
    ('VECTORIZED_DIRECT_AUDIT_PAIRS={0}' -f (Cap 'VECTORIZED_DIRECT_AUDIT_PAIRS')),
    ('VECTORIZED_DIRECT_RHO_MAX_ABS_DIFF={0}' -f (Cap 'VECTORIZED_DIRECT_RHO_MAX_ABS_DIFF')),
    ('VECTORIZED_DIRECT_PVALUE_MAX_ABS_DIFF={0}' -f (Cap 'VECTORIZED_DIRECT_PVALUE_MAX_ABS_DIFF')),
    'ALL_348705_ASSOCIATION_ROWS_SAVED=YES',
    'ALL_ASSOCIATION_ROUNDTRIP_INTEGRITY=PASS',
    'CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO',
    'BOOTSTRAP_EXECUTED=NO',
    'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'PRIMARY_ASSOCIATION_EXECUTION_COMPLETE=YES',
    'READY_FOR_D7B_BOOTSTRAP_STABILITY_EXECUTION=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D7B_BOOTSTRAP_STABILITY_EXECUTION',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D7A_IMPLEMENTATION_AUDIT={0}' -f $ImplementationAudit)
Write-Host ('D7A_ALL_ASSOCIATIONS={0}' -f $AllAssociations)
Write-Host ('D7A_CANDIDATE_ASSOCIATIONS={0}' -f $CandidateAssociations)
Write-Host ('D7A_ASSOCIATION_SUMMARY={0}' -f $AssociationSummary)
Write-Host ('D7A_EXECUTION_SPEC={0}' -f $ExecutionSpec)
Write-Host ('D7A_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D7A_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D7A=PASS'
Write-Host 'STOP=YES'
