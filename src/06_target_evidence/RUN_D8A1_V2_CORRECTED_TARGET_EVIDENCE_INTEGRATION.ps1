$ErrorActionPreference = 'Stop'

# GSE243219 PHASE D8A1
# Annotation only: no edge removal/addition, no network rebuild, no A-CLA.

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D6Root = Join-Path $Project '06_ASSOCIATION_AND_STABILITY'
$D8Root = Join-Path $Project '07_TARGET_EVIDENCE'

$D7CRun = Join-Path $D6Root 'D7C_ASSOCIATION_STABILITY_AUDIT_EDGE_FREEZE_20260905_145214'
$D7CManifest = Join-Path $D7CRun 'D7C_OUTPUT_SHA256_MANIFEST.csv'
$StableEdges = Join-Path $D7CRun 'D7C_FROZEN_STABLE_ASSOCIATION_EDGES.csv.gz'

$D8Run = Join-Path $D8Root 'D8_V6_TARGET_EVIDENCE_PREFLIGHT_20260905_154552'
$D8Manifest = Join-Path $D8Run 'D8_OUTPUT_SHA256_MANIFEST.csv'
$D8Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D8_V6_20260905_154552\PHASE_D8_SUMMARY.txt'
$D8AssetInventory = Join-Path $D8Run 'D8_REUSABLE_TARGET_ASSET_INVENTORY.csv'

$D8A3Run = Join-Path $D8Root 'D8A_V3_IDENTIFIER_BRIDGE_PREFLIGHT_20260905_191138'
$D8A3Manifest = Join-Path $D8A3Run 'D8A_V3_OUTPUT_SHA256_MANIFEST.csv'
$D8A3Report = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D8A_V3_20260905_191138\PHASE_D8A_V3_SUMMARY.txt'
$GeneAudit = Join-Path $D8A3Run 'D8A_V3_PROJECT_GENE_REFERENCE_MAPPING_AUDIT.csv'
$MiRBaseAudit = Join-Path $D8A3Run 'D8A_V3_MIRBASE_41_PROJECT_MIRNA_VALIDATION.csv'
$TargetScanFamilyAudit = Join-Path $D8A3Run 'D8A_V3_TARGETSCAN_RELEASE8_FAMILY_METADATA_AUDIT.csv'
$MiRDBRefSeqBridge = Join-Path $D8A3Run 'D8A_V3_MIRDB_REFSEQ_TO_PROJECT_GENE_BRIDGE.csv.gz'

