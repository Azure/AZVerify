#Requires -Version 7.0
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$shared = Join-Path $root '.github/skills/shared/scripts'
. (Join-Path $shared '_Common.ps1')
. (Join-Path $shared '_ExpectedAzureDiscovery.ps1')
$work = Join-Path $root ('.azverify-lessons-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $work
$script:checks = 0
$parentId = '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Insights/privateLinkScopes/scope'
$script:scenario = 'pages'
$script:reads = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param([bool]$Condition, [string]$Label)
    if (-not $Condition) { throw $Label }
    $script:checks++
}

function Invoke-AzJson {
    param([string[]]$Arguments)
    $global:LASTEXITCODE = 0
    switch ($Arguments[0]) {
        'resource' {
            return [pscustomobject]@{
                id = $parentId; type = 'Microsoft.Insights/privateLinkScopes'; name = 'scope'; tags = @{}
            }
        }
        'account' { return @{ accessToken = 'test-token' } }
        default { throw "Detection attempted unexpected CLI call: $($Arguments -join ' ')" }
    }
}

function Invoke-ArmRead {
    param([string]$Uri, [string]$Token, [int]$MaxRetry, [int]$TimeoutSeconds)
    $script:reads.Add($Uri)
    if ($script:scenario -eq 'forbidden') {
        return @{ status = 'Unavailable'; errorCode = 'AuthorizationFailed'; requests = 1; retries = 0 }
    }
    $second = $Uri -match 'page=2'
    $children = @(foreach ($number in $(if ($second) { 18..34 } else { 1..17 })) {
        [pscustomobject]@{
            id = "$parentId/scopedResources/nonstandard-$number"
            name = "nonstandard-$number"
            type = 'Microsoft.Insights/privateLinkScopes/scopedResources'
            properties = @{ linkedResourceId = "/subscriptions/sub/resourceGroups/workload/providers/Microsoft.OperationalInsights/workspaces/target-$number" }
        }
    })
    $next = if ($second) { $null } else { "https://management.azure.com$parentId/scopedResources?api-version=2021-07-01-preview&page=2" }
    if ($script:scenario -eq 'foreign-next') { $next = 'https://example.invalid/steal-token' }
    if ($script:scenario -eq 'cycle') { $next = $Uri }
    return @{ status = 'Found'; data = @{ value = $children; nextLink = $next }; requests = 1; retries = 0 }
}

function Compare-Fixture {
    param([object[]]$Expected, [object[]]$Actual)
    Write-ResourceModel @{ resources = $Expected } -OutFile (Join-Path $work 'a.json')
    Write-ResourceModel @{ resources = $Actual } -OutFile (Join-Path $work 'b.json')
    & (Join-Path $shared 'Compare-ResourceModels.ps1') -ModelA (Join-Path $work 'a.json') `
        -ModelB (Join-Path $work 'b.json') -AzureIdentity -TrackedProperties -LabelA Bicep -LabelB Azure `
        -OutFile (Join-Path $work 'comparison.json')
    Assert-True ($LASTEXITCODE -eq 0) 'Comparison failed'
    return Get-Content -LiteralPath (Join-Path $work 'comparison.json') -Raw | ConvertFrom-Json
}

function New-Fixture {
    param([string]$Type, [hashtable]$Properties, [hashtable]$Tags = @{})
    return @{
        id = "/subscriptions/sub/resourceGroups/rg/providers/$Type/test"
        type = $Type; name = 'test'; properties = $Properties; tags = $Tags
    }
}

