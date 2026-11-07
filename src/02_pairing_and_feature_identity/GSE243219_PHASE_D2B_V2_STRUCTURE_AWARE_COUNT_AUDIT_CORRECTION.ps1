$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D2B — STRUCTURE-AWARE COUNT AUDIT CORRECTION
#
# READ/AUDIT ONLY.
#
# Scientific correction:
#   mRNA unique raw feature key:
#       gene_symbol
#
#   miRNA unique raw row key:
#       pre-miRNA + MIMAT + mature-miRNA
#
# Repeated pre-miRNA labels are NOT duplicates when the complete
# annotation tuple differs.
#
# This phase does NOT aggregate mature miRNAs across precursors.
# It only audits whether such consolidation will be required
# prospectively for downstream biological/statistical analysis.
#
# NO matrix construction / aggregation / zero fill / rounding /
# normalization / filtering / exclusion / DE / network / A-CLA.
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D1Audit = Join-Path $Project '01_PROCESSED_DATA_ACQUISITION\audit'
$D2Root = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING'

$MrnaInventoryCsv = Join-Path $D1Audit 'D1_GSE243217_MRNA_FILE_INVENTORY.csv'
$MirnaInventoryCsv = Join-Path $D1Audit 'D1_GSE243218_MIRNA_FILE_INVENTORY.csv'