$BundledPython = Join-Path $PSScriptRoot 'D8A1_V2_TARGET_EVIDENCE_INTEGRATION.py'
$ExpectedPythonSHA256 = '8b7e416bffb18c224f40750159af4f5e40421f126e7c6bf7ddd903492c8c125b'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D8Root ('D8A1_V2_CORRECTED_TARGET_EVIDENCE_INTEGRATION_' + $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D8A1_V2_' + $Stamp)
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PythonCopy = Join-Path $RunDir 'D8A1_V2_TARGET_EVIDENCE_INTEGRATION.py'
$ResultJson = Join-Path $RunDir 'D8A1_RESULT.json'
$Stdout = Join-Path $RunDir 'D8A1_PYTHON_STDOUT.txt'
$Stderr = Join-Path $RunDir 'D8A1_PYTHON_STDERR.txt'
$Log = Join-Path $RunDir 'D8A1_PYTHON_LOG.txt'
$Decision = Join-Path $RunDir 'D8A1_DECISION.txt'
$Manifest = Join-Path $RunDir 'D8A1_OUTPUT_SHA256_MANIFEST.csv'
$Summary = Join-Path $ReportDir 'PHASE_D8A1_SUMMARY.txt'

Write-Host '=== GSE243219 PHASE D8A1-V2 - CORRECTED TARGETSCAN EVIDENCE INTEGRATION ==='
Write-Host 'MODE=ANNOTATION_ONLY'
Write-Host 'FROZEN_INPUT_EDGES=11531'
Write-Host 'EDGE_REMOVAL_ALLOWED=NO'
Write-Host 'EDGE_ADDITION_ALLOWED=NO'
Write-Host 'NETWORK_REBUILDING_EXECUTED=NO'
Write-Host 'ACLA_EXECUTED=NO'
Write-Host ('RUN_DIR=' + $RunDir)

function SHA([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Recertify([string]$ManifestPath,[int]$Expected,[string]$Label) {
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw ("$Label`_MANIFEST_MISSING=$ManifestPath")
    }
    $rows = @(Import-Csv -LiteralPath $ManifestPath)
    if ($rows.Count -ne $Expected) {
        throw ("$Label`_MANIFEST_ROW_COUNT_CHANGED expected=$Expected observed=$($rows.Count)")
    }
    foreach ($r in $rows) {
        if (-not (Test-Path -LiteralPath $r.full_path -PathType Leaf)) {
            throw ("$Label`_OUTPUT_MISSING=$($r.full_path)")
        }
        $item = Get-Item -LiteralPath $r.full_path
        if ([Int64]$item.Length -ne [Int64]$r.size_bytes -or (SHA $r.full_path) -ne $r.SHA256.ToLowerInvariant()) {
            throw ("$Label`_OUTPUT_CHANGED=$($r.full_path)")
        }
    }
    Write-Host ("$Label`_OUTPUTS_RECERTIFIED=$Expected/$Expected")
}

if (-not (Test-Path -LiteralPath $BundledPython -PathType Leaf)) {
    throw ('BUNDLED_PYTHON_MISSING=' + $BundledPython)
}
if ((SHA $BundledPython) -ne $ExpectedPythonSHA256) {
    throw 'BUNDLED_PYTHON_SHA256_CHANGED'
}
Write-Host 'D8A1_PACKAGE_PYTHON_INTEGRITY=PASS'

Recertify $D7CManifest 11 'D7C'
Write-Host 'D7C_CERTIFICATION_GATE=PASS'
Recertify $D8Manifest 10 'D8_V6'
Write-Host 'D8_V6_CERTIFICATION_GATE=PASS'
Recertify $D8A3Manifest 14 'D8A_V3'
Write-Host 'D8A_V3_CERTIFICATION_GATE=PASS'

foreach ($p in @($StableEdges,$D8Report,$D8AssetInventory,$D8A3Report,$GeneAudit,$MiRBaseAudit,$TargetScanFamilyAudit,$MiRDBRefSeqBridge)) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw ('REQUIRED_D8A1_INPUT_MISSING=' + $p)
    }
}

$d8 = Get-Content -LiteralPath $D8Report -Raw
foreach ($tok in @(
    'PHASE_D8_V6_STATUS=PASS',
    'FROZEN_STABLE_ASSOCIATION_EDGES=11531',
    'REUSABLE_TARGET_ASSET_SCHEMA_AUDIT=PASS',
    'TARGET_EVIDENCE_STRATEGY_FROZEN=YES'
)) {
    if (-not $d8.Contains($tok)) { throw ('D8_V6_TOKEN_MISSING=' + $tok) }
}

$d8a3 = Get-Content -LiteralPath $D8A3Report -Raw
foreach ($tok in @(
    'PHASE_D8A_V3_STATUS=PASS',
    'PROJECT_GENE_AUTHORITATIVE_IDS_RETAINED=4467',
    'MIRBASE22_1_PROJECT_MIRNA_EXACT_VALIDATED=41',
    'TARGETSCAN_PROJECT_MIRNAS_WITH_EXPLICIT_FAMILY_METADATA=40',
    'MIRDB_REFSEQ_BRIDGE_GATE=PASS_WITH_CONSERVATIVE_NON_SUPPORT',
    'READY_FOR_D8A1_TARGET_EVIDENCE_INTEGRATION=YES'
)) {
    if (-not $d8a3.Contains($tok)) { throw ('D8A_V3_TOKEN_MISSING=' + $tok) }
}

Copy-Item -LiteralPath $BundledPython -Destination $PythonCopy -Force
if ((SHA $PythonCopy) -ne $ExpectedPythonSHA256) { throw 'PYTHON_COPY_HASH_FAILED' }

$PythonExe = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING\D2D_PREFLIGHT_20260904_195001\venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
    throw ('PYTHON_EXECUTABLE_MISSING=' + $PythonExe)
}

