$ErrorActionPreference = 'Stop'

# ============================================================
# GSE243219 D9 — FINAL MULTILAYER NETWORK CONSTRUCTION
# No A-CLA execution.
# ============================================================

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$D6Root = Join-Path $Project '06_ASSOCIATION_AND_STABILITY'
$D8Root = Join-Path $Project '07_TARGET_EVIDENCE'
$D9Root = Join-Path $Project '08_NETWORK_CONSTRUCTION'

$D7CRun = Join-Path $D6Root 'D7C_ASSOCIATION_STABILITY_AUDIT_EDGE_FREEZE_20260905_145214'
$D7CManifest = Join-Path $D7CRun 'D7C_OUTPUT_SHA256_MANIFEST.csv'
$D7CEdges = Join-Path $D7CRun 'D7C_FROZEN_STABLE_ASSOCIATION_EDGES.csv.gz'

$D8A3Run = Join-Path $D8Root 'D8A_V3_IDENTIFIER_BRIDGE_PREFLIGHT_20260905_191138'
$D8A3Manifest = Join-Path $D8A3Run 'D8A_V3_OUTPUT_SHA256_MANIFEST.csv'
$D8A3GeneAudit = Join-Path $D8A3Run 'D8A_V3_PROJECT_GENE_REFERENCE_MAPPING_AUDIT.csv'

# Latest D8B run is authoritative. If the newest D8B run is not PASS,
# fail closed rather than silently using an older run.
$D8BCandidates = @(
    Get-ChildItem -LiteralPath $D8Root -Directory -ErrorAction Stop |
    Where-Object { $_.Name -like 'D8B_TARGET_EVIDENCE_AUDIT_REGULATORY_FREEZE_*' } |
    Sort-Object Name -Descending
)
if ($D8BCandidates.Count -lt 1) {
    throw 'AUTHORITATIVE_D8B_RUN_NOT_FOUND'
}
$D8BRun = $D8BCandidates[0].FullName
$D8BManifest = Join-Path $D8BRun 'D8B_SHA256_MANIFEST.csv'
$D8BStatus = Join-Path $D8BRun 'D8B_FINAL_STATUS.txt'

if (-not (Test-Path -LiteralPath $D8BStatus -PathType Leaf)) {
    throw ('D8B_FINAL_STATUS_MISSING=' + $D8BStatus)
}
$d8bText = Get-Content -LiteralPath $D8BStatus -Raw
if (-not $d8bText.Contains('D8B_STATUS=PASS')) {
    throw ('LATEST_D8B_NOT_PASS=' + $D8BRun)
}
if (-not $d8bText.Contains('READY_FOR_D9_MULTILAYER_NETWORK_CONSTRUCTION=YES')) {
    throw 'LATEST_D8B_NOT_AUTHORIZED_FOR_D9'
}

$BundledPython = Join-Path $PSScriptRoot 'D9_FINAL_MULTILAYER_NETWORK_CONSTRUCTION.py'
$ExpectedPythonSHA256 = '95042273075df4c91210a96f3ebb4c273fd135bc3af962e223cd990150d7de1b'

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir = Join-Path $D9Root ('D9_FINAL_MULTILAYER_NETWORK_CONSTRUCTION_' + $Stamp)
$ReportDir = Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D9_' + $Stamp)
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PythonCopy = Join-Path $RunDir 'D9_FINAL_MULTILAYER_NETWORK_CONSTRUCTION.py'
$Stdout = Join-Path $RunDir 'D9_PYTHON_STDOUT.txt'
$Stderr = Join-Path $RunDir 'D9_PYTHON_STDERR.txt'
$Log = Join-Path $RunDir 'D9_PYTHON_LOG.txt'
$ResultJson = Join-Path $RunDir 'D9_RESULT.json'
$FinalStatus = Join-Path $RunDir 'D9_FINAL_STATUS.txt'
$Manifest = Join-Path $RunDir 'D9_SHA256_MANIFEST.csv'
$Summary = Join-Path $ReportDir 'PHASE_D9_SUMMARY.txt'

