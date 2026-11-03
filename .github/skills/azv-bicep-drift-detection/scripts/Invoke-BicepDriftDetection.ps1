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
.PARAMETER PipelineFile
Pipeline reference for provenance only; pass its effective values using ParameterOverride.
.PARAMETER DeploymentMode
Deployment mode read from the selected pipeline. Unknown unless supplied.
.PARAMETER BuildVersion
Version of the template artifact being compared. Unverified unless supplied.
.PARAMETER ParameterSource
Whether inputs are explicit, current pipeline values, or a historical fallback.
.PARAMETER AnalysisTimestamp
Optional fixed timestamp for analysis-only utcNow defaults; never verifies deployed identities.
.PARAMETER ResourceGroup
Target resource group. Never inferred from folder names.
.PARAMETER SubscriptionId
Target subscription ID. Required so every request is explicitly scoped.
.PARAMETER Location
Optional deployment location used when resolving expressions. Defaults to the resource group location.
.PARAMETER Backend
AzureCLI only. Auto selects AzureCLI; AzPowerShell is rejected before authentication.
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
    [string]$PipelineFile,
    [ValidateSet('Incremental', 'Complete', 'Unknown')][string]$DeploymentMode = 'Unknown',
    [string]$BuildVersion,
    [ValidateSet('ExplicitInput', 'CurrentPipeline', 'HistoricalFallback')][string]$ParameterSource = 'ExplicitInput',
    [datetimeoffset]$AnalysisTimestamp,
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
. (Join-Path $shared '_ResourceProjection.ps1')
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

function Format-ReportValue {
    param([AllowNull()]$Value)
    $text = ConvertTo-Json -InputObject $Value -Compress -Depth 100
    return ($text -replace '\|', '&#124;' -replace '`', '&#96;' -replace '[\r\n]', ' ')
}

function Add-PropertyReport {
    param($Entry)
    [void]$report.AppendLine("### ``$($Entry.resourceA.id)``")
    [void]$report.AppendLine('| Property | Azure value | Bicep value | Source | Interpretation / decisions |')
    [void]$report.AppendLine('|---|---|---|---|---|')
    foreach ($drift in @($Entry.propertyComparison.drifts)) {
        $sources = Get-ModelMember $Entry.resourceA 'propertySources'
        $source = Get-ModelMember $sources $drift.property
        if (-not $source) { $source = Get-ModelMember $Entry.resourceA 'sourceFile' }
        if (-not $source) { $source = $BicepFile }
        [void]$report.AppendLine("| ``$($drift.property)`` | $(Format-ReportValue $drift.valueB) | $(Format-ReportValue $drift.valueA) | $(Format-ReportValue $source) | Confirmed difference. Adopt Azure / reset Azure / skip. |")
    }
}

