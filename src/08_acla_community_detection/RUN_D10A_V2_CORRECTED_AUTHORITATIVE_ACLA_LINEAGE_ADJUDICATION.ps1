$ErrorActionPreference = 'Stop'

$Parent = 'C:\Users\Amir\OneDrive\Desktop\covid-19'
$Project = Join-Path $Parent 'GSE243219_NEW_PROJECT'
$Reusable = Join-Path $Parent '00_REUSABLE_ASSETS'
$D9Root = Join-Path $Project '08_NETWORK_CONSTRUCTION'
$D10Root = Join-Path $Project '09_ACLA'

$D9Candidates = @(Get-ChildItem -LiteralPath $D9Root -Directory | Where-Object { $_.Name -like 'D9_FINAL_MULTILAYER_NETWORK_CONSTRUCTION_*' } | Sort-Object Name -Descending)
if ($D9Candidates.Count -lt 1) { throw 'AUTHORITATIVE_D9_RUN_NOT_FOUND' }
$D9Run = $D9Candidates[0].FullName

$PriorV2='NONE'
$V2Candidates=@(Get-ChildItem -LiteralPath $D10Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'D10A_V2_LINEAGE_ADJUDICATION_*' } | Sort-Object Name -Descending)
if ($V2Candidates.Count -ge 1) { $PriorV2=$V2Candidates[0].FullName }

$BundledPython=Join-Path $PSScriptRoot 'D10A_V2_CORRECTED_AUTHORITATIVE_ACLA_LINEAGE_ADJUDICATION.py'
$ExpectedPythonSHA256='effd14afe05a9e6f0cc1778d621cd192c2be2b4bf0fe34ecf29691153924c196'

$Stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$RunDir=Join-Path $D10Root ('D10A_V2_CORRECTED_LINEAGE_ADJUDICATION_' + $Stamp)
$ReportDir=Join-Path $env:USERPROFILE ('Downloads\GSE243219_PHASE_D10A_V2_CORRECTED_' + $Stamp)
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null

$PythonCopy=Join-Path $RunDir 'D10A_V2_CORRECTED_AUTHORITATIVE_ACLA_LINEAGE_ADJUDICATION.py'
$Stdout=Join-Path $RunDir 'D10A_V2_PYTHON_STDOUT.txt'
$Stderr=Join-Path $RunDir 'D10A_V2_PYTHON_STDERR.txt'
$Log=Join-Path $RunDir 'D10A_V2_PYTHON_LOG.txt'
$ResultJson=Join-Path $RunDir 'D10A_V2_RESULT.json'
$FinalStatus=Join-Path $RunDir 'D10A_V2_FINAL_STATUS.txt'
$Manifest=Join-Path $RunDir 'D10A_V2_SHA256_MANIFEST.csv'
$Summary=Join-Path $ReportDir 'PHASE_D10A_V2_SUMMARY.txt'

function SHA([string]$Path) { return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant() }