function SHA([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Write-FailClosed([string]$Reason) {
    $lines = @(
        '=== D9 MULTILAYER NETWORK CONSTRUCTION ===',
        '',
        'D9_STATUS=FAIL_CLOSED',
        'UPSTREAM_INPUT_INTEGRITY=FAIL',
        '',
        'MRNA_NODES=4467',
        'MIRNA_NODES=41',
        'TOTAL_NODES=4508',
        '',
        'FROZEN_LAYERS_DISCOVERED=',
        'FROZEN_LAYERS_INCLUDED=',
        '',
        'MRNA_MRNA_EDGES=',
        'MIRNA_MIRNA_EDGES=',
        'MRNA_MIRNA_ASSOCIATION_EDGES=',
        'REGULATORY_EDGES=',
        'NONREGULATORY_MRNA_MIRNA_ASSOCIATION_EDGES=',
        '',
        'REGULATORY_EXPERIMENTAL=',
        'REGULATORY_PREDICTED_CONSENSUS=',
        'REGULATORY_EXPERIMENTAL_AND_PREDICTED=',
        '',
        'ASSOCIATION_ONLY_EDGES_RETAINED=',
        'REGULATORY_EDGE_DOUBLE_COUNT_IN_FLATTENED_GRAPH=',
        '',
        'TOTAL_STRUCTURAL_EDGES=',
        'SELF_LOOPS=',
        'DUPLICATE_STRUCTURAL_EDGES=',
        'UNKNOWN_ENDPOINTS=',
        'INVALID_WEIGHTS=',
        '',
        'CONNECTED_COMPONENTS=',
        'LARGEST_COMPONENT_NODES=',
        'LARGEST_COMPONENT_FRACTION=',
        'ISOLATED_NODES=',
        '',
        'DE_RECOMPUTED=NO',
        'ASSOCIATION_RECOMPUTED=NO',
        'TARGET_EVIDENCE_RECOMPUTED=NO',
        '',
        'MRNA_IDENTITY_CHANGED=UNKNOWN',
        'MIRNA_IDENTITY_CHANGED=UNKNOWN',
        '',
        'D9_MASTER_NODES_CREATED=NO',
        'D9_MASTER_EDGES_CREATED=NO',
        'D9_LAYER_SUMMARY_CREATED=NO',
        '',
        'ACLA_INPUT_SCHEMA=',
        'ACLA_INPUT_GENERATED=NO',
        'ACLA_EXECUTED=NO',
        '',
        'D9_SHA256_MANIFEST_CREATED=NO',
        'D9_HASH_MISMATCHES=1',
        '',
        'NETWORK_CONSTRUCTION_EXECUTED=NO',
        'READY_FOR_ACLA_PREEXECUTION_FREEZE=NO',
        '',
        'STOP=YES'
    )
    $lines | Set-Content -LiteralPath $FinalStatus -Encoding UTF8
    $lines | Set-Content -LiteralPath $Summary -Encoding UTF8
    $lines | ForEach-Object { Write-Host $_ }
    Write-Host ('D9_FAIL_REASON=' + $Reason)
}

try {
    if (-not (Test-Path -LiteralPath $BundledPython -PathType Leaf)) {
        throw ('BUNDLED_PYTHON_MISSING=' + $BundledPython)
    }
    if ((SHA $BundledPython) -ne $ExpectedPythonSHA256) {
        throw 'BUNDLED_PYTHON_SHA256_CHANGED'
    }

    foreach ($p in @(
        $D8BManifest,$D8BStatus,
        $D7CManifest,$D7CEdges,
        $D8A3Manifest,$D8A3GeneAudit
    )) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
            throw ('REQUIRED_D9_INPUT_MISSING=' + $p)
        }
    }

    Copy-Item -LiteralPath $BundledPython -Destination $PythonCopy -Force
    if ((SHA $PythonCopy) -ne $ExpectedPythonSHA256) {
        throw 'D9_PYTHON_COPY_HASH_FAILED'
    }

    $PythonExe = Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING\D2D_PREFLIGHT_20260904_195001\venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) {
        throw ('PYTHON_EXECUTABLE_MISSING=' + $PythonExe)
    }

    Write-Host '=== GSE243219 D9 - FINAL MULTILAYER NETWORK CONSTRUCTION ==='
    Write-Host ('AUTHORITATIVE_D8B_RUN=' + $D8BRun)
    Write-Host 'NETWORK_CONSTRUCTION_EXECUTED=STARTING'
    Write-Host 'ACLA_EXECUTED=NO'

    $env:PYTHONUTF8='1'
    $env:PYTHONIOENCODING='utf-8'

    $args = @(
        '-u',
        $PythonCopy,
        $D8BRun,
        $D8BManifest,
        $D8BStatus,
        $D7CManifest,
        $D7CEdges,
        $D8A3Manifest,
        $D8A3GeneAudit,
        $Project,
        $RunDir
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
        throw ('D9_PYTHON_FAILED exit=' + $p.ExitCode + ' trace=' + ($stderrLines -join ' | '))
    }

    if (-not (Test-Path -LiteralPath $ResultJson -PathType Leaf)) {
        throw 'D9_RESULT_JSON_MISSING'
    }

    $r = Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json
    function Cap([string]$Key) { return [string]$r.$Key }

    foreach ($pair in @(
        @('D9_STATUS','PASS'),
        @('UPSTREAM_INPUT_INTEGRITY','PASS'),
        @('MRNA_NODES','4467'),
        @('MIRNA_NODES','41'),
        @('TOTAL_NODES','4508'),
        @('MRNA_MRNA_EDGES','0'),
        @('MIRNA_MIRNA_EDGES','0'),
        @('MRNA_MIRNA_ASSOCIATION_EDGES','11531'),
        @('REGULATORY_EDGES','1978'),
        @('NONREGULATORY_MRNA_MIRNA_ASSOCIATION_EDGES','9553'),
        @('REGULATORY_EXPERIMENTAL','1935'),
        @('REGULATORY_PREDICTED_CONSENSUS','6'),
        @('REGULATORY_EXPERIMENTAL_AND_PREDICTED','37'),
        @('ASSOCIATION_ONLY_EDGES_RETAINED','9553'),
        @('REGULATORY_EDGE_DOUBLE_COUNT_IN_FLATTENED_GRAPH','0'),
        @('TOTAL_STRUCTURAL_EDGES','11531'),
        @('SELF_LOOPS','0'),
        @('DUPLICATE_STRUCTURAL_EDGES','0'),
        @('UNKNOWN_ENDPOINTS','0'),
        @('INVALID_WEIGHTS','0'),
        @('DE_RECOMPUTED','NO'),
        @('ASSOCIATION_RECOMPUTED','NO'),
        @('TARGET_EVIDENCE_RECOMPUTED','NO'),
        @('MRNA_IDENTITY_CHANGED','NO'),
        @('MIRNA_IDENTITY_CHANGED','NO'),
        @('D9_MASTER_NODES_CREATED','YES'),
        @('D9_MASTER_EDGES_CREATED','YES'),
        @('D9_LAYER_SUMMARY_CREATED','YES'),
        @('ACLA_INPUT_GENERATED','YES'),
        @('ACLA_EXECUTED','NO'),
        @('NETWORK_CONSTRUCTION_EXECUTED','YES'),
        @('READY_FOR_ACLA_PREEXECUTION_FREEZE','YES'),
        @('STOP','YES')
    )) {
        $obs = Cap $pair[0]
        if ($obs -ne $pair[1]) {
            throw ('D9_FINAL_GATE_FAILED key=' + $pair[0] + ' expected=' + $pair[1] + ' observed=' + $obs)
        }
    }

    # Required D9 outputs before final status / manifest.
    $requiredFiles = @(
        'D9_MASTER_NODES.csv',
        'D9_MASTER_EDGES.csv',
        'D9_LAYER_INVENTORY.csv',
        'D9_LAYER_SUMMARY.csv',
        'D9_MRNA_MIRNA_ASSOCIATION_EDGES.csv',
        'D9_REGULATORY_EDGE_LAYER.csv',
        'D9_REGULATORY_COVERAGE_AUDIT.csv',
        'D9_NETWORK_QC_SUMMARY.csv',
        'D9_DE_METADATA_AUDIT.csv',
        'D9_ACLA_CODE_INVENTORY.csv',
        'D9_AUTHORITATIVE_UPSTREAM_HASHES.csv',
        'D9_EXECUTION_SPECIFICATION.txt',
        'D9_RESULT.json'
    )
    foreach ($name in $requiredFiles) {
        $f = Join-Path $RunDir $name
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
            throw ('D9_REQUIRED_OUTPUT_MISSING=' + $f)
        }
    }

    $ACLAInputDir = Join-Path $RunDir 'D9_ACLA_INPUT'
    foreach ($name in @(
        'node_index.csv',
        'structural_edge_list.csv',
        'regulatory_semantic_edge_list.csv',
        'association_score_symmetric_coo.npz',
        'stability_score_symmetric_coo.npz',
        'regulatory_binary_symmetric_coo.npz',
        'input_schema.json',
        'README.txt'
    )) {
        $f = Join-Path $ACLAInputDir $name
        if (-not (Test-Path -LiteralPath $f -PathType Leaf)) {
            throw ('D9_ACLA_INPUT_OUTPUT_MISSING=' + $f)
        }
    }

    $final = @(
        '=== D9 MULTILAYER NETWORK CONSTRUCTION ===',
        '',
        'D9_STATUS=PASS',
        'UPSTREAM_INPUT_INTEGRITY=PASS',
        '',
        'MRNA_NODES=4467',
        'MIRNA_NODES=41',
        'TOTAL_NODES=4508',
        '',
        ('FROZEN_LAYERS_DISCOVERED=' + (Cap 'FROZEN_LAYERS_DISCOVERED')),
        ('FROZEN_LAYERS_INCLUDED=' + (Cap 'FROZEN_LAYERS_INCLUDED')),
        '',
        ('MRNA_MRNA_EDGES=' + (Cap 'MRNA_MRNA_EDGES')),
        ('MIRNA_MIRNA_EDGES=' + (Cap 'MIRNA_MIRNA_EDGES')),
        'MRNA_MIRNA_ASSOCIATION_EDGES=11531',
        'REGULATORY_EDGES=1978',
        'NONREGULATORY_MRNA_MIRNA_ASSOCIATION_EDGES=9553',
        '',
        'REGULATORY_EXPERIMENTAL=1935',
        'REGULATORY_PREDICTED_CONSENSUS=6',
        'REGULATORY_EXPERIMENTAL_AND_PREDICTED=37',
        '',
        'ASSOCIATION_ONLY_EDGES_RETAINED=9553',
        'REGULATORY_EDGE_DOUBLE_COUNT_IN_FLATTENED_GRAPH=0',
        '',
        'TOTAL_STRUCTURAL_EDGES=11531',
        ('SELF_LOOPS=' + (Cap 'SELF_LOOPS')),
        ('DUPLICATE_STRUCTURAL_EDGES=' + (Cap 'DUPLICATE_STRUCTURAL_EDGES')),
        ('UNKNOWN_ENDPOINTS=' + (Cap 'UNKNOWN_ENDPOINTS')),
        ('INVALID_WEIGHTS=' + (Cap 'INVALID_WEIGHTS')),
        '',
        ('CONNECTED_COMPONENTS=' + (Cap 'CONNECTED_COMPONENTS')),
        ('LARGEST_COMPONENT_NODES=' + (Cap 'LARGEST_COMPONENT_NODES')),
        ('LARGEST_COMPONENT_FRACTION=' + (Cap 'LARGEST_COMPONENT_FRACTION')),
        ('ISOLATED_NODES=' + (Cap 'ISOLATED_NODES')),
        '',
        'DE_RECOMPUTED=NO',
        'ASSOCIATION_RECOMPUTED=NO',
        'TARGET_EVIDENCE_RECOMPUTED=NO',
        '',
        'MRNA_IDENTITY_CHANGED=NO',
        'MIRNA_IDENTITY_CHANGED=NO',
        '',
        'D9_MASTER_NODES_CREATED=YES',
        'D9_MASTER_EDGES_CREATED=YES',
        'D9_LAYER_SUMMARY_CREATED=YES',
        '',
        ('ACLA_INPUT_SCHEMA=' + (Cap 'ACLA_INPUT_SCHEMA')),
        ('ACLA_CODE_VERSION_OR_HASH=' + (Cap 'ACLA_CODE_VERSION_OR_HASH')),
        ('ACLA_CODE_CANDIDATES=' + (Cap 'ACLA_CODE_CANDIDATES')),
        'ACLA_INPUT_GENERATED=YES',
        'ACLA_EXECUTED=NO',
        '',
        'D9_SHA256_MANIFEST_CREATED=YES',
        'D9_HASH_MISMATCHES=0',
        '',
        'NETWORK_CONSTRUCTION_EXECUTED=YES',
        'READY_FOR_ACLA_PREEXECUTION_FREEZE=YES',
        '',
        'STOP=YES'
    )
    $final | Set-Content -LiteralPath $FinalStatus -Encoding UTF8
    $final | Set-Content -LiteralPath $Summary -Encoding UTF8

    # Hash every D9 output except the manifest itself; include nested ACLA input.
    $outputFiles = @(
        Get-ChildItem -LiteralPath $RunDir -Recurse -File |
        Where-Object { $_.FullName -ne $Manifest }
    )
    $manifestRows = foreach ($f in $outputFiles) {
        [pscustomobject]@{
            relative_path = $f.FullName.Substring($RunDir.Length).TrimStart('\')
            full_path = $f.FullName
            size_bytes = [Int64]$f.Length
            SHA256 = (SHA $f.FullName)
        }
    }
    $manifestRows | Export-Csv -LiteralPath $Manifest -NoTypeInformation -Encoding UTF8

    # Immediate post-write hash verification.
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
        throw ('D9_POSTWRITE_HASH_MISMATCHES=' + $hashMismatches)
    }

    $final | ForEach-Object { Write-Host $_ }

} catch {
    Write-FailClosed $_.Exception.Message
    exit 1
}
