#Requires -Version 5.1
<#
.SYNOPSIS
Offline shared-parser regressions for effective parameters and uncertain identities.
.DESCRIPTION
Run with pwsh -NoProfile -File tests/Test-ArmExpression.ps1.
Bicep compilation is mocked; no Azure commands or network requests are made.
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
function Assert-Unresolved {
    param($Actual, [string]$Label)
    Assert-Equal ($Actual -is [ArmUnresolved]) $true $Label
}

$json = @'
{
  // Keep URLs and comment-like string contents.
  "url": "https://example.invalid/a//b",
  "literal": "/* not a comment */ \"quoted\" \\",
  /* multiline
     comment */
  "one": ["only"],
  "empty": [],
  "nested": [["inner"]]
}
'@
$parsed = ConvertFrom-ArmJson $json
Assert-Equal $parsed.url 'https://example.invalid/a//b' 'JSONC URL preserved'
Assert-Equal $parsed.literal '/* not a comment */ "quoted" \' 'JSONC escaping preserved'
Assert-Equal (Test-ArmList $parsed.one) $true 'Single item remains an array'
Assert-Equal $parsed.one.Count 1 'Single array count'
Assert-Equal $parsed.empty.Count 0 'Empty array preserved'
Assert-Equal (Test-ArmList $parsed.nested[0]) $true 'Nested single array preserved'
Assert-Equal $parsed.nested[0][0] 'inner' 'Nested array value'
foreach ($arrayJson in @('[]', '["only"]', '[["inner"]]')) {
    Assert-Equal (Test-ArmList (ConvertFrom-ArmJson $arrayJson)) $true "Root array preserved: $arrayJson"
}

$timestamp = [DateTimeOffset]'2026-11-03T10:20:30+02:00'
$defaultTemplate = [ordered]@{
    parameters = [ordered]@{
        stamp = @{ type = 'string'; defaultValue = "[utcNow()]" }
        shortStamp = @{ type = 'string'; defaultValue = "[utcNow('yyyyMMddHHmmss')]" }
        derivedStamp = @{ type = 'string'; defaultValue = "[concat('release-', parameters('stamp'))]" }
        secretStamp = @{ type = 'secureString'; defaultValue = "[utcNow()]" }
        explicit = @{ type = 'string'; defaultValue = "[utcNow()]" }
        version = @{ type = 'string'; defaultValue = 'fallback' }
        config = @{ type = 'object' }
        nullable = @{ type = 'string'; nullable = $true }
        missing = @{ type = 'string' }
    }
}
$scope = New-ArmScope -Template $defaultTemplate -Path '' -AnalysisTimestamp $timestamp
Set-ArmScopeParameters $scope @{
    explicit = 'actual-deployment-stamp'
    version = '$(Build.BuildNumber)'
    config = @{ known = 'safe'; nested = @('$(Pipeline.Value)') }
} @{ version = 'explicitOverride' }
Assert-Unresolved $scope.Params.version 'Unexpanded build version is unresolved'
Assert-Equal $scope.ParameterMetadata.version.source 'explicitOverride' 'Explicit source recorded'
Assert-Equal $scope.ParameterMetadata.version.status 'Unverified' 'Build version unverified'
Assert-Unresolved $scope.Params.stamp 'Synthetic default is unresolved in effective model'
Assert-Equal $scope.ParameterMetadata.stamp.analysisValue '20261103T082030Z' 'Automatic UTC default format'
Assert-Equal $scope.ParameterMetadata.shortStamp.analysisValue '20261103082030' 'Formatted utcNow uses same instant'
Assert-Equal $scope.ParameterMetadata.derivedStamp.analysisValue 'release-20261103T082030Z' 'Derived default analysis value'
Assert-Equal $scope.ParameterMetadata.derivedStamp.isSynthetic $true 'Derived default remains synthetic'
Assert-Equal $scope.ParameterMetadata.secretStamp.Contains('analysisValue') $false 'Secure default has no analysis value'
Assert-Equal $scope.ParameterMetadata.explicit.isSynthetic $false 'Explicit timestamp is not synthetic'
Assert-Equal $scope.Params.explicit 'actual-deployment-stamp' 'Explicit timestamp overrides utcNow'
Assert-Equal $scope.ParameterMetadata.nullable.source 'nullableDefault' 'Nullable provenance'
Assert-Equal $scope.ParameterMetadata.missing.source 'missing' 'Missing provenance'
Assert-Equal $scope.ParameterMetadata.config.status 'Unverified' 'Nested macro unverified'
Assert-Equal (Resolve-ArmValue "[parameters('config').known]" $scope) 'safe' 'Known object member remains usable'
Assert-Unresolved (Resolve-ArmValue "[string(parameters('config'))]" $scope) 'Nested macro cannot be stringified into identity'
Assert-Unresolved (Resolve-ArmValue "[utcNow()]" $scope) 'utcNow is not allowed in resource properties'
Assert-Equal (Test-ArmList (Resolve-ArmValue "[json('[]')]" $scope)) $true 'ARM json empty array preserved'
Assert-Equal (Test-ArmList (Resolve-ArmValue "[json('[1]')]" $scope)) $true 'ARM json single array preserved'
Assert-Equal (Resolve-ArmValue "[json('[[1]]')]" $scope)[0][0] 1 'ARM json nested array preserved'