try {
    if ($Backend -eq 'AzPowerShell') { Stop-Run 'Expected-aware drift detection requires Azure CLI authentication. Use az login and -Backend AzureCLI.' }
    Write-Progress -Activity 'Bicep drift detection' -Status 'Checking authentication'
    & (Join-Path $shared 'Test-AzureAuth.ps1') -Backend AzureCLI -SubscriptionId $SubscriptionId -OutFile $paths.Auth
    if ($LASTEXITCODE -ne 0) { Stop-Run 'Not authenticated to Azure for the requested subscription. Sign in (az login) and retry.' }

    $groupJson = az group show --name $ResourceGroup --subscription $SubscriptionId --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $groupJson) { Stop-Run "Resource group '$ResourceGroup' was not found or is not readable in subscription '$SubscriptionId'." }
    $group = $groupJson | ConvertFrom-Json
    $cloudJson = az cloud show --query endpoints.resourceManager --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $cloudJson) { Stop-Run 'Azure CLI could not determine the active Resource Manager endpoint.' }
    $managementEndpoint = [string]($cloudJson | ConvertFrom-Json)
    if (-not $Location) { $Location = [string]$group.location }

    Write-Progress -Activity 'Bicep drift detection' -Status 'Parsing Bicep'
    $parseArguments = @{
        BicepFile = $BicepFile; SubscriptionId = $SubscriptionId; ResourceGroup = $ResourceGroup; Location = $Location
        ResolveDeterministicNames = $true; MaskSecrets = $true; ParameterOverride = $ParameterOverride; OutFile = $paths.Expected
    }
    if ($ParamFile) { $parseArguments.ParamFile = $ParamFile }
    if ($PSBoundParameters.ContainsKey('AnalysisTimestamp')) { $parseArguments.AnalysisTimestamp = $AnalysisTimestamp }
    & (Join-Path $shared 'ConvertFrom-BicepTemplate.ps1') @parseArguments 6>$null
    if ($LASTEXITCODE -ne 0) { Stop-Run 'Bicep compilation or parameter evaluation failed. Run the parser directly for details.' }
    $expected = Get-Content -LiteralPath $paths.Expected -Raw | ConvertFrom-Json

    & (Join-Path $shared 'Select-AzureResources.ps1') -Mode bicep -InputFile $paths.Expected -OutFile $paths.Filtered
    if ($LASTEXITCODE -ne 0) { Stop-Run 'Expected-resource filtering failed.' }

    Write-Progress -Activity 'Bicep drift detection' -Status 'Reading Azure (read-only)'
    & (Join-Path $shared 'Get-AzureResourceModel.ps1') -ResourceGroup $ResourceGroup -SubscriptionId $SubscriptionId `
        -ExpectedModel $paths.Filtered -Mode bicep -ManagementEndpoint $managementEndpoint -ThrottleLimit $ThrottleLimit -MaxRetry $MaxRetry -OutFile $paths.Actual
    if ($LASTEXITCODE -ne 0) { Stop-Run 'Azure discovery failed (inventory could not be read).' }
    $actual = Get-Content -LiteralPath $paths.Actual -Raw | ConvertFrom-Json

    Write-Progress -Activity 'Bicep drift detection' -Status 'Comparing'
    & (Join-Path $shared 'Compare-ResourceModels.ps1') -ModelA $paths.Filtered -ModelB $paths.Actual -LabelA 'Bicep' -LabelB 'Azure' `
        -AzureIdentity -TrackedProperties -OutFile $paths.Compare
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
$noComparable = 0
$uncertainCount = 0
foreach ($entry in @($comparison.matches)) {
    switch ($entry.status) {
        'Bicep Only' { $create.Add($entry.resourceA) }
        'Azure Only' { $extra.Add($entry.resourceB) }
        'Unresolved' { $unresolved.Add($entry.resourceA) }
        'Unverified' { $unresolved.Add($entry.resourceA) }
        default {
            $propertyComparison = if ($entry.PSObject.Properties['propertyComparison']) { $entry.propertyComparison } else { $null }
            if (-not $propertyComparison -or $propertyComparison.status -eq 'No Comparable Properties') { $noComparable++ }
            elseif ($propertyComparison.status -eq 'Incomplete') { $unresolved.Add($entry.resourceA) }
            elseif (@($propertyComparison.drifts).Count -gt 0) { $modify.Add($entry) }
            elseif ($propertyComparison.status -eq 'All Properties Match') { $noChange++ }
            if ($propertyComparison -and $propertyComparison.PSObject.Properties['uncertainties']) { $uncertainCount += @($propertyComparison.uncertainties).Count }
        }
    }
}

$unresolvedNames = if ($diagnostics) { [int]$diagnostics.unresolvedNames } else { 0 }
$missingParameters = @(if ($diagnostics) { $diagnostics.missingParameters })
$unresolvedParameters = @(if ($diagnostics -and $diagnostics.PSObject.Properties['unresolvedParameters']) { $diagnostics.unresolvedParameters })
$unresolvedIds = if ($diagnostics -and $diagnostics.PSObject.Properties['unresolvedResourceIds']) { [int]$diagnostics.unresolvedResourceIds } else { 0 }
$incompleteReasons = [System.Collections.Generic.List[string]]::new()
if ($unresolvedNames -gt 0) { $incompleteReasons.Add("$unresolvedNames expected resource name(s) could not be resolved") }
if ($unresolved.Count -gt 0) { $incompleteReasons.Add("$($unresolved.Count) resource comparison(s) could not be verified") }
if ($missingParameters.Count -gt 0) { $incompleteReasons.Add("parameters without values: $($missingParameters -join ', ')") }
if ($unresolvedParameters.Count -gt 0) { $incompleteReasons.Add("unresolved parameter inputs: $($unresolvedParameters -join ', ')") }
if ($unresolvedIds -gt 0) { $incompleteReasons.Add("$unresolvedIds expected resource identity/identities could not be verified") }
if ($issues.Count -gt 0) { $incompleteReasons.Add("$($issues.Count) Azure read(s) unavailable") }
if ($uncertainCount -gt 0) { $incompleteReasons.Add("$uncertainCount property value(s) unknown or unresolved") }
if ($noComparable -gt 0) { $incompleteReasons.Add("$noComparable resource(s) have no comparable expected properties") }
$status = if ($incompleteReasons.Count -gt 0) { 'INCOMPLETE' } else { 'COMPLETE' }

