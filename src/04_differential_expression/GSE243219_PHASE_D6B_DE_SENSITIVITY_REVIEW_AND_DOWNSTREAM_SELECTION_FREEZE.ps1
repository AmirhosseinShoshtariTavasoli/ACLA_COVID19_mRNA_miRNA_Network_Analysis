$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D6B — DE SENSITIVITY REVIEW
#              + DOWNSTREAM FEATURE-SELECTION FREEZE
#
# Purpose:
#   - re-certify D6-V5 primary DE and D6A sensitivity outputs
#   - quantitatively review MEDIAN-vs-MAX miRNA sensitivity
#   - keep MEDIAN as the frozen primary miRNA analysis
#   - freeze the downstream association candidate universe
#
# Frozen downstream candidate rule:
#   PRIMARY CONTRAST = COV_vs_H
#   PRIMARY STATISTICAL SELECTION = BH FDR <= 0.05
#
# Therefore:
#   mRNA candidate universe = D6-V5 COV_vs_H FDR <= 0.05
#   miRNA candidate universe = D6-V5 MEDIAN COV_vs_H FDR <= 0.05
#
# P_vs_H and COV_vs_P are carried forward as comparator /
# specificity annotations only. They do NOT delete primary
# COVID-vs-healthy candidates at this stage.
#
# Secondary |log2FC|>=1 rule remains PRIORITIZATION ONLY.
#
# MAX miRNA sensitivity:
#   - never replaces the primary MEDIAN result
#   - row-level MAX replication/sign information is annotated
#   - no post-hoc concordance threshold is invented
#
# Prohibited:
#   - re-running DE
#   - re-filtering
#   - count rounding
#   - sample exclusion
#   - association/correlation execution
#   - network construction
#   - A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D5Root = Join-Path $Project '05_DIFFERENTIAL_EXPRESSION'

$D6Run = Join-Path $D5Root 'D6_V5_PRIMARY_DE_EXECUTION_20260905_102127'
$D6Manifest = Join-Path $D6Run 'D6_OUTPUT_SHA256_MANIFEST.csv'
$D6Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D6_V5_20260905_102127\PHASE_D6_SUMMARY.txt'

$MrnaCovH = Join-Path $D6Run 'D6_MRNA_COV_vs_H_FULL_RESULTS.csv.gz'
$MrnaPH = Join-Path $D6Run 'D6_MRNA_P_vs_H_FULL_RESULTS.csv.gz'
$MrnaCovP = Join-Path $D6Run 'D6_MRNA_COV_vs_P_FULL_RESULTS.csv.gz'

$MirnaCovH = Join-Path $D6Run 'D6_MIRNA_COV_vs_H_FULL_RESULTS.csv.gz'
$MirnaPH = Join-Path $D6Run 'D6_MIRNA_P_vs_H_FULL_RESULTS.csv.gz'
$MirnaCovP = Join-Path $D6Run 'D6_MIRNA_COV_vs_P_FULL_RESULTS.csv.gz'

$D6ARun = Join-Path $D5Root 'D6A_DE_AUDIT_MIRNA_MAX_SENSITIVITY_20260905_103302'
$D6AManifest = Join-Path $D6ARun 'D6A_OUTPUT_SHA256_MANIFEST.csv'
$D6AReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D6A_20260905_103302\PHASE_D6A_SUMMARY.txt'

$MaxCovH = Join-Path $D6ARun 'D6A_MIRNA_MAX_COV_vs_H_FULL_RESULTS.csv.gz'
$MaxPH = Join-Path $D6ARun 'D6A_MIRNA_MAX_P_vs_H_FULL_RESULTS.csv.gz'
$MaxCovP = Join-Path $D6ARun 'D6A_MIRNA_MAX_COV_vs_P_FULL_RESULTS.csv.gz'
$D6AConcordance = Join-Path $D6ARun 'D6A_MIRNA_MEDIAN_VS_MAX_SENSITIVITY_CONCORDANCE.csv'
$D6APrimaryAudit = Join-Path $D6ARun 'D6A_PRIMARY_DE_RESULT_AUDIT.csv'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D5Root ('D6B_SELECTION_FREEZE_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D6B_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PyScript = Join-Path $RunDir 'D6B_DE_SENSITIVITY_REVIEW_AND_SELECTION_FREEZE.py'
$ConcordanceReview = Join-Path $RunDir 'D6B_MIRNA_MEDIAN_MAX_QUANTITATIVE_REVIEW.csv'
$MrnaCandidates = Join-Path $RunDir 'D6B_MRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES.csv.gz'
$MirnaCandidates = Join-Path $RunDir 'D6B_MIRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES.csv.gz'
$SelectionSummary = Join-Path $RunDir 'D6B_DOWNSTREAM_SELECTION_SUMMARY.csv'
$SelectionFreeze = Join-Path $RunDir 'D6B_DOWNSTREAM_FEATURE_SELECTION_FREEZE.txt'
$ResultJson = Join-Path $RunDir 'D6B_RESULT.json'

$PythonStdout = Join-Path $RunDir 'D6B_PYTHON_STDOUT.txt'
$PythonStderr = Join-Path $RunDir 'D6B_PYTHON_STDERR.txt'
$PythonLog = Join-Path $RunDir 'D6B_PYTHON_LOG.txt'
$DecisionTxt = Join-Path $RunDir 'D6B_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D6B_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D6B_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D6B — SENSITIVITY REVIEW + DOWNSTREAM SELECTION FREEZE ==='
Write-Host 'MODE=REVIEW_AND_SELECTION_FREEZE_ONLY'
Write-Host 'PRIMARY_MIRNA_AUTHORITY=MEDIAN'
Write-Host 'MAX_MIRNA_ROLE=SENSITIVITY_ONLY'
Write-Host 'PRIMARY_DOWNSTREAM_CONTRAST=COV_vs_H'
Write-Host 'PRIMARY_DOWNSTREAM_SELECTION=BH_FDR_LE_0.05'
Write-Host 'ABS_LOG2FC_GE_1_ROLE=PRIORITIZATION_ONLY'
Write-Host 'SEPSIS_CONTRASTS_ROLE=ANNOTATION_NOT_DELETION_GATE'
Write-Host 'DE_REEXECUTED=NO'
Write-Host 'FEATURE_REFILTERING_EXECUTED=NO'
Write-Host 'COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'ASSOCIATION_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $D6Manifest,$D6Report,
    $MrnaCovH,$MrnaPH,$MrnaCovP,
    $MirnaCovH,$MirnaPH,$MirnaCovP,
    $D6AManifest,$D6AReport,
    $MaxCovH,$MaxPH,$MaxCovP,
    $D6AConcordance,$D6APrimaryAudit
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D6B_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D6BSHA256 {
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
        $hash = Get-D6BSHA256 $r.full_path

        if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
            $hash -ne $r.SHA256.ToLowerInvariant()) {
            throw ('{0}_OUTPUT_CHANGED={1}' -f $Label,$r.full_path)
        }
    }

    Write-Host ('{0}_OUTPUTS_RECERTIFIED={1}/{1}' -f $Label,$ExpectedRows)
}