try {
    if (-not (Test-Path -LiteralPath $BundledPython -PathType Leaf)) { throw 'BUNDLED_PYTHON_MISSING' }
    if ((SHA $BundledPython) -ne $ExpectedPythonSHA256) { throw 'BUNDLED_PYTHON_SHA_CHANGED' }
    Copy-Item -LiteralPath $BundledPython -Destination $PythonCopy -Force

    $PythonExe=Join-Path $Project '02_INPUT_AUDIT_AND_PAIRING\D2D_PREFLIGHT_20260904_195001\venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $PythonExe -PathType Leaf)) { throw 'PYTHON_EXECUTABLE_MISSING' }

    Write-Host '=== GSE243219 D10A-V2 CORRECTED - AUTHORITATIVE A-CLA LINEAGE ADJUDICATION ==='
    Write-Host ('AUTHORITATIVE_D9_RUN=' + $D9Run)
    Write-Host ('PRIOR_D10A_V2_RUN=' + $PriorV2)
    Write-Host 'FAMILY_ASSIGNMENT=PATH_FILENAME_FIRST_ONLY'
    Write-Host 'DECISION_EVIDENCE=AUTHORITATIVE_REPORTS_ONLY'
    Write-Host 'GSE243219_ACLA_EXECUTED=NO'

    $args=@('-u',$PythonCopy,$Project,$Reusable,$D9Run,$PriorV2,$RunDir,$ResultJson)
    $p=Start-Process -FilePath $PythonExe -ArgumentList $args -Wait -PassThru -NoNewWindow -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr
    $stdoutLines=@();$stderrLines=@()
    if(Test-Path $Stdout){$stdoutLines=@(Get-Content $Stdout)}
    if(Test-Path $Stderr){$stderrLines=@(Get-Content $Stderr)}
    @('=== STDOUT ===',$stdoutLines,'','=== STDERR ===',$stderrLines) | Set-Content -LiteralPath $Log -Encoding UTF8
    if([int]$p.ExitCode -ne 0){throw ('D10A_V2_PYTHON_FAILED exit=' + $p.ExitCode + ' trace=' + ($stderrLines -join ' | '))}
    $r=Get-Content -LiteralPath $ResultJson -Raw | ConvertFrom-Json
    function Cap([string]$K){$v=$r.$K;if($null -eq $v){return ''};return [string]$v}

    foreach($pair in @(
        @('INPUT_NODES','4508'),@('INPUT_EDGES','11531'),
        @('SIGNED_WEIGHTS_PRESENT','YES'),
        @('OLD_DATASET_DERIVED_PARAMETER_CARRIED_FORWARD','NO'),
        @('NETWORK_CHANGED','NO'),@('WEIGHT_TRANSFORMATION_APPLIED','NO'),
        @('PARAMETER_TUNING_EXECUTED','NO'),@('GSE243219_ACLA_EXECUTED','NO'),
        @('COMMUNITY_RESULTS_CREATED','NO'),@('READY_FOR_ACLA_EXECUTION','NO'),
        @('STOP','YES')
    )){
        if((Cap $pair[0]) -ne $pair[1]){throw ('SAFETY_GATE_FAILED=' + $pair[0])}
    }

    foreach($name in @(
        'D10A_V2_ACLA_FILE_INVENTORY.csv',
        'D10A_V2_IMPLEMENTATION_FAMILIES.csv',
        'D10A_V2_LINEAGE_TIMELINE.csv',
        'D10A_V2_ALGORITHM_SEMANTIC_COMPARISON.csv',
        'D10A_V2_VALIDATION_EVIDENCE.csv',
        'D10A_V2_R1_LIFECYCLE_GATE_AUDIT.csv',
        'D10A_V2_PARAMETER_PROVENANCE_AUDIT.csv',
        'D10A_V2_ADJUDICATION_SPECIFICATION.txt',
        'D10A_V2_RESULT.json'
    )){
        if(-not(Test-Path -LiteralPath (Join-Path $RunDir $name) -PathType Leaf)){throw ('REQUIRED_OUTPUT_MISSING=' + $name)}
    }

    $final=@(
        '=== D10A-V2 AUTHORITATIVE A-CLA LINEAGE ADJUDICATION ===','',
        ('D10A_V2_STATUS=' + (Cap 'D10A_V2_STATUS')),'',
        ('DISCOVERED_ACLA_FILES=' + (Cap 'DISCOVERED_ACLA_FILES')),
        ('IMPLEMENTATION_FAMILIES_IDENTIFIED=' + (Cap 'IMPLEMENTATION_FAMILIES_IDENTIFIED')),'',
        ('PUBLISHED_BASELINE_FAMILY=' + (Cap 'PUBLISHED_BASELINE_FAMILY')),
        ('SUPERSEDED_FAMILIES=' + (Cap 'SUPERSEDED_FAMILIES')),
        ('DIAGNOSTIC_ONLY_FAMILIES=' + (Cap 'DIAGNOSTIC_ONLY_FAMILIES')),
        ('REJECTED_FAMILIES=' + (Cap 'REJECTED_FAMILIES')),'',
        ('B1A_EVIDENCE_FOUND=' + (Cap 'B1A_EVIDENCE_FOUND')),
        ('B1B_EVIDENCE_FOUND=' + (Cap 'B1B_EVIDENCE_FOUND')),
        ('B1C0_R1_DESIGN_EVIDENCE_FOUND=' + (Cap 'B1C0_R1_DESIGN_EVIDENCE_FOUND')),'',
        ('R1_DESIGN_VALIDATED=' + (Cap 'R1_DESIGN_VALIDATED')),
        ('R1_IMPLEMENTATION_FOUND=' + (Cap 'R1_IMPLEMENTATION_FOUND')),
        ('R1_IMPLEMENTATION_EXECUTED=' + (Cap 'R1_IMPLEMENTATION_EXECUTED')),
        ('R1_IMPLEMENTATION_BENCHMARKED=' + (Cap 'R1_IMPLEMENTATION_BENCHMARKED')),
        ('R1_IMPLEMENTATION_ACCEPTED=' + (Cap 'R1_IMPLEMENTATION_ACCEPTED')),
        ('ACCEPTANCE_SIGNAL_PRESENT_BUT_INVALID_WITHOUT_PRIOR_GATES=' + (Cap 'ACCEPTANCE_SIGNAL_PRESENT_BUT_INVALID_WITHOUT_PRIOR_GATES')),'',
        ('AUTHORITATIVE_ACLA_IMPLEMENTATION_FOUND=' + (Cap 'AUTHORITATIVE_ACLA_IMPLEMENTATION_FOUND')),
        ('ACLA_IMPLEMENTATION_AMBIGUOUS=' + (Cap 'ACLA_IMPLEMENTATION_AMBIGUOUS')),'',
        ('ACLA_AUTHORITATIVE_FAMILY=' + (Cap 'ACLA_AUTHORITATIVE_FAMILY')),
        ('ACLA_AUTHORITATIVE_ENTRYPOINT=' + (Cap 'ACLA_AUTHORITATIVE_ENTRYPOINT')),
        ('ACLA_ENTRYPOINT_SHA256=' + (Cap 'ACLA_ENTRYPOINT_SHA256')),
        ('ACLA_IMPLEMENTATION_PACKAGE_SHA256=' + (Cap 'ACLA_IMPLEMENTATION_PACKAGE_SHA256')),
        ('AUTHORITATIVE_SELECTION_BASIS=' + (Cap 'AUTHORITATIVE_SELECTION_BASIS')),'',
        'INPUT_NODES=4508','INPUT_EDGES=11531','SIGNED_WEIGHTS_PRESENT=YES',
        ('INPUT_WEIGHT_MIN=' + (Cap 'INPUT_WEIGHT_MIN')),
        ('INPUT_WEIGHT_MAX=' + (Cap 'INPUT_WEIGHT_MAX')),'',
        ('AUTHORITATIVE_SIGNED_WEIGHT_POLICY=' + (Cap 'AUTHORITATIVE_SIGNED_WEIGHT_POLICY')),
        ('D9_SIGNED_WEIGHT_COMPATIBLE=' + (Cap 'D9_SIGNED_WEIGHT_COMPATIBLE')),
        ('D9_SCHEMA_COMPATIBLE=' + (Cap 'D9_SCHEMA_COMPATIBLE')),
        ('D9_COMPONENT_STRUCTURE_COMPATIBLE=' + (Cap 'D9_COMPONENT_STRUCTURE_COMPATIBLE')),
        ('D9_REGULATORY_CHANNEL_COMPATIBLE=' + (Cap 'D9_REGULATORY_CHANNEL_COMPATIBLE')),'',
        'OLD_DATASET_DERIVED_PARAMETER_CARRIED_FORWARD=NO',
        'NETWORK_CHANGED=NO','WEIGHT_TRANSFORMATION_APPLIED=NO',
        'PARAMETER_TUNING_EXECUTED=NO','GSE243219_ACLA_EXECUTED=NO','',
        'D10A_V2_SHA256_MANIFEST_CREATED=YES','D10A_V2_HASH_MISMATCHES=0','',
        ('FAILURE_STAGE=' + (Cap 'FAILURE_STAGE')),
        ('FAILURE_REASON=' + (Cap 'FAILURE_REASON')),'',
        ('READY_FOR_ACLA_PARAMETER_FREEZE=' + (Cap 'READY_FOR_ACLA_PARAMETER_FREEZE')),
        'READY_FOR_ACLA_EXECUTION=NO','','STOP=YES'
    )
    $final | Set-Content -LiteralPath $FinalStatus -Encoding UTF8
    $final | Set-Content -LiteralPath $Summary -Encoding UTF8

    $files=@(Get-ChildItem -LiteralPath $RunDir -Recurse -File | Where-Object {$_.FullName -ne $Manifest})
    $rows=foreach($f in $files){[pscustomobject]@{relative_path=$f.FullName.Substring($RunDir.Length).TrimStart('\');full_path=$f.FullName;size_bytes=[Int64]$f.Length;SHA256=(SHA $f.FullName)}}
    $rows | Export-Csv -LiteralPath $Manifest -NoTypeInformation -Encoding UTF8
    $bad=0
    foreach($row in @(Import-Csv $Manifest)){
        if(-not(Test-Path $row.full_path)){$bad++;continue}
        $fi=Get-Item $row.full_path
        if([Int64]$fi.Length -ne [Int64]$row.size_bytes -or (SHA $row.full_path) -ne $row.SHA256.ToLowerInvariant()){$bad++}
    }
    if($bad -ne 0){throw ('POSTWRITE_HASH_MISMATCHES=' + $bad)}

    $final | ForEach-Object {Write-Host $_}
} catch {
    Write-Host '=== D10A-V2 AUTHORITATIVE A-CLA LINEAGE ADJUDICATION ==='
    Write-Host 'D10A_V2_STATUS=FAIL_CLOSED'
    Write-Host 'GSE243219_ACLA_EXECUTED=NO'
    Write-Host 'READY_FOR_ACLA_PARAMETER_FREEZE=NO'
    Write-Host 'READY_FOR_ACLA_EXECUTION=NO'
    Write-Host ('FAILURE_REASON=PACKAGE_EXECUTION_FAILURE:' + $_.Exception.Message)
    Write-Host 'STOP=YES'
    exit 1
}