$report = [System.Text.StringBuilder]::new()
[void]$report.AppendLine("# Bicep drift report ($status)")
[void]$report.AppendLine()
[void]$report.AppendLine("Scope: subscription ``$SubscriptionId``, resource group ``$ResourceGroup``. Read-only run.")
[void]$report.AppendLine("Template: ``$BicepFile``. Parameters: ``$ParamFile``. Explicit override names: ``$(@($ParameterOverride.Keys | Sort-Object) -join ', ')``.")
[void]$report.AppendLine("Input provenance: **$ParameterSource**. Pipeline reference: ``$PipelineFile`` (not evaluated by this script). Deployment mode: **$DeploymentMode**.")
$versionText = if ($BuildVersion) { $BuildVersion } else { 'unknown; local template is not verified as the deployed build' }
[void]$report.AppendLine("Build version: $versionText.")
if ($diagnostics -and $diagnostics.PSObject.Properties['analysisTimestamp']) {
    [void]$report.AppendLine("Analysis timestamp: ``$($diagnostics.analysisTimestamp)``. utcNow defaults are synthetic analysis values, not verified deployment values.")
}
if ($ParameterSource -eq 'HistoricalFallback') {
    [void]$report.AppendLine('> Historical deployment parameters are a fallback, not proof of current pipeline inputs.')
}
[void]$report.AppendLine('What-if is optional, separate from this report, and was not invoked. No Bicep or Azure changes are authorized by selecting a resource for investigation.')
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
[void]$report.AppendLine("| Unverified | $($unresolved.Count) |")
[void]$report.AppendLine("| No comparable properties (existence only) | $noComparable |")
[void]$report.AppendLine("| No change | $noChange |")

if ($extra.Count -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('## Not in template (in Azure only)')
    [void]$report.AppendLine('Absent from this deployment does not mean unmanaged by any IaC. Check other workload pipelines before centralizing ownership. These are not implied deletions.')
    [void]$report.AppendLine('| Resource identity | Azure value | Bicep | Interpretation / decisions |')
    [void]$report.AppendLine('|---|---|---|---|')
    foreach ($resource in $extra) {
        $interpretation = if ($resource.type -eq 'Microsoft.Network/networkInterfaces') { 'May be an Azure-created private-endpoint dependency; verify its owner before adoption or removal.' } else { 'Ownership unverified.' }
        [void]$report.AppendLine("| ``$($resource.id)`` | $(Format-ReportValue $resource.properties) | Omitted from ``$BicepFile`` | $interpretation Adopt / investigate / skip. |")
    }
}
if ($modify.Count -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('## Modify (in both, with different configuration)')
    foreach ($entry in $modify) { Add-PropertyReport $entry }
}
if ($unresolved.Count -gt 0 -or $issues.Count -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('## Unverified')
    foreach ($resource in $unresolved) {
        $resourceIssues = @($issues | Where-Object { $_.resourceId -eq $resource.id })
        $reason = if ($resourceIssues.Count -gt 0) { @($resourceIssues | ForEach-Object { $_.errorCode }) -join ', ' } else { 'identity, existence or configuration could not be verified' }
        $templateIssues = Get-ModelMember $resource 'templateIssues'
        if ($templateIssues) { $reason += "; conflicting declarations: $($templateIssues -join ', ')" }
        [void]$report.AppendLine("- ``$($resource.id)``: $reason. Resolve inputs/permissions or investigate; no adoption until verified.")
        foreach ($entry in @($comparison.matches | Where-Object { $_.resourceA -and $_.resourceA.id -eq $resource.id -and $_.PSObject.Properties['propertyComparison'] })) {
            if (@($entry.propertyComparison.drifts).Count -gt 0) { Add-PropertyReport $entry }
            foreach ($uncertainty in @($entry.propertyComparison.uncertainties)) {
                [void]$report.AppendLine("  - ``$($uncertainty.property)``: $($uncertainty.status)")
            }
        }
    }
    foreach ($issue in $issues) {
        [void]$report.AppendLine("- Coverage/read issue for ``$($issue.resourceId)``: $($issue.errorCode)")
    }
}
if ($create.Count -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('## Create')
    foreach ($resource in $create) { [void]$report.AppendLine("- ``$($resource.id)``: absent from Azure. Create in Azure / remove from Bicep / skip (approval required).") }
}
if ($noComparable -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('## No Comparable Properties')
    foreach ($entry in @($comparison.matches | Where-Object {
        $_.status -in @('In Sync', 'In Sync (name differs)') -and
        (-not $_.PSObject.Properties['propertyComparison'] -or $_.propertyComparison.status -eq 'No Comparable Properties')
    })) {
        [void]$report.AppendLine("- ``$($entry.resourceA.id)``: existence only; configuration was not assessed")
    }
}
$omissions = @($comparison.matches | Where-Object {
    $_.PSObject.Properties['propertyComparison'] -and @($_.propertyComparison.omittedConfiguration).Count -gt 0
})
if ($omissions.Count -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('## Azure configuration omitted from Bicep (not confirmed drift)')
    [void]$report.AppendLine('These observations may be provider defaults/read-only state or configuration owned elsewhere. Investigate before adoption.')
    foreach ($entry in $omissions) {
        [void]$report.AppendLine("### ``$($entry.resourceA.id)``")
        foreach ($item in $entry.propertyComparison.omittedConfiguration) {
            [void]$report.AppendLine("- ``$($item.property)``: Azure $(Format-ReportValue $item.valueB); omitted from ``$BicepFile``. Investigate / adopt explicitly / skip.")
        }
    }
}
$providerState = @($comparison.matches | Where-Object {
    $_.PSObject.Properties['propertyComparison'] -and @($_.propertyComparison.providerMaintained).Count -gt 0
})
if ($providerState.Count -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('<details><summary>Provider-maintained state (not deployable intent)</summary>')
    foreach ($entry in $providerState) {
        foreach ($item in $entry.propertyComparison.providerMaintained) {
            [void]$report.AppendLine("- ``$($entry.resourceA.id)`` / ``$($item.property)``: $(Format-ReportValue $item.valueB)")
        }
    }
    [void]$report.AppendLine('</details>')
}
$parameterScopes = Get-ModelMember $diagnostics 'parameterScopes'
if ($null -ne $parameterScopes -and @($parameterScopes).Count -gt 0) {
    [void]$report.AppendLine(); [void]$report.AppendLine('<details><summary>Effective parameter sources and unresolved expectations</summary>')
    [void]$report.AppendLine('| Scope | Parameter | Source | Status | Reason |')
    [void]$report.AppendLine('|---|---|---|---|---|')
    foreach ($scope in $parameterScopes) {
        foreach ($parameter in $scope.parameters) {
            [void]$report.AppendLine("| $(Format-ReportValue $scope.scope) | ``$($parameter.name)`` | $($parameter.source) | $($parameter.status) | $(Format-ReportValue $parameter.reason) |")
        }
    }
    [void]$report.AppendLine('</details>')
}
[void]$report.AppendLine(); [void]$report.AppendLine('<details><summary>Matching resources (explicit expectations only)</summary>')
foreach ($entry in @($comparison.matches | Where-Object {
    $_.PSObject.Properties['propertyComparison'] -and $_.propertyComparison.status -eq 'All Properties Match'
})) { [void]$report.AppendLine("- ``$($entry.resourceA.id)``") }
[void]$report.AppendLine('</details>')
[void]$report.AppendLine(); [void]$report.AppendLine('Inspect -> report -> choose per resource/property -> edit. No infrastructure edits or deletion commands without explicit approval.')
$elapsed = [Math]::Round($timer.Elapsed.TotalSeconds, 1)
$requestText = if ($metrics) { ", $($metrics.armRequests) ARM request(s), $($metrics.retries) retries" } else { '' }
[void]$report.AppendLine(); [void]$report.AppendLine("_Elapsed ${elapsed}s$requestText._")
Set-Content -LiteralPath $paths.Report -Value $report.ToString() -Encoding utf8

