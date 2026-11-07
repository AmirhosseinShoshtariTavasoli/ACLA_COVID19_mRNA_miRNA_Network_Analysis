$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D3C — SAMPLE-STRUCTURE REVIEW + ANALYSIS COHORT FREEZE
#
# Scientific rule:
#   PCA/clustering/correlation flags are review annotations only.
#   In the absence of a traceable technical failure or hard data
#   integrity failure, biological samples are NOT excluded merely
#   for being multivariate outliers.
#
# Authorized:
#   - re-certify D3B
#   - review D3A/D3B sample flags
#   - calculate within-disease Spearman-similarity review metrics
#   - calculate robust TMM-factor review metrics
#   - freeze the analysis cohort
#
# Frozen cohort target (unless hard integrity failure is found):
#   72 subjects = 35 COVID19 + 22 SEPSIS + 15 HEALTHY
#
# Prohibited:
#   - sample exclusion based on PCA/correlation alone
#   - changing frozen D3A feature filters
#   - changing D3B TMM factors
#   - count rounding
#   - DE
#   - network construction
#   - A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D2Root = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING'
$D3Root = Join-Path $Project '03_QC_AND_FILTERING'

$D2DRun = Join-Path $D2Root 'D2D_PREFLIGHT_20260904_195001'
$VenvPython = Join-Path $D2DRun 'venv\Scripts\python.exe'

$D3Run = Join-Path $D3Root 'D3_V2_MATRIX_QC_20260904_231245'
$Metadata = Join-Path $D3Run 'D3_PAIRED_SAMPLE_METADATA.csv'

$D3ARun = Join-Path $D3Root 'D3A_QC_FILTER_DESIGN_20260905_092247'
$D3AQcReview = Join-Path $D3ARun 'D3A_SAMPLE_QC_REVIEW.csv'

$D3BRun = Join-Path $D3Root 'D3B_FILTER_TMM_SAMPLE_QC_20260905_092809'
$D3BManifest = Join-Path $D3BRun 'D3B_OUTPUT_SHA256_MANIFEST.csv'
$D3BDecision = Join-Path $D3BRun 'D3B_DECISION.txt'
$D3BReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D3B_20260905_092809\PHASE_D3B_SUMMARY.txt'