$scope.SubscriptionId = 'sub'
$scope.ResourceGroupName = 'rg'
$scope.Symbols['target'] = @{ name = 'store'; type = 'Microsoft.Storage/storageAccounts' }
$scope.Symbols['unknownTarget'] = @{ name = "[parameters('missing')]"; type = 'Microsoft.Storage/storageAccounts' }
$extensionType = 'Microsoft.Authorization/roleAssignments'
$baseId = '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/store'
foreach ($extensionScope in @('target', $baseId, 'Microsoft.Storage/storageAccounts/store')) {
    $definition = @{ type = $extensionType; scope = $extensionScope }
    Assert-Equal (Get-ArmResourceId $scope $definition 'assignment') "$baseId/providers/$extensionType/assignment" 'Resolved extension scope'
}
foreach ($extensionScope in @("[parameters('missing')]", 'unknownTarget', 'missingSymbol', '', '<unresolved: missing scope>')) {
    $definition = @{ type = $extensionType; scope = $extensionScope }
    Assert-Equal (Get-ArmResourceId $scope $definition 'assignment') $null 'Unresolved extension scope has no fallback RG ID'
}
$scope.Symbols['assignment'] = @{ name = 'assignment'; type = $extensionType; scope = "[parameters('missing')]"; apiVersion = '2022-04-01' }
Assert-Unresolved (Resolve-ArmValue "[resourceInfo('assignment').id]" $scope) 'resourceInfo preserves unknown ID'
Assert-Unresolved (Resolve-ArmValue "[concat(resourceInfo('assignment').id, '/child')]" $scope) 'Unknown ID cannot become concrete child ID'
$child = New-ArmChildScope $scope @{
    resourceGroup = "[parameters('version')]"
    properties = @{ template = [ordered]@{} }
} $scope.Params.stamp
Assert-Unresolved (Resolve-ArmValue "[deployment().name]" $child) 'Unresolved deployment name stays typed through modules'
Assert-Unresolved (Resolve-ArmValue "[substring(deployment().name, 0, 3)]" $child) 'Cannot remove uncertainty by slicing a module name'
Assert-Unresolved (Resolve-ArmValue "[resourceGroup().id]" $child) 'Unresolved child resource group stays typed'
Assert-Equal (Get-ArmResourceId $child @{ type = 'Microsoft.Web/sites' } 'known-name') $null 'Unresolved child scope cannot produce RG ID'
$forwarded = New-ArmChildScope $scope @{
    properties = @{
        template = [ordered]@{ parameters = [ordered]@{ stamp = @{ type = 'string' } } }
        parameters = @{ stamp = @{ value = "[parameters('stamp')]" } }
    }
} 'forwarded'
Assert-Equal $forwarded.ParameterMetadata.stamp.isSynthetic $true 'Synthetic provenance survives module parameter forwarding'