$summary = [ordered]@{
    status = $status; subscriptionId = $SubscriptionId; resourceGroup = $ResourceGroup
    create = $create.Count; modify = $modify.Count; notInTemplate = $extra.Count
    unverified = $unresolved.Count; noComparableProperties = $noComparable; noChange = $noChange
    incompleteReasons = @($incompleteReasons); elapsedSeconds = $elapsed; metrics = $metrics
    inputProvenance = @{
        template = $BicepFile; parameterFile = $ParamFile; overrideNames = @($ParameterOverride.Keys)
        parameterSource = $ParameterSource; pipelineFile = $PipelineFile; deploymentMode = $DeploymentMode
        buildVersion = $BuildVersion; deployedBuildVerified = $false
        parameters = Get-ModelMember $diagnostics 'parameters'
        parameterScopes = Get-ModelMember $diagnostics 'parameterScopes'
        analysisTimestamp = Get-ModelMember $diagnostics 'analysisTimestamp'
    }
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $paths.Summary -Encoding utf8

if (-not $KeepIntermediate) {
    foreach ($name in 'Auth', 'Expected', 'Filtered', 'Actual', 'Compare') { Remove-Item -LiteralPath $paths[$name] -Force -ErrorAction SilentlyContinue }
}

[pscustomobject]@{
    Status = $status; ReportPath = $paths.Report; SummaryPath = $paths.Summary
    Create = $create.Count; Modify = $modify.Count; NotInTemplate = $extra.Count; Unverified = $unresolved.Count; NoComparableProperties = $noComparable; NoChange = $noChange
}
if ($status -eq 'INCOMPLETE') { exit 2 }
