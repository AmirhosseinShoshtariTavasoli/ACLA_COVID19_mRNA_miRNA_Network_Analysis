$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D2C — PROSPECTIVE FEATURE-IDENTITY + STATISTICAL STRATEGY
#
# DESIGN-FREEZE / AUDIT ONLY.
#
# This phase DOES NOT:
#   - construct expression matrices
#   - aggregate miRNA counts
#   - round mRNA counts
#   - normalize
#   - filter/exclude samples/features
#   - perform DE
#   - build networks
#   - execute A-CLA
#
# Purpose:
#   1) Re-certify D2B-V2 evidence.
#   2) Audit what sample-level covariates actually exist in GEO SOFT.
#   3) Freeze the feature-identity policy.
#   4) Freeze the statistical-family strategy without yet executing it.
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D1Downloads = Join-Path $Project '01_PROCESSED_DATA_ACQUISITION\downloads'
$D2Root = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING'

$D2BRun = Join-Path $D2Root 'D2B_AUDIT_20260904_192048'
$D2BDecision = Join-Path $D2BRun 'D2B_DECISION.txt'
$D2BManifest = Join-Path $D2BRun 'D2B_OUTPUT_SHA256_MANIFEST.csv'
$D2BCount = Join-Path $D2BRun 'D2B_COUNT_SEMANTICS_SUMMARY.csv'
$D2BIdentity = Join-Path $D2BRun 'D2B_MIRNA_REGULATORY_IDENTITY_SUMMARY.csv'

$D2BReport = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D2B_20260904_192048\PHASE_D2B_SUMMARY.txt'

$MrnaSoft = Join-Path $D1Downloads 'GSE243217_family.soft.gz'
$MirnaSoft = Join-Path $D1Downloads 'GSE243218_family.soft.gz'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D2Root ('D2C_STRATEGY_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D2C_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$CovariateCsv = Join-Path $RunDir 'D2C_GEO_CHARACTERISTIC_COVERAGE.csv'
$StrategyTxt = Join-Path $RunDir 'D2C_FROZEN_FEATURE_IDENTITY_AND_STATISTICAL_STRATEGY.txt'
$DecisionCsv = Join-Path $RunDir 'D2C_METHOD_DECISION_REGISTRY.csv'
$ManifestCsv = Join-Path $RunDir 'D2C_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D2C_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D2C-V2 — PROSPECTIVE FEATURE-IDENTITY + STATISTICAL STRATEGY ==='
Write-Host 'MODE=DESIGN_FREEZE_AND_METADATA_AUDIT_ONLY'
Write-Host 'MATRIX_CONSTRUCTION_EXECUTED=NO'
Write-Host 'FEATURE_AGGREGATION_EXECUTED=NO'
Write-Host 'COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'NORMALIZATION_EXECUTED=NO'
Write-Host 'FILTERING_EXECUTED=NO'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'DE_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $D2BDecision,$D2BManifest,$D2BCount,$D2BIdentity,$D2BReport,
    $MrnaSoft,$MirnaSoft
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D2CSHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-D2CGzipText {
    param([string]$Path)

    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $gz = New-Object System.IO.Compression.GZipStream(
            $fs,
            [System.IO.Compression.CompressionMode]::Decompress
        )
        try {
            $sr = New-Object System.IO.StreamReader($gz)
            try { return $sr.ReadToEnd() }
            finally { $sr.Dispose() }
        }
        finally { $gz.Dispose() }
    }
    finally { $fs.Dispose() }
}

# ------------------------------------------------------------
# 1. D2B-V2 certification chain
# ------------------------------------------------------------
$d2bSummary = Get-Content -LiteralPath $D2BReport -Raw
$d2bDecisionText = Get-Content -LiteralPath $D2BDecision -Raw

