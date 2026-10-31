<#
.SYNOPSIS
Read-only Bicep-vs-Azure drift detection in a single run.
.DESCRIPTION
Orchestrates the shared AzVerify scripts: auth check, Bicep parse (with deterministic
name resolution and secret masking), expected-resource filtering, expected-aware Azure
discovery (one inventory call plus detail reads only where needed), and tracked-property
comparison. Writes a Markdown report and a machine-readable summary.
Only GET/list/show Azure calls are made. Nothing in Azure is created, changed or deleted.
Scope, authentication and compile failures stop the run (exit 1). Individual unreadable
resources or unresolved values produce an INCOMPLETE report (exit 2) instead of aborting.
.PARAMETER BicepFile
Path to the Bicep template (main.bicep).
.PARAMETER ParamFile
Optional .bicepparam or ARM JSON parameter file.
.PARAMETER ParameterOverride
Optional hashtable of parameter values (for example pipeline variables).
.PARAMETER ResourceGroup
Target resource group. Never inferred from folder names.
.PARAMETER SubscriptionId
Target subscription ID. Required so every request is explicitly scoped.
.PARAMETER Location
Optional deployment location used when resolving expressions. Defaults to the resource group location.
.PARAMETER Backend
Authentication backend preference for the auth probe.
.PARAMETER OutputDirectory
Directory for the report and intermediate files. Defaults to .azverify-tmp in the current directory.
.PARAMETER ThrottleLimit
Maximum concurrent detail reads (PowerShell 7).
.PARAMETER MaxRetry
Maximum transient retries per read.
.PARAMETER KeepIntermediate
Keep intermediate model files next to the report.
.EXAMPLE
pwsh Invoke-BicepDriftDetection.ps1 -BicepFile .\main.bicep -ParamFile .\main.bicepparam -ResourceGroup rg-demo -SubscriptionId 00000000-0000-0000-0000-000000000000
.OUTPUTS
PSCustomObject with Status, ReportPath, SummaryPath and counts.
.NOTES
Exit codes: 0 complete, 2 incomplete, 1 failed.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$BicepFile,
    [string]$ParamFile,
    [hashtable]$ParameterOverride = @{},
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ResourceGroup,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$SubscriptionId,
    [string]$Location,
    [ValidateSet('Auto', 'AzureCLI', 'AzPowerShell')][string]$Backend = 'Auto',
    [string]$OutputDirectory = (Join-Path (Get-Location) '.azverify-tmp'),
    [ValidateRange(1, 16)][int]$ThrottleLimit = 4,
    [ValidateRange(0, 5)][int]$MaxRetry = 2,
    [switch]$KeepIntermediate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$shared = Join-Path $PSScriptRoot '..\..\shared\scripts'
$timer = [System.Diagnostics.Stopwatch]::StartNew()
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$paths = @{
    Auth     = Join-Path $OutputDirectory 'auth.json'
    Expected = Join-Path $OutputDirectory 'expected.json'
    Filtered = Join-Path $OutputDirectory 'expected-filtered.json'
    Actual   = Join-Path $OutputDirectory 'actual.json'
    Compare  = Join-Path $OutputDirectory 'comparison.json'
    Report   = Join-Path $OutputDirectory 'drift-report.md'
    Summary  = Join-Path $OutputDirectory 'drift-summary.json'
}

function Stop-Run {
    param([string]$Message)
    [Console]::Error.WriteLine("FAILED: $Message")
    exit 1
}