$D2AV2Dir = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D2A_V2_20260904_190826'
$D2AV2Summary = Join-Path $D2AV2Dir 'PHASE_D2A_V2_SUMMARY.txt'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D2Root ('D2B_AUDIT_{0}' -f $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D2B_{0}' -f $Stamp)

New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$SampleAuditCsv = Join-Path $RunDir 'D2B_SAMPLE_COUNT_SEMANTICS_AUDIT.csv'
$FeatureSummaryCsv = Join-Path $RunDir 'D2B_FEATURE_SET_SUMMARY.csv'
$MirnaAnnotationCsv = Join-Path $RunDir 'D2B_MIRNA_ANNOTATION_IDENTITY_MAP.csv'
$MirnaIdentitySummaryCsv = Join-Path $RunDir 'D2B_MIRNA_REGULATORY_IDENTITY_SUMMARY.csv'
$MirnaRepeatedIdentityCsv = Join-Path $RunDir 'D2B_MIRNA_REPEATED_REGULATORY_IDENTITIES.csv'
$MirnaPerSampleRepeatedCsv = Join-Path $RunDir 'D2B_MIRNA_PER_SAMPLE_REPEATED_IDENTITY_COUNT_BEHAVIOR.csv'
$CountSummaryCsv = Join-Path $RunDir 'D2B_COUNT_SEMANTICS_SUMMARY.csv'
$DecisionTxt = Join-Path $RunDir 'D2B_DECISION.txt'
$ManifestCsv = Join-Path $RunDir 'D2B_OUTPUT_SHA256_MANIFEST.csv'
$SummaryTxt = Join-Path $ReportDir 'PHASE_D2B_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D2B-V2 — STRUCTURE-AWARE COUNT AUDIT CORRECTION ==='
Write-Host 'MODE=READ_AND_AUDIT_ONLY'
Write-Host 'MATRIX_CONSTRUCTION_EXECUTED=NO'
Write-Host 'FEATURE_AGGREGATION_EXECUTED=NO'
Write-Host 'ZERO_FILL_EXECUTED=NO'
Write-Host 'COUNT_ROUNDING_EXECUTED=NO'
Write-Host 'NORMALIZATION_EXECUTED=NO'
Write-Host 'FILTERING_EXECUTED=NO'
Write-Host 'SAMPLE_EXCLUSION_EXECUTED=NO'
Write-Host 'DE_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR={0}' -f $RunDir)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @($MrnaInventoryCsv,$MirnaInventoryCsv,$D2AV2Summary)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D2BSHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-D2BGzipText {
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

function Get-D2BStringSHA256 {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-','').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Try-D2BDouble {
    param([string]$Text,[ref]$Value)

    return [double]::TryParse(
        $Text,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        $Value
    )
}

# ------------------------------------------------------------
# 1. D2A-V2 certification gate
# ------------------------------------------------------------
$d2a = Get-Content -LiteralPath $D2AV2Summary -Raw

foreach ($tok in @(
    'PHASE_D2A_V2_STATUS=PASS',
    'KNOWN_FAILURE_STATE_RECERTIFIED=YES',
    'FAILED_MODALITY=miRNA',
    'FAILED_MRNA_FILES=0',
    'FAILED_MIRNA_FILES=72',
    'ONLY_FAILURE_CLASS=DUPLICATE_FIRST_COLUMN_FEATURE_ID',
    'MIRNA_COLUMN_COUNT_PATTERNS=4',
    'MIRNA_DATA_ROW_COUNT_PATTERNS=2886',
    'MIRNA_UNIQUE_FIRST_ID_COUNT_PATTERNS=1917',
    'MIRNA_FIRST_ID_SET_HASH_COUNT=1',
    'MIRNA_FIRST_ID_SEQUENCE_HASH_COUNT=1',
    'MIRNA_ANNOTATION_SET_HASH_COUNT=1',
    'MIRNA_ANNOTATION_SEQUENCE_HASH_COUNT=1',
    'DUPLICATE_GROUPS_NOT_DISAMBIGUATED_BY_OTHER_ANNOTATION=0',
    'DUPLICATE_ANNOTATION_KEY_OCCURRENCES=0',
    'EXACT_DUPLICATE_FULL_ROW_OCCURRENCES=0',
    'MIRNA_DUPLICATE_STRUCTURE_CLASS=FIRST_COLUMN_LABEL_REPEATS_BUT_FULL_ANNOTATION_KEY_IS_UNIQUE'
)) {
    if ($d2a -notmatch [regex]::Escape($tok)) {
        throw ('D2A_V2_CERTIFICATION_TOKEN_MISSING={0}' -f $tok)
    }
}

Write-Host 'D2A_V2_STRUCTURE_CERTIFICATION_GATE=PASS'

$mrnaInv = @(Import-Csv -LiteralPath $MrnaInventoryCsv)
$mirnaInv = @(Import-Csv -LiteralPath $MirnaInventoryCsv)

if ($mrnaInv.Count -ne 72 -or $mirnaInv.Count -ne 72) {
    throw ('D1_INVENTORY_COUNT_CHANGED mRNA={0} miRNA={1}' -f $mrnaInv.Count,$mirnaInv.Count)
}

# Re-certify all 144 compressed count files.
foreach ($r in @($mrnaInv + $mirnaInv)) {
    if (-not (Test-Path -LiteralPath $r.final_path -PathType Leaf)) {
        throw ('COUNT_FILE_MISSING={0}' -f $r.final_path)
    }

    $item = Get-Item -LiteralPath $r.final_path
    $hash = Get-D2BSHA256 $r.final_path

    if ([Int64]$item.Length -ne [Int64]$r.compressed_bytes -or
        $hash -ne $r.SHA256.ToLowerInvariant()) {
        throw ('COUNT_FILE_HASH_OR_SIZE_CHANGED={0}' -f $r.final_path)
    }
}

Write-Host 'COUNT_FILES_RECERTIFIED=144/144'

# Lists avoid PowerShell PSObject += scalarization issues.
$sampleAudit = New-Object 'System.Collections.Generic.List[object]'
$mrnaFeatureInfo = New-Object 'System.Collections.Generic.List[object]'
$mirnaFeatureInfo = New-Object 'System.Collections.Generic.List[object]'
$mirnaRepeatedBehavior = New-Object 'System.Collections.Generic.List[object]'

function Audit-D2BFile {
    param(
        [string]$Path,
        [string]$Modality,
        [string]$GSM,
        [string]$SubjectId,
        [string]$GroupPrefix
    )

    $text = Get-D2BGzipText $Path
    $lines = @($text -split "`r?`n")

    $firstNonCommentSeen = $false
    $headerPresent = $false
    $headerText = ''
    $expectedColumns = $null

    $dataRows = 0
    $emptyRawKeys = 0
    $duplicateRawKeys = 0
    $missingCounts = 0
    $nonnumericCounts = 0
    $nonfiniteCounts = 0
    $negativeCounts = 0
    $fractionalCounts = 0
    $zeroCounts = 0

    [double]$countSum = 0
    [double]$minCount = [double]::PositiveInfinity
    [double]$maxCount = [double]::NegativeInfinity

    $rawKeys = New-Object 'System.Collections.Generic.List[string]'
    $rawKeySet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

    $regulatoryRows = New-Object 'System.Collections.Generic.List[object]'

    foreach ($lineRaw in $lines) {
        $line = [string]$lineRaw

        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('#')) { continue }

        $fields = @($line -split "`t",-1)

        if (-not $firstNonCommentSeen) {
            $firstNonCommentSeen = $true

            $last = $fields[$fields.Count-1].Trim()
            [double]$tmp = 0
            $isNumeric = Try-D2BDouble -Text $last -Value ([ref]$tmp)

            if (-not $isNumeric) {
                $headerPresent = $true
                $headerText = $line
                $expectedColumns = $fields.Count
                continue
            }
        }

        if ($null -eq $expectedColumns) {
            $expectedColumns = $fields.Count
        }

        if ($fields.Count -ne $expectedColumns) {
            throw ('COLUMN_COUNT_MISMATCH modality={0} file={1} expected={2} observed={3}' -f `
                $Modality,$Path,$expectedColumns,$fields.Count)
        }

        if ($Modality -eq 'mRNA') {
            if ($fields.Count -ne 2) {
                throw ('MRNA_EXPECTED_2_COLUMNS observed={0} file={1}' -f $fields.Count,$Path)
            }

            $gene = $fields[0].Trim()
            $rawKey = $gene

            if ([string]::IsNullOrWhiteSpace($rawKey)) {
                $emptyRawKeys++
            }
            elseif (-not $rawKeySet.Add($rawKey)) {
                $duplicateRawKeys++
            }

            $rawKeys.Add($rawKey)
        }
        else {
            if ($fields.Count -ne 4) {
                throw ('MIRNA_EXPECTED_4_COLUMNS observed={0} file={1}' -f $fields.Count,$Path)
            }

            $pre = $fields[0].Trim()
            $mimat = $fields[1].Trim()
            $mature = $fields[2].Trim()

            $rawKey = $pre + "`t" + $mimat + "`t" + $mature

            if ([string]::IsNullOrWhiteSpace($pre) -or
                [string]::IsNullOrWhiteSpace($mimat) -or
                [string]::IsNullOrWhiteSpace($mature)) {
                $emptyRawKeys++
            }
            elseif (-not $rawKeySet.Add($rawKey)) {
                $duplicateRawKeys++
            }

            $rawKeys.Add($rawKey)

            [void]$regulatoryRows.Add([pscustomobject]@{
                pre_miRNA=$pre
                MIMAT=$mimat
                mature_miRNA=$mature
                regulatory_key=($mimat + "`t" + $mature)
                raw_key=$rawKey
            })
        }

        $countText = $fields[$fields.Count-1].Trim()

        if ([string]::IsNullOrWhiteSpace($countText)) {
            $missingCounts++
            $dataRows++
            continue
        }

        [double]$countValue = 0
        $ok = Try-D2BDouble -Text $countText -Value ([ref]$countValue)

        if (-not $ok) {
            $nonnumericCounts++
            $dataRows++
            continue
        }

        if ([double]::IsNaN($countValue) -or [double]::IsInfinity($countValue)) {
            $nonfiniteCounts++
            $dataRows++
            continue
        }

        if ($countValue -lt 0) { $negativeCounts++ }

        if ([math]::Abs($countValue - [math]::Round($countValue)) -gt 1e-9) {
            $fractionalCounts++
        }

        if ([math]::Abs($countValue) -le 1e-15) {
            $zeroCounts++
        }

        $countSum += $countValue
        if ($countValue -lt $minCount) { $minCount = $countValue }
        if ($countValue -gt $maxCount) { $maxCount = $countValue }

        if ($Modality -eq 'miRNA') {
            $regulatoryRows[$regulatoryRows.Count-1] |
                Add-Member -NotePropertyName count_value -NotePropertyValue $countValue
        }

        $dataRows++
    }

    if ($dataRows -le 0) {
        throw ('NO_DATA_ROWS modality={0} file={1}' -f $Modality,$Path)
    }

    if ($emptyRawKeys -gt 0 -or $duplicateRawKeys -gt 0 -or
        $missingCounts -gt 0 -or $nonnumericCounts -gt 0 -or
        $nonfiniteCounts -gt 0 -or $negativeCounts -gt 0) {

        throw ('STRUCTURAL_FAILURE modality={0} file={1} empty_keys={2} duplicate_raw_keys={3} missing={4} nonnumeric={5} nonfinite={6} negative={7}' -f `
            $Modality,$Path,$emptyRawKeys,$duplicateRawKeys,$missingCounts,$nonnumericCounts,$nonfiniteCounts,$negativeCounts)
    }

    if ([double]::IsPositiveInfinity($minCount)) { $minCount = [double]::NaN }
    if ([double]::IsNegativeInfinity($maxCount)) { $maxCount = [double]::NaN }

    if ($Modality -eq 'miRNA') {
        $groups = @($regulatoryRows | Group-Object regulatory_key | Where-Object Count -gt 1)

        $sameCount = 0
        $differentCount = 0
        $maxSpread = 0.0

        foreach ($g in $groups) {
            $values = @($g.Group.count_value | ForEach-Object { [double]$_ })
            $uniqueVals = @($values | Sort-Object -Unique).Count
            $minV = ($values | Measure-Object -Minimum).Minimum
            $maxV = ($values | Measure-Object -Maximum).Maximum
            $spread = [double]$maxV - [double]$minV

            if ($uniqueVals -eq 1) { $sameCount++ }
            else { $differentCount++ }

            if ($spread -gt $maxSpread) { $maxSpread = $spread }
        }

        [void]$script:mirnaRepeatedBehavior.Add([pscustomobject]@{
            GSM=$GSM
            subject_id=$SubjectId
            repeated_regulatory_identity_groups=$groups.Count
            groups_with_identical_counts=$sameCount
            groups_with_different_counts=$differentCount
            maximum_within_identity_absolute_spread=[math]::Round($maxSpread,6)
        })
    }

    [void]$script:sampleAudit.Add([pscustomobject]@{
        modality=$Modality
        GSM=$GSM
        subject_id=$SubjectId
        group_prefix=$GroupPrefix
        file_path=$Path
        header_present=$(if ($headerPresent) {'YES'} else {'NO'})
        header_text=$headerText
        column_count=$expectedColumns
        data_rows=$dataRows
        unique_raw_feature_keys=$rawKeySet.Count
        duplicate_raw_feature_keys=$duplicateRawKeys
        empty_raw_feature_keys=$emptyRawKeys
        missing_count_values=$missingCounts
        nonnumeric_count_values=$nonnumericCounts
        nonfinite_count_values=$nonfiniteCounts
        negative_count_values=$negativeCounts
        fractional_count_values=$fractionalCounts
        zero_count_values=$zeroCounts
        zero_fraction=[math]::Round($zeroCounts/[double]$dataRows,6)
        count_sum=[math]::Round($countSum,6)
        min_count=$minCount
        max_count=$maxCount
        raw_feature_sequence_sha256=(Get-D2BStringSHA256 ($rawKeys -join "`n"))
        raw_feature_set_sha256=(Get-D2BStringSHA256 ((@($rawKeys | Sort-Object -Unique)) -join "`n"))
    })

    if ($Modality -eq 'mRNA') {
        [void]$script:mrnaFeatureInfo.Add([pscustomobject]@{
            GSM=$GSM
            subject_id=$SubjectId
            feature_sequence_sha256=(Get-D2BStringSHA256 ($rawKeys -join "`n"))
            feature_set_sha256=(Get-D2BStringSHA256 ((@($rawKeys | Sort-Object -Unique)) -join "`n"))
            feature_count=$rawKeySet.Count
        })
    }
    else {
        [void]$script:mirnaFeatureInfo.Add([pscustomobject]@{
            GSM=$GSM
            subject_id=$SubjectId
            feature_sequence_sha256=(Get-D2BStringSHA256 ($rawKeys -join "`n"))
            feature_set_sha256=(Get-D2BStringSHA256 ((@($rawKeys | Sort-Object -Unique)) -join "`n"))
            feature_count=$rawKeySet.Count
            regulatory_rows=[object[]]$regulatoryRows.ToArray()
        })
    }
}

