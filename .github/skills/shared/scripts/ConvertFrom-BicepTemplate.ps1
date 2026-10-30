#Requires -Version 5.1
<#
.SYNOPSIS
Parses a Bicep template and emits an Azure resource model.
.DESCRIPTION
Compiles the Bicep file to ARM JSON using the az bicep or standalone bicep CLI,
then evaluates the ARM JSON offline into a resource model per the shared contract.
Parameter file overrides are applied before evaluation. Variables, user-defined and
imported functions, module deployments, conditions and copy loops are evaluated;
resources whose condition is false are omitted. Values that depend on runtime state
are emitted as '<unresolved: reason>'.
.PARAMETER BicepFile
Path to the main.bicep file to parse.
.PARAMETER ParamFile
Optional path to the .bicepparam parameter override file.
.PARAMETER Depth
'shallow' resolves names, locations and tags only; 'standard' and 'deep' also resolve
resource properties. Defaults to 'standard'.
.PARAMETER OutFile
Optional path to write the JSON resource model. If omitted, output is written to stdout.
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Requires az CLI with bicep support, or the standalone bicep CLI.
If the bicep CLI is unavailable the script exits with code 1.
.EXAMPLE
pwsh ConvertFrom-BicepTemplate.ps1 -BicepFile main.bicep
.EXAMPLE
pwsh ConvertFrom-BicepTemplate.ps1 -BicepFile main.bicep -ParamFile prod.bicepparam -Depth deep -OutFile model.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$BicepFile,

    [Parameter()]
    [string]$ParamFile,

    [Parameter()]
    [ValidateSet('shallow', 'standard', 'deep')]
    [string]$Depth = 'standard',

    [Parameter()]
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_Common.ps1"
. "$PSScriptRoot/_ArmExpression.ps1"

function Resolve-FullPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$BasePath
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $Path))
}

function Get-BicepCommand {
    [CmdletBinding()]
    param()

    if (Get-Command -Name 'az' -ErrorAction SilentlyContinue) {
        return @{ Executable = 'az'; Prefix = @('bicep') }
    }

    if (Get-Command -Name 'bicep' -ErrorAction SilentlyContinue) {
        return @{ Executable = 'bicep'; Prefix = @() }
    }

    $null
}

function Invoke-BicepCli {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubCommand,

        [Parameter(Mandatory = $true)]
        [string]$InputPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    $command = Get-BicepCommand
    if ($null -eq $command) {
        return $false
    }

    $commandArgs = $command.Prefix + @($SubCommand, '--file', $InputPath, '--outfile', $OutputPath)

    Write-Diag "Running 'bicep $SubCommand' with $($command.Executable)."

    # Merging native stderr into the pipeline (2>&1) and piping through a cmdlet causes
    # Windows PowerShell 5.1 to raise a terminating NativeCommandError for any stderr
    # output-even benign warnings-when $ErrorActionPreference is 'Stop'. Temporarily
    # relax it around the native call so warnings are captured without aborting; actual
    # failures are still detected via the $LASTEXITCODE check below.
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $command.Executable @commandArgs 2>&1 | ForEach-Object {
            if ($_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_)) {
                Write-Diag $_
            }
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Bicep '$SubCommand' failed for '$InputPath'."
    }

    $true
}

function Invoke-BicepBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplatePath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    Invoke-BicepCli -SubCommand 'build' -InputPath $TemplatePath -OutputPath $OutputPath
}

function Invoke-BicepBuildParams {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParamPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    Invoke-BicepCli -SubCommand 'build-params' -InputPath $ParamPath -OutputPath $OutputPath
}

