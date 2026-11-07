$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219
# PHASE D2A-V2 — miRNA DUPLICATE-FEATURE STRUCTURE DIAGNOSTIC
#
# READ ONLY.
#
# Known from D2A:
#   failed files = 72
#   failed modality = miRNA
#   only failure = duplicate first-column feature identifiers
#
# This script determines whether those repeated identifiers:
#   A) are disambiguated by other annotation columns,
#   B) are duplicate annotation rows,
#   C) are exact duplicate full rows,
#   D) require a prospective aggregation policy.
#
# NO matrix construction / aggregation / zero fill / rounding /
# normalization / filtering / exclusion / DE / network / A-CLA.
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D1Audit = Join-Path $Project '01_PROCESSED_DATA_ACQUISITION\audit'

$MrnaInventoryCsv = Join-Path $D1Audit 'D1_GSE243217_MRNA_FILE_INVENTORY.csv'
$MirnaInventoryCsv = Join-Path $D1Audit 'D1_GSE243218_MIRNA_FILE_INVENTORY.csv'

$FailedD2Run = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING\D2_AUDIT_20260904_183945'
$FailedCsv = Join-Path $FailedD2Run 'FAIL_COUNT_STRUCTURE_FILES.csv'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$OutDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D2A_V2_{0}' -f $Stamp)
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

$PerSampleCsv = Join-Path $OutDir 'D2A_V2_MIRNA_PER_SAMPLE_DUPLICATE_STRUCTURE.csv'
$PreviewCsv = Join-Path $OutDir 'D2A_V2_REPRESENTATIVE_RAW_PREVIEW.csv'
$DupExamplesCsv = Join-Path $OutDir 'D2A_V2_DUPLICATE_FEATURE_GROUP_EXAMPLES.csv'
$SchemaCsv = Join-Path $OutDir 'D2A_V2_SCHEMA_SUMMARY.csv'
$CrossSampleCsv = Join-Path $OutDir 'D2A_V2_CROSS_SAMPLE_DUPLICATE_PATTERN_SUMMARY.csv'
$SummaryTxt = Join-Path $OutDir 'PHASE_D2A_V2_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D2A-V2 — miRNA DUPLICATE-FEATURE STRUCTURE DIAGNOSTIC ==='
Write-Host 'MODE=READ_ONLY_DIAGNOSTIC'
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
Write-Host ('REPORT_DIR={0}' -f $OutDir)

foreach ($p in @($MrnaInventoryCsv,$MirnaInventoryCsv,$FailedCsv)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_INPUT_MISSING={0}' -f $p)
    }
}