# ------------------------------------------------------------
# 2. Audit all 144 files with corrected feature identity
# ------------------------------------------------------------
$i = 0
foreach ($r in $mrnaInv | Sort-Object subject_id) {
    $i++
    if (($i % 12) -eq 0) {
        Write-Host ('MRNA_STRUCTURE_AWARE_AUDIT_PROGRESS={0}/72' -f $i)
    }

    Audit-D2BFile `
        -Path $r.final_path `
        -Modality 'mRNA' `
        -GSM $r.GSM `
        -SubjectId $r.subject_id `
        -GroupPrefix $r.group_prefix
}

$i = 0
foreach ($r in $mirnaInv | Sort-Object subject_id) {
    $i++
    if (($i % 12) -eq 0) {
        Write-Host ('MIRNA_STRUCTURE_AWARE_AUDIT_PROGRESS={0}/72' -f $i)
    }

    Audit-D2BFile `
        -Path $r.final_path `
        -Modality 'miRNA' `
        -GSM $r.GSM `
        -SubjectId $r.subject_id `
        -GroupPrefix $r.group_prefix
}

if ($sampleAudit.Count -ne 144) {
    throw ('SAMPLE_AUDIT_COUNT={0}' -f $sampleAudit.Count)
}

Write-Host 'STRUCTURE_AWARE_COUNT_FILES_AUDITED=144/144'
Write-Host 'STRUCTURE_AWARE_HARD_FAILURES=0'

