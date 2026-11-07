$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219 NEW PROJECT
# PHASE D2 — INPUT STRUCTURE, COUNT-SEMANTICS, METADATA & PAIRING AUDIT
#
# READ/AUDIT ONLY.
#
# Authorized:
#   - Re-certify D1 downloads/extracted files
#   - Parse all 72 mRNA and 72 miRNA count files
#   - Audit count numeric semantics
#   - Parse GEO family-SOFT sample metadata
#   - Certify COV/P/H disease-state mapping
#   - Certify 72 cross-modality subject pairs
#   - Characterize feature-set consistency
#
# NOT authorized:
#   - Build a combined expression/count matrix
#   - Fill missing features with zero
#   - Round fractional counts
#   - Normalize
#   - Filter/exclude samples/features
#   - Differential expression
#   - Network construction
#   - A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D1Root = Join-Path $Project '01_PROCESSED_DATA_ACQUISITION'
$D1Audit = Join-Path $D1Root 'audit'
$D1Downloads = Join-Path $D1Root 'downloads'
$D1Extracted = Join-Path $D1Root 'extracted'

$D2Root = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING'
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D2Root ('D2_AUDIT_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D2_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$D1Status = Join-Path $D1Audit 'D1_ACQUISITION_STATUS.txt'
$D1DownloadManifest = Join-Path $D1Audit 'D1_DOWNLOAD_SHA256_MANIFEST.csv'
$D1MrnaInventory = Join-Path $D1Audit 'D1_GSE243217_MRNA_FILE_INVENTORY.csv'
$D1MirnaInventory = Join-Path $D1Audit 'D1_GSE243218_MIRNA_FILE_INVENTORY.csv'
$D1SubjectComparison = Join-Path $D1Audit 'D1_CROSS_MODALITY_FILENAME_SUBJECT_COMPARISON.csv'
$D1SoftSummary = Join-Path $D1Audit 'D1_SOFT_METADATA_SUMMARY.csv'

$MrnaSoft = Join-Path $D1Downloads 'GSE243217_family.soft.gz'
$MirnaSoft = Join-Path $D1Downloads 'GSE243218_family.soft.gz'

$SampleAuditCsv = Join-Path $RunDir 'D2_SAMPLE_COUNT_STRUCTURE_AUDIT.csv'
$PairingCsv = Join-Path $RunDir 'D2_CERTIFIED_CROSS_MODALITY_PAIRING.csv'
$MetadataCsv = Join-Path $RunDir 'D2_GEO_SAMPLE_METADATA.csv'
$FeatureSummaryCsv = Join-Path $RunDir 'D2_FEATURE_SET_SUMMARY.csv'
$CountSummaryCsv = Join-Path $RunDir 'D2_COUNT_SEMANTICS_SUMMARY.csv'
$StatusTxt = Join-Path $RunDir 'D2_STATUS.txt'
$OutputManifest = Join-Path $RunDir 'D2_OUTPUT_SHA256_MANIFEST.csv'
$ReportSummary = Join-Path $ReportDir 'PHASE_D2_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D2-V2 — INPUT STRUCTURE, COUNT SEMANTICS, METADATA & PAIRING AUDIT ==='
Write-Host 'MODE=READ_AND_AUDIT_ONLY'
Write-Host 'MATRIX_CONSTRUCTION_EXECUTED=NO'
Write-Host 'ZERO_FILL_EXECUTED=NO'
Write-Host 'COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'NORMALIZATION_EXECUTED=NO'
Write-Host 'FILTERING_EXECUTED=NO'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'DE_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('PROJECT_ROOT={0}' -f $Project)
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @(
    $D1Status,$D1DownloadManifest,$D1MrnaInventory,$D1MirnaInventory,
    $D1SubjectComparison,$D1SoftSummary,$MrnaSoft,$MirnaSoft
)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D1_INPUT_MISSING={0}' -f $p)
    }
}

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
function Get-D2SHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-D2GZipText {
    param([string]$Path)

    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $gz = New-Object System.IO.Compression.GZipStream(
            $fs,
            [System.IO.Compression.CompressionMode]::Decompress
        )
        try {
            $sr = New-Object System.IO.StreamReader($gz)
            try {
                return $sr.ReadToEnd()
            }
            finally {
                $sr.Dispose()
            }
        }
        finally {
            $gz.Dispose()
        }
    }
    finally {
        $fs.Dispose()
    }
}

function Get-D2StringSHA256 {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-','').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Normalize-DiseaseState {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 'UNKNOWN'
    }

    $x = $Value.Trim()

    if ($x -match '(?i)\bsepsis\b') {
        return 'SEPSIS'
    }
    if ($x -match '(?i)covid[\s-]*19|sars[\s-]*cov[\s-]*2') {
        return 'COVID-19'
    }
    if ($x -match '(?i)\bhealthy\b|\bhealthy subject\b|\bhealthy control\b|^control$|^normal$|\buninfected\b') {
        return 'HEALTHY'
    }

    return ('OTHER:' + $x)
}

function Get-ExpectedDiseaseFromSubject {
    param([string]$SubjectId)

    if ($SubjectId -match '(?i)^P\d+$') { return 'SEPSIS' }
    if ($SubjectId -match '(?i)^COV\d+$') { return 'COVID-19' }
    if ($SubjectId -match '(?i)^H\d+$') { return 'HEALTHY' }

    return 'UNKNOWN'
}

function Test-D2SeriesDesignCohort {
    param(
        [string]$Path,
        [string]$Modality
    )

    $text = Get-D2GZipText $Path

    $has22Sepsis = $text -match '(?is)\b22\s+sepsis\s+patients\b'
    $has35Covid = $text -match '(?is)\b35\s+COVID-19\s+patients\b'
    $has15Healthy = $text -match '(?is)\b15\s+healthy\s+subjects\b'

    return [pscustomobject]@{
        modality=$Modality
        has_22_sepsis=$(if ($has22Sepsis) {'YES'} else {'NO'})
        has_35_covid=$(if ($has35Covid) {'YES'} else {'NO'})
        has_15_healthy=$(if ($has15Healthy) {'YES'} else {'NO'})
        cohort_design_certified=$(if ($has22Sepsis -and $has35Covid -and $has15Healthy) {'YES'} else {'NO'})
    }
}

