$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D2E-V4 — OFFLINE PYTHON TMM REFERENCE VALIDATION
#
# Corrected provenance:
#   D2D1 reused the virtual environment created by D2D:
#   ...\D2D_PREFLIGHT_20260904_195001\venv
#
# This phase:
#   - re-certifies D2D1
#   - reuses the validated D2D Python 3.12 / InMoose 0.9.1 venv
#   - performs ZERO network access and ZERO package installation
#   - validates a frozen edgeR-style TMM implementation against
#     an independently coded RNAnorm-style oracle
#   - validates against the published RNAnorm toy factor vector
#     [1, 1, 0.5, 2]
#
# NO biological data, real matrices, normalization, filtering,
# DE, network construction, or A-CLA are executed.
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D2Root = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING'

$D2DRun = Join-Path $D2Root 'D2D_PREFLIGHT_20260904_195001'
$D2D1Run = Join-Path $D2Root 'D2D1_LOW_LEVEL_PREFLIGHT_20260904_201625'

$D2D1Manifest = Join-Path $D2D1Run 'D2D1_OUTPUT_SHA256_MANIFEST.csv'
$D2D1Decision = Join-Path $D2D1Run 'D2D1_DECISION.txt'
$D2D1Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D2D1_20260904_201625\PHASE_D2D1_SUMMARY.txt'