# ------------------------------------------------------------
# 3. Cross-sample feature-set certification
# ------------------------------------------------------------
$mrnaSetHashes = @($mrnaFeatureInfo.feature_set_sha256 | Sort-Object -Unique)
$mrnaSequenceHashes = @($mrnaFeatureInfo.feature_sequence_sha256 | Sort-Object -Unique)
$mirnaSetHashes = @($mirnaFeatureInfo.feature_set_sha256 | Sort-Object -Unique)
$mirnaSequenceHashes = @($mirnaFeatureInfo.feature_sequence_sha256 | Sort-Object -Unique)

$mrnaFeatureCounts = @($mrnaFeatureInfo.feature_count | Sort-Object -Unique)
$mirnaFeatureCounts = @($mirnaFeatureInfo.feature_count | Sort-Object -Unique)

$mrnaSetsIdentical = ($mrnaSetHashes.Count -eq 1)
$mrnaOrderIdentical = ($mrnaSequenceHashes.Count -eq 1)
$mirnaSetsIdentical = ($mirnaSetHashes.Count -eq 1)
$mirnaOrderIdentical = ($mirnaSequenceHashes.Count -eq 1)

Write-Host ('MRNA_RAW_FEATURE_SETS_IDENTICAL={0}' -f $(if ($mrnaSetsIdentical) {'YES'} else {'NO'}))
Write-Host ('MRNA_RAW_FEATURE_ORDER_IDENTICAL={0}' -f $(if ($mrnaOrderIdentical) {'YES'} else {'NO'}))
Write-Host ('MRNA_RAW_FEATURE_COUNT_PATTERNS={0}' -f ($mrnaFeatureCounts -join '|'))
Write-Host ('MIRNA_RAW_FEATURE_SETS_IDENTICAL={0}' -f $(if ($mirnaSetsIdentical) {'YES'} else {'NO'}))
Write-Host ('MIRNA_RAW_FEATURE_ORDER_IDENTICAL={0}' -f $(if ($mirnaOrderIdentical) {'YES'} else {'NO'}))
Write-Host ('MIRNA_RAW_FEATURE_COUNT_PATTERNS={0}' -f ($mirnaFeatureCounts -join '|'))

# ------------------------------------------------------------
# 4. Static miRNA annotation identity map from one sample
#    (annotation hashes already must match across all samples).
# ------------------------------------------------------------
if (-not $mirnaSetsIdentical -or -not $mirnaOrderIdentical) {
    throw 'MIRNA_RAW_ANNOTATION_NOT_IDENTICAL_ACROSS_SAMPLES'
}

$representative = $mirnaFeatureInfo | Sort-Object subject_id | Select-Object -First 1
$annotationRows = [object[]]$representative.regulatory_rows
Write-Host ('REPRESENTATIVE_MIRNA_REGULATORY_ROWS_TYPE={0}' -f $annotationRows.GetType().FullName)
Write-Host ('REPRESENTATIVE_MIRNA_REGULATORY_ROWS={0}' -f $annotationRows.Count)

if ($annotationRows.Count -ne 2886) {
    throw ('REPRESENTATIVE_MIRNA_ANNOTATION_ROWS expected=2886 observed={0}' -f $annotationRows.Count)
}

$annotationMap = New-Object 'System.Collections.Generic.List[object]'

foreach ($r in $annotationRows) {
    [void]$annotationMap.Add([pscustomobject]@{
        pre_miRNA=$r.pre_miRNA
        MIMAT=$r.MIMAT
        mature_miRNA=$r.mature_miRNA
        raw_feature_key=($r.pre_miRNA + '|' + $r.MIMAT + '|' + $r.mature_miRNA)
        regulatory_identity_key=($r.MIMAT + '|' + $r.mature_miRNA)
    })
}

