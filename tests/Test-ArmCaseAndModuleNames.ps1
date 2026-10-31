#Requires -Version 5.1
<#
.SYNOPSIS
Regression tests for ARM case-sensitive conditions and deterministic module outputs.
.DESCRIPTION
Run with pwsh -NoProfile -File tests/Test-ArmCaseAndModuleNames.ps1.
Requires Azure CLI with Bicep support or standalone Bicep. Expected resource names
are checked independently of Invoke-Fixtures.ps1, with deterministic resolution
enabled for the module fixture. All generated files stay in the repository.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$scripts = Join-Path $repoRoot '.github/skills/shared/scripts'
. (Join-Path $scripts '_ArmExpression.ps1')

$script:assertions = 0
function Assert-Equal {
    param($Actual, $Expected, [string]$Label)
    if ($Actual -cne $Expected) { throw "$Label`: expected '$Expected', got '$Actual'." }
    $script:assertions++
}

$scope = New-ArmScope -Template ([ordered]@{}) -Path '' -DeploymentName 'test'
$cases = @(
    @("[equals('Prod', 'prod')]", $false),
    @("[equals('Prod', 'Prod')]", $true),
    @("[contains('Production', 'prod')]", $false),
    @("[contains('Production', 'Prod')]", $true),
    @("[contains(createArray('Prod'), 'prod')]", $false),
    @("[contains(createArray('Prod'), 'Prod')]", $true),
    @("[contains(createObject('Prod', 'Enabled'), 'prod')]", $true),
    @("[equals(createArray('Prod'), createArray('prod'))]", $false),
    @("[equals(createObject('Prod', 'Enabled'), createObject('prod', 'Enabled'))]", $false),
    @("[equals(createObject('Prod', 'Enabled'), createObject('Prod', 'enabled'))]", $false),
    @("[contains(createArray(createObject('Prod', 'Enabled')), createObject('Prod', 'enabled'))]", $false),
    @("[equals(createObject('a', 1, 'b', 2), createObject('b', 2, 'a', 1))]", $true),
    @("[equals(createArray(1, 2), createArray(2, 1))]", $false),
    @("[equals(createArray(1, 2), createArray(1, 2))]", $true),
    @("[contains(createArray(1, 2), 2)]", $true),
    @("[contains(createArray(), 'Prod')]", $false),
    @("[equals(true(), false())]", $false),
    @("[equals(null(), null())]", $true)
)
foreach ($case in $cases) {
    Assert-Equal (Resolve-ArmValue $case[0] $scope) $case[1] $case[0]
}

function New-OutputTestScope {
    param([string]$Value)
    $template = [ordered]@{
        resources = [ordered]@{
            names = [ordered]@{
                name = 'names'
                properties = [ordered]@{
                    template = [ordered]@{
                        outputs = [ordered]@{
                            name = [ordered]@{ value = $Value }
                        }
                    }
                }
            }
        }
    }
    New-ArmScope -Template $template -Path '' -DeploymentName 'test'
}

$pendingScope = New-OutputTestScope "[uniqueString('seed')]"
$pendingScope.ResolveDeterministicNames = $true
$pending = Get-ArmDeploymentOutputs $pendingScope 'names'
Assert-Equal ($pending.outputs.name.value -is [ArmUnresolved]) $true 'First pass is unresolved'
Assert-Equal $pendingScope.NamingRequests.Count 1 'First pass collects naming request'
Assert-Equal ([object]::ReferenceEquals($pending, (Get-ArmDeploymentOutputs $pendingScope 'names'))) $true 'Cache reused within pass'

$resolvedScope = New-OutputTestScope "[uniqueString('seed')]"
$resolvedScope.ResolveDeterministicNames = $true
$key = @($pendingScope.NamingRequests.Keys)[0]
$resolvedScope.NamingValues[$key] = 'resolved-suffix'
Assert-Equal (Get-ArmDeploymentOutputs $resolvedScope 'names').outputs.name.value 'resolved-suffix' 'New pass has a fresh output cache'
$otherScope = New-OutputTestScope 'different-template'
Assert-Equal (Get-ArmDeploymentOutputs $otherScope 'names').outputs.name.value 'different-template' 'Same path and symbol do not collide across scopes'