function Get-ParameterOverrides {
    [CmdletBinding()]
    param(
        [string]$ParameterFilePath,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    if ([string]::IsNullOrWhiteSpace($ParameterFilePath)) {
        return @{}
    }

    if (-not (Test-Path -LiteralPath $ParameterFilePath)) {
        throw "Parameter file not found: $ParameterFilePath"
    }

    # Compile the .bicepparam to ARM parameters JSON so values keep their real types
    # instead of being reconstructed from Bicep source text by hand.
    $paramsJsonPath = Join-Path -Path $WorkingDirectory -ChildPath 'params.json'
    if (-not (Invoke-BicepBuildParams -ParamPath $ParameterFilePath -OutputPath $paramsJsonPath)) {
        throw 'Bicep CLI is unavailable for parameter compilation.'
    }

    $content = Get-Content -LiteralPath $paramsJsonPath -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($content)) {
        return @{}
    }

    $document = ConvertFrom-Json -InputObject $content
    $overrides = @{}
    if ($document.PSObject.Properties['parameters'] -and $null -ne $document.parameters) {
        foreach ($property in $document.parameters.PSObject.Properties) {
            $entry = $property.Value
            if ($entry -is [System.Management.Automation.PSCustomObject] -and $entry.PSObject.Properties['value']) {
                $overrides[$property.Name] = $entry.value
            }
        }
    }

    $overrides
}

function Get-ResourceGroupNameFromTemplatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplatePath
    )

    Split-Path -Path (Split-Path -Path $TemplatePath -Parent) -Leaf
}

function Add-ArmResourceModel {
    # Walks one template scope, expanding copy loops, conditions and module deployments into model resources.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Scope,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Definitions,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Results,

        [bool]$IncludeProperties,

        [bool]$UseNameAsSymbol,

        [string]$ParentSymbolicName
    )

    foreach ($symbol in @($Definitions.Keys)) {
        $definition = $Definitions[$symbol]
        if ($definition -isnot [System.Collections.IDictionary] -or -not $definition.Contains('type')) { continue }
        if ($definition.Contains('existing') -and $definition['existing'] -eq $true) { continue }

        $iterations = @($null)
        if ($definition.Contains('copy')) {
            $count = Resolve-ArmValue $definition['copy']['count'] $Scope
            if ($count -is [ArmUnresolved]) {
                Write-Diag "Copy loop count for '$symbol' is unresolved ($($count.Reason)); emitting one placeholder resource."
            }
            elseif ([int]$count -gt 0) {
                $iterations = @(0..([int]$count - 1))
            }
            else {
                $iterations = @()
            }
        }

        foreach ($iteration in $iterations) {
            $iterationScope = $Scope
            if ($null -ne $iteration) {
                $iterationScope = Copy-ArmScope $Scope
                $iterationScope.CopyIndex[[string]$definition['copy']['name']] = $iteration
                $iterationScope.CopyIndex[''] = $iteration
            }

            $hasCondition = $definition.Contains('condition')
            $conditionUnknown = $false
            if ($hasCondition) {
                $condition = Resolve-ArmValue $definition['condition'] $iterationScope
                if ($condition -is [ArmUnresolved]) {
                    $conditionUnknown = $true
                }
                elseif (-not [bool]$condition) {
                    Write-Diag "Skipping '$symbol': condition evaluates to false."
                    continue
                }
            }

            $name = Resolve-ArmValue $definition['name'] $iterationScope
            $nameText = ConvertTo-ArmString (ConvertTo-ArmPlainValue $name)
            $symbolicName = if ($UseNameAsSymbol -and $name -isnot [ArmUnresolved]) { $nameText } else { [string]$symbol }
            if ($null -ne $iteration) { $symbolicName = '{0}[{1}]' -f $symbolicName, $iteration }

            $resourceType = [string]$definition['type']
            $resourceId = Get-ArmResourceId -Scope $iterationScope -Definition $definition -Name $name
            if ($null -eq $resourceId) {
                $resourceId = "/subscriptions/$($iterationScope.SubscriptionId)/resourceGroups/$($iterationScope.ResourceGroupName)/providers/$resourceType/$nameText"
            }

            $isDeployment = $resourceType -eq 'Microsoft.Resources/deployments'
            $location = if ($definition.Contains('location')) { Resolve-ArmValue $definition['location'] $iterationScope } else { $iterationScope.Location }
            $tags = if ($definition.Contains('tags')) { Resolve-ArmValue $definition['tags'] $iterationScope } else { $null }
            $properties = $null
            if ($IncludeProperties -and -not $isDeployment -and $definition.Contains('properties')) {
                $properties = Resolve-ArmValue $definition['properties'] $iterationScope
            }

            $Results.Add([PSCustomObject][ordered]@{
                    id            = [string]$resourceId
                    symbolicName  = $symbolicName
                    type          = $resourceType
                    apiVersion    = [string]$definition['apiVersion']
                    name          = $nameText
                    sourceFile    = [string]$iterationScope.SourceFile
                    conditional   = ($hasCondition -or $iterationScope.ConditionUnknown)
                    parent        = $ParentSymbolicName
                    resourceGroup = $iterationScope.ResourceGroupName
                    location      = (ConvertTo-ArmPlainValue $location)
                    properties    = if ($null -ne $properties) { ConvertTo-ArmPlainValue $properties } else { @{} }
                    tags          = if ($null -ne $tags) { ConvertTo-ArmPlainValue $tags } else { @{} }
                    relationships = @()
                })

            # Pre-languageVersion-2.0 templates may nest child resources inline.
            if ($definition.Contains('resources') -and (Test-ArmList $definition['resources'])) {
                $children = [ordered]@{}
                $childIndex = 0
                foreach ($child in $definition['resources']) {
                    $children["$symbol/child$childIndex"] = $child
                    $childIndex++
                }
                Add-ArmResourceModel -Scope $iterationScope -Definitions $children -Results $Results -IncludeProperties $IncludeProperties -UseNameAsSymbol $true -ParentSymbolicName $symbolicName
            }

            if ($isDeployment -and $definition['properties'] -is [System.Collections.IDictionary] -and $definition['properties'].Contains('template')) {
                $childScope = New-ArmChildScope -Scope $iterationScope -Definition $definition -DeploymentName $nameText
                $childScope.ConditionUnknown = $iterationScope.ConditionUnknown -or $conditionUnknown
                $childUsesNames = $childScope.Template['resources'] -isnot [System.Collections.IDictionary]
                Add-ArmResourceModel -Scope $childScope -Definitions $childScope.Symbols -Results $Results -IncludeProperties $IncludeProperties -UseNameAsSymbol $childUsesNames
            }
        }
    }
}