$preGroups = @($annotationMap | Group-Object pre_miRNA)
$mimatGroups = @($annotationMap | Group-Object MIMAT)
$matureGroups = @($annotationMap | Group-Object mature_miRNA)
$regGroups = @($annotationMap | Group-Object regulatory_identity_key)

$repeatedPreGroups = @($preGroups | Where-Object Count -gt 1)
$repeatedMimatGroups = @($mimatGroups | Where-Object Count -gt 1)
$repeatedMatureGroups = @($matureGroups | Where-Object Count -gt 1)
$repeatedRegGroups = @($regGroups | Where-Object Count -gt 1)

$mimatToMultipleMature = @()
foreach ($g in $mimatGroups) {
    $uniqueMature = @($g.Group.mature_miRNA | Sort-Object -Unique)
    if ($uniqueMature.Count -gt 1) {
        $mimatToMultipleMature += [pscustomobject]@{
            MIMAT=$g.Name
            mature_count=$uniqueMature.Count
            mature_names=($uniqueMature -join '|')
        }
    }
}

$matureToMultipleMimat = @()
foreach ($g in $matureGroups) {
    $uniqueMimat = @($g.Group.MIMAT | Sort-Object -Unique)
    if ($uniqueMimat.Count -gt 1) {
        $matureToMultipleMimat += [pscustomobject]@{
            mature_miRNA=$g.Name
            MIMAT_count=$uniqueMimat.Count
            MIMAT_ids=($uniqueMimat -join '|')
        }
    }
}

$repeatedIdentityRows = New-Object 'System.Collections.Generic.List[object]'

foreach ($g in $repeatedRegGroups | Sort-Object Name) {
    $pres = @($g.Group.pre_miRNA | Sort-Object -Unique)
    $first = $g.Group[0]

    [void]$repeatedIdentityRows.Add([pscustomobject]@{
        regulatory_identity_key=$g.Name
        MIMAT=$first.MIMAT
        mature_miRNA=$first.mature_miRNA
        precursor_row_count=$g.Count
        unique_precursor_count=$pres.Count
        precursor_ids=($pres -join '|')
    })
}

$annotationMap |
    Export-Csv -LiteralPath $MirnaAnnotationCsv -NoTypeInformation -Encoding UTF8

$repeatedIdentityRows |
    Export-Csv -LiteralPath $MirnaRepeatedIdentityCsv -NoTypeInformation -Encoding UTF8

$mirnaRepeatedBehavior |
    Sort-Object subject_id |
    Export-Csv -LiteralPath $MirnaPerSampleRepeatedCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Count semantics
# ------------------------------------------------------------
$mrnaAudit = @($sampleAudit | Where-Object modality -eq 'mRNA')
$mirnaAudit = @($sampleAudit | Where-Object modality -eq 'miRNA')

function Get-D2BCountSummary {
    param([array]$Rows,[string]$Modality)

    [Int64]$fractional = (($Rows | Measure-Object fractional_count_values -Sum).Sum)
    [Int64]$zeros = (($Rows | Measure-Object zero_count_values -Sum).Sum)
    [Int64]$dataRows = (($Rows | Measure-Object data_rows -Sum).Sum)

    $libs = @($Rows.count_sum | ForEach-Object { [double]$_ })

    return [pscustomobject]@{
        modality=$Modality
        sample_count=$Rows.Count
        total_data_rows=$dataRows
        samples_with_fractional_values=@($Rows | Where-Object fractional_count_values -gt 0).Count
        total_fractional_count_values=$fractional
        count_integer_status=$(if ($fractional -eq 0) {'ALL_NONNEGATIVE_INTEGER_VALUES'} else {'FRACTIONAL_VALUES_PRESENT'})
        total_zero_values=$zeros
        overall_zero_fraction=[math]::Round($zeros/[double]$dataRows,6)
        minimum_library_sum=[math]::Round((($libs | Measure-Object -Minimum).Minimum),6)
        maximum_library_sum=[math]::Round((($libs | Measure-Object -Maximum).Maximum),6)
        mean_library_sum=[math]::Round((($libs | Measure-Object -Average).Average),6)
        negative_values=0
        missing_values=0
        nonnumeric_values=0
        nonfinite_values=0
        duplicate_raw_feature_keys=0
    }
}

$mrnaCount = Get-D2BCountSummary -Rows $mrnaAudit -Modality 'mRNA'
$mirnaCount = Get-D2BCountSummary -Rows $mirnaAudit -Modality 'miRNA'

Write-Host ('MRNA_COUNT_INTEGER_STATUS={0}' -f $mrnaCount.count_integer_status)
Write-Host ('MRNA_SAMPLES_WITH_FRACTIONAL_VALUES={0}/72' -f $mrnaCount.samples_with_fractional_values)
Write-Host ('MRNA_TOTAL_FRACTIONAL_VALUES={0}' -f $mrnaCount.total_fractional_count_values)
Write-Host ('MIRNA_COUNT_INTEGER_STATUS={0}' -f $mirnaCount.count_integer_status)
Write-Host ('MIRNA_SAMPLES_WITH_FRACTIONAL_VALUES={0}/72' -f $mirnaCount.samples_with_fractional_values)
Write-Host ('MIRNA_TOTAL_FRACTIONAL_VALUES={0}' -f $mirnaCount.total_fractional_count_values)

