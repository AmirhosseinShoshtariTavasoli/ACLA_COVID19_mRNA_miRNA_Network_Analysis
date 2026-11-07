$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D7C — ASSOCIATION-STABILITY AUDIT
#              + STABLE EDGE-SET FREEZE
#
# Purpose:
#   Independently re-audit the complete D7B-V2 bootstrap evidence,
#   recompute support/stability calls from the saved 500x11,576
#   bootstrap-rho matrix, verify the derived stability tables,
#   and freeze the stable mRNA-miRNA association edge set.
#
# Frozen upstream rule (NO CHANGES):
#   Full-data candidate:
#       D7A BH FDR <= 0.05
#       AND abs(full-data partial Spearman rho) >= 0.30
#
#   Bootstrap:
#       500 paired stratified subject bootstraps
#       seed = 243219
#       35 COVID + 15 HEALTHY draws with replacement
#
#   Bootstrap support:
#       same sign as full-data rho
#       AND abs(bootstrap rho) >= 0.30
#
#   Stable edge:
#       support frequency >= 0.80 over all 500 replicates
#
# D7C is AUDIT/FREEZE ONLY.
# NO thresholds are changed.
# NO association is re-fit on the biological data.
# NO target evidence integration.
# NO network construction.
# NO A-CLA.
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D6Root = Join-Path $Project '06_ASSOCIATION_AND_STABILITY'

$D7Run = Join-Path $D6Root 'D7_V2_ASSOCIATION_STABILITY_PREFLIGHT_20260905_104708'
$D7Manifest = Join-Path $D7Run 'D7_OUTPUT_SHA256_MANIFEST.csv'
$D7FrozenDesign = Join-Path $D7Run 'D7_FROZEN_ASSOCIATION_AND_STABILITY_DESIGN.txt'
$D7Cohort = Join-Path $D7Run 'D7_PRIMARY_ASSOCIATION_COHORT_50.csv'

$D7ARun = Join-Path $D6Root 'D7A_PRIMARY_ASSOCIATION_EXECUTION_20260905_105352'
$D7AManifest = Join-Path $D7ARun 'D7A_OUTPUT_SHA256_MANIFEST.csv'
$D7AReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D7A_20260905_105352\PHASE_D7A_SUMMARY.txt'
$D7AAll = Join-Path $D7ARun 'D7A_ALL_348705_PRIMARY_ASSOCIATIONS.csv.gz'
$D7ACandidates = Join-Path $D7ARun 'D7A_FULL_DATA_ASSOCIATION_CANDIDATES.csv.gz'