function Parse-D2SoftSamples {
    param(
        [string]$Path,
        [string]$Modality
    )

    $text = Get-D2GZipText $Path
    $lines = $text -split "`r?`n"

    $records = @()
    $current = $null

    function Flush-CurrentRecord {
        param($Rec,[ref]$Target)

        if ($null -eq $Rec) { return }

        $title = [string]$Rec.title
        $subject = ''

        $m = [regex]::Match(
            $title,
            '^(?<subject>(?:COV|P|H)\d+)\s*(?:\(|$)',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if ($m.Success) {
            $subject = $m.Groups['subject'].Value.ToUpperInvariant()
        }

        $tissue = ''
        if ($Rec.characteristics.ContainsKey('tissue')) {
            $tissue = [string]$Rec.characteristics['tissue']
        }

        $cellType = ''
        if ($Rec.characteristics.ContainsKey('cell type')) {
            $cellType = [string]$Rec.characteristics['cell type']
        }

        # Phenotype extraction is deliberately flexible across GEO characteristic
        # key naming, but only recognized biological values are accepted.
        $phenotypeRaw = ''
        $phenotypeKey = ''
        $phenotypeNorm = 'UNKNOWN'

        $priorityKeys = @(
            'disease state',
            'disease status',
            'disease',
            'condition',
            'phenotype',
            'diagnosis',
            'clinical group',
            'group'
        )

        foreach ($k in $priorityKeys) {
            if ($Rec.characteristics.ContainsKey($k)) {
                $candidate = [string]$Rec.characteristics[$k]
                $norm = Normalize-DiseaseState $candidate

                if ($norm -in @('SEPSIS','COVID-19','HEALTHY')) {
                    $phenotypeRaw = $candidate
                    $phenotypeKey = $k
                    $phenotypeNorm = $norm
                    break
                }
            }
        }

        # If no standard phenotype key exists, scan characteristic values for an
        # explicit recognizable phenotype. This remains sample-level evidence.
        if ($phenotypeNorm -eq 'UNKNOWN') {
            foreach ($k in @($Rec.characteristics.Keys | Sort-Object)) {
                $candidate = [string]$Rec.characteristics[$k]
                $norm = Normalize-DiseaseState $candidate

                if ($norm -in @('SEPSIS','COVID-19','HEALTHY')) {
                    $phenotypeRaw = $candidate
                    $phenotypeKey = [string]$k
                    $phenotypeNorm = $norm
                    break
                }
            }
        }

        $characteristicPairs = @()
        foreach ($k in @($Rec.characteristics.Keys | Sort-Object)) {
            $characteristicPairs += ('{0}={1}' -f $k,[string]$Rec.characteristics[$k])
        }

        $sourceName = [string]$Rec.source_name

        $Target.Value += [pscustomobject]@{
            modality=$Modality
            GSM=[string]$Rec.GSM
            title=$title
            subject_id=$subject
            group_prefix=$(if ($subject -match '^COV') {'COV'} elseif ($subject -match '^P') {'P'} elseif ($subject -match '^H') {'H'} else {'UNKNOWN'})
            disease_state_raw=$phenotypeRaw
            disease_state_normalized=$phenotypeNorm
            phenotype_evidence_key=$phenotypeKey
            phenotype_evidence_source=$(if ($phenotypeNorm -in @('SEPSIS','COVID-19','HEALTHY')) {'SAMPLE_CHARACTERISTIC'} else {'NONE'})
            phenotype_explicit=$(if ($phenotypeNorm -in @('SEPSIS','COVID-19','HEALTHY')) {'YES'} else {'NO'})
            expected_disease_from_subject=(Get-ExpectedDiseaseFromSubject $subject)
            tissue=$tissue
            cell_type=$cellType
            source_name=$sourceName
            all_characteristics=($characteristicPairs -join ' || ')
        }
    }

    foreach ($line in $lines) {
        if ($line -match '^\^SAMPLE = (?<gsm>GSM\d+)\s*$') {
            Flush-CurrentRecord -Rec $current -Target ([ref]$records)

            $current = @{
                GSM=$Matches['gsm'].ToUpperInvariant()
                title=''
                source_name=''
                characteristics=@{}
            }

            continue
        }

        if ($null -eq $current) { continue }

        if ($line -match '^!Sample_title = (?<v>.*)$') {
            $current.title = $Matches['v'].Trim()
            continue
        }

        if ($line -match '^!Sample_source_name_ch1 = (?<v>.*)$') {
            $current.source_name = $Matches['v'].Trim()
            continue
        }

        if ($line -match '^!Sample_characteristics_ch1 = (?<v>.*)$') {
            $v = $Matches['v'].Trim()
            $ix = $v.IndexOf(':')

            if ($ix -gt 0) {
                $key = $v.Substring(0,$ix).Trim().ToLowerInvariant()
                $value = $v.Substring($ix+1).Trim()

                if (-not $current.characteristics.ContainsKey($key)) {
                    $current.characteristics[$key] = $value
                }
                else {
                    $current.characteristics[$key] = [string]$current.characteristics[$key] + ' | ' + $value
                }
            }

            continue
        }
    }

    Flush-CurrentRecord -Rec $current -Target ([ref]$records)

    return @($records)
}

function Get-FeatureIdType {
    param([string[]]$Ids)

    if ($Ids.Count -eq 0) {
        return 'UNKNOWN'
    }

    $probe = @($Ids | Select-Object -First ([math]::Min(1000,$Ids.Count)))
    $n = $probe.Count

    $ensembl = @($probe | Where-Object { $_ -match '^ENSG\d+(?:\.\d+)?$' }).Count
    $mirna = @($probe | Where-Object { $_ -match '(?i)^hsa-(?:miR|mir|let)-' }).Count
    $numeric = @($probe | Where-Object { $_ -match '^\d+$' }).Count

    if (($ensembl / [double]$n) -ge 0.80) { return 'ENSEMBL_GENE_ID' }
    if (($mirna / [double]$n) -ge 0.80) { return 'MIRBASE_STYLE_HUMAN_MIRNA_ID' }
    if (($numeric / [double]$n) -ge 0.80) { return 'NUMERIC_ID' }

    return 'OTHER_OR_MIXED'
}

function Audit-D2CountFile {
    param(
        [string]$Path,
        [string]$Modality,
        [string]$GSM,
        [string]$SubjectId,
        [string]$GroupPrefix
    )

    $text = Get-D2GZipText $Path
    $lines = $text -split "`r?`n"

    $commentLines = 0
    $blankLines = 0
    $headerPresent = $false
    $headerText = ''
    $expectedColumns = $null
    $dataRows = 0
    $nonNumericCounts = 0
    $missingCounts = 0
    $negativeCounts = 0
    $nonFiniteCounts = 0
    $fractionalCounts = 0
    $zeroCounts = 0
    [double]$countSum = 0
    [double]$minCount = [double]::PositiveInfinity
    [double]$maxCount = [double]::NegativeInfinity
    $columnCountMismatches = 0
    $emptyFeatureIds = 0
    $duplicateFeatureIds = 0

    $featureIds = New-Object 'System.Collections.Generic.List[string]'
    $featureSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

    $firstNonCommentSeen = $false

    foreach ($lineRaw in $lines) {
        $line = [string]$lineRaw

        if ([string]::IsNullOrWhiteSpace($line)) {
            $blankLines++
            continue
        }

        if ($line.StartsWith('#')) {
            $commentLines++
            continue
        }

        $fields = $line -split "`t",-1

        if (-not $firstNonCommentSeen) {
            $firstNonCommentSeen = $true

            $last = $fields[$fields.Count-1].Trim()
            [double]$testValue = 0

            $isNumeric = [double]::TryParse(
                $last,
                [System.Globalization.NumberStyles]::Float,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$testValue
            )

            if (-not $isNumeric) {
                $headerPresent = $true
                $headerText = ($fields -join '|')
                $expectedColumns = $fields.Count
                continue
            }
        }

        if ($null -eq $expectedColumns) {
            $expectedColumns = $fields.Count
        }

        if ($fields.Count -ne $expectedColumns) {
            $columnCountMismatches++
        }

        $featureId = $fields[0].Trim()

        if ([string]::IsNullOrWhiteSpace($featureId)) {
            $emptyFeatureIds++
        }
        else {
            $featureIds.Add($featureId)
            if (-not $featureSet.Add($featureId)) {
                $duplicateFeatureIds++
            }
        }

        $countText = $fields[$fields.Count-1].Trim()

        if ([string]::IsNullOrWhiteSpace($countText)) {
            $missingCounts++
            $dataRows++
            continue
        }

        [double]$countValue = 0
        $ok = [double]::TryParse(
            $countText,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$countValue
        )

        if (-not $ok) {
            $nonNumericCounts++
            $dataRows++
            continue
        }

        if ([double]::IsNaN($countValue) -or [double]::IsInfinity($countValue)) {
            $nonFiniteCounts++
            $dataRows++
            continue
        }

        if ($countValue -lt 0) {
            $negativeCounts++
        }

        if ([math]::Abs($countValue - [math]::Round($countValue)) -gt 1e-9) {
            $fractionalCounts++
        }

        if ([math]::Abs($countValue) -le 1e-15) {
            $zeroCounts++
        }

        $countSum += $countValue
        if ($countValue -lt $minCount) { $minCount = $countValue }
        if ($countValue -gt $maxCount) { $maxCount = $countValue }

        $dataRows++
    }

    if ($dataRows -eq 0) {
        throw ('NO_DATA_ROWS modality={0} file={1}' -f $Modality,$Path)
    }

    if ($featureIds.Count -ne $dataRows) {
        # Any empty feature IDs would cause this.
        if ($emptyFeatureIds -eq 0) {
            throw ('FEATURE_ID_ROW_ACCOUNTING_ERROR modality={0} file={1}' -f $Modality,$Path)
        }
    }

    $featureSequenceHash = Get-D2StringSHA256 ($featureIds -join "`n")
    $sortedIds = @($featureIds | Sort-Object -Unique)
    $featureSetHash = Get-D2StringSHA256 ($sortedIds -join "`n")

    if ([double]::IsPositiveInfinity($minCount)) { $minCount = [double]::NaN }
    if ([double]::IsNegativeInfinity($maxCount)) { $maxCount = [double]::NaN }

    return [pscustomobject]@{
        modality=$Modality
        GSM=$GSM
        subject_id=$SubjectId
        group_prefix=$GroupPrefix
        file_path=$Path
        compressed_SHA256=(Get-D2SHA256 $Path)
        header_present=$(if ($headerPresent) {'YES'} else {'NO'})
        header_text=$headerText
        column_count=$expectedColumns
        data_rows=$dataRows
        unique_feature_ids=$featureSet.Count
        empty_feature_ids=$emptyFeatureIds
        duplicate_feature_ids=$duplicateFeatureIds
        column_count_mismatches=$columnCountMismatches
        missing_count_values=$missingCounts
        nonnumeric_count_values=$nonNumericCounts
        nonfinite_count_values=$nonFiniteCounts
        negative_count_values=$negativeCounts
        fractional_count_values=$fractionalCounts
        zero_count_values=$zeroCounts
        zero_fraction=[math]::Round($zeroCounts/[double]$dataRows,6)
        count_sum=[math]::Round($countSum,6)
        min_count=$minCount
        max_count=$maxCount
        feature_id_type=(Get-FeatureIdType $sortedIds)
        feature_sequence_sha256=$featureSequenceHash
        feature_set_sha256=$featureSetHash
        _feature_ids=$sortedIds
    }
}

# ------------------------------------------------------------
# 1. D1 authorization and integrity chain
# ------------------------------------------------------------
$d1 = Get-Content -LiteralPath $D1Status -Raw

foreach ($tok in @(
    'GSE243219_PHASE_D1_STATUS',
    'GEO_PROCESSED_DATA_DOWNLOADED=YES',
    'RAW_FASTQ_DOWNLOADED=NO',
    'MRNA_EXTRACTED_FILES=72',
    'MIRNA_EXTRACTED_FILES=72',
    'MRNA_GZIP_INTEGRITY_PASS=72',
    'MIRNA_GZIP_INTEGRITY_PASS=72',
    'FILENAME_SUBJECT_SET_MATCH=YES',
    'FILENAME_PAIRABLE_SUBJECTS=72',
    'READY_FOR_PHASE_D2_INPUT_AUDIT_AND_PAIRING=YES'
)) {
    if ($d1 -notmatch [regex]::Escape($tok)) {
        throw ('D1_AUTHORIZATION_TOKEN_MISSING={0}' -f $tok)
    }
}

Write-Host 'D1_AUTHORIZATION_GATE=PASS'

# Re-certify 4 downloaded files against D1 download manifest.
$downloadManifest = @(Import-Csv -LiteralPath $D1DownloadManifest)
if ($downloadManifest.Count -ne 4) {
    throw ('D1_DOWNLOAD_MANIFEST_ROW_COUNT_CHANGED={0}' -f $downloadManifest.Count)
}

foreach ($r in $downloadManifest) {
    if (-not (Test-Path -LiteralPath $r.local_path -PathType Leaf)) {
        throw ('D1_DOWNLOAD_MISSING={0}' -f $r.local_path)
    }

    $item = Get-Item -LiteralPath $r.local_path
    $hash = Get-D2SHA256 $r.local_path

    if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or
        $hash -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D1_DOWNLOAD_HASH_OR_SIZE_CHANGED={0}' -f $r.local_path)
    }
}