# ------------------------------------------------------------
# 1. Re-certify D6-V5 and D6A
# ------------------------------------------------------------
Recertify-Manifest -ManifestPath $D6Manifest -ExpectedRows 16 -Label 'D6_V5'
Write-Host 'D6_V5_CERTIFICATION_GATE=PASS'

Recertify-Manifest -ManifestPath $D6AManifest -ExpectedRows 16 -Label 'D6A'
Write-Host 'D6A_CERTIFICATION_GATE=PASS'

$d6 = Get-Content -LiteralPath $D6Report -Raw
foreach ($tok in @(
    'PHASE_D6_V5_STATUS=PASS',
    'MRNA_COV_vs_H_FDR_LE_0_05=8505',
    'MRNA_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1=3618',
    'MIRNA_COV_vs_H_FDR_LE_0_05=41',
    'MIRNA_COV_vs_H_FDR_LE_0_05_ABS_LOG2FC_GE_1=22',
    'ALL_SIX_DE_RESULT_TABLES_COMPLETE=YES',
    'ALL_DE_PVALUES_VALID=YES',
    'ALL_BH_FDR_VALID=YES',
    'DE_EXECUTION_COMPLETE=YES'
)) {
    if ($d6 -notmatch [regex]::Escape($tok)) {
        throw ('D6_V5_TOKEN_MISSING={0}' -f $tok)
    }
}

$d6a = Get-Content -LiteralPath $D6AReport -Raw
foreach ($tok in @(
    'PHASE_D6A_STATUS=PASS',
    'PRIMARY_D6_RESULT_TABLES_AUDITED=6/6',
    'PRIMARY_D6_BH_RECOMPUTATION=PASS',
    'PRIMARY_D6_CONTRAST_ALGEBRA_REAUDIT=PASS',
    'PRIMARY_D6_RESULTS_MODIFIED=NO',
    'PRIMARY_MIRNA_CONSOLIDATION=MEDIAN',
    'SENSITIVITY_MIRNA_CONSOLIDATION=MAX',
    'MIRNA_MAX_SENSITIVITY_FEATURES=428',
    'MIRNA_MAX_SAME_PRIMARY_FEATURE_IDENTITIES=YES',
    'MIRNA_MAX_COV_vs_H_FDR_LE_0_05=41',
    'MIRNA_MAX_P_vs_H_FDR_LE_0_05=191',
    'MIRNA_MAX_COV_vs_P_FDR_LE_0_05=204',
    'MIRNA_MAX_CONTRAST_LOGFC_ALGEBRA=PASS',
    'PRIMARY_MIRNA_RESULT_AUTHORITY=MEDIAN_UNCHANGED',
    'SENSITIVITY_ACCEPTANCE_THRESHOLD_PREDECLARED=NO',
    'PHASE_D6A_COMPUTATION_COMPLETE=YES'
)) {
    if ($d6a -notmatch [regex]::Escape($tok)) {
        throw ('D6A_TOKEN_MISSING={0}' -f $tok)
    }
}

# ------------------------------------------------------------
# 2. Python quantitative review and selection freeze
# ------------------------------------------------------------
$PythonCode = @'
import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import pearsonr, spearmanr


MRNA_COV_H = Path(sys.argv[1])
MRNA_P_H = Path(sys.argv[2])
MRNA_COV_P = Path(sys.argv[3])

MIRNA_COV_H = Path(sys.argv[4])
MIRNA_P_H = Path(sys.argv[5])
MIRNA_COV_P = Path(sys.argv[6])

MAX_COV_H = Path(sys.argv[7])
MAX_P_H = Path(sys.argv[8])
MAX_COV_P = Path(sys.argv[9])

D6A_CONCORDANCE = Path(sys.argv[10])
D6A_PRIMARY_AUDIT = Path(sys.argv[11])

CONCORDANCE_REVIEW = Path(sys.argv[12])
MRNA_CANDIDATES = Path(sys.argv[13])
MIRNA_CANDIDATES = Path(sys.argv[14])
SELECTION_SUMMARY = Path(sys.argv[15])
SELECTION_FREEZE = Path(sys.argv[16])
RESULT_JSON = Path(sys.argv[17])


FDR = 0.05
ABS_LOGFC = 1.0

results = {}


def put(k, v):
    results[k] = v
    print(f"{k}={v}")


def read_result(path):
    df = pd.read_csv(
        path,
        compression="gzip",
        engine="c",
        float_precision="round_trip",
    )
    required = {"feature_id","logFC","PValue","FDR","contrast"}
    missing = sorted(required - set(df.columns))
    if missing:
        raise RuntimeError(f"RESULT_COLUMNS_MISSING path={path} missing={missing}")
    return df


# ------------------------------------------------------------
# A. Re-read primary + sensitivity result tables
# ------------------------------------------------------------
mrna = {
    "COV_vs_H": read_result(MRNA_COV_H),
    "P_vs_H": read_result(MRNA_P_H),
    "COV_vs_P": read_result(MRNA_COV_P),
}

mirna = {
    "COV_vs_H": read_result(MIRNA_COV_H),
    "P_vs_H": read_result(MIRNA_P_H),
    "COV_vs_P": read_result(MIRNA_COV_P),
}