try {
    $expectedPath = Join-Path $work 'expected.json'
    Write-ResourceModel @{ resources = @() } -OutFile $expectedPath
    $model = Get-ExpectedAzureModel -ExpectedModel $expectedPath -SubscriptionId sub -ResourceGroup rg -ThrottleLimit 1
    Assert-True ($model.resources.Count -eq 35) 'Inventory must include all 34 undeclared AMPLS children'
    Assert-True ($script:reads.Count -eq 2) 'AMPLS collection must follow pagination'
    Assert-True ($model.issues.Count -eq 0) 'Successful collection should not produce issues'
    $link = @($model.resources | Where-Object name -eq 'nonstandard-34')[0]
    Assert-True ($link.id -ceq "$parentId/scopedResources/nonstandard-34") 'Nonstandard link name must be preserved exactly'
    Assert-True ($link.properties.linkedResourceId -ceq '/subscriptions/sub/resourceGroups/workload/providers/Microsoft.OperationalInsights/workspaces/target-34') 'Exact link target must be preserved'
    $comparison = Compare-Fixture @() $model.resources
    Assert-True ($comparison.summary.onlyB -eq 35) 'Undeclared children must be reported as Azure-only resources'

    foreach ($scenario in @('forbidden', 'foreign-next', 'cycle')) {
        $script:scenario = $scenario
        $script:reads.Clear()
        $model = Get-ExpectedAzureModel -ExpectedModel $expectedPath -SubscriptionId sub -ResourceGroup rg -ThrottleLimit 1
        Assert-True ($model.issues.Count -eq 1) "$scenario collection must mark coverage incomplete"
        Assert-True ($script:reads.Count -eq 1) "$scenario must not send a token to another endpoint or loop"
    }

    $target = '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Test/targets/one'
    $expected = New-Fixture 'Microsoft.Test/widgets' @{
        diagnostic = @{ enabled = $true }
        linkedResourceId = $target
        networkAcls = @{ ipRules = @(@{ value = '10.0.0.1' }, @{ value = '10.0.0.2' }) }
    } @{ owner = 'network' }
    $actual = New-Fixture 'Microsoft.Test/widgets' @{
        diagnostic = @{ enabled = $true }
        linkedResourceId = $target.ToUpperInvariant()
        networkAcls = @{ ipRules = @(@{ value = '10.0.0.2' }, @{ value = '10.0.0.1' }) }
        providerDefault = 'observed'
    } @{ owner = 'network' }
    $comparison = Compare-Fixture @($expected) @($actual)
    Assert-True ($comparison.summary.propertyDriftCount -eq 0) 'IDs and keyed unordered ACLs should normalize'
    Assert-True ($comparison.matches[0].propertyComparison.omittedConfiguration.Count -eq 1) 'Azure omissions must be distinct from drift'
    $actual.tags.owner = 'different'
    $actual.properties.diagnostic.enabled = $false
    $comparison = Compare-Fixture @($expected) @($actual)
    Assert-True ($comparison.summary.propertyDriftCount -eq 2) 'Explicit uncatalogued configuration and tags must detect real differences'

    $expected = New-Fixture 'Microsoft.Insights/diagnosticSettings' @{
        logs = @(@{ category = 'Audit'; enabled = $true }, @{ category = 'Unused'; enabled = $false })
    }
    $actual = New-Fixture 'Microsoft.Insights/diagnosticSettings' @{ logs = @(@{ category = 'Audit'; enabled = $true }) }
    $comparison = Compare-Fixture @($expected) @($actual)
    Assert-True ($comparison.summary.propertyDriftCount -eq 0) 'Disabled diagnostic categories are equivalent to absent disabled collection'
    $actual.properties.logs[0].enabled = $false
    $comparison = Compare-Fixture @($expected) @($actual)
    Assert-True ($comparison.summary.propertyDriftCount -eq 1) 'Missing enabled diagnostic collection is actionable drift'

    $expected = New-Fixture 'Microsoft.Test/widgets' @{ values = @() }
    $actual = New-Fixture 'Microsoft.Test/widgets' @{ values = $null }
    $comparison = Compare-Fixture @($expected) @($actual)
    Assert-True ($comparison.summary.propertyDriftCount -eq 1) 'Null and empty collections must not be universally equivalent'
    $actual.properties.Remove('values')
    $comparison = Compare-Fixture @($expected) @($actual)
    Assert-True ($comparison.summary.unverified -eq 1) 'Missing explicit property must be unknown, not an invented default'

    $expected = New-Fixture 'Microsoft.Network/privateDnsZones/A' @{
        ttl = 300; aRecords = @(@{ ipv4Address = '10.0.0.1' }, @{ ipv4Address = '10.0.0.2' })
    }
    $actual = New-Fixture 'Microsoft.Network/privateDnsZones/A' @{
        ttl = 300; aRecords = @(@{ ipv4Address = '10.0.0.2' }, @{ ipv4Address = '10.0.0.1' })
    }
    $comparison = Compare-Fixture @($expected) @($actual)
    Assert-True ($comparison.summary.propertyDriftCount -eq 0) 'DNS record collections must compare as keyed sets'
    $actual.properties.ttl = 600
    $comparison = Compare-Fixture @($expected) @($actual)
    Assert-True ($comparison.summary.propertyDriftCount -eq 1) 'DNS TTL differences must remain visible'

    $expected = New-Fixture 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings' @{
        peeringState = 'Initiated'; allowForwardedTraffic = $false
    }
    $actual = New-Fixture 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings' @{
        peeringState = 'Connected'; allowForwardedTraffic = $true
    }
    $comparison = Compare-Fixture @($expected) @($actual)
    Assert-True ($comparison.summary.propertyDriftCount -eq 1) 'Provider-maintained peering state must not obscure deployable peering differences'
    Assert-True ($comparison.matches[0].propertyComparison.providerMaintained[0].valueB -eq 'Connected') 'Provider peering state must be labeled separately'

    $first = New-Fixture 'Microsoft.Test/widgets' @{ first = 1 }
    $second = New-Fixture 'Microsoft.Test/widgets' @{ second = 2 }
    $actual = New-Fixture 'Microsoft.Test/widgets' @{ first = 1; second = 2 }
    $comparison = Compare-Fixture @($first, $second) @($actual)
    Assert-True ($comparison.summary.total -eq 1 -and $comparison.summary.confirmedMatch -eq 1) 'Compatible duplicate declarations must consolidate'
    $second.properties.first = 3
    $comparison = Compare-Fixture @($first, $second) @($actual)
    Assert-True ($comparison.templateIssues.Count -eq 1 -and $comparison.summary.unverified -eq 1) 'Conflicting duplicate declarations must be template issues'

    $script:scenario = 'pages'
    Write-ResourceModel @{ resources = @($link, $link) } -OutFile $expectedPath
    $script:reads.Clear()
    $model = Get-ExpectedAzureModel -ExpectedModel $expectedPath -SubscriptionId sub -ResourceGroup rg -ThrottleLimit 1
    Assert-True ($script:reads.Count -eq 2) 'Discovered child resources should satisfy duplicate expected declarations without redundant detail reads'

    Write-Output "PASS: $script:checks drift lessons checks."
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