$VenvPython = Join-Path $D2DRun 'venv\Scripts\python.exe'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D2Root ('D2E_V4_TMM_OFFLINE_VALIDATION_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D2E_V4_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$ValidationPy = Join-Path $RunDir 'D2E_V4_OFFLINE_TMM_VALIDATION.py'
$ResultJson = Join-Path $RunDir 'D2E_V4_TMM_VALIDATION_RESULTS.json'
$ResultCsv = Join-Path $RunDir 'D2E_V4_TMM_VALIDATION_RESULTS.csv'
$FactorCsv = Join-Path $RunDir 'D2E_V4_TMM_FACTOR_COMPARISON.csv'
$PythonLog = Join-Path $RunDir 'D2E_V4_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D2E_V4_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D2E_V4_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D2E_V4_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D2E-V4 — OFFLINE PYTHON TMM REFERENCE VALIDATION ==='
Write-Host 'MODE=SYNTHETIC_OFFLINE_NORMALIZATION_VALIDATION_ONLY'
Write-Host 'NETWORK_ACCESS_EXECUTED=NO'
Write-Host 'PACKAGE_INSTALLATION_EXECUTED=NO'
Write-Host 'REAL_BIOLOGICAL_COUNTS_READ=NO'
Write-Host 'REAL_MATRIX_CONSTRUCTION_EXECUTED=NO'
Write-Host 'REAL_FEATURE_AGGREGATION_EXECUTED=NO'
Write-Host 'REAL_NORMALIZATION_EXECUTED=NO'
Write-Host 'REAL_FILTERING_EXECUTED=NO'
Write-Host 'REAL_DE_EXECUTED=NO'
Write-Host 'NETWORK_ANALYSIS_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @($D2D1Manifest,$D2D1Decision,$D2D1Report,$VenvPython)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D2E4SHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

# ------------------------------------------------------------
# 1. Re-certify D2D1 scientific/capability state
# ------------------------------------------------------------
$d2d1 = Get-Content -LiteralPath $D2D1Report -Raw

foreach ($tok in @(
    'PHASE_D2D1_STATUS=PASS',
    'REAL_BIOLOGICAL_COUNTS_READ=NO',
    'PYTHON_VERSION=3.12.3',
    'INMOOSE_VERSION=0.9.1',
    'DGELIST_SOURCE_EXPLICIT_INTEGER_CAST=YES',
    'DGELIST_INTEGER_COERCION_CONFIRMED=YES',
    'DGELIST_AUTHORIZED_FOR_FRACTIONAL_REAL_DATA=NO',
    'LOW_LEVEL_GLMFIT_FRACTIONAL_COUNTS_PRESERVED=YES',
    'LOW_LEVEL_GLMFIT_FRACTIONAL_NUMERICAL_EFFECT_VERIFIED=YES',
    'LOW_LEVEL_EFFECTIVE_LIBRARY_OFFSET_PRESERVED=YES',
    'LOW_LEVEL_COMMON_DISPERSION_FRACTIONAL=PASS',
    'AVELOGCPM_EFFECTIVE_LIBRARY_CAPABILITY=PASS',
    'LOW_LEVEL_GLMQLFIT_FRACTIONAL=PASS',
    'LOW_LEVEL_GLMQLFIT_COUNTS_PRESERVED=YES',
    'LOW_LEVEL_GLMQLFIT_OFFSET_PRESERVED=YES',
    'LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_TRUE=PASS',
    'LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_FALSE=PASS',
    'LOW_LEVEL_FRACTIONAL_QL_PIPELINE_CAPABILITY_VERIFIED=YES',
    'FRACTIONAL_ENGINE_STATUS=LOW_LEVEL_EDGEPY_FRACTIONAL_PIPELINE_PASS',
    'NEXT_PHASE=D2E_PYTHON_TMM_REFERENCE_IMPLEMENTATION_VALIDATION'
)) {
    if ($d2d1 -notmatch [regex]::Escape($tok)) {
        throw ('D2D1_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$manifestRows = @(Import-Csv -LiteralPath $D2D1Manifest)
if ($manifestRows.Count -ne 5) {
    throw ('D2D1_MANIFEST_ROW_COUNT_CHANGED expected=5 observed={0}' -f $manifestRows.Count)
}

foreach ($r in $manifestRows) {
    if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
        throw ('D2D1_OUTPUT_MISSING={0}' -f $r.full_path)
    }

    $item = Get-Item -LiteralPath $r.full_path
    $hash = Get-D2E4SHA256 $r.full_path

    if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
        $hash -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D2D1_OUTPUT_HASH_OR_SIZE_CHANGED={0}' -f $r.full_path)
    }
}

$PythonVersion = & $VenvPython -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$InMooseVersion = & $VenvPython -c "import importlib.metadata as m; print(m.version('inmoose'))"
$NumpyVersion = & $VenvPython -c "import numpy; print(numpy.__version__)"
$ScipyVersion = & $VenvPython -c "import scipy; print(scipy.__version__)"

if ($PythonVersion -ne '3.12.3') {
    throw ('VALIDATED_VENV_PYTHON_CHANGED={0}' -f $PythonVersion)
}
if ($InMooseVersion.Trim() -ne '0.9.1') {
    throw ('VALIDATED_VENV_INMOOSE_CHANGED={0}' -f $InMooseVersion)
}

Write-Host 'D2D1_CERTIFICATION_GATE=PASS'
Write-Host 'D2D1_OUTPUTS_RECERTIFIED=5/5'
Write-Host ('REUSED_VALIDATED_VENV_SOURCE={0}' -f $D2DRun)
Write-Host ('PYTHON_VERSION={0}' -f $PythonVersion)
Write-Host ('INMOOSE_VERSION={0}' -f $InMooseVersion)
Write-Host ('NUMPY_VERSION={0}' -f $NumpyVersion)
Write-Host ('SCIPY_VERSION={0}' -f $ScipyVersion)

# ------------------------------------------------------------
# 2. Write one self-contained offline Python validation program.
# ------------------------------------------------------------
$PythonCode = @'
import csv
import json
import math
import sys
from pathlib import Path

import numpy as np
from scipy.stats import gmean, rankdata, scoreatpercentile

RESULT_JSON = Path(sys.argv[1])
RESULT_CSV = Path(sys.argv[2])
FACTOR_CSV = Path(sys.argv[3])

results = {}
details = {}
factor_rows = []

def put(key, value, detail=None):
    results[key] = value
    if detail is not None:
        details[key] = str(detail)

def geom_mean(x):
    x = np.asarray(x, dtype=np.float64)
    return float(np.exp(np.mean(np.log(x))))

# ============================================================
# IMPLEMENTATION A
# Frozen edgeR-style TMM translation.
# Input orientation = genes/features x samples.
# ============================================================

def average_rank(x):
    x = np.asarray(x, dtype=np.float64)
    order = np.argsort(x, kind="mergesort")
    out = np.empty(x.size, dtype=np.float64)

    i = 0
    while i < x.size:
        j = i + 1
        while j < x.size and x[order[j]] == x[order[i]]:
            j += 1

        # Average 1-based ranks, matching R rank() default ties.method.
        out[order[i:j]] = ((i + 1) + j) / 2.0
        i = j

    return out


def factor_tmm_edge_style(
    obs,
    ref,
    lib_obs,
    lib_ref,
    logratio_trim=0.30,
    sum_trim=0.05,
    do_weighting=True,
    acutoff=-1e10,
):
    obs = np.asarray(obs, dtype=np.float64)
    ref = np.asarray(ref, dtype=np.float64)
    n_o = float(lib_obs)
    n_r = float(lib_ref)

    with np.errstate(divide="ignore", invalid="ignore"):
        log_r = np.log2((obs / n_o) / (ref / n_r))
        abs_e = (np.log2(obs / n_o) + np.log2(ref / n_r)) / 2.0
        v = (n_o - obs) / n_o / obs + (n_r - ref) / n_r / ref

    keep0 = np.isfinite(log_r) & np.isfinite(abs_e) & (abs_e > acutoff)
    log_r = log_r[keep0]
    abs_e = abs_e[keep0]
    v = v[keep0]

    if log_r.size == 0:
        return 1.0

    if np.max(np.abs(log_r)) < 1e-6:
        return 1.0

    n = log_r.size

    lo_l = np.floor(n * logratio_trim) + 1
    hi_l = n + 1 - lo_l
    lo_s = np.floor(n * sum_trim) + 1
    hi_s = n + 1 - lo_s

    r_m = average_rank(log_r)
    r_a = average_rank(abs_e)

    keep = (
        (r_m >= lo_l)
        & (r_m <= hi_l)
        & (r_a >= lo_s)
        & (r_a <= hi_s)
    )

    if not np.any(keep):
        return 1.0

    if do_weighting:
        den = np.sum(1.0 / v[keep])
        f = np.sum(log_r[keep] / v[keep]) / den if den != 0 else np.nan
    else:
        f = np.mean(log_r[keep])

    if not np.isfinite(f):
        f = 0.0

    return float(2.0 ** f)


def edge_style_tmm(
    counts,
    lib_size=None,
    ref_column=None,
    logratio_trim=0.30,
    sum_trim=0.05,
    do_weighting=True,
    acutoff=-1e10,
):
    x = np.asarray(counts, dtype=np.float64)

    if x.ndim != 2:
        raise ValueError("counts must be 2-D")
    if x.shape[1] < 1:
        raise ValueError("at least one sample is required")
    if np.any(~np.isfinite(x)):
        raise ValueError("non-finite counts are not permitted")
    if np.any(x < 0):
        raise ValueError("negative counts are not permitted")

    nsamples = x.shape[1]

    if lib_size is None:
        lib_size = np.sum(x, axis=0, dtype=np.float64)
    else:
        lib_size = np.asarray(lib_size, dtype=np.float64)
        if lib_size.ndim == 0:
            lib_size = np.repeat(lib_size, nsamples)
        if lib_size.size != nsamples:
            raise ValueError("lib_size length mismatch")

    if np.any(~np.isfinite(lib_size)) or np.any(lib_size <= 0):
        raise ValueError("library sizes must be finite and positive")

    # Remove features that are zero in every sample.
    all_zero = np.sum(x > 0, axis=1) == 0
    if np.any(all_zero):
        x = x[~all_zero, :]

    if x.shape[0] == 0 or nsamples == 1:
        return np.ones(nsamples, dtype=np.float64)

    if ref_column is None:
        # NumPy linear quantile = R quantile type=7.
        f75 = np.quantile(x, 0.75, axis=0, method="linear") / lib_size

        if np.median(f75) < 1e-20:
            ref_column = int(np.argmax(np.sum(np.sqrt(x), axis=0)))
        else:
            ref_column = int(np.argmin(np.abs(f75 - np.mean(f75))))

    ref = x[:, ref_column]
    n_ref = lib_size[ref_column]

    factors = np.array(
        [
            factor_tmm_edge_style(
                x[:, j],
                ref,
                lib_size[j],
                n_ref,
                logratio_trim,
                sum_trim,
                do_weighting,
                acutoff,
            )
            for j in range(nsamples)
        ],
        dtype=np.float64,
    )

    if np.any(~np.isfinite(factors)) or np.any(factors <= 0):
        raise RuntimeError("invalid TMM factor")

    # edgeR convention: product of factors = 1.
    factors = factors / np.exp(np.mean(np.log(factors)))
    return factors


# ============================================================
# IMPLEMENTATION B
# Independent RNAnorm-style implementation.
# Input orientation = samples x genes/features.
# Uses scipy ranking/percentile routines and NaN masking.
# ============================================================

def remove_all_zero_features_sample_major(x):
    x = np.asarray(x, dtype=np.float64)
    return x[:, np.any(x != 0, axis=0)]


def rnanorm_style_reference_index(x):
    x = remove_all_zero_features_sample_major(x)
    libs = np.sum(x, axis=1, dtype=np.float64)

    uq = np.apply_along_axis(scoreatpercentile, 1, x, 75)
    raw_uq = uq / libs
    uq_factors = raw_uq / gmean(raw_uq)

    return int(np.argmin(np.abs(uq_factors - np.mean(uq_factors))))


def rnanorm_style_tmm(x, m_trim=0.30, a_trim=0.05):
    x = np.asarray(x, dtype=np.float64).copy()

    if x.ndim != 2:
        raise ValueError("x must be 2-D samples x features")
    if np.any(~np.isfinite(x)):
        raise ValueError("non-finite input")
    if np.any(x < 0):
        raise ValueError("negative input")

    x = remove_all_zero_features_sample_major(x)

    ref_idx = rnanorm_style_reference_index(x)
    ref = x[ref_idx].copy()

    libs = np.sum(x, axis=1, dtype=np.float64)
    lib_ref = float(np.sum(ref))

    z = x.copy()
    z[z == 0] = np.nan

    ref_nan = ref.copy()
    ref_nan[ref_nan == 0] = np.nan

    r = z / libs[:, None]
    r_ref = ref_nan / lib_ref

    with np.errstate(divide="ignore", invalid="ignore"):
        m = np.log2(r / r_ref)
        a = np.log2(r * r_ref) / 2.0

        # Equivalent inverse-asymptotic variance denominator form.
        w = (1.0 - r) / z + (1.0 - r_ref) / ref_nan

    logs = []

    for i in range(x.shape[0]):
        mm = m[i]
        aa = a[i]
        ww = w[i]

        finite = np.isfinite(mm) & np.isfinite(aa) & np.isfinite(ww)
        mm = mm[finite]
        aa = aa[finite]
        ww = ww[finite]

        n = mm.size

        if n == 0:
            logs.append(0.0)
            continue

        m_low = np.floor(n * m_trim) + 1
        m_high = n - m_low + 1

        a_low = np.floor(n * a_trim) + 1
        a_high = n - a_low + 1

        rank_m = rankdata(mm, method="average")
        rank_a = rankdata(aa, method="average")

        keep = (
            (rank_m >= m_low)
            & (rank_m <= m_high)
            & (rank_a >= a_low)
            & (rank_a <= a_high)
        )

        if not np.any(keep):
            logs.append(0.0)
            continue

        den = np.sum(1.0 / ww[keep])
        f = np.sum(mm[keep] / ww[keep]) / den if den != 0 else np.nan

        if not np.isfinite(f):
            f = 0.0

        logs.append(float(f))

    factors = np.power(2.0, np.asarray(logs, dtype=np.float64))
    factors = factors / gmean(factors)

    return factors, ref_idx


def compare_fixture(name, features_by_samples, tolerance=5e-10):
    x = np.asarray(features_by_samples, dtype=np.float64)

    a = edge_style_tmm(x)
    b, ref_idx = rnanorm_style_tmm(x.T)

    d = np.abs(a - b)
    max_abs = float(np.max(d))
    max_rel = float(np.max(d / np.maximum(np.abs(b), 1e-300)))

    finite_positive = bool(
        np.all(np.isfinite(a))
        and np.all(a > 0)
        and np.all(np.isfinite(b))
        and np.all(b > 0)
    )

    gm_ok = abs(geom_mean(a) - 1.0) <= 1e-12 and abs(geom_mean(b) - 1.0) <= 1e-12
    ok = finite_positive and gm_ok and max_abs <= tolerance

    put(f"{name}_MAX_ABS_FACTOR_DIFF", max_abs)
    put(f"{name}_MAX_REL_FACTOR_DIFF", max_rel)
    put(f"{name}_EDGE_STYLE_GEOMEAN", geom_mean(a))
    put(f"{name}_ORACLE_GEOMEAN", geom_mean(b))
    put(f"{name}_ORACLE_REFERENCE_INDEX", ref_idx)
    put(f"{name}_ORACLE_CONCORDANCE", "PASS" if ok else "FAIL")

    for i, (fa, fb) in enumerate(zip(a, b)):
        factor_rows.append({
            "fixture": name,
            "sample_index": i,
            "edge_style_factor": float(fa),
            "oracle_factor": float(fb),
            "abs_diff": float(abs(fa-fb)),
        })

    return ok, a, b


# ============================================================
# 1. Published RNAnorm toy example
# ============================================================

toy_sample_major = np.array(
    [
        [200, 300, 500, 2000, 7000],
        [400, 600, 1000, 4000, 14000],
        [200, 300, 500, 2000, 17000],
        [200, 300, 500, 2000, 2000],
    ],
    dtype=np.float64,
)

published = np.array([1.0, 1.0, 0.5, 2.0], dtype=np.float64)

toy_edge = edge_style_tmm(toy_sample_major.T)
toy_oracle, toy_ref = rnanorm_style_tmm(toy_sample_major)

toy_edge_diff = float(np.max(np.abs(toy_edge - published)))
toy_oracle_diff = float(np.max(np.abs(toy_oracle - published)))

put("PUBLISHED_TOY_EXPECTED_FACTORS", "1|1|0.5|2")
put("PUBLISHED_TOY_EDGE_STYLE_MAX_ABS_DIFF", toy_edge_diff)
put("PUBLISHED_TOY_ORACLE_MAX_ABS_DIFF", toy_oracle_diff)
put("PUBLISHED_TOY_ORACLE_REFERENCE_INDEX", toy_ref)
put(
    "PUBLISHED_TOY_REFERENCE_VALIDATION",
    "PASS" if toy_edge_diff <= 1e-12 and toy_oracle_diff <= 1e-12 else "FAIL",
)

# ============================================================
# 2. Proportional invariant
# ============================================================

base = np.arange(1, 1201, dtype=np.float64) + 10.0
proportional = np.column_stack([
    base,
    base * 2.0,
    base * 4.0,
    base * 0.5,
])

prop_ok, prop_a, prop_b = compare_fixture("PROPORTIONAL", proportional)

prop_unity = bool(
    np.allclose(prop_a, np.ones_like(prop_a), rtol=0, atol=1e-12)
    and np.allclose(prop_b, np.ones_like(prop_b), rtol=0, atol=1e-12)
)

put("PROPORTIONAL_UNITY_INVARIANT", "PASS" if prop_unity else "FAIL")

# ============================================================
# 3. Composition-biased integer fixture
# ============================================================

n = 1800
g = np.arange(n, dtype=np.float64)
composition = np.zeros((n, 6), dtype=np.float64)

for j in range(6):
    composition[:, j] = 30 + ((g * (j + 3) + 17*j) % 89)

composition[:180, 1] *= 7
composition[180:360, 2] *= 5
composition[360:500, 3] *= 9
composition[500:620, 4] *= 4
composition[620:760, 5] *= 6
composition = np.round(composition, 0)

comp_ok, _, _ = compare_fixture("COMPOSITION_INTEGER", composition)

# ============================================================
# 4. Zero-containing fixture
# ============================================================

zero_fixture = composition.copy()
mask = (
    (
        np.arange(n)[:, None] * 11
        + np.arange(6)[None, :] * 7
    )
    % 13
) < 3

zero_fixture[mask] = 0

zero_ok, _, _ = compare_fixture("ZERO_CONTAINING_INTEGER", zero_fixture)

# ============================================================
# 5. Fractional featureCounts-like fixture
# ============================================================

fractional = composition.astype(np.float64)
frac_pattern = np.array([0.0, 0.25, 0.5, 0.75], dtype=np.float64)

for i in range(n):
    for j in range(6):
        fractional[i, j] += frac_pattern[(i + 2*j) % 4]

fractional_n = int(np.sum(np.abs(fractional - np.round(fractional)) > 1e-12))
put("FRACTIONAL_FIXTURE_FRACTIONAL_VALUES", fractional_n)

before = fractional.copy()
frac_ok, _, _ = compare_fixture("FRACTIONAL", fractional)

input_unchanged = bool(np.array_equal(before, fractional))
put("FRACTIONAL_INPUT_UNCHANGED", "YES" if input_unchanged else "NO")

# ============================================================
# 6. Custom lib-size capability
# ============================================================

custom_lib = fractional.sum(axis=0) * np.array(
    [1.00, 1.03, 0.98, 1.07, 0.94, 1.02],
    dtype=np.float64,
)

custom_f = edge_style_tmm(fractional, lib_size=custom_lib)

custom_ok = bool(
    np.all(np.isfinite(custom_f))
    and np.all(custom_f > 0)
    and abs(geom_mean(custom_f) - 1.0) <= 1e-12
)

put("CUSTOM_LIBSIZE_CAPABILITY", "PASS" if custom_ok else "FAIL")
put("CUSTOM_LIBSIZE_FACTOR_GEOMEAN", geom_mean(custom_f))

# ============================================================
# 7. Invalid-input rejection
# ============================================================

negative_rejected = False
try:
    bad = composition.copy()
    bad[0, 0] = -1.0
    edge_style_tmm(bad)
except ValueError:
    negative_rejected = True

nan_rejected = False
try:
    bad = composition.copy()
    bad[0, 0] = np.nan
    edge_style_tmm(bad)
except ValueError:
    nan_rejected = True

put("NEGATIVE_COUNT_REJECTION", "PASS" if negative_rejected else "FAIL")
put("NAN_COUNT_REJECTION", "PASS" if nan_rejected else "FAIL")

# ============================================================
# 8. Final validation gate
# ============================================================

cross_checks = all([
    results.get("PUBLISHED_TOY_REFERENCE_VALIDATION") == "PASS",
    prop_ok,
    comp_ok,
    zero_ok,
    frac_ok,
])

invariants = all([
    prop_unity,
    input_unchanged,
    custom_ok,
    negative_rejected,
    nan_rejected,
])

validated = cross_checks and invariants

put("ALL_OFFLINE_TMM_REFERENCE_CHECKS", "PASS" if cross_checks else "FAIL")
put("ALL_TMM_INVARIANTS", "PASS" if invariants else "FAIL")
put("PYTHON_TMM_REFERENCE_IMPLEMENTATION_VALIDATED", "YES" if validated else "NO")

next_phase = (
    "D3_MATRIX_CONSTRUCTION_AND_QC_PREFLIGHT"
    if validated
    else "D2E5_TMM_IMPLEMENTATION_REVIEW"
)

put("NEXT_PHASE", next_phase)

RESULT_JSON.write_text(
    json.dumps({"results": results, "details": details}, indent=2, sort_keys=True),
    encoding="utf-8",
)

with RESULT_CSV.open("w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["key", "value", "detail"])
    for key in sorted(results):
        w.writerow([key, results[key], details.get(key, "")])

with FACTOR_CSV.open("w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(
        f,
        fieldnames=[
            "fixture",
            "sample_index",
            "edge_style_factor",
            "oracle_factor",
            "abs_diff",
        ],
    )
    w.writeheader()
    w.writerows(factor_rows)

for key in [
    "PUBLISHED_TOY_EXPECTED_FACTORS",
    "PUBLISHED_TOY_EDGE_STYLE_MAX_ABS_DIFF",
    "PUBLISHED_TOY_ORACLE_MAX_ABS_DIFF",
    "PUBLISHED_TOY_REFERENCE_VALIDATION",
    "PROPORTIONAL_UNITY_INVARIANT",
    "PROPORTIONAL_MAX_ABS_FACTOR_DIFF",
    "PROPORTIONAL_ORACLE_CONCORDANCE",
    "COMPOSITION_INTEGER_MAX_ABS_FACTOR_DIFF",
    "COMPOSITION_INTEGER_ORACLE_CONCORDANCE",
    "ZERO_CONTAINING_INTEGER_MAX_ABS_FACTOR_DIFF",
    "ZERO_CONTAINING_INTEGER_ORACLE_CONCORDANCE",
    "FRACTIONAL_FIXTURE_FRACTIONAL_VALUES",
    "FRACTIONAL_MAX_ABS_FACTOR_DIFF",
    "FRACTIONAL_ORACLE_CONCORDANCE",
    "FRACTIONAL_INPUT_UNCHANGED",
    "CUSTOM_LIBSIZE_CAPABILITY",
    "NEGATIVE_COUNT_REJECTION",
    "NAN_COUNT_REJECTION",
    "ALL_OFFLINE_TMM_REFERENCE_CHECKS",
    "ALL_TMM_INVARIANTS",
    "PYTHON_TMM_REFERENCE_IMPLEMENTATION_VALIDATED",
    "NEXT_PHASE",
]:
    print(f"{key}={results.get(key, 'MISSING')}")
'@

$PythonCode | Set-Content -LiteralPath $ValidationPy -Encoding UTF8

# ------------------------------------------------------------
# 3. Execute locally using the already validated D2D venv.
# ------------------------------------------------------------
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

$logLines = New-Object 'System.Collections.Generic.List[string]'
$PythonExit = $null

Push-Location $RunDir
try {
    & $VenvPython $ValidationPy $ResultJson $ResultCsv $FactorCsv 2>&1 |
        ForEach-Object {
            [void]$logLines.Add([string]$_)
            Write-Host $_
        }

    $PythonExit = $LASTEXITCODE
}
finally {
    Pop-Location
}

$logLines | Set-Content -LiteralPath $PythonLog -Encoding UTF8

if ($PythonExit -ne 0) {
    throw ('D2E_V4_PYTHON_VALIDATION_CRASHED exit={0}' -f $PythonExit)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D2E_V4_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

$Validated = Cap 'PYTHON_TMM_REFERENCE_IMPLEMENTATION_VALIDATED'
$Checks = Cap 'ALL_OFFLINE_TMM_REFERENCE_CHECKS'
$Invariants = Cap 'ALL_TMM_INVARIANTS'
$NextPhase = Cap 'NEXT_PHASE'

$NormStatus = if ($Validated -eq 'YES') {'PASS'} else {'FAIL_CLOSED'}

@(
    'GSE243219_D2E_V4_DECISION',
    'PHASE_D2E_V4_STATUS=PASS',
    'MODE=SYNTHETIC_OFFLINE_NORMALIZATION_VALIDATION_ONLY',
    'NETWORK_ACCESS_EXECUTED=NO',
    'PACKAGE_INSTALLATION_EXECUTED=NO',
    'REAL_BIOLOGICAL_COUNTS_READ=NO',
    'D2D1_CERTIFICATION_GATE=PASS',
    'D2D1_OUTPUTS_RECERTIFIED=5/5',
    ('REUSED_VALIDATED_VENV_SOURCE={0}' -f $D2DRun),
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('INMOOSE_VERSION={0}' -f $InMooseVersion),
    ('PUBLISHED_TOY_REFERENCE_VALIDATION={0}' -f (Cap 'PUBLISHED_TOY_REFERENCE_VALIDATION')),
    ('ALL_OFFLINE_TMM_REFERENCE_CHECKS={0}' -f $Checks),
    ('ALL_TMM_INVARIANTS={0}' -f $Invariants),
    ('PYTHON_TMM_REFERENCE_IMPLEMENTATION_VALIDATED={0}' -f $Validated),
    ('TMM_NORMALIZATION_ENGINE_STATUS={0}' -f $NormStatus),
    'DGELIST_AUTHORIZED_FOR_FRACTIONAL_REAL_DATA=NO',
    ('REAL_MATRIX_CONSTRUCTION_AUTHORIZED={0}' -f $(if ($Validated -eq 'YES') {'YES_FOR_D3_ONLY'} else {'NO'})),
    'REAL_NORMALIZATION_AUTHORIZED=NO',
    'REAL_DE_AUTHORIZED=NO',
    ('NEXT_PHASE={0}' -f $NextPhase),
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Hash outputs
# ------------------------------------------------------------
$outFiles = @(
    $ValidationPy,
    $ResultJson,
    $ResultCsv,
    $FactorCsv,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D2E_V4_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p

    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D2E4SHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Final summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D2E-V4 SUMMARY ===',
    'PHASE_D2E_V4_STATUS=PASS',
    'MODE=SYNTHETIC_OFFLINE_NORMALIZATION_VALIDATION_ONLY',
    'NETWORK_ACCESS_EXECUTED=NO',
    'PACKAGE_INSTALLATION_EXECUTED=NO',
    'REAL_BIOLOGICAL_COUNTS_READ=NO',
    'REAL_MATRIX_CONSTRUCTION_EXECUTED=NO',
    'REAL_FEATURE_AGGREGATION_EXECUTED=NO',
    'REAL_NORMALIZATION_EXECUTED=NO',
    'REAL_FILTERING_EXECUTED=NO',
    'REAL_DE_EXECUTED=NO',
    'NETWORK_ANALYSIS_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'D2D1_CERTIFICATION_GATE=PASS',
    'D2D1_OUTPUTS_RECERTIFIED=5/5',
    'REUSED_D2D_VENV=YES',
    'D2D_VENV_SOURCE=D2D_PREFLIGHT_20260904_195001',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('INMOOSE_VERSION={0}' -f $InMooseVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    ('SCIPY_VERSION={0}' -f $ScipyVersion),
    'OFFLINE_REFERENCE_1=EDGER_STYLE_TMM_SPECIFICATION',
    'OFFLINE_REFERENCE_2=INDEPENDENT_RNANORM_STYLE_ORACLE',
    'OFFLINE_REFERENCE_3=PUBLISHED_RNANORM_TOY_FACTORS_1_1_0.5_2',
    ('PUBLISHED_TOY_EDGE_STYLE_MAX_ABS_DIFF={0}' -f (Cap 'PUBLISHED_TOY_EDGE_STYLE_MAX_ABS_DIFF')),
    ('PUBLISHED_TOY_ORACLE_MAX_ABS_DIFF={0}' -f (Cap 'PUBLISHED_TOY_ORACLE_MAX_ABS_DIFF')),
    ('PUBLISHED_TOY_REFERENCE_VALIDATION={0}' -f (Cap 'PUBLISHED_TOY_REFERENCE_VALIDATION')),
    ('PROPORTIONAL_UNITY_INVARIANT={0}' -f (Cap 'PROPORTIONAL_UNITY_INVARIANT')),
    ('PROPORTIONAL_MAX_ABS_FACTOR_DIFF={0}' -f (Cap 'PROPORTIONAL_MAX_ABS_FACTOR_DIFF')),
    ('PROPORTIONAL_ORACLE_CONCORDANCE={0}' -f (Cap 'PROPORTIONAL_ORACLE_CONCORDANCE')),
    ('COMPOSITION_INTEGER_MAX_ABS_FACTOR_DIFF={0}' -f (Cap 'COMPOSITION_INTEGER_MAX_ABS_FACTOR_DIFF')),
    ('COMPOSITION_INTEGER_ORACLE_CONCORDANCE={0}' -f (Cap 'COMPOSITION_INTEGER_ORACLE_CONCORDANCE')),
    ('ZERO_CONTAINING_INTEGER_MAX_ABS_FACTOR_DIFF={0}' -f (Cap 'ZERO_CONTAINING_INTEGER_MAX_ABS_FACTOR_DIFF')),
    ('ZERO_CONTAINING_INTEGER_ORACLE_CONCORDANCE={0}' -f (Cap 'ZERO_CONTAINING_INTEGER_ORACLE_CONCORDANCE')),
    ('FRACTIONAL_FIXTURE_FRACTIONAL_VALUES={0}' -f (Cap 'FRACTIONAL_FIXTURE_FRACTIONAL_VALUES')),
    ('FRACTIONAL_MAX_ABS_FACTOR_DIFF={0}' -f (Cap 'FRACTIONAL_MAX_ABS_FACTOR_DIFF')),
    ('FRACTIONAL_ORACLE_CONCORDANCE={0}' -f (Cap 'FRACTIONAL_ORACLE_CONCORDANCE')),
    ('FRACTIONAL_INPUT_UNCHANGED={0}' -f (Cap 'FRACTIONAL_INPUT_UNCHANGED')),
    ('CUSTOM_LIBSIZE_CAPABILITY={0}' -f (Cap 'CUSTOM_LIBSIZE_CAPABILITY')),
    ('NEGATIVE_COUNT_REJECTION={0}' -f (Cap 'NEGATIVE_COUNT_REJECTION')),
    ('NAN_COUNT_REJECTION={0}' -f (Cap 'NAN_COUNT_REJECTION')),
    ('ALL_OFFLINE_TMM_REFERENCE_CHECKS={0}' -f $Checks),
    ('ALL_TMM_INVARIANTS={0}' -f $Invariants),
    ('PYTHON_TMM_REFERENCE_IMPLEMENTATION_VALIDATED={0}' -f $Validated),
    ('TMM_NORMALIZATION_ENGINE_STATUS={0}' -f $NormStatus),
    'DGELIST_AUTHORIZED_FOR_FRACTIONAL_REAL_DATA=NO',
    ('READY_FOR_PHASE_D3_MATRIX_CONSTRUCTION={0}' -f $(if ($Validated -eq 'YES') {'YES'} else {'NO'})),
    'READY_FOR_REAL_NORMALIZATION=NO',
    'READY_FOR_REAL_DE=NO',
    ('NEXT_PHASE={0}' -f $NextPhase),
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D2E_V4_VALIDATION_SCRIPT={0}' -f $ValidationPy)
Write-Host ('D2E_V4_RESULT_JSON={0}' -f $ResultJson)
Write-Host ('D2E_V4_RESULT_CSV={0}' -f $ResultCsv)
Write-Host ('D2E_V4_FACTOR_COMPARISON={0}' -f $FactorCsv)
Write-Host ('D2E_V4_PYTHON_LOG={0}' -f $PythonLog)
Write-Host ('D2E_V4_DECISION={0}' -f $DecisionTxt)
Write-Host ('D2E_V4_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D2E_V4_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D2E_V4=PASS'
Write-Host 'STOP=YES'