mirna_max = {
    "COV_vs_H": read_result(MAX_COV_H),
    "P_vs_H": read_result(MAX_P_H),
    "COV_vs_P": read_result(MAX_COV_P),
}

for modality_name, tables, expected_rows in (
    ("MRNA", mrna, 15083),
    ("MIRNA", mirna, 428),
    ("MIRNA_MAX", mirna_max, 428),
):
    ref = tables["COV_vs_H"]["feature_id"].astype(str).tolist()

    for contrast, df in tables.items():
        if df.shape[0] != expected_rows:
            raise RuntimeError(
                f"{modality_name}_{contrast}_ROWS_CHANGED observed={df.shape[0]}"
            )
        if df["feature_id"].astype(str).tolist() != ref:
            raise RuntimeError(
                f"{modality_name}_{contrast}_FEATURE_ORDER_CHANGED"
            )

if mirna["COV_vs_H"]["feature_id"].astype(str).tolist() != \
   mirna_max["COV_vs_H"]["feature_id"].astype(str).tolist():
    raise RuntimeError("MIRNA_MEDIAN_MAX_FEATURE_ORDER_MISMATCH")

# Reconfirm D6A concordance artifact is structurally complete.
prior_conc = pd.read_csv(D6A_CONCORDANCE)
if prior_conc.shape[0] != 3:
    raise RuntimeError(
        f"D6A_CONCORDANCE_ROWS_CHANGED observed={prior_conc.shape[0]}"
    )

prior_audit = pd.read_csv(D6A_PRIMARY_AUDIT)
if prior_audit.shape[0] != 6 or not prior_audit["status"].astype(str).eq("PASS").all():
    raise RuntimeError("D6A_PRIMARY_AUDIT_NOT_6_OF_6_PASS")

put("D6A_CONCORDANCE_INPUT_RECERTIFIED", "PASS")
put("D6A_PRIMARY_AUDIT_INPUT_RECERTIFIED", "PASS")


# ------------------------------------------------------------
# B. Independent MEDIAN-vs-MAX quantitative review
# ------------------------------------------------------------
review_rows = []

for contrast in ["COV_vs_H","P_vs_H","COV_vs_P"]:
    med = mirna[contrast]
    mx = mirna_max[contrast]

    med_fc = med["logFC"].to_numpy(dtype=np.float64)
    max_fc = mx["logFC"].to_numpy(dtype=np.float64)
    med_fdr = med["FDR"].to_numpy(dtype=np.float64)
    max_fdr = mx["FDR"].to_numpy(dtype=np.float64)

    med_sig = med_fdr <= FDR
    max_sig = max_fdr <= FDR

    med_strict = med_sig & (np.abs(med_fc) >= ABS_LOGFC)
    max_strict = max_sig & (np.abs(max_fc) >= ABS_LOGFC)

    both_sig = med_sig & max_sig
    union_sig = med_sig | max_sig
    both_strict = med_strict & max_strict
    union_strict = med_strict | max_strict

    same_sign_all = np.sign(med_fc) == np.sign(max_fc)
    same_sign_both_sig = same_sign_all & both_sig

    pearson = float(pearsonr(med_fc, max_fc).statistic)
    spearman = float(spearmanr(med_fc, max_fc).statistic)

    sig_jaccard = (
        float(np.sum(both_sig) / np.sum(union_sig))
        if np.sum(union_sig) else 1.0
    )
    strict_jaccard = (
        float(np.sum(both_strict) / np.sum(union_strict))
        if np.sum(union_strict) else 1.0
    )

    row = {
        "contrast": contrast,
        "features_compared": 428,
        "logFC_Pearson_r": pearson,
        "logFC_Spearman_rho": spearman,
        "all_feature_sign_concordance": float(np.mean(same_sign_all)),
        "median_FDR_le_0_05": int(np.sum(med_sig)),
        "max_FDR_le_0_05": int(np.sum(max_sig)),
        "both_FDR_le_0_05": int(np.sum(both_sig)),
        "median_only_FDR_le_0_05": int(np.sum(med_sig & ~max_sig)),
        "max_only_FDR_le_0_05": int(np.sum(max_sig & ~med_sig)),
        "both_significant_same_direction": int(np.sum(same_sign_both_sig)),
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
        "formal_acceptance_threshold_predeclared": "NO",
        "primary_authority": "MEDIAN_UNCHANGED",
    }
    review_rows.append(row)

review = pd.DataFrame(review_rows)
review.to_csv(CONCORDANCE_REVIEW, index=False)

# Cross-check the D6A concordance metrics that were already computed.
for _, row in review.iterrows():
    old = prior_conc.loc[
        prior_conc["contrast"].astype(str).eq(str(row["contrast"]))
    ]
    if old.shape[0] != 1:
        raise RuntimeError(
            f"D6A_CONCORDANCE_CONTRAST_MISSING={row['contrast']}"
        )
    old = old.iloc[0]

    numeric_fields = [
        "logFC_Pearson_r",
        "logFC_Spearman_rho",
        "all_feature_sign_concordance",
        "FDR_le_0_05_Jaccard",
        "strict_Jaccard",
        "median_abs_logFC_difference",
        "max_abs_logFC_difference",
    ]
    integer_fields = [
        "median_FDR_le_0_05",
        "max_FDR_le_0_05",
        "both_FDR_le_0_05",
        "median_only_FDR_le_0_05",
        "max_only_FDR_le_0_05",
        "median_strict",
        "max_strict",
        "both_strict",
    ]

    for field in numeric_fields:
        if abs(float(row[field]) - float(old[field])) > 1e-12:
            raise RuntimeError(
                f"D6A_CONCORDANCE_RECOMPUTE_MISMATCH "
                f"contrast={row['contrast']} field={field}"
            )

    for field in integer_fields:
        if int(row[field]) != int(old[field]):
            raise RuntimeError(
                f"D6A_CONCORDANCE_RECOMPUTE_MISMATCH "
                f"contrast={row['contrast']} field={field}"
            )

put("MIRNA_MEDIAN_MAX_CONCORDANCE_RECOMPUTATION", "PASS")