foreach ($tok in @(
    'PHASE_D2B_V2_STATUS=PASS',
    'COUNT_FILES_RECERTIFIED=144/144',
    'STRUCTURE_AWARE_COUNT_FILES_AUDITED=144/144',
    'STRUCTURE_AWARE_HARD_FAILURES=0',
    'MRNA_RAW_FEATURE_KEY=gene_symbol',
    'MIRNA_RAW_FEATURE_KEY=pre-miRNA|MIMAT|mature-miRNA',
    'MIRNA_REGULATORY_IDENTITY_KEY=MIMAT|mature-miRNA',
    'MRNA_RAW_FEATURE_SETS_IDENTICAL=YES',
    'MRNA_RAW_FEATURE_ORDER_IDENTICAL=YES',
    'MRNA_RAW_FEATURE_COUNT_PATTERNS=26364',
    'MIRNA_RAW_FEATURE_SETS_IDENTICAL=YES',
    'MIRNA_RAW_FEATURE_ORDER_IDENTICAL=YES',
    'MIRNA_RAW_FEATURE_COUNT_PATTERNS=2886',
    'MRNA_COUNT_INTEGER_STATUS=FRACTIONAL_VALUES_PRESENT',
    'MRNA_SAMPLES_WITH_FRACTIONAL_VALUES=72',
    'MRNA_TOTAL_FRACTIONAL_VALUES=355532',
    'MIRNA_COUNT_INTEGER_STATUS=ALL_NONNEGATIVE_INTEGER_VALUES',
    'MIRNA_SAMPLES_WITH_FRACTIONAL_VALUES=0',
    'MIRNA_TOTAL_FRACTIONAL_VALUES=0',
    'MIRNA_UNIQUE_REGULATORY_IDENTITIES=2656',
    'MIRNA_REPEATED_REGULATORY_IDENTITY_GROUPS=166',
    'MIRNA_MIMAT_TO_MULTIPLE_MATURE_CONFLICTS=0',
    'MIRNA_MATURE_TO_MULTIPLE_MIMAT_CONFLICTS=0',
    'MIRNA_REPEATED_IDENTITY_GROUPS_IDENTICAL_COUNTS=10608',
    'MIRNA_REPEATED_IDENTITY_GROUPS_DIFFERENT_COUNTS=1344',
    'RAW_MATRIX_CONSTRUCTION_TECHNICALLY_FEASIBLE=YES',
    'MIRNA_REGULATORY_CONSOLIDATION_REVIEW_REQUIRED=YES',
    'DE_METHOD_REVIEW_REQUIRED=YES',
    'NEXT_PHASE=D2C_PROSPECTIVE_FEATURE_IDENTITY_AND_STATISTICAL_STRATEGY'
)) {
    if ($d2bSummary -notmatch [regex]::Escape($tok)) {
        throw ('D2B_V2_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

foreach ($tok in @(
    'PHASE_D2B_V2_STATUS=PASS',
    'MRNA_RAW_FEATURE_KEY=gene_symbol',
    'MIRNA_RAW_FEATURE_KEY=pre-miRNA|MIMAT|mature-miRNA',
    'MIRNA_REGULATORY_IDENTITY_KEY=MIMAT|mature-miRNA',
    'READY_FOR_MATRIX_CONSTRUCTION=NO',
    'READY_FOR_NORMALIZATION=NO',
    'READY_FOR_DE=NO'
)) {
    if ($d2bDecisionText -notmatch [regex]::Escape($tok)) {
        throw ('D2B_DECISION_TOKEN_MISSING={0}' -f $tok)
    }
}

# Re-certify the D2B output artifacts by the D2B manifest.
$d2bManifestRows = @(Import-Csv -LiteralPath $D2BManifest)

if ($d2bManifestRows.Count -ne 8) {
    throw ('D2B_OUTPUT_MANIFEST_ROW_COUNT_CHANGED expected=8 observed={0}' -f $d2bManifestRows.Count)
}

foreach ($r in $d2bManifestRows) {
    if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
        throw ('D2B_OUTPUT_MISSING={0}' -f $r.full_path)
    }

    $item = Get-Item -LiteralPath $r.full_path
    $hash = Get-D2CSHA256 $r.full_path

    if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
        $hash -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D2B_OUTPUT_HASH_OR_SIZE_CHANGED={0}' -f $r.full_path)
    }
}

Write-Host 'D2B_V2_CERTIFICATION_GATE=PASS'
Write-Host 'D2B_OUTPUTS_RECERTIFIED=8/8'

# ------------------------------------------------------------
# 2. Recalculate decision-driving percentages from certified facts
# ------------------------------------------------------------
[Int64]$MrnaFeatures = 26364
[Int64]$Samples = 72
[Int64]$MrnaCells = $MrnaFeatures * $Samples
[Int64]$MrnaFractional = 355532

[Int64]$MirnaRegIds = 2656
[Int64]$MirnaRepeatedIds = 166
[Int64]$RepeatedAcrossSamples = 11952
[Int64]$RepeatedIdentical = 10608
[Int64]$RepeatedDifferent = 1344

$MrnaFractionalPct = [math]::Round(100.0 * $MrnaFractional / $MrnaCells,4)
$MirnaRepeatedIdentityPct = [math]::Round(100.0 * $MirnaRepeatedIds / $MirnaRegIds,4)
$MirnaRepeatedIdenticalPct = [math]::Round(100.0 * $RepeatedIdentical / $RepeatedAcrossSamples,4)
$MirnaRepeatedDifferentPct = [math]::Round(100.0 * $RepeatedDifferent / $RepeatedAcrossSamples,4)

Write-Host ('MRNA_FRACTIONAL_COUNT_CELL_PERCENT={0}' -f $MrnaFractionalPct)
Write-Host ('MIRNA_REPEATED_REGULATORY_IDENTITY_PERCENT={0}' -f $MirnaRepeatedIdentityPct)
Write-Host ('MIRNA_REPEATED_IDENTITY_GROUPS_IDENTICAL_PERCENT={0}' -f $MirnaRepeatedIdenticalPct)
Write-Host ('MIRNA_REPEATED_IDENTITY_GROUPS_DIFFERENT_PERCENT={0}' -f $MirnaRepeatedDifferentPct)

# ------------------------------------------------------------
# 3. Audit all available GEO sample-characteristic keys.
#    This is used to prevent silently ignoring a hidden covariate.
# ------------------------------------------------------------
function Get-D2CCharacteristicCoverage {
    param(
        [string]$SoftPath,
        [string]$Modality
    )

    $text = Get-D2CGzipText $SoftPath
    $lines = @($text -split "`r?`n")

    $sampleCount = 0
    $currentGsm = ''
    $perSample = @{}
    $allKeys = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($line in $lines) {
        if ($line -match '^\^SAMPLE = (?<gsm>GSM\d+)\s*$') {
            $currentGsm = $Matches['gsm'].ToUpperInvariant()
            $sampleCount++
            if (-not $perSample.ContainsKey($currentGsm)) {
                $perSample[$currentGsm] = @{}
            }
            continue
        }

        if ([string]::IsNullOrWhiteSpace($currentGsm)) { continue }

        if ($line -match '^!Sample_characteristics_ch1 = (?<v>.*)$') {
            $v = $Matches['v'].Trim()
            $ix = $v.IndexOf(':')

            if ($ix -gt 0) {
                $key = $v.Substring(0,$ix).Trim().ToLowerInvariant()
                $value = $v.Substring($ix+1).Trim()

                [void]$allKeys.Add($key)

                if (-not $perSample[$currentGsm].ContainsKey($key)) {
                    $perSample[$currentGsm][$key] = New-Object 'System.Collections.Generic.List[string]'
                }

                [void]$perSample[$currentGsm][$key].Add($value)
            }
        }
    }

    if ($sampleCount -ne 72) {
        throw ('SOFT_SAMPLE_COUNT_CHANGED modality={0} observed={1}' -f $Modality,$sampleCount)
    }

    $rows = New-Object 'System.Collections.Generic.List[object]'

    foreach ($key in @($allKeys | Sort-Object)) {
        $present = 0
        $values = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

        foreach ($gsm in $perSample.Keys) {
            if ($perSample[$gsm].ContainsKey($key)) {
                $present++
                foreach ($value in $perSample[$gsm][$key]) {
                    [void]$values.Add([string]$value)
                }
            }
        }

        [void]$rows.Add([pscustomobject]@{
            modality=$Modality
            characteristic_key=$key
            samples_present=$present
            samples_missing=(72-$present)
            unique_value_count=$values.Count
            unique_values=((@($values | Sort-Object)) -join ' | ')
        })
    }

    $resultRows = [object[]]$rows.ToArray()
    return $resultRows
}

$mrnaCov = @(Get-D2CCharacteristicCoverage -SoftPath $MrnaSoft -Modality 'mRNA')
$mirnaCov = @(Get-D2CCharacteristicCoverage -SoftPath $MirnaSoft -Modality 'miRNA')
$covariateRows = @($mrnaCov + $mirnaCov)

Write-Host ('MRNA_CHARACTERISTIC_ROWS={0}' -f $mrnaCov.Count)
Write-Host ('MIRNA_CHARACTERISTIC_ROWS={0}' -f $mirnaCov.Count)
Write-Host ('TOTAL_CHARACTERISTIC_ROWS={0}' -f $covariateRows.Count)

$covariateRows |
    Sort-Object modality,characteristic_key |
    Export-Csv -LiteralPath $CovariateCsv -NoTypeInformation -Encoding UTF8

# Require the known three characteristic fields to be complete.
foreach ($modality in @('mRNA','miRNA')) {
    foreach ($key in @('tissue','cell type','disease state')) {
        $row = @($covariateRows | Where-Object {
            $_.modality -eq $modality -and $_.characteristic_key -eq $key
        })

        if ($row.Count -ne 1 -or [Int64]$row[0].samples_present -ne 72) {
            throw ('EXPECTED_CHARACTERISTIC_NOT_COMPLETE modality={0} key={1}' -f $modality,$key)
        }
    }
}

$knownKeys = @('tissue','cell type','disease state')
$extraCharacteristics = @($covariateRows | Where-Object {
    $_.characteristic_key -notin $knownKeys
})

if ($extraCharacteristics.Count -gt 0) {
    $extraCharacteristics |
        Export-Csv -LiteralPath (Join-Path $RunDir 'D2C_UNEXPECTED_ADDITIONAL_GEO_CHARACTERISTICS.csv') -NoTypeInformation -Encoding UTF8

    throw ('UNEXPECTED_ADDITIONAL_GEO_CHARACTERISTIC_KEYS={0}' -f $extraCharacteristics.Count)
}

# Tissue and cell type should be technically constant and therefore not useful covariates.
foreach ($modality in @('mRNA','miRNA')) {
    foreach ($key in @('tissue','cell type')) {
        $row = @($covariateRows | Where-Object {
            $_.modality -eq $modality -and $_.characteristic_key -eq $key
        })[0]

        if ([Int64]$row.unique_value_count -ne 1) {
            throw ('TECHNICAL_CHARACTERISTIC_NOT_CONSTANT modality={0} key={1} values={2}' -f `
                $modality,$key,$row.unique_value_count)
        }
    }
}

Write-Host 'GEO_CHARACTERISTIC_KEYS=tissue|cell type|disease state'
Write-Host 'ADDITIONAL_SAMPLE_LEVEL_COVARIATES_AVAILABLE=NO'
Write-Host 'DE_MODEL_METADATA_BASIS=DISEASE_STATE_ONLY'

# ------------------------------------------------------------
# 4. Freeze prospective feature-identity policy
# ------------------------------------------------------------
$strategy = @'
GSE243219 — D2C FROZEN FEATURE-IDENTITY AND STATISTICAL STRATEGY

STATUS
------
This document freezes the prospective strategy before any matrix construction,
aggregation, normalization, filtering, differential-expression analysis, network
construction, or A-CLA execution.

A. COHORT / MODEL METADATA
--------------------------
Biological subjects: 72 paired subjects
Groups:
- COV = COVID-19, n=35
- P   = Sepsis, n=22
- H   = Healthy, n=15

The locally archived GEO family-SOFT files expose the following complete
sample-level characteristics:
- tissue
- cell type
- disease state

Tissue and cell type are constant across samples and therefore are not model
covariates. No age, sex, batch, treatment, or other sample-level adjustment
covariate is present in the GEO family-SOFT metadata.

Prospective DE model basis:
- disease state / group only

Frozen contrasts:
1. PRIMARY_COVID_SIGNAL      = COV vs H
2. SEPSIS_COMPARATOR_SIGNAL  = P vs H
3. COVID_SPECIFICITY         = COV vs P

B. mRNA FEATURE / COUNT POLICY
------------------------------
Raw feature identity:
- gene_symbol

Raw dimensions:
- 26,364 gene symbols x 72 samples

Count semantics:
- featureCounts output created upstream with -M -O --fraction
- fractional values occur in all 72 samples
- 355,532 fractional values are present

Frozen policy:
- preserve the exact fractional mRNA counts
- do NOT round counts
- do NOT coerce to integer
- do NOT silently substitute DESeq2/PyDESeq2 as the primary DE engine
- retain the original count scale

Reason:
The fractional observations are a direct consequence of the upstream counting
policy and are not file-format noise.

C. miRNA RAW FEATURE POLICY
---------------------------
Raw row identity:
- pre-miRNA | MIMAT | mature-miRNA

Raw dimensions:
- 2,886 raw annotation rows x 72 samples

The first-column pre-miRNA value is NOT a unique feature key.
The complete three-column annotation tuple is unique and identical across all
samples.

D. miRNA BIOLOGICAL / REGULATORY IDENTITY POLICY
------------------------------------------------
Primary regulatory identity:
- MIMAT | mature-miRNA

Observed:
- 2,656 unique mature regulatory identities
- 166 regulatory identities map to multiple precursor rows
- no MIMAT-to-multiple-mature-name conflicts
- no mature-name-to-multiple-MIMAT conflicts

PRIMARY CONSOLIDATION RULE:
For each sample and each MIMAT|mature-miRNA regulatory identity:
- if represented by one precursor row: retain that count
- if represented by multiple precursor rows: use the MEDIAN precursor-row count

Rationale:
- precursor rows are not independent regulatory miRNAs
- summing can multiply a mature signal represented in several precursor contexts
- median prevents artificial precursor-count multiplication
- median is robust when one precursor-specific count differs strongly
- this rule is fixed prospectively before matrix construction

SENSITIVITY CONSOLIDATION RULE:
- MAXIMUM precursor-row count for repeated regulatory identities

This sensitivity representation is not the primary analysis. It will be used
only to assess whether conclusions involving repeated mature identities are
sensitive to the consolidation rule.

PROHIBITED:
- SUM across repeated precursor rows
- treating repeated precursor rows as independent mature regulatory nodes
- selecting one arbitrary precursor row
- changing the primary consolidation rule after seeing DE results

Note:
Median consolidation can yield non-integer values even though the original
miRNA counts are integer-valued. This is acceptable for the planned
fractional-count-compatible statistical family, subject to local implementation
preflight.

E. DIFFERENTIAL-EXPRESSION STATISTICAL FAMILY
---------------------------------------------
Primary statistical family:
- edgeR-style negative-binomial quasi-likelihood framework

Implementation target:
- Python / InMoose edgepy

Reason:
- the mRNA data contain genuine fractional counts
- current edgeR methodology supports fractional counts without requiring
  integer rounding when values remain on a count-like scale
- InMoose provides a Python port of edgeR differential-expression functions,
  including GLM and quasi-likelihood functions

Target testing framework:
- group-only design
- quasi-likelihood GLM
- Benjamini-Hochberg FDR control
- three prospectively frozen contrasts listed above

Normalization target:
- TMM-style effective library-size normalization

IMPORTANT IMPLEMENTATION GATE:
The scientific strategy is frozen here, but the local Python implementation
has NOT yet been authorized.

Before any real matrix or DE execution, the next phase must verify:
1. exact Python and InMoose versions in a clean project environment
2. that InMoose edgepy preserves fractional input counts without implicit cast
3. that quasi-likelihood fitting/testing succeeds on a synthetic fractional fixture
4. how TMM normalization factors will be calculated in the Python-only workflow
5. that no normalization implementation silently rounds counts

If those gates fail:
- do NOT round the biological count matrices as a fallback
- do NOT silently switch methods
- stop and redesign the implementation layer

F. FILTERING / QC POLICY
------------------------
No expression-filter threshold is frozen in D2C.
Filtering must be designed prospectively from the actual library-size and
expression distributions in the later QC/filtering phase.

Old GSE179850/GSE182152 exclusion or filtering thresholds are prohibited.

G. CURRENT AUTHORIZATION
------------------------
FEATURE_IDENTITY_STRATEGY_FROZEN=YES
DE_STATISTICAL_FAMILY_FROZEN=YES
MIRNA_PRIMARY_CONSOLIDATION_FROZEN=YES

MATRIX_CONSTRUCTION_AUTHORIZED=NO
MIRNA_AGGREGATION_EXECUTED=NO
MRNA_ROUNDING_AUTHORIZED=NO
NORMALIZATION_AUTHORIZED=NO
FILTERING_AUTHORIZED=NO
DE_AUTHORIZED=NO
NETWORK_AUTHORIZED=NO
ACLA_AUTHORIZED=NO

NEXT:
D2D — clean Python environment + fractional-count / edgepy / normalization capability preflight.
'@

$strategy | Set-Content -LiteralPath $StrategyTxt -Encoding UTF8

# ------------------------------------------------------------
# 5. Machine-readable decision registry
# ------------------------------------------------------------
$decisionRows = @(
    [pscustomobject]@{domain='cohort';key='PRIMARY_CONTRAST';value='COV_vs_H';status='FROZEN'},
    [pscustomobject]@{domain='cohort';key='SEPSIS_COMPARATOR_CONTRAST';value='P_vs_H';status='FROZEN'},
    [pscustomobject]@{domain='cohort';key='COVID_SPECIFICITY_CONTRAST';value='COV_vs_P';status='FROZEN'},
    [pscustomobject]@{domain='metadata';key='ADDITIONAL_SAMPLE_LEVEL_COVARIATES_AVAILABLE';value='NO';status='CERTIFIED'},
    [pscustomobject]@{domain='metadata';key='DE_MODEL_METADATA_BASIS';value='DISEASE_STATE_ONLY';status='FROZEN'},

    [pscustomobject]@{domain='mRNA';key='RAW_FEATURE_KEY';value='gene_symbol';status='FROZEN'},
    [pscustomobject]@{domain='mRNA';key='FRACTIONAL_COUNTS_PRESENT';value='YES';status='CERTIFIED'},
    [pscustomobject]@{domain='mRNA';key='FRACTIONAL_COUNT_CELL_PERCENT';value=[string]$MrnaFractionalPct;status='CERTIFIED'},
    [pscustomobject]@{domain='mRNA';key='ROUNDING_POLICY';value='PROHIBITED';status='FROZEN'},

    [pscustomobject]@{domain='miRNA';key='RAW_FEATURE_KEY';value='pre-miRNA|MIMAT|mature-miRNA';status='FROZEN'},
    [pscustomobject]@{domain='miRNA';key='REGULATORY_IDENTITY_KEY';value='MIMAT|mature-miRNA';status='FROZEN'},
    [pscustomobject]@{domain='miRNA';key='REPEATED_REGULATORY_IDENTITY_PERCENT';value=[string]$MirnaRepeatedIdentityPct;status='CERTIFIED'},
    [pscustomobject]@{domain='miRNA';key='PRIMARY_CONSOLIDATION';value='MEDIAN_ACROSS_PRECURSOR_ROWS_PER_SAMPLE';status='FROZEN'},
    [pscustomobject]@{domain='miRNA';key='SENSITIVITY_CONSOLIDATION';value='MAX_ACROSS_PRECURSOR_ROWS_PER_SAMPLE';status='FROZEN'},
    [pscustomobject]@{domain='miRNA';key='SUM_CONSOLIDATION';value='PROHIBITED';status='FROZEN'},
    [pscustomobject]@{domain='miRNA';key='PRECURSOR_ROWS_AS_INDEPENDENT_REGULATORY_NODES';value='PROHIBITED';status='FROZEN'},

    [pscustomobject]@{domain='DE';key='STATISTICAL_FAMILY';value='EDGER_STYLE_NEGATIVE_BINOMIAL_QUASI_LIKELIHOOD';status='FROZEN'},
    [pscustomobject]@{domain='DE';key='IMPLEMENTATION_TARGET';value='PYTHON_INMOOSE_EDGEPY';status='TARGET_FROZEN_CAPABILITY_UNVERIFIED'},
    [pscustomobject]@{domain='DE';key='NORMALIZATION_TARGET';value='TMM_STYLE_EFFECTIVE_LIBRARY_SIZE';status='TARGET_FROZEN_CAPABILITY_UNVERIFIED'},
    [pscustomobject]@{domain='DE';key='MULTIPLE_TEST_CORRECTION';value='BENJAMINI_HOCHBERG_FDR';status='FROZEN'},
    [pscustomobject]@{domain='DE';key='DESEQ2_PYDESEQ2_PRIMARY_ENGINE';value='NO';status='FROZEN'},

    [pscustomobject]@{domain='authorization';key='MATRIX_CONSTRUCTION';value='NO';status='BLOCKED'},
    [pscustomobject]@{domain='authorization';key='FEATURE_AGGREGATION_EXECUTED';value='NO';status='NOT_EXECUTED'},
    [pscustomobject]@{domain='authorization';key='NORMALIZATION';value='NO';status='BLOCKED'},
    [pscustomobject]@{domain='authorization';key='DE';value='NO';status='BLOCKED'},
    [pscustomobject]@{domain='authorization';key='NEXT_PHASE';value='D2D_PYTHON_EDGEPY_FRACTIONAL_COUNT_CAPABILITY_PREFLIGHT';status='AUTHORIZED'}
)

$decisionRows |
    Export-Csv -LiteralPath $DecisionCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 6. Hash outputs
# ------------------------------------------------------------
$outFiles = @($CovariateCsv,$StrategyTxt,$DecisionCsv)
$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    $item = Get-Item -LiteralPath $p
    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D2CSHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 7. Summary
# ------------------------------------------------------------
@(
    '=== GSE243219 PHASE D2C SUMMARY ===',
    'PHASE_D2C_V2_STATUS=PASS',
    'MODE=DESIGN_FREEZE_AND_METADATA_AUDIT_ONLY',
    'MATRIX_CONSTRUCTION_EXECUTED=NO',
    'FEATURE_AGGREGATION_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'NORMALIZATION_EXECUTED=NO',
    'FILTERING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'D2B_V2_CERTIFICATION_GATE=PASS',
    'D2B_OUTPUTS_RECERTIFIED=8/8',
    ('MRNA_FRACTIONAL_COUNT_CELL_PERCENT={0}' -f $MrnaFractionalPct),
    ('MIRNA_REPEATED_REGULATORY_IDENTITY_PERCENT={0}' -f $MirnaRepeatedIdentityPct),
    ('MIRNA_REPEATED_IDENTITY_GROUPS_IDENTICAL_PERCENT={0}' -f $MirnaRepeatedIdenticalPct),
    ('MIRNA_REPEATED_IDENTITY_GROUPS_DIFFERENT_PERCENT={0}' -f $MirnaRepeatedDifferentPct),
    'GEO_CHARACTERISTIC_KEYS=tissue|cell type|disease state',
    'ADDITIONAL_SAMPLE_LEVEL_COVARIATES_AVAILABLE=NO',
    'DE_MODEL_METADATA_BASIS=DISEASE_STATE_ONLY',
    'PRIMARY_CONTRAST=COV_vs_H',
    'SEPSIS_COMPARATOR_CONTRAST=P_vs_H',
    'COVID_SPECIFICITY_CONTRAST=COV_vs_P',
    'MRNA_RAW_FEATURE_KEY=gene_symbol',
    'MRNA_FRACTIONAL_COUNTS_PRESERVED=YES',
    'MRNA_COUNT_ROUNDING_POLICY=PROHIBITED',
    'MIRNA_RAW_FEATURE_KEY=pre-miRNA|MIMAT|mature-miRNA',
    'MIRNA_REGULATORY_IDENTITY_KEY=MIMAT|mature-miRNA',
    'MIRNA_PRIMARY_CONSOLIDATION=MEDIAN_ACROSS_PRECURSOR_ROWS_PER_SAMPLE',
    'MIRNA_SENSITIVITY_CONSOLIDATION=MAX_ACROSS_PRECURSOR_ROWS_PER_SAMPLE',
    'MIRNA_SUM_CONSOLIDATION=PROHIBITED',
    'MIRNA_PRECURSOR_ROWS_AS_INDEPENDENT_REGULATORY_NODES=PROHIBITED',
    'PRIMARY_DE_STATISTICAL_FAMILY=EDGER_STYLE_NEGATIVE_BINOMIAL_QUASI_LIKELIHOOD',
    'DE_IMPLEMENTATION_TARGET=PYTHON_INMOOSE_EDGEPY',
    'NORMALIZATION_TARGET=TMM_STYLE_EFFECTIVE_LIBRARY_SIZE',
    'DESEQ2_PYDESEQ2_PRIMARY_ENGINE=NO',
    'LOCAL_FRACTIONAL_COUNT_ENGINE_CAPABILITY_VERIFIED=NO',
    'LOCAL_TMM_IMPLEMENTATION_CAPABILITY_VERIFIED=NO',
    'FEATURE_IDENTITY_STRATEGY_FROZEN=YES',
    'DE_STATISTICAL_FAMILY_FROZEN=YES',
    'MIRNA_PRIMARY_CONSOLIDATION_FROZEN=YES',
    'READY_FOR_MATRIX_CONSTRUCTION=NO',
    'READY_FOR_NORMALIZATION=NO',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'READY_FOR_PHASE_D2D_CAPABILITY_PREFLIGHT=YES',
    'NEXT_PHASE=D2D_PYTHON_EDGEPY_FRACTIONAL_COUNT_CAPABILITY_PREFLIGHT',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D2C_GEO_CHARACTERISTIC_COVERAGE={0}' -f $CovariateCsv)
Write-Host ('D2C_FROZEN_STRATEGY={0}' -f $StrategyTxt)
Write-Host ('D2C_METHOD_DECISION_REGISTRY={0}' -f $DecisionCsv)
Write-Host ('D2C_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D2C_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D2C_V2=PASS'
Write-Host 'STOP=YES'
