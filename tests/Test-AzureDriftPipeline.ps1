#Requires -Version 7.0
<#
.SYNOPSIS
Offline regression coverage for expected-aware Bicep drift detection.
.DESCRIPTION
Run with: pwsh -NoProfile -File tests/Test-AzureDriftPipeline.ps1
Mocks Azure CLI, Bicep compilation, and ARM GETs; no Azure account or network is used.
The generated work directory is inside the repository and removed on completion.
#>
[CmdletBinding()]
param(
    [switch]$OrchestratorChild,
    [string]$WorkRoot,
    [ValidateSet('AzureCLI', 'AzPowerShell')][string]$ChildBackend = 'AzureCLI'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$shared = Join-Path $repoRoot '.github/skills/shared/scripts'
$orchestrator = Join-Path $repoRoot '.github/skills/azv-bicep-drift-detection/scripts/Invoke-BicepDriftDetection.ps1'
$subscriptionId = '11111111-2222-3333-4444-555555555555'
$resourceGroup = 'drift-test-rg'
$endpoint = 'https://management.azure.com'
$script:assertions = 0
if (-not ('AzureDriftMockWebResponse' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Net;
public sealed class AzureDriftMockWebResponse : WebResponse
{
    public int StatusCode { get; private set; }
    private readonly WebHeaderCollection responseHeaders = new WebHeaderCollection();
    public override WebHeaderCollection Headers { get { return responseHeaders; } }
    public AzureDriftMockWebResponse(int statusCode, string retryAfter)
    {
        StatusCode = statusCode;
        if (retryAfter != null) responseHeaders.Add("Retry-After", retryAfter);
    }
}
'@
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -cne $Expected) {
        throw "$Label`: expected '$Expected', got '$Actual'."
    }
    $script:assertions++
}

function Assert-True {
    param([bool]$Condition, [string]$Label)
    if (-not $Condition) { throw "$Label`: expected true." }
    $script:assertions++
}

function Write-JsonFile {
    param([Parameter(Mandatory)]$Value, [Parameter(Mandatory)][string]$Path)
    ConvertTo-Json -InputObject $Value -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
}

function ConvertTo-CanonicalValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        $canonical = [ordered]@{}
        foreach ($key in @($Value.Keys | Sort-Object -CaseSensitive)) {
            $canonical[[string]$key] = ConvertTo-CanonicalValue $Value[$key]
        }
        return $canonical
    }
    if ($Value -is [pscustomobject]) {
        $canonical = [ordered]@{}
        foreach ($property in @($Value.PSObject.Properties | Sort-Object Name -CaseSensitive)) {
            $memberValue = $property.Value
            if ($property.Name -in @('drifts', 'uncertainties')) {
                $memberValue = @($memberValue | Sort-Object property)
            }
            $canonical[$property.Name] = ConvertTo-CanonicalValue $memberValue
        }
        return $canonical
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        return , @($Value | ForEach-Object { ConvertTo-CanonicalValue $_ })
    }
    return $Value
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Initialize-Mocks {
    param([Parameter(Mandatory)][string]$Root)
    $global:mockRoot = $Root
    $global:azCalls = [System.Collections.Generic.List[string]]::new()
    $global:armCalls = [System.Collections.Generic.List[string]]::new()
    $global:compiledTemplatePath = Join-Path $Root 'compiled-arm-template.json'
    $global:armResponsePath = Join-Path $Root 'arm-responses.json'
    $global:inventoryPath = Join-Path $Root 'inventory.json'
    $global:azCallLog = Join-Path $Root 'az-call-log.txt'
}

function az {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $joined = $Arguments -join ' '
    $global:azCalls.Add($joined)
    if ($global:azCallLog) { Add-Content -LiteralPath $global:azCallLog -Value $joined }
    $global:LASTEXITCODE = 0
    if ($Arguments -contains 'account' -and $Arguments -contains 'show') {
        return (@{ id = $subscriptionId; name = 'test-sub'; tenantId = 'test-tenant'; user = @{ name = 'test@example.invalid' } } | ConvertTo-Json -Compress)
    }
    if ($Arguments -contains 'group' -and $Arguments -contains 'show') {
        return (@{ location = 'eastus' } | ConvertTo-Json -Compress)
    }
    if ($Arguments -contains 'cloud' -and $Arguments -contains 'show') {
        return ('"' + $endpoint + '/"')
    }
    if ($Arguments -contains 'resource' -and $Arguments -contains 'list') {
        return Get-Content -LiteralPath $global:inventoryPath -Raw
    }
    if ($Arguments -contains 'get-access-token') {
        return (@{ accessToken = 'mock-token-never-persist' } | ConvertTo-Json -Compress)
    }
    throw "Unexpected mocked az invocation: $joined"
}

function bicep {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    $outIndex = [Array]::IndexOf($Arguments, '--outfile')
    if ($outIndex -lt 0 -or $outIndex + 1 -ge $Arguments.Count) { throw "Unexpected bicep arguments: $($Arguments -join ' ')" }
    Copy-Item -LiteralPath $global:compiledTemplatePath -Destination $Arguments[$outIndex + 1] -Force
    $global:LASTEXITCODE = 0
}