$env:PYTHONUTF8='1'
$env:PYTHONIOENCODING='utf-8'

$args = @(
    '-u',$PythonCopy,
    $StableEdges,
    $D8AssetInventory,
    $GeneAudit,
    $MiRBaseAudit,
    $TargetScanFamilyAudit,
    $MiRDBRefSeqBridge,
    $RunDir,
    $ResultJson
)

$p = Start-Process -FilePath $PythonExe -ArgumentList $args -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr

$stdoutLines = @(Get-Content -LiteralPath $Stdout)
foreach ($line in $stdoutLines) { Write-Host $line }
$stderrLines = @(Get-Content -LiteralPath $Stderr)
if ($stderrLines.Count -gt 0) {
    Write-Host '=== D8A1 PYTHON STDERR ==='
    foreach ($line in $stderrLines) { Write-Host $line }
}
@('=== STDOUT ===',$stdoutLines,'','=== STDERR ===',$stderrLines) | Set-Content -LiteralPath $Log -Encoding UTF8

if ([int]$p.ExitCode -ne 0) {
    throw ("D8A1_PYTHON_FAILED exit=$($p.ExitCode) full_traceback=$Stderr")
}

$r = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json
function Cap([string]$Key) { return [string]$r.results.$Key }

foreach ($pair in @(
    @('FROZEN_EDGE_INPUT_COUNT','11531'),
    @('FROZEN_UNIQUE_MRNA','4467'),
    @('FROZEN_UNIQUE_MIRNA','41'),
    @('FROZEN_EDGE_INPUT_GATE','PASS'),
    @('SELECTED_DATABASE_ASSET_SHA256_RECERTIFICATION','PASS'),
    @('IDENTIFIER_BRIDGE_GATE','PASS'),
    @('TARBASE_MATCHING_COMPLETED','YES'),
    @('TARGETSCAN_MATCHING_COMPLETED','YES'),
    @('TARGETSCAN_MAPPING_CORRECTION','PREDICTION_MIRNA_COLUMN_IS_NATIVE_MIRNA_LABEL_NOT_FAMILY_COLUMN'),
    @('TARGETSCAN_LABEL_MATCHING_MODE','EXACT_RELEASE8_METADATA_LABEL_ONLY'),
    @('TARGETSCAN_FAMILY_INFERENCE_FROM_NAME_OR_SEQUENCE','NO'),
    @('TARGETSCAN_EXPLICIT_FAMILY_PROJECT_MIRNAS','40'),
    @('MIRDB_MATCHING_COMPLETED','YES'),
    @('MIRDB_SCORE_RULE','STRICT_GT_80'),
    @('OUTPUT_EDGE_COUNT','11531'),
    @('DUPLICATE_EDGE_COUNT','0'),
    @('MIRNA_IDENTITY_CHANGED','NO'),
    @('MRNA_SYMBOL_CHANGED','NO'),
    @('NETWORK_TOPOLOGY_CHANGED','NO'),
    @('TARGET_EVIDENCE_INTEGRATION','PASS'),
    @('D8A1_COMPLETE','YES'),
    @('READY_FOR_FINAL_MULTILAYER_NETWORK_CONSTRUCTION','YES'),
    @('READY_FOR_ACLA','NO'),
    @('NETWORK_REBUILDING_EXECUTED','NO'),
    @('ACLA_EXECUTED','NO'),
    @('STOP','YES')
)) {
    $obs = Cap $pair[0]
    if ($obs -ne $pair[1]) {
        throw ("D8A1_FINAL_GATE_FAILED key=$($pair[0]) expected=$($pair[1]) observed=$obs")
    }
}

$EdgeMatrix = Join-Path $RunDir 'EDGE_EVIDENCE_MATRIX.csv'
$TarSummary = Join-Path $RunDir 'TarBase_match_summary.csv'
$TsSummary = Join-Path $RunDir 'TargetScan_match_summary.csv'
$MdbSummary = Join-Path $RunDir 'miRDB_match_summary.csv'
$IdAudit = Join-Path $RunDir 'D8A1_IDENTIFIER_AUDIT.csv'
$EdgeAudit = Join-Path $RunDir 'D8A1_EDGE_PRESERVATION_AUDIT.csv'
$ClassSummary = Join-Path $RunDir 'D8A1_EVIDENCE_CLASS_SUMMARY.csv'
$Spec = Join-Path $RunDir 'D8A1_EXECUTION_SPECIFICATION.txt'