Write-Host 'D1_DOWNLOADS_RECERTIFIED=4/4'

$mrnaInv = @(Import-Csv -LiteralPath $D1MrnaInventory)
$mirnaInv = @(Import-Csv -LiteralPath $D1MirnaInventory)

if ($mrnaInv.Count -ne 72) {
    throw ('D1_MRNA_INVENTORY_COUNT_CHANGED={0}' -f $mrnaInv.Count)
}
if ($mirnaInv.Count -ne 72) {
    throw ('D1_MIRNA_INVENTORY_COUNT_CHANGED={0}' -f $mirnaInv.Count)
}

foreach ($r in @($mrnaInv + $mirnaInv)) {
    if (-not (Test-Path -LiteralPath $r.final_path -PathType Leaf)) {
        throw ('D1_EXTRACTED_FILE_MISSING={0}' -f $r.final_path)
    }

    $item = Get-Item -LiteralPath $r.final_path
    $hash = Get-D2SHA256 $r.final_path

    if ([Int64]$item.Length -ne [Int64]$r.compressed_bytes -or
        $hash -ne $r.SHA256.ToLowerInvariant()) {
        throw ('D1_EXTRACTED_FILE_CHANGED={0}' -f $r.final_path)
    }
}

Write-Host 'D1_EXTRACTED_FILES_RECERTIFIED=144/144'