try {
    Write-Progress -Activity 'Bicep drift detection' -Status 'Checking authentication'
    & (Join-Path $shared 'Test-AzureAuth.ps1') -Backend $Backend -SubscriptionId $SubscriptionId -OutFile $paths.Auth 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Run 'Not authenticated to Azure for the requested subscription. Sign in (az login) and retry.' }

    $groupJson = az group show --name $ResourceGroup --subscription $SubscriptionId --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $groupJson) { Stop-Run "Resource group '$ResourceGroup' was not found or is not readable in subscription '$SubscriptionId'." }
    $group = $groupJson | ConvertFrom-Json
    if (-not $Location) { $Location = [string]$group.location }

    Write-Progress -Activity 'Bicep drift detection' -Status 'Parsing Bicep'
    $parseArguments = @{
        BicepFile = $BicepFile; SubscriptionId = $SubscriptionId; ResourceGroup = $ResourceGroup; Location = $Location
        ResolveDeterministicNames = $true; MaskSecrets = $true; ParameterOverride = $ParameterOverride; OutFile = $paths.Expected
    }
    if ($ParamFile) { $parseArguments.ParamFile = $ParamFile }
    & (Join-Path $shared 'ConvertFrom-BicepTemplate.ps1') @parseArguments 2>$null 6>$null
    if ($LASTEXITCODE -ne 0) { Stop-Run 'Bicep compilation or parameter evaluation failed. Run the parser directly for details.' }
    $expected = Get-Content -LiteralPath $paths.Expected -Raw | ConvertFrom-Json

    & (Join-Path $shared 'Select-AzureResources.ps1') -Mode bicep -InputFile $paths.Expected -OutFile $paths.Filtered 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Run 'Expected-resource filtering failed.' }

    Write-Progress -Activity 'Bicep drift detection' -Status 'Reading Azure (read-only)'
    & (Join-Path $shared 'Get-AzureResourceModel.ps1') -ResourceGroup $ResourceGroup -SubscriptionId $SubscriptionId `
        -ExpectedModel $paths.Filtered -Mode bicep -ThrottleLimit $ThrottleLimit -MaxRetry $MaxRetry -OutFile $paths.Actual 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Run 'Azure discovery failed (inventory could not be read).' }
    $actual = Get-Content -LiteralPath $paths.Actual -Raw | ConvertFrom-Json

    Write-Progress -Activity 'Bicep drift detection' -Status 'Comparing'
    & (Join-Path $shared 'Compare-ResourceModels.ps1') -ModelA $paths.Filtered -ModelB $paths.Actual -LabelA 'Bicep' -LabelB 'Azure' `
        -AzureIdentity -TrackedProperties -OutFile $paths.Compare 2>$null
    if ($LASTEXITCODE -ne 0) { Stop-Run 'Comparison failed.' }
    $comparison = Get-Content -LiteralPath $paths.Compare -Raw | ConvertFrom-Json
}
finally {
    Write-Progress -Activity 'Bicep drift detection' -Completed
}

$diagnostics = if ($expected.PSObject.Properties['diagnostics']) { $expected.diagnostics } else { $null }
$issues = @(if ($actual.PSObject.Properties['issues']) { $actual.issues })
$metrics = if ($actual.PSObject.Properties['metrics']) { $actual.metrics } else { $null }

$create = [System.Collections.Generic.List[object]]::new()
$modify = [System.Collections.Generic.List[object]]::new()
$extra = [System.Collections.Generic.List[object]]::new()
$unresolved = [System.Collections.Generic.List[object]]::new()
$noChange = 0
$uncertainCount = 0
foreach ($entry in @($comparison.matches)) {
    switch ($entry.status) {
        'Bicep Only' { $create.Add($entry.resourceA) }
        'Azure Only' { $extra.Add($entry.resourceB) }
        'Unresolved' { $unresolved.Add($entry.resourceA) }
        default {
            $propertyComparison = if ($entry.PSObject.Properties['propertyComparison']) { $entry.propertyComparison } else { $null }
            if ($propertyComparison -and @($propertyComparison.drifts).Count -gt 0) { $modify.Add($entry) }
            else { $noChange++ }
            if ($propertyComparison -and $propertyComparison.PSObject.Properties['uncertainties']) { $uncertainCount += @($propertyComparison.uncertainties).Count }
        }
    }
}

$unresolvedNames = if ($diagnostics) { [int]$diagnostics.unresolvedNames } else { 0 }
$missingParameters = @(if ($diagnostics) { $diagnostics.missingParameters })
$incompleteReasons = [System.Collections.Generic.List[string]]::new()
if ($unresolved.Count -gt 0 -or $unresolvedNames -gt 0) { $incompleteReasons.Add("$([Math]::Max($unresolved.Count, $unresolvedNames)) expected resource name(s) could not be resolved") }
if ($missingParameters.Count -gt 0) { $incompleteReasons.Add("parameters without values: $($missingParameters -join ', ')") }
if ($issues.Count -gt 0) { $incompleteReasons.Add("$($issues.Count) Azure read(s) unavailable") }
if ($uncertainCount -gt 0) { $incompleteReasons.Add("$uncertainCount property value(s) unknown or unresolved") }
$status = if ($incompleteReasons.Count -gt 0) { 'INCOMPLETE' } else { 'COMPLETE' }