for _, row in review.iterrows():
    tag = str(row["contrast"])
    put(f"MIRNA_{tag}_MEDIAN_MAX_PEARSON_R", float(row["logFC_Pearson_r"]))
    put(f"MIRNA_{tag}_MEDIAN_MAX_SPEARMAN_RHO", float(row["logFC_Spearman_rho"]))
    put(f"MIRNA_{tag}_MEDIAN_MAX_SIGN_CONCORDANCE", float(row["all_feature_sign_concordance"]))
    put(f"MIRNA_{tag}_MEDIAN_MAX_SIG_JACCARD", float(row["FDR_le_0_05_Jaccard"]))
    put(f"MIRNA_{tag}_MEDIAN_ONLY_SIG", int(row["median_only_FDR_le_0_05"]))
    put(f"MIRNA_{tag}_MAX_ONLY_SIG", int(row["max_only_FDR_le_0_05"]))


# ------------------------------------------------------------
# C. Freeze mRNA primary COVID association candidates
# ------------------------------------------------------------
m_cov = mrna["COV_vs_H"].copy()
m_p = mrna["P_vs_H"].copy()
m_cp = mrna["COV_vs_P"].copy()

if not (
    m_cov["feature_id"].astype(str).tolist()
    == m_p["feature_id"].astype(str).tolist()
    == m_cp["feature_id"].astype(str).tolist()
):
    raise RuntimeError("MRNA_CONTRAST_FEATURE_ORDER_MISMATCH")

m_keep = m_cov["FDR"].to_numpy(dtype=np.float64) <= FDR

if int(np.sum(m_keep)) != 8505:
    raise RuntimeError(
        f"MRNA_PRIMARY_COVID_CANDIDATE_COUNT_CHANGED observed={int(np.sum(m_keep))}"
    )

m_out = pd.DataFrame({
    "feature_id": m_cov.loc[m_keep, "feature_id"].astype(str).to_numpy(),
    "primary_selection_rule": "COV_vs_H_BH_FDR_LE_0.05",
    "COV_vs_H_logFC": m_cov.loc[m_keep, "logFC"].to_numpy(dtype=np.float64),
    "COV_vs_H_PValue": m_cov.loc[m_keep, "PValue"].to_numpy(dtype=np.float64),
    "COV_vs_H_FDR": m_cov.loc[m_keep, "FDR"].to_numpy(dtype=np.float64),
    "COV_vs_H_strict_priority": np.where(
        np.abs(m_cov.loc[m_keep, "logFC"].to_numpy(dtype=np.float64)) >= ABS_LOGFC,
        "YES","NO"
    ),
    "P_vs_H_logFC": m_p.loc[m_keep, "logFC"].to_numpy(dtype=np.float64),
    "P_vs_H_FDR": m_p.loc[m_keep, "FDR"].to_numpy(dtype=np.float64),
    "P_vs_H_significant_FDR_le_0_05": np.where(
        m_p.loc[m_keep, "FDR"].to_numpy(dtype=np.float64) <= FDR,
        "YES","NO"
    ),
    "COV_vs_P_logFC": m_cp.loc[m_keep, "logFC"].to_numpy(dtype=np.float64),
    "COV_vs_P_FDR": m_cp.loc[m_keep, "FDR"].to_numpy(dtype=np.float64),
    "COV_vs_P_significant_FDR_le_0_05": np.where(
        m_cp.loc[m_keep, "FDR"].to_numpy(dtype=np.float64) <= FDR,
        "YES","NO"
    ),
})

m_out.to_csv(
    MRNA_CANDIDATES,
    index=False,
    compression="gzip",
    float_format="%.17g",
)

put("MRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES", int(m_out.shape[0]))
put(
    "MRNA_PRIMARY_COVID_STRICT_PRIORITY_COUNT",
    int(np.sum(m_out["COV_vs_H_strict_priority"].eq("YES")))
)


# ------------------------------------------------------------
# D. Freeze miRNA primary COVID association candidates
#     + row-level MAX sensitivity annotation
# ------------------------------------------------------------
mi_cov = mirna["COV_vs_H"].copy()
mi_p = mirna["P_vs_H"].copy()
mi_cp = mirna["COV_vs_P"].copy()

mx_cov = mirna_max["COV_vs_H"].copy()
mx_p = mirna_max["P_vs_H"].copy()
mx_cp = mirna_max["COV_vs_P"].copy()

mi_keep = mi_cov["FDR"].to_numpy(dtype=np.float64) <= FDR

if int(np.sum(mi_keep)) != 41:
    raise RuntimeError(
        f"MIRNA_PRIMARY_COVID_CANDIDATE_COUNT_CHANGED observed={int(np.sum(mi_keep))}"
    )

med_fc = mi_cov.loc[mi_keep, "logFC"].to_numpy(dtype=np.float64)
max_fc = mx_cov.loc[mi_keep, "logFC"].to_numpy(dtype=np.float64)
max_fdr = mx_cov.loc[mi_keep, "FDR"].to_numpy(dtype=np.float64)

max_sig = max_fdr <= FDR
same_dir = np.sign(med_fc) == np.sign(max_fc)

sensitivity_status = np.where(
    max_sig & same_dir,
    "MAX_FDR_REPLICATED_SAME_DIRECTION",
    np.where(
        max_sig & ~same_dir,
        "MAX_FDR_REPLICATED_OPPOSITE_DIRECTION",
        np.where(
            ~max_sig & same_dir,
            "MAX_NOT_FDR_SIG_SAME_DIRECTION",
            "MAX_NOT_FDR_SIG_OPPOSITE_DIRECTION",
        ),
    ),
)