function global:Invoke-WebRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [string]$Method,
        [switch]$UseBasicParsing,
        [hashtable]$Headers,
        [int]$TimeoutSec
    )

    $resourceId = ([uri]$Uri).AbsolutePath
    $global:armCalls.Add($Uri)
    $map = Read-JsonFile $global:armResponsePath
    $result = $map.PSObject.Properties[$resourceId]
    if (-not $result) {
        throw "No mocked ARM response registered for $resourceId."
    }
    $payload = $result.Value
    if ($payload.status -eq 'Found') {
        return [pscustomobject]@{ Content = ($payload.data | ConvertTo-Json -Depth 100 -Compress) }
    }

    $retryAfter = if ($payload.PSObject.Properties['retryAfter'] -and $null -ne $payload.retryAfter) { [string]$payload.retryAfter } else { $null }
    $response = [AzureDriftMockWebResponse]::new([int]$payload.httpStatus, $retryAfter)
    $exception = [System.Net.WebException]::new(
        'Mock ARM HTTP failure.', $null, [System.Net.WebExceptionStatus]::ProtocolError, $response
    )
    $record = [System.Management.Automation.ErrorRecord]::new(
        $exception, 'MockArmHttpFailure', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Uri
    )
    $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
        (@{ error = @{ code = [string]$payload.errorCode } } | ConvertTo-Json -Compress)
    )
    throw $record
}

function New-ResourceId {
    param([string]$Type, [string]$Name)
    "/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/$Type/$Name"
}

function New-ArmResource {
    param(
        [string]$Type,
        [string]$Name,
        [hashtable]$Properties = @{},
        [string]$ApiVersion = '2024-01-01',
        [string]$Location = 'eastus',
        [hashtable]$Sku
    )
    $resource = [ordered]@{
        type = $Type
        apiVersion = $ApiVersion
        name = $Name
        location = $Location
        properties = $Properties
    }
    if ($Sku) { $resource.sku = $Sku }
    return $resource
}

function New-InventoryResource {
    param([string]$Type, [string]$Name)
    [ordered]@{
        id = New-ResourceId $Type $Name
        name = $Name
        type = $Type
        location = 'eastus'
        tags = @{}
    }
}

function New-ArmResponseData {
    param(
        [string]$Type,
        [string]$Name,
        [hashtable]$Properties = @{},
        [string]$Location = 'eastus',
        [hashtable]$Sku
    )
    $resource = New-ArmResource $Type $Name $Properties -Location $Location -Sku $Sku
    $resource.id = New-ResourceId $Type $Name
    return ($resource | ConvertTo-Json -Depth 30 | ConvertFrom-Json)
}

function New-ExpectedArmTemplate {
    @(
        (New-ArmResource 'Microsoft.Storage/storageAccounts' 'sku-drift' @{} -Sku @{ name = 'Standard_LRS'; tier = 'Standard' }),
        (New-ArmResource 'Microsoft.Storage/storageAccounts' 'sku-enum' @{} -Sku @{ name = 'Standard_LRS'; tier = 'Standard' }),
        (New-ArmResource 'Microsoft.Compute/virtualMachines' 'vm-case' @{
            osProfile = @{ adminUsername = 'Alice' }
        } -Location 'East US'),
        (New-ArmResource 'Microsoft.Compute/virtualMachines' 'vm-whitespace' @{
            osProfile = @{ adminUsername = 'Alice ' }
        }),
        (New-ArmResource 'Microsoft.Storage/storageAccounts' 'vm-absent' @{} -Sku @{ name = 'Standard_LRS'; tier = 'Standard' }),
        (New-ArmResource 'Microsoft.Storage/storageAccounts' 'vm-404' @{} -Sku @{ name = 'Standard_LRS'; tier = 'Standard' }),
        (New-ArmResource 'Microsoft.Storage/storageAccounts' 'vm-403' @{} -Sku @{ name = 'Standard_LRS'; tier = 'Standard' }),
        (New-ArmResource 'Microsoft.Storage/storageAccounts' 'vm-429' @{} -Sku @{ name = 'Standard_LRS'; tier = 'Standard' }),
        [ordered]@{
            type = 'Microsoft.Test/widgets'; apiVersion = '2024-01-01'
            name = 'no-comparable'; location = $null; properties = @{}
        }
    )
}