# ------------------------------------------------------------
# 6. miRNA regulatory-identity behavior
# ------------------------------------------------------------
[Int64]$totalRepeatedGroupsAcrossSamples = (($mirnaRepeatedBehavior | Measure-Object repeated_regulatory_identity_groups -Sum).Sum)
[Int64]$sameCountGroupsAcrossSamples = (($mirnaRepeatedBehavior | Measure-Object groups_with_identical_counts -Sum).Sum)
[Int64]$differentCountGroupsAcrossSamples = (($mirnaRepeatedBehavior | Measure-Object groups_with_different_counts -Sum).Sum)
$maxSpread = (($mirnaRepeatedBehavior.maximum_within_identity_absolute_spread | Measure-Object -Maximum).Maximum)

$regulatoryConsolidationRequired = ($repeatedRegGroups.Count -gt 0)

Write-Host ('MIRNA_RAW_ANNOTATION_ROWS={0}' -f $annotationMap.Count)
Write-Host ('MIRNA_UNIQUE_PRECURSOR_IDS={0}' -f $preGroups.Count)
Write-Host ('MIRNA_UNIQUE_MIMAT_IDS={0}' -f $mimatGroups.Count)
Write-Host ('MIRNA_UNIQUE_MATURE_NAMES={0}' -f $matureGroups.Count)
Write-Host ('MIRNA_UNIQUE_REGULATORY_IDENTITIES={0}' -f $regGroups.Count)
Write-Host ('MIRNA_REPEATED_PRECURSOR_GROUPS={0}' -f $repeatedPreGroups.Count)
Write-Host ('MIRNA_REPEATED_MIMAT_GROUPS={0}' -f $repeatedMimatGroups.Count)
Write-Host ('MIRNA_REPEATED_MATURE_NAME_GROUPS={0}' -f $repeatedMatureGroups.Count)
Write-Host ('MIRNA_REPEATED_REGULATORY_IDENTITY_GROUPS={0}' -f $repeatedRegGroups.Count)
Write-Host ('MIRNA_MIMAT_TO_MULTIPLE_MATURE_CONFLICTS={0}' -f $mimatToMultipleMature.Count)
Write-Host ('MIRNA_MATURE_TO_MULTIPLE_MIMAT_CONFLICTS={0}' -f $matureToMultipleMimat.Count)
Write-Host ('MIRNA_REPEATED_IDENTITY_GROUPS_ACROSS_72_SAMPLES={0}' -f $totalRepeatedGroupsAcrossSamples)
Write-Host ('MIRNA_REPEATED_IDENTITY_GROUPS_IDENTICAL_COUNTS={0}' -f $sameCountGroupsAcrossSamples)
Write-Host ('MIRNA_REPEATED_IDENTITY_GROUPS_DIFFERENT_COUNTS={0}' -f $differentCountGroupsAcrossSamples)
Write-Host ('MIRNA_MAX_WITHIN_IDENTITY_ABSOLUTE_COUNT_SPREAD={0}' -f $maxSpread)
Write-Host ('MIRNA_REGULATORY_CONSOLIDATION_REVIEW_REQUIRED={0}' -f $(if ($regulatoryConsolidationRequired) {'YES'} else {'NO'}))

# ------------------------------------------------------------
# 7. Export summaries
# ------------------------------------------------------------
$sampleAudit |
    Sort-Object modality,subject_id |
    Export-Csv -LiteralPath $SampleAuditCsv -NoTypeInformation -Encoding UTF8

@(
    [pscustomobject]@{
        modality='mRNA'
        raw_feature_key='gene_symbol'
        samples=72
        raw_feature_count_patterns=($mrnaFeatureCounts -join '|')
        feature_sets_identical=$(if ($mrnaSetsIdentical) {'YES'} else {'NO'})
        feature_order_identical=$(if ($mrnaOrderIdentical) {'YES'} else {'NO'})
        raw_matrix_structure_status=$(if ($mrnaSetsIdentical) {'TECHNICALLY_FEASIBLE'} else {'REVIEW_REQUIRED'})
    },
    [pscustomobject]@{
        modality='miRNA'
        raw_feature_key='pre-miRNA|MIMAT|mature-miRNA'
        samples=72
        raw_feature_count_patterns=($mirnaFeatureCounts -join '|')
        feature_sets_identical=$(if ($mirnaSetsIdentical) {'YES'} else {'NO'})
        feature_order_identical=$(if ($mirnaOrderIdentical) {'YES'} else {'NO'})
        raw_matrix_structure_status=$(if ($mirnaSetsIdentical) {'TECHNICALLY_FEASIBLE'} else {'REVIEW_REQUIRED'})
    }
) | Export-Csv -LiteralPath $FeatureSummaryCsv -NoTypeInformation -Encoding UTF8

@($mrnaCount,$mirnaCount) |
    Export-Csv -LiteralPath $CountSummaryCsv -NoTypeInformation -Encoding UTF8