mi_out = pd.DataFrame({
    "feature_id": mi_cov.loc[mi_keep, "feature_id"].astype(str).to_numpy(),
    "primary_selection_rule": "MEDIAN_COV_vs_H_BH_FDR_LE_0.05",
    "primary_consolidation": "MEDIAN",
    "MEDIAN_COV_vs_H_logFC": med_fc,
    "MEDIAN_COV_vs_H_PValue": mi_cov.loc[mi_keep, "PValue"].to_numpy(dtype=np.float64),
    "MEDIAN_COV_vs_H_FDR": mi_cov.loc[mi_keep, "FDR"].to_numpy(dtype=np.float64),
    "MEDIAN_COV_vs_H_strict_priority": np.where(
        np.abs(med_fc) >= ABS_LOGFC,
        "YES","NO"
    ),
    "MEDIAN_P_vs_H_logFC": mi_p.loc[mi_keep, "logFC"].to_numpy(dtype=np.float64),
    "MEDIAN_P_vs_H_FDR": mi_p.loc[mi_keep, "FDR"].to_numpy(dtype=np.float64),
    "MEDIAN_P_vs_H_significant_FDR_le_0_05": np.where(
        mi_p.loc[mi_keep, "FDR"].to_numpy(dtype=np.float64) <= FDR,
        "YES","NO"
    ),
    "MEDIAN_COV_vs_P_logFC": mi_cp.loc[mi_keep, "logFC"].to_numpy(dtype=np.float64),
    "MEDIAN_COV_vs_P_FDR": mi_cp.loc[mi_keep, "FDR"].to_numpy(dtype=np.float64),
    "MEDIAN_COV_vs_P_significant_FDR_le_0_05": np.where(
        mi_cp.loc[mi_keep, "FDR"].to_numpy(dtype=np.float64) <= FDR,
        "YES","NO"
    ),
    "MAX_COV_vs_H_logFC": max_fc,
    "MAX_COV_vs_H_FDR": max_fdr,
    "MAX_COV_vs_H_significant_FDR_le_0_05": np.where(max_sig,"YES","NO"),
    "MEDIAN_MAX_COV_vs_H_same_direction": np.where(same_dir,"YES","NO"),
    "MEDIAN_MAX_COV_vs_H_abs_logFC_difference": np.abs(med_fc - max_fc),
    "MAX_P_vs_H_logFC": mx_p.loc[mi_keep, "logFC"].to_numpy(dtype=np.float64),
    "MAX_P_vs_H_FDR": mx_p.loc[mi_keep, "FDR"].to_numpy(dtype=np.float64),
    "MAX_COV_vs_P_logFC": mx_cp.loc[mi_keep, "logFC"].to_numpy(dtype=np.float64),
    "MAX_COV_vs_P_FDR": mx_cp.loc[mi_keep, "FDR"].to_numpy(dtype=np.float64),
    "MAX_sensitivity_status_for_primary_COV_vs_H_candidate": sensitivity_status,
})

mi_out.to_csv(
    MIRNA_CANDIDATES,
    index=False,
    compression="gzip",
    float_format="%.17g",
)

rep_same = int(np.sum(
    mi_out[
        "MAX_sensitivity_status_for_primary_COV_vs_H_candidate"
    ].eq("MAX_FDR_REPLICATED_SAME_DIRECTION")
))
rep_opp = int(np.sum(
    mi_out[
        "MAX_sensitivity_status_for_primary_COV_vs_H_candidate"
    ].eq("MAX_FDR_REPLICATED_OPPOSITE_DIRECTION")
))
not_sig = int(np.sum(
    ~mi_out["MAX_COV_vs_H_significant_FDR_le_0_05"].eq("YES")
))

put("MIRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES", int(mi_out.shape[0]))
put(
    "MIRNA_PRIMARY_COVID_STRICT_PRIORITY_COUNT",
    int(np.sum(mi_out["MEDIAN_COV_vs_H_strict_priority"].eq("YES")))
)
put("MIRNA_PRIMARY_CANDIDATES_MAX_REPLICATED_SAME_DIRECTION", rep_same)
put("MIRNA_PRIMARY_CANDIDATES_MAX_REPLICATED_OPPOSITE_DIRECTION", rep_opp)
put("MIRNA_PRIMARY_CANDIDATES_MAX_NOT_FDR_SIG", not_sig)


# ------------------------------------------------------------
# E. Freeze selection summary and policy
# ------------------------------------------------------------
summary = pd.DataFrame([
    {
        "modality": "mRNA",
        "primary_consolidation": "N/A",
        "primary_contrast": "COV_vs_H",
        "primary_selection": "BH_FDR_LE_0.05",
        "candidates": int(m_out.shape[0]),
        "strict_priority_abs_log2FC_ge_1": int(
            np.sum(m_out["COV_vs_H_strict_priority"].eq("YES"))
        ),
        "sepsis_contrasts_role": "ANNOTATION_NOT_DELETION_GATE",
        "sensitivity_role": "N/A",
    },
    {
        "modality": "miRNA",
        "primary_consolidation": "MEDIAN",
        "primary_contrast": "COV_vs_H",
        "primary_selection": "BH_FDR_LE_0.05",
        "candidates": int(mi_out.shape[0]),
        "strict_priority_abs_log2FC_ge_1": int(
            np.sum(mi_out["MEDIAN_COV_vs_H_strict_priority"].eq("YES"))
        ),
        "sepsis_contrasts_role": "ANNOTATION_NOT_DELETION_GATE",
        "sensitivity_role": "MAX_ANNOTATION_ONLY_PRIMARY_MEDIAN_UNCHANGED",
    },
])
summary.to_csv(SELECTION_SUMMARY, index=False)