function Set-EndToEndFixtures {
    param([string]$Root)
    $template = [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
        contentVersion = '1.0.0.0'
        parameters = @{}
        resources = @(New-ExpectedArmTemplate)
    }
    Write-JsonFile $template $global:compiledTemplatePath
    Set-Content -LiteralPath (Join-Path $Root 'fixture.bicep') -Value @'
param location string = 'eastus'
// This valid source is paired with an offline mocked Bicep build artifact.
resource fixture 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: 'fixture'
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
}
'@ -Encoding utf8

    $inventory = @(
        (New-InventoryResource 'Microsoft.Storage/storageAccounts' 'sku-drift'),
        (New-InventoryResource 'Microsoft.Storage/storageAccounts' 'sku-enum'),
        (New-InventoryResource 'Microsoft.Compute/virtualMachines' 'vm-case'),
        (New-InventoryResource 'Microsoft.Compute/virtualMachines' 'vm-whitespace'),
        (New-InventoryResource 'Microsoft.Storage/storageAccounts' 'vm-404'),
        (New-InventoryResource 'Microsoft.Storage/storageAccounts' 'vm-403'),
        (New-InventoryResource 'Microsoft.Storage/storageAccounts' 'vm-429'),
        (New-InventoryResource 'Microsoft.Test/widgets' 'no-comparable')
    )
    Write-JsonFile $inventory $global:inventoryPath

    $responses = [ordered]@{}
    $responses[(New-ResourceId 'Microsoft.Storage/storageAccounts' 'sku-drift')] = @{
        status = 'Found'
        data = New-ArmResponseData 'Microsoft.Storage/storageAccounts' 'sku-drift' @{} -Sku @{ name = 'Standard_GRS'; tier = 'Standard' }
    }
    $responses[(New-ResourceId 'Microsoft.Storage/storageAccounts' 'sku-enum')] = @{
        status = 'Found'
        data = New-ArmResponseData 'Microsoft.Storage/storageAccounts' 'sku-enum' @{} -Sku @{ name = 'standard_lrs'; tier = 'standard' }
    }
    $responses[(New-ResourceId 'Microsoft.Compute/virtualMachines' 'vm-case')] = @{
        status = 'Found'
        data = New-ArmResponseData 'Microsoft.Compute/virtualMachines' 'vm-case' @{
            osProfile = @{ adminUsername = 'alice' }
            storageProfile = @{ dataDisks = @(@{
                name = 'data-1'; lun = 0; diskSizeGB = 128; caching = 'ReadOnly'; managedDisk = @{ id = '/extra/id' }
            }) }
        } -Location 'eastus'
    }
    $responses[(New-ResourceId 'Microsoft.Compute/virtualMachines' 'vm-whitespace')] = @{
        status = 'Found'
        data = New-ArmResponseData 'Microsoft.Compute/virtualMachines' 'vm-whitespace' @{
            osProfile = @{ adminUsername = 'Alice' }
        }
    }
    $responses[(New-ResourceId 'Microsoft.Storage/storageAccounts' 'vm-404')] = @{
        status = 'Absent'; httpStatus = 404; errorCode = 'ResourceNotFound'
    }
    $responses[(New-ResourceId 'Microsoft.Storage/storageAccounts' 'vm-absent')] = @{
        status = 'Unavailable'; httpStatus = 403; errorCode = 'AuthorizationFailed'
    }
    $responses[(New-ResourceId 'Microsoft.Storage/storageAccounts' 'vm-403')] = @{
        status = 'Unavailable'; httpStatus = 403; errorCode = 'AuthorizationFailed'
    }
    $responses[(New-ResourceId 'Microsoft.Storage/storageAccounts' 'vm-429')] = @{
        status = 'Unavailable'; httpStatus = 429; errorCode = 'TooManyRequests'; retryAfter = 0
    }
    Write-JsonFile $responses $global:armResponsePath
}

function Invoke-ManualPipeline {
    param([string]$Root)
    $expectedPath = Join-Path $Root 'manual-expected.json'
    $filteredPath = Join-Path $Root 'manual-filtered.json'
    $actualPath = Join-Path $Root 'manual-actual.json'
    $comparisonPath = Join-Path $Root 'manual-comparison.json'
    & (Join-Path $shared 'ConvertFrom-BicepTemplate.ps1') -BicepFile (Join-Path $Root 'fixture.bicep') `
        -SubscriptionId $subscriptionId -ResourceGroup $resourceGroup -Location 'eastus' `
        -ResolveDeterministicNames -MaskSecrets -OutFile $expectedPath
    Assert-Equal $LASTEXITCODE 0 'Manual Bicep parse'
    & (Join-Path $shared 'Select-AzureResources.ps1') -InputFile $expectedPath -Mode bicep -OutFile $filteredPath
    Assert-Equal $LASTEXITCODE 0 'Manual expected-resource filter'
    & (Join-Path $shared 'Get-AzureResourceModel.ps1') -ResourceGroup $resourceGroup -SubscriptionId $subscriptionId `
        -ExpectedModel $filteredPath -Mode bicep -ManagementEndpoint "$endpoint/" -ThrottleLimit 1 -MaxRetry 1 -OutFile $actualPath
    Assert-Equal $LASTEXITCODE 0 'Manual Azure discovery'
    & (Join-Path $shared 'Compare-ResourceModels.ps1') -ModelA $filteredPath -ModelB $actualPath `
        -LabelA Bicep -LabelB Azure -AzureIdentity -TrackedProperties -OutFile $comparisonPath
    Assert-Equal $LASTEXITCODE 0 'Manual tracked-property comparison'
    $compatibilityPath = Join-Path $Root 'manual-compatibility-comparison.json'
    & (Join-Path $shared 'Compare-ResourceModels.ps1') -ModelA $filteredPath -ModelB $actualPath `
        -LabelA Bicep -LabelB Azure -CompareProperties -OutFile $compatibilityPath
    Assert-Equal $LASTEXITCODE 0 'Legacy manual flag uses canonical Azure comparison'
    Assert-Equal `
        (ConvertTo-Json -InputObject (ConvertTo-CanonicalValue (Read-JsonFile $compatibilityPath)) -Depth 100 -Compress) `
        (ConvertTo-Json -InputObject (ConvertTo-CanonicalValue (Read-JsonFile $comparisonPath)) -Depth 100 -Compress) `
        'Manual CompareProperties and tracked comparison reports are identical'
    return [pscustomobject]@{
        Expected = $expectedPath; Actual = $actualPath; Comparison = $comparisonPath
    }
}