@(
    [pscustomobject]@{metric='raw_annotation_rows';value=$annotationMap.Count},
    [pscustomobject]@{metric='unique_precursor_ids';value=$preGroups.Count},
    [pscustomobject]@{metric='unique_MIMAT_ids';value=$mimatGroups.Count},
    [pscustomobject]@{metric='unique_mature_names';value=$matureGroups.Count},
    [pscustomobject]@{metric='unique_regulatory_identity_pairs';value=$regGroups.Count},
    [pscustomobject]@{metric='repeated_precursor_groups';value=$repeatedPreGroups.Count},
    [pscustomobject]@{metric='repeated_MIMAT_groups';value=$repeatedMimatGroups.Count},
    [pscustomobject]@{metric='repeated_mature_name_groups';value=$repeatedMatureGroups.Count},
    [pscustomobject]@{metric='repeated_regulatory_identity_groups';value=$repeatedRegGroups.Count},
    [pscustomobject]@{metric='MIMAT_to_multiple_mature_conflicts';value=$mimatToMultipleMature.Count},
    [pscustomobject]@{metric='mature_to_multiple_MIMAT_conflicts';value=$matureToMultipleMimat.Count},
    [pscustomobject]@{metric='repeated_identity_groups_across_72_samples';value=$totalRepeatedGroupsAcrossSamples},
    [pscustomobject]@{metric='repeated_identity_groups_identical_counts';value=$sameCountGroupsAcrossSamples},
    [pscustomobject]@{metric='repeated_identity_groups_different_counts';value=$differentCountGroupsAcrossSamples},
    [pscustomobject]@{metric='maximum_within_identity_absolute_count_spread';value=$maxSpread}
) | Export-Csv -LiteralPath $MirnaIdentitySummaryCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 8. Decision
# ------------------------------------------------------------
$rawMatrixTechnicallyFeasible = (
    $mrnaSetsIdentical -and
    $mirnaSetsIdentical -and
    $mrnaOrderIdentical -and
    $mirnaOrderIdentical
)

$deMethodReviewRequired = (
    $mrnaCount.count_integer_status -eq 'FRACTIONAL_VALUES_PRESENT' -or
    $mirnaCount.count_integer_status -eq 'FRACTIONAL_VALUES_PRESENT'
)

$featureIdentityStrategyRequired = $regulatoryConsolidationRequired

@(
    'GSE243219_D2B_DECISION',
    'PHASE_D2B_V2_STATUS=PASS',
    'STRUCTURE_AWARE_COUNT_AUDIT_CORRECTED=YES',
    'MATRIX_CONSTRUCTION_EXECUTED=NO',
    'FEATURE_AGGREGATION_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'NORMALIZATION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'MRNA_RAW_FEATURE_KEY=gene_symbol',
    'MIRNA_RAW_FEATURE_KEY=pre-miRNA|MIMAT|mature-miRNA',
    'MIRNA_REGULATORY_IDENTITY_KEY=MIMAT|mature-miRNA',
    ('MRNA_COUNT_INTEGER_STATUS={0}' -f $mrnaCount.count_integer_status),
    ('MIRNA_COUNT_INTEGER_STATUS={0}' -f $mirnaCount.count_integer_status),
    ('MRNA_RAW_FEATURE_SETS_IDENTICAL={0}' -f $(if ($mrnaSetsIdentical) {'YES'} else {'NO'})),
    ('MIRNA_RAW_FEATURE_SETS_IDENTICAL={0}' -f $(if ($mirnaSetsIdentical) {'YES'} else {'NO'})),
    ('RAW_MATRIX_CONSTRUCTION_TECHNICALLY_FEASIBLE={0}' -f $(if ($rawMatrixTechnicallyFeasible) {'YES'} else {'NO'})),
    ('MIRNA_REGULATORY_CONSOLIDATION_REVIEW_REQUIRED={0}' -f $(if ($featureIdentityStrategyRequired) {'YES'} else {'NO'})),
    ('DE_METHOD_REVIEW_REQUIRED={0}' -f $(if ($deMethodReviewRequired) {'YES'} else {'NO'})),
    'READY_FOR_MATRIX_CONSTRUCTION=NO',
    'READY_FOR_NORMALIZATION=NO',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D2C_PROSPECTIVE_FEATURE_IDENTITY_AND_STATISTICAL_STRATEGY',
    'STOP=YES'
) | Set-Content -LiteralPath $DecisionTxt -Encoding UTF8

# ------------------------------------------------------------
# 9. Output manifest + terminal summary
# ------------------------------------------------------------
$outFiles = @(
    $SampleAuditCsv,
    $FeatureSummaryCsv,
    $MirnaAnnotationCsv,
    $MirnaIdentitySummaryCsv,
    $MirnaRepeatedIdentityCsv,
    $MirnaPerSampleRepeatedCsv,
    $CountSummaryCsv,
    $DecisionTxt
)

$manifest = New-Object 'System.Collections.Generic.List[object]'

foreach ($p in $outFiles) {
    $item = Get-Item -LiteralPath $p

    [void]$manifest.Add([pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D2BSHA256 $item.FullName)
    })
}

$manifest |
    Export-Csv -LiteralPath $ManifestCsv -NoTypeInformation -Encoding UTF8

