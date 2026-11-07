$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219 NEW PROJECT
# PHASE D1 — PROCESSED DATA ACQUISITION + INTEGRITY AUDIT
#
# Authorized:
#   - Download GEO-supplied count TAR archives
#   - Download authoritative GEO family SOFT metadata
#   - SHA256 all downloads
#   - Safe TAR extraction
#   - GZIP integrity verification
#   - Filename/sample-set inventory
#
# Not authorized:
#   - Matrix construction
#   - Normalization
#   - Differential expression
#   - Biological sample exclusion
#   - Network construction
#   - A-CLA
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$AcqRoot = Join-Path $Project '01_PROCESSED_DATA_ACQUISITION'
$MetaRoot = Join-Path $Project '00_PROTOCOL_AND_METADATA'

$DownloadsDir = Join-Path $AcqRoot 'downloads'
$ExtractRoot = Join-Path $AcqRoot 'extracted'
$AuditDir = Join-Path $AcqRoot 'audit'
$MrnaFinal = Join-Path $ExtractRoot 'GSE243217_mRNA'
$MirnaFinal = Join-Path $ExtractRoot 'GSE243218_miRNA'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D1_{0}' -f $Stamp)
$StageRoot = Join-Path $AcqRoot ('_D1_STAGING_{0}' -f $Stamp)
$MrnaStage = Join-Path $StageRoot 'GSE243217_mRNA'
$MirnaStage = Join-Path $StageRoot 'GSE243218_miRNA'

New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

Write-Host '=== GSE243219 PHASE D1-V2 — PROCESSED DATA ACQUISITION + INTEGRITY AUDIT ==='
Write-Host 'MODE=ACQUISITION_AND_INTEGRITY_ONLY'
Write-Host 'RAW_FASTQ_DOWNLOADED=NO'
Write-Host 'ALIGNMENT_EXECUTED=NO'
Write-Host 'MATRIX_CONSTRUCTION_EXECUTED=NO'
Write-Host 'NORMALIZATION_EXECUTED=NO'
Write-Host 'DE_EXECUTED=NO'
Write-Host 'NETWORK_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('PROJECT_ROOT={0}' -f $Project)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

foreach ($p in @($Project,$AcqRoot,$MetaRoot)) {
    if (-not (Test-Path -LiteralPath $p -PathType Container)) {
        throw ('REQUIRED_DIRECTORY_MISSING={0}' -f $p)
    }
}

$D0Status = Join-Path $MetaRoot 'PROJECT_STATUS.txt'
if (-not (Test-Path -LiteralPath $D0Status -PathType Leaf)) {
    throw ('D0_STATUS_MISSING={0}' -f $D0Status)
}

$d0 = Get-Content -LiteralPath $D0Status -Raw
foreach ($tok in @(
    'PHASE_D0_PROJECT_INITIALIZATION=PASS',
    'GEO_DATA_DOWNLOADED=NO',
    'READY_FOR_PHASE_D1_PROCESSED_DATA_ACQUISITION=YES'
)) {
    if ($d0 -notmatch [regex]::Escape($tok)) {
        throw ('D0_AUTHORIZATION_TOKEN_MISSING={0}' -f $tok)
    }
}

# Acquisition target directories must not already contain final extracted data.
foreach ($p in @($MrnaFinal,$MirnaFinal)) {
    if (Test-Path -LiteralPath $p -PathType Container) {
        $existing = @(Get-ChildItem -LiteralPath $p -File -Recurse -Force -ErrorAction SilentlyContinue)
        if ($existing.Count -gt 0) {
            throw ('FINAL_EXTRACTION_DIRECTORY_ALREADY_NONEMPTY={0}|files={1}' -f $p,$existing.Count)
        }
    }
}

if (Test-Path -LiteralPath $StageRoot) {
    throw ('D1_STAGING_ROOT_ALREADY_EXISTS={0}' -f $StageRoot)
}

New-Item -ItemType Directory -Path $DownloadsDir -Force | Out-Null
New-Item -ItemType Directory -Path $ExtractRoot -Force | Out-Null
New-Item -ItemType Directory -Path $AuditDir -Force | Out-Null
New-Item -ItemType Directory -Path $MrnaStage -Force | Out-Null
New-Item -ItemType Directory -Path $MirnaStage -Force | Out-Null