if ($OrchestratorChild) {
    Initialize-Mocks -Root $WorkRoot
    $output = Join-Path $WorkRoot 'fast-output'
    & $orchestrator -BicepFile (Join-Path $WorkRoot 'fixture.bicep') -ResourceGroup $resourceGroup `
        -SubscriptionId $subscriptionId -Backend $ChildBackend -OutputDirectory $output `
        -ThrottleLimit 1 -MaxRetry 1 -KeepIntermediate
    exit $LASTEXITCODE
}

$workRoot = Join-Path $repoRoot ('.azverify-drift-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workRoot | Out-Null
try {
    Initialize-Mocks -Root $workRoot
    Set-EndToEndFixtures -Root $workRoot

    $manual = Invoke-ManualPipeline -Root $workRoot
    $childOutput = & pwsh -NoProfile -File $PSCommandPath -OrchestratorChild -ChildBackend AzureCLI -WorkRoot $workRoot 2>&1
    $fastExitCode = $LASTEXITCODE
    Assert-Equal $fastExitCode 2 'Fast orchestration returns INCOMPLETE for deliberately unavailable ARM reads'
    $fastOutput = Join-Path $workRoot 'fast-output'
    $fastComparison = Join-Path $fastOutput 'comparison.json'
    Assert-True (Test-Path -LiteralPath $fastComparison) "Fast orchestration wrote comparison report; output: $($childOutput -join [Environment]::NewLine)"

    $fastNormalized = ConvertTo-Json -InputObject (ConvertTo-CanonicalValue (Read-JsonFile $fastComparison)) -Depth 100 -Compress
    $manualNormalized = ConvertTo-Json -InputObject (ConvertTo-CanonicalValue (Read-JsonFile $manual.Comparison)) -Depth 100 -Compress
    if ($fastNormalized -cne $manualNormalized) {
        $fastEntries = @((Read-JsonFile $fastComparison).matches)
        $manualEntries = @((Read-JsonFile $manual.Comparison).matches)
        $differences = for ($index = 0; $index -lt [Math]::Min($fastEntries.Count, $manualEntries.Count); $index++) {
            $fastEntry = $fastEntries[$index]
            $manualEntry = $manualEntries[$index]
            $fastEntryJson = ConvertTo-Json -InputObject (ConvertTo-CanonicalValue $fastEntry) -Depth 100 -Compress
            $manualEntryJson = ConvertTo-Json -InputObject (ConvertTo-CanonicalValue $manualEntry) -Depth 100 -Compress
            if ($fastEntryJson -cne $manualEntryJson) {
                $name = if ($fastEntry.resourceA) { $fastEntry.resourceA.name } else { $fastEntry.resourceB.name }
                $fastPropertyStatus = if ($fastEntry.PSObject.Properties['propertyComparison']) { $fastEntry.propertyComparison.status } else { '-' }
                $manualPropertyStatus = if ($manualEntry.PSObject.Properties['propertyComparison']) { $manualEntry.propertyComparison.status } else { '-' }
                $fields = @($fastEntry.PSObject.Properties.Name + $manualEntry.PSObject.Properties.Name | Sort-Object -Unique)
                $differentFields = @($fields | Where-Object {
                    $leftProperty = $fastEntry.PSObject.Properties[$_]
                    $rightProperty = $manualEntry.PSObject.Properties[$_]
                    $left = if ($leftProperty) { ConvertTo-Json -InputObject (ConvertTo-CanonicalValue $leftProperty.Value) -Depth 100 -Compress } else { '<missing>' }
                    $right = if ($rightProperty) { ConvertTo-Json -InputObject (ConvertTo-CanonicalValue $rightProperty.Value) -Depth 100 -Compress } else { '<missing>' }
                    $left -cne $right
                })
                if ($differentFields -contains 'propertyComparison') {
                    $fastComp = $fastEntry.propertyComparison
                    $manualComp = $manualEntry.propertyComparison
                    $fastDrifts = @($fastComp.drifts | ForEach-Object { $_.property + ':' + $_.valueA + '>' + $_.valueB }) -join ','
                    $manualDrifts = @($manualComp.drifts | ForEach-Object { $_.property + ':' + $_.valueA + '>' + $_.valueB }) -join ','
                    $fastUnknown = @($fastComp.uncertainties | ForEach-Object { $_.property + ':' + $_.status }) -join ','
                    $manualUnknown = @($manualComp.uncertainties | ForEach-Object { $_.property + ':' + $_.status }) -join ','
                    "$name status=$($fastComp.status)/$($manualComp.status) drift=$fastDrifts/$manualDrifts unknown=$fastUnknown/$manualUnknown"
                }
                else { "$name fields=$($differentFields -join ',')" }
            }
        }
        throw "Fast/manual report first difference: $($differences | Select-Object -First 1)"
    }
    $script:assertions++

    $summary = Read-JsonFile (Join-Path $fastOutput 'drift-summary.json')
    $comparison = Read-JsonFile $manual.Comparison
    $counts = @{
        create = @($comparison.matches | Where-Object { $_.status -eq 'Bicep Only' }).Count
        notInTemplate = @($comparison.matches | Where-Object { $_.status -eq 'Azure Only' }).Count
        unverified = @($comparison.matches | Where-Object {
            $_.status -in @('Unresolved', 'Unverified') -or
            ($_.PSObject.Properties['propertyComparison'] -and $_.propertyComparison.status -eq 'Incomplete')
        }).Count
        modify = @($comparison.matches | Where-Object {
            $_.PSObject.Properties['propertyComparison'] -and @($_.propertyComparison.drifts).Count -gt 0
        }).Count
        noComparableProperties = @($comparison.matches | Where-Object {
            $_.PSObject.Properties['propertyComparison'] -and $_.propertyComparison.status -eq 'No Comparable Properties'
        }).Count
        noChange = @($comparison.matches | Where-Object {
            $_.PSObject.Properties['propertyComparison'] -and $_.propertyComparison.status -eq 'All Properties Match'
        }).Count
    }
    foreach ($category in $counts.Keys) {
        Assert-Equal ([int]$summary.$category) ([int]$counts[$category]) "Fast/manual category count: $category"
    }
    Assert-Equal ($summary.create + $summary.modify + $summary.notInTemplate + $summary.unverified + $summary.noComparableProperties + $summary.noChange) `
        $comparison.summary.total 'Every resource is counted exactly once'
    Assert-Equal $summary.unverified $comparison.summary.unverified 'Shared comparison and fast workflow unverified counts agree'

    $entriesByName = @{}
    foreach ($entry in $comparison.matches) {
        if ($entry.resourceA) { $entriesByName[$entry.resourceA.name] = $entry }
    }
    Assert-Equal $entriesByName['sku-drift'].propertyComparison.drifts[0].property 'skuName' 'Top-level SKU drift is tracked'
    Assert-Equal $entriesByName['sku-enum'].propertyComparison.status 'All Properties Match' 'SKU enum casing is ignored'
    Assert-Equal $entriesByName['vm-case'].propertyComparison.drifts[0].property 'adminUsername' 'VM username casing remains exact'
    Assert-Equal $entriesByName['vm-whitespace'].propertyComparison.drifts[0].property 'adminUsername' 'VM username whitespace remains exact'
    Assert-Equal $entriesByName['vm-case'].propertyComparison.status 'Properties Drifted' 'The VM username difference remains a confirmed drift'
    Assert-Equal $entriesByName['vm-absent'].status 'Unverified' '403 for an inventory-absent resource stays unverified'
    Assert-Equal $entriesByName['vm-404'].status 'Bicep Only' 'ARM 404 is reported as absent'
    Assert-Equal $entriesByName['vm-403'].propertyComparison.status 'Incomplete' 'Inventory-found 403 yields unknown properties'
    Assert-Equal $entriesByName['vm-403'].propertyComparison.comparedCount 0 'All-unknown properties are not verified matches'
    Assert-Equal $entriesByName['vm-429'].propertyComparison.status 'Incomplete' 'Exhausted throttling yields unknown properties'
    Assert-Equal $entriesByName['vm-case'].propertyComparison.drifts.Count 1 'Region whitespace and Azure-only nested fields do not drift'
    Assert-Equal (Read-JsonFile (Join-Path $fastOutput 'actual.json')).metrics.retries 1 '429 retry is accounted for'
    $recordedAzCalls = @(Get-Content -LiteralPath $global:azCallLog)
    Assert-True (@($recordedAzCalls | Where-Object { $_ -match '^account show' }).Count -gt 0) 'Explicit AzureCLI backend authenticated through mocked native az'
    Assert-True (@($recordedAzCalls | Where-Object { $_ -match '^cloud show' }).Count -gt 0) 'Mocked Azure cloud endpoint was selected'

    $actual = Read-JsonFile $manual.Actual
    Assert-Equal (@($actual.resources | Where-Object { $_.name -eq 'vm-absent' })[0].existence) 'Unknown' '403 absent from inventory has unknown existence'
    Assert-Equal (@($actual.resources | Where-Object { $_.name -eq 'vm-403' })[0].existence) 'Found' '403 present in inventory retains known existence'
    $unknown403 = @($actual.resources | Where-Object { $_.name -eq 'vm-403' })[0].comparisonProperties
    Assert-True (@($unknown403.PSObject.Properties | Where-Object { $_.Value -eq 'unknown' }).Count -gt 0) '403 marks each tracked property unknown'
    $unknown429 = @($actual.resources | Where-Object { $_.name -eq 'vm-429' })[0].comparisonProperties
    Assert-True (@($unknown429.PSObject.Properties | Where-Object { $_.Value -eq 'unknown' }).Count -gt 0) '429 marks each tracked property unknown'

    $scopeLocationTemplatePath = Join-Path $workRoot 'scope-location-template.json'
    Write-JsonFile @{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
        contentVersion = '1.0.0.0'
        parameters = @{}
        resources = @(@{
            type = 'Microsoft.Compute/virtualMachines'; apiVersion = '2024-01-01'
            name = 'scope-location-vm'; properties = @{}
        })
    } $scopeLocationTemplatePath
    $global:compiledTemplatePath = $scopeLocationTemplatePath
    $scopeLocationBicep = Join-Path $workRoot 'scope-location.bicep'
    Set-Content -LiteralPath $scopeLocationBicep -Value "resource vm 'Microsoft.Compute/virtualMachines@2024-01-01' = { name: 'scope-location-vm'; properties: {} }" -Encoding utf8
    $scopeLocationExpectedPath = Join-Path $workRoot 'scope-location-expected.json'
    & (Join-Path $shared 'ConvertFrom-BicepTemplate.ps1') -BicepFile $scopeLocationBicep -SubscriptionId $subscriptionId `
        -ResourceGroup $resourceGroup -Location 'eastus' -OutFile $scopeLocationExpectedPath
    Assert-Equal $LASTEXITCODE 0 'Bicep resource without an explicit location parses'
    $scopeLocationExpected = Read-JsonFile $scopeLocationExpectedPath
    Assert-Equal $scopeLocationExpected.resources[0].location 'eastus' 'Missing Bicep location retains deployment-scope metadata'
    Assert-Equal $scopeLocationExpected.resources[0].locationIsExplicit $false 'Inherited deployment location is marked non-explicit'
    $scopeLocationActualPath = Join-Path $workRoot 'scope-location-actual.json'
    $scopeLocationActual = @{
        resources = @(@{
            id = $scopeLocationExpected.resources[0].id; name = 'scope-location-vm'
            type = 'Microsoft.Compute/virtualMachines'; resourceGroup = $resourceGroup
            location = $null; properties = @{}
        })
    }
    Write-JsonFile $scopeLocationActual $scopeLocationActualPath
    $scopeLocationComparisonPath = Join-Path $workRoot 'scope-location-comparison.json'
    & (Join-Path $shared 'Compare-ResourceModels.ps1') -ModelA $scopeLocationExpectedPath -ModelB $scopeLocationActualPath `
        -AzureIdentity -TrackedProperties -OutFile $scopeLocationComparisonPath
    Assert-Equal (Read-JsonFile $scopeLocationComparisonPath).matches[0].propertyComparison.status `
        'No Comparable Properties' 'Inherited deployment location is not compared as an explicit expectation'
    $global:compiledTemplatePath = Join-Path $workRoot 'compiled-arm-template.json'

    $enrichedInputPath = Join-Path $workRoot 'enriched-input.json'
    $enrichedResource = @{
        id = New-ResourceId 'Microsoft.Compute/virtualMachines' 'zone-vm'
        name = 'zone-vm'; type = 'Microsoft.Compute/virtualMachines'; resourceGroup = $resourceGroup
        location = 'eastus'; zones = @('1'); properties = @{ hardwareProfile = @{ vmSize = 'Standard_B2s' } }
    }
    Write-JsonFile @($enrichedResource) $enrichedInputPath
    $enrichedOutputPath = Join-Path $workRoot 'enriched-model.json'
    & (Join-Path $shared 'Get-AzureResourceModel.ps1') -FromJson $enrichedInputPath -Enrich -OutFile $enrichedOutputPath
    Assert-Equal $LASTEXITCODE 0 'Offline enriched model generation'
    $enrichedActual = Read-JsonFile $enrichedOutputPath
    Assert-Equal $enrichedActual.resources[0].properties.availabilityZone '1' 'Legacy enrichment retains flattened availability zone'
    Assert-Equal $enrichedActual.resources[0].comparisonProperties.availabilityZone '1' 'Legacy enrichment emits canonical comparison properties'
    $enrichedExpectedPath = Join-Path $workRoot 'enriched-expected.json'
    Write-JsonFile @{ resources = @(@{
        id = $enrichedResource.id; name = 'zone-vm'; type = $enrichedResource.type
        resourceGroup = $resourceGroup; properties = @{}; comparisonProperties = @{ availabilityZone = '1' }
    }) } $enrichedExpectedPath
    $enrichedComparisonPath = Join-Path $workRoot 'enriched-comparison.json'
    & (Join-Path $shared 'Compare-ResourceModels.ps1') -ModelA $enrichedExpectedPath -ModelB $enrichedOutputPath `
        -LabelA Diagram -LabelB Azure -CompareProperties -OutFile $enrichedComparisonPath
    Assert-Equal (Read-JsonFile $enrichedComparisonPath).matches[0].propertyComparison.status `
        'All Properties Match' 'Deep comparison uses canonical values from legacy enriched discovery'

    $nestedModelA = Join-Path $workRoot 'nested-a.json'
    $nestedModelB = Join-Path $workRoot 'nested-b.json'
    $nestedComparison = Join-Path $workRoot 'nested-comparison.json'
    $nestedExpected = @{
        id = New-ResourceId 'Microsoft.Compute/virtualMachines' 'nested-vm'
        name = 'nested-vm'; type = 'Microsoft.Compute/virtualMachines'; resourceGroup = $resourceGroup
        properties = @{}
        comparisonProperties = @{ dataDisks = @(@{ name = 'data-1'; lun = 0; diskSizeGB = 128 }) }
    }
    $nestedActual = @{
        id = $nestedExpected.id
        name = 'nested-vm'; type = $nestedExpected.type; resourceGroup = $resourceGroup
        properties = @{ storageProfile = @{ dataDisks = @(@{
            name = 'data-1'; lun = 0; diskSizeGB = 128; caching = 'ReadOnly'
            managedDisk = @{ id = '/azure-default/id'; storageAccountType = 'Premium_LRS' }
        }) } }
    }
    Write-JsonFile @{ resources = @($nestedExpected) } $nestedModelA
    Write-JsonFile @{ resources = @($nestedActual) } $nestedModelB
    & (Join-Path $shared 'Compare-ResourceModels.ps1') -ModelA $nestedModelA -ModelB $nestedModelB `
        -AzureIdentity -TrackedProperties -OutFile $nestedComparison
    Assert-True (Test-Path -LiteralPath $nestedComparison) 'Nested tracked-object comparison emitted a report'
    Assert-Equal (Read-JsonFile $nestedComparison).matches[0].propertyComparison.status 'All Properties Match' 'Azure-only nested/default object fields are ignored'
    $noComparableA = Join-Path $workRoot 'no-comparable-a.json'
    $noComparableB = Join-Path $workRoot 'no-comparable-b.json'
    $noComparableComparison = Join-Path $workRoot 'no-comparable-comparison.json'
    $noComparableResource = @{
        id = New-ResourceId 'Microsoft.Test/widgets' 'plain-object'
        name = 'plain-object'; type = 'Microsoft.Test/widgets'; resourceGroup = $resourceGroup
        properties = @{}
    }
    Write-JsonFile @{ resources = @($noComparableResource) } $noComparableA
    Write-JsonFile @{ resources = @($noComparableResource) } $noComparableB
    & (Join-Path $shared 'Compare-ResourceModels.ps1') -ModelA $noComparableA -ModelB $noComparableB `
        -AzureIdentity -TrackedProperties -OutFile $noComparableComparison
    Assert-True (Test-Path -LiteralPath $noComparableComparison) 'No-comparable-property comparison emitted a report'
    Assert-Equal (Read-JsonFile $noComparableComparison).matches[0].propertyComparison.status 'No Comparable Properties' 'Unknown resource supports existence-only comparison'

    $noComparableResource.existenceUnknown = $true
    Write-JsonFile @{ resources = @($noComparableResource) } $noComparableA
    & (Join-Path $shared 'Compare-ResourceModels.ps1') -ModelA $noComparableA -ModelB $noComparableB `
        -AzureIdentity -TrackedProperties -OutFile $noComparableComparison
    $unknownCondition = Read-JsonFile $noComparableComparison
    Assert-Equal $unknownCondition.matches.Count 1 'An unknown condition does not double-count the same actual identity'
    Assert-Equal $unknownCondition.matches[0].status 'Unverified' 'An unknown expected condition is unverified even when inventory found the ID'

    $missingApiModel = [ordered]@{ resources = @(
        [ordered]@{
            id = New-ResourceId 'Microsoft.Storage/storageAccounts' 'missing-api'
            name = 'missing-api'; type = 'Microsoft.Storage/storageAccounts'; properties = @{}
            comparisonProperties = @{ skuName = 'Standard_LRS' }
        }
    ) }
    $missingApiPath = Join-Path $workRoot 'missing-api.json'
    Write-JsonFile $missingApiModel $missingApiPath
    $inventoryMissingApi = @((New-InventoryResource 'Microsoft.Storage/storageAccounts' 'missing-api'))
    Write-JsonFile $inventoryMissingApi $global:inventoryPath
    Write-JsonFile ([ordered]@{}) $global:armResponsePath
    $missingApiActualPath = Join-Path $workRoot 'missing-api-actual.json'
    $global:azCalls.Clear()
    $global:armCalls.Clear()
    & (Join-Path $shared 'Get-AzureResourceModel.ps1') -ResourceGroup $resourceGroup -SubscriptionId $subscriptionId `
        -ExpectedModel $missingApiPath -ManagementEndpoint "$endpoint/" -ThrottleLimit 1 -MaxRetry 0 -OutFile $missingApiActualPath
    Assert-Equal $LASTEXITCODE 0 'Missing API version discovery completes as incomplete data'
    $missingApiActual = Read-JsonFile $missingApiActualPath
    Assert-Equal $missingApiActual.issues[0].errorCode 'MissingDeclaredApiVersion' 'Missing API version is surfaced'
    Assert-Equal $global:armCalls.Count 0 'Missing API version skips ARM detail requests'
    Assert-True (@($global:azCalls | Where-Object { $_ -match 'get-access-token' }).Count -eq 0) 'Missing API version skips token acquisition'
    Write-JsonFile @() $global:inventoryPath
    & (Join-Path $shared 'Get-AzureResourceModel.ps1') -SubscriptionId $subscriptionId `
        -ExpectedModel $missingApiPath -ManagementEndpoint "$endpoint/" -ThrottleLimit 1 -MaxRetry 0 -OutFile $missingApiActualPath
    $missingApiActual = Read-JsonFile $missingApiActualPath
    Assert-Equal $missingApiActual.resources[0].existence 'Unknown' 'Missing API version without inventory evidence cannot confirm existence'
    Assert-True (@($global:azCalls | Where-Object { $_ -match '^resource list' -and $_ -notmatch '--resource-group' }).Count -gt 0) 'Subscription-scope expected discovery uses the same CLI pipeline'
    & (Join-Path $shared 'Compare-ResourceModels.ps1') -ModelA $missingApiPath -ModelB $missingApiActualPath `
        -AzureIdentity -TrackedProperties -OutFile $noComparableComparison
    Assert-Equal (Read-JsonFile $noComparableComparison).matches[0].status 'Unverified' 'Unread absent-from-inventory resources never become no-change candidates'

    $secretTemplatePath = Join-Path $workRoot 'secret-template.json'
    Write-JsonFile @{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
        contentVersion = '1.0.0.0'
        parameters = @{ password = @{ type = 'secureString' } }
        resources = @((New-ArmResource 'Microsoft.Compute/virtualMachines' 'secure-vm' @{
            osProfile = @{ adminPassword = "[parameters('password')]"; adminUsername = 'operator' }
        }))
    } $secretTemplatePath
    $global:compiledTemplatePath = $secretTemplatePath
    $secretBicep = Join-Path $workRoot 'secret.bicep'
    Set-Content -LiteralPath $secretBicep -Value "param password secureString`nresource vm 'Microsoft.Compute/virtualMachines@2024-01-01' = { name: 'secure-vm'; location: 'eastus'; properties: { osProfile: { adminPassword: password } } }" -Encoding utf8
    $secretOutput = Join-Path $workRoot 'secret-model.json'
    & (Join-Path $shared 'ConvertFrom-BicepTemplate.ps1') -BicepFile $secretBicep -SubscriptionId $subscriptionId `
        -ResourceGroup $resourceGroup -ParameterOverride @{ password = 'DoNotPersist-Secret-Regression-Value' } `
        -MaskSecrets -OutFile $secretOutput
    Assert-Equal $LASTEXITCODE 0 'Secret parameter parser execution'
    $serializedSecretModel = Get-Content -LiteralPath $secretOutput -Raw
    Assert-True (-not $serializedSecretModel.Contains('DoNotPersist-Secret-Regression-Value')) 'Secret parameter is absent from parser output'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $workRoot '.azverify-tmp'))) 'Parser leaves no temporary secret artifacts'

    $global:compiledTemplatePath = Join-Path $workRoot 'compiled-arm-template.json'
    Remove-Item -LiteralPath $global:azCallLog -Force -ErrorAction SilentlyContinue
    & pwsh -NoProfile -File $PSCommandPath -OrchestratorChild -ChildBackend AzPowerShell -WorkRoot $workRoot 2>&1 | Out-Null
    $backendExitCode = $LASTEXITCODE
    Assert-Equal $backendExitCode 1 'AzPowerShell backend is rejected'
    Assert-Equal (Test-Path -LiteralPath $global:azCallLog) $false 'AzPowerShell rejection occurs before Azure discovery/authentication'

    Write-Output "PASS: $script:assertions assertions (mocked offline Azure drift pipeline)."
}
catch {
    [Console]::Error.WriteLine(("Test failure at line {0}: {1}" -f $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message))
    throw
}
finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
}
