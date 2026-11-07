$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219 NEW PROJECT
# PHASE D0 — PROJECT INITIALIZATION
#
# Scope:
#   - Create the authoritative project directory structure.
#   - Write frozen scope/provenance/status documents.
#   - NO GEO data download.
#   - NO biological analysis.
#   - NO reuse of old dataset-specific thresholds.
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$Reusable = Join-Path $Parent '00_REUSABLE_ASSETS'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D0_{0}' -f $Stamp)
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

Write-Host '=== GSE243219 PHASE D0 — PROJECT INITIALIZATION ==='
Write-Host 'MODE=INITIALIZATION_ONLY'
Write-Host 'GEO_DATA_DOWNLOADED=NO'
Write-Host 'BIOLOGICAL_ANALYSIS_EXECUTED=NO'
Write-Host 'OLD_BIOLOGICAL_RESULTS_IMPORTED=NO'
Write-Host 'OLD_DATASET_SPECIFIC_THRESHOLDS_REUSED=NO'
Write-Host ('PROJECT_ROOT={0}' -f $Project)
Write-Host ('REUSABLE_ASSETS_ROOT={0}' -f $Reusable)
Write-Host ('REPORT_DIR={0}' -f $ReportDir)

if (-not (Test-Path -LiteralPath $Project -PathType Container)) {
    throw ('PROJECT_ROOT_MISSING={0}' -f $Project)
}
if (-not (Test-Path -LiteralPath $Reusable -PathType Container)) {
    throw ('REUSABLE_ASSETS_ROOT_MISSING={0}' -f $Reusable)
}

# Project must still contain no files before initialization.
$preFiles = @(Get-ChildItem -LiteralPath $Project -File -Recurse -Force -ErrorAction SilentlyContinue)
if ($preFiles.Count -ne 0) {
    throw ('PROJECT_ROOT_NOT_EMPTY_PREINIT files={0}' -f $preFiles.Count)
}

$dirs = @(
    '00_PROTOCOL_AND_METADATA',
    '01_PROCESSED_DATA_ACQUISITION',
    '02_INPUT_AUDIT_AND_PAIRING',
    '03_QC_AND_FILTERING',
    '04_NORMALIZATION',
    '05_DIFFERENTIAL_EXPRESSION',
    '06_ASSOCIATION_AND_STABILITY',
    '07_TARGET_EVIDENCE',
    '08_NETWORK_CONSTRUCTION',
    '09_ACLA',
    '10_MODULES_AND_HUBS',
    '11_SEPSIS_SPECIFICITY',
    '12_ENRICHMENT',
    '13_FINAL_REPORT'
)

foreach ($d in $dirs) {
    New-Item -ItemType Directory -Path (Join-Path $Project $d) -Force | Out-Null
}

$metaDir = Join-Path $Project '00_PROTOCOL_AND_METADATA'

# ------------------------------------------------------------
# Authoritative GEO accession registry
# ------------------------------------------------------------
$geoRows = @(
    [pscustomobject]@{
        accession='GSE243219'
        role='SuperSeries'
        modality='mRNA + miRNA'
        subjects='72 paired subjects across two modalities'
        covid_n=35
        sepsis_n=22
        healthy_n=15
        platform='GPL30209 + GPL24676'
        processed_archive=''
        processed_archive_size='N/A'
        source_url='https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE243219'
        status='AUTHORITATIVE_PARENT'
    },
    [pscustomobject]@{
        accession='GSE243217'
        role='SubSeries'
        modality='mRNA RNA-seq'
        subjects='72'
        covid_n=35
        sepsis_n=22
        healthy_n=15
        platform='GPL30209 MGISEQ-2000RS'
        processed_archive='GSE243217_RAW.tar'
        processed_archive_size='7.7 MB on GEO'
        source_url='https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE243217'
        status='PRIMARY_MRNA_INPUT'
    },
    [pscustomobject]@{
        accession='GSE243218'
        role='SubSeries'
        modality='miRNA-seq'
        subjects='72'
        covid_n=35
        sepsis_n=22
        healthy_n=15
        platform='GPL24676 Illumina NovaSeq 6000'
        processed_archive='GSE243218_RAW.tar'
        processed_archive_size='1.5 MB on GEO'
        source_url='https://www.ncbi.nlm.nih.gov/geo/query/acc.cgi?acc=GSE243218'
        status='PRIMARY_MIRNA_INPUT'
    }
)

$geoCsv = Join-Path $metaDir 'GSE243219_ACCESSION_REGISTRY.csv'
$geoRows | Export-Csv -LiteralPath $geoCsv -NoTypeInformation -Encoding UTF8

# ------------------------------------------------------------
# Frozen project scope
# ------------------------------------------------------------
$scope = @'
GSE243219 NEW PROJECT — FROZEN INITIAL SCOPE

PROJECT:
GSE243219 SuperSeries

SUBSERIES:
GSE243217 = mRNA RNA-seq
GSE243218 = miRNA-seq

COHORT DESIGN:
35 COVID-19 subjects
22 sepsis subjects
15 healthy subjects
72 subjects per modality
144 GEO sample records total across the paired mRNA + miRNA modalities

