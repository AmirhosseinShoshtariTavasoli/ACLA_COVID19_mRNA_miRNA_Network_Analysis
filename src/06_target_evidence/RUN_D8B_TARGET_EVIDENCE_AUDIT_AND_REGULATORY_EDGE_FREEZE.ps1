$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219 D8B
# TARGET EVIDENCE AUDIT + REGULATORY EDGE FREEZE
#
# Independent audit only.
# No target database re-acquisition.
# No network construction.
# No A-CLA.
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D6Root = Join-Path $Project '06_ASSOCIATION_AND_STABILITY'
$D8Root = Join-Path $Project '07_TARGET_EVIDENCE'

$D7CRun = Join-Path $D6Root 'D7C_ASSOCIATION_STABILITY_AUDIT_EDGE_FREEZE_20260905_145214'
$D7CManifest = Join-Path $D7CRun 'D7C_OUTPUT_SHA256_MANIFEST.csv'
$D7CEdges = Join-Path $D7CRun 'D7C_FROZEN_STABLE_ASSOCIATION_EDGES.csv.gz'

$D8A3Run = Join-Path $D8Root 'D8A_V3_IDENTIFIER_BRIDGE_PREFLIGHT_20260905_191138'
$D8A3GeneAudit = Join-Path $D8A3Run 'D8A_V3_PROJECT_GENE_REFERENCE_MAPPING_AUDIT.csv'

$D8A1Run = Join-Path $D8Root 'D8A1_V2_CORRECTED_TARGET_EVIDENCE_INTEGRATION_20260905_223753'
$D8A1Manifest = Join-Path $D8A1Run 'D8A1_OUTPUT_SHA256_MANIFEST.csv'
$D8A1Decision = Join-Path $D8A1Run 'D8A1_DECISION.txt'
$D8A1Matrix = Join-Path $D8A1Run 'EDGE_EVIDENCE_MATRIX.csv'
$D8A1Summary = 'C:\Users\Amir\Downloads\GSE243219_PHASE_D8A1_V2_20260905_223753\PHASE_D8A1_SUMMARY.txt'

