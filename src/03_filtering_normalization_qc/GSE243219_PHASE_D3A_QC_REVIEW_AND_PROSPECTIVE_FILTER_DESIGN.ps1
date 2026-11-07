$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D3A — QC REVIEW + PROSPECTIVE FEATURE-FILTER DESIGN
#
# Reads certified D3-V2 matrices and QC summaries.
#
# Authorized:
#   - descriptive QC review
#   - robust REVIEW-ONLY sample-QC flags
#   - calculate candidate feature-retention masks using the
#     current edgeR filterByExpr default specification
#   - freeze the feature-filter strategy for the next phase
#
# Not authorized:
#   - apply feature filtering to create analysis matrices
#   - sample exclusion
#   - TMM normalization
#   - normalized/logCPM analysis matrix creation
#   - DE
#   - network construction
#   - A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D3Root = Join-Path $Project '03_QC_AND_FILTERING'

$D3Run = Join-Path $D3Root 'D3_V2_MATRIX_QC_20260904_231245'
$D3Manifest = Join-Path $D3Run 'D3_OUTPUT_SHA256_MANIFEST.csv'
$D3Decision = Join-Path $D3Run 'D3_DECISION.txt'
$D3Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D3_V2_20260904_231245\PHASE_D3_SUMMARY.txt'

$Metadata = Join-Path $D3Run 'D3_PAIRED_SAMPLE_METADATA.csv'
$MrnaMatrix = Join-Path $D3Run 'D3_MRNA_RAW_COUNTS_26364x72.csv.gz'
$MirnaMatrix = Join-Path $D3Run 'D3_MIRNA_MATURE_MEDIAN_COUNTS_2656x72.csv.gz'
$QcMetrics = Join-Path $D3Run 'D3_SAMPLE_QC_PREFLIGHT_METRICS.csv'