# ------------------------------------------------------------
# 2. Parse authoritative GEO family-SOFT metadata
# ------------------------------------------------------------
$mrnaDesign = Test-D2SeriesDesignCohort -Path $MrnaSoft -Modality 'mRNA'
$mirnaDesign = Test-D2SeriesDesignCohort -Path $MirnaSoft -Modality 'miRNA'

if ($mrnaDesign.cohort_design_certified -ne 'YES' -or
    $mirnaDesign.cohort_design_certified -ne 'YES') {

    @($mrnaDesign,$mirnaDesign) |
        Export-Csv -LiteralPath (Join-Path $RunDir 'FAIL_SERIES_DESIGN_COHORT_CERTIFICATION.csv') -NoTypeInformation -Encoding UTF8

    throw 'SERIES_DESIGN_COHORT_CERTIFICATION_FAILED'
}

Write-Host 'MRNA_SERIES_DESIGN_COHORT=COV35|P22|H15|CERTIFIED=YES'
Write-Host 'MIRNA_SERIES_DESIGN_COHORT=COV35|P22|H15|CERTIFIED=YES'

$mrnaMeta = @(Parse-D2SoftSamples -Path $MrnaSoft -Modality 'mRNA')
$mirnaMeta = @(Parse-D2SoftSamples -Path $MirnaSoft -Modality 'miRNA')

if ($mrnaMeta.Count -ne 72) {
    throw ('MRNA_SOFT_PARSED_SAMPLE_COUNT={0}' -f $mrnaMeta.Count)
}
if ($mirnaMeta.Count -ne 72) {
    throw ('MIRNA_SOFT_PARSED_SAMPLE_COUNT={0}' -f $mirnaMeta.Count)
}

$metadata = @($mrnaMeta + $mirnaMeta)

# Structural validity is distinct from phenotype-field completeness.
$metadataStructuralFailures = @($metadata | Where-Object {
    [string]::IsNullOrWhiteSpace($_.GSM) -or
    [string]::IsNullOrWhiteSpace($_.title) -or
    [string]::IsNullOrWhiteSpace($_.subject_id) -or
    $_.group_prefix -eq 'UNKNOWN'
})

if ($metadataStructuralFailures.Count -gt 0) {
    $metadataStructuralFailures |
        Export-Csv -LiteralPath (Join-Path $RunDir 'FAIL_METADATA_STRUCTURAL_RECORDS.csv') -NoTypeInformation -Encoding UTF8

    throw ('METADATA_STRUCTURAL_FAILURES={0}' -f $metadataStructuralFailures.Count)
}

Write-Host 'METADATA_STRUCTURAL_FAILURES=0'

# Apply a narrowly defined fallback only to H samples when the local family-SOFT
# Series design explicitly certifies 15 healthy subjects in that modality.
# COV and P samples are required to carry explicit sample-level phenotype evidence.
foreach ($row in $metadata) {
    if ($row.disease_state_normalized -eq 'UNKNOWN') {
        $designOK = if ($row.modality -eq 'mRNA') {
            $mrnaDesign.cohort_design_certified -eq 'YES'
        }
        else {
            $mirnaDesign.cohort_design_certified -eq 'YES'
        }

        if ($row.group_prefix -eq 'H' -and $designOK) {
            $row.disease_state_raw = '15 healthy subjects (Series overall design)'
            $row.disease_state_normalized = 'HEALTHY'
            $row.phenotype_evidence_key = 'Series overall design + H sample title'
            $row.phenotype_evidence_source = 'SERIES_DESIGN_PLUS_H_TITLE'
            $row.phenotype_explicit = 'NO'
        }
    }
}

$unresolvedPhenotype = @($metadata | Where-Object {
    $_.disease_state_normalized -notin @('SEPSIS','COVID-19','HEALTHY')
})

if ($unresolvedPhenotype.Count -gt 0) {
    $unresolvedPhenotype |
        Export-Csv -LiteralPath (Join-Path $RunDir 'FAIL_UNRESOLVED_PHENOTYPE_RECORDS.csv') -NoTypeInformation -Encoding UTF8

    throw ('UNRESOLVED_PHENOTYPE_RECORDS={0}' -f $unresolvedPhenotype.Count)
}

# COV and P must remain backed by explicit sample-level evidence.
$nonHealthyFallback = @($metadata | Where-Object {
    $_.group_prefix -in @('COV','P') -and $_.phenotype_explicit -ne 'YES'
})

if ($nonHealthyFallback.Count -gt 0) {
    $nonHealthyFallback |
        Export-Csv -LiteralPath (Join-Path $RunDir 'FAIL_COV_P_WITHOUT_EXPLICIT_PHENOTYPE.csv') -NoTypeInformation -Encoding UTF8

    throw ('COV_P_WITHOUT_EXPLICIT_PHENOTYPE={0}' -f $nonHealthyFallback.Count)
}

$metadataDiseaseMismatches = @($metadata | Where-Object {
    $_.disease_state_normalized -ne $_.expected_disease_from_subject
})