function Get-D1SHA256 {
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Download-D1File {
    param(
        [string]$Url,
        [string]$Destination,
        [Int64]$MinimumBytes = 1,
        [int]$Retries = 4
    )

    if (Test-Path -LiteralPath $Destination -PathType Leaf) {
        $existing = Get-Item -LiteralPath $Destination
        if ([Int64]$existing.Length -lt $MinimumBytes) {
            throw ('EXISTING_DOWNLOAD_TOO_SMALL={0}|bytes={1}' -f $Destination,$existing.Length)
        }
        Write-Host ('DOWNLOAD_REUSED_EXISTING={0}|bytes={1}' -f $Destination,$existing.Length)
        return
    }

    $partial = $Destination + '.partial'
    if (Test-Path -LiteralPath $partial) {
        Remove-Item -LiteralPath $partial -Force
    }

    $lastError = ''
    for ($attempt=1; $attempt -le $Retries; $attempt++) {
        try {
            Write-Host ('DOWNLOAD_ATTEMPT={0}/{1}|URL={2}' -f $attempt,$Retries,$Url)

            Invoke-WebRequest `
                -Uri $Url `
                -OutFile $partial `
                -UseBasicParsing `
                -MaximumRedirection 10 `
                -TimeoutSec 180

            if (-not (Test-Path -LiteralPath $partial -PathType Leaf)) {
                throw 'PARTIAL_DOWNLOAD_FILE_NOT_CREATED'
            }

            $item = Get-Item -LiteralPath $partial
            if ([Int64]$item.Length -lt $MinimumBytes) {
                throw ('DOWNLOADED_FILE_TOO_SMALL bytes={0} minimum={1}' -f $item.Length,$MinimumBytes)
            }

            Move-Item -LiteralPath $partial -Destination $Destination
            Write-Host ('DOWNLOAD_PASS={0}|bytes={1}' -f $Destination,$item.Length)
            return
        }
        catch {
            $lastError = $_.Exception.Message
            if (Test-Path -LiteralPath $partial) {
                Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue
            }

            if ($attempt -lt $Retries) {
                Start-Sleep -Seconds ([math]::Min(5*$attempt,15))
            }
        }
    }

    throw ('DOWNLOAD_FAILED url={0} error={1}' -f $Url,$lastError)
}

function Test-D1GZip {
    param([string]$Path)

    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $gz = New-Object System.IO.Compression.GZipStream(
            $fs,
            [System.IO.Compression.CompressionMode]::Decompress
        )

        try {
            $buffer = New-Object byte[] 65536
            [Int64]$total = 0
            while (($n = $gz.Read($buffer,0,$buffer.Length)) -gt 0) {
                $total += $n
            }
            return $total
        }
        finally {
            $gz.Dispose()
        }
    }
    finally {
        $fs.Dispose()
    }
}

function Read-D1GZipText {
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

function Assert-SafeTarAndExtract {
    param(
        [string]$TarPath,
        [string]$Destination,
        [string]$ExpectedSuffix,
        [int]$ExpectedFileCount
    )

    $entries = @(& tar.exe -tf $TarPath)
    if ($LASTEXITCODE -ne 0) {
        throw ('TAR_LIST_FAILED={0}|exit={1}' -f $TarPath,$LASTEXITCODE)
    }

    $fileEntries = @()

    foreach ($rawEntry in $entries) {
        $entry = ([string]$rawEntry).Trim()
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }

        $norm = $entry -replace '\\','/'

        if ($norm.StartsWith('/') -or
            $norm -match '^[A-Za-z]:' -or
            $norm -match '(^|/)\.\.(/|$)') {
            throw ('UNSAFE_TAR_ENTRY={0}|archive={1}' -f $entry,$TarPath)
        }

        if ($norm.EndsWith('/')) { continue }

        if (-not $norm.ToLowerInvariant().EndsWith($ExpectedSuffix.ToLowerInvariant())) {
            throw ('UNEXPECTED_TAR_FILE_TYPE={0}|expected_suffix={1}' -f $entry,$ExpectedSuffix)
        }

        $fileEntries += $entry
    }

    if ($fileEntries.Count -ne $ExpectedFileCount) {
        throw ('TAR_FILE_COUNT_MISMATCH archive={0} expected={1} observed={2}' -f $TarPath,$ExpectedFileCount,$fileEntries.Count)
    }

    & tar.exe -xf $TarPath -C $Destination
    if ($LASTEXITCODE -ne 0) {
        throw ('TAR_EXTRACTION_FAILED={0}|exit={1}' -f $TarPath,$LASTEXITCODE)
    }

    return $fileEntries
}

function Build-D1Inventory {
    param(
        [string]$Root,
        [string]$Modality
    )

    $files = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction Stop |
        Where-Object { $_.Name.ToLowerInvariant().EndsWith('.txt.gz') })

    $rows = @()

    foreach ($f in $files) {
        if ($Modality -eq 'mRNA') {
            $m = [regex]::Match(
                $f.Name,
                '^(?<gsm>GSM\d+)_(?<subject>(?:COV|P|H)\d+)_raw_count\.txt\.gz$',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
        }
        else {
            $m = [regex]::Match(
                $f.Name,
                '^(?<gsm>GSM\d+)_(?<subject>(?:COV|P|H)\d+)_COUNT\.txt\.gz$',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
        }

        if (-not $m.Success) {
            throw ('UNEXPECTED_SAMPLE_FILENAME modality={0} file={1}' -f $Modality,$f.Name)
        }

        $subject = $m.Groups['subject'].Value.ToUpperInvariant()
        $group = if ($subject.StartsWith('COV')) {
            'COV'
        }
        elseif ($subject.StartsWith('P')) {
            'P'
        }
        elseif ($subject.StartsWith('H')) {
            'H'
        }
        else {
            'UNKNOWN'
        }

        [Int64]$uncompressed = Test-D1GZip $f.FullName

        if ($uncompressed -le 0) {
            throw ('GZIP_DECOMPRESSED_EMPTY modality={0} file={1}' -f $Modality,$f.FullName)
        }

        $rows += [pscustomobject]@{
            modality=$Modality
            GSM=$m.Groups['gsm'].Value.ToUpperInvariant()
            subject_id=$subject
            group_prefix=$group
            filename=$f.Name
            full_path=$f.FullName
            compressed_bytes=[Int64]$f.Length
            uncompressed_bytes=$uncompressed
            SHA256=(Get-D1SHA256 $f.FullName)
            gzip_integrity='PASS'
        }
    }

    return @($rows)
}

function Parse-D1SoftSummary {
    param(
        [string]$SoftGz,
        [string]$Modality
    )

    $text = Read-D1GZipText $SoftGz
    $sampleMatches = [regex]::Matches($text,'(?m)^\^SAMPLE = (?<gsm>GSM\d+)\s*$')
    $titleMatches = [regex]::Matches($text,'(?m)^!Sample_title = (?<title>.+?)\s*$')

    $titles = @()
    foreach ($m in $titleMatches) {
        $title = $m.Groups['title'].Value.Trim()

        $s = [regex]::Match(
            $title,
            '^(?<subject>(?:COV|P|H)\d+)\s+\(',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if ($s.Success) {
            $subject = $s.Groups['subject'].Value.ToUpperInvariant()
            $group = if ($subject.StartsWith('COV')) {'COV'} elseif ($subject.StartsWith('P')) {'P'} elseif ($subject.StartsWith('H')) {'H'} else {'UNKNOWN'}

            $titles += [pscustomobject]@{
                modality=$Modality
                subject_id=$subject
                group_prefix=$group
                sample_title=$title
            }
        }
    }

    return [pscustomobject]@{
        modality=$Modality
        soft_sample_records=$sampleMatches.Count
        parsed_subject_titles=$titles.Count
        COV=@($titles | Where-Object group_prefix -eq 'COV').Count
        P=@($titles | Where-Object group_prefix -eq 'P').Count
        H=@($titles | Where-Object group_prefix -eq 'H').Count
        subjects=$titles
    }
}

# ------------------------------------------------------------
# 1. Authoritative NCBI GEO download registry
# ------------------------------------------------------------
# Compressed family-SOFT files are allowed to be small.
# Authenticity/integrity is established later by successful GZIP decompression,
# exactly 72 ^SAMPLE records, and exact COV/P/H subject-title counts.
$downloadSpecs = @(
    [pscustomobject]@{
        accession='GSE243217'
        role='mRNA_count_archive'
        url='https://ftp.ncbi.nlm.nih.gov/geo/series/GSE243nnn/GSE243217/suppl/GSE243217_RAW.tar'
        destination=(Join-Path $DownloadsDir 'GSE243217_RAW.tar')
        minimum_bytes=5000000
    },
    [pscustomobject]@{
        accession='GSE243218'
        role='miRNA_count_archive'
        url='https://ftp.ncbi.nlm.nih.gov/geo/series/GSE243nnn/GSE243218/suppl/GSE243218_RAW.tar'
        destination=(Join-Path $DownloadsDir 'GSE243218_RAW.tar')
        minimum_bytes=800000
    },
    [pscustomobject]@{
        accession='GSE243217'
        role='family_SOFT_metadata'
        url='https://ftp.ncbi.nlm.nih.gov/geo/series/GSE243nnn/GSE243217/soft/GSE243217_family.soft.gz'
        destination=(Join-Path $DownloadsDir 'GSE243217_family.soft.gz')
        minimum_bytes=1000
    },
    [pscustomobject]@{
        accession='GSE243218'
        role='family_SOFT_metadata'
        url='https://ftp.ncbi.nlm.nih.gov/geo/series/GSE243nnn/GSE243218/soft/GSE243218_family.soft.gz'
        destination=(Join-Path $DownloadsDir 'GSE243218_family.soft.gz')
        minimum_bytes=1000
    }
)

foreach ($d in $downloadSpecs) {
    Download-D1File `
        -Url $d.url `
        -Destination $d.destination `
        -MinimumBytes ([Int64]$d.minimum_bytes)
}

# ------------------------------------------------------------
# 2. Download manifest + archive hashes
# ------------------------------------------------------------
$downloadRows = @()

foreach ($d in $downloadSpecs) {
    $item = Get-Item -LiteralPath $d.destination

    $downloadRows += [pscustomobject]@{
        accession=$d.accession
        role=$d.role
        source_url=$d.url
        local_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D1SHA256 $item.FullName)
    }
}

$DownloadManifest = Join-Path $AuditDir 'D1_DOWNLOAD_SHA256_MANIFEST.csv'
$downloadRows | Export-Csv -LiteralPath $DownloadManifest -NoTypeInformation -Encoding UTF8

$MrnaTar = Join-Path $DownloadsDir 'GSE243217_RAW.tar'
$MirnaTar = Join-Path $DownloadsDir 'GSE243218_RAW.tar'
$MrnaSoft = Join-Path $DownloadsDir 'GSE243217_family.soft.gz'
$MirnaSoft = Join-Path $DownloadsDir 'GSE243218_family.soft.gz'

# ------------------------------------------------------------
# 3. GZIP-integrity test family SOFT metadata
# ------------------------------------------------------------
$mrnaSoftBytes = Test-D1GZip $MrnaSoft
$mirnaSoftBytes = Test-D1GZip $MirnaSoft

if ($mrnaSoftBytes -le 0 -or $mirnaSoftBytes -le 0) {
    throw 'SOFT_GZIP_INTEGRITY_FAILURE'
}

Write-Host ('MRNA_SOFT_GZIP_INTEGRITY=PASS|uncompressed_bytes={0}' -f $mrnaSoftBytes)
Write-Host ('MIRNA_SOFT_GZIP_INTEGRITY=PASS|uncompressed_bytes={0}' -f $mirnaSoftBytes)

# ------------------------------------------------------------
# 4. Safe TAR audit and extraction into staging
# ------------------------------------------------------------
$mrnaTarEntries = Assert-SafeTarAndExtract `
    -TarPath $MrnaTar `
    -Destination $MrnaStage `
    -ExpectedSuffix '.txt.gz' `
    -ExpectedFileCount 72

$mirnaTarEntries = Assert-SafeTarAndExtract `
    -TarPath $MirnaTar `
    -Destination $MirnaStage `
    -ExpectedSuffix '.txt.gz' `
    -ExpectedFileCount 72

Write-Host ('MRNA_TAR_FILE_ENTRIES={0}' -f $mrnaTarEntries.Count)
Write-Host ('MIRNA_TAR_FILE_ENTRIES={0}' -f $mirnaTarEntries.Count)

# ------------------------------------------------------------
# 5. Extracted-file inventories and GZIP integrity
# ------------------------------------------------------------
$mrnaRows = @(Build-D1Inventory -Root $MrnaStage -Modality 'mRNA')
$mirnaRows = @(Build-D1Inventory -Root $MirnaStage -Modality 'miRNA')

if ($mrnaRows.Count -ne 72) {
    throw ('MRNA_EXTRACTED_FILE_COUNT_MISMATCH expected=72 observed={0}' -f $mrnaRows.Count)
}
if ($mirnaRows.Count -ne 72) {
    throw ('MIRNA_EXTRACTED_FILE_COUNT_MISMATCH expected=72 observed={0}' -f $mirnaRows.Count)
}

foreach ($x in @(
    [pscustomobject]@{name='mRNA';rows=$mrnaRows},
    [pscustomobject]@{name='miRNA';rows=$mirnaRows}
)) {
    $cov = @($x.rows | Where-Object group_prefix -eq 'COV').Count
    $p = @($x.rows | Where-Object group_prefix -eq 'P').Count
    $h = @($x.rows | Where-Object group_prefix -eq 'H').Count

    if ($cov -ne 35 -or $p -ne 22 -or $h -ne 15) {
        throw ('FILENAME_GROUP_COUNT_MISMATCH modality={0} COV={1} P={2} H={3}' -f $x.name,$cov,$p,$h)
    }

    if (@($x.rows | Group-Object GSM | Where-Object Count -gt 1).Count -gt 0) {
        throw ('DUPLICATE_GSM_IN_EXTRACTED_FILES modality={0}' -f $x.name)
    }

    if (@($x.rows | Group-Object subject_id | Where-Object Count -gt 1).Count -gt 0) {
        throw ('DUPLICATE_SUBJECT_IN_EXTRACTED_FILES modality={0}' -f $x.name)
    }

    Write-Host ('FILENAME_GROUP_COUNTS={0}|COV={1}|P={2}|H={3}' -f $x.name,$cov,$p,$h)
}

# ------------------------------------------------------------
# 6. Filename subject-set comparison across modalities
# ------------------------------------------------------------
$mrnaSubjects = @($mrnaRows.subject_id | Sort-Object -Unique)
$mirnaSubjects = @($mirnaRows.subject_id | Sort-Object -Unique)

$allSubjects = @($mrnaSubjects + $mirnaSubjects | Sort-Object -Unique)
$subjectRows = @()

foreach ($s in $allSubjects) {
    $inM = $mrnaSubjects -contains $s
    $inMi = $mirnaSubjects -contains $s

    $subjectRows += [pscustomobject]@{
        subject_id=$s
        in_mRNA=$(if ($inM) {'YES'} else {'NO'})
        in_miRNA=$(if ($inMi) {'YES'} else {'NO'})
        filename_subject_pairable=$(if ($inM -and $inMi) {'YES'} else {'NO'})
    }
}

$unpairedByFilename = @($subjectRows | Where-Object filename_subject_pairable -ne 'YES')
if ($subjectRows.Count -ne 72 -or $unpairedByFilename.Count -ne 0) {
    throw ('FILENAME_SUBJECT_SET_MISMATCH total_union={0} unpaired={1}' -f $subjectRows.Count,$unpairedByFilename.Count)
}

Write-Host 'FILENAME_SUBJECT_SET_MATCH=YES'
Write-Host 'FILENAME_PAIRABLE_SUBJECTS=72'

# ------------------------------------------------------------
# 7. SOFT metadata sample-count audit
# ------------------------------------------------------------
$mrnaSoftSummary = Parse-D1SoftSummary -SoftGz $MrnaSoft -Modality 'mRNA'
$mirnaSoftSummary = Parse-D1SoftSummary -SoftGz $MirnaSoft -Modality 'miRNA'

foreach ($s in @($mrnaSoftSummary,$mirnaSoftSummary)) {
    if ($s.soft_sample_records -ne 72) {
        throw ('SOFT_SAMPLE_RECORD_COUNT_MISMATCH modality={0} observed={1}' -f $s.modality,$s.soft_sample_records)
    }

    if ($s.parsed_subject_titles -ne 72 -or
        $s.COV -ne 35 -or
        $s.P -ne 22 -or
        $s.H -ne 15) {
        throw ('SOFT_TITLE_GROUP_COUNT_MISMATCH modality={0} parsed={1} COV={2} P={3} H={4}' -f `
            $s.modality,$s.parsed_subject_titles,$s.COV,$s.P,$s.H)
    }

    Write-Host ('SOFT_METADATA_COUNTS={0}|samples={1}|COV={2}|P={3}|H={4}' -f `
        $s.modality,$s.soft_sample_records,$s.COV,$s.P,$s.H)
}

# SOFT subject titles must match archive filename subject sets.
$mrnaSoftSubjects = @($mrnaSoftSummary.subjects.subject_id | Sort-Object -Unique)
$mirnaSoftSubjects = @($mirnaSoftSummary.subjects.subject_id | Sort-Object -Unique)

if (@(Compare-Object $mrnaSubjects $mrnaSoftSubjects).Count -ne 0) {
    throw 'MRNA_FILENAME_VS_SOFT_SUBJECT_SET_MISMATCH'
}
if (@(Compare-Object $mirnaSubjects $mirnaSoftSubjects).Count -ne 0) {
    throw 'MIRNA_FILENAME_VS_SOFT_SUBJECT_SET_MISMATCH'
}

Write-Host 'MRNA_FILENAME_VS_SOFT_SUBJECT_SET_MATCH=YES'
Write-Host 'MIRNA_FILENAME_VS_SOFT_SUBJECT_SET_MATCH=YES'

# ------------------------------------------------------------
# 8. Commit staged extracted files only after complete audit
# ------------------------------------------------------------
foreach ($final in @($MrnaFinal,$MirnaFinal)) {
    if (Test-Path -LiteralPath $final) {
        $items = @(Get-ChildItem -LiteralPath $final -Force -ErrorAction SilentlyContinue)
        if ($items.Count -gt 0) {
            throw ('FINAL_EXTRACTION_PATH_NOT_EMPTY_AT_COMMIT={0}' -f $final)
        }
        Remove-Item -LiteralPath $final -Force -Recurse
    }
}

Move-Item -LiteralPath $MrnaStage -Destination $MrnaFinal
Move-Item -LiteralPath $MirnaStage -Destination $MirnaFinal

# Remove only empty D1 staging root.
$stageFiles = @(Get-ChildItem -LiteralPath $StageRoot -File -Recurse -Force -ErrorAction SilentlyContinue)
if ($stageFiles.Count -gt 0) {
    throw ('D1_STAGING_FILES_REMAIN_AFTER_COMMIT={0}' -f $stageFiles.Count)
}

if (Test-Path -LiteralPath $StageRoot) {
    Remove-Item -LiteralPath $StageRoot -Recurse -Force
}
if (Test-Path -LiteralPath $StageRoot) {
    throw 'D1_STAGING_ROOT_REMOVAL_FAILED'
}

# Rebind inventory paths to final locations and re-hash final copies.
function Build-FinalD1Inventory {
    param(
        [array]$Rows,
        [string]$FinalRoot
    )

    $out = @()
    foreach ($r in $Rows) {
        $finalPath = Join-Path $FinalRoot $r.filename

        if (-not (Test-Path -LiteralPath $finalPath -PathType Leaf)) {
            # TARs might contain safe subdirectories. Resolve by filename if needed.
            $matches = @(Get-ChildItem -LiteralPath $FinalRoot -File -Recurse -Force |
                Where-Object { $_.Name -ceq $r.filename })
            if ($matches.Count -ne 1) {
                throw ('FINAL_EXTRACTED_FILE_RESOLUTION_FAILURE filename={0} matches={1}' -f $r.filename,$matches.Count)
            }
            $finalPath = $matches[0].FullName
        }

        $item = Get-Item -LiteralPath $finalPath
        $hash = Get-D1SHA256 $finalPath

        if ([Int64]$item.Length -ne [Int64]$r.compressed_bytes -or
            $hash -ne $r.SHA256) {
            throw ('FINAL_EXTRACTED_HASH_OR_SIZE_MISMATCH={0}' -f $finalPath)
        }

        $out += [pscustomobject]@{
            modality=$r.modality
            GSM=$r.GSM
            subject_id=$r.subject_id
            group_prefix=$r.group_prefix
            filename=$r.filename
            final_path=$finalPath
            compressed_bytes=[Int64]$item.Length
            uncompressed_bytes=[Int64]$r.uncompressed_bytes
            SHA256=$hash
            gzip_integrity='PASS'
        }
    }
    return @($out)
}

$mrnaFinalRows = @(Build-FinalD1Inventory -Rows $mrnaRows -FinalRoot $MrnaFinal)
$mirnaFinalRows = @(Build-FinalD1Inventory -Rows $mirnaRows -FinalRoot $MirnaFinal)

# ------------------------------------------------------------
# 9. Write D1 audit outputs
# ------------------------------------------------------------
$MrnaInventory = Join-Path $AuditDir 'D1_GSE243217_MRNA_FILE_INVENTORY.csv'
$MirnaInventory = Join-Path $AuditDir 'D1_GSE243218_MIRNA_FILE_INVENTORY.csv'
$SubjectComparison = Join-Path $AuditDir 'D1_CROSS_MODALITY_FILENAME_SUBJECT_COMPARISON.csv'
$SoftSummaryCsv = Join-Path $AuditDir 'D1_SOFT_METADATA_SUMMARY.csv'
$StatusPath = Join-Path $AuditDir 'D1_ACQUISITION_STATUS.txt'

$mrnaFinalRows | Sort-Object subject_id |
    Export-Csv -LiteralPath $MrnaInventory -NoTypeInformation -Encoding UTF8
$mirnaFinalRows | Sort-Object subject_id |
    Export-Csv -LiteralPath $MirnaInventory -NoTypeInformation -Encoding UTF8
$subjectRows | Sort-Object subject_id |
    Export-Csv -LiteralPath $SubjectComparison -NoTypeInformation -Encoding UTF8

@(
    [pscustomobject]@{
        modality='mRNA'
        accession='GSE243217'
        SOFT_sample_records=$mrnaSoftSummary.soft_sample_records
        parsed_subject_titles=$mrnaSoftSummary.parsed_subject_titles
        COV=$mrnaSoftSummary.COV
        P=$mrnaSoftSummary.P
        H=$mrnaSoftSummary.H
        filename_vs_SOFT_subject_set_match='YES'
    },
    [pscustomobject]@{
        modality='miRNA'
        accession='GSE243218'
        SOFT_sample_records=$mirnaSoftSummary.soft_sample_records
        parsed_subject_titles=$mirnaSoftSummary.parsed_subject_titles
        COV=$mirnaSoftSummary.COV
        P=$mirnaSoftSummary.P
        H=$mirnaSoftSummary.H
        filename_vs_SOFT_subject_set_match='YES'
    }
) | Export-Csv -LiteralPath $SoftSummaryCsv -NoTypeInformation -Encoding UTF8

@(
    'GSE243219_PHASE_D1_STATUS',
    'PHASE_D1_V2_STATUS=PASS',
    'GEO_PROCESSED_DATA_DOWNLOADED=YES',
    'RAW_FASTQ_DOWNLOADED=NO',
    'ALIGNMENT_EXECUTED=NO',
    'MATRIX_CONSTRUCTION_EXECUTED=NO',
    'NORMALIZATION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'GSE243217_COUNT_ARCHIVE_DOWNLOADED=YES',
    'GSE243218_COUNT_ARCHIVE_DOWNLOADED=YES',
    'GSE243217_FAMILY_SOFT_DOWNLOADED=YES',
    'GSE243218_FAMILY_SOFT_DOWNLOADED=YES',
    'MRNA_EXTRACTED_FILES=72',
    'MIRNA_EXTRACTED_FILES=72',
    'MRNA_GZIP_INTEGRITY_PASS=72',
    'MIRNA_GZIP_INTEGRITY_PASS=72',
    'MRNA_FILENAME_COUNTS_COV=35',
    'MRNA_FILENAME_COUNTS_P=22',
    'MRNA_FILENAME_COUNTS_H=15',
    'MIRNA_FILENAME_COUNTS_COV=35',
    'MIRNA_FILENAME_COUNTS_P=22',
    'MIRNA_FILENAME_COUNTS_H=15',
    'FILENAME_SUBJECT_SET_MATCH=YES',
    'FILENAME_PAIRABLE_SUBJECTS=72',
    'MRNA_SOFT_SAMPLE_RECORDS=72',
    'MIRNA_SOFT_SAMPLE_RECORDS=72',
    'MRNA_FILENAME_VS_SOFT_SUBJECT_SET_MATCH=YES',
    'MIRNA_FILENAME_VS_SOFT_SUBJECT_SET_MATCH=YES',
    'P_LABEL_SEPSIS_MAPPING_CERTIFIED=NO',
    'CROSS_MODALITY_PAIRING_CERTIFIED=NO',
    'MRNA_COUNT_INTEGER_STATUS=UNKNOWN',
    'MIRNA_COUNT_INTEGER_STATUS=UNKNOWN',
    'READY_FOR_PHASE_D2_INPUT_AUDIT_AND_PAIRING=YES',
    'READY_FOR_NORMALIZATION=NO',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'STOP=YES'
) | Set-Content -LiteralPath $StatusPath -Encoding UTF8

# ------------------------------------------------------------
# 10. D1 output SHA256 manifest
# ------------------------------------------------------------
$outputFiles = @(
    $DownloadManifest,
    $MrnaInventory,
    $MirnaInventory,
    $SubjectComparison,
    $SoftSummaryCsv,
    $StatusPath
)

$outputManifestRows = @()
foreach ($p in $outputFiles) {
    $item = Get-Item -LiteralPath $p
    $outputManifestRows += [pscustomobject]@{
        filename=$item.Name
        full_path=$item.FullName
        size_bytes=[Int64]$item.Length
        SHA256=(Get-D1SHA256 $item.FullName)
    }
}

$OutputManifest = Join-Path $AuditDir 'D1_OUTPUT_SHA256_MANIFEST.csv'
$outputManifestRows | Export-Csv -LiteralPath $OutputManifest -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# 11. Final D1 summary
# ------------------------------------------------------------
$mrnaTarHash = ($downloadRows | Where-Object role -eq 'mRNA_count_archive').SHA256
$mirnaTarHash = ($downloadRows | Where-Object role -eq 'miRNA_count_archive').SHA256

$summary = @(
    '=== GSE243219 PHASE D1 SUMMARY ===',
    'PHASE_D1_V2_STATUS=PASS',
    'MODE=ACQUISITION_AND_INTEGRITY_ONLY',
    'GEO_PROCESSED_DATA_DOWNLOADED=YES',
    'RAW_FASTQ_DOWNLOADED=NO',
    'ALIGNMENT_EXECUTED=NO',
    'MATRIX_CONSTRUCTION_EXECUTED=NO',
    'NORMALIZATION_EXECUTED=NO',
    'DE_EXECUTED=NO',
    'NETWORK_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    ('GSE243217_RAW_TAR_SHA256={0}' -f $mrnaTarHash),
    ('GSE243218_RAW_TAR_SHA256={0}' -f $mirnaTarHash),
    'MRNA_TAR_SAFE_EXTRACTION=PASS',
    'MIRNA_TAR_SAFE_EXTRACTION=PASS',
    ('MRNA_EXTRACTED_FILES={0}' -f $mrnaFinalRows.Count),
    ('MIRNA_EXTRACTED_FILES={0}' -f $mirnaFinalRows.Count),
    'MRNA_GZIP_INTEGRITY_PASS=72',
    'MIRNA_GZIP_INTEGRITY_PASS=72',
    'MRNA_FILENAME_COUNTS=COV35|P22|H15',
    'MIRNA_FILENAME_COUNTS=COV35|P22|H15',
    'FILENAME_SUBJECT_SET_MATCH=YES',
    'FILENAME_PAIRABLE_SUBJECTS=72',
    ('MRNA_SOFT_SAMPLE_RECORDS={0}' -f $mrnaSoftSummary.soft_sample_records),
    ('MIRNA_SOFT_SAMPLE_RECORDS={0}' -f $mirnaSoftSummary.soft_sample_records),
    'MRNA_FILENAME_VS_SOFT_SUBJECT_SET_MATCH=YES',
    'MIRNA_FILENAME_VS_SOFT_SUBJECT_SET_MATCH=YES',
    'P_LABEL_SEPSIS_MAPPING_CERTIFIED=NO',
    'CROSS_MODALITY_PAIRING_CERTIFIED=NO',
    'MRNA_COUNT_INTEGER_STATUS=UNKNOWN',
    'MIRNA_COUNT_INTEGER_STATUS=UNKNOWN',
    'READY_FOR_PHASE_D2_INPUT_AUDIT_AND_PAIRING=YES',
    'READY_FOR_NORMALIZATION=NO',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'STOP=YES'
)

$ReportSummary = Join-Path $ReportDir 'PHASE_D1_SUMMARY.txt'
$summary | Set-Content -LiteralPath $ReportSummary -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $ReportSummary
Write-Host ''
Write-Host ('DOWNLOAD_MANIFEST={0}' -f $DownloadManifest)
Write-Host ('MRNA_FILE_INVENTORY={0}' -f $MrnaInventory)
Write-Host ('MIRNA_FILE_INVENTORY={0}' -f $MirnaInventory)
Write-Host ('SUBJECT_COMPARISON={0}' -f $SubjectComparison)
Write-Host ('SOFT_METADATA_SUMMARY={0}' -f $SoftSummaryCsv)
Write-Host ('D1_STATUS={0}' -f $StatusPath)
Write-Host ('D1_OUTPUT_SHA256_MANIFEST={0}' -f $OutputManifest)
Write-Host ('PHASE_D1_SUMMARY={0}' -f $ReportSummary)
Write-Host 'STEP_GSE243219_PHASE_D1_V2=PASS'
Write-Host 'STOP=YES'