$workRoot = Join-Path $repoRoot ('.azverify-arm-case-module-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workRoot | Out-Null
try {
    $oracleInput = Join-Path $repoRoot 'examples/arm-module-deterministic-names/verification/expected-values.bicepparam'
    $oracleOutput = Join-Path $workRoot 'expected-values.json'
    if (Get-Command 'bicep' -ErrorAction SilentlyContinue) {
        & bicep build-params $oracleInput --outfile $oracleOutput
    }
    else {
        & az bicep build-params --file $oracleInput --outfile $oracleOutput
    }
    if ($LASTEXITCODE -ne 0) { throw 'Official Bicep expected-value evaluation failed.' }
    $oracle = (Get-Content -LiteralPath $oracleOutput -Raw | ConvertFrom-Json).parameters
    foreach ($fixture in @('arm-case-sensitive-conditions', 'arm-module-deterministic-names')) {
        $fixtureRoot = Join-Path (Join-Path $repoRoot 'examples') $fixture
        $modelFile = Join-Path $workRoot "$fixture.json"
        $arguments = @{
            BicepFile = (Join-Path $fixtureRoot 'main.bicep')
            OutFile = $modelFile
        }
        if ($fixture -eq 'arm-module-deterministic-names') { $arguments.ResolveDeterministicNames = $true }
        & (Join-Path $scripts 'ConvertFrom-BicepTemplate.ps1') @arguments
        $model = Get-Content -LiteralPath $modelFile -Raw | ConvertFrom-Json
        $expected = @((Get-Content -LiteralPath (Join-Path $fixtureRoot 'expected-names.json') -Raw | ConvertFrom-Json))
        $actual = @($model.resources | Where-Object { $_.type -ne 'Microsoft.Resources/deployments' } |
            ForEach-Object { "$($_.type)|$($_.name)" })
        $differences = @(Compare-Object -ReferenceObject $expected -DifferenceObject $actual -CaseSensitive)
        Assert-Equal $differences.Count 0 "$fixture expected names: $($differences | Out-String)"
        Assert-Equal $model.diagnostics.unresolvedNames 0 "$fixture resolved names"
        if ($fixture -eq 'arm-case-sensitive-conditions') {
            foreach ($resource in $model.resources) {
                Assert-Equal $resource.conditional $true "$($resource.name) retains condition metadata"
                Assert-Equal $resource.existenceUnknown $false "$($resource.name) condition is known"
            }
        }
        else {
            Assert-Equal $model.diagnostics.namingBatches 2 'Chained uniqueString/guid requires two evaluation batches'
            $identity = @($model.resources | Where-Object { $_.type -eq 'Microsoft.ManagedIdentity/userAssignedIdentities' })[0]
            Assert-Equal $identity.name $oracle.consumerGuid.value 'Consumer GUID matches official Bicep evaluator'
            Assert-Equal $identity.tags.moduleGuid $oracle.generatedGuid.value 'Nested module GUID output resolves'
            Assert-Equal $identity.tags.moduleName $oracle.accountName.value 'Module name matches official Bicep evaluator'
            Assert-Equal $identity.tags.moduleName ($actual | Where-Object { $_.StartsWith('Microsoft.Storage/storageAccounts|') }).Split('|')[1] 'Output resolves in tags as well as name'
            $arguments.Remove('ResolveDeterministicNames')
            & (Join-Path $scripts 'ConvertFrom-BicepTemplate.ps1') @arguments
            $offlineModel = Get-Content -LiteralPath $modelFile -Raw | ConvertFrom-Json
            Assert-Equal $offlineModel.diagnostics.unresolvedNames 2 'Default offline mode keeps deterministic names unresolved'
            Assert-Equal $offlineModel.diagnostics.namingBatches 0 'Default offline mode does not call naming evaluator'
            Assert-Equal $offlineModel.resources.Count $model.resources.Count 'Default offline mode preserves resource count'
        }
    }
    Write-Output "PASS: $script:assertions assertions (ARM case sensitivity, scope-local cache, compiled Bicep fixtures)."
}
finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
}