if ($metadataDiseaseMismatches.Count -gt 0) {
    $metadataDiseaseMismatches |
        Export-Csv -LiteralPath (Join-Path $RunDir 'FAIL_METADATA_DISEASE_MISMATCHES.csv') -NoTypeInformation -Encoding UTF8

    throw ('METADATA_DISEASE_STATE_MISMATCHES={0}' -f $metadataDiseaseMismatches.Count)
}

foreach ($x in @(
    [pscustomobject]@{modality='mRNA';rows=$mrnaMeta},
    [pscustomobject]@{modality='miRNA';rows=$mirnaMeta}
)) {
    $cov = @($x.rows | Where-Object group_prefix -eq 'COV').Count
    $p = @($x.rows | Where-Object group_prefix -eq 'P').Count
    $h = @($x.rows | Where-Object group_prefix -eq 'H').Count

    if ($cov -ne 35 -or $p -ne 22 -or $h -ne 15) {
        throw ('SOFT_GROUP_COUNT_MISMATCH modality={0} COV={1} P={2} H={3}' -f $x.modality,$cov,$p,$h)
    }

    $explicit = @($x.rows | Where-Object phenotype_explicit -eq 'YES').Count
    $fallback = @($x.rows | Where-Object phenotype_evidence_source -eq 'SERIES_DESIGN_PLUS_H_TITLE').Count

    Write-Host ('METADATA_DISEASE_COUNTS={0}|COVID19={1}|SEPSIS={2}|HEALTHY={3}|EXPLICIT={4}|SERIES_FALLBACK={5}' -f `
        $x.modality,
        @($x.rows | Where-Object disease_state_normalized -eq 'COVID-19').Count,
        @($x.rows | Where-Object disease_state_normalized -eq 'SEPSIS').Count,
        @($x.rows | Where-Object disease_state_normalized -eq 'HEALTHY').Count,
        $explicit,
        $fallback)
}

$pSepsisCertified = (
    @($metadata | Where-Object group_prefix -eq 'P').Count -eq 44 -and
    @($metadata | Where-Object {
        $_.group_prefix -eq 'P' -and $_.disease_state_normalized -ne 'SEPSIS'
    }).Count -eq 0 -and
    @($metadata | Where-Object {
        $_.group_prefix -ne 'P' -and $_.disease_state_normalized -eq 'SEPSIS'
    }).Count -eq 0
)

$covCovidCertified = (
    @($metadata | Where-Object group_prefix -eq 'COV').Count -eq 70 -and
    @($metadata | Where-Object {
        $_.group_prefix -eq 'COV' -and $_.disease_state_normalized -ne 'COVID-19'
    }).Count -eq 0
)

$hHealthyCertified = (
    @($metadata | Where-Object group_prefix -eq 'H').Count -eq 30 -and
    @($metadata | Where-Object {
        $_.group_prefix -eq 'H' -and $_.disease_state_normalized -ne 'HEALTHY'
    }).Count -eq 0
)

if (-not $pSepsisCertified) {
    throw 'P_LABEL_SEPSIS_MAPPING_CERTIFICATION_FAILED'
}
if (-not $covCovidCertified) {
    throw 'COV_LABEL_COVID19_MAPPING_CERTIFICATION_FAILED'
}
if (-not $hHealthyCertified) {
    throw 'H_LABEL_HEALTHY_MAPPING_CERTIFICATION_FAILED'
}

$explicitPhenotypeCount = @($metadata | Where-Object phenotype_explicit -eq 'YES').Count
$seriesFallbackCount = @($metadata | Where-Object phenotype_evidence_source -eq 'SERIES_DESIGN_PLUS_H_TITLE').Count

Write-Host 'P_LABEL_SEPSIS_MAPPING_CERTIFIED=YES'
Write-Host 'COV_LABEL_COVID19_MAPPING_CERTIFIED=YES'
Write-Host 'H_LABEL_HEALTHY_MAPPING_CERTIFIED=YES'
Write-Host ('PHENOTYPE_EXPLICIT_SAMPLE_RECORDS={0}/144' -f $explicitPhenotypeCount)
Write-Host ('PHENOTYPE_SERIES_DESIGN_FALLBACK_RECORDS={0}/144' -f $seriesFallbackCount)

# ------------------------------------------------------------
# 3. Build and certify the 72 cross-modality pairs
# ------------------------------------------------------------
$pairRows = @()
$allSubjects = @($metadata.subject_id | Sort-Object -Unique)

if ($allSubjects.Count -ne 72) {
    throw ('UNIQUE_BIOLOGICAL_SUBJECT_COUNT={0}' -f $allSubjects.Count)
}

foreach ($subject in $allSubjects) {
    $m = @($mrnaMeta | Where-Object subject_id -eq $subject)
    $mi = @($mirnaMeta | Where-Object subject_id -eq $subject)

    if ($m.Count -ne 1 -or $mi.Count -ne 1) {
        throw ('PAIR_CARDINALITY_FAILURE subject={0} mRNA={1} miRNA={2}' -f $subject,$m.Count,$mi.Count)
    }

    if ($m[0].group_prefix -ne $mi[0].group_prefix -or
        $m[0].disease_state_normalized -ne $mi[0].disease_state_normalized) {
        throw ('PAIR_METADATA_MISMATCH subject={0}' -f $subject)
    }

    $mFile = @($mrnaInv | Where-Object subject_id -eq $subject)
    $miFile = @($mirnaInv | Where-Object subject_id -eq $subject)

    if ($mFile.Count -ne 1 -or $miFile.Count -ne 1) {
        throw ('PAIR_FILE_CARDINALITY_FAILURE subject={0} mRNA={1} miRNA={2}' -f $subject,$mFile.Count,$miFile.Count)
    }

    if ($mFile[0].GSM -ne $m[0].GSM -or $miFile[0].GSM -ne $mi[0].GSM) {
        throw ('PAIR_GSM_FILENAME_VS_SOFT_MISMATCH subject={0}' -f $subject)
    }

    $pairRows += [pscustomobject]@{
        subject_id=$subject
        group_prefix=$m[0].group_prefix
        disease_state=$m[0].disease_state_normalized
        mRNA_GSM=$m[0].GSM
        mRNA_title=$m[0].title
        mRNA_phenotype_evidence=$m[0].phenotype_evidence_source
        mRNA_file=$mFile[0].final_path
        miRNA_GSM=$mi[0].GSM
        miRNA_title=$mi[0].title
        miRNA_phenotype_evidence=$mi[0].phenotype_evidence_source
        miRNA_file=$miFile[0].final_path
        subject_id_match='YES'
        disease_state_match='YES'
        paired='YES'
    }
}

if ($pairRows.Count -ne 72) {
    throw ('CERTIFIED_PAIR_COUNT={0}' -f $pairRows.Count)
}

if (@($pairRows | Where-Object paired -ne 'YES').Count -gt 0) {
    throw 'PAIR_CERTIFICATION_INTERNAL_FAILURE'
}

Write-Host 'CROSS_MODALITY_PAIRING_CERTIFIED=YES'
Write-Host 'CERTIFIED_PAIRED_SUBJECTS=72'

# ------------------------------------------------------------
# 4. Audit every count file
# ------------------------------------------------------------
$countAudits = @()
$index = 0

foreach ($r in $mrnaInv) {
    $index++
    if (($index % 12) -eq 0) {
        Write-Host ('MRNA_COUNT_AUDIT_PROGRESS={0}/72' -f $index)
    }

    $countAudits += Audit-D2CountFile `
        -Path $r.final_path `
        -Modality 'mRNA' `
        -GSM $r.GSM `
        -SubjectId $r.subject_id `
        -GroupPrefix $r.group_prefix
}

$index = 0
foreach ($r in $mirnaInv) {
    $index++
    if (($index % 12) -eq 0) {
        Write-Host ('MIRNA_COUNT_AUDIT_PROGRESS={0}/72' -f $index)
    }

    $countAudits += Audit-D2CountFile `
        -Path $r.final_path `
        -Modality 'miRNA' `
        -GSM $r.GSM `
        -SubjectId $r.subject_id `
        -GroupPrefix $r.group_prefix
}

if ($countAudits.Count -ne 144) {
    throw ('COUNT_AUDIT_ROW_COUNT={0}' -f $countAudits.Count)
}

# Hard structural failures. Fractional values are NOT a structural failure.
$hardCountFailures = @($countAudits | Where-Object {
    $_.data_rows -le 0 -or
    $_.empty_feature_ids -gt 0 -or
    $_.duplicate_feature_ids -gt 0 -or
    $_.column_count_mismatches -gt 0 -or
    $_.missing_count_values -gt 0 -or
    $_.nonnumeric_count_values -gt 0 -or
    $_.nonfinite_count_values -gt 0 -or
    $_.negative_count_values -gt 0
})

if ($hardCountFailures.Count -gt 0) {
    $hardCountFailures |
        Select-Object * -ExcludeProperty _feature_ids |
        Export-Csv -LiteralPath (Join-Path $RunDir 'FAIL_COUNT_STRUCTURE_FILES.csv') -NoTypeInformation -Encoding UTF8

    throw ('COUNT_STRUCTURE_HARD_FAILURES={0}' -f $hardCountFailures.Count)
}

Write-Host 'COUNT_STRUCTURE_HARD_FAILURES=0'

# ------------------------------------------------------------
# 5. Feature-set consistency / union / intersection
# ------------------------------------------------------------
function Get-D2FeatureSetSummary {
    param(
        [array]$Rows,
        [string]$Modality
    )

    $setHashCount = @($Rows.feature_set_sha256 | Sort-Object -Unique).Count
    $sequenceHashCount = @($Rows.feature_sequence_sha256 | Sort-Object -Unique).Count

    $union = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $intersection = $null

    foreach ($r in $Rows) {
        $current = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

        foreach ($id in $r._feature_ids) {
            [void]$current.Add([string]$id)
            [void]$union.Add([string]$id)
        }

        if ($null -eq $intersection) {
            $intersection = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
            foreach ($id in $current) {
                [void]$intersection.Add($id)
            }
        }
        else {
            $intersection.IntersectWith($current)
        }
    }

    $rowCounts = @($Rows.data_rows | ForEach-Object { [int]$_ })
    $minRows = ($rowCounts | Measure-Object -Minimum).Minimum
    $maxRows = ($rowCounts | Measure-Object -Maximum).Maximum

    $featureTypes = @($Rows.feature_id_type | Sort-Object -Unique)
    $featureTypeSummary = $featureTypes -join '|'

    return [pscustomobject]@{
        modality=$Modality
        sample_count=$Rows.Count
        minimum_features_per_sample=$minRows
        maximum_features_per_sample=$maxRows
        union_feature_count=$union.Count
        intersection_feature_count=$intersection.Count
        unique_feature_set_hashes=$setHashCount
        unique_feature_sequence_hashes=$sequenceHashCount
        feature_sets_identical=$(if ($setHashCount -eq 1) {'YES'} else {'NO'})
        feature_order_identical=$(if ($sequenceHashCount -eq 1) {'YES'} else {'NO'})
        feature_id_type_summary=$featureTypeSummary
        matrix_strategy_flag=$(if ($setHashCount -eq 1) {'DIRECT_COMMON_FEATURE_SET'} else {'VARIABLE_FEATURE_SET_REQUIRES_EXPLICIT_UNION_INTERSECTION_POLICY'})
    }
}

$mrnaAudit = @($countAudits | Where-Object modality -eq 'mRNA')
$mirnaAudit = @($countAudits | Where-Object modality -eq 'miRNA')

$mrnaFeatureSummary = Get-D2FeatureSetSummary -Rows $mrnaAudit -Modality 'mRNA'
$mirnaFeatureSummary = Get-D2FeatureSetSummary -Rows $mirnaAudit -Modality 'miRNA'

Write-Host ('MRNA_FEATURE_SETS_IDENTICAL={0}' -f $mrnaFeatureSummary.feature_sets_identical)
Write-Host ('MRNA_FEATURE_UNION={0}|INTERSECTION={1}' -f $mrnaFeatureSummary.union_feature_count,$mrnaFeatureSummary.intersection_feature_count)
Write-Host ('MIRNA_FEATURE_SETS_IDENTICAL={0}' -f $mirnaFeatureSummary.feature_sets_identical)
Write-Host ('MIRNA_FEATURE_UNION={0}|INTERSECTION={1}' -f $mirnaFeatureSummary.union_feature_count,$mirnaFeatureSummary.intersection_feature_count)

# ------------------------------------------------------------
# 6. Count semantics aggregation
# ------------------------------------------------------------
function Get-D2CountSemanticSummary {
    param(
        [array]$Rows,
        [string]$Modality
    )

    [Int64]$fractional = (($Rows | Measure-Object fractional_count_values -Sum).Sum)
    [Int64]$zeros = (($Rows | Measure-Object zero_count_values -Sum).Sum)
    [Int64]$dataRows = (($Rows | Measure-Object data_rows -Sum).Sum)

    $sums = @($Rows.count_sum | ForEach-Object { [double]$_ })
    $minLib = ($sums | Measure-Object -Minimum).Minimum
    $maxLib = ($sums | Measure-Object -Maximum).Maximum
    $meanLib = ($sums | Measure-Object -Average).Average

    $columnPatterns = @($Rows.column_count | Sort-Object -Unique)
    $headerPatterns = @($Rows.header_text | Sort-Object -Unique)
    $idTypes = @($Rows.feature_id_type | Sort-Object -Unique)

    return [pscustomobject]@{
        modality=$Modality
        sample_count=$Rows.Count
        total_data_rows=$dataRows
        total_fractional_count_values=$fractional
        count_integer_status=$(if ($fractional -eq 0) {'ALL_NONNEGATIVE_INTEGER_VALUES'} else {'FRACTIONAL_VALUES_PRESENT'})
        samples_with_fractional_values=@($Rows | Where-Object fractional_count_values -gt 0).Count
        total_zero_values=$zeros
        overall_zero_fraction=[math]::Round($zeros/[double]$dataRows,6)
        minimum_library_sum=[math]::Round($minLib,6)
        maximum_library_sum=[math]::Round($maxLib,6)
        mean_library_sum=[math]::Round($meanLib,6)
        unique_column_count_patterns=$columnPatterns.Count
        column_counts=($columnPatterns -join '|')
        unique_header_patterns=$headerPatterns.Count
        feature_id_types=($idTypes -join '|')
        negative_values=0
        missing_values=0
        nonnumeric_values=0
        nonfinite_values=0
        duplicate_feature_ids=0
    }
}

$mrnaCountSummary = Get-D2CountSemanticSummary -Rows $mrnaAudit -Modality 'mRNA'
$mirnaCountSummary = Get-D2CountSemanticSummary -Rows $mirnaAudit -Modality 'miRNA'

Write-Host ('MRNA_COUNT_INTEGER_STATUS={0}' -f $mrnaCountSummary.count_integer_status)
Write-Host ('MRNA_SAMPLES_WITH_FRACTIONAL_VALUES={0}/72' -f $mrnaCountSummary.samples_with_fractional_values)
Write-Host ('MRNA_TOTAL_FRACTIONAL_VALUES={0}' -f $mrnaCountSummary.total_fractional_count_values)
Write-Host ('MIRNA_COUNT_INTEGER_STATUS={0}' -f $mirnaCountSummary.count_integer_status)
Write-Host ('MIRNA_SAMPLES_WITH_FRACTIONAL_VALUES={0}/72' -f $mirnaCountSummary.samples_with_fractional_values)
Write-Host ('MIRNA_TOTAL_FRACTIONAL_VALUES={0}' -f $mirnaCountSummary.total_fractional_count_values)

# ------------------------------------------------------------
# 7. Write audit outputs (exclude in-memory feature arrays)
# ------------------------------------------------------------
$metadata |
    Sort-Object modality,subject_id |
    Export-Csv -LiteralPath $MetadataCsv -NoTypeInformation -Encoding UTF8

$pairRows |
    Sort-Object group_prefix,subject_id |
    Export-Csv -LiteralPath $PairingCsv -NoTypeInformation -Encoding UTF8

$countAudits |
    Select-Object * -ExcludeProperty _feature_ids |
    Sort-Object modality,subject_id |
    Export-Csv -LiteralPath $SampleAuditCsv -NoTypeInformation -Encoding UTF8

@($mrnaFeatureSummary,$mirnaFeatureSummary) |
    Export-Csv -LiteralPath $FeatureSummaryCsv -NoTypeInformation -Encoding UTF8

@($mrnaCountSummary,$mirnaCountSummary) |
    Export-Csv -LiteralPath $CountSummaryCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 8. Frozen D2 decisions / authorization state
# ------------------------------------------------------------
$mrnaIntegerStatus = $mrnaCountSummary.count_integer_status
$mirnaIntegerStatus = $mirnaCountSummary.count_integer_status

$matrixDesignNeeded = (
    $mrnaFeatureSummary.feature_sets_identical -ne 'YES' -or
    $mirnaFeatureSummary.feature_sets_identical -ne 'YES'
)

$deMethodDecisionNeeded = (
    $mrnaIntegerStatus -eq 'FRACTIONAL_VALUES_PRESENT' -or
    $mirnaIntegerStatus -eq 'FRACTIONAL_VALUES_PRESENT'
)

$nextPhase = if ($matrixDesignNeeded -or $deMethodDecisionNeeded) {
    'D2A_PROSPECTIVE_MATRIX_AND_STATISTICAL_STRATEGY'
}
else {
    'D3_MATRIX_CONSTRUCTION_AND_QC_PREFLIGHT'
}

@(
    'GSE243219_PHASE_D2_STATUS',
    'PHASE_D2_V2_STATUS=PASS',
    'MODE=READ_AND_AUDIT_ONLY',
    'MATRIX_CONSTRUCTION_EXECUTED=NO',
    'ZERO_FILL_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'NORMALIZATION_EXECUTED=NO',
    'FILTERING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'D1_DOWNLOADS_RECERTIFIED=4',
    'D1_EXTRACTED_FILES_RECERTIFIED=144',
    'GEO_METADATA_RECORDS_MRNA=72',
    'GEO_METADATA_RECORDS_MIRNA=72',
    ('PHENOTYPE_EXPLICIT_SAMPLE_RECORDS={0}' -f $explicitPhenotypeCount),
    ('PHENOTYPE_SERIES_DESIGN_FALLBACK_RECORDS={0}' -f $seriesFallbackCount),
    'P_LABEL_SEPSIS_MAPPING_CERTIFIED=YES',
    'COV_LABEL_COVID19_MAPPING_CERTIFIED=YES',
    'H_LABEL_HEALTHY_MAPPING_CERTIFIED=YES',
    'CROSS_MODALITY_PAIRING_CERTIFIED=YES',
    'CERTIFIED_PAIRED_SUBJECTS=72',
    'PAIRED_COVID=35',
    'PAIRED_SEPSIS=22',
    'PAIRED_HEALTHY=15',
    ('MRNA_COUNT_INTEGER_STATUS={0}' -f $mrnaIntegerStatus),
    ('MIRNA_COUNT_INTEGER_STATUS={0}' -f $mirnaIntegerStatus),
    ('MRNA_FEATURE_SETS_IDENTICAL={0}' -f $mrnaFeatureSummary.feature_sets_identical),
    ('MIRNA_FEATURE_SETS_IDENTICAL={0}' -f $mirnaFeatureSummary.feature_sets_identical),
    ('MRNA_FEATURE_UNION={0}' -f $mrnaFeatureSummary.union_feature_count),
    ('MRNA_FEATURE_INTERSECTION={0}' -f $mrnaFeatureSummary.intersection_feature_count),
    ('MIRNA_FEATURE_UNION={0}' -f $mirnaFeatureSummary.union_feature_count),
    ('MIRNA_FEATURE_INTERSECTION={0}' -f $mirnaFeatureSummary.intersection_feature_count),
    ('MRNA_FEATURE_ID_TYPE={0}' -f $mrnaCountSummary.feature_id_types),
    ('MIRNA_FEATURE_ID_TYPE={0}' -f $mirnaCountSummary.feature_id_types),
    ('MATRIX_DESIGN_REVIEW_REQUIRED={0}' -f $(if ($matrixDesignNeeded) {'YES'} else {'NO'})),
    ('DE_METHOD_REVIEW_REQUIRED={0}' -f $(if ($deMethodDecisionNeeded) {'YES'} else {'NO'})),
    'READY_FOR_MATRIX_CONSTRUCTION=NO',
    'READY_FOR_NORMALIZATION=NO',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    ('NEXT_PHASE={0}' -f $nextPhase),
    'STOP=YES'
) | Set-Content -LiteralPath $StatusTxt -Encoding UTF8

# ------------------------------------------------------------
# 9. Output SHA256 manifest
# ------------------------------------------------------------
$outFiles = @(
    $SampleAuditCsv,
    $PairingCsv,
    $MetadataCsv,
    $FeatureSummaryCsv,
    $CountSummaryCsv,
    $StatusTxt
)

$manifestRows = @()

foreach ($p in $outFiles) {
    $item = Get-Item -LiteralPath $p

    $manifestRows += [pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D2SHA256 $item.FullName)
    }
}

$manifestRows |
    Export-Csv -LiteralPath $OutputManifest -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 10. Final summary
# ------------------------------------------------------------
$summary = @(
    '=== GSE243219 PHASE D2 SUMMARY ===',
    'PHASE_D2_V2_STATUS=PASS',
    'MODE=READ_AND_AUDIT_ONLY',
    'MATRIX_CONSTRUCTION_EXECUTED=NO',
    'ZERO_FILL_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'NORMALIZATION_EXECUTED=NO',
    'FILTERING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'D1_DOWNLOADS_RECERTIFIED=4/4',
    'D1_EXTRACTED_FILES_RECERTIFIED=144/144',
    'COUNT_FILES_AUDITED=144/144',
    'COUNT_STRUCTURE_HARD_FAILURES=0',
    'GEO_METADATA_RECORDS_MRNA=72',
    'GEO_METADATA_RECORDS_MIRNA=72',
    ('PHENOTYPE_EXPLICIT_SAMPLE_RECORDS={0}' -f $explicitPhenotypeCount),
    ('PHENOTYPE_SERIES_DESIGN_FALLBACK_RECORDS={0}' -f $seriesFallbackCount),
    'P_LABEL_SEPSIS_MAPPING_CERTIFIED=YES',
    'COV_LABEL_COVID19_MAPPING_CERTIFIED=YES',
    'H_LABEL_HEALTHY_MAPPING_CERTIFIED=YES',
    'CROSS_MODALITY_PAIRING_CERTIFIED=YES',
    'CERTIFIED_PAIRED_SUBJECTS=72',
    'PAIRED_GROUP_COUNTS=COV35|P22|H15',
    ('MRNA_COUNT_INTEGER_STATUS={0}' -f $mrnaIntegerStatus),
    ('MRNA_SAMPLES_WITH_FRACTIONAL_VALUES={0}' -f $mrnaCountSummary.samples_with_fractional_values),
    ('MRNA_TOTAL_FRACTIONAL_VALUES={0}' -f $mrnaCountSummary.total_fractional_count_values),
    ('MIRNA_COUNT_INTEGER_STATUS={0}' -f $mirnaIntegerStatus),
    ('MIRNA_SAMPLES_WITH_FRACTIONAL_VALUES={0}' -f $mirnaCountSummary.samples_with_fractional_values),
    ('MIRNA_TOTAL_FRACTIONAL_VALUES={0}' -f $mirnaCountSummary.total_fractional_count_values),
    ('MRNA_FEATURE_SETS_IDENTICAL={0}' -f $mrnaFeatureSummary.feature_sets_identical),
    ('MRNA_FEATURE_UNION={0}' -f $mrnaFeatureSummary.union_feature_count),
    ('MRNA_FEATURE_INTERSECTION={0}' -f $mrnaFeatureSummary.intersection_feature_count),
    ('MRNA_FEATURE_ID_TYPE={0}' -f $mrnaCountSummary.feature_id_types),
    ('MIRNA_FEATURE_SETS_IDENTICAL={0}' -f $mirnaFeatureSummary.feature_sets_identical),
    ('MIRNA_FEATURE_UNION={0}' -f $mirnaFeatureSummary.union_feature_count),
    ('MIRNA_FEATURE_INTERSECTION={0}' -f $mirnaFeatureSummary.intersection_feature_count),
    ('MIRNA_FEATURE_ID_TYPE={0}' -f $mirnaCountSummary.feature_id_types),
    ('MATRIX_DESIGN_REVIEW_REQUIRED={0}' -f $(if ($matrixDesignNeeded) {'YES'} else {'NO'})),
    ('DE_METHOD_REVIEW_REQUIRED={0}' -f $(if ($deMethodDecisionNeeded) {'YES'} else {'NO'})),
    'READY_FOR_MATRIX_CONSTRUCTION=NO',
    'READY_FOR_NORMALIZATION=NO',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    ('NEXT_PHASE={0}' -f $nextPhase),
    'STOP=YES'
)

$summary | Set-Content -LiteralPath $ReportSummary -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $ReportSummary
Write-Host ''
Write-Host ('D2_SAMPLE_COUNT_STRUCTURE_AUDIT={0}' -f $SampleAuditCsv)
Write-Host ('D2_CERTIFIED_PAIRING={0}' -f $PairingCsv)
Write-Host ('D2_GEO_SAMPLE_METADATA={0}' -f $MetadataCsv)
Write-Host ('D2_FEATURE_SET_SUMMARY={0}' -f $FeatureSummaryCsv)
Write-Host ('D2_COUNT_SEMANTICS_SUMMARY={0}' -f $CountSummaryCsv)
Write-Host ('D2_STATUS={0}' -f $StatusTxt)
Write-Host ('D2_OUTPUT_SHA256_MANIFEST={0}' -f $OutputManifest)
Write-Host ('PHASE_D2_SUMMARY={0}' -f $ReportSummary)
Write-Host 'STEP_GSE243219_PHASE_D2_V2=PASS'
Write-Host 'STOP=YES'