@(
    'GSE243219_D8A1_V2_DECISION',
    'PHASE_D8A1_V2_STATUS=PASS',
    'MODE=CORRECTED_TARGETSCAN_ANNOTATION_ONLY',
    'D8A1_V1_TARGETSCAN_PARSER_INVALID=YES',
    'D8A1_V1_INVALID_REASON=PREDICTION_MIRNA_COLUMN_MISTAKEN_FOR_FAMILY_COLUMN',
    'D7C_CERTIFICATION_GATE=PASS',
    'D8_V6_CERTIFICATION_GATE=PASS',
    'D8A_V3_CERTIFICATION_GATE=PASS',
    'FROZEN_INPUT_EDGES=11531',
    'OUTPUT_EDGES=11531',
    'DUPLICATE_EDGE_COUNT=0',
    'MIRNA_IDENTITY_CHANGED=NO',
    'MRNA_SYMBOL_CHANGED=NO',
    ('TARBASE_MATCHED_EDGES=' + (Cap 'TARBASE_MATCHED_EDGES')),
    ('TARGETSCAN_HUMAN_ROWS_WITH_EXPLICIT_PROJECT_LABEL=' + (Cap 'TARGETSCAN_HUMAN_ROWS_WITH_EXPLICIT_PROJECT_LABEL')),
    ('TARGETSCAN_PROJECT_MIRNAS_OBSERVED_IN_PREDICTION_TABLE=' + (Cap 'TARGETSCAN_PROJECT_MIRNAS_OBSERVED_IN_PREDICTION_TABLE')),
    ('TARGETSCAN_MATCHED_EDGES=' + (Cap 'TARGETSCAN_MATCHED_EDGES')),
    ('MIRDB_MATCHED_EDGES=' + (Cap 'MIRDB_MATCHED_EDGES')),
    ('CLASS_A_EXPERIMENTAL_SUPPORTED=' + (Cap 'CLASS_A_EXPERIMENTAL_SUPPORTED')),
    ('CLASS_B_MULTI_DATABASE_PREDICTED=' + (Cap 'CLASS_B_MULTI_DATABASE_PREDICTED')),
    ('CLASS_C_ASSOCIATION_ONLY=' + (Cap 'CLASS_C_ASSOCIATION_ONLY')),
    ('PREDICTION_CONSENSUS_BOTH_TARGETSCAN_AND_MIRDB=' + (Cap 'PREDICTION_CONSENSUS_BOTH_TARGETSCAN_AND_MIRDB')),
    'TARGET_EVIDENCE_INTEGRATION=PASS',
    'D8A1_V2_COMPLETE=YES',
    'D8A1_COMPLETE=YES',
    'NETWORK_TOPOLOGY_CHANGED=NO',
    'NETWORK_REBUILDING_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'FUNCTIONAL_ENRICHMENT_EXECUTED=NO',
    'DRUG_ANALYSIS_EXECUTED=NO',
    'READY_FOR_FINAL_MULTILAYER_NETWORK_CONSTRUCTION=YES',
    'READY_FOR_ACLA=NO',
    'STOP=YES'
) | Set-Content -LiteralPath $Decision -Encoding UTF8

$outFiles = @($PythonCopy,$EdgeMatrix,$TarSummary,$TsSummary,$MdbSummary,$IdAudit,$EdgeAudit,$ClassSummary,$Spec,$ResultJson,$Stdout,$Stderr,$Log,$Decision)
$rows = foreach ($f in $outFiles) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw ('D8A1_OUTPUT_MISSING=' + $f) }
    $i = Get-Item -LiteralPath $f
    [pscustomobject]@{filename=$i.Name;full_path=$i.FullName;size_bytes=[Int64]$i.Length;SHA256=(SHA $i.FullName)}
}
$rows | Export-Csv -LiteralPath $Manifest -NoTypeInformation -Encoding UTF8

