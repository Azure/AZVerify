#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [ValidateSet('AzVerify1', 'AzVerify2')]
    [string[]]$ResourceGroups = @('AzVerify1', 'AzVerify2'),

    [switch]$SkipPeering
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ResourceGroups.Count -ne 2) {
    throw 'Exactly two resource groups are required.'
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$complexMain = Join-Path $repoRoot 'assets/complex/main.bicep'
$peeringTemplate = Join-Path $repoRoot 'assets/complex/peering.bicep'

$suffix = $SubscriptionId.Replace('-', '').Substring(0, 8).ToLowerInvariant()
$fixtures = @(
    [pscustomobject]@{
        ResourceGroup = $ResourceGroups[0]
        Prefix = 'azvft1'
        AddressPrefix = '10.91.0.0/16'
        SubnetPrefixes = '["10.91.1.0/24","10.91.2.0/24","10.91.3.0/24"]'
        IncludeMonitoring = 'true'
    },
    [pscustomobject]@{
        ResourceGroup = $ResourceGroups[1]
        Prefix = 'azvft2'
        AddressPrefix = '10.92.0.0/16'
        SubnetPrefixes = '["10.92.1.0/24","10.92.2.0/24","10.92.3.0/24"]'
        IncludeMonitoring = 'false'
    }
)

function Invoke-Az {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & az @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    if ($exitCode -ne 0) {
        throw "az $($Arguments -join ' ') failed with exit code $exitCode.`n$text"
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $text
}

foreach ($fixture in $fixtures) {
    Invoke-Az -Arguments @(
        'group', 'show',
        '--name', $fixture.ResourceGroup,
        '--subscription', $SubscriptionId,
        '--output', 'none'
    ) | Out-Null

    Invoke-Az -Arguments @(
        'deployment', 'group', 'create',
        '--resource-group', $fixture.ResourceGroup,
        '--subscription', $SubscriptionId,
        '--name', "azverify-complex-$($fixture.Prefix)",
        '--template-file', $complexMain,
        '--parameters',
        "prefix=$($fixture.Prefix)",
        "nameSuffix=$suffix",
        "addressPrefix=$($fixture.AddressPrefix)",
        "subnetPrefixes=$($fixture.SubnetPrefixes)",
        "includeMonitoring=$($fixture.IncludeMonitoring)",
        '--output', 'none'
    ) | Out-Null
}

if (-not $SkipPeering) {
    $peeringPairs = @(
        [pscustomobject]@{
            ResourceGroup = $fixtures[0].ResourceGroup
            LocalVnetName = "$($fixtures[0].Prefix)-vnet"
            RemoteVnetId = "/subscriptions/$SubscriptionId/resourceGroups/$($fixtures[1].ResourceGroup)/providers/Microsoft.Network/virtualNetworks/$($fixtures[1].Prefix)-vnet"
            DeploymentName = "azverify-peering-$($fixtures[0].Prefix)-to-$($fixtures[1].Prefix)"
        },
        [pscustomobject]@{
            ResourceGroup = $fixtures[1].ResourceGroup
            LocalVnetName = "$($fixtures[1].Prefix)-vnet"
            RemoteVnetId = "/subscriptions/$SubscriptionId/resourceGroups/$($fixtures[0].ResourceGroup)/providers/Microsoft.Network/virtualNetworks/$($fixtures[0].Prefix)-vnet"
            DeploymentName = "azverify-peering-$($fixtures[1].Prefix)-to-$($fixtures[0].Prefix)"
        }
    )

    foreach ($pair in $peeringPairs) {
        Invoke-Az -Arguments @(
            'deployment', 'group', 'create',
            '--resource-group', $pair.ResourceGroup,
            '--subscription', $SubscriptionId,
            '--name', $pair.DeploymentName,
            '--template-file', $peeringTemplate,
            '--parameters',
            "localVnetName=$($pair.LocalVnetName)",
            "remoteVnetId=$($pair.RemoteVnetId)",
            '--output', 'none'
        ) | Out-Null
    }
}

$summary = foreach ($fixture in $fixtures) {
    $resources = Invoke-Az -Arguments @(
        'resource', 'list',
        '--resource-group', $fixture.ResourceGroup,
        '--subscription', $SubscriptionId,
        '--query', "[?tags.azverifyFunctionalTest=='expanded-v1'].{name:name,type:type}",
        '--output', 'json'
    ) | ConvertFrom-Json

    [pscustomobject]@{
        resourceGroup = $fixture.ResourceGroup
        taggedResourceCount = @($resources).Count
        taggedResourceTypes = (@($resources | Select-Object -ExpandProperty type -Unique) -join ', ')
    }
}

$summary | ConvertTo-Json -Depth 8
