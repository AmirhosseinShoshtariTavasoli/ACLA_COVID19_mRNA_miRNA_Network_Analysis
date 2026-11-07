$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D2D1 — LOW-LEVEL InMoose edgepy FRACTIONAL-COUNT REDESIGN
#
# SYNTHETIC / IMPLEMENTATION DIAGNOSTIC ONLY.
#
# Purpose:
#   - prove that DGEList integer-coerces fractional counts
#   - bypass DGEList and test edgepy low-level functions directly
#   - verify fractional values are not only retained but numerically used
#   - correctly validate glmQLFTest's DataFrame-like DGELRT result
#   - verify explicit effective-library-size offsets
#
# NOT authorized:
#   - real biological matrix construction
#   - real miRNA consolidation
#   - real normalization
#   - real filtering
#   - real DE
#   - network analysis
#   - A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D2Root = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING'

$D2DRun = Join-Path $D2Root 'D2D_PREFLIGHT_20260904_195001'
$D2DManifest = Join-Path $D2DRun 'D2D_OUTPUT_SHA256_MANIFEST.csv'
$D2DDecision = Join-Path $D2DRun 'D2D_DECISION.txt'
$D2DReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D2D_20260904_195001\PHASE_D2D_SUMMARY.txt'
$VenvPython = Join-Path $D2DRun 'venv\Scripts\python.exe'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D2Root ('D2D1_LOW_LEVEL_PREFLIGHT_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D2D1_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D2D1_LOW_LEVEL_FRACTIONAL_PREFLIGHT.py'
$ResultJson = Join-Path $RunDir 'D2D1_CAPABILITY_RESULTS.json'
$ResultCsv = Join-Path $RunDir 'D2D1_CAPABILITY_RESULTS.csv'
$PythonLog = Join-Path $RunDir 'D2D1_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D2D1_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D2D1_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D2D1_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D2D1 — LOW-LEVEL InMoose FRACTIONAL-COUNT REDESIGN ==='
Write-Host 'MODE=SYNTHETIC_LOW_LEVEL_CAPABILITY_TEST_ONLY'
Write-Host 'REAL_BIOLOGICAL_COUNTS_READ=NO'
Write-Host 'REAL_MATRIX_CONSTRUCTION_EXECUTED=NO'
Write-Host 'REAL_FEATURE_AGGREGATION_EXECUTED=NO'
Write-Host 'REAL_NORMALIZATION_EXECUTED=NO'
Write-Host 'REAL_DE_EXECUTED=NO'
Write-Host 'COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @($D2DManifest,$D2DDecision,$D2DReport,$VenvPython)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D2D_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D2D1SHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

# ------------------------------------------------------------
# 1. Re-certify D2D audit state
# ------------------------------------------------------------
$d2d = Get-Content -LiteralPath $D2DReport -Raw

foreach ($tok in @(
    'PHASE_D2D_STATUS=PASS',
    'REAL_BIOLOGICAL_COUNTS_READ=NO',
    'INMOOSE_VERSION=0.9.1',
    'INMOOSE_PIN_VERIFIED=YES',
    'DGELIST_FRACTIONAL_INPUT_ACCEPTED=YES',
    'DGELIST_FRACTIONAL_VALUES_PRESERVED=NO',
    'COMMON_DISPERSION_ESTIMATION_FRACTIONAL=PASS',
    'GLMQLFIT_FRACTIONAL=PASS',
    'GLMQLFTEST_FRACTIONAL=FAIL',
    'FRACTIONAL_QL_PIPELINE_CAPABILITY_VERIFIED=NO',
    'EXTERNAL_NORMALIZATION_FACTOR_INJECTION_VERIFIED=YES',
    'NATIVE_TMM_CAPABILITY_DETECTED=NO',
    'FRACTIONAL_ENGINE_STATUS=FAIL_CLOSED',
    'NEXT_PHASE=D2D1_FRACTIONAL_EDGEPY_CAPABILITY_REDESIGN'
)) {
    if ($d2d -notmatch [regex]::Escape($tok)) {
        throw ('D2D_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$manifestRows = @(Import-Csv -LiteralPath $D2DManifest)
if ($manifestRows.Count -ne 8) {
    throw ('D2D_MANIFEST_ROW_COUNT_CHANGED expected=8 observed={0}' -f $manifestRows.Count)
}

foreach ($r in $manifestRows) {
    if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
        throw ('D2D_OUTPUT_MISSING={0}' -f $r.full_path)
    }

    $item = Get-Item -LiteralPath $r.full_path
    $hash = Get-D2D1SHA256 $r.full_path

    if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
        $hash -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D2D_OUTPUT_HASH_OR_SIZE_CHANGED={0}' -f $r.full_path)
    }
}

Write-Host 'D2D_CERTIFICATION_GATE=PASS'
Write-Host 'D2D_OUTPUTS_RECERTIFIED=8/8'

$venvVersion = & $VenvPython -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$inmooseVersion = & $VenvPython -c "import importlib.metadata as m; print(m.version('inmoose'))"

if ($venvVersion -ne '3.12.3') {
    throw ('D2D_VENV_PYTHON_CHANGED={0}' -f $venvVersion)
}
if ($inmooseVersion.Trim() -ne '0.9.1') {
    throw ('D2D_VENV_INMOOSE_CHANGED={0}' -f $inmooseVersion)
}

Write-Host 'REUSED_D2D_VENV=YES'
Write-Host ('PYTHON_VERSION={0}' -f $venvVersion)
Write-Host 'INMOOSE_VERSION=0.9.1'

# ------------------------------------------------------------
# 2. Write corrected Python synthetic preflight
# ------------------------------------------------------------
$PythonCode = @'
import csv
import inspect
import json
import math
import sys
import traceback
from pathlib import Path
from importlib.metadata import version

import numpy as np
import pandas as pd
import patsy

from inmoose.edgepy import DGEList
from inmoose.edgepy.DGELRT import DGELRT
from inmoose.edgepy.aveLogCPM import aveLogCPM
from inmoose.edgepy.estimateGLMCommonDisp import estimateGLMCommonDisp
from inmoose.edgepy.glmFit import glmFit
from inmoose.edgepy.glmQLFit import glmQLFit, glmQLFTest

RESULT_JSON = Path(sys.argv[1])
RESULT_CSV = Path(sys.argv[2])

results = {}
details = {}

def set_result(key, value, detail=None):
    results[key] = value
    if detail is not None:
        details[key] = str(detail)

def fail(key, exc):
    results[key] = "FAIL"
    details[key] = f"{type(exc).__name__}: {exc}"
    details[key + "_TRACEBACK"] = traceback.format_exc()

def finite_dataframe_numeric(df):
    num = df.select_dtypes(include=[np.number])
    if num.shape[1] == 0:
        return False
    return bool(np.isfinite(num.to_numpy(dtype=float)).all())

# ------------------------------------------------------------
# A. Environment and installed-source audit
# ------------------------------------------------------------
set_result("PYTHON_VERSION", ".".join(map(str, sys.version_info[:3])))
set_result("INMOOSE_VERSION", version("inmoose"))

src = inspect.getsource(DGEList.__init__)
details["DGELIST_INIT_SOURCE_EXCERPT"] = src
int_cast_source = ("astype(int)" in src) or ("astype(np.int" in src)
set_result("DGELIST_SOURCE_EXPLICIT_INTEGER_CAST", "YES" if int_cast_source else "NO")

details["AVELOGCPM_SIGNATURE"] = str(inspect.signature(aveLogCPM))
details["ESTIMATE_COMMON_DISP_SIGNATURE"] = str(inspect.signature(estimateGLMCommonDisp))
details["GLMFIT_SIGNATURE"] = str(inspect.signature(glmFit))
details["GLMQLFIT_SIGNATURE"] = str(inspect.signature(glmQLFit))
details["GLMQLFTEST_SIGNATURE"] = str(inspect.signature(glmQLFTest))

# ------------------------------------------------------------
# B. Deterministic fractional fixture
# ------------------------------------------------------------
n_genes = 80
n_samples = 12
genes = [f"fixture_gene_{i:03d}" for i in range(n_genes)]
samples = [f"S{i+1:02d}" for i in range(n_samples)]
groups = ["A"] * 6 + ["B"] * 6

x = np.zeros((n_genes, n_samples), dtype=float)
for i in range(n_genes):
    for j in range(n_samples):
        base = 40.0 + i * 2.75 + ((i * 13 + j * 17) % 31)
        if j >= 6 and i < 25:
            effect = 1.7
        elif j >= 6 and 25 <= i < 40:
            effect = 0.68
        else:
            effect = 1.0

        frac = (0.15, 0.35, 0.55, 0.75)[(i + j) % 4]
        x[i, j] = round(base * effect + frac, 4)

fixture = pd.DataFrame(x, index=genes, columns=samples)
truncated = pd.DataFrame(np.trunc(x), index=genes, columns=samples)

sample_df = pd.DataFrame({"group": groups}, index=samples)
design = patsy.dmatrix("~ group", data=sample_df, return_type="dataframe")

fractional_n = int(np.sum(np.abs(x - np.round(x)) > 1e-12))
set_result("FIXTURE_FRACTIONAL_VALUES", fractional_n)
set_result("FIXTURE_HAS_FRACTIONAL_VALUES", "YES" if fractional_n > 0 else "NO")

# Effective library sizes with deterministic non-unity factors.
lib_size = fixture.sum(axis=0).to_numpy(dtype=float)
norm_factors = np.array(
    [0.82, 0.87, 0.91, 0.96, 1.01, 1.06, 1.11, 1.16, 1.21, 1.26, 1.31, 1.36],
    dtype=float,
)
# Recenter to geometric mean 1, matching edgeR normalization-factor convention.
norm_factors = norm_factors / np.exp(np.mean(np.log(norm_factors)))
effective_lib = lib_size * norm_factors
offset = np.log(effective_lib)

set_result("SYNTHETIC_EXTERNAL_NORM_GEOMEAN", float(np.exp(np.mean(np.log(norm_factors)))))

# ------------------------------------------------------------
# C. Prove DGEList integer coercion
# ------------------------------------------------------------
try:
    dge = DGEList(
        counts=fixture,
        samples=sample_df.copy(),
        group_col="group",
        lib_size=lib_size,
        norm_factors=norm_factors,
    )

    observed = np.asarray(dge.counts, dtype=float)
    expected_trunc = np.asarray(fixture.astype(int), dtype=float)

    fractional_after = int(np.sum(np.abs(observed - np.round(observed)) > 1e-12))
    max_input_diff = float(np.max(np.abs(observed - x)))
    equals_truncated = bool(np.array_equal(observed, expected_trunc))

    set_result("DGELIST_FRACTIONAL_VALUES_AFTER", fractional_after)
    set_result("DGELIST_MAX_ABS_INPUT_DIFFERENCE", max_input_diff)
    set_result("DGELIST_OUTPUT_EQUALS_INTEGER_CAST", "YES" if equals_truncated else "NO")
    set_result(
        "DGELIST_INTEGER_COERCION_CONFIRMED",
        "YES" if (fractional_after == 0 and max_input_diff > 0 and equals_truncated) else "NO",
    )
except Exception as e:
    fail("DGELIST_INTEGER_COERCION_TEST", e)
    set_result("DGELIST_INTEGER_COERCION_CONFIRMED", "NO")

# ------------------------------------------------------------
# D. Low-level glmFit test: are fractional values numerically USED?
#    Same design, same fixed dispersion, same offset for fractional
#    and integer-truncated matrices. If engine silently truncates,
#    fitted results should be numerically identical.
# ------------------------------------------------------------
try:
    fixed_disp = 0.12

    fit_frac = glmFit(
        fixture,
        design=design,
        dispersion=fixed_disp,
        offset=offset,
        prior_count=0,
    )
    fit_int = glmFit(
        truncated,
        design=design,
        dispersion=fixed_disp,
        offset=offset,
        prior_count=0,
    )

    frac_counts_preserved = bool(
        np.allclose(np.asarray(fit_frac.counts, dtype=float), x, rtol=0, atol=1e-12)
    )
    coeff_diff = float(np.max(np.abs(
        np.asarray(fit_frac.coefficients, dtype=float)
        - np.asarray(fit_int.coefficients, dtype=float)
    )))
    dev_diff = float(np.max(np.abs(
        np.asarray(fit_frac.deviance, dtype=float)
        - np.asarray(fit_int.deviance, dtype=float)
    )))

    numerical_effect = bool(coeff_diff > 1e-10 or dev_diff > 1e-10)

    set_result("LOW_LEVEL_GLMFIT_FRACTIONAL_COUNTS_PRESERVED", "YES" if frac_counts_preserved else "NO")
    set_result("LOW_LEVEL_GLMFIT_MAX_COEFFICIENT_DIFF_VS_TRUNCATED", coeff_diff)
    set_result("LOW_LEVEL_GLMFIT_MAX_DEVIANCE_DIFF_VS_TRUNCATED", dev_diff)
    set_result("LOW_LEVEL_GLMFIT_FRACTIONAL_NUMERICAL_EFFECT_VERIFIED", "YES" if numerical_effect else "NO")

    off = np.asarray(fit_frac.offset, dtype=float)
    expected_off = np.broadcast_to(offset.reshape(1, -1), fixture.shape)
    offset_exact = bool(np.allclose(off, expected_off, rtol=0, atol=1e-12))
    set_result("LOW_LEVEL_EFFECTIVE_LIBRARY_OFFSET_PRESERVED", "YES" if offset_exact else "NO")
except Exception as e:
    fail("LOW_LEVEL_GLMFIT_FRACTIONAL_TEST", e)
    set_result("LOW_LEVEL_GLMFIT_FRACTIONAL_COUNTS_PRESERVED", "NO")
    set_result("LOW_LEVEL_GLMFIT_FRACTIONAL_NUMERICAL_EFFECT_VERIFIED", "NO")
    set_result("LOW_LEVEL_EFFECTIVE_LIBRARY_OFFSET_PRESERVED", "NO")

# ------------------------------------------------------------
# E. Low-level common-dispersion estimation directly on fractions
# ------------------------------------------------------------
common_disp = None
try:
    common_disp = estimateGLMCommonDisp(
        y=fixture,
        design=design,
        offset=offset,
        subset=n_genes,
        AveLogCPM=None,
        verbose=False,
        weights=None,
    )
    common_disp = float(common_disp)

    ok = bool(math.isfinite(common_disp) and common_disp >= 0)
    set_result("LOW_LEVEL_COMMON_DISPERSION_FRACTIONAL", "PASS" if ok else "FAIL")
    set_result("LOW_LEVEL_COMMON_DISPERSION_VALUE", common_disp)
except Exception as e:
    fail("LOW_LEVEL_COMMON_DISPERSION_FRACTIONAL", e)

# ------------------------------------------------------------
# F. Compute AveLogCPM with the SAME effective library sizes.
#    Introspect API rather than assume one spelling.
# ------------------------------------------------------------
ave = None
try:
    sig = inspect.signature(aveLogCPM)
    params = sig.parameters

    kwargs = {}
    if "offset" in params:
        kwargs["offset"] = offset
        set_result("AVELOGCPM_EFFECTIVE_LIBRARY_ROUTE", "OFFSET")
    elif "lib_size" in params:
        kwargs["lib_size"] = effective_lib
        set_result("AVELOGCPM_EFFECTIVE_LIBRARY_ROUTE", "LIB_SIZE")
    else:
        raise RuntimeError("aveLogCPM exposes neither offset nor lib_size")

    if "dispersion" in params and common_disp is not None:
        kwargs["dispersion"] = common_disp

    ave = np.asarray(aveLogCPM(fixture, **kwargs), dtype=float)
    ok = bool(ave.shape[0] == n_genes and np.isfinite(ave).all())
    set_result("AVELOGCPM_EFFECTIVE_LIBRARY_CAPABILITY", "PASS" if ok else "FAIL")
    details["AVELOGCPM_OUTPUT_SHAPE"] = str(ave.shape)
except Exception as e:
    fail("AVELOGCPM_EFFECTIVE_LIBRARY_CAPABILITY", e)

# ------------------------------------------------------------
# G. Low-level QL fit directly on fractional counts
# ------------------------------------------------------------
qlfit = None
if common_disp is not None and ave is not None:
    try:
        qlfit = glmQLFit(
            y=fixture,
            design=design,
            dispersion=common_disp,
            offset=offset,
            lib_size=None,
            abundance_trend=True,
            AveLogCPM=ave,
            robust=False,
        )

        counts_exact = bool(
            np.allclose(np.asarray(qlfit.counts, dtype=float), x, rtol=0, atol=1e-12)
        )
        ql_offset = np.asarray(qlfit.offset, dtype=float)
        expected_off = np.broadcast_to(offset.reshape(1, -1), fixture.shape)
        offset_exact = bool(np.allclose(ql_offset, expected_off, rtol=0, atol=1e-12))

        coef = np.asarray(qlfit.coefficients, dtype=float)
        var_post = np.asarray(qlfit.var_post, dtype=float)

        fit_ok = bool(
            counts_exact
            and offset_exact
            and coef.shape[0] == n_genes
            and np.isfinite(coef).all()
            and var_post.shape[0] == n_genes
            and np.isfinite(var_post).all()
        )

        set_result("LOW_LEVEL_GLMQLFIT_FRACTIONAL", "PASS" if fit_ok else "FAIL")
        set_result("LOW_LEVEL_GLMQLFIT_COUNTS_PRESERVED", "YES" if counts_exact else "NO")
        set_result("LOW_LEVEL_GLMQLFIT_OFFSET_PRESERVED", "YES" if offset_exact else "NO")
        details["LOW_LEVEL_GLMQLFIT_COEFFICIENT_SHAPE"] = str(coef.shape)
    except Exception as e:
        fail("LOW_LEVEL_GLMQLFIT_FRACTIONAL", e)
else:
    set_result("LOW_LEVEL_GLMQLFIT_FRACTIONAL", "NOT_RUN")

# ------------------------------------------------------------
# H. Correct glmQLFTest validation.
#    InMoose returns DGELRT, which is itself DataFrame-like.
# ------------------------------------------------------------
if qlfit is not None:
    for poisson_bound in (True, False):
        key = "LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_" + ("TRUE" if poisson_bound else "FALSE")
        try:
            qlf = glmQLFTest(qlfit, coef=1, poisson_bound=poisson_bound)

            is_dgelrt = isinstance(qlf, DGELRT)
            is_df = isinstance(qlf, pd.DataFrame)
            rows_ok = int(qlf.shape[0]) == n_genes
            required_cols = {"log2FoldChange", "logCPM", "stat", "pvalue"}
            cols_ok = required_cols.issubset(set(map(str, qlf.columns)))
            finite_ok = finite_dataframe_numeric(qlf)
            p = np.asarray(qlf["pvalue"], dtype=float)
            p_ok = bool(np.isfinite(p).all() and (p >= 0).all() and (p <= 1).all())

            ok = is_dgelrt and is_df and rows_ok and cols_ok and finite_ok and p_ok

            set_result(key, "PASS" if ok else "FAIL")
            details[key + "_TYPE"] = type(qlf).__name__
            details[key + "_SHAPE"] = str(qlf.shape)
            details[key + "_COLUMNS"] = "|".join(map(str, qlf.columns))
        except Exception as e:
            fail(key, e)
else:
    set_result("LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_TRUE", "NOT_RUN")
    set_result("LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_FALSE", "NOT_RUN")

# ------------------------------------------------------------
# I. Final capability decision
# ------------------------------------------------------------
low_level_capability = (
    results.get("DGELIST_SOURCE_EXPLICIT_INTEGER_CAST") == "YES"
    and results.get("DGELIST_INTEGER_COERCION_CONFIRMED") == "YES"
    and results.get("LOW_LEVEL_GLMFIT_FRACTIONAL_COUNTS_PRESERVED") == "YES"
    and results.get("LOW_LEVEL_GLMFIT_FRACTIONAL_NUMERICAL_EFFECT_VERIFIED") == "YES"
    and results.get("LOW_LEVEL_EFFECTIVE_LIBRARY_OFFSET_PRESERVED") == "YES"
    and results.get("LOW_LEVEL_COMMON_DISPERSION_FRACTIONAL") == "PASS"
    and results.get("AVELOGCPM_EFFECTIVE_LIBRARY_CAPABILITY") == "PASS"
    and results.get("LOW_LEVEL_GLMQLFIT_FRACTIONAL") == "PASS"
    and results.get("LOW_LEVEL_GLMQLFIT_COUNTS_PRESERVED") == "YES"
    and results.get("LOW_LEVEL_GLMQLFIT_OFFSET_PRESERVED") == "YES"
    and results.get("LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_TRUE") == "PASS"
    and results.get("LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_FALSE") == "PASS"
)

set_result(
    "LOW_LEVEL_FRACTIONAL_QL_PIPELINE_CAPABILITY_VERIFIED",
    "YES" if low_level_capability else "NO",
)

if low_level_capability:
    next_phase = "D2E_PYTHON_TMM_REFERENCE_IMPLEMENTATION_VALIDATION"
else:
    next_phase = "D2D2_ALTERNATIVE_FRACTIONAL_COUNT_DE_ENGINE_REVIEW"

set_result("NEXT_PHASE", next_phase)

payload = {"results": results, "details": details}
RESULT_JSON.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")

with RESULT_CSV.open("w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["key", "value", "detail"])
    for key in sorted(results):
        w.writerow([key, results[key], details.get(key, "")])

for key in [
    "PYTHON_VERSION",
    "INMOOSE_VERSION",
    "DGELIST_SOURCE_EXPLICIT_INTEGER_CAST",
    "FIXTURE_FRACTIONAL_VALUES",
    "DGELIST_INTEGER_COERCION_CONFIRMED",
    "DGELIST_MAX_ABS_INPUT_DIFFERENCE",
    "LOW_LEVEL_GLMFIT_FRACTIONAL_COUNTS_PRESERVED",
    "LOW_LEVEL_GLMFIT_FRACTIONAL_NUMERICAL_EFFECT_VERIFIED",
    "LOW_LEVEL_GLMFIT_MAX_COEFFICIENT_DIFF_VS_TRUNCATED",
    "LOW_LEVEL_GLMFIT_MAX_DEVIANCE_DIFF_VS_TRUNCATED",
    "LOW_LEVEL_EFFECTIVE_LIBRARY_OFFSET_PRESERVED",
    "LOW_LEVEL_COMMON_DISPERSION_FRACTIONAL",
    "LOW_LEVEL_COMMON_DISPERSION_VALUE",
    "AVELOGCPM_EFFECTIVE_LIBRARY_ROUTE",
    "AVELOGCPM_EFFECTIVE_LIBRARY_CAPABILITY",
    "LOW_LEVEL_GLMQLFIT_FRACTIONAL",
    "LOW_LEVEL_GLMQLFIT_COUNTS_PRESERVED",
    "LOW_LEVEL_GLMQLFIT_OFFSET_PRESERVED",
    "LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_TRUE",
    "LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_FALSE",
    "LOW_LEVEL_FRACTIONAL_QL_PIPELINE_CAPABILITY_VERIFIED",
    "NEXT_PHASE",
]:
    print(f"{key}={results.get(key, 'MISSING')}")
'@

$PythonCode | Set-Content -LiteralPath $PyScript -Encoding UTF8

# ------------------------------------------------------------
# 3. Run corrected low-level preflight
# ------------------------------------------------------------
$logLines = New-Object 'System.Collections.Generic.List[string]'

& $VenvPython $PyScript $ResultJson $ResultCsv 2>&1 |
    ForEach-Object {
        [void]$logLines.Add([string]$_)
        Write-Host $_
    }

$logLines | Set-Content -LiteralPath $PythonLog -Encoding UTF8

if ($LASTEXITCODE -ne 0) {
    throw ('D2D1_PYTHON_DIAGNOSTIC_CRASHED exit={0}' -f $LASTEXITCODE)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D2D1_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

$SourceCast = Cap 'DGELIST_SOURCE_EXPLICIT_INTEGER_CAST'
$CastConfirmed = Cap 'DGELIST_INTEGER_COERCION_CONFIRMED'
$LowLevel = Cap 'LOW_LEVEL_FRACTIONAL_QL_PIPELINE_CAPABILITY_VERIFIED'
$NextPhase = Cap 'NEXT_PHASE'

if ($SourceCast -ne 'YES' -or $CastConfirmed -ne 'YES') {
    throw ('DGELIST_INTEGER_CAST_DIAGNOSIS_NOT_CONFIRMED source={0} runtime={1}' -f $SourceCast,$CastConfirmed)
}

$EngineStatus = if ($LowLevel -eq 'YES') {
    'LOW_LEVEL_EDGEPY_FRACTIONAL_PIPELINE_PASS'
}
else {
    'LOW_LEVEL_EDGEPY_FRACTIONAL_PIPELINE_FAIL_CLOSED'
}

@(
    'GSE243219_D2D1_DECISION',
    'PHASE_D2D1_STATUS=PASS',
    'MODE=SYNTHETIC_LOW_LEVEL_CAPABILITY_TEST_ONLY',
    'REAL_BIOLOGICAL_COUNTS_READ=NO',
    'D2D_CERTIFICATION_GATE=PASS',
    'D2D_OUTPUTS_RECERTIFIED=8/8',
    'PYTHON_VERSION=3.12.3',
    'INMOOSE_VERSION=0.9.1',
    ('DGELIST_SOURCE_EXPLICIT_INTEGER_CAST={0}' -f $SourceCast),
    ('DGELIST_INTEGER_COERCION_CONFIRMED={0}' -f $CastConfirmed),
    'DGELIST_AUTHORIZED_FOR_FRACTIONAL_REAL_DATA=NO',
    ('LOW_LEVEL_FRACTIONAL_QL_PIPELINE_CAPABILITY_VERIFIED={0}' -f $LowLevel),
    ('FRACTIONAL_ENGINE_STATUS={0}' -f $EngineStatus),
    'REAL_MATRIX_CONSTRUCTION_AUTHORIZED=NO',
    'REAL_NORMALIZATION_AUTHORIZED=NO',
    'REAL_DE_AUTHORIZED=NO',
    ('NEXT_PHASE={0}' -f $NextPhase),
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Hash outputs
# ------------------------------------------------------------
$outFiles = @($PyScript,$ResultJson,$ResultCsv,$PythonLog,$DecisionTxt)
$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    $item = Get-Item -LiteralPath $p
    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D2D1SHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Final summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D2D1 SUMMARY ===',
    'PHASE_D2D1_STATUS=PASS',
    'MODE=SYNTHETIC_LOW_LEVEL_CAPABILITY_TEST_ONLY',
    'REAL_BIOLOGICAL_COUNTS_READ=NO',
    'REAL_MATRIX_CONSTRUCTION_EXECUTED=NO',
    'REAL_FEATURE_AGGREGATION_EXECUTED=NO',
    'REAL_NORMALIZATION_EXECUTED=NO',
    'REAL_DE_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'D2D_CERTIFICATION_GATE=PASS',
    'D2D_OUTPUTS_RECERTIFIED=8/8',
    'PYTHON_VERSION=3.12.3',
    'INMOOSE_VERSION=0.9.1',
    ('DGELIST_SOURCE_EXPLICIT_INTEGER_CAST={0}' -f (Cap 'DGELIST_SOURCE_EXPLICIT_INTEGER_CAST')),
    ('DGELIST_INTEGER_COERCION_CONFIRMED={0}' -f (Cap 'DGELIST_INTEGER_COERCION_CONFIRMED')),
    ('DGELIST_MAX_ABS_INPUT_DIFFERENCE={0}' -f (Cap 'DGELIST_MAX_ABS_INPUT_DIFFERENCE')),
    'DGELIST_AUTHORIZED_FOR_FRACTIONAL_REAL_DATA=NO',
    ('LOW_LEVEL_GLMFIT_FRACTIONAL_COUNTS_PRESERVED={0}' -f (Cap 'LOW_LEVEL_GLMFIT_FRACTIONAL_COUNTS_PRESERVED')),
    ('LOW_LEVEL_GLMFIT_FRACTIONAL_NUMERICAL_EFFECT_VERIFIED={0}' -f (Cap 'LOW_LEVEL_GLMFIT_FRACTIONAL_NUMERICAL_EFFECT_VERIFIED')),
    ('LOW_LEVEL_EFFECTIVE_LIBRARY_OFFSET_PRESERVED={0}' -f (Cap 'LOW_LEVEL_EFFECTIVE_LIBRARY_OFFSET_PRESERVED')),
    ('LOW_LEVEL_COMMON_DISPERSION_FRACTIONAL={0}' -f (Cap 'LOW_LEVEL_COMMON_DISPERSION_FRACTIONAL')),
    ('AVELOGCPM_EFFECTIVE_LIBRARY_ROUTE={0}' -f (Cap 'AVELOGCPM_EFFECTIVE_LIBRARY_ROUTE')),
    ('AVELOGCPM_EFFECTIVE_LIBRARY_CAPABILITY={0}' -f (Cap 'AVELOGCPM_EFFECTIVE_LIBRARY_CAPABILITY')),
    ('LOW_LEVEL_GLMQLFIT_FRACTIONAL={0}' -f (Cap 'LOW_LEVEL_GLMQLFIT_FRACTIONAL')),
    ('LOW_LEVEL_GLMQLFIT_COUNTS_PRESERVED={0}' -f (Cap 'LOW_LEVEL_GLMQLFIT_COUNTS_PRESERVED')),
    ('LOW_LEVEL_GLMQLFIT_OFFSET_PRESERVED={0}' -f (Cap 'LOW_LEVEL_GLMQLFIT_OFFSET_PRESERVED')),
    ('LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_TRUE={0}' -f (Cap 'LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_TRUE')),
    ('LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_FALSE={0}' -f (Cap 'LOW_LEVEL_GLMQLFTEST_POISSON_BOUND_FALSE')),
    ('LOW_LEVEL_FRACTIONAL_QL_PIPELINE_CAPABILITY_VERIFIED={0}' -f $LowLevel),
    ('FRACTIONAL_ENGINE_STATUS={0}' -f $EngineStatus),
    'REAL_MATRIX_CONSTRUCTION_AUTHORIZED=NO',
    'REAL_NORMALIZATION_AUTHORIZED=NO',
    'REAL_DE_AUTHORIZED=NO',
    'READY_FOR_MATRIX_CONSTRUCTION=NO',
    'READY_FOR_NORMALIZATION=NO',
    'READY_FOR_DE=NO',
    ('NEXT_PHASE={0}' -f $NextPhase),
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D2D1_PYTHON_SCRIPT={0}' -f $PyScript)
Write-Host ('D2D1_RESULT_JSON={0}' -f $ResultJson)
Write-Host ('D2D1_RESULT_CSV={0}' -f $ResultCsv)
Write-Host ('D2D1_PYTHON_LOG={0}' -f $PythonLog)
Write-Host ('D2D1_DECISION={0}' -f $DecisionTxt)
Write-Host ('D2D1_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D2D1_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D2D1=PASS'
Write-Host 'STOP=YES'