freeze_lines = [
    "GSE243219_D6B_DOWNSTREAM_FEATURE_SELECTION_FREEZE",
    "PRIMARY_DOWNSTREAM_BIOLOGICAL_CONTRAST=COV_vs_H",
    "PRIMARY_DOWNSTREAM_STATISTICAL_SELECTION=BH_FDR_LE_0.05",
    "PRIMARY_MRNA_CANDIDATES=8505",
    "PRIMARY_MIRNA_CANDIDATES=41",
    "PRIMARY_MIRNA_CONSOLIDATION=MEDIAN",
    "MAX_MIRNA_ROLE=SENSITIVITY_ANNOTATION_ONLY",
    "MAX_MIRNA_CAN_DELETE_PRIMARY_MEDIAN_CANDIDATE=NO",
    "SEPSIS_P_vs_H_ROLE=COMPARATOR_ANNOTATION",
    "COVID_VS_SEPSIS_COV_vs_P_ROLE=SPECIFICITY_ANNOTATION",
    "SEPSIS_CONTRASTS_CAN_DELETE_PRIMARY_COVID_CANDIDATE_AT_D6B=NO",
    "ABS_LOG2FC_GE_1_ROLE=PRIORITIZATION_ONLY",
    "ABS_LOG2FC_GE_1_USED_AS_PRIMARY_ASSOCIATION_GATE=NO",
    "PRIMARY_MRNA_STRICT_PRIORITY_COUNT=3618",
    "PRIMARY_MIRNA_STRICT_PRIORITY_COUNT=22",
    "FORMAL_MEDIAN_MAX_CONCORDANCE_ACCEPTANCE_THRESHOLD_PREDECLARED=NO",
    "POST_HOC_CONCORDANCE_THRESHOLD_ADDED=NO",
    "ASSOCIATION_INPUT_FEATURE_UNIVERSE_FROZEN=YES",
    "ASSOCIATION_INPUT_MRNA_FEATURES=8505",
    "ASSOCIATION_INPUT_MIRNA_FEATURES=41",
    "ASSOCIATION_EXECUTED_IN_D6B=NO",
    "NETWORK_EXECUTED_IN_D6B=NO",
    "ACLA_EXECUTED_IN_D6B=NO",
]
SELECTION_FREEZE.write_text(
    "\n".join(freeze_lines) + "\n",
    encoding="utf-8",
)

put("PRIMARY_MIRNA_AUTHORITY", "MEDIAN_UNCHANGED")
put("POST_HOC_CONCORDANCE_THRESHOLD_ADDED", "NO")
put("SEPSIS_CONTRASTS_USED_AS_DELETION_GATE", "NO")
put("ABS_LOG2FC_GE_1_USED_AS_PRIMARY_ASSOCIATION_GATE", "NO")
put("ASSOCIATION_INPUT_FEATURE_UNIVERSE_FROZEN", "YES")
put("ASSOCIATION_INPUT_MRNA_FEATURES", 8505)
put("ASSOCIATION_INPUT_MIRNA_FEATURES", 41)
put("DE_REEXECUTED", "NO")
put("FEATURE_REFILTERING_EXECUTED", "NO")
put("COUNT_ROUNDING_EXECUTED", "NO")
put("SAMPLE_EXCLUSION_EXECUTED", "NO")
put("ASSOCIATION_EXECUTED", "NO")
put("NETWORK_EXECUTED", "NO")
put("ACLA_EXECUTED", "NO")
put("READY_FOR_D7_ASSOCIATION_AND_STABILITY_DESIGN_PREFLIGHT", "YES")
put("NEXT_PHASE", "D7_PAIRED_MRNA_MIRNA_ASSOCIATION_AND_STABILITY_DESIGN_PREFLIGHT")

RESULT_JSON.write_text(
    json.dumps({"results": results}, indent=2, sort_keys=True),
    encoding="utf-8",
)
'@

$PythonCode | Set-Content -LiteralPath $PyScript -Encoding UTF8

$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

$PythonExe = 'C:\Users\Amir\OneDrive\Desktop\covid-19\GSE243219_NEW_PROJECT\02_INPUT_AUDIT_AND_PAIRING\D2D_PREFLIGHT_20260904_195001\venv\Scripts\python.exe'

if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw ('PYTHON_EXECUTABLE_MISSING={0}' -f $PythonExe)
}

$PythonArgs = @(
    '-u',
    $PyScript,
    $MrnaCovH,
    $MrnaPH,
    $MrnaCovP,
    $MirnaCovH,
    $MirnaPH,
    $MirnaCovP,
    $MaxCovH,
    $MaxPH,
    $MaxCovP,
    $D6AConcordance,
    $D6APrimaryAudit,
    $ConcordanceReview,
    $MrnaCandidates,
    $MirnaCandidates,
    $SelectionSummary,
    $SelectionFreeze,
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
        Write-Host '=== D6B PYTHON STDERR ==='
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
    throw ('D6B_PYTHON_FAILED exit={0} full_traceback={1}' -f `
        $PythonExit,$PythonStderr)
}

if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
    throw 'D6B_RESULT_JSON_MISSING'
}

$result = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json

function Cap {
    param([string]$Key)
    return [string]$result.results.$Key
}

foreach ($pair in @(
    @('D6A_CONCORDANCE_INPUT_RECERTIFIED','PASS'),
    @('D6A_PRIMARY_AUDIT_INPUT_RECERTIFIED','PASS'),
    @('MIRNA_MEDIAN_MAX_CONCORDANCE_RECOMPUTATION','PASS'),
    @('MRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES','8505'),
    @('MRNA_PRIMARY_COVID_STRICT_PRIORITY_COUNT','3618'),
    @('MIRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES','41'),
    @('MIRNA_PRIMARY_COVID_STRICT_PRIORITY_COUNT','22'),
    @('PRIMARY_MIRNA_AUTHORITY','MEDIAN_UNCHANGED'),
    @('POST_HOC_CONCORDANCE_THRESHOLD_ADDED','NO'),
    @('SEPSIS_CONTRASTS_USED_AS_DELETION_GATE','NO'),
    @('ABS_LOG2FC_GE_1_USED_AS_PRIMARY_ASSOCIATION_GATE','NO'),
    @('ASSOCIATION_INPUT_FEATURE_UNIVERSE_FROZEN','YES'),
    @('ASSOCIATION_INPUT_MRNA_FEATURES','8505'),
    @('ASSOCIATION_INPUT_MIRNA_FEATURES','41'),
    @('DE_REEXECUTED','NO'),
    @('FEATURE_REFILTERING_EXECUTED','NO'),
    @('COUNT_ROUNDING_EXECUTED','NO'),
    @('SAMPLE_EXCLUSION_EXECUTED','NO'),
    @('ASSOCIATION_EXECUTED','NO'),
    @('NETWORK_EXECUTED','NO'),
    @('ACLA_EXECUTED','NO'),
    @('READY_FOR_D7_ASSOCIATION_AND_STABILITY_DESIGN_PREFLIGHT','YES'),
    @('NEXT_PHASE','D7_PAIRED_MRNA_MIRNA_ASSOCIATION_AND_STABILITY_DESIGN_PREFLIGHT')
)) {
    $observed = Cap $pair[0]
    if ($observed -ne $pair[1]) {
        throw ('D6B_FINAL_GATE_FAILED key={0} expected={1} observed={2}' -f `
            $pair[0],$pair[1],$observed)
    }
}