$MrnaFiltered = Join-Path $D3BRun 'D3B_MRNA_FILTERED_RAW_COUNTS_15083x72.csv.gz'
$MirnaFiltered = Join-Path $D3BRun 'D3B_MIRNA_FILTERED_RAW_COUNTS_428x72.csv.gz'
$NormTable = Join-Path $D3BRun 'D3B_TMM_NORMALIZATION_FACTORS_AND_LIBRARY_SIZES.csv'
$MrnaLogCpm = Join-Path $D3BRun 'D3B_MRNA_TMM_LOGCPM_PRIOR2_QC_15083x72.csv.gz'
$MirnaLogCpm = Join-Path $D3BRun 'D3B_MIRNA_TMM_LOGCPM_PRIOR2_QC_428x72.csv.gz'
$StructureReview = Join-Path $D3BRun 'D3B_SAMPLE_STRUCTURE_REVIEW.csv'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D3Root ('D3C_COHORT_FREEZE_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D3C_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D3C_SAMPLE_STRUCTURE_REVIEW_AND_COHORT_FREEZE.py'
$CorrelationReview = Join-Path $RunDir 'D3C_WITHIN_DISEASE_SPEARMAN_REVIEW.csv'
$TmmReview = Join-Path $RunDir 'D3C_TMM_FACTOR_REVIEW.csv'
$IntegratedReview = Join-Path $RunDir 'D3C_INTEGRATED_SAMPLE_REVIEW.csv'
$FrozenCohort = Join-Path $RunDir 'D3C_FROZEN_ANALYSIS_COHORT.csv'
$FreezeTxt = Join-Path $RunDir 'D3C_ANALYSIS_COHORT_FREEZE.txt'
$ResultJson = Join-Path $RunDir 'D3C_RESULT.json'
$PythonStdout = Join-Path $RunDir 'D3C_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D3C_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D3C_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D3C_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D3C_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D3C_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D3C — SAMPLE-STRUCTURE REVIEW + ANALYSIS COHORT FREEZE ==='
Write-Host 'MODE=REVIEW_AND_COHORT_FREEZE_ONLY'
Write-Host 'REAL_BIOLOGICAL_MATRICES_READ=YES'
Write-Host 'SAMPLE_STRUCTURE_REVIEW_EXECUTED=YES'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'FEATURE_FILTER_CHANGED=NO'
Write-Host 'TMM_FACTORS_CHANGED=NO'
Write-Host 'MRNA_COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'DE_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $VenvPython,$Metadata,$D3AQcReview,
    $D3BManifest,$D3BDecision,$D3BReport,
    $MrnaFiltered,$MirnaFiltered,$NormTable,
    $MrnaLogCpm,$MirnaLogCpm,$StructureReview
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D3C_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D3CSHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

# ------------------------------------------------------------
# 1. Re-certify D3B
# ------------------------------------------------------------
$d3b = Get-Content -LiteralPath $D3BReport -Raw

foreach ($tok in @(
    'PHASE_D3B_STATUS=PASS',
    'FEATURE_FILTER_APPLICATION_EXECUTED=YES',
    'MRNA_FILTERED_FEATURES=15083',
    'MIRNA_FILTERED_FEATURES=428',
    'FILTERED_SAMPLE_COUNT=72',
    'FILTERED_RAW_MATRIX_ROUNDTRIP_INTEGRITY=PASS',
    'POST_FILTER_LIBRARY_SIZES_RECOMPUTED=YES',
    'TMM_NORMALIZATION_EXECUTED=YES',
    'TMM_IMPLEMENTATION_SOURCE=D2E_V4_VALIDATED_EDGE_STYLE_FUNCTION',
    'TMM_VALIDATED_SOURCE_FUNCTION_EXTRACTION=PASS',
    'TMM_PRODUCTION_TOY_SELF_TEST=PASS',
    'MRNA_TMM_FACTOR_GEOMEAN=1.0',
    'MIRNA_TMM_FACTOR_GEOMEAN=1.0',
    'PCA_STRUCTURE_REVIEW_SUBJECTS=3',
    'PCA_STRUCTURE_REVIEW_SUBJECT_IDS=H22|H24|H25',
    'COMBINED_QC_REVIEW_SUBJECTS=4',
    'COMBINED_QC_REVIEW_SUBJECT_IDS=H22|H24|H25|P25',
    'ALL_72_SAMPLES_RETAINED=YES',
    'D3A_REVIEW_SUBJECTS_H24_P25_RETAINED=YES',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'SAMPLE_EXCLUSION_AUTHORIZED=NO',
    'MRNA_COUNT_ROUNDING_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'READY_FOR_D3C_SAMPLE_STRUCTURE_REVIEW=YES',
    'NEXT_PHASE=D3C_SAMPLE_STRUCTURE_REVIEW_AND_ANALYSIS_COHORT_FREEZE'
)) {
    if ($d3b -notmatch [regex]::Escape($tok)) {
        throw ('D3B_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

$d3bRows = @(Import-Csv -LiteralPath $D3BManifest)
if ($d3bRows.Count -ne 18) {
    throw ('D3B_MANIFEST_ROW_COUNT_CHANGED expected=18 observed={0}' -f $d3bRows.Count)
}

foreach ($r in $d3bRows) {
    if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
        throw ('D3B_OUTPUT_MISSING={0}' -f $r.full_path)
    }

    $item = Get-Item -LiteralPath $r.full_path
    if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
        (Get-D3CSHA256 $r.full_path) -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D3B_OUTPUT_CHANGED={0}' -f $r.full_path)
    }
}

Write-Host 'D3B_CERTIFICATION_GATE=PASS'
Write-Host 'D3B_OUTPUTS_RECERTIFIED=18/18'

$PythonVersion = & $VenvPython -c "import sys; print('.'.join(map(str,sys.version_info[:3])))"
$PandasVersion = & $VenvPython -c "import pandas; print(pandas.__version__)"
$NumpyVersion = & $VenvPython -c "import numpy; print(numpy.__version__)"
$ScipyVersion = & $VenvPython -c "import scipy; print(scipy.__version__)"

if ($PythonVersion -ne '3.12.3') {
    throw ('VALIDATED_PYTHON_CHANGED={0}' -f $PythonVersion)
}

Write-Host ('PYTHON_VERSION={0}' -f $PythonVersion)
Write-Host ('PANDAS_VERSION={0}' -f $PandasVersion)
Write-Host ('NUMPY_VERSION={0}' -f $NumpyVersion)
Write-Host ('SCIPY_VERSION={0}' -f $ScipyVersion)

# ------------------------------------------------------------
# 2. Python integrated review and cohort freeze
# ------------------------------------------------------------
$PythonCode = @'
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import rankdata


METADATA = Path(sys.argv[1])
D3A_QC = Path(sys.argv[2])
NORM_TABLE = Path(sys.argv[3])
MRNA_LOG = Path(sys.argv[4])
MIRNA_LOG = Path(sys.argv[5])
STRUCTURE = Path(sys.argv[6])
MRNA_FILTERED = Path(sys.argv[7])
MIRNA_FILTERED = Path(sys.argv[8])

CORR_REVIEW = Path(sys.argv[9])
TMM_REVIEW = Path(sys.argv[10])
INTEGRATED_REVIEW = Path(sys.argv[11])
FROZEN_COHORT = Path(sys.argv[12])
FREEZE_TXT = Path(sys.argv[13])
RESULT_JSON = Path(sys.argv[14])

results = {}

def put(k, v):
    results[k] = v
    print(f"{k}={v}")


def modified_z(values):
    values = np.asarray(values, dtype=np.float64)
    med = np.median(values)
    mad = np.median(np.abs(values - med))
    if mad == 0:
        return np.zeros(values.size, dtype=np.float64)
    return 0.6744897501960817 * (values - med) / mad


metadata = pd.read_csv(METADATA)
d3a_qc = pd.read_csv(D3A_QC)
norm = pd.read_csv(NORM_TABLE)
structure = pd.read_csv(STRUCTURE)

mrna_log = pd.read_csv(
    MRNA_LOG,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
mirna_log = pd.read_csv(
    MIRNA_LOG,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
mrna_filtered = pd.read_csv(
    MRNA_FILTERED,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)
mirna_filtered = pd.read_csv(
    MIRNA_FILTERED,
    index_col=0,
    compression="gzip",
    engine="c",
    float_precision="round_trip",
)

if metadata.shape[0] != 72:
    raise RuntimeError(f"METADATA_ROWS_CHANGED observed={metadata.shape[0]}")
if mrna_log.shape != (15083, 72):
    raise RuntimeError(f"MRNA_LOGCPM_SHAPE_CHANGED observed={mrna_log.shape}")
if mirna_log.shape != (428, 72):
    raise RuntimeError(f"MIRNA_LOGCPM_SHAPE_CHANGED observed={mirna_log.shape}")
if mrna_filtered.shape != (15083, 72):
    raise RuntimeError(f"MRNA_FILTERED_SHAPE_CHANGED observed={mrna_filtered.shape}")
if mirna_filtered.shape != (428, 72):
    raise RuntimeError(f"MIRNA_FILTERED_SHAPE_CHANGED observed={mirna_filtered.shape}")

subjects = metadata["subject_id"].astype(str).tolist()
groups = metadata["disease_state"].astype(str).tolist()

if list(mrna_log.columns) != subjects:
    raise RuntimeError("MRNA_LOGCPM_SAMPLE_ORDER_CHANGED")
if list(mirna_log.columns) != subjects:
    raise RuntimeError("MIRNA_LOGCPM_SAMPLE_ORDER_CHANGED")
if list(mrna_filtered.columns) != subjects:
    raise RuntimeError("MRNA_FILTERED_SAMPLE_ORDER_CHANGED")
if list(mirna_filtered.columns) != subjects:
    raise RuntimeError("MIRNA_FILTERED_SAMPLE_ORDER_CHANGED")

counts = pd.Series(groups).value_counts().to_dict()
expected_counts = {"COVID19": 35, "SEPSIS": 22, "HEALTHY": 15}
if counts != expected_counts:
    raise RuntimeError(f"PHENOTYPE_COUNTS_CHANGED observed={counts}")

if np.any(~np.isfinite(mrna_log.to_numpy(dtype=np.float64))):
    raise RuntimeError("MRNA_LOGCPM_NONFINITE")
if np.any(~np.isfinite(mirna_log.to_numpy(dtype=np.float64))):
    raise RuntimeError("MIRNA_LOGCPM_NONFINITE")
if np.any(~np.isfinite(mrna_filtered.to_numpy(dtype=np.float64))):
    raise RuntimeError("MRNA_FILTERED_NONFINITE")
if np.any(~np.isfinite(mirna_filtered.to_numpy(dtype=np.float64))):
    raise RuntimeError("MIRNA_FILTERED_NONFINITE")

put("HARD_MATRIX_INTEGRITY_GATE", "PASS")


# ------------------------------------------------------------
# A. Within-disease Spearman-expression similarity
# ------------------------------------------------------------
def spearman_similarity_review(log_df, modality):
    # Rank genes/features within each sample; Pearson correlation of ranks
    # is Spearman correlation.
    x = log_df.to_numpy(dtype=np.float64)
    ranked = np.empty_like(x)

    for j in range(x.shape[1]):
        ranked[:, j] = rankdata(x[:, j], method="average")

    corr = np.corrcoef(ranked.T)

    rows = []
    disease_arr = np.asarray(groups, dtype=object)

    # First compute within-group medians.
    medcorr = np.zeros(len(subjects), dtype=np.float64)

    for i, subject in enumerate(subjects):
        peer_idx = np.where(disease_arr == disease_arr[i])[0]
        peer_idx = peer_idx[peer_idx != i]
        medcorr[i] = float(np.median(corr[i, peer_idx]))

    # Lower-tail modified z within each disease group.
    z = np.zeros(len(subjects), dtype=np.float64)
    for group in sorted(set(groups)):
        idx = np.where(disease_arr == group)[0]
        z[idx] = modified_z(medcorr[idx])

    for i, subject in enumerate(subjects):
        review = z[i] <= -3.5
        rows.append({
            "subject_id": subject,
            "disease_state": groups[i],
            "modality": modality,
            "median_spearman_to_within_disease_peers": float(medcorr[i]),
            "within_disease_modified_z": float(z[i]),
            "low_similarity_review_flag": "REVIEW" if review else "NO",
            "sample_exclusion_authorized": "NO",
        })

    return rows


corr_rows = []
corr_rows.extend(spearman_similarity_review(mrna_log, "mRNA"))
corr_rows.extend(
    spearman_similarity_review(mirna_log, "miRNA_mature_median_primary")
)

corr_df = pd.DataFrame(corr_rows)
corr_df.to_csv(CORR_REVIEW, index=False)

corr_review_subjects = sorted(set(
    corr_df.loc[
        corr_df["low_similarity_review_flag"].eq("REVIEW"),
        "subject_id",
    ].astype(str)
))

put("SPEARMAN_REVIEW_SUBJECTS", len(corr_review_subjects))
put(
    "SPEARMAN_REVIEW_SUBJECT_IDS",
    "|".join(corr_review_subjects) if corr_review_subjects else "NONE",
)


# ------------------------------------------------------------
# B. TMM-factor robust extremeness review
# ------------------------------------------------------------
if norm.shape[0] != 144:
    raise RuntimeError(f"NORM_TABLE_ROWS_CHANGED observed={norm.shape[0]}")

tmm_rows = []
for modality, mdf in norm.groupby("modality", sort=False):
    mdf = mdf.copy()
    factors = mdf["tmm_norm_factor"].to_numpy(dtype=np.float64)
    z = modified_z(np.log(factors))

    for i, (_, row) in enumerate(mdf.iterrows()):
        review = abs(float(z[i])) >= 3.5
        tmm_rows.append({
            "subject_id": str(row["subject_id"]),
            "disease_state": str(row["disease_state"]),
            "modality": modality,
            "tmm_norm_factor": float(row["tmm_norm_factor"]),
            "log_tmm_factor_modified_z": float(z[i]),
            "tmm_factor_review_flag": "REVIEW" if review else "NO",
            "sample_exclusion_authorized": "NO",
        })

tmm_df = pd.DataFrame(tmm_rows)
tmm_df.to_csv(TMM_REVIEW, index=False)

tmm_review_subjects = sorted(set(
    tmm_df.loc[
        tmm_df["tmm_factor_review_flag"].eq("REVIEW"),
        "subject_id",
    ].astype(str)
))

put("TMM_FACTOR_REVIEW_SUBJECTS", len(tmm_review_subjects))
put(
    "TMM_FACTOR_REVIEW_SUBJECT_IDS",
    "|".join(tmm_review_subjects) if tmm_review_subjects else "NONE",
)


# ------------------------------------------------------------
# C. Integrate all review annotations
# ------------------------------------------------------------
d3a_subject_flags = (
    d3a_qc.groupby("subject_id")["qc_review_flag"]
    .apply(lambda x: "REVIEW" if (x.astype(str) == "REVIEW").any() else "NO")
    .to_dict()
)

pca_subject_flags = (
    structure.groupby("subject_id")["pca_structure_review_flag"]
    .apply(lambda x: "REVIEW" if (x.astype(str) == "REVIEW").any() else "NO")
    .to_dict()
)

corr_subject_flags = (
    corr_df.groupby("subject_id")["low_similarity_review_flag"]
    .apply(lambda x: "REVIEW" if (x.astype(str) == "REVIEW").any() else "NO")
    .to_dict()
)

tmm_subject_flags = (
    tmm_df.groupby("subject_id")["tmm_factor_review_flag"]
    .apply(lambda x: "REVIEW" if (x.astype(str) == "REVIEW").any() else "NO")
    .to_dict()
)

integrated_rows = []

for subject, disease in zip(subjects, groups):
    flags = {
        "d3a_raw_library_qc": d3a_subject_flags.get(subject, "NO"),
        "d3b_pca_structure": pca_subject_flags.get(subject, "NO"),
        "d3c_spearman_similarity": corr_subject_flags.get(subject, "NO"),
        "d3c_tmm_factor": tmm_subject_flags.get(subject, "NO"),
    }

    n_review = sum(v == "REVIEW" for v in flags.values())

    integrated_rows.append({
        "subject_id": subject,
        "disease_state": disease,
        **flags,
        "independent_review_domains_flagged": n_review,
        "hard_integrity_failure": "NO",
        "traceable_technical_failure_available": "NO",
        "cohort_decision": "RETAIN",
        "decision_reason": (
            "NO_HARD_OR_TRACEABLE_TECHNICAL_FAILURE;"
            "MULTIVARIATE_FLAGS_REVIEW_ONLY"
            if n_review > 0
            else "NO_QC_EXCLUSION_EVIDENCE"
        ),
    })

integrated_df = pd.DataFrame(integrated_rows)
integrated_df.to_csv(INTEGRATED_REVIEW, index=False)

all_review_subjects = sorted(
    integrated_df.loc[
        integrated_df["independent_review_domains_flagged"] > 0,
        "subject_id",
    ].astype(str)
)

multi_domain_subjects = sorted(
    integrated_df.loc[
        integrated_df["independent_review_domains_flagged"] >= 2,
        "subject_id",
    ].astype(str)
)

put("INTEGRATED_REVIEW_ANNOTATION_SUBJECTS", len(all_review_subjects))
put(
    "INTEGRATED_REVIEW_ANNOTATION_SUBJECT_IDS",
    "|".join(all_review_subjects) if all_review_subjects else "NONE",
)
put("MULTIDOMAIN_REVIEW_SUBJECTS", len(multi_domain_subjects))
put(
    "MULTIDOMAIN_REVIEW_SUBJECT_IDS",
    "|".join(multi_domain_subjects) if multi_domain_subjects else "NONE",
)


# ------------------------------------------------------------
# D. Freeze complete 72-subject analysis cohort
# ------------------------------------------------------------
cohort_df = metadata.copy()
cohort_df["analysis_cohort_included"] = "YES"
cohort_df["exclusion_reason"] = ""
cohort_df["qc_review_annotation"] = cohort_df["subject_id"].astype(str).map(
    lambda s: "REVIEW_ANNOTATION" if s in all_review_subjects else "NONE"
)
cohort_df.to_csv(FROZEN_COHORT, index=False)

if cohort_df.shape[0] != 72:
    raise RuntimeError("FROZEN_COHORT_NOT_72")
if not cohort_df["analysis_cohort_included"].eq("YES").all():
    raise RuntimeError("UNAUTHORIZED_SAMPLE_EXCLUSION_DETECTED")

final_counts = cohort_df["disease_state"].value_counts().to_dict()
if final_counts != expected_counts:
    raise RuntimeError(f"FROZEN_COHORT_GROUP_COUNTS_CHANGED observed={final_counts}")

freeze_lines = [
    "GSE243219_D3C_ANALYSIS_COHORT_FREEZE",
    "ANALYSIS_COHORT_FROZEN=YES",
    "ANALYSIS_COHORT_SUBJECTS=72",
    "ANALYSIS_COHORT_COVID19=35",
    "ANALYSIS_COHORT_SEPSIS=22",
    "ANALYSIS_COHORT_HEALTHY=15",
    "EXCLUDED_SUBJECTS=NONE",
    "SAMPLE_EXCLUSION_EXECUTED=NO",
    "SAMPLE_EXCLUSION_POLICY=PCA_CLUSTERING_CORRELATION_FLAGS_ALONE_ARE_INSUFFICIENT",
    "TRACEABLE_TECHNICAL_FAILURE_AVAILABLE=NO",
    "HARD_INTEGRITY_FAILURES=0",
    "D3A_FEATURE_FILTERS_RETAINED_UNCHANGED=YES",
    "D3B_TMM_FACTORS_RETAINED_UNCHANGED=YES",
    "DE_INPUT_COUNTS=FILTERED_RAW_COUNTS",
    "DE_INPUT_NORMALIZATION=LOG_EFFECTIVE_LIBRARY_SIZE_OFFSETS",
    "NORMALIZED_CPM_AS_DE_INPUT=PROHIBITED",
    "LOGCPM_AS_DE_INPUT=PROHIBITED",
    "ANALYSIS_COHORT_FREEZE_PROSPECTIVE_FOR_DE=YES",
]
FREEZE_TXT.write_text("\n".join(freeze_lines) + "\n", encoding="utf-8")

put("ANALYSIS_COHORT_FROZEN", "YES")
put("ANALYSIS_COHORT_SUBJECTS", 72)
put("ANALYSIS_COHORT_COVID19", 35)
put("ANALYSIS_COHORT_SEPSIS", 22)
put("ANALYSIS_COHORT_HEALTHY", 15)
put("EXCLUDED_SUBJECTS", "NONE")
put("SAMPLE_EXCLUSION_EXECUTED", "NO")
put("TRACEABLE_TECHNICAL_FAILURE_AVAILABLE", "NO")
put("HARD_INTEGRITY_FAILURES", 0)
put("READY_FOR_D4_DE_INPUT_BUNDLE_FREEZE", "YES")
put("NEXT_PHASE", "D4_NORMALIZATION_CERTIFICATION_AND_DE_INPUT_BUNDLE_FREEZE")

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
    $D3AQcReview,
    $NormTable,
    $MrnaLogCpm,
    $MirnaLogCpm,
    $StructureReview,
    $MrnaFiltered,
    $MirnaFiltered,
    $CorrelationReview,
    $TmmReview,
    $IntegratedReview,
    $FrozenCohort,
    $FreezeTxt,
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
        Write-Host '=== D3C PYTHON STDERR ==='
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
    throw ('D3C_PYTHON_FAILED exit={0} full_traceback={1}' -f $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D3C_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('HARD_MATRIX_INTEGRITY_GATE','PASS'),
    @('ANALYSIS_COHORT_FROZEN','YES'),
    @('ANALYSIS_COHORT_SUBJECTS','72'),
    @('ANALYSIS_COHORT_COVID19','35'),
    @('ANALYSIS_COHORT_SEPSIS','22'),
    @('ANALYSIS_COHORT_HEALTHY','15'),
    @('EXCLUDED_SUBJECTS','NONE'),
    @('SAMPLE_EXCLUSION_EXECUTED','NO'),
    @('TRACEABLE_TECHNICAL_FAILURE_AVAILABLE','NO'),
    @('HARD_INTEGRITY_FAILURES','0'),
    @('READY_FOR_D4_DE_INPUT_BUNDLE_FREEZE','YES'),
    @('NEXT_PHASE','D4_NORMALIZATION_CERTIFICATION_AND_DE_INPUT_BUNDLE_FREEZE')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D3C_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 3. Decision
# ------------------------------------------------------------
@(
    'GSE243219_D3C_DECISION',
    'PHASE_D3C_STATUS=PASS',
    'MODE=REVIEW_AND_COHORT_FREEZE_ONLY',
    'D3B_CERTIFICATION_GATE=PASS',
    'D3B_OUTPUTS_RECERTIFIED=18/18',
    'HARD_MATRIX_INTEGRITY_GATE=PASS',
    'SAMPLE_STRUCTURE_REVIEW_EXECUTED=YES',
    ('SPEARMAN_REVIEW_SUBJECTS={0}' -f (Cap 'SPEARMAN_REVIEW_SUBJECTS')),
    ('SPEARMAN_REVIEW_SUBJECT_IDS={0}' -f (Cap 'SPEARMAN_REVIEW_SUBJECT_IDS')),
    ('TMM_FACTOR_REVIEW_SUBJECTS={0}' -f (Cap 'TMM_FACTOR_REVIEW_SUBJECTS')),
    ('TMM_FACTOR_REVIEW_SUBJECT_IDS={0}' -f (Cap 'TMM_FACTOR_REVIEW_SUBJECT_IDS')),
    ('INTEGRATED_REVIEW_ANNOTATION_SUBJECTS={0}' -f (Cap 'INTEGRATED_REVIEW_ANNOTATION_SUBJECTS')),
    ('INTEGRATED_REVIEW_ANNOTATION_SUBJECT_IDS={0}' -f (Cap 'INTEGRATED_REVIEW_ANNOTATION_SUBJECT_IDS')),
    ('MULTIDOMAIN_REVIEW_SUBJECTS={0}' -f (Cap 'MULTIDOMAIN_REVIEW_SUBJECTS')),
    ('MULTIDOMAIN_REVIEW_SUBJECT_IDS={0}' -f (Cap 'MULTIDOMAIN_REVIEW_SUBJECT_IDS')),
    'PCA_CLUSTERING_CORRELATION_FLAGS_ALONE_AUTHORIZE_EXCLUSION=NO',
    'TRACEABLE_TECHNICAL_FAILURE_AVAILABLE=NO',
    'HARD_INTEGRITY_FAILURES=0',
    'ANALYSIS_COHORT_FROZEN=YES',
    'ANALYSIS_COHORT_SUBJECTS=72',
    'ANALYSIS_COHORT_COVID19=35',
    'ANALYSIS_COHORT_SEPSIS=22',
    'ANALYSIS_COHORT_HEALTHY=15',
    'EXCLUDED_SUBJECTS=NONE',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'FEATURE_FILTER_CHANGED=NO',
    'TMM_FACTORS_CHANGED=NO',
    'MRNA_COUNT_ROUNDING_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D4_DE_INPUT_BUNDLE_FREEZE=YES',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D4_NORMALIZATION_CERTIFICATION_AND_DE_INPUT_BUNDLE_FREEZE',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Manifest
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $CorrelationReview,
    $TmmReview,
    $IntegratedReview,
    $FrozenCohort,
    $FreezeTxt,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D3C_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p
    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D3CSHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D3C SUMMARY ===',
    'PHASE_D3C_STATUS=PASS',
    'MODE=REVIEW_AND_COHORT_FREEZE_ONLY',
    'D3B_CERTIFICATION_GATE=PASS',
    'D3B_OUTPUTS_RECERTIFIED=18/18',
    ('PYTHON_VERSION={0}' -f $PythonVersion),
    ('PANDAS_VERSION={0}' -f $PandasVersion),
    ('NUMPY_VERSION={0}' -f $NumpyVersion),
    ('SCIPY_VERSION={0}' -f $ScipyVersion),
    'HARD_MATRIX_INTEGRITY_GATE=PASS',
    'SAMPLE_STRUCTURE_REVIEW_EXECUTED=YES',
    ('SPEARMAN_REVIEW_SUBJECTS={0}' -f (Cap 'SPEARMAN_REVIEW_SUBJECTS')),
    ('SPEARMAN_REVIEW_SUBJECT_IDS={0}' -f (Cap 'SPEARMAN_REVIEW_SUBJECT_IDS')),
    ('TMM_FACTOR_REVIEW_SUBJECTS={0}' -f (Cap 'TMM_FACTOR_REVIEW_SUBJECTS')),
    ('TMM_FACTOR_REVIEW_SUBJECT_IDS={0}' -f (Cap 'TMM_FACTOR_REVIEW_SUBJECT_IDS')),
    ('INTEGRATED_REVIEW_ANNOTATION_SUBJECTS={0}' -f (Cap 'INTEGRATED_REVIEW_ANNOTATION_SUBJECTS')),
    ('INTEGRATED_REVIEW_ANNOTATION_SUBJECT_IDS={0}' -f (Cap 'INTEGRATED_REVIEW_ANNOTATION_SUBJECT_IDS')),
    ('MULTIDOMAIN_REVIEW_SUBJECTS={0}' -f (Cap 'MULTIDOMAIN_REVIEW_SUBJECTS')),
    ('MULTIDOMAIN_REVIEW_SUBJECT_IDS={0}' -f (Cap 'MULTIDOMAIN_REVIEW_SUBJECT_IDS')),
    'PCA_CLUSTERING_CORRELATION_FLAGS_ALONE_AUTHORIZE_EXCLUSION=NO',
    'TRACEABLE_TECHNICAL_FAILURE_AVAILABLE=NO',
    'HARD_INTEGRITY_FAILURES=0',
    'ANALYSIS_COHORT_FROZEN=YES',
    'ANALYSIS_COHORT_SUBJECTS=72',
    'ANALYSIS_COHORT_COVID19=35',
    'ANALYSIS_COHORT_SEPSIS=22',
    'ANALYSIS_COHORT_HEALTHY=15',
    'EXCLUDED_SUBJECTS=NONE',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'FEATURE_FILTER_CHANGED=NO',
    'TMM_FACTORS_CHANGED=NO',
    'MRNA_COUNT_ROUNDING_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D4_DE_INPUT_BUNDLE_FREEZE=YES',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D4_NORMALIZATION_CERTIFICATION_AND_DE_INPUT_BUNDLE_FREEZE',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D3C_SPEARMAN_REVIEW={0}' -f $CorrelationReview)
Write-Host ('D3C_TMM_FACTOR_REVIEW={0}' -f $TmmReview)
Write-Host ('D3C_INTEGRATED_SAMPLE_REVIEW={0}' -f $IntegratedReview)
Write-Host ('D3C_FROZEN_ANALYSIS_COHORT={0}' -f $FrozenCohort)
Write-Host ('D3C_ANALYSIS_COHORT_FREEZE={0}' -f $FreezeTxt)
Write-Host ('D3C_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D3C_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D3C=PASS'
Write-Host 'STOP=YES'