@(
    '=== GSE243219 PHASE D2B SUMMARY ===',
    'PHASE_D2B_V2_STATUS=PASS',
    'MODE=READ_AND_AUDIT_ONLY',
    'MATRIX_CONSTRUCTION_EXECUTED=NO',
    'FEATURE_AGGREGATION_EXECUTED=NO',
    'ZERO_FILL_EXECUTED=NO',
    'COUNT_ROUNDING_EXECUTED=NO',
    'NORMALIZATION_EXECUTED=NO',
    'FILTERING_EXECUTED=NO',
    'SAMPLE_EXCLUSION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'COUNT_FILES_RECERTIFIED=144/144',
    'STRUCTURE_AWARE_COUNT_FILES_AUDITED=144/144',
    'STRUCTURE_AWARE_HARD_FAILURES=0',
    'MRNA_RAW_FEATURE_KEY=gene_symbol',
    'MIRNA_RAW_FEATURE_KEY=pre-miRNA|MIMAT|mature-miRNA',
    'MIRNA_REGULATORY_IDENTITY_KEY=MIMAT|mature-miRNA',
    ('MRNA_RAW_FEATURE_SETS_IDENTICAL={0}' -f $(if ($mrnaSetsIdentical) {'YES'} else {'NO'})),
    ('MRNA_RAW_FEATURE_ORDER_IDENTICAL={0}' -f $(if ($mrnaOrderIdentical) {'YES'} else {'NO'})),
    ('MRNA_RAW_FEATURE_COUNT_PATTERNS={0}' -f ($mrnaFeatureCounts -join '|')),
    ('MIRNA_RAW_FEATURE_SETS_IDENTICAL={0}' -f $(if ($mirnaSetsIdentical) {'YES'} else {'NO'})),
    ('MIRNA_RAW_FEATURE_ORDER_IDENTICAL={0}' -f $(if ($mirnaOrderIdentical) {'YES'} else {'NO'})),
    ('MIRNA_RAW_FEATURE_COUNT_PATTERNS={0}' -f ($mirnaFeatureCounts -join '|')),
    ('MRNA_COUNT_INTEGER_STATUS={0}' -f $mrnaCount.count_integer_status),
    ('MRNA_SAMPLES_WITH_FRACTIONAL_VALUES={0}' -f $mrnaCount.samples_with_fractional_values),
    ('MRNA_TOTAL_FRACTIONAL_VALUES={0}' -f $mrnaCount.total_fractional_count_values),
    ('MIRNA_COUNT_INTEGER_STATUS={0}' -f $mirnaCount.count_integer_status),
    ('MIRNA_SAMPLES_WITH_FRACTIONAL_VALUES={0}' -f $mirnaCount.samples_with_fractional_values),
    ('MIRNA_TOTAL_FRACTIONAL_VALUES={0}' -f $mirnaCount.total_fractional_count_values),
    ('MIRNA_RAW_ANNOTATION_ROWS={0}' -f $annotationMap.Count),
    ('MIRNA_UNIQUE_PRECURSOR_IDS={0}' -f $preGroups.Count),
    ('MIRNA_UNIQUE_MIMAT_IDS={0}' -f $mimatGroups.Count),
    ('MIRNA_UNIQUE_MATURE_NAMES={0}' -f $matureGroups.Count),
    ('MIRNA_UNIQUE_REGULATORY_IDENTITIES={0}' -f $regGroups.Count),
    ('MIRNA_REPEATED_REGULATORY_IDENTITY_GROUPS={0}' -f $repeatedRegGroups.Count),
    ('MIRNA_MIMAT_TO_MULTIPLE_MATURE_CONFLICTS={0}' -f $mimatToMultipleMature.Count),
    ('MIRNA_MATURE_TO_MULTIPLE_MIMAT_CONFLICTS={0}' -f $matureToMultipleMimat.Count),
    ('MIRNA_REPEATED_IDENTITY_GROUPS_IDENTICAL_COUNTS={0}' -f $sameCountGroupsAcrossSamples),
    ('MIRNA_REPEATED_IDENTITY_GROUPS_DIFFERENT_COUNTS={0}' -f $differentCountGroupsAcrossSamples),
    ('MIRNA_MAX_WITHIN_IDENTITY_ABSOLUTE_COUNT_SPREAD={0}' -f $maxSpread),
    ('RAW_MATRIX_CONSTRUCTION_TECHNICALLY_FEASIBLE={0}' -f $(if ($rawMatrixTechnicallyFeasible) {'YES'} else {'NO'})),
    ('MIRNA_REGULATORY_CONSOLIDATION_REVIEW_REQUIRED={0}' -f $(if ($featureIdentityStrategyRequired) {'YES'} else {'NO'})),
    ('DE_METHOD_REVIEW_REQUIRED={0}' -f $(if ($deMethodReviewRequired) {'YES'} else {'NO'})),
    'READY_FOR_MATRIX_CONSTRUCTION=NO',
    'READY_FOR_NORMALIZATION=NO',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'NEXT_PHASE=D2C_PROSPECTIVE_FEATURE_IDENTITY_AND_STATISTICAL_STRATEGY',
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D2B_SAMPLE_COUNT_AUDIT={0}' -f $SampleAuditCsv)
Write-Host ('D2B_FEATURE_SET_SUMMARY={0}' -f $FeatureSummaryCsv)
Write-Host ('D2B_MIRNA_ANNOTATION_MAP={0}' -f $MirnaAnnotationCsv)
Write-Host ('D2B_MIRNA_IDENTITY_SUMMARY={0}' -f $MirnaIdentitySummaryCsv)
Write-Host ('D2B_MIRNA_REPEATED_IDENTITIES={0}' -f $MirnaRepeatedIdentityCsv)
Write-Host ('D2B_MIRNA_PER_SAMPLE_REPEATED_BEHAVIOR={0}' -f $MirnaPerSampleRepeatedCsv)
Write-Host ('D2B_COUNT_SEMANTICS_SUMMARY={0}' -f $CountSummaryCsv)
Write-Host ('D2B_DECISION={0}' -f $DecisionTxt)
Write-Host ('D2B_OUTPUT_SHA256_MANIFEST={0}' -f $ManifestCsv)
Write-Host ('PHASE_D2B_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D2B_V2=PASS'
Write-Host 'STOP=YES'