$workRoot = Join-Path $repoRoot ('.azverify-parser-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $workRoot | Out-Null
$global:parserTestTemplate = Join-Path $workRoot 'compiled.json'
$global:parserTestParams = Join-Path $workRoot 'compiled-params.json'
function bicep {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $outIndex = [Array]::IndexOf($Arguments, '--outfile')
    if ($outIndex -lt 0) { throw 'Unexpected Bicep call (only offline compilation is mocked).' }
    $source = if ($Arguments[0] -eq 'build-params') { $global:parserTestParams } else { $global:parserTestTemplate }
    Copy-Item -LiteralPath $source -Destination $Arguments[$outIndex + 1]
    $global:LASTEXITCODE = 0
}
function Invoke-ParserTest {
    param($Template, [string]$ParamFile, [hashtable]$Overrides = @{}, [switch]$MaskSecrets, [switch]$AutomaticTimestamp)
    ConvertTo-Json -InputObject $Template -Depth 100 | Set-Content -LiteralPath $global:parserTestTemplate -Encoding utf8
    $arguments = @{
        BicepFile = (Join-Path $workRoot 'main.bicep')
        SubscriptionId = 'sub'
        ResourceGroup = 'rg'
        OutFile = (Join-Path $workRoot 'model.json')
        ParameterOverride = $Overrides
        MaskSecrets = $MaskSecrets
    }
    if (-not $AutomaticTimestamp) { $arguments.AnalysisTimestamp = $timestamp }
    if ($ParamFile) { $arguments.ParamFile = $ParamFile }
    & (Join-Path $scripts 'ConvertFrom-BicepTemplate.ps1') @arguments
    if ($LASTEXITCODE -ne 0) { throw 'Parser failed.' }
    Get-Content -LiteralPath $arguments.OutFile -Raw | ConvertFrom-Json
}
try {
    Set-Content -LiteralPath (Join-Path $workRoot 'main.bicep') -Value '// Compilation is mocked.'
    $parameterFile = Join-Path $workRoot 'pipeline.jsonc'
    Set-Content -LiteralPath $parameterFile -Value @'
{
  // A file must not win over the effective explicit pipeline overrides.
  "parameters": {
    "environment": { "value": "stage" },
    "version": { "value": "old-version" },
    "location": { "value": "eastus" },
    "one": { "value": ["only"] },
    "empty": { "value": [] },
    "nested": { "value": [["inner"]] },
    "literal": { "value": "[parameters('not-an-expression')]" },
    "vault": { "reference": { "keyVault": { "id": "/vault" }, "secretName": "secret" } }
  }
}
'@
    $template = [ordered]@{
        parameters = [ordered]@{
            environment = @{ type = 'string'; defaultValue = 'dev' }
            version = @{ type = 'string'; defaultValue = 'default-version' }
            location = @{ type = 'string'; defaultValue = 'westus' }
            one = @{ type = 'array' }; empty = @{ type = 'array' }; nested = @{ type = 'array' }
            literal = @{ type = 'string' }; vault = @{ type = 'secureString' }
        }
        resources = [ordered]@{
            app = @{
                type = 'Microsoft.Web/sites'; apiVersion = '2024-01-01'
                name = "[concat('app-', parameters('environment'), '-', parameters('version'))]"
                properties = @{
                    one = "[parameters('one')]"; empty = "[parameters('empty')]"; nested = "[parameters('nested')]"
                    literal = "[parameters('literal')]"
                }
            }
        }
    }
    $model = Invoke-ParserTest $template $parameterFile @{ ENVIRONMENT = 'prod'; VERSION = '$(Build.BuildNumber)'; LOCATION = '$(Region)' }
    Assert-Equal $model.resources[0].identityUnknown $true 'Macro-dependent identity unknown'
    Assert-Equal $model.resources[0].id.StartsWith('<unresolved:') $true 'Macro ID is unresolved marker'
    Assert-Equal $model.resources[0].name.Contains('$(') $false 'Unexpanded build macro is not a literal resource name'
    Assert-Equal $model.resources[0].location.StartsWith('<unresolved:') $true 'Unresolved override does not fall back to file/default location'
    Assert-Equal $model.resources[0].properties.one.Count 1 'Parameter single array preserved'
    Assert-Equal $model.resources[0].properties.empty.Count 0 'Parameter empty array preserved'
    Assert-Equal $model.resources[0].properties.nested[0][0] 'inner' 'Parameter nested single array preserved'
    Assert-Equal $model.resources[0].properties.literal "[parameters('not-an-expression')]" 'Parameter strings remain literal'
    $versionMetadata = @($model.diagnostics.parameters | Where-Object name -eq 'version')[0]
    Assert-Equal $versionMetadata.source 'explicitOverride' 'Explicit overrides win case-insensitively'
    Assert-Equal $versionMetadata.status 'Unverified' 'Unresolved build version diagnostics'
    Assert-Equal (@($model.diagnostics.parameters | Where-Object name -eq 'vault')[0]).status 'Unverified' 'Key Vault references stay unresolved'
    Assert-Equal $model.diagnostics.unresolvedResourceIds 1 'Unknown ID count'
    Assert-Equal $model.diagnostics.unresolvedParameters.Count 3 'Recursive unresolved parameter list'
    $model = Invoke-ParserTest $template $parameterFile @{ ENVIRONMENT = 'prod'; VERSION = '42' }
    Assert-Equal $model.resources[0].name 'app-prod-42' 'Effective explicit environment and version win'
    Assert-Equal $model.resources[0].identityUnknown $false 'Actual build version verifies identity'
    Assert-Equal $model.resources[0].location 'eastus' 'File location retained without explicit override'
    Assert-Equal (@($model.diagnostics.parameters | Where-Object name -eq 'one')[0]).source 'parameterFile' 'File provenance'

    Copy-Item -LiteralPath $parameterFile -Destination $global:parserTestParams
    $bicepParams = Join-Path $workRoot 'pipeline.bicepparam'
    Set-Content -LiteralPath $bicepParams -Value 'using none'
    $model = Invoke-ParserTest $template $bicepParams @{ environment = 'prod'; version = '43' }
    Assert-Equal $model.resources[0].name 'app-prod-43' 'Compiled bicepparam follows identical override precedence'

    $childTemplate = [ordered]@{
        parameters = [ordered]@{ stamp = @{ type = 'string'; defaultValue = "[utcNow('yyyyMMddHHmmss')]" } }
        resources = [ordered]@{
            stableChild = @{ type = 'Microsoft.Storage/storageAccounts'; apiVersion = '2023-01-01'; name = 'stable' }
            stampedChild = @{ type = 'Microsoft.Storage/storageAccounts'; apiVersion = '2023-01-01'; name = "[concat('store', parameters('stamp'))]" }
        }
    }
    $template = [ordered]@{
        parameters = [ordered]@{
            stamp = @{ type = 'string'; defaultValue = "[utcNow()]" }
            count = @{ type = 'int'; defaultValue = "[int(utcNow('ss'))]" }
        }
        resources = [ordered]@{
            module = @{
                type = 'Microsoft.Resources/deployments'; apiVersion = '2022-09-01'
                name = "[concat('deploy-', parameters('stamp'))]"
                properties = @{ template = $childTemplate }
            }
            extension = @{ type = $extensionType; apiVersion = '2022-04-01'; name = 'assignment'; scope = "[resourceInfo('module').id]" }
            conditional = @{
                type = 'Microsoft.Web/sites'; apiVersion = '2024-01-01'; name = 'conditional'
                condition = "[equals(parameters('stamp'), 'previous-stamp')]"
            }
            loop = @{
                type = 'Microsoft.Web/sites'; apiVersion = '2024-01-01'; name = "[concat('loop', copyIndex())]"
                copy = @{ name = 'loop'; count = "[parameters('count')]" }
            }
        }
    }
    $model = Invoke-ParserTest $template
    Assert-Equal $model.diagnostics.analysisTimestamp '2026-11-03T08:20:30.0000000+00:00' 'Analysis timestamp normalized to UTC'
    Assert-Equal $model.resources.Count 6 'Uncertain modules and loops still expanded'
    $deployment = @($model.resources | Where-Object type -eq 'Microsoft.Resources/deployments')[0]
    Assert-Equal $deployment.identityUnknown $true 'Synthetic deployment name does not verify identity'
    $extension = @($model.resources | Where-Object type -eq $extensionType)[0]
    Assert-Equal $extension.id.StartsWith('<unresolved:') $true 'Unresolved extension never fabricates RG ID'
    Assert-Equal $extension.name 'assignment' 'Extension name can be known while scope is unknown'
    Assert-Equal (@($model.resources | Where-Object name -eq 'stable')[0]).identityUnknown $false 'Unrelated module child identity remains known'
    Assert-Equal (@($model.resources | Where-Object name -eq 'conditional')[0]).existenceUnknown $true 'Timestamp-dependent condition remains unknown'
    Assert-Equal (@($model.resources | Where-Object symbolicName -eq 'loop')[0]).existenceUnknown $true 'Synthetic loop count stays unknown'
    $moduleMetadata = @($model.diagnostics.parameterScopes | Where-Object scope -ne '')[0].parameters[0]
    Assert-Equal $moduleMetadata.analysisValue '20261103082030' 'Child module shares one analysis instant'
    Assert-Equal $moduleMetadata.status 'Unverified' 'Module synthetic defaults unverified'
    $model = Invoke-ParserTest $template -AutomaticTimestamp
    Assert-Equal ((Get-Content -LiteralPath (Join-Path $workRoot 'model.json') -Raw) -match '"analysisTimestamp"\s*:\s*"[^"]+\+00:00"') $true 'Automatic analysis timestamp is UTC'
    $rootStamp = @($model.diagnostics.parameters | Where-Object name -eq 'stamp')[0].analysisValue
    $childStamp = @($model.diagnostics.parameterScopes | Where-Object scope -ne '')[0].parameters[0].analysisValue
    Assert-Equal ($rootStamp.Replace('T', '').Replace('Z', '')) $childStamp 'Automatic timestamp consistent across scopes'
    Assert-Equal (@($model.resources | Where-Object { $_.id -match '^/.*<unresolved:' }).Count) 0 'No fabricated ARM IDs containing unresolved markers'

    $template = [ordered]@{
        resources = [ordered]@{
            omitted = @{ type = 'Microsoft.Web/sites'; apiVersion = '2024-01-01'; name = 'omitted' }
            explicitNulls = @{
                type = 'Microsoft.Web/sites'; apiVersion = '2024-01-01'; name = 'nulls'
                properties = $null; tags = $null; sku = $null; kind = $null; identity = $null; zones = $null
            }
            declaredZones = @{ type = 'Microsoft.Web/sites'; apiVersion = '2024-01-01'; name = 'zones'; zones = @('1') }
        }
    }
    $model = Invoke-ParserTest $template
    foreach ($field in @('properties', 'tags', 'sku', 'kind', 'identity', 'zones')) {
        if ($field -in @('properties', 'tags')) {
            Assert-Equal @($model.resources[0].$field.PSObject.Properties).Count 0 "Undeclared $field is an empty schema-required object"
        }
        else {
            Assert-Equal ($null -eq $model.resources[0].PSObject.Properties[$field]) $true "Undeclared $field omitted"
        }
        Assert-Equal ($null -ne $model.resources[1].PSObject.Properties[$field]) $true "Explicit null $field present"
        Assert-Equal $model.resources[1].$field $null "Explicit null $field preserved"
    }
    Assert-Equal $model.resources[0].locationIsExplicit $false 'Inherited location remains explicitly annotated'
    Assert-Equal $model.resources[2].zones.Count 1 'Declared single zone preserved'

    $template = [ordered]@{
        parameters = [ordered]@{
            password = @{ type = 'secureString' }
            stamp = @{ type = 'secureString'; defaultValue = "[utcNow()]" }
        }
        resources = [ordered]@{
            app = @{ type = 'Microsoft.Web/sites'; apiVersion = '2024-01-01'; name = 'safe'; properties = @{ password = "[parameters('password')]" } }
        }
    }
    $model = Invoke-ParserTest $template -Overrides @{ password = 'DoNotPersist-ParserRegression' } -MaskSecrets
    Assert-Equal ((ConvertTo-Json $model -Depth 100).Contains('DoNotPersist-ParserRegression')) $false 'Parameter diagnostics do not leak secrets'
    Assert-Equal (@($model.diagnostics.parameters | Where-Object name -eq 'stamp')[0]).PSObject.Properties.Name.Contains('analysisValue') $false 'Secure analysis values not emitted'
    Write-Output "PASS: $script:assertions assertions (offline ARM expression and shared-parser regressions)."
}
finally {
    Remove-Item -LiteralPath $workRoot -Recurse -Force
    Remove-Variable -Name parserTestTemplate, parserTestParams -Scope Global
}