# ------------------------------------------------------------
# 3. Decision
# ------------------------------------------------------------
@(
    'GSE243219_D6B_DECISION',
    'PHASE_D6B_STATUS=PASS',
    'MODE=REVIEW_AND_SELECTION_FREEZE_ONLY',
    'D6_V5_CERTIFICATION_GATE=PASS',
    'D6_V5_OUTPUTS_RECERTIFIED=16/16',
    'D6A_CERTIFICATION_GATE=PASS',
    'D6A_OUTPUTS_RECERTIFIED=16/16',
    'MIRNA_MEDIAN_MAX_CONCORDANCE_RECOMPUTATION=PASS',
    ('MIRNA_COV_vs_H_MEDIAN_MAX_PEARSON_R={0}' -f (Cap 'MIRNA_COV_vs_H_MEDIAN_MAX_PEARSON_R')),
    ('MIRNA_COV_vs_H_MEDIAN_MAX_SPEARMAN_RHO={0}' -f (Cap 'MIRNA_COV_vs_H_MEDIAN_MAX_SPEARMAN_RHO')),
    ('MIRNA_COV_vs_H_MEDIAN_MAX_SIGN_CONCORDANCE={0}' -f (Cap 'MIRNA_COV_vs_H_MEDIAN_MAX_SIGN_CONCORDANCE')),
    ('MIRNA_COV_vs_H_MEDIAN_MAX_SIG_JACCARD={0}' -f (Cap 'MIRNA_COV_vs_H_MEDIAN_MAX_SIG_JACCARD')),
    ('MIRNA_COV_vs_H_MEDIAN_ONLY_SIG={0}' -f (Cap 'MIRNA_COV_vs_H_MEDIAN_ONLY_SIG')),
    ('MIRNA_COV_vs_H_MAX_ONLY_SIG={0}' -f (Cap 'MIRNA_COV_vs_H_MAX_ONLY_SIG')),
    ('MIRNA_P_vs_H_MEDIAN_MAX_PEARSON_R={0}' -f (Cap 'MIRNA_P_vs_H_MEDIAN_MAX_PEARSON_R')),
    ('MIRNA_P_vs_H_MEDIAN_MAX_SPEARMAN_RHO={0}' -f (Cap 'MIRNA_P_vs_H_MEDIAN_MAX_SPEARMAN_RHO')),
    ('MIRNA_P_vs_H_MEDIAN_MAX_SIG_JACCARD={0}' -f (Cap 'MIRNA_P_vs_H_MEDIAN_MAX_SIG_JACCARD')),
    ('MIRNA_COV_vs_P_MEDIAN_MAX_PEARSON_R={0}' -f (Cap 'MIRNA_COV_vs_P_MEDIAN_MAX_PEARSON_R')),
    ('MIRNA_COV_vs_P_MEDIAN_MAX_SPEARMAN_RHO={0}' -f (Cap 'MIRNA_COV_vs_P_MEDIAN_MAX_SPEARMAN_RHO')),
    ('MIRNA_COV_vs_P_MEDIAN_MAX_SIG_JACCARD={0}' -f (Cap 'MIRNA_COV_vs_P_MEDIAN_MAX_SIG_JACCARD')),
    'FORMAL_MEDIAN_MAX_ACCEPTANCE_THRESHOLD_PREDECLARED=NO',
    'POST_HOC_CONCORDANCE_THRESHOLD_ADDED=NO',
    'PRIMARY_MIRNA_AUTHORITY=MEDIAN_UNCHANGED',
    'PRIMARY_DOWNSTREAM_CONTRAST=COV_vs_H',
    'PRIMARY_DOWNSTREAM_SELECTION=BH_FDR_LE_0.05',
    'MRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES=8505',
    'MRNA_PRIMARY_COVID_STRICT_PRIORITY_COUNT=3618',
    'MIRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES=41',
    'MIRNA_PRIMARY_COVID_STRICT_PRIORITY_COUNT=22',
    ('MIRNA_PRIMARY_CANDIDATES_MAX_REPLICATED_SAME_DIRECTION={0}' -f (Cap 'MIRNA_PRIMARY_CANDIDATES_MAX_REPLICATED_SAME_DIRECTION')),
    ('MIRNA_PRIMARY_CANDIDATES_MAX_REPLICATED_OPPOSITE_DIRECTION={0}' -f (Cap 'MIRNA_PRIMARY_CANDIDATES_MAX_REPLICATED_OPPOSITE_DIRECTION')),
    ('MIRNA_PRIMARY_CANDIDATES_MAX_NOT_FDR_SIG={0}' -f (Cap 'MIRNA_PRIMARY_CANDIDATES_MAX_NOT_FDR_SIG')),
    'SEPSIS_CONTRASTS_USED_AS_DELETION_GATE=NO',
    'ABS_LOG2FC_GE_1_USED_AS_PRIMARY_ASSOCIATION_GATE=NO',
    'ASSOCIATION_INPUT_FEATURE_UNIVERSE_FROZEN=YES',
    'ASSOCIATION_INPUT_MRNA_FEATURES=8505',
    'ASSOCIATION_INPUT_MIRNA_FEATURES=41',
    'DE_REEXECUTED=NO',
    'FEATURE_REFILTERING_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'ASSOCIATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D7_ASSOCIATION_AND_STABILITY_DESIGN_PREFLIGHT=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D7_PAIRED_MRNA_MIRNA_ASSOCIATION_AND_STABILITY_DESIGN_PREFLIGHT',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 4. Manifest
# ------------------------------------------------------------
$outFiles = @(
    $PyScript,
    $ConcordanceReview,
    $MrnaCandidates,
    $MirnaCandidates,
    $SelectionSummary,
    $SelectionFreeze,
    $ResultJson,
    $PythonStdout,
    $PythonStderr,
    $PythonLog,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('D6B_OUTPUT_MISSING={0}' -f $p)
    }

    $item = Get-Item -LiteralPath $p
    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D6BSHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D6B SUMMARY ===',
    'PHASE_D6B_STATUS=PASS',
    'MODE=REVIEW_AND_SELECTION_FREEZE_ONLY',
    'D6_V5_CERTIFICATION_GATE=PASS',
    'D6A_CERTIFICATION_GATE=PASS',
    'MIRNA_MEDIAN_MAX_CONCORDANCE_RECOMPUTATION=PASS',
    ('MIRNA_COV_vs_H_MEDIAN_MAX_PEARSON_R={0}' -f (Cap 'MIRNA_COV_vs_H_MEDIAN_MAX_PEARSON_R')),
    ('MIRNA_COV_vs_H_MEDIAN_MAX_SPEARMAN_RHO={0}' -f (Cap 'MIRNA_COV_vs_H_MEDIAN_MAX_SPEARMAN_RHO')),
    ('MIRNA_COV_vs_H_MEDIAN_MAX_SIGN_CONCORDANCE={0}' -f (Cap 'MIRNA_COV_vs_H_MEDIAN_MAX_SIGN_CONCORDANCE')),
    ('MIRNA_COV_vs_H_MEDIAN_MAX_SIG_JACCARD={0}' -f (Cap 'MIRNA_COV_vs_H_MEDIAN_MAX_SIG_JACCARD')),
    ('MIRNA_COV_vs_H_MEDIAN_ONLY_SIG={0}' -f (Cap 'MIRNA_COV_vs_H_MEDIAN_ONLY_SIG')),
    ('MIRNA_COV_vs_H_MAX_ONLY_SIG={0}' -f (Cap 'MIRNA_COV_vs_H_MAX_ONLY_SIG')),
    ('MIRNA_P_vs_H_MEDIAN_MAX_PEARSON_R={0}' -f (Cap 'MIRNA_P_vs_H_MEDIAN_MAX_PEARSON_R')),
    ('MIRNA_P_vs_H_MEDIAN_MAX_SPEARMAN_RHO={0}' -f (Cap 'MIRNA_P_vs_H_MEDIAN_MAX_SPEARMAN_RHO')),
    ('MIRNA_P_vs_H_MEDIAN_MAX_SIG_JACCARD={0}' -f (Cap 'MIRNA_P_vs_H_MEDIAN_MAX_SIG_JACCARD')),
    ('MIRNA_COV_vs_P_MEDIAN_MAX_PEARSON_R={0}' -f (Cap 'MIRNA_COV_vs_P_MEDIAN_MAX_PEARSON_R')),
    ('MIRNA_COV_vs_P_MEDIAN_MAX_SPEARMAN_RHO={0}' -f (Cap 'MIRNA_COV_vs_P_MEDIAN_MAX_SPEARMAN_RHO')),
    ('MIRNA_COV_vs_P_MEDIAN_MAX_SIG_JACCARD={0}' -f (Cap 'MIRNA_COV_vs_P_MEDIAN_MAX_SIG_JACCARD')),
    'FORMAL_MEDIAN_MAX_ACCEPTANCE_THRESHOLD_PREDECLARED=NO',
    'POST_HOC_CONCORDANCE_THRESHOLD_ADDED=NO',
    'PRIMARY_MIRNA_AUTHORITY=MEDIAN_UNCHANGED',
    'PRIMARY_DOWNSTREAM_CONTRAST=COV_vs_H',
    'PRIMARY_DOWNSTREAM_SELECTION=BH_FDR_LE_0.05',
    'MRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES=8505',
    'MRNA_PRIMARY_COVID_STRICT_PRIORITY_COUNT=3618',
    'MIRNA_PRIMARY_COVID_ASSOCIATION_CANDIDATES=41',
    'MIRNA_PRIMARY_COVID_STRICT_PRIORITY_COUNT=22',
    ('MIRNA_PRIMARY_CANDIDATES_MAX_REPLICATED_SAME_DIRECTION={0}' -f (Cap 'MIRNA_PRIMARY_CANDIDATES_MAX_REPLICATED_SAME_DIRECTION')),
    ('MIRNA_PRIMARY_CANDIDATES_MAX_REPLICATED_OPPOSITE_DIRECTION={0}' -f (Cap 'MIRNA_PRIMARY_CANDIDATES_MAX_REPLICATED_OPPOSITE_DIRECTION')),
    ('MIRNA_PRIMARY_CANDIDATES_MAX_NOT_FDR_SIG={0}' -f (Cap 'MIRNA_PRIMARY_CANDIDATES_MAX_NOT_FDR_SIG')),
    'SEPSIS_CONTRASTS_USED_AS_DELETION_GATE=NO',
    'ABS_LOG2FC_GE_1_USED_AS_PRIMARY_ASSOCIATION_GATE=NO',
    'ASSOCIATION_INPUT_FEATURE_UNIVERSE_FROZEN=YES',
    'ASSOCIATION_INPUT_MRNA_FEATURES=8505',
    'ASSOCIATION_INPUT_MIRNA_FEATURES=41',
    'DE_REEXECUTED=NO',
    'FEATURE_REFILTERING_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'ASSOCIATION_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_D7_ASSOCIATION_AND_STABILITY_DESIGN_PREFLIGHT=YES',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D7_PAIRED_MRNA_MIRNA_ASSOCIATION_AND_STABILITY_DESIGN_PREFLIGHT',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D6B_MIRNA_CONCORDANCE_REVIEW={0}' -f $ConcordanceReview)
Write-Host ('D6B_MRNA_CANDIDATES={0}' -f $MrnaCandidates)
Write-Host ('D6B_MIRNA_CANDIDATES={0}' -f $MirnaCandidates)
Write-Host ('D6B_SELECTION_SUMMARY={0}' -f $SelectionSummary)
Write-Host ('D6B_SELECTION_FREEZE={0}' -f $SelectionFreeze)
Write-Host ('D6B_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D6B_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D6B=PASS'
Write-Host 'STOP=YES'