PREFIX INTERPRETATION:
COV = COVID-19
H = healthy
P = operationally mapped to the 22-patient sepsis cohort based on exact cohort/sample counts.
This mapping MUST be confirmed against sample-level GEO characteristics before biological analysis.

PRIMARY INPUT POLICY:
Use GEO-supplied processed/count TXT files.
Do NOT download SRA/FASTQ for the primary workflow.
Do NOT perform alignment production.

GEO ARCHIVES:
GSE243217_RAW.tar = small archive of per-sample mapped-count TXT files, not a FASTQ archive.
GSE243218_RAW.tar = small archive of per-sample miRNA count TXT files, not a FASTQ archive.

MRNA GEO PROCESSING:
Platform: MGISEQ-2000RS
Sequencing: 2 x 100 bp paired-end
Reference assembly reported by GEO: hg19
Alignment: TopHat 2.0.13 + Bowtie2 2.2.3 + SAMtools 0.1.19
Counting: featureCounts/subread 2.0.0 with -M -O --fraction

IMPORTANT MRNA COUNT AUDIT:
Because --fraction was used, do NOT assume every mRNA count is integer-valued.
Before choosing DESeq2/PyDESeq2/InMoose handling, audit the downloaded matrices for:
- numeric type
- fractional values
- missing values
- negative values
- duplicated identifiers
- count range and sparsity
No DE method is authorized until that audit is complete.

MIRNA GEO PROCESSING:
Platform: Illumina NovaSeq 6000
Sequencing: 101-base single-end
3-prime adapter trimmed: AGATCGGAAGAGCACACGTCT
Mapping/quantification: miRDeep2 against a miRBase human miRNA dataset
Input files: per-sample tab-delimited count TXT files

PAIRING POLICY:
Pair mRNA and miRNA strictly by biological subject ID/title after metadata audit.
Do not assume GSM identifiers are pairing keys.
Expected biological titles should match across modalities:
35 COV + 22 P + 15 H.

REFERENCE POLICY:
The previously preserved GRCh38 assets are retained as reusable historical/reference resources.
Do NOT silently use GRCh38 to reinterpret GSE243217 identifiers because GEO reports hg19 for the mRNA processing.
Identifier mapping must be audited explicitly.

REUSE POLICY:
Reusable generic code/databases/utilities may be reused.
Old GSE179850/GSE182152 biological outputs must never be imported.
Old dataset-specific thresholds, exclusions, cutoffs, convergence parameters, and tuning values are NOT frozen for GSE243219.
All dataset-dependent choices require prospective recalibration.

INITIAL ANALYTIC DIRECTION:
1. Processed-data acquisition
2. Integrity and format audit
3. Sample metadata + phenotype audit
4. Cross-modality pairing
5. QC/filtering design
6. Normalization/DE strategy chosen only after count audit
7. Association/stability analysis
8. miRNA-target evidence integration
9. Network construction
10. Prospective A-CLA application
11. Modules/hubs
12. Sepsis-specificity analysis
13. Enrichment/final interpretation

CURRENT AUTHORIZATION:
PROJECT_INITIALIZED=YES
PROCESSED_DATA_DOWNLOADED=NO
PAIRING_CERTIFIED=NO
DE_AUTHORIZED=NO
NETWORK_AUTHORIZED=NO
ACLA_AUTHORIZED=NO
'@

$scopePath = Join-Path $metaDir 'GSE243219_FROZEN_INITIAL_SCOPE.txt'
$scope | Set-Content -LiteralPath $scopePath -Encoding UTF8

# ------------------------------------------------------------
# Status registry
# ------------------------------------------------------------
$status = @'
GSE243219_PROJECT_STATUS

CLEANUP_PREDECESSOR=C2_PASS
OLD_PROJECT_CLEANUP_COMPLETE=YES
REUSABLE_ASSETS_AVAILABLE=YES
REUSABLE_ASSETS_CERTIFIED_COUNT=2965

PHASE_D0_PROJECT_INITIALIZATION=PASS

GEO_SUPERSERIES=GSE243219
MRNA_SUBSERIES=GSE243217
MIRNA_SUBSERIES=GSE243218

EXPECTED_SUBJECTS=72
EXPECTED_COVID=35
EXPECTED_SEPSIS=22
EXPECTED_HEALTHY=15
EXPECTED_MRNA_SAMPLES=72
EXPECTED_MIRNA_SAMPLES=72
EXPECTED_GEO_SAMPLE_RECORDS_TOTAL=144

PROCESSED_ONLY_PRIMARY_WORKFLOW=YES
RAW_FASTQ_PRIMARY_WORKFLOW=NO

GEO_DATA_DOWNLOADED=NO
INPUT_INTEGRITY_VERIFIED=NO
SAMPLE_METADATA_AUDITED=NO
P_LABEL_SEPSIS_MAPPING_CERTIFIED=NO
CROSS_MODALITY_PAIRING_CERTIFIED=NO
MRNA_COUNT_INTEGER_STATUS=UNKNOWN
MIRNA_COUNT_INTEGER_STATUS=UNKNOWN