$report = [System.Text.StringBuilder]::new()
[void]$report.AppendLine("# Bicep drift report ($status)")
[void]$report.AppendLine()
[void]$report.AppendLine("Scope: subscription ``$SubscriptionId``, resource group ``$ResourceGroup``. Read-only run.")
if ($status -eq 'INCOMPLETE') {
    [void]$report.AppendLine()
    [void]$report.AppendLine('> **INCOMPLETE** - results below exclude anything that could not be verified:')
    foreach ($reason in $incompleteReasons) { [void]$report.AppendLine("> - $reason") }
}
[void]$report.AppendLine()
[void]$report.AppendLine('| Category | Count |')
[void]$report.AppendLine('|---|---|')
[void]$report.AppendLine("| Create (in Bicep, not in Azure) | $($create.Count) |")
[void]$report.AppendLine("| Modify (property drift) | $($modify.Count) |")
[void]$report.AppendLine("| Not in template (in Azure only) | $($extra.Count) |")
[void]$report.AppendLine("| Unverified | $($unresolved.Count + $issues.Count) |")
[void]$report.AppendLine("| No change | $noChange |")

if ($create.Count -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('## Create')
    foreach ($resource in $create) { [void]$report.AppendLine("- ``$($resource.type)`` ``$($resource.name)``") }
}
if ($modify.Count -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('## Modify')
    foreach ($entry in $modify) {
        [void]$report.AppendLine("- ``$($entry.resourceA.type)`` ``$($entry.resourceA.name)``")
        foreach ($drift in @($entry.propertyComparison.drifts)) {
            [void]$report.AppendLine("  - $($drift.property): Bicep ``$($drift | Select-Object -ExpandProperty valueA | ConvertTo-Json -Compress -Depth 5)`` vs Azure ``$($drift | Select-Object -ExpandProperty valueB | ConvertTo-Json -Compress -Depth 5)``")
        }
    }
}
if ($extra.Count -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('## Not in template (in Azure only)')
    [void]$report.AppendLine('These may be unmanaged, created by Azure automatically, or child resources outside this template. Review before deleting anything.')
    foreach ($resource in $extra) { [void]$report.AppendLine("- ``$($resource.type)`` ``$($resource.name)``") }
}
if ($unresolved.Count -gt 0 -or $issues.Count -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('## Unverified')
    foreach ($resource in $unresolved) { [void]$report.AppendLine("- ``$($resource.type)`` ``$($resource.name)``: identity not resolvable") }
    foreach ($issue in $issues) { [void]$report.AppendLine("- ``$($issue.resourceId)``: $($issue.errorCode)") }
}
$elapsed = [Math]::Round($timer.Elapsed.TotalSeconds, 1)
$requestText = if ($metrics) { ", $($metrics.armRequests) ARM request(s), $($metrics.retries) retries" } else { '' }
[void]$report.AppendLine(); [void]$report.AppendLine("_Elapsed ${elapsed}s$requestText._")
Set-Content -LiteralPath $paths.Report -Value $report.ToString() -Encoding utf8

$summary = [ordered]@{
    status = $status; subscriptionId = $SubscriptionId; resourceGroup = $ResourceGroup
    create = $create.Count; modify = $modify.Count; notInTemplate = $extra.Count
    unverified = $unresolved.Count + $issues.Count; noChange = $noChange
    incompleteReasons = @($incompleteReasons); elapsedSeconds = $elapsed; metrics = $metrics
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $paths.Summary -Encoding utf8

if (-not $KeepIntermediate) {
    foreach ($name in 'Auth', 'Expected', 'Filtered', 'Actual', 'Compare') { Remove-Item -LiteralPath $paths[$name] -Force -ErrorAction SilentlyContinue }
}

[pscustomobject]@{
    Status = $status; ReportPath = $paths.Report; SummaryPath = $paths.Summary
    Create = $create.Count; Modify = $modify.Count; NotInTemplate = $extra.Count; Unverified = $unresolved.Count + $issues.Count; NoChange = $noChange
}
if ($status -eq 'INCOMPLETE') { exit 2 }