$D2DRun = Join-Path (Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING') 'D2D_PREFLIGHT_20260904_195001'
$VenvPython = Join-Path $D2DRun 'venv\Scripts\python.exe'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D3Root ('D3A_QC_FILTER_DESIGN_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D3A_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D3A_QC_REVIEW_AND_FILTER_DESIGN.py'
$QcReview = Join-Path $RunDir 'D3A_SAMPLE_QC_REVIEW.csv'
$QcSummary = Join-Path $RunDir 'D3A_QC_DISTRIBUTION_SUMMARY.csv'
$MrnaFilter = Join-Path $RunDir 'D3A_MRNA_FILTERBYEXPR_CANDIDATE.csv.gz'
$MirnaFilter = Join-Path $RunDir 'D3A_MIRNA_FILTERBYEXPR_CANDIDATE.csv.gz'
$FilterSummary = Join-Path $RunDir 'D3A_FEATURE_FILTER_SUMMARY.csv'
$FrozenStrategy = Join-Path $RunDir 'D3A_FROZEN_QC_AND_FILTER_STRATEGY.txt'
$ResultJson = Join-Path $RunDir 'D3A_RESULT.json'
$PythonStdout = Join-Path $RunDir 'D3A_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D3A_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D3A_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D3A_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D3A_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D3A_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D3A — QC REVIEW + PROSPECTIVE FEATURE-FILTER DESIGN ==='
Write-Host 'MODE=REVIEW_AND_DESIGN_ONLY'
Write-Host 'REAL_BIOLOGICAL_MATRICES_READ=YES'
Write-Host 'FILTER_SCREEN_CPM_COMPUTED=YES'
Write-Host 'FEATURE_FILTER_APPLICATION_EXECUTED=NO'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'TMM_NORMALIZATION_EXECUTED=NO'
Write-Host 'NORMALIZED_MATRIX_CREATED=NO'
Write-Host 'DE_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $D3Manifest,$D3Decision,$D3Report,
    $Metadata,$MrnaMatrix,$MirnaMatrix,$QcMetrics,$VenvPython
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D3A_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D3ASHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

$d3 = Get-Content -LiteralPath $D3Report -Raw

foreach ($tok in @(
    'PHASE_D3_V2_STATUS=PASS',
    'REAL_BIOLOGICAL_COUNTS_READ=YES',
    'MRNA_COUNT_ROUNDING_EXECUTED=NO',
    'ZERO_FILL_EXECUTED=NO',
    'REAL_NORMALIZATION_EXECUTED=NO',
    'FILTERING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'SOURCE_COUNT_FILES_HASHED=144',
    'PAIRED_SUBJECTS=72',
    'PHENOTYPE_COUNTS=COVID19=35|SEPSIS=22|HEALTHY=15',
    'MRNA_MATRIX_ROWS=26364',
    'MRNA_MATRIX_SAMPLES=72',
    'MRNA_FRACTIONAL_VALUES=355532',
    'MIRNA_RAW_MATRIX_ROWS=2886',
    'MIRNA_MATURE_PRIMARY_ROWS=2656',
    'MIRNA_REPEATED_REGULATORY_IDENTITIES=166',
    'MIRNA_PRIMARY_MEDIAN_FRACTIONAL_VALUES=666',
    'CROSS_MODALITY_MATRIX_SAMPLE_ORDER_IDENTICAL=YES',
    'MATRIX_ROUNDTRIP_INTEGRITY=PASS',
    'MATRIX_CONSTRUCTION_COMPLETE=YES',
    'QC_PREFLIGHT_METRICS_COMPLETE=YES',
    'READY_FOR_QC_REVIEW_AND_FILTER_DESIGN=YES',
    'NEXT_PHASE=D3A_QC_REVIEW_AND_PROSPECTIVE_FILTER_DESIGN'
)) {
    if ($d3 -notmatch [regex]::Escape($tok)) {
        throw ('D3_V2_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$manifestRows = @(Import-Csv -LiteralPath $D3Manifest)

if ($manifestRows.Count -ne 15) {
    throw ('D3_V2_MANIFEST_ROW_COUNT_CHANGED expected=15 observed={0}' -f $manifestRows.Count)
}

foreach ($r in $manifestRows) {
    if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
        throw ('D3_V2_OUTPUT_MISSING={0}' -f $r.full_path)
    }

    $item = Get-Item -LiteralPath $r.full_path
    $hash = Get-D3ASHA256 $r.full_path

    if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
        $hash -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D3_V2_OUTPUT_CHANGED={0}' -f $r.full_path)
    }
}

Write-Host 'D3_V2_CERTIFICATION_GATE=PASS'
Write-Host 'D3_V2_OUTPUTS_RECERTIFIED=15/15'

$PythonVersion = & $VenvPython -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$PandasVersion = & $VenvPython -c "import pandas; print(pandas.__version__)"
$NumpyVersion = & $VenvPython -c "import numpy; print(numpy.__version__)"

if ($PythonVersion -ne '3.12.3') {
    throw ('VALIDATED_PYTHON_CHANGED={0}' -f $PythonVersion)
}

Write-Host ('PYTHON_VERSION={0}' -f $PythonVersion)
Write-Host ('PANDAS_VERSION={0}' -f $PandasVersion)
Write-Host ('NUMPY_VERSION={0}' -f $NumpyVersion)

$PythonCode = @'
import json
import math
import sys
from pathlib import Path

import numpy as np
import pandas as pd

METADATA = Path(sys.argv[1])
MRNA = Path(sys.argv[2])
MIRNA = Path(sys.argv[3])
QC = Path(sys.argv[4])

QC_REVIEW = Path(sys.argv[5])
QC_SUMMARY = Path(sys.argv[6])
MRNA_FILTER = Path(sys.argv[7])
MIRNA_FILTER = Path(sys.argv[8])
FILTER_SUMMARY = Path(sys.argv[9])
FROZEN_STRATEGY = Path(sys.argv[10])
RESULT_JSON = Path(sys.argv[11])

results = {}

def put(key, value):
    results[key] = value
    print(f"{key}={value}")

MIN_COUNT = 10.0
MIN_TOTAL_COUNT = 15.0
LARGE_N = 10.0
MIN_PROP = 0.7

metadata = pd.read_csv(METADATA)
mrna = pd.read_csv(
    MRNA,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
mirna = pd.read_csv(
    MIRNA,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
qc = pd.read_csv(QC)

if metadata.shape[0] != 72:
    raise RuntimeError(f"METADATA_ROWS_NOT_72 observed={metadata.shape[0]}")
if mrna.shape != (26364, 72):
    raise RuntimeError(f"MRNA_DIMENSION_CHANGED observed={mrna.shape}")
if mirna.shape != (2656, 72):
    raise RuntimeError(f"MIRNA_DIMENSION_CHANGED observed={mirna.shape}")

subjects = metadata["subject_id"].astype(str).tolist()
groups = metadata["disease_state"].astype(str).tolist()

if list(mrna.columns) != subjects:
    raise RuntimeError("MRNA_SAMPLE_ORDER_DOES_NOT_MATCH_METADATA")
if list(mirna.columns) != subjects:
    raise RuntimeError("MIRNA_SAMPLE_ORDER_DOES_NOT_MATCH_METADATA")

group_counts = pd.Series(groups).value_counts().to_dict()
expected = {"COVID19": 35, "SEPSIS": 22, "HEALTHY": 15}
if group_counts != expected:
    raise RuntimeError(f"GROUP_COUNTS_CHANGED observed={group_counts}")

min_group_size = float(min(group_counts.values()))
min_sample_size = min_group_size

if min_sample_size > LARGE_N:
    min_sample_size = LARGE_N + (min_sample_size - LARGE_N) * MIN_PROP

min_samples_integer = int(math.ceil(min_sample_size - 1e-12))

put("FILTERBYEXPR_MIN_COUNT", MIN_COUNT)
put("FILTERBYEXPR_MIN_TOTAL_COUNT", MIN_TOTAL_COUNT)
put("FILTERBYEXPR_LARGE_N", LARGE_N)
put("FILTERBYEXPR_MIN_PROP", MIN_PROP)
put("SMALLEST_GROUP_SIZE", int(min_group_size))
put("FILTERBYEXPR_MIN_SAMPLE_SIZE_NUMERIC", min_sample_size)
put("FILTERBYEXPR_EFFECTIVE_MIN_SAMPLES_INTEGER", min_samples_integer)

def filter_design(matrix, label):
    x = matrix.to_numpy(dtype=np.float64)

    if np.any(~np.isfinite(x)):
        raise RuntimeError(f"{label}_NONFINITE")
    if np.any(x < 0):
        raise RuntimeError(f"{label}_NEGATIVE")

    lib = np.sum(x, axis=0, dtype=np.float64)

    if np.any(lib <= 0):
        raise RuntimeError(f"{label}_NONPOSITIVE_LIBRARY_SIZE")

    median_lib = float(np.median(lib))
    cpm_cutoff = MIN_COUNT / median_lib * 1e6

    cpm = x / lib[np.newaxis, :] * 1e6
    samples_above = np.sum(cpm >= cpm_cutoff, axis=1)
    total = np.sum(x, axis=1, dtype=np.float64)

    pass_cpm = samples_above >= min_sample_size
    pass_total = total >= MIN_TOTAL_COUNT
    keep = pass_cpm & pass_total

    out = pd.DataFrame({
        "feature_id": matrix.index.astype(str),
        "samples_at_or_above_cpm_cutoff": samples_above.astype(int),
        "total_count": total,
        "passes_cpm_sample_requirement": np.where(pass_cpm, "YES", "NO"),
        "passes_min_total_count": np.where(pass_total, "YES", "NO"),
        "candidate_keep": np.where(keep, "YES", "NO"),
    })

    return {
        "library_min": float(np.min(lib)),
        "library_q1": float(np.quantile(lib, 0.25)),
        "library_median": median_lib,
        "library_q3": float(np.quantile(lib, 0.75)),
        "library_max": float(np.max(lib)),
        "cpm_cutoff": float(cpm_cutoff),
        "keep_count": int(np.sum(keep)),
        "drop_count": int(np.sum(~keep)),
        "keep_fraction": float(np.mean(keep)),
        "table": out,
    }

mrna_f = filter_design(mrna, "MRNA")
mirna_f = filter_design(mirna, "MIRNA_PRIMARY")

mrna_f["table"].to_csv(MRNA_FILTER, index=False, compression="gzip")
mirna_f["table"].to_csv(MIRNA_FILTER, index=False, compression="gzip")

put("MRNA_FILTER_CPM_CUTOFF", mrna_f["cpm_cutoff"])
put("MRNA_CANDIDATE_KEEP_FEATURES", mrna_f["keep_count"])
put("MRNA_CANDIDATE_DROP_FEATURES", mrna_f["drop_count"])
put("MIRNA_FILTER_CPM_CUTOFF", mirna_f["cpm_cutoff"])
put("MIRNA_CANDIDATE_KEEP_FEATURES", mirna_f["keep_count"])
put("MIRNA_CANDIDATE_DROP_FEATURES", mirna_f["drop_count"])

primary_qc = qc[
    qc["modality"].isin(["mRNA_raw", "miRNA_mature_median_primary"])
].copy()

if primary_qc.shape[0] != 144:
    raise RuntimeError(
        f"PRIMARY_QC_ROWS_NOT_144 observed={primary_qc.shape[0]}"
    )

metrics = ["library_sum", "nonzero_features", "zero_fraction"]

def modified_z(values):
    values = np.asarray(values, dtype=np.float64)
    med = np.median(values)
    mad = np.median(np.abs(values - med))

    if mad == 0:
        return np.zeros(values.size, dtype=np.float64), float(med), float(mad)

    z = 0.6744897501960817 * (values - med) / mad
    return z, float(med), float(mad)

review_rows = []
summary_rows = []

for modality, mdf in primary_qc.groupby("modality", sort=False):
    mdf = mdf.copy()

    for metric in metrics:
        vals = mdf[metric].to_numpy(dtype=np.float64)
        summary_rows.append({
            "modality": modality,
            "scope": "ALL",
            "disease_state": "ALL",
            "metric": metric,
            "min": float(np.min(vals)),
            "q1": float(np.quantile(vals, 0.25)),
            "median": float(np.median(vals)),
            "q3": float(np.quantile(vals, 0.75)),
            "max": float(np.max(vals)),
            "mean": float(np.mean(vals)),
            "std": float(np.std(vals, ddof=1)),
        })

    for disease, gdf in mdf.groupby("disease_state", sort=False):
        for metric in metrics:
            vals = gdf[metric].to_numpy(dtype=np.float64)
            summary_rows.append({
                "modality": modality,
                "scope": "WITHIN_DISEASE",
                "disease_state": disease,
                "metric": metric,
                "min": float(np.min(vals)),
                "q1": float(np.quantile(vals, 0.25)),
                "median": float(np.median(vals)),
                "q3": float(np.quantile(vals, 0.75)),
                "max": float(np.max(vals)),
                "mean": float(np.mean(vals)),
                "std": float(np.std(vals, ddof=1)),
            })

    for _, row in mdf.iterrows():
        subject = str(row["subject_id"])
        disease = str(row["disease_state"])

        global_flags = 0
        within_flags = 0
        review = {
            "subject_id": subject,
            "disease_state": disease,
            "modality": modality,
        }

        for metric in metrics:
            all_vals = mdf[metric].to_numpy(dtype=np.float64)
            all_z, _, _ = modified_z(all_vals)
            position = list(mdf["subject_id"].astype(str)).index(subject)
            gz = float(all_z[position])

            disease_df = mdf[mdf["disease_state"] == disease]
            disease_vals = disease_df[metric].to_numpy(dtype=np.float64)
            disease_z, _, _ = modified_z(disease_vals)
            dposition = list(disease_df["subject_id"].astype(str)).index(subject)
            dz = float(disease_z[dposition])

            review[f"{metric}_global_modified_z"] = gz
            review[f"{metric}_within_disease_modified_z"] = dz

            if abs(gz) >= 3.5:
                global_flags += 1
            if abs(dz) >= 3.5:
                within_flags += 1

        review["global_extreme_metric_count"] = global_flags
        review["within_disease_extreme_metric_count"] = within_flags

        review["qc_review_flag"] = (
            "REVIEW"
            if (global_flags >= 2 or within_flags >= 2)
            else "NO_MULTIMETRIC_FLAG"
        )
        review["sample_exclusion_authorized"] = "NO"

        review_rows.append(review)

review_df = pd.DataFrame(review_rows)
review_df.to_csv(QC_REVIEW, index=False)
pd.DataFrame(summary_rows).to_csv(QC_SUMMARY, index=False)

review_sample_ids = sorted(
    set(review_df.loc[review_df["qc_review_flag"] == "REVIEW", "subject_id"].astype(str))
)

put("QC_PRIMARY_MODALITY_ROWS", int(primary_qc.shape[0]))
put("QC_REVIEW_FLAGGED_SUBJECTS", len(review_sample_ids))
put(
    "QC_REVIEW_FLAGGED_SUBJECT_IDS",
    "|".join(review_sample_ids) if review_sample_ids else "NONE",
)
put("SAMPLE_EXCLUSION_AUTHORIZED", "NO")

filter_summary = pd.DataFrame([
    {
        "modality": "mRNA",
        "input_features": mrna.shape[0],
        "candidate_keep_features": mrna_f["keep_count"],
        "candidate_drop_features": mrna_f["drop_count"],
        "candidate_keep_fraction": mrna_f["keep_fraction"],
        "raw_library_min": mrna_f["library_min"],
        "raw_library_q1": mrna_f["library_q1"],
        "raw_library_median": mrna_f["library_median"],
        "raw_library_q3": mrna_f["library_q3"],
        "raw_library_max": mrna_f["library_max"],
        "cpm_cutoff": mrna_f["cpm_cutoff"],
    },
    {
        "modality": "miRNA_mature_median_primary",
        "input_features": mirna.shape[0],
        "candidate_keep_features": mirna_f["keep_count"],
        "candidate_drop_features": mirna_f["drop_count"],
        "candidate_keep_fraction": mirna_f["keep_fraction"],
        "raw_library_min": mirna_f["library_min"],
        "raw_library_q1": mirna_f["library_q1"],
        "raw_library_median": mirna_f["library_median"],
        "raw_library_q3": mirna_f["library_q3"],
        "raw_library_max": mirna_f["library_max"],
        "cpm_cutoff": mirna_f["cpm_cutoff"],
    },
])
filter_summary.to_csv(FILTER_SUMMARY, index=False)

strategy_lines = [
    "GSE243219_D3A_FROZEN_QC_AND_FILTER_STRATEGY",
    "FEATURE_FILTER_METHOD=EDGER_FILTERBYEXPR_DEFAULT_SPECIFICATION",
    "FILTER_INPUT_LIBRARY_SIZE=RAW_COLUMN_SUMS",
    "FILTER_CPM_FORMULA=count/lib_size*1e6",
    f"FILTER_MIN_COUNT={MIN_COUNT:g}",
    f"FILTER_MIN_TOTAL_COUNT={MIN_TOTAL_COUNT:g}",
    f"FILTER_LARGE_N={LARGE_N:g}",
    f"FILTER_MIN_PROP={MIN_PROP:g}",
    f"SMALLEST_GROUP_SIZE={int(min_group_size)}",
    f"FILTER_MIN_SAMPLE_SIZE_NUMERIC={min_sample_size:g}",
    f"FILTER_EFFECTIVE_MIN_SAMPLES_INTEGER={min_samples_integer}",
    "FILTER_GROUP_USE=MINIMUM_GROUP_SIZE_ONLY",
    "FILTER_GROUP_SPECIFIC_EXPRESSION_SELECTION=PROHIBITED",
    "FEATURE_FILTER_APPLICATION_EXECUTED=NO",
    "SAMPLE_QC_FLAG_METHOD=MODIFIED_Z_REVIEW_ONLY",
    "SAMPLE_QC_FLAG_THRESHOLD_ABS_MODIFIED_Z=3.5",
    "SAMPLE_QC_MULTIMETRIC_REVIEW_RULE=AT_LEAST_2_EXTREME_METRICS",
    "SAMPLE_QC_WITHIN_DISEASE_REVIEW=YES",
    "SAMPLE_EXCLUSION_AUTOMATIC=NO",
    "SAMPLE_EXCLUSION_AUTHORIZED=NO",
    "TMM_NORMALIZATION_EXECUTED=NO",
    "DE_EXECUTED=NO",
    "FEATURE_FILTER_STRATEGY_FROZEN=YES",
]
FROZEN_STRATEGY.write_text("\n".join(strategy_lines) + "\n", encoding="utf-8")

put("FEATURE_FILTER_STRATEGY_FROZEN", "YES")
put("FEATURE_FILTER_APPLICATION_EXECUTED", "NO")
put("TMM_NORMALIZATION_EXECUTED", "NO")
put("READY_FOR_D3B_FILTER_APPLICATION_AND_TMM_QC", "YES")
put("NEXT_PHASE", "D3B_FILTER_APPLICATION_TMM_NORMALIZATION_AND_SAMPLE_STRUCTURE_QC")

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
    $MrnaMatrix,
    $MirnaMatrix,
    $QcMetrics,
    $QcReview,
    $QcSummary,
    $MrnaFilter,
    $MirnaFilter,
    $FilterSummary,
    $FrozenStrategy,
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
        Write-Host '=== D3A PYTHON STDERR ==='
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
    throw ('D3A_PYTHON_FAILED exit={0} full_traceback={1}' -f $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D3A_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('FILTERBYEXPR_MIN_COUNT','10.0'),
    @('FILTERBYEXPR_MIN_TOTAL_COUNT','15.0'),
    @('FILTERBYEXPR_LARGE_N','10.0'),
    @('FILTERBYEXPR_MIN_PROP','0.7'),
    @('SMALLEST_GROUP_SIZE','15'),
    @('FILTERBYEXPR_MIN_SAMPLE_SIZE_NUMERIC','13.5'),
    @('FILTERBYEXPR_EFFECTIVE_MIN_SAMPLES_INTEGER','14'),
    @('QC_PRIMARY_MODALITY_ROWS','144'),
    @('SAMPLE_EXCLUSION_AUTHORIZED','NO'),
    @('FEATURE_FILTER_STRATEGY_FROZEN','YES'),
    @('FEATURE_FILTER_APPLICATION_EXECUTED','NO'),
    @('TMM_NORMALIZATION_EXECUTED','NO'),
    @('READY_FOR_D3B_FILTER_APPLICATION_AND_TMM_QC','YES'),
    @('NEXT_PHASE','D3B_FILTER_APPLICATION_TMM_NORMALIZATION_AND_SAMPLE_STRUCTURE_QC')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D3A_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

@(
    'GSE243219_D3A_DECISION',
    'PHASE_D3A_STATUS=PASS',
    'MODE=REVIEW_AND_DESIGN_ONLY',
    'REAL_BIOLOGICAL_MATRICES_READ=YES',
    'D3_V2_CERTIFICATION_GATE=PASS',
    'D3_V2_OUTPUTS_RECERTIFIED=15/15',
    'FILTER_SCREEN_CPM_COMPUTED=YES',
    'FEATURE_FILTER_METHOD=EDGER_FILTERBYEXPR_DEFAULT_SPECIFICATION',
    'FILTER_MIN_COUNT=10',
    'FILTER_MIN_TOTAL_COUNT=15',
    'FILTER_LARGE_N=10',
    'FILTER_MIN_PROP=0.7',
    'SMALLEST_GROUP_SIZE=15',
    'FILTER_MIN_SAMPLE_SIZE_NUMERIC=13.5',
    'FILTER_EFFECTIVE_MIN_SAMPLES_INTEGER=14',
    ('MRNA_CANDIDATE_KEEP_FEATURES={0}' -f (Cap 'MRNA_CANDIDATE_KEEP_FEATURES')),
    ('MRNA_CANDIDATE_DROP_FEATURES={0}' -f (Cap 'MRNA_CANDIDATE_DROP_FEATURES')),
    ('MIRNA_CANDIDATE_KEEP_FEATURES={0}' -f (Cap 'MIRNA_CANDIDATE_KEEP_FEATURES')),
    ('MIRNA_CANDIDATE_DROP_FEATURES={0}' -f (Cap 'MIRNA_CANDIDATE_DROP_FEATURES')),
    ('QC_REVIEW_FLAGGED_SUBJECTS={0}' -f (Cap 'QC_REVIEW_FLAGGED_SUBJECTS')),
    ('QC_REVIEW_FLAGGED_SUBJECT_IDS={0}' -f (Cap 'QC_REVIEW_FLAGGED_SUBJECT_IDS')),
    'SAMPLE_EXCLUSION_AUTHORIZED=NO',
    'FEATURE_FILTER_STRATEGY_FROZEN=YES',
    'FEATURE_FILTER_APPLICATION_EXECUTED=NO',
    'TMM_NORMALIZATION_EXECUTED=NO',
    'NORMALIZED_MATRIX_CREATED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D3B_FILTER_APPLICATION_AND_TMM_QC=YES',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D3B_FILTER_APPLICATION_TMM_NORMALIZATION_AND_SAMPLE_STRUCTURE_QC',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

$outFiles = @(
    $PyScript,
    $QcReview,
    $QcSummary,
    $MrnaFilter,
    $MirnaFilter,
    $FilterSummary,
    $FrozenStrategy,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D3A_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p

    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D3ASHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

@(
    '=== GSE243219 PHASE D3A SUMMARY ===',
    'PHASE_D3A_STATUS=PASS',
    'MODE=REVIEW_AND_DESIGN_ONLY',
    'REAL_BIOLOGICAL_MATRICES_READ=YES',
    'D3_V2_CERTIFICATION_GATE=PASS',
    'D3_V2_OUTPUTS_RECERTIFIED=15/15',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    'FEATURE_FILTER_METHOD=EDGER_FILTERBYEXPR_DEFAULT_SPECIFICATION',
    'FILTER_INPUT_LIBRARY_SIZE=RAW_COLUMN_SUMS',
    'FILTER_MIN_COUNT=10',
    'FILTER_MIN_TOTAL_COUNT=15',
    'FILTER_LARGE_N=10',
    'FILTER_MIN_PROP=0.7',
    'SMALLEST_GROUP_SIZE=15',
    'FILTER_MIN_SAMPLE_SIZE_NUMERIC=13.5',
    'FILTER_EFFECTIVE_MIN_SAMPLES_INTEGER=14',
    ('MRNA_FILTER_CPM_CUTOFF={0}' -f (Cap 'MRNA_FILTER_CPM_CUTOFF')),
    ('MRNA_CANDIDATE_KEEP_FEATURES={0}' -f (Cap 'MRNA_CANDIDATE_KEEP_FEATURES')),
    ('MRNA_CANDIDATE_DROP_FEATURES={0}' -f (Cap 'MRNA_CANDIDATE_DROP_FEATURES')),
    ('MIRNA_FILTER_CPM_CUTOFF={0}' -f (Cap 'MIRNA_FILTER_CPM_CUTOFF')),
    ('MIRNA_CANDIDATE_KEEP_FEATURES={0}' -f (Cap 'MIRNA_CANDIDATE_KEEP_FEATURES')),
    ('MIRNA_CANDIDATE_DROP_FEATURES={0}' -f (Cap 'MIRNA_CANDIDATE_DROP_FEATURES')),
    ('QC_REVIEW_FLAGGED_SUBJECTS={0}' -f (Cap 'QC_REVIEW_FLAGGED_SUBJECTS')),
    ('QC_REVIEW_FLAGGED_SUBJECT_IDS={0}' -f (Cap 'QC_REVIEW_FLAGGED_SUBJECT_IDS')),
    'QC_FLAGS_ARE_REVIEW_ONLY=YES',
    'SAMPLE_EXCLUSION_AUTHORIZED=NO',
    'FEATURE_FILTER_STRATEGY_FROZEN=YES',
    'FEATURE_FILTER_APPLICATION_EXECUTED=NO',
    'TMM_NORMALIZATION_EXECUTED=NO',
    'NORMALIZED_MATRIX_CREATED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D3B_FILTER_APPLICATION_AND_TMM_QC=YES',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D3B_FILTER_APPLICATION_TMM_NORMALIZATION_AND_SAMPLE_STRUCTURE_QC',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D3A_SAMPLE_QC_REVIEW={0}' -f $QcReview)
Write-Host ('D3A_QC_DISTRIBUTION_SUMMARY={0}' -f $QcSummary)
Write-Host ('D3A_MRNA_FILTER_CANDIDATE={0}' -f $MrnaFilter)
Write-Host ('D3A_MIRNA_FILTER_CANDIDATE={0}' -f $MirnaFilter)
Write-Host ('D3A_FEATURE_FILTER_SUMMARY={0}' -f $FilterSummary)
Write-Host ('D3A_FROZEN_STRATEGY={0}' -f $FrozenStrategy)
Write-Host ('D3A_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D3A_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D3A=PASS'
Write-Host 'STOP=YES'