$D7BRun = Join-Path $D6Root 'D7B_V2_BOOTSTRAP_STABILITY_EXECUTION_20260905_111643'
$D7BManifest = Join-Path $D7BRun 'D7B_OUTPUT_SHA256_MANIFEST.csv'
$D7BReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D7B_V2_20260905_111643\PHASE_D7B_SUMMARY.txt'
$D7BNpz = Join-Path $D7BRun 'D7B_BOOTSTRAP_RHO_AND_DRAW_AUDIT_500x11576.npz'
$D7BCandidateStability = Join-Path $D7BRun 'D7B_ALL_11576_CANDIDATE_STABILITY.csv.gz'
$D7BStableEdges = Join-Path $D7BRun 'D7B_STABLE_ASSOCIATION_EDGES.csv.gz'
$D7BDirectAudit = Join-Path $D7BRun 'D7B_BOOTSTRAP_DIRECT_PAIR_AUDIT.csv'
$D7BExecutionSpec = Join-Path $D7BRun 'D7B_V2_BOOTSTRAP_EXECUTION_SPECIFICATION.txt'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D6Root ('D7C_ASSOCIATION_STABILITY_AUDIT_EDGE_FREEZE_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D7C_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D7C_ASSOCIATION_STABILITY_AUDIT_AND_EDGE_FREEZE.py'
$BootstrapReaudit = Join-Path $RunDir 'D7C_BOOTSTRAP_EVIDENCE_REAUDIT.csv'
$ThresholdAudit = Join-Path $RunDir 'D7C_STABILITY_THRESHOLD_AUDIT.csv'
$StableSetAudit = Join-Path $RunDir 'D7C_STABLE_EDGE_SET_AUDIT.csv'
$FrozenStableEdges = Join-Path $RunDir 'D7C_FROZEN_STABLE_ASSOCIATION_EDGES.csv.gz'
$FrozenSpec = Join-Path $RunDir 'D7C_FROZEN_STABLE_EDGE_SET_SPECIFICATION.txt'
$ResultJson = Join-Path $RunDir 'D7C_RESULT.json'

$PythonStdout = Join-Path $RunDir 'D7C_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D7C_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D7C_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D7C_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D7C_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D7C_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D7C — ASSOCIATION-STABILITY AUDIT + EDGE FREEZE ==='
Write-Host 'MODE=INDEPENDENT_AUDIT_AND_FREEZE_ONLY'
Write-Host 'FULL_DATA_CANDIDATES_EXPECTED=11576'
Write-Host 'STABLE_EDGES_EXPECTED=11531'
Write-Host 'UNSTABLE_EDGES_EXPECTED=45'
Write-Host 'STABILITY_THRESHOLD=0.80'
Write-Host 'BOOTSTRAP_REPLICATES=500'
Write-Host 'BOOTSTRAP_SUPPORT_EVENT=SAME_SIGN_AND_ABS_RHO_GE_0.30'
Write-Host 'THRESHOLD_CHANGED=NO'
Write-Host 'ASSOCIATION_REEXECUTED=NO'
Write-Host 'BOOTSTRAP_REEXECUTED=NO'
Write-Host 'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $D7Manifest,$D7FrozenDesign,$D7Cohort,
    $D7AManifest,$D7AReport,$D7AAll,$D7ACandidates,
    $D7BManifest,$D7BReport,$D7BNpz,$D7BCandidateStability,
    $D7BStableEdges,$D7BDirectAudit,$D7BExecutionSpec
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D7C_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D7CSHA256 {
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
        $hash = Get-D7CSHA256 $r.full_path

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
Recertify-Manifest -ManifestPath $D7Manifest -ExpectedRows 10 -Label 'D7_V2'
Write-Host 'D7_V2_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D7AManifest -ExpectedRows 11 -Label 'D7A'
Write-Host 'D7A_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D7BManifest -ExpectedRows 12 -Label 'D7B_V2'
Write-Host 'D7B_V2_CERTIFICATION_GATE=PASS'

$d7Frozen = Get-Content -LiteralPath $D7FrozenDesign -Raw
foreach ($tok in @(
    'BOOTSTRAP_REPLICATES=500',
    'BOOTSTRAP_RANDOM_SEED=243219',
    'BOOTSTRAP_STRATIFIED_BY_DISEASE=YES',
    'BOOTSTRAP_COVID_DRAWS_PER_REPLICATE=35',
    'BOOTSTRAP_HEALTHY_DRAWS_PER_REPLICATE=15',
    'BOOTSTRAP_MRNA_MIRNA_USE_IDENTICAL_SUBJECT_DRAW=YES',
    'BOOTSTRAP_SELECTION_EVENT=SAME_SIGN_AND_ABS_RHO_GE_0.30',
    'STABLE_EDGE_BOOTSTRAP_FREQUENCY_THRESHOLD=0.80',
    'CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO'
)) {
    if (-not $d7Frozen.Contains($tok)) {
        throw ('D7_FROZEN_DESIGN_TOKEN_MISSING={0}' -f $tok)
    }
}

$d7a = Get-Content -LiteralPath $D7AReport -Raw
foreach ($tok in @(
    'PHASE_D7A_STATUS=PASS',
    'FULL_DATA_ASSOCIATION_CANDIDATES=11576',
    'FULL_DATA_POSITIVE_CANDIDATES=5255',
    'FULL_DATA_NEGATIVE_CANDIDATES=6321',
    'ALL_348705_ASSOCIATION_ROWS_SAVED=YES',
    'ALL_ASSOCIATION_ROUNDTRIP_INTEGRITY=PASS'
)) {
    if (-not $d7a.Contains($tok)) {
        throw ('D7A_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$d7b = Get-Content -LiteralPath $D7BReport -Raw
foreach ($tok in @(
    'PHASE_D7B_V2_STATUS=PASS',
    'BOOTSTRAP_REPLICATES=500',
    'BOOTSTRAP_EXECUTED=YES',
    'BOOTSTRAP_FULL_EVIDENCE_SAVED=YES',
    'BOOTSTRAP_NPZ_ROUNDTRIP_INTEGRITY=PASS',
    'STABLE_ASSOCIATION_EDGES=11531',
    'STABLE_POSITIVE_ASSOCIATION_EDGES=5225',
    'STABLE_NEGATIVE_ASSOCIATION_EDGES=6306',
    'CANDIDATES_WITH_ANY_UNDEFINED_BOOTSTRAP_RHO=0',
    'TOTAL_UNDEFINED_BOOTSTRAP_PAIR_REPLICATES=0',
    'MIN_BOOTSTRAP_SELECTION_FREQUENCY=0.758',
    'MEDIAN_BOOTSTRAP_SELECTION_FREQUENCY=0.928',
    'MAX_BOOTSTRAP_SELECTION_FREQUENCY=1.0'
)) {
    if (-not $d7b.Contains($tok)) {
        throw ('D7B_V2_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$PythonExe = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING\D2D_PREFLIGHT_20260904_195001\venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw ('PYTHON_EXECUTABLE_MISSING={0}' -f $PythonExe)
}

$PythonVersion = & $PythonExe -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$PandasVersion = & $PythonExe -c "import pandas; print(pandas.__version__)"
$NumpyVersion = & $PythonExe -c "import numpy; print(numpy.__version__)"

Write-Host ('PYTHON_VERSION={0}' -f $PythonVersion)
Write-Host ('PANDAS_VERSION={0}' -f $PandasVersion)
Write-Host ('NUMPY_VERSION={0}' -f $NumpyVersion)

# ------------------------------------------------------------
# 2. Python independent audit
# ------------------------------------------------------------
$PythonCode = @'
import json
import shutil
import sys
from pathlib import Path

import numpy as np
import pandas as pd


D7_COHORT = Path(sys.argv[1])
D7A_ALL = Path(sys.argv[2])
D7A_CAND = Path(sys.argv[3])
D7B_NPZ = Path(sys.argv[4])
D7B_CAND_STAB = Path(sys.argv[5])
D7B_STABLE = Path(sys.argv[6])
D7B_DIRECT_AUDIT = Path(sys.argv[7])

BOOT_REAUDIT = Path(sys.argv[8])
THRESHOLD_AUDIT = Path(sys.argv[9])
STABLE_SET_AUDIT = Path(sys.argv[10])
FROZEN_STABLE = Path(sys.argv[11])
FROZEN_SPEC = Path(sys.argv[12])
RESULT_JSON = Path(sys.argv[13])


N_CAND = 11576
N_BOOT = 500
RHO_THRESHOLD = 0.30
STABILITY_THRESHOLD = 0.80
EXPECTED_STABLE = 11531
EXPECTED_UNSTABLE = 45
EXPECTED_STABLE_POS = 5225
EXPECTED_STABLE_NEG = 6306

results = {}


def put(k, v):
    results[k] = v
    print(f"{k}={v}")


# ------------------------------------------------------------
# A. Load source tables
# ------------------------------------------------------------
cohort = pd.read_csv(D7_COHORT)

all_assoc = pd.read_csv(
    D7A_ALL,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
cand = pd.read_csv(
    D7A_CAND,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
cand_stab = pd.read_csv(
    D7B_CAND_STAB,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
stable = pd.read_csv(
    D7B_STABLE,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
direct_audit = pd.read_csv(D7B_DIRECT_AUDIT)

if cohort.shape[0] != 50:
    raise RuntimeError(
        f"COHORT_ROWS_CHANGED observed={cohort.shape[0]}"
    )
if cohort["disease_state"].value_counts().to_dict() != {
    "COVID19":35,
    "HEALTHY":15,
}:
    raise RuntimeError("COHORT_GROUP_COUNTS_CHANGED")

if all_assoc.shape[0] != 348705:
    raise RuntimeError(
        f"ALL_ASSOCIATION_ROWS_CHANGED observed={all_assoc.shape[0]}"
    )
if cand.shape[0] != N_CAND:
    raise RuntimeError(
        f"CANDIDATE_ROWS_CHANGED observed={cand.shape[0]}"
    )
if cand_stab.shape[0] != N_CAND:
    raise RuntimeError(
        f"CANDIDATE_STABILITY_ROWS_CHANGED observed={cand_stab.shape[0]}"
    )
if stable.shape[0] != EXPECTED_STABLE:
    raise RuntimeError(
        f"STABLE_ROWS_CHANGED observed={stable.shape[0]}"
    )
if direct_audit.shape[0] != 32:
    raise RuntimeError(
        f"DIRECT_AUDIT_ROWS_CHANGED observed={direct_audit.shape[0]}"
    )
if not direct_audit["status"].astype(str).eq("PASS").all():
    raise RuntimeError("D7B_DIRECT_AUDIT_NOT_ALL_PASS")

put("D7C_SOURCE_TABLE_INTEGRITY", "PASS")


# ------------------------------------------------------------
# B. Verify D7A candidate subset identity/order
# ------------------------------------------------------------
pair_idx = cand["pair_index_1based"].to_numpy(dtype=np.int64)

if len(np.unique(pair_idx)) != N_CAND:
    raise RuntimeError("CANDIDATE_PAIR_INDEX_NOT_UNIQUE")

subset = all_assoc.iloc[pair_idx - 1, :]

for col in ["pair_index_1based","mRNA_id","miRNA_id"]:
    if subset[col].astype(str).tolist() != cand[col].astype(str).tolist():
        raise RuntimeError(
            f"D7A_CANDIDATE_SUBSET_IDENTITY_MISMATCH column={col}"
        )

for col in ["partial_spearman_rho","PValue","FDR"]:
    if not np.allclose(
        subset[col].to_numpy(dtype=np.float64),
        cand[col].to_numpy(dtype=np.float64),
        rtol=0.0,
        atol=1e-15,
    ):
        raise RuntimeError(
            f"D7A_CANDIDATE_SUBSET_VALUE_MISMATCH column={col}"
        )

if np.any(
    cand["FDR"].to_numpy(dtype=np.float64) > 0.05 + 1e-15
):
    raise RuntimeError("D7A_CANDIDATE_FDR_RULE_VIOLATION")

if np.any(
    np.abs(
        cand["partial_spearman_rho"].to_numpy(dtype=np.float64)
    ) < 0.30 - 1e-15
):
    raise RuntimeError("D7A_CANDIDATE_RHO_RULE_VIOLATION")

put("D7A_FULL_DATA_CANDIDATE_SET_REAUDIT", "PASS")


# ------------------------------------------------------------
# C. Load complete D7B bootstrap evidence
# ------------------------------------------------------------
with np.load(D7B_NPZ, allow_pickle=False) as z:
    required = {
        "bootstrap_rho",
        "draw_indices_0based",
        "candidate_pair_index_1based",
        "full_data_rho",
        "bootstrap_seed",
    }

    missing = sorted(required - set(z.files))
    if missing:
        raise RuntimeError(
            f"BOOTSTRAP_NPZ_ARRAYS_MISSING={missing}"
        )

    boot_rho = z["bootstrap_rho"].astype(np.float64,copy=False)
    draws = z["draw_indices_0based"].astype(np.int64,copy=False)
    npz_pair_idx = z["candidate_pair_index_1based"].astype(
        np.int64,copy=False
    )
    npz_full_rho = z["full_data_rho"].astype(np.float64,copy=False)
    seed = int(z["bootstrap_seed"][0])

if boot_rho.shape != (N_BOOT,N_CAND):
    raise RuntimeError(
        f"BOOTSTRAP_RHO_SHAPE_CHANGED observed={boot_rho.shape}"
    )
if draws.shape != (N_BOOT,50):
    raise RuntimeError(
        f"BOOTSTRAP_DRAW_SHAPE_CHANGED observed={draws.shape}"
    )
if seed != 243219:
    raise RuntimeError(
        f"BOOTSTRAP_SEED_CHANGED observed={seed}"
    )

if not np.array_equal(npz_pair_idx,pair_idx):
    raise RuntimeError("BOOTSTRAP_NPZ_PAIR_INDEX_ORDER_MISMATCH")

full_rho = cand["partial_spearman_rho"].to_numpy(dtype=np.float64)

if not np.allclose(
    npz_full_rho,
    full_rho,
    rtol=0.0,
    atol=0.0,
):
    raise RuntimeError("BOOTSTRAP_NPZ_FULL_RHO_MISMATCH")

g = cohort["disease_indicator_COVID19"].to_numpy(dtype=np.int64)

if not np.all(g[draws[:,:35]] == 1):
    raise RuntimeError("BOOTSTRAP_COVID_STRATIFICATION_REAUDIT_FAILED")
if not np.all(g[draws[:,35:]] == 0):
    raise RuntimeError("BOOTSTRAP_HEALTHY_STRATIFICATION_REAUDIT_FAILED")

put("BOOTSTRAP_NPZ_STRUCTURAL_REAUDIT", "PASS")
put("BOOTSTRAP_DRAW_STRATIFICATION_REAUDIT", "PASS")


# ------------------------------------------------------------
# D. Independently recompute every stability quantity
# ------------------------------------------------------------
finite = np.isfinite(boot_rho)
finite_count = np.sum(finite,axis=0)

full_sign = np.sign(full_rho)[None,:]
boot_sign = np.sign(boot_rho)

same_sign = finite & (boot_sign == full_sign)
support = (
    same_sign
    & (np.abs(boot_rho) >= RHO_THRESHOLD)
)

support_count = np.sum(support,axis=0)
same_sign_count = np.sum(same_sign,axis=0)

finite_frequency = finite_count / float(N_BOOT)
same_sign_frequency_all = same_sign_count / float(N_BOOT)
selection_frequency = support_count / float(N_BOOT)

same_sign_frequency_finite = np.divide(
    same_sign_count,
    finite_count,
    out=np.zeros(N_CAND,dtype=np.float64),
    where=finite_count > 0,
)

recomputed_stable = selection_frequency >= STABILITY_THRESHOLD

# Check every stored derived column.
int_checks = {
    "bootstrap_finite_rho_count": finite_count,
    "bootstrap_same_sign_count": same_sign_count,
    "bootstrap_support_count_same_sign_abs_rho_ge_0_30":
        support_count,
}

for col, expected in int_checks.items():
    observed = cand_stab[col].to_numpy(dtype=np.int64)
    if not np.array_equal(observed,expected):
        raise RuntimeError(
            f"CANDIDATE_STABILITY_INTEGER_COLUMN_MISMATCH={col}"
        )

float_checks = {
    "bootstrap_finite_rho_frequency": finite_frequency,
    "bootstrap_same_sign_frequency_all_500": same_sign_frequency_all,
    "bootstrap_same_sign_frequency_among_finite":
        same_sign_frequency_finite,
    "bootstrap_selection_frequency": selection_frequency,
}

for col, expected in float_checks.items():
    observed = cand_stab[col].to_numpy(dtype=np.float64)
    if not np.allclose(
        observed,
        expected,
        rtol=0.0,
        atol=1e-15,
    ):
        raise RuntimeError(
            f"CANDIDATE_STABILITY_FLOAT_COLUMN_MISMATCH={col}"
        )

observed_stable = cand_stab[
    "stable_edge_frequency_ge_0_80"
].astype(str).eq("YES").to_numpy()

if not np.array_equal(observed_stable,recomputed_stable):
    raise RuntimeError("CANDIDATE_STABLE_FLAG_MISMATCH")

n_stable = int(np.sum(recomputed_stable))
n_unstable = int(N_CAND - n_stable)
n_stable_pos = int(
    np.sum(
        recomputed_stable & (full_rho > 0)
    )
)
n_stable_neg = int(
    np.sum(
        recomputed_stable & (full_rho < 0)
    )
)

if n_stable != EXPECTED_STABLE:
    raise RuntimeError(
        f"STABLE_EDGE_COUNT_RECOMPUTE_CHANGED observed={n_stable}"
    )
if n_unstable != EXPECTED_UNSTABLE:
    raise RuntimeError(
        f"UNSTABLE_EDGE_COUNT_RECOMPUTE_CHANGED observed={n_unstable}"
    )
if n_stable_pos != EXPECTED_STABLE_POS:
    raise RuntimeError(
        f"STABLE_POSITIVE_COUNT_RECOMPUTE_CHANGED observed={n_stable_pos}"
    )
if n_stable_neg != EXPECTED_STABLE_NEG:
    raise RuntimeError(
        f"STABLE_NEGATIVE_COUNT_RECOMPUTE_CHANGED observed={n_stable_neg}"
    )

undefined_pair_replicates = int(np.sum(~finite))
undefined_candidates = int(np.sum(np.any(~finite,axis=0)))

if undefined_pair_replicates != 0 or undefined_candidates != 0:
    raise RuntimeError(
        f"UNDEFINED_BOOTSTRAP_RHO_RECOMPUTE_NONZERO "
        f"pairs={undefined_pair_replicates} "
        f"candidates={undefined_candidates}"
    )

min_freq = float(np.min(selection_frequency))
median_freq = float(np.median(selection_frequency))
max_freq = float(np.max(selection_frequency))

if abs(min_freq - 0.758) > 1e-15:
    raise RuntimeError(
        f"MIN_SELECTION_FREQUENCY_CHANGED observed={min_freq}"
    )
if abs(median_freq - 0.928) > 1e-15:
    raise RuntimeError(
        f"MEDIAN_SELECTION_FREQUENCY_CHANGED observed={median_freq}"
    )
if abs(max_freq - 1.0) > 1e-15:
    raise RuntimeError(
        f"MAX_SELECTION_FREQUENCY_CHANGED observed={max_freq}"
    )

put("BOOTSTRAP_STABILITY_FULL_RECOMPUTATION", "PASS")
put("RECOMPUTED_STABLE_EDGES", n_stable)
put("RECOMPUTED_UNSTABLE_EDGES", n_unstable)
put("RECOMPUTED_STABLE_POSITIVE_EDGES", n_stable_pos)
put("RECOMPUTED_STABLE_NEGATIVE_EDGES", n_stable_neg)
put("RECOMPUTED_UNDEFINED_PAIR_REPLICATES", undefined_pair_replicates)
put("RECOMPUTED_MIN_SELECTION_FREQUENCY", min_freq)
put("RECOMPUTED_MEDIAN_SELECTION_FREQUENCY", median_freq)
put("RECOMPUTED_MAX_SELECTION_FREQUENCY", max_freq)


# ------------------------------------------------------------
# E. Quantile / median recomputation audit on deterministic subset
# ------------------------------------------------------------
rng = np.random.default_rng(2432197)
audit_idx = np.sort(
    rng.choice(
        N_CAND,
        size=128,
        replace=False,
    )
)

quantile_rows = []
max_median_diff = 0.0
max_p025_diff = 0.0
max_p975_diff = 0.0

for j in audit_idx:
    vals = boot_rho[:,j]
    vals = vals[np.isfinite(vals)]

    med = float(np.median(vals))
    p025 = float(np.quantile(vals,0.025))
    p975 = float(np.quantile(vals,0.975))

    stored_med = float(cand_stab.iloc[j]["bootstrap_median_rho"])
    stored_p025 = float(cand_stab.iloc[j]["bootstrap_rho_p2_5"])
    stored_p975 = float(cand_stab.iloc[j]["bootstrap_rho_p97_5"])

    dmed = abs(med-stored_med)
    d025 = abs(p025-stored_p025)
    d975 = abs(p975-stored_p975)

    max_median_diff = max(max_median_diff,dmed)
    max_p025_diff = max(max_p025_diff,d025)
    max_p975_diff = max(max_p975_diff,d975)

    status = (
        "PASS"
        if max(dmed,d025,d975) <= 1e-15
        else "FAIL"
    )

    quantile_rows.append({
        "candidate_row_1based":int(j+1),
        "pair_index_1based":int(cand.iloc[j]["pair_index_1based"]),
        "mRNA_id":str(cand.iloc[j]["mRNA_id"]),
        "miRNA_id":str(cand.iloc[j]["miRNA_id"]),
        "recomputed_median_rho":med,
        "stored_median_rho":stored_med,
        "abs_median_diff":dmed,
        "recomputed_p2_5":p025,
        "stored_p2_5":stored_p025,
        "abs_p2_5_diff":d025,
        "recomputed_p97_5":p975,
        "stored_p97_5":stored_p975,
        "abs_p97_5_diff":d975,
        "status":status,
    })

quantile_df = pd.DataFrame(quantile_rows)

if not quantile_df["status"].eq("PASS").all():
    raise RuntimeError(
        "BOOTSTRAP_QUANTILE_REAUDIT_FAILED"
    )

quantile_df.to_csv(BOOT_REAUDIT,index=False)

put("BOOTSTRAP_MEDIAN_QUANTILE_REAUDIT", "PASS")
put("BOOTSTRAP_MEDIAN_QUANTILE_REAUDIT_ROWS", 128)
put("BOOTSTRAP_MEDIAN_MAX_ABS_DIFF", max_median_diff)
put("BOOTSTRAP_P2_5_MAX_ABS_DIFF", max_p025_diff)
put("BOOTSTRAP_P97_5_MAX_ABS_DIFF", max_p975_diff)


# ------------------------------------------------------------
# F. Exact stable-edge table subset audit
# ------------------------------------------------------------
expected_stable = cand_stab.loc[recomputed_stable].copy()

if expected_stable.shape[0] != stable.shape[0]:
    raise RuntimeError("STABLE_TABLE_ROW_COUNT_NOT_EXACT_SUBSET")

id_cols = [
    "pair_index_1based",
    "mRNA_id",
    "miRNA_id",
]

for col in id_cols:
    if expected_stable[col].astype(str).tolist() != \
       stable[col].astype(str).tolist():
        raise RuntimeError(
            f"STABLE_TABLE_IDENTITY_ORDER_MISMATCH column={col}"
        )

compare_numeric = [
    "partial_spearman_rho",
    "PValue",
    "FDR",
    "bootstrap_selection_frequency",
    "bootstrap_median_rho",
    "bootstrap_rho_p2_5",
    "bootstrap_rho_p97_5",
]

for col in compare_numeric:
    if not np.allclose(
        expected_stable[col].to_numpy(dtype=np.float64),
        stable[col].to_numpy(dtype=np.float64),
        rtol=0.0,
        atol=1e-15,
    ):
        raise RuntimeError(
            f"STABLE_TABLE_NUMERIC_MISMATCH column={col}"
        )

put("D7B_STABLE_EDGE_TABLE_EXACT_SUBSET_AUDIT", "PASS")


# ------------------------------------------------------------
# G. Threshold-boundary audit
# ------------------------------------------------------------
failed = selection_frequency[~recomputed_stable]
passed = selection_frequency[recomputed_stable]

if failed.size != EXPECTED_UNSTABLE:
    raise RuntimeError("FAILED_EDGE_COUNT_CHANGED")
if passed.size != EXPECTED_STABLE:
    raise RuntimeError("PASSED_EDGE_COUNT_CHANGED")

max_failed = float(np.max(failed))
min_passed = float(np.min(passed))

# Because frequency increments in 1/500 = 0.002,
# the last failing value should be <=0.798 and first passing >=0.800.
if max_failed >= STABILITY_THRESHOLD:
    raise RuntimeError(
        f"FAILED_EDGE_AT_OR_ABOVE_THRESHOLD observed={max_failed}"
    )
if min_passed < STABILITY_THRESHOLD:
    raise RuntimeError(
        f"PASSED_EDGE_BELOW_THRESHOLD observed={min_passed}"
    )

threshold_df = pd.DataFrame([
    {
        "metric":"stability_threshold",
        "value":STABILITY_THRESHOLD,
    },
    {
        "metric":"max_frequency_among_45_unstable_edges",
        "value":max_failed,
    },
    {
        "metric":"min_frequency_among_11531_stable_edges",
        "value":min_passed,
    },
    {
        "metric":"stable_edge_retention_fraction",
        "value":float(n_stable/N_CAND),
    },
    {
        "metric":"unstable_edge_fraction",
        "value":float(n_unstable/N_CAND),
    },
])
threshold_df.to_csv(THRESHOLD_AUDIT,index=False)

put("STABILITY_THRESHOLD_BOUNDARY_AUDIT", "PASS")
put("MAX_UNSTABLE_SELECTION_FREQUENCY", max_failed)
put("MIN_STABLE_SELECTION_FREQUENCY", min_passed)
put("STABLE_EDGE_RETENTION_FRACTION", float(n_stable/N_CAND))


# ------------------------------------------------------------
# H. Freeze edge set as byte-identical certified copy
# ------------------------------------------------------------
shutil.copyfile(D7B_STABLE,FROZEN_STABLE)

source_bytes = D7B_STABLE.read_bytes()
frozen_bytes = FROZEN_STABLE.read_bytes()

if source_bytes != frozen_bytes:
    raise RuntimeError(
        "FROZEN_STABLE_EDGE_COPY_NOT_BYTE_IDENTICAL"
    )

put("FROZEN_STABLE_EDGE_SET_BYTE_IDENTICAL_TO_D7B", "YES")


# ------------------------------------------------------------
# I. Stable-set audit summary
# ------------------------------------------------------------
stable_set_audit = pd.DataFrame([
    {
        "metric":"full_data_candidates",
        "value":N_CAND,
        "status":"PASS",
    },
    {
        "metric":"stable_edges",
        "value":n_stable,
        "status":"PASS",
    },
    {
        "metric":"unstable_edges",
        "value":n_unstable,
        "status":"PASS",
    },
    {
        "metric":"stable_positive_edges",
        "value":n_stable_pos,
        "status":"PASS",
    },
    {
        "metric":"stable_negative_edges",
        "value":n_stable_neg,
        "status":"PASS",
    },
    {
        "metric":"undefined_bootstrap_pair_replicates",
        "value":undefined_pair_replicates,
        "status":"PASS",
    },
    {
        "metric":"bootstrap_replicates",
        "value":N_BOOT,
        "status":"PASS",
    },
])
stable_set_audit.to_csv(STABLE_SET_AUDIT,index=False)


# ------------------------------------------------------------
# J. Frozen specification
# ------------------------------------------------------------
spec_lines = [
    "GSE243219_D7C_FROZEN_STABLE_ASSOCIATION_EDGE_SET",
    "SOURCE_FULL_DATA_ASSOCIATION_PHASE=D7A",
    "SOURCE_BOOTSTRAP_STABILITY_PHASE=D7B_V2",
    "FULL_DATA_CANDIDATES=11576",
    "FULL_DATA_POSITIVE_CANDIDATES=5255",
    "FULL_DATA_NEGATIVE_CANDIDATES=6321",
    "BOOTSTRAP_REPLICATES=500",
    "BOOTSTRAP_RANDOM_SEED=243219",
    "BOOTSTRAP_SUPPORT_EVENT=SAME_SIGN_AS_FULL_DATA_AND_ABS_RHO_GE_0.30",
    "STABLE_EDGE_FREQUENCY_THRESHOLD=0.80",
    "STABILITY_DENOMINATOR=ALL_500_REPLICATES",
    "UNDEFINED_BOOTSTRAP_RHO_COUNTS_AS_SUPPORT=NO",
    f"FROZEN_STABLE_ASSOCIATION_EDGES={n_stable}",
    f"FROZEN_STABLE_POSITIVE_ASSOCIATION_EDGES={n_stable_pos}",
    f"FROZEN_STABLE_NEGATIVE_ASSOCIATION_EDGES={n_stable_neg}",
    f"REJECTED_UNSTABLE_ASSOCIATION_EDGES={n_unstable}",
    f"STABLE_EDGE_RETENTION_FRACTION={n_stable/N_CAND:.17g}",
    "CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO",
    "POSITIVE_ASSOCIATIONS_RETAINED=YES",
    "NEGATIVE_ASSOCIATIONS_RETAINED=YES",
    "COVID_ONLY_SPEARMAN_ROLE=DESCRIPTIVE_ANNOTATION_ONLY",
    "HEALTHY_ONLY_SPEARMAN_ROLE=DESCRIPTIVE_ANNOTATION_ONLY",
    "TARGET_EVIDENCE_REQUIRED_BEFORE_REGULATORY_DIRECTION=YES",
    "TARGET_EVIDENCE_INTEGRATION_EXECUTED_IN_D7C=NO",
    "NETWORK_CONSTRUCTION_EXECUTED_IN_D7C=NO",
    "ACLA_EXECUTED_IN_D7C=NO",
    "STABLE_ASSOCIATION_EDGE_SET_FROZEN=YES",
]
FROZEN_SPEC.write_text(
    "\n".join(spec_lines) + "\n",
    encoding="utf-8",
)

put("STABLE_ASSOCIATION_EDGE_SET_FROZEN", "YES")
put("THRESHOLD_CHANGED", "NO")
put("ASSOCIATION_REEXECUTED", "NO")
put("BOOTSTRAP_REEXECUTED", "NO")
put("TARGET_EVIDENCE_INTEGRATION_EXECUTED", "NO")
put("NETWORK_EXECUTED", "NO")
put("ACLA_EXECUTED", "NO")
put("READY_FOR_D8_TARGET_EVIDENCE_STRATEGY_AND_INPUT_PREFLIGHT", "YES")
put("NEXT_PHASE", "D8_TARGET_EVIDENCE_STRATEGY_AND_INPUT_PREFLIGHT")

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
    $D7Cohort,
    $D7AAll,
    $D7ACandidates,
    $D7BNpz,
    $D7BCandidateStability,
    $D7BStableEdges,
    $D7BDirectAudit,
    $BootstrapReaudit,
    $ThresholdAudit,
    $StableSetAudit,
    $FrozenStableEdges,
    $FrozenSpec,
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
        Write-Host '=== D7C PYTHON STDERR ==='
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
    throw ('D7C_PYTHON_FAILED exit={0} full_traceback={1}' -f `
        $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D7C_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('D7C_SOURCE_TABLE_INTEGRITY','PASS'),
    @('D7A_FULL_DATA_CANDIDATE_SET_REAUDIT','PASS'),
    @('BOOTSTRAP_NPZ_STRUCTURAL_REAUDIT','PASS'),
    @('BOOTSTRAP_DRAW_STRATIFICATION_REAUDIT','PASS'),
    @('BOOTSTRAP_STABILITY_FULL_RECOMPUTATION','PASS'),
    @('RECOMPUTED_STABLE_EDGES','11531'),
    @('RECOMPUTED_UNSTABLE_EDGES','45'),
    @('RECOMPUTED_STABLE_POSITIVE_EDGES','5225'),
    @('RECOMPUTED_STABLE_NEGATIVE_EDGES','6306'),
    @('RECOMPUTED_UNDEFINED_PAIR_REPLICATES','0'),
    @('BOOTSTRAP_MEDIAN_QUANTILE_REAUDIT','PASS'),
    @('BOOTSTRAP_MEDIAN_QUANTILE_REAUDIT_ROWS','128'),
    @('D7B_STABLE_EDGE_TABLE_EXACT_SUBSET_AUDIT','PASS'),
    @('STABILITY_THRESHOLD_BOUNDARY_AUDIT','PASS'),
    @('FROZEN_STABLE_EDGE_SET_BYTE_IDENTICAL_TO_D7B','YES'),
    @('STABLE_ASSOCIATION_EDGE_SET_FROZEN','YES'),
    @('THRESHOLD_CHANGED','NO'),
    @('ASSOCIATION_REEXECUTED','NO'),
    @('BOOTSTRAP_REEXECUTED','NO'),
    @('TARGET_EVIDENCE_INTEGRATION_EXECUTED','NO'),
    @('NETWORK_EXECUTED','NO'),
    @('ACLA_EXECUTED','NO'),
    @('READY_FOR_D8_TARGET_EVIDENCE_STRATEGY_AND_INPUT_PREFLIGHT','YES'),
    @('NEXT_PHASE','D8_TARGET_EVIDENCE_STRATEGY_AND_INPUT_PREFLIGHT')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D7C_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 3. Decision
# ------------------------------------------------------------
@(
    'GSE243219_D7C_DECISION',
    'PHASE_D7C_STATUS=PASS',
    'MODE=INDEPENDENT_AUDIT_AND_FREEZE_ONLY',
    'D7_V2_CERTIFICATION_GATE=PASS',
    'D7_V2_OUTPUTS_RECERTIFIED=10/10',
    'D7A_CERTIFICATION_GATE=PASS',
    'D7A_OUTPUTS_RECERTIFIED=11/11',
    'D7B_V2_CERTIFICATION_GATE=PASS',
    'D7B_V2_OUTPUTS_RECERTIFIED=12/12',
    'D7A_FULL_DATA_CANDIDATE_SET_REAUDIT=PASS',
    'BOOTSTRAP_NPZ_STRUCTURAL_REAUDIT=PASS',
    'BOOTSTRAP_DRAW_STRATIFICATION_REAUDIT=PASS',
    'BOOTSTRAP_STABILITY_FULL_RECOMPUTATION=PASS',
    'FULL_DATA_CANDIDATES=11576',
    'FROZEN_STABLE_ASSOCIATION_EDGES=11531',
    'REJECTED_UNSTABLE_ASSOCIATION_EDGES=45',
    'FROZEN_STABLE_POSITIVE_ASSOCIATION_EDGES=5225',
    'FROZEN_STABLE_NEGATIVE_ASSOCIATION_EDGES=6306',
    ('STABLE_EDGE_RETENTION_FRACTION={0}' -f (Cap 'STABLE_EDGE_RETENTION_FRACTION')),
    ('MAX_UNSTABLE_SELECTION_FREQUENCY={0}' -f (Cap 'MAX_UNSTABLE_SELECTION_FREQUENCY')),
    ('MIN_STABLE_SELECTION_FREQUENCY={0}' -f (Cap 'MIN_STABLE_SELECTION_FREQUENCY')),
    ('RECOMPUTED_MIN_SELECTION_FREQUENCY={0}' -f (Cap 'RECOMPUTED_MIN_SELECTION_FREQUENCY')),
    ('RECOMPUTED_MEDIAN_SELECTION_FREQUENCY={0}' -f (Cap 'RECOMPUTED_MEDIAN_SELECTION_FREQUENCY')),
    ('RECOMPUTED_MAX_SELECTION_FREQUENCY={0}' -f (Cap 'RECOMPUTED_MAX_SELECTION_FREQUENCY')),
    'RECOMPUTED_UNDEFINED_PAIR_REPLICATES=0',
    'BOOTSTRAP_MEDIAN_QUANTILE_REAUDIT=PASS',
    ('BOOTSTRAP_MEDIAN_MAX_ABS_DIFF={0}' -f (Cap 'BOOTSTRAP_MEDIAN_MAX_ABS_DIFF')),
    ('BOOTSTRAP_P2_5_MAX_ABS_DIFF={0}' -f (Cap 'BOOTSTRAP_P2_5_MAX_ABS_DIFF')),
    ('BOOTSTRAP_P97_5_MAX_ABS_DIFF={0}' -f (Cap 'BOOTSTRAP_P97_5_MAX_ABS_DIFF')),
    'D7B_STABLE_EDGE_TABLE_EXACT_SUBSET_AUDIT=PASS',
    'STABILITY_THRESHOLD_BOUNDARY_AUDIT=PASS',
    'FROZEN_STABLE_EDGE_SET_BYTE_IDENTICAL_TO_D7B=YES',
    'STABLE_ASSOCIATION_EDGE_SET_FROZEN=YES',
    'THRESHOLD_CHANGED=NO',
    'CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO',
    'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D8_TARGET_EVIDENCE_STRATEGY_AND_INPUT_PREFLIGHT=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D8_TARGET_EVIDENCE_STRATEGY_AND_INPUT_PREFLIGHT',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Manifest
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $BootstrapReaudit,
    $ThresholdAudit,
    $StableSetAudit,
    $FrozenStableEdges,
    $FrozenSpec,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D7C_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p

    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D7CSHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D7C SUMMARY ===',
    'PHASE_D7C_STATUS=PASS',
    'MODE=INDEPENDENT_AUDIT_AND_FREEZE_ONLY',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    'D7_V2_CERTIFICATION_GATE=PASS',
    'D7A_CERTIFICATION_GATE=PASS',
    'D7B_V2_CERTIFICATION_GATE=PASS',
    'D7A_FULL_DATA_CANDIDATE_SET_REAUDIT=PASS',
    'BOOTSTRAP_NPZ_STRUCTURAL_REAUDIT=PASS',
    'BOOTSTRAP_DRAW_STRATIFICATION_REAUDIT=PASS',
    'BOOTSTRAP_STABILITY_FULL_RECOMPUTATION=PASS',
    'FULL_DATA_CANDIDATES=11576',
    'FROZEN_STABLE_ASSOCIATION_EDGES=11531',
    'REJECTED_UNSTABLE_ASSOCIATION_EDGES=45',
    'FROZEN_STABLE_POSITIVE_ASSOCIATION_EDGES=5225',
    'FROZEN_STABLE_NEGATIVE_ASSOCIATION_EDGES=6306',
    ('STABLE_EDGE_RETENTION_FRACTION={0}' -f (Cap 'STABLE_EDGE_RETENTION_FRACTION')),
    ('MAX_UNSTABLE_SELECTION_FREQUENCY={0}' -f (Cap 'MAX_UNSTABLE_SELECTION_FREQUENCY')),
    ('MIN_STABLE_SELECTION_FREQUENCY={0}' -f (Cap 'MIN_STABLE_SELECTION_FREQUENCY')),
    ('RECOMPUTED_MIN_SELECTION_FREQUENCY={0}' -f (Cap 'RECOMPUTED_MIN_SELECTION_FREQUENCY')),
    ('RECOMPUTED_MEDIAN_SELECTION_FREQUENCY={0}' -f (Cap 'RECOMPUTED_MEDIAN_SELECTION_FREQUENCY')),
    ('RECOMPUTED_MAX_SELECTION_FREQUENCY={0}' -f (Cap 'RECOMPUTED_MAX_SELECTION_FREQUENCY')),
    'RECOMPUTED_UNDEFINED_PAIR_REPLICATES=0',
    'BOOTSTRAP_MEDIAN_QUANTILE_REAUDIT=PASS',
    'BOOTSTRAP_MEDIAN_QUANTILE_REAUDIT_ROWS=128',
    'D7B_STABLE_EDGE_TABLE_EXACT_SUBSET_AUDIT=PASS',
    'STABILITY_THRESHOLD_BOUNDARY_AUDIT=PASS',
    'FROZEN_STABLE_EDGE_SET_BYTE_IDENTICAL_TO_D7B=YES',
    'STABLE_ASSOCIATION_EDGE_SET_FROZEN=YES',
    'THRESHOLD_CHANGED=NO',
    'ASSOCIATION_REEXECUTED=NO',
    'BOOTSTRAP_REEXECUTED=NO',
    'CORRELATION_SIGN_ESTABLISHES_REGULATORY_DIRECTION=NO',
    'TARGET_EVIDENCE_INTEGRATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D8_TARGET_EVIDENCE_STRATEGY_AND_INPUT_PREFLIGHT=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D8_TARGET_EVIDENCE_STRATEGY_AND_INPUT_PREFLIGHT',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D7C_BOOTSTRAP_REAUDIT={0}' -f $BootstrapReaudit)
Write-Host ('D7C_THRESHOLD_AUDIT={0}' -f $ThresholdAudit)
Write-Host ('D7C_STABLE_SET_AUDIT={0}' -f $StableSetAudit)
Write-Host ('D7C_FROZEN_STABLE_EDGES={0}' -f $FrozenStableEdges)
Write-Host ('D7C_FROZEN_SPEC={0}' -f $FrozenSpec)
Write-Host ('D7C_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D7C_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D7C=PASS'
Write-Host 'STOP=YES'