READY_FOR_PHASE_D1_PROCESSED_DATA_ACQUISITION=YES
READY_FOR_DE=NO
READY_FOR_NETWORK=NO
READY_FOR_ACLA=NO
STOP=YES
'@

$statusPath = Join-Path $metaDir 'PROJECT_STATUS.txt'
$status | Set-Content -LiteralPath $statusPath -Encoding UTF8

# ------------------------------------------------------------
# Directory manifest
# ------------------------------------------------------------
$dirRows = @()
foreach ($d in $dirs) {
    $p = Join-Path $Project $d
    $dirRows += [pscustomobject]@{
        relative_path=$d
        full_path=$p
        exists=$(if (Test-Path -LiteralPath $p -PathType Container) {'YES'} else {'NO'})
    }
}

$dirCsv = Join-Path $metaDir 'PROJECT_DIRECTORY_MANIFEST.csv'
$dirRows | Export-Csv -LiteralPath $dirCsv -NoTypeInformation -Encoding UTF8

# Hash the initialization documents.
$artifactRows = @()
foreach ($p in @($geoCsv,$scopePath,$statusPath,$dirCsv)) {
    $i = Get-Item -LiteralPath $p
    $artifactRows += [pscustomobject]@{
        file=$i.Name
        full_path=$i.FullName
        size_bytes=[Int64]$i.Length
        SHA256=(Get-FileHash -Algorithm SHA256 -LiteralPath $i.FullName).Hash.ToLowerInvariant()
    }
}

$manifestPath = Join-Path $metaDir 'D0_INITIALIZATION_SHA256_MANIFEST.csv'
$artifactRows | Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8

# Final verification.
$missingDirs = @($dirRows | Where-Object exists -ne 'YES')
if ($missingDirs.Count -gt 0) {
    throw ('PROJECT_DIRECTORIES_MISSING={0}' -f $missingDirs.Count)
}

$filesNow = @(Get-ChildItem -LiteralPath $Project -File -Recurse -Force -ErrorAction Stop)

$unexpectedOutsideMeta = @($filesNow | Where-Object {
    -not $_.FullName.StartsWith($metaDir,[System.StringComparison]::OrdinalIgnoreCase)
})
if ($unexpectedOutsideMeta.Count -gt 0) {
    $unexpectedOutsideMeta | Select-Object FullName,Length |
        Export-Csv -LiteralPath (Join-Path $ReportDir 'FAIL_UNEXPECTED_PROJECT_FILES.csv') -NoTypeInformation -Encoding UTF8
    throw ('UNEXPECTED_FILES_OUTSIDE_PROTOCOL_METADATA={0}' -f $unexpectedOutsideMeta.Count)
}

$summary = @(
    '=== GSE243219 PHASE D0 SUMMARY ===',
    'PHASE_D0_STATUS=PASS',
    'MODE=INITIALIZATION_ONLY',
    'GEO_DATA_DOWNLOADED=NO',
    'BIOLOGICAL_ANALYSIS_EXECUTED=NO',
    'OLD_BIOLOGICAL_RESULTS_IMPORTED=NO',
    'OLD_DATASET_SPECIFIC_THRESHOLDS_REUSED=NO',
    ('PROJECT_DIRECTORIES_VERIFIED={0}' -f $dirs.Count),
    ('PROJECT_FILES_CREATED={0}' -f $filesNow.Count),
    'GSE243219_SUPERSERIES=VERIFIED',
    'GSE243217_MRNA_SUBSERIES=VERIFIED',
    'GSE243218_MIRNA_SUBSERIES=VERIFIED',
    'EXPECTED_MRNA_SAMPLES=72',
    'EXPECTED_MIRNA_SAMPLES=72',
    'EXPECTED_COVID=35',
    'EXPECTED_SEPSIS=22',
    'EXPECTED_HEALTHY=15',
    'PROCESSED_ONLY_PRIMARY_WORKFLOW=YES',
    'PAIRING_CERTIFIED=NO',
    'MRNA_COUNT_INTEGER_STATUS=UNKNOWN',
    'READY_FOR_PHASE_D1_PROCESSED_DATA_ACQUISITION=YES',
    'READY_FOR_DE=NO',
    'READY_FOR_NETWORK=NO',
    'READY_FOR_ACLA=NO',
    'STOP=YES'
)

$reportSummary = Join-Path $ReportDir 'PHASE_D0_SUMMARY.txt'
$summary | Set-Content -LiteralPath $reportSummary -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $reportSummary
Write-Host ''
Write-Host ('ACCESSION_REGISTRY={0}' -f $geoCsv)
Write-Host ('FROZEN_SCOPE={0}' -f $scopePath)
Write-Host ('PROJECT_STATUS={0}' -f $statusPath)
Write-Host ('DIRECTORY_MANIFEST={0}' -f $dirCsv)
Write-Host ('INITIALIZATION_SHA256_MANIFEST={0}' -f $manifestPath)
Write-Host ('PHASE_D0_SUMMARY={0}' -f $reportSummary)
Write-Host 'STEP_GSE243219_PHASE_D0=PASS'
Write-Host 'STOP=YES'