function Get-D2AV2GzipText {
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

function Try-D2AV2Double {
    param([string]$Text,[ref]$Value)

    return [double]::TryParse(
        $Text,
        [System.Globalization.NumberStyles]::Float,
        [System.Globalization.CultureInfo]::InvariantCulture,
        $Value
    )
}

function Get-D2AV2StringHash {
    param([string]$Text)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha.ComputeHash($bytes)
        return ([BitConverter]::ToString($hash) -replace '-','').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

$failed = @(Import-Csv -LiteralPath $FailedCsv)
$mrnaInv = @(Import-Csv -LiteralPath $MrnaInventoryCsv)
$mirnaInv = @(Import-Csv -LiteralPath $MirnaInventoryCsv)

if ($failed.Count -ne 72) {
    throw ('FAILED_ROW_COUNT_CHANGED expected=72 observed={0}' -f $failed.Count)
}

$failedMrna = @($failed | Where-Object modality -eq 'mRNA')
$failedMirna = @($failed | Where-Object modality -eq 'miRNA')

if ($failedMrna.Count -ne 0 -or $failedMirna.Count -ne 72) {
    throw ('KNOWN_FAILURE_MODALITY_CHANGED mRNA={0} miRNA={1}' -f $failedMrna.Count,$failedMirna.Count)
}

$unexpectedReasonRows = @($failedMirna | Where-Object {
    [Int64]$_.empty_feature_ids -gt 0 -or
    [Int64]$_.column_count_mismatches -gt 0 -or
    [Int64]$_.missing_count_values -gt 0 -or
    [Int64]$_.nonnumeric_count_values -gt 0 -or
    [Int64]$_.nonfinite_count_values -gt 0 -or
    [Int64]$_.negative_count_values -gt 0 -or
    [Int64]$_.duplicate_feature_ids -le 0
})

if ($unexpectedReasonRows.Count -gt 0) {
    throw ('KNOWN_FAILURE_REASON_CHANGED files={0}' -f $unexpectedReasonRows.Count)
}

Write-Host 'KNOWN_FAILURE_STATE_RECERTIFIED=YES'
Write-Host 'FAILED_MODALITY=miRNA'
Write-Host 'FAILED_MRNA_FILES=0'
Write-Host 'FAILED_MIRNA_FILES=72'
Write-Host 'ONLY_FAILURE_CLASS=DUPLICATE_FIRST_COLUMN_FEATURE_ID'

# Use generic lists to avoid PowerShell += / PSObject scalarization.
$perSampleRows = New-Object 'System.Collections.Generic.List[object]'
$previewRows = New-Object 'System.Collections.Generic.List[object]'
$duplicateExampleRows = New-Object 'System.Collections.Generic.List[object]'
$schemaRows = New-Object 'System.Collections.Generic.List[object]'

# ------------------------------------------------------------
# Parse a count file generically.
# ------------------------------------------------------------
function Parse-D2AV2File {
    param(
        [string]$Path,
        [string]$Modality,
        [string]$SubjectId,
        [string]$GSM,
        [bool]$CapturePreview,
        [bool]$CaptureDuplicateExamples
    )

    $text = Get-D2AV2GzipText $Path
    $lines = @($text -split "`r?`n")

    $nonBlank = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($CapturePreview) {
        $previewN = [math]::Min(15,$nonBlank.Count)
        for ($i=0; $i -lt $previewN; $i++) {
            $line = [string]$nonBlank[$i]
            $fields = @($line -split "`t",-1)
            $last = if ($fields.Count -gt 0) { $fields[$fields.Count-1].Trim() } else { '' }
            [double]$tmp = 0
            $numeric = Try-D2AV2Double -Text $last -Value ([ref]$tmp)

            [void]$script:previewRows.Add([pscustomobject]@{
                modality=$Modality
                subject_id=$SubjectId
                GSM=$GSM
                preview_line_number=($i+1)
                starts_with_hash=$(if ($line.StartsWith('#')) {'YES'} else {'NO'})
                tab_column_count=$fields.Count
                last_field_numeric=$(if ($numeric) {'YES'} else {'NO'})
                line_text=$(if ($line.Length -gt 900) {$line.Substring(0,900)} else {$line})
            })
        }
    }

    $firstNonCommentSeen = $false
    $headerPresent = $false
    $headerText = ''
    $expectedColumns = $null
    $rows = New-Object 'System.Collections.Generic.List[object]'

    foreach ($lineRaw in $lines) {
        $line = [string]$lineRaw

        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('#')) { continue }

        $fields = @($line -split "`t",-1)

        if (-not $firstNonCommentSeen) {
            $firstNonCommentSeen = $true

            $last = $fields[$fields.Count-1].Trim()
            [double]$tmp = 0
            $numeric = Try-D2AV2Double -Text $last -Value ([ref]$tmp)

            if (-not $numeric) {
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
            throw ('COLUMN_COUNT_CHANGED file={0} expected={1} observed={2}' -f $Path,$expectedColumns,$fields.Count)
        }

        $lastText = $fields[$fields.Count-1].Trim()
        [double]$countValue = 0
        $ok = Try-D2AV2Double -Text $lastText -Value ([ref]$countValue)

        if (-not $ok) {
            throw ('NONNUMERIC_COUNT_IN_V2 file={0} last={1}' -f $Path,$lastText)
        }

        $firstId = $fields[0].Trim()

        # Annotation key = all non-count columns.
        $annotationFields = @()
        if ($fields.Count -gt 1) {
            for ($j=0; $j -lt ($fields.Count-1); $j++) {
                $annotationFields += [string]$fields[$j]
            }
        }

        $annotationKey = $annotationFields -join "`t"
        $fullRowKey = $fields -join "`t"

        [void]$rows.Add([pscustomobject]@{
            first_id=$firstId
            annotation_key=$annotationKey
            full_row_key=$fullRowKey
            count_value=$countValue
            fields=$fields
        })
    }

    if ($rows.Count -eq 0) {
        throw ('NO_DATA_ROWS={0}' -f $Path)
    }

    $firstGroups = @($rows | Group-Object first_id)
    $dupFirstGroups = @($firstGroups | Where-Object Count -gt 1)

    [Int64]$duplicateOccurrences = 0
    foreach ($g in $dupFirstGroups) {
        $duplicateOccurrences += ($g.Count - 1)
    }

    $annotationGroups = @($rows | Group-Object annotation_key)
    $dupAnnotationGroups = @($annotationGroups | Where-Object Count -gt 1)

    [Int64]$annotationDuplicateOccurrences = 0
    foreach ($g in $dupAnnotationGroups) {
        $annotationDuplicateOccurrences += ($g.Count - 1)
    }

    $fullGroups = @($rows | Group-Object full_row_key)
    $dupFullGroups = @($fullGroups | Where-Object Count -gt 1)

    [Int64]$fullDuplicateOccurrences = 0
    foreach ($g in $dupFullGroups) {
        $fullDuplicateOccurrences += ($g.Count - 1)
    }

    $duplicatedFirstIdsDisambiguated = 0
    $duplicatedFirstIdsNotDisambiguated = 0
    $duplicateGroupsWithDifferentCounts = 0
    $maxMultiplicity = 1

    foreach ($g in $dupFirstGroups) {
        if ($g.Count -gt $maxMultiplicity) { $maxMultiplicity = $g.Count }

        $uniqueAnnotation = @($g.Group.annotation_key | Sort-Object -Unique).Count
        $uniqueCounts = @($g.Group.count_value | Sort-Object -Unique).Count

        if ($uniqueAnnotation -eq $g.Count) {
            $duplicatedFirstIdsDisambiguated++
        }
        else {
            $duplicatedFirstIdsNotDisambiguated++
        }

        if ($uniqueCounts -gt 1) {
            $duplicateGroupsWithDifferentCounts++
        }

        if ($CaptureDuplicateExamples -and $script:duplicateExampleRows.Count -lt 250) {
            $otherAnnotationValues = @()

            foreach ($row in $g.Group) {
                if ($row.fields.Count -gt 2) {
                    $other = @()
                    for ($k=1; $k -lt ($row.fields.Count-1); $k++) {
                        $other += [string]$row.fields[$k]
                    }
                    $otherAnnotationValues += ($other -join '|')
                }
                elseif ($row.fields.Count -eq 2) {
                    $otherAnnotationValues += '<NO_ADDITIONAL_ANNOTATION_COLUMN>'
                }
            }

            [void]$script:duplicateExampleRows.Add([pscustomobject]@{
                modality=$Modality
                subject_id=$SubjectId
                GSM=$GSM
                first_id=$g.Name
                multiplicity=$g.Count
                unique_annotation_keys=$uniqueAnnotation
                unique_count_values=$uniqueCounts
                count_values=(($g.Group.count_value | ForEach-Object {[string]$_}) -join '|')
                other_annotation_values=(($otherAnnotationValues | Sort-Object -Unique) -join ' || ')
            })
        }
    }

    $firstIdSequence = @($rows.first_id)
    $firstIdSet = @($rows.first_id | Sort-Object -Unique)
    $annotationSequence = @($rows.annotation_key)
    $annotationSet = @($rows.annotation_key | Sort-Object -Unique)

    [void]$script:schemaRows.Add([pscustomobject]@{
        modality=$Modality
        subject_id=$SubjectId
        GSM=$GSM
        header_present=$(if ($headerPresent) {'YES'} else {'NO'})
        header_text=$headerText
        column_count=$expectedColumns
        data_rows=$rows.Count
        first_column_unique_ids=$firstIdSet.Count
        duplicate_first_id_groups=$dupFirstGroups.Count
        duplicate_first_id_occurrences=$duplicateOccurrences
        unique_annotation_keys=$annotationSet.Count
        duplicate_annotation_key_groups=$dupAnnotationGroups.Count
        duplicate_annotation_key_occurrences=$annotationDuplicateOccurrences
        duplicate_full_row_groups=$dupFullGroups.Count
        duplicate_full_row_occurrences=$fullDuplicateOccurrences
    })

    return [pscustomobject]@{
        modality=$Modality
        subject_id=$SubjectId
        GSM=$GSM
        file_path=$Path
        header_present=$(if ($headerPresent) {'YES'} else {'NO'})
        header_text=$headerText
        column_count=$expectedColumns
        data_rows=$rows.Count
        unique_first_ids=$firstIdSet.Count
        duplicate_first_id_groups=$dupFirstGroups.Count
        duplicate_first_id_occurrences=$duplicateOccurrences
        maximum_first_id_multiplicity=$maxMultiplicity
        duplicate_first_ids_disambiguated_by_other_annotation=$duplicatedFirstIdsDisambiguated
        duplicate_first_ids_not_disambiguated_by_other_annotation=$duplicatedFirstIdsNotDisambiguated
        duplicate_groups_with_different_count_values=$duplicateGroupsWithDifferentCounts
        unique_annotation_keys=$annotationSet.Count
        duplicate_annotation_key_groups=$dupAnnotationGroups.Count
        duplicate_annotation_key_occurrences=$annotationDuplicateOccurrences
        duplicate_full_row_groups=$dupFullGroups.Count
        duplicate_full_row_occurrences=$fullDuplicateOccurrences
        first_id_sequence_sha256=(Get-D2AV2StringHash ($firstIdSequence -join "`n"))
        first_id_set_sha256=(Get-D2AV2StringHash ($firstIdSet -join "`n"))
        annotation_sequence_sha256=(Get-D2AV2StringHash ($annotationSequence -join "`n"))
        annotation_set_sha256=(Get-D2AV2StringHash ($annotationSet -join "`n"))
    }
}

# ------------------------------------------------------------
# 1. Inspect all miRNA files.
# Representative preview/duplicate examples: one COV, P, H.
# ------------------------------------------------------------
$representativeSubjects = @()

foreach ($prefix in @('COV','P','H')) {
    $r = $mirnaInv |
        Where-Object group_prefix -eq $prefix |
        Sort-Object subject_id |
        Select-Object -First 1

    if ($null -eq $r) {
        throw ('REPRESENTATIVE_MIRNA_FILE_MISSING group={0}' -f $prefix)
    }

    $representativeSubjects += [string]$r.subject_id
}

$i = 0
foreach ($r in $mirnaInv | Sort-Object subject_id) {
    $i++

    if (($i % 12) -eq 0) {
        Write-Host ('MIRNA_DUPLICATE_DIAGNOSTIC_PROGRESS={0}/72' -f $i)
    }

    $capture = $representativeSubjects -contains [string]$r.subject_id

    $result = Parse-D2AV2File `
        -Path $r.final_path `
        -Modality 'miRNA' `
        -SubjectId $r.subject_id `
        -GSM $r.GSM `
        -CapturePreview $capture `
        -CaptureDuplicateExamples $capture

    [void]$perSampleRows.Add($result)
}

if ($perSampleRows.Count -ne 72) {
    throw ('PER_SAMPLE_DIAGNOSTIC_COUNT={0}' -f $perSampleRows.Count)
}

# ------------------------------------------------------------
# 2. Inspect representative mRNA files only as a clean-schema control.
# ------------------------------------------------------------
foreach ($prefix in @('COV','P','H')) {
    $r = $mrnaInv |
        Where-Object group_prefix -eq $prefix |
        Sort-Object subject_id |
        Select-Object -First 1

    if ($null -eq $r) {
        throw ('REPRESENTATIVE_MRNA_FILE_MISSING group={0}' -f $prefix)
    }

    [void](Parse-D2AV2File `
        -Path $r.final_path `
        -Modality 'mRNA' `
        -SubjectId $r.subject_id `
        -GSM $r.GSM `
        -CapturePreview $true `
        -CaptureDuplicateExamples $false)
}

# ------------------------------------------------------------
# 3. Cross-sample invariants.
# ------------------------------------------------------------
$columnCounts = @($perSampleRows.column_count | Sort-Object -Unique)
$rowCounts = @($perSampleRows.data_rows | Sort-Object -Unique)
$uniqueFirstCounts = @($perSampleRows.unique_first_ids | Sort-Object -Unique)
$dupGroupCounts = @($perSampleRows.duplicate_first_id_groups | Sort-Object -Unique)
$dupOccurrenceCounts = @($perSampleRows.duplicate_first_id_occurrences | Sort-Object -Unique)
$firstSetHashes = @($perSampleRows.first_id_set_sha256 | Sort-Object -Unique)
$firstSequenceHashes = @($perSampleRows.first_id_sequence_sha256 | Sort-Object -Unique)
$annotationSetHashes = @($perSampleRows.annotation_set_sha256 | Sort-Object -Unique)
$annotationSequenceHashes = @($perSampleRows.annotation_sequence_sha256 | Sort-Object -Unique)

[Int64]$allDupGroups = (($perSampleRows | Measure-Object duplicate_first_id_groups -Sum).Sum)
[Int64]$allDupOccurrences = (($perSampleRows | Measure-Object duplicate_first_id_occurrences -Sum).Sum)
[Int64]$allDisambiguatedGroups = (($perSampleRows | Measure-Object duplicate_first_ids_disambiguated_by_other_annotation -Sum).Sum)
[Int64]$allNotDisambiguatedGroups = (($perSampleRows | Measure-Object duplicate_first_ids_not_disambiguated_by_other_annotation -Sum).Sum)
[Int64]$allDupAnnotationOccurrences = (($perSampleRows | Measure-Object duplicate_annotation_key_occurrences -Sum).Sum)
[Int64]$allFullRowDupOccurrences = (($perSampleRows | Measure-Object duplicate_full_row_occurrences -Sum).Sum)

$structureClass = 'REVIEW_REQUIRED'

if ($allDupOccurrences -gt 0 -and
    $allDisambiguatedGroups -eq $allDupGroups -and
    $allNotDisambiguatedGroups -eq 0 -and
    $allDupAnnotationOccurrences -eq 0) {

    $structureClass = 'FIRST_COLUMN_LABEL_REPEATS_BUT_FULL_ANNOTATION_KEY_IS_UNIQUE'
}
elseif ($allDupOccurrences -gt 0 -and
        $allDupAnnotationOccurrences -gt 0 -and
        $allFullRowDupOccurrences -eq 0) {

    $structureClass = 'DUPLICATE_ANNOTATION_KEYS_WITH_DIFFERENT_COUNTS'
}
elseif ($allFullRowDupOccurrences -gt 0) {
    $structureClass = 'EXACT_DUPLICATE_FULL_ROWS_PRESENT'
}
elseif ($allDupOccurrences -gt 0 -and $columnCounts.Count -eq 1 -and $columnCounts[0] -eq 2) {
    $structureClass = 'TWO_COLUMN_TABLE_WITH_REPEATED_FEATURE_IDS_REQUIRES_AGGREGATION_POLICY'
}

$crossRows = @(
    [pscustomobject]@{metric='unique_column_count_patterns';value=$columnCounts.Count;details=($columnCounts -join '|')},
    [pscustomobject]@{metric='unique_data_row_counts';value=$rowCounts.Count;details=($rowCounts -join '|')},
    [pscustomobject]@{metric='unique_first_id_count_patterns';value=$uniqueFirstCounts.Count;details=($uniqueFirstCounts -join '|')},
    [pscustomobject]@{metric='unique_duplicate_group_count_patterns';value=$dupGroupCounts.Count;details=($dupGroupCounts -join '|')},
    [pscustomobject]@{metric='unique_duplicate_occurrence_patterns';value=$dupOccurrenceCounts.Count;details=($dupOccurrenceCounts -join '|')},
    [pscustomobject]@{metric='unique_first_id_set_hashes';value=$firstSetHashes.Count;details=''},
    [pscustomobject]@{metric='unique_first_id_sequence_hashes';value=$firstSequenceHashes.Count;details=''},
    [pscustomobject]@{metric='unique_annotation_set_hashes';value=$annotationSetHashes.Count;details=''},
    [pscustomobject]@{metric='unique_annotation_sequence_hashes';value=$annotationSequenceHashes.Count;details=''},
    [pscustomobject]@{metric='total_duplicate_first_id_groups';value=$allDupGroups;details=''},
    [pscustomobject]@{metric='total_duplicate_first_id_occurrences';value=$allDupOccurrences;details=''},
    [pscustomobject]@{metric='duplicate_groups_disambiguated_by_other_annotation';value=$allDisambiguatedGroups;details=''},
    [pscustomobject]@{metric='duplicate_groups_not_disambiguated_by_other_annotation';value=$allNotDisambiguatedGroups;details=''},
    [pscustomobject]@{metric='duplicate_annotation_key_occurrences';value=$allDupAnnotationOccurrences;details=''},
    [pscustomobject]@{metric='exact_duplicate_full_row_occurrences';value=$allFullRowDupOccurrences;details=''},
    [pscustomobject]@{metric='structure_class';value='';details=$structureClass}
)

# ------------------------------------------------------------
# 4. Export.
# ------------------------------------------------------------
$perSampleRows |
    Sort-Object subject_id |
    Export-Csv -LiteralPath $PerSampleCsv -NoTypeInformation -Encoding UTF8

$previewRows |
    Export-Csv -LiteralPath $PreviewCsv -NoTypeInformation -Encoding UTF8

$duplicateExampleRows |
    Export-Csv -LiteralPath $DupExamplesCsv -NoTypeInformation -Encoding UTF8

$schemaRows |
    Sort-Object modality,subject_id |
    Export-Csv -LiteralPath $SchemaCsv -NoTypeInformation -Encoding UTF8

$crossRows |
    Export-Csv -LiteralPath $CrossSampleCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 5. Terminal evidence.
# ------------------------------------------------------------
Write-Host ''
Write-Host '=== REPRESENTATIVE RAW PREVIEW ==='
foreach ($r in $previewRows) {
    Write-Host ('PREVIEW={0}|{1}|line={2}|cols={3}|last_numeric={4}|{5}' -f `
        $r.modality,$r.subject_id,$r.preview_line_number,$r.tab_column_count,$r.last_field_numeric,$r.line_text)
}

Write-Host ''
Write-Host '=== REPRESENTATIVE miRNA DUPLICATE GROUPS ==='
foreach ($r in $duplicateExampleRows | Select-Object -First 50) {
    Write-Host ('DUPLICATE={0}|feature={1}|multiplicity={2}|unique_annotation_keys={3}|unique_counts={4}|other={5}' -f `
        $r.subject_id,$r.first_id,$r.multiplicity,$r.unique_annotation_keys,$r.unique_count_values,$r.other_annotation_values)
}

Write-Host ''
Write-Host ('MIRNA_COLUMN_COUNT_PATTERNS={0}' -f ($columnCounts -join '|'))
Write-Host ('MIRNA_DATA_ROW_COUNT_PATTERNS={0}' -f ($rowCounts -join '|'))
Write-Host ('MIRNA_UNIQUE_FIRST_ID_COUNT_PATTERNS={0}' -f ($uniqueFirstCounts -join '|'))
Write-Host ('MIRNA_DUPLICATE_GROUP_COUNT_PATTERNS={0}' -f ($dupGroupCounts -join '|'))
Write-Host ('MIRNA_DUPLICATE_OCCURRENCE_PATTERNS={0}' -f ($dupOccurrenceCounts -join '|'))
Write-Host ('MIRNA_FIRST_ID_SET_HASH_COUNT={0}' -f $firstSetHashes.Count)
Write-Host ('MIRNA_FIRST_ID_SEQUENCE_HASH_COUNT={0}' -f $firstSequenceHashes.Count)
Write-Host ('MIRNA_ANNOTATION_SET_HASH_COUNT={0}' -f $annotationSetHashes.Count)
Write-Host ('MIRNA_ANNOTATION_SEQUENCE_HASH_COUNT={0}' -f $annotationSequenceHashes.Count)
Write-Host ('TOTAL_DUPLICATE_FIRST_ID_GROUPS={0}' -f $allDupGroups)
Write-Host ('TOTAL_DUPLICATE_FIRST_ID_OCCURRENCES={0}' -f $allDupOccurrences)
Write-Host ('DUPLICATE_GROUPS_DISAMBIGUATED_BY_OTHER_ANNOTATION={0}' -f $allDisambiguatedGroups)
Write-Host ('DUPLICATE_GROUPS_NOT_DISAMBIGUATED_BY_OTHER_ANNOTATION={0}' -f $allNotDisambiguatedGroups)
Write-Host ('DUPLICATE_ANNOTATION_KEY_OCCURRENCES={0}' -f $allDupAnnotationOccurrences)
Write-Host ('EXACT_DUPLICATE_FULL_ROW_OCCURRENCES={0}' -f $allFullRowDupOccurrences)
Write-Host ('MIRNA_DUPLICATE_STRUCTURE_CLASS={0}' -f $structureClass)

$next = if ($structureClass -eq 'REVIEW_REQUIRED') {
    'D2A_V3_TARGETED_STRUCTURE_REVIEW'
}
else {
    'D2B_STRUCTURE_AWARE_COUNT_AUDIT_CORRECTION'
}

@(
    '=== GSE243219 PHASE D2A-V2 SUMMARY ===',
    'PHASE_D2A_V2_STATUS=PASS',
    'MODE=READ_ONLY_DIAGNOSTIC',
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
    'KNOWN_FAILURE_STATE_RECERTIFIED=YES',
    'FAILED_MODALITY=miRNA',
    'FAILED_MRNA_FILES=0',
    'FAILED_MIRNA_FILES=72',
    'ONLY_FAILURE_CLASS=DUPLICATE_FIRST_COLUMN_FEATURE_ID',
    ('MIRNA_COLUMN_COUNT_PATTERNS={0}' -f ($columnCounts -join '|')),
    ('MIRNA_DATA_ROW_COUNT_PATTERNS={0}' -f ($rowCounts -join '|')),
    ('MIRNA_UNIQUE_FIRST_ID_COUNT_PATTERNS={0}' -f ($uniqueFirstCounts -join '|')),
    ('MIRNA_DUPLICATE_GROUP_COUNT_PATTERNS={0}' -f ($dupGroupCounts -join '|')),
    ('MIRNA_DUPLICATE_OCCURRENCE_PATTERNS={0}' -f ($dupOccurrenceCounts -join '|')),
    ('MIRNA_FIRST_ID_SET_HASH_COUNT={0}' -f $firstSetHashes.Count),
    ('MIRNA_FIRST_ID_SEQUENCE_HASH_COUNT={0}' -f $firstSequenceHashes.Count),
    ('MIRNA_ANNOTATION_SET_HASH_COUNT={0}' -f $annotationSetHashes.Count),
    ('MIRNA_ANNOTATION_SEQUENCE_HASH_COUNT={0}' -f $annotationSequenceHashes.Count),
    ('TOTAL_DUPLICATE_FIRST_ID_GROUPS={0}' -f $allDupGroups),
    ('TOTAL_DUPLICATE_FIRST_ID_OCCURRENCES={0}' -f $allDupOccurrences),
    ('DUPLICATE_GROUPS_DISAMBIGUATED_BY_OTHER_ANNOTATION={0}' -f $allDisambiguatedGroups),
    ('DUPLICATE_GROUPS_NOT_DISAMBIGUATED_BY_OTHER_ANNOTATION={0}' -f $allNotDisambiguatedGroups),
    ('DUPLICATE_ANNOTATION_KEY_OCCURRENCES={0}' -f $allDupAnnotationOccurrences),
    ('EXACT_DUPLICATE_FULL_ROW_OCCURRENCES={0}' -f $allFullRowDupOccurrences),
    ('MIRNA_DUPLICATE_STRUCTURE_CLASS={0}' -f $structureClass),
    'READY_FOR_FEATURE_AGGREGATION=NO',
    'READY_FOR_MATRIX_CONSTRUCTION=NO',
    'READY_FOR_NORMALIZATION=NO',
    'READY_FOR_DE=NO',
    ('NEXT_PHASE={0}' -f $next),
    'STOP=YES'
) | Set-Content -LiteralPath $SummaryTxt -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $SummaryTxt
Write-Host ''
Write-Host ('D2A_V2_PER_SAMPLE_STRUCTURE={0}' -f $PerSampleCsv)
Write-Host ('D2A_V2_REPRESENTATIVE_PREVIEW={0}' -f $PreviewCsv)
Write-Host ('D2A_V2_DUPLICATE_EXAMPLES={0}' -f $DupExamplesCsv)
Write-Host ('D2A_V2_SCHEMA_SUMMARY={0}' -f $SchemaCsv)
Write-Host ('D2A_V2_CROSS_SAMPLE_SUMMARY={0}' -f $CrossSampleCsv)
Write-Host ('PHASE_D2A_V2_SUMMARY={0}' -f $SummaryTxt)
Write-Host 'STEP_GSE243219_PHASE_D2A_V2=PASS'
Write-Host 'STOP=YES'