$BundledPython = Join-Path $PSScriptRoot 'D8B_TARGET_EVIDENCE_AUDIT_AND_REGULATORY_EDGE_FREEZE.py'
$ExpectedPythonSHA256 = '1fb90c397bc22cd17508aacd5b099551e9aec854e9849e32edf3791a3bbf58d8'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D8Root ('D8B_TARGET_EVIDENCE_AUDIT_REGULATORY_FREEZE_' + $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D8B_' + $Stamp)
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PythonCopy = Join-Path $RunDir 'D8B_TARGET_EVIDENCE_AUDIT_AND_REGULATORY_EDGE_FREEZE.py'
$ResultJson = Join-Path $RunDir 'D8B_RESULT.json'
$Stdout = Join-Path $RunDir 'D8B_PYTHON_STDOUT.txt'
$Stderr = Join-Path $RunDir 'D8B_PYTHON_STDERR.txt'
$Log = Join-Path $RunDir 'D8B_PYTHON_LOG.txt'
$FinalStatus = Join-Path $RunDir 'D8B_FINAL_STATUS.txt'
$Manifest = Join-Path $RunDir 'D8B_SHA256_MANIFEST.csv'
$Summary = Join-Path $ReportDir 'PHASE_D8B_SUMMARY.txt'

function SHA([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Write-FailClosed([string]$Reason) {
    $lines = @(
        '=== D8B TARGET EVIDENCE AUDIT + REGULATORY EDGE FREEZE ===',
        '',
        'D8B_STATUS=FAIL_CLOSED',
        '',
        'INPUT_EDGES=11531',
        'OUTPUT_EDGE_UNIVERSE=11531',
        '',
        'MRNA_FEATURES=4467',
        'MIRNA_FEATURES=41',
        '',
        'TARBASE_SUPPORTED=',
        'TARGETSCAN_SUPPORTED=',
        'MIRDB_GT80_SUPPORTED=',
        'TARGETSCAN_AND_MIRDB_SUPPORTED=',
        '',
        'TARBASE_AND_TARGETSCAN=',
        'TARBASE_AND_MIRDB=',
        'TARBASE_AND_TARGETSCAN_AND_MIRDB=',
        '',
        'ANY_EXTERNAL_EVIDENCE=',
        'NO_EXTERNAL_EVIDENCE=',
        '',
        'TS_MIRDB_CONSENSUS_TOTAL=',
        'TS_MIRDB_CONSENSUS_WITH_TARBASE=',
        'TS_MIRDB_CONSENSUS_WITHOUT_TARBASE=',
        '',
        'TARGETSCAN_ONLY_EDGES=',
        'MIRDB_ONLY_EDGES=',
        'TARGETSCAN_OR_MIRDB_BUT_NOT_BOTH=',
        '',
        'UNIQUE_REGULATORY_EDGES=',
        'NONREGULATORY_ASSOCIATION_EDGES=',
        '',
        'REGULATORY_EXPERIMENTAL=',
        'REGULATORY_PREDICTED_CONSENSUS=',
        'REGULATORY_EXPERIMENTAL_AND_PREDICTED=',
        '',
        'FULL_EDGE_CONSERVATION=FAIL',
        '',
        'DUPLICATE_REGULATORY_EDGES=',
        'DUPLICATE_NONREGULATORY_EDGES=',
        '',
        'SINGLE_PREDICTOR_ONLY_ELIGIBLE=NO',
        'SINGLE_PREDICTOR_EDGES_CLASSIFIED_REGULATORY=',
        '',
        'MIRNA_IDENTITY_CHANGED=UNKNOWN',
        'MRNA_SYMBOL_CHANGED=UNKNOWN',
        '',
        'NETWORK_CONSTRUCTION_EXECUTED=NO',
        'ACLA_EXECUTED=NO',
        '',
        'D8B_SHA256_MANIFEST_CREATED=NO',
        'D8B_HASH_MISMATCHES=1',
        '',
        'READY_FOR_D9_MULTILAYER_NETWORK_CONSTRUCTION=NO',
        '',
        'STOP=YES'
    )
    $lines | Set-Content -LiteralPath $FinalStatus -Encoding UTF8
    $lines | Set-Content -LiteralPath $Summary -Encoding UTF8
    $lines | ForEach-Object { Write-Host $_ }
    Write-Host ('D8B_FAIL_REASON=' + $Reason)
}

try {
    if (-not (Test-Path -LiteralPath $BundledPython -PathType Leaf)) {
        throw ('BUNDLED_PYTHON_MISSING=' + $BundledPython)
    }
    if ((SHA $BundledPython) -ne $ExpectedPythonSHA256) {
        throw 'BUNDLED_PYTHON_SHA256_CHANGED'
    }

    foreach ($p in @(
        $D7CManifest,
        $D7CEdges,
        $D8A3GeneAudit,
        $D8A1Manifest,
        $D8A1Decision,
        $D8A1Matrix,
        $D8A1Summary
    )) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            throw ('REQUIRED_D8B_INPUT_MISSING=' + $p)
        }
    }

    Copy-Item -LiteralPath $BundledPython -Destination $PythonCopy -Force
    if ((SHA $PythonCopy) -ne $ExpectedPythonSHA256) {
        throw 'D8B_PYTHON_COPY_HASH_FAILED'
    }

    $PythonExe = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING\D2D_PREFLIGHT_20260904_195001\venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
        throw ('PYTHON_EXECUTABLE_MISSING=' + $PythonExe)
    }

    $env:PYTHONUTF8='1'
    $env:PYTHONIOENCODING='utf-8'

    $args = @(
        '-u',
        $PythonCopy,
        $D8A1Manifest,
        $D8A1Decision,
        $D8A1Summary,
        $D8A1Matrix,
        $D7CManifest,
        $D7CEdges,
        $D8A3GeneAudit,
        $RunDir,
        $ResultJson
    )

    $p = Start-Process `
        -FilePath $PythonExe `
        -ArgumentList $args `
        -Wait `
        -PassThru `
        -NoNewWindow `
        -RedirectStandardOutput $Stdout `
        -RedirectStandardError $Stderr

    $stdoutLines = @()
    $stderrLines = @()
    if (Test-Path -LiteralPath $Stdout -PathType Leaf) {
        $stdoutLines = @(Get-Content -LiteralPath $Stdout)
    }
    if (Test-Path -LiteralPath $Stderr -PathType Leaf) {
        $stderrLines = @(Get-Content -LiteralPath $Stderr)
    }
    @(
        '=== STDOUT ===',
        $stdoutLines,
        '',
        '=== STDERR ===',
        $stderrLines
    ) | Set-Content -LiteralPath $Log -Encoding UTF8

    if ([int]$p.ExitCode -ne 0) {
        $trace = ($stderrLines -join ' | ')
        throw ('D8B_PYTHON_FAILED exit=' + $p.ExitCode + ' trace=' + $trace)
    }

    if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
        throw 'D8B_RESULT_JSON_MISSING'
    }

    $r = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json
    function Cap([string]$Key) { return [string]$r.$Key }

    foreach ($pair in @(
        @('D8B_STATUS','PASS'),
        @('INPUT_EDGES','11531'),
        @('OUTPUT_EDGE_UNIVERSE','11531'),
        @('MRNA_FEATURES','4467'),
        @('MIRNA_FEATURES','41'),
        @('TARBASE_SUPPORTED','1972'),
        @('TARGETSCAN_SUPPORTED','205'),
        @('MIRDB_GT80_SUPPORTED','118'),
        @('TARGETSCAN_AND_MIRDB_SUPPORTED','43'),
        @('ANY_EXTERNAL_EVIDENCE','2079'),
        @('NO_EXTERNAL_EVIDENCE','9452'),
        @('TS_MIRDB_CONSENSUS_TOTAL','43'),
        @('FULL_EDGE_CONSERVATION','PASS'),
        @('DUPLICATE_REGULATORY_EDGES','0'),
        @('DUPLICATE_NONREGULATORY_EDGES','0'),
        @('SINGLE_PREDICTOR_ONLY_ELIGIBLE','NO'),
        @('SINGLE_PREDICTOR_EDGES_CLASSIFIED_REGULATORY','0'),
        @('MIRNA_IDENTITY_CHANGED','NO'),
        @('MRNA_SYMBOL_CHANGED','NO'),
        @('GENE_NORMALIZATION_COLLISIONS','0'),
        @('NETWORK_CONSTRUCTION_EXECUTED','NO'),
        @('ACLA_EXECUTED','NO'),
        @('READY_FOR_D9_MULTILAYER_NETWORK_CONSTRUCTION','YES'),
        @('STOP','YES')
    )) {
        $obs = Cap $pair[0]
        if ($obs -ne $pair[1]) {
            throw (
                'D8B_FINAL_GATE_FAILED key=' + $pair[0] +
                ' expected=' + $pair[1] +
                ' observed=' + $obs
            )
        }
    }

    # Required outputs produced by Python
    $FullClass = Join-Path $RunDir 'D8B_FULL_EDGE_CLASSIFICATION.csv'
    $RegFreeze = Join-Path $RunDir 'D8B_REGULATORY_EDGE_FREEZE.csv'
    $RegSummary = Join-Path $RunDir 'D8B_REGULATORY_EDGE_SUMMARY.csv'
    $OverlapAudit = Join-Path $RunDir 'D8B_EVIDENCE_OVERLAP_AUDIT.csv'
    $NonReg = Join-Path $RunDir 'D8B_NONREGULATORY_ASSOCIATION_EDGES.csv'
    $Conservation = Join-Path $RunDir 'D8B_EDGE_CONSERVATION_AUDIT.csv'
    $Spec = Join-Path $RunDir 'D8B_EXECUTION_SPECIFICATION.txt'

    foreach ($f in @(
        $FullClass,$RegFreeze,$RegSummary,$OverlapAudit,
        $NonReg,$Conservation,$Spec,$ResultJson,$Stdout,$Stderr,$Log
    )) {
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
            throw ('D8B_REQUIRED_OUTPUT_MISSING=' + $f)
        }
    }

    # Create final status BEFORE manifest so final status itself is hashed.
    $final = @(
        '=== D8B TARGET EVIDENCE AUDIT + REGULATORY EDGE FREEZE ===',
        '',
        'D8B_STATUS=PASS',
        '',
        'INPUT_EDGES=11531',
        'OUTPUT_EDGE_UNIVERSE=11531',
        '',
        'MRNA_FEATURES=4467',
        'MIRNA_FEATURES=41',
        '',
        ('TARBASE_SUPPORTED=' + (Cap 'TARBASE_SUPPORTED')),
        ('TARGETSCAN_SUPPORTED=' + (Cap 'TARGETSCAN_SUPPORTED')),
        ('MIRDB_GT80_SUPPORTED=' + (Cap 'MIRDB_GT80_SUPPORTED')),
        ('TARGETSCAN_AND_MIRDB_SUPPORTED=' + (Cap 'TARGETSCAN_AND_MIRDB_SUPPORTED')),
        '',
        ('TARBASE_AND_TARGETSCAN=' + (Cap 'TARBASE_AND_TARGETSCAN')),
        ('TARBASE_AND_MIRDB=' + (Cap 'TARBASE_AND_MIRDB')),
        ('TARBASE_AND_TARGETSCAN_AND_MIRDB=' + (Cap 'TARBASE_AND_TARGETSCAN_AND_MIRDB')),
        '',
        ('ANY_EXTERNAL_EVIDENCE=' + (Cap 'ANY_EXTERNAL_EVIDENCE')),
        ('NO_EXTERNAL_EVIDENCE=' + (Cap 'NO_EXTERNAL_EVIDENCE')),
        '',
        ('TS_MIRDB_CONSENSUS_TOTAL=' + (Cap 'TS_MIRDB_CONSENSUS_TOTAL')),
        ('TS_MIRDB_CONSENSUS_WITH_TARBASE=' + (Cap 'TS_MIRDB_CONSENSUS_WITH_TARBASE')),
        ('TS_MIRDB_CONSENSUS_WITHOUT_TARBASE=' + (Cap 'TS_MIRDB_CONSENSUS_WITHOUT_TARBASE')),
        '',
        ('TARGETSCAN_ONLY_EDGES=' + (Cap 'TARGETSCAN_ONLY_EDGES')),
        ('MIRDB_ONLY_EDGES=' + (Cap 'MIRDB_ONLY_EDGES')),
        ('TARGETSCAN_OR_MIRDB_BUT_NOT_BOTH=' + (Cap 'TARGETSCAN_OR_MIRDB_BUT_NOT_BOTH')),
        '',
        ('UNIQUE_REGULATORY_EDGES=' + (Cap 'UNIQUE_REGULATORY_EDGES')),
        ('NONREGULATORY_ASSOCIATION_EDGES=' + (Cap 'NONREGULATORY_ASSOCIATION_EDGES')),
        '',
        ('REGULATORY_EXPERIMENTAL=' + (Cap 'REGULATORY_EXPERIMENTAL')),
        ('REGULATORY_PREDICTED_CONSENSUS=' + (Cap 'REGULATORY_PREDICTED_CONSENSUS')),
        ('REGULATORY_EXPERIMENTAL_AND_PREDICTED=' + (Cap 'REGULATORY_EXPERIMENTAL_AND_PREDICTED')),
        '',
        'FULL_EDGE_CONSERVATION=PASS',
        '',
        'DUPLICATE_REGULATORY_EDGES=0',
        'DUPLICATE_NONREGULATORY_EDGES=0',
        '',
        'SINGLE_PREDICTOR_ONLY_ELIGIBLE=NO',
        'SINGLE_PREDICTOR_EDGES_CLASSIFIED_REGULATORY=0',
        '',
        'MIRNA_IDENTITY_CHANGED=NO',
        'MRNA_SYMBOL_CHANGED=NO',
        '',
        'NETWORK_CONSTRUCTION_EXECUTED=NO',
        'ACLA_EXECUTED=NO',
        '',
        'D8B_SHA256_MANIFEST_CREATED=YES',
        'D8B_HASH_MISMATCHES=0',
        '',
        'READY_FOR_D9_MULTILAYER_NETWORK_CONSTRUCTION=YES',
        '',
        'STOP=YES'
    )
    $final | Set-Content -LiteralPath $FinalStatus -Encoding UTF8
    $final | Set-Content -LiteralPath $Summary -Encoding UTF8

    # Manifest covers every non-manifest D8B output.
    $outFiles = @(
        $PythonCopy,
        $FullClass,
        $RegFreeze,
        $RegSummary,
        $OverlapAudit,
        $NonReg,
        $Conservation,
        $Spec,
        $ResultJson,
        $Stdout,
        $Stderr,
        $Log,
        $FinalStatus
    )

    $manifestRows = foreach ($f in $outFiles) {
        $i = Get-Item -LiteralPath $f
        [pscustomobject]@{
            filename=$i.Name
            full_path=$i.FullName
            size_bytes=[Int64]$i.Length
            SHA256=(SHA $i.FullName)
        }
    }
    $manifestRows | Export-Csv `
        -LiteralPath $Manifest `
        -NoTypeInformation `
        -Encoding UTF8

    # Immediate manifest re-verification.
    $hashMismatches = 0
    $checkRows = @(Import-Csv -LiteralPath $Manifest)
    foreach ($row in $checkRows) {
        if (-not (Test-Path -LiteralPath $row.full_path -PathType Leaf)) {
            $hashMismatches++
            continue
        }
        $item = Get-Item -LiteralPath $row.full_path
        if (
            [Int64]$item.Length -ne [Int64]$row.size_bytes -or
            (SHA $row.full_path) -ne $row.SHA256.ToLowerInvariant()
        ) {
            $hashMismatches++
        }
    }
    if ($hashMismatches -ne 0) {
        throw ('D8B_POSTWRITE_HASH_MISMATCHES=' + $hashMismatches)
    }

    # Print EXACT requested final terminal block.
    $final | ForEach-Object { Write-Host $_ }

} catch {
    Write-FailClosed $_.Exception.Message
    exit 1
}