try {
    $resolvedBicepFile = Resolve-FullPath -Path $BicepFile
    if (-not (Test-Path -LiteralPath $resolvedBicepFile)) {
        Invoke-Exit -Code 1 -Message "Bicep file not found: $resolvedBicepFile"
    }

    $resolvedParamFile = if ($ParamFile) {
        if (Test-Path -LiteralPath $ParamFile) {
            Resolve-FullPath -Path $ParamFile
        }
        else {
            Resolve-FullPath -Path $ParamFile -BasePath (Split-Path -Path $resolvedBicepFile -Parent)
        }
    }
    else {
        $null
    }
    # Stay inside the workspace; the agent may lack permissions on the system temp folder.
    $temporaryRoot = Join-Path -Path (Split-Path -Path $resolvedBicepFile -Parent) -ChildPath '.azverify-tmp'
    $temporaryDirectory = Join-Path -Path $temporaryRoot -ChildPath ("bicep-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null

    try {
        $armTemplatePath = Join-Path -Path $temporaryDirectory -ChildPath 'template.json'
        $buildSucceeded = Invoke-BicepBuild -TemplatePath $resolvedBicepFile -OutputPath $armTemplatePath
        if (-not $buildSucceeded) {
            Invoke-Exit -Code 1 -Message 'Bicep CLI is unavailable. Install Azure CLI with Bicep support or the standalone bicep CLI.'
        }

        $template = ConvertTo-ArmObject (Get-Content -LiteralPath $armTemplatePath -Raw -ErrorAction Stop | ConvertFrom-Json)
        $suppliedParameters = ConvertTo-ArmObject (Get-ParameterOverrides -ParameterFilePath $resolvedParamFile -WorkingDirectory $temporaryDirectory)
        $resourceGroupName = Get-ResourceGroupNameFromTemplatePath -TemplatePath $resolvedBicepFile
        $subscriptionId = '<subscription-id>'
        $sourceRoot = Split-Path -Path $resolvedBicepFile -Parent
        Push-Location -LiteralPath $sourceRoot
        try {
            $sourceFile = (Resolve-Path -LiteralPath $resolvedBicepFile -Relative) -replace '^\.[\\/]', ''
        }
        finally {
            Pop-Location
        }

        # The 'location' parameter stands in for resourceGroup().location, which is unknown offline.
        $location = [ArmUnresolved]::new('resource group location')
        $locationKey = Find-ArmKey $suppliedParameters 'location'
        if ($null -ne $locationKey -and $suppliedParameters[$locationKey] -is [string]) {
            $location = $suppliedParameters[$locationKey]
        }
        elseif ($template['parameters'] -is [System.Collections.IDictionary] -and $template['parameters'].Contains('location')) {
            $locationDefault = $template['parameters']['location']['defaultValue']
            if ($locationDefault -is [string] -and -not $locationDefault.StartsWith('[')) {
                $location = $locationDefault
            }
        }

        $rootScope = New-ArmScope -Template $template -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName `
            -Location $location -Path '' -DeploymentName 'main' -SourceFile $sourceFile
        Set-ArmScopeParameters -Scope $rootScope -Supplied $suppliedParameters

        $resources = New-Object System.Collections.Generic.List[object]
        $rootUsesNames = $template['resources'] -isnot [System.Collections.IDictionary]
        Add-ArmResourceModel -Scope $rootScope -Definitions $rootScope.Symbols -Results $resources `
            -IncludeProperties ($Depth -ne 'shallow') -UseNameAsSymbol $rootUsesNames

        $resourceIndex = @{}
        foreach ($resource in $resources) {
            $resourceIndex[[string]$resource.symbolicName] = $resource
        }

        $unresolvedNames = @($resources | Where-Object { ([string]$_.name).Contains('<unresolved:') })
        if ($unresolvedNames.Count -gt 0) {
            Write-Diag "WARNING: $($unresolvedNames.Count) of $($resources.Count) resource name(s) could not be resolved offline:"
            foreach ($resource in $unresolvedNames) {
                Write-Diag "  $($resource.type) '$($resource.symbolicName)': $($resource.name)"
            }
        }
        else {
            Write-Diag "Resolved all $($resources.Count) resource name(s)."
        }

        foreach ($resource in $resources) {
            if (-not [string]::IsNullOrWhiteSpace($resource.parent) -and $resourceIndex.ContainsKey([string]$resource.parent)) {
                $parentResource = $resourceIndex[[string]$resource.parent]
                $resource.relationships += [PSCustomObject]@{
                    targetId = $parentResource.id
                    type     = 'contains'
                }
            }
        }

        $model = [ordered]@{
            resources = $resources.ToArray()
        }

        Write-ResourceModel -Model $model -OutFile $OutFile
    }
    finally {
        if (Test-Path -LiteralPath $temporaryDirectory) {
            Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ((Test-Path -LiteralPath $temporaryRoot) -and -not (Get-ChildItem -LiteralPath $temporaryRoot -Force)) {
            Remove-Item -LiteralPath $temporaryRoot -Force -ErrorAction SilentlyContinue
        }
    }
}
catch {
    Invoke-Exit -Code 1 -Message "Bicep template conversion failed: $($_.Exception.Message)"
}