@(
    '=== GSE243219 PHASE D8A1-V2 SUMMARY ===',
    'PHASE_D8A1_V2_STATUS=PASS',
    'MODE=CORRECTED_TARGETSCAN_ANNOTATION_ONLY',
    'D8A1_V1_TARGETSCAN_PARSER_INVALID=YES',
    'D8A1_V1_INVALID_REASON=PREDICTION_MIRNA_COLUMN_MISTAKEN_FOR_FAMILY_COLUMN',
    'D7C_OUTPUTS_RECERTIFIED=11/11',
    'D8_V6_OUTPUTS_RECERTIFIED=10/10',
    'D8A_V3_OUTPUTS_RECERTIFIED=14/14',
    'FROZEN_INPUT_EDGES=11531',
    'OUTPUT_EDGES=11531',
    'DUPLICATE_EDGE_COUNT=0',
    'MIRNA_IDENTITY_CHANGED=NO',
    'MRNA_SYMBOL_CHANGED=NO',
    ('TARBASE_MATCHED_EDGES=' + (Cap 'TARBASE_MATCHED_EDGES')),
    ('TARGETSCAN_HUMAN_ROWS_WITH_EXPLICIT_PROJECT_LABEL=' + (Cap 'TARGETSCAN_HUMAN_ROWS_WITH_EXPLICIT_PROJECT_LABEL')),
    ('TARGETSCAN_PROJECT_MIRNAS_OBSERVED_IN_PREDICTION_TABLE=' + (Cap 'TARGETSCAN_PROJECT_MIRNAS_OBSERVED_IN_PREDICTION_TABLE')),
    ('TARGETSCAN_MATCHED_EDGES=' + (Cap 'TARGETSCAN_MATCHED_EDGES')),
    ('MIRDB_MATCHED_EDGES=' + (Cap 'MIRDB_MATCHED_EDGES')),
    ('CLASS_A_EXPERIMENTAL_SUPPORTED=' + (Cap 'CLASS_A_EXPERIMENTAL_SUPPORTED')),
    ('CLASS_B_MULTI_DATABASE_PREDICTED=' + (Cap 'CLASS_B_MULTI_DATABASE_PREDICTED')),
    ('CLASS_C_ASSOCIATION_ONLY=' + (Cap 'CLASS_C_ASSOCIATION_ONLY')),
    ('PREDICTION_CONSENSUS_BOTH_TARGETSCAN_AND_MIRDB=' + (Cap 'PREDICTION_CONSENSUS_BOTH_TARGETSCAN_AND_MIRDB')),
    'TARGET_EVIDENCE_INTEGRATION=PASS',
    'D8A1_V2_COMPLETE=YES',
    'D8A1_COMPLETE=YES',
    'NETWORK_TOPOLOGY_CHANGED=NO',
    'NETWORK_REBUILDING_EXECUTED=NO',
    'ACLA_EXECUTED=NO',
    'READY_FOR_FINAL_MULTILAYER_NETWORK_CONSTRUCTION=YES',
    'READY_FOR_ACLA=NO',
    'STOP=YES'
) | Set-Content -LiteralPath $Summary -Encoding UTF8

Write-Host ''
Get-Content -LiteralPath $Summary
Write-Host ''
Write-Host ('EDGE_EVIDENCE_MATRIX=' + $EdgeMatrix)
Write-Host ('TARBASE_MATCH_SUMMARY=' + $TarSummary)
Write-Host ('TARGETSCAN_MATCH_SUMMARY=' + $TsSummary)
Write-Host ('MIRDB_MATCH_SUMMARY=' + $MdbSummary)
Write-Host ('D8A1_IDENTIFIER_AUDIT=' + $IdAudit)
Write-Host ('D8A1_EDGE_PRESERVATION_AUDIT=' + $EdgeAudit)
Write-Host ('D8A1_EVIDENCE_CLASS_SUMMARY=' + $ClassSummary)
Write-Host ('D8A1_OUTPUT_SHA256_MANIFEST=' + $Manifest)
Write-Host ('PHASE_D8A1_SUMMARY=' + $Summary)
Write-Host 'STEP_GSE243219_PHASE_D8A1_V2=PASS'
Write-Host 'STOP=YES'
