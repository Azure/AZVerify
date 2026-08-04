#Requires -Version 5.1
<#
.SYNOPSIS
Parses a Bicep template and emits an Azure resource model.
.DESCRIPTION
Compiles the Bicep file to ARM JSON using the az bicep or standalone bicep CLI,
then transforms the ARM JSON into a resource model per the shared contract.
Parameter file overrides are applied before resource name resolution.
.PARAMETER BicepFile
Path to the main.bicep file to parse.
.PARAMETER ParamFile
Optional path to the .bicepparam parameter override file.
.PARAMETER Depth
Resolution depth for ARM expressions: shallow (0), standard (4), or deep (20).
Defaults to 'standard'.
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
    & $command.Executable @commandArgs 2>&1 | ForEach-Object {
        if ($_ -is [string] -and -not [string]::IsNullOrWhiteSpace($_)) {
            Write-Diag $_
        }
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

    $document = ConvertFrom-Json -InputObject $content -Depth 100
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

function ConvertTo-ParameterValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-ParameterValue -Value $property.Value
        }

        return $hash
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $Value.Keys) {
            $hash[[string]$key] = ConvertTo-ParameterValue -Value $Value[$key]
        }

        return $hash
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $items.Add((ConvertTo-ParameterValue -Value $item))
        }

        return $items.ToArray()
    }

    $Value
}

function Get-ArmParameters {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Template,

        [hashtable]$Overrides
    )

    $parameters = @{}
    $templateParameters = $Template.parameters
    if ($null -eq $templateParameters) {
        return $parameters
    }

    foreach ($property in $templateParameters.PSObject.Properties) {
        $parameterName = $property.Name
        $parameterDefinition = $property.Value

        if ($Overrides.ContainsKey($parameterName)) {
            $parameters[$parameterName] = @{ value = (ConvertTo-ParameterValue -Value $Overrides[$parameterName]) }
            continue
        }

        if ($parameterDefinition.PSObject.Properties['defaultValue'] -and $null -ne $parameterDefinition.defaultValue) {
            $parameters[$parameterName] = @{ value = (ConvertTo-ParameterValue -Value $parameterDefinition.defaultValue) }
        }
    }

    $parameters
}


function Resolve-ArmExpression {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value,

        [AllowNull()]
        $Template,

        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters,

        [Parameter(Mandatory = $true)]
        [hashtable]$Variables,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [int]$DepthRemaining
    )

    if ($DepthRemaining -lt 0) {
        return $Value
    }

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        foreach ($property in $Value.PSObject.Properties) {
            $hash[$property.Name] = Resolve-ArmExpression -Value $property.Value -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
        }

        return $hash
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $Value.Keys) {
            $hash[[string]$key] = Resolve-ArmExpression -Value $Value[$key] -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
        }

        return $hash
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) {
            $items.Add((Resolve-ArmExpression -Value $item -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)))
        }

        return $items.ToArray()
    }

    if ($Value -isnot [string]) {
        return $Value
    }

    $text = $Value.Trim()
    if (-not ($text.StartsWith('[') -and $text.EndsWith(']'))) {
        return $Value
    }

    $expression = $text.Substring(1, $text.Length - 2).Trim()

    if ($expression -match "^parameters\('([^']+)'\)$") {
        $parameterName = $matches[1]
        if ($Parameters.ContainsKey($parameterName)) {
            return $Parameters[$parameterName].value
        }

        return $Value
    }

    if ($expression -match "^variables\('([^']+)'\)$") {
        $variableName = $matches[1]
        if ($Variables.ContainsKey($variableName)) {
            return $Variables[$variableName]
        }

        if ($null -ne $Template -and $Template -is [System.Management.Automation.PSCustomObject] -and $Template.PSObject.Properties['variables'] -and $null -ne $Template.variables -and $Template.variables -is [System.Management.Automation.PSCustomObject] -and $Template.variables.PSObject.Properties[$variableName]) {
            $resolvedVariable = Resolve-ArmExpression -Value $Template.variables.$variableName -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
            $Variables[$variableName] = $resolvedVariable
            return $resolvedVariable
        }

        return $Value
    }

    if ($expression -match '^resourceGroup\(\)\.location$') {
        return $Context.Location
    }

    if ($expression -match '^resourceGroup\(\)\.name$') {
        return $Context.ResourceGroupName
    }

    if ($expression -match '^subscription\(\)\.subscriptionId$') {
        return $Context.SubscriptionId
    }

    if ($expression -match '^concat\((.+)\)$') {
        $parts = Split-ArmArguments -ArgumentText $matches[1]
        $builder = New-Object System.Text.StringBuilder
        foreach ($part in $parts) {
            $resolvedPart = Resolve-ArmExpression -Value "[$part]" -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
            [void]$builder.Append([string]$resolvedPart)
        }

        return $builder.ToString()
    }

    if ($expression -match '^format\(') {
        $parts = Split-ArmArguments -ArgumentText ($expression.Substring(7, $expression.Length - 8))
        if ($parts.Count -gt 0) {
            $formatString = Resolve-ArmExpression -Value "[$($parts[0])]" -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
            $formatArgs = @()
            for ($index = 1; $index -lt $parts.Count; $index++) {
                $formatArgs += Resolve-ArmExpression -Value "[$($parts[$index])]" -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
            }

            return [string]::Format([string]$formatString, $formatArgs)
        }
    }

    if ($expression -match '^toLower\((.+)\)$') {
        $inner = Resolve-ArmExpression -Value "[$($matches[1])]" -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
        return ([string]$inner).ToLowerInvariant()
    }

    if ($expression -match '^toUpper\((.+)\)$') {
        $inner = Resolve-ArmExpression -Value "[$($matches[1])]" -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
        return ([string]$inner).ToUpperInvariant()
    }

    if ($expression -match '^resourceId\((.+)\)$') {
        $parts = Split-ArmArguments -ArgumentText $matches[1]
        if ($parts.Count -ge 1) {
            $typeValue = Resolve-ArmExpression -Value "[$($parts[0])]" -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
            $nameSegments = @()
            for ($index = 1; $index -lt $parts.Count; $index++) {
                $nameSegments += [string](Resolve-ArmExpression -Value "[$($parts[$index])]" -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1))
            }

            return "/subscriptions/$($Context.SubscriptionId)/resourceGroups/$($Context.ResourceGroupName)/providers/$typeValue/$($nameSegments -join '/')"
        }
    }

    if ($expression -match '^reference\((.+?)\)(\..+)?$') {
        $parts = Split-ArmArguments -ArgumentText $matches[1]
        if ($parts.Count -ge 1) {
            $referenceTarget = Resolve-ArmExpression -Value "[$($parts[0])]" -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
            if ($Context.ResourceIndex.ContainsKey([string]$referenceTarget)) {
                $resource = $Context.ResourceIndex[[string]$referenceTarget]
                $suffix = $matches[2]
                if ([string]::IsNullOrWhiteSpace($suffix)) {
                    return $resource
                }

                return Get-ObjectPropertyValue -InputObject $resource -PropertyPath $suffix.TrimStart('.')
            }
        }
    }

    if ($expression -match '^if\((.+)\)$') {
        $parts = Split-ArmArguments -ArgumentText $matches[1]
        if ($parts.Count -eq 3) {
            $condition = Resolve-ArmExpression -Value "[$($parts[0])]" -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
            if ([bool]$condition) {
                return Resolve-ArmExpression -Value "[$($parts[1])]" -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
            }

            return Resolve-ArmExpression -Value "[$($parts[2])]" -Template $Template -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining ($DepthRemaining - 1)
        }
    }

    if ($expression -match "^'(.*)'$") {
        return $matches[1]
    }

    if ($expression -match '^-?\d+$') {
        return [int64]$expression
    }

    if ($expression -match '^(true|false)$') {
        return [bool]::Parse($expression)
    }

    $Value
}

function Split-ArmArguments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArgumentText
    )

    $arguments = New-Object System.Collections.Generic.List[string]
    $builder = New-Object System.Text.StringBuilder
    $depth = 0
    $inString = $false

    for ($index = 0; $index -lt $ArgumentText.Length; $index++) {
        $character = $ArgumentText[$index]

        if ($character -eq "'") {
            $inString = -not $inString
            [void]$builder.Append($character)
            continue
        }

        if (-not $inString) {
            if ($character -eq '(') {
                $depth++
            }
            elseif ($character -eq ')') {
                $depth--
            }
            elseif ($character -eq ',' -and $depth -eq 0) {
                $arguments.Add($builder.ToString().Trim())
                $builder.Clear() | Out-Null
                continue
            }
        }

        [void]$builder.Append($character)
    }

    if ($builder.Length -gt 0) {
        $arguments.Add($builder.ToString().Trim())
    }

    # Use comma operator to prevent pipeline enumeration — a single-element List would otherwise
    # be unwrapped to a bare string by PowerShell, making .Count fail under Set-StrictMode.
    , $arguments.ToArray()
}

function Get-ObjectPropertyValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyPath
    )

    if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($PropertyPath)) {
        return $null
    }

    $current = $InputObject
    foreach ($segment in ($PropertyPath -split '\.')) {
        if ($null -eq $current) {
            return $null
        }

        if ($segment -match '^([A-Za-z0-9_]+)\[(\d+)\]$') {
            $propertyName = $matches[1]
            $arrayIndex = [int]$matches[2]

            if ($current -is [System.Management.Automation.PSCustomObject]) {
                if (-not $current.PSObject.Properties[$propertyName]) { return $null }
                $current = $current.$propertyName
            } elseif ($current -is [System.Collections.IDictionary]) {
                if (-not $current.Contains($propertyName)) { return $null }
                $current = $current[$propertyName]
            } else {
                $current = $current.$propertyName
            }

            $currentCount = if ($current -is [System.Collections.ICollection]) { $current.Count } elseif ($current -is [array]) { $current.Length } else { 0 }
            if ($null -eq $current -or $currentCount -le $arrayIndex) {
                return $null
            }

            $current = $current[$arrayIndex]
            continue
        }

        if ($current -is [System.Management.Automation.PSCustomObject]) {
            if (-not $current.PSObject.Properties[$segment]) { return $null }
            $current = $current.$segment
        } elseif ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($segment)) { return $null }
            $current = $current[$segment]
        } else {
            $current = $current.$segment
        }
    }

    $current
}

function Get-ResourceGroupNameFromTemplatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TemplatePath
    )

    Split-Path -Path (Split-Path -Path $TemplatePath -Parent) -Leaf
}

function Get-DepthLevel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DepthName
    )

    switch ($DepthName) {
        'shallow' { return 0 }
        'standard' { return 4 }
        'deep' { return 20 }
        default { return 4 }
    }
}

function Get-EnumerableResources {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Resources
    )

    if ($null -eq $Resources) {
        return @()
    }

    # ARM languageVersion 2.0 emits resources as a symbolic-name → resource map, surfaced
    # either as a hashtable or a PSCustomObject depending on the JSON parser.
    if ($Resources -is [System.Collections.IDictionary] -or $Resources -is [System.Management.Automation.PSCustomObject]) {
        if ($Resources -is [System.Collections.IDictionary]) {
            $namedResources = $Resources.Keys | ForEach-Object { @{ Name = [string]$_; Value = $Resources[$_] } }
        }
        else {
            $namedResources = $Resources.PSObject.Properties | ForEach-Object { @{ Name = [string]$_.Name; Value = $_.Value } }
        }

        $items = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $namedResources) {
            $resource = $entry.Value
            if ($resource -is [System.Management.Automation.PSCustomObject] -and -not $resource.PSObject.Properties['symbolicName']) {
                Add-Member -InputObject $resource -NotePropertyName 'symbolicName' -NotePropertyValue $entry.Name -Force
            }

            $items.Add($resource)
        }

        return $items.ToArray()
    }

    if ($Resources -is [System.Collections.IEnumerable] -and $Resources -isnot [string]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($resource in $Resources) {
            $items.Add($resource)
        }

        return $items.ToArray()
    }

    @($Resources)
}

function Get-ResourceNameFromId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceType
    )

    $segments = $ResourceId.Trim('/') -split '/'
    $typeSegments = $ResourceType -split '/'
    $providerIndex = [Array]::IndexOf($segments, 'providers')
    if ($providerIndex -lt 0) {
        return $ResourceId
    }

    $nameStartIndex = $providerIndex + 2 + $typeSegments.Length
    if ($nameStartIndex -ge $segments.Length) {
        return $ResourceId
    }

    $segments[$nameStartIndex..($segments.Length - 1)] -join '/'
}

function Convert-ArmResourceToModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Resource,

        [Parameter(Mandatory = $true)]
        [hashtable]$Parameters,

        [Parameter(Mandatory = $true)]
        [hashtable]$Variables,

        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $true)]
        [int]$DepthRemaining,

        [string]$ParentSymbolicName,

        [string]$SourceFile
    )

    Write-Diag 'Entered Convert-ArmResourceToModel.'
    if (-not $Resource.PSObject.Properties['type']) {
        return @()
    }
    Write-Diag 'Resolving resource name.'
    $resolvedName = $null
    if ($Resource.PSObject.Properties['name']) {
        $resolvedName = Resolve-ArmExpression -Value $Resource.name -Template $null -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining $DepthRemaining
    }
    Write-Diag 'Resolving resource location.'
    $resolvedLocation = $Context.Location
    if ($Resource.PSObject.Properties['location']) {
        $resolvedLocation = Resolve-ArmExpression -Value $Resource.location -Template $null -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining $DepthRemaining
    }
    Write-Diag 'Resolving resource tags.'
    $resolvedTags = @{}
    if ($Resource.PSObject.Properties['tags']) {
        $resolvedTags = Resolve-ArmExpression -Value $Resource.tags -Template $null -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining $DepthRemaining
    }
    Write-Diag 'Resolving resource properties.'
    $resolvedProperties = @{}
    if ($DepthRemaining -gt 0 -and $Resource.PSObject.Properties['properties']) {
        $resolvedProperties = Resolve-ArmExpression -Value $Resource.properties -Template $null -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining $DepthRemaining
    }

    Write-Diag 'Resolving resource id.'
    $resourceId = "/subscriptions/$($Context.SubscriptionId)/resourceGroups/$($Context.ResourceGroupName)/providers/$($Resource.type)/$resolvedName"
    if ($Resource.PSObject.Properties['id'] -and $Resource.id) {
        $resourceId = Resolve-ArmExpression -Value $Resource.id -Template $null -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining $DepthRemaining
    }

    if ([string]::IsNullOrWhiteSpace([string]$resolvedName)) {
        $resolvedName = Get-ResourceNameFromId -ResourceId ([string]$resourceId) -ResourceType ([string]$Resource.type)
    }

    Write-Diag 'Building model resource object.'
    $symbolicName = [string]$resolvedName
    if ($Resource.PSObject.Properties['symbolicName'] -and $Resource.symbolicName) {
        $symbolicName = [string]$Resource.symbolicName
    }
    $modelResource = [ordered]@{
        id = [string]$resourceId
        symbolicName = $symbolicName
        type = [string]$Resource.type
        apiVersion = [string]$Resource.apiVersion
        name = [string]$resolvedName
        sourceFile = [string]$SourceFile
        conditional = [bool]($Resource.PSObject.Properties['condition'] -and $null -ne $Resource.condition)
        parent = $ParentSymbolicName
        resourceGroup = $Context.ResourceGroupName
        location = $resolvedLocation
        properties = if ($resolvedProperties) { $resolvedProperties } else { @{} }
        tags = if ($resolvedTags) { $resolvedTags } else { @{} }
        relationships = @()
    }

    $Context.ResourceIndex[[string]$resourceId] = $modelResource
    $Context.ResourceIndex[$symbolicName] = $modelResource

    $results = New-Object System.Collections.Generic.List[object]
    $results.Add([PSCustomObject]$modelResource)

    if ($Resource.PSObject.Properties['resources'] -and $null -ne $Resource.resources) {
        foreach ($child in (Get-EnumerableResources -Resources $Resource.resources)) {
            $childSourceFile = if ($child.PSObject.Properties['sourceFile']) { [string]$child.sourceFile } else { $SourceFile }
            $childResults = Convert-ArmResourceToModel -Resource $child -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining $DepthRemaining -ParentSymbolicName $symbolicName -SourceFile $childSourceFile
            foreach ($childResult in $childResults) {
                $results.Add($childResult)
            }
        }
    }

    if ($Resource.type -eq 'Microsoft.Resources/deployments' -and $Resource.PSObject.Properties['properties']) {
        $deploymentProperties = $Resource.properties
        $deploymentTemplate = $null
        if ($deploymentProperties -is [System.Management.Automation.PSCustomObject] -and $deploymentProperties.PSObject.Properties['template']) {
            $deploymentTemplate = $deploymentProperties.template
        } elseif ($deploymentProperties -is [System.Collections.IDictionary] -and $deploymentProperties.Contains('template')) {
            $deploymentTemplate = $deploymentProperties['template']
        }

        $templateHasResources = $false
        if ($null -ne $deploymentTemplate) {
            if ($deploymentTemplate -is [System.Management.Automation.PSCustomObject] -and $deploymentTemplate.PSObject.Properties['resources']) {
                $templateHasResources = $true
            } elseif ($deploymentTemplate -is [System.Collections.IDictionary] -and $deploymentTemplate.ContainsKey('resources')) {
                $templateHasResources = $true
            }
        }

        if ($templateHasResources) {
            $nestedParameters = @{}
            $deploymentParamsObj = $null
            if ($deploymentProperties -is [System.Management.Automation.PSCustomObject] -and $deploymentProperties.PSObject.Properties['parameters']) {
                $deploymentParamsObj = $deploymentProperties.parameters
            } elseif ($deploymentProperties -is [System.Collections.IDictionary] -and $deploymentProperties.Contains('parameters')) {
                $deploymentParamsObj = $deploymentProperties['parameters']
            }

            if ($null -ne $deploymentParamsObj -and $deploymentParamsObj -is [System.Management.Automation.PSCustomObject]) {
                foreach ($parameterProperty in $deploymentParamsObj.PSObject.Properties) {
                    $paramRawValue = $null
                    if ($parameterProperty.Value -is [System.Management.Automation.PSCustomObject] -and $parameterProperty.Value.PSObject.Properties['value']) {
                        $paramRawValue = $parameterProperty.Value.value
                    } elseif ($parameterProperty.Value -is [System.Collections.IDictionary] -and $parameterProperty.Value.Contains('value')) {
                        $paramRawValue = $parameterProperty.Value['value']
                    }
                    $nestedParameters[$parameterProperty.Name] = @{
                        value = Resolve-ArmExpression -Value $paramRawValue -Template $null -Parameters $Parameters -Variables $Variables -Context $Context -DepthRemaining $DepthRemaining
                    }
                }
            }

            $nestedVariables = @{}
            $nestedSourceFile = if ($SourceFile) { $SourceFile } else { [System.IO.Path]::GetFileName($Context.TemplatePath) }
            foreach ($nestedResource in (Get-EnumerableResources -Resources $deploymentTemplate.resources)) {
                $nestedResults = Convert-ArmResourceToModel -Resource $nestedResource -Parameters $nestedParameters -Variables $nestedVariables -Context $Context -DepthRemaining $DepthRemaining -SourceFile $nestedSourceFile
                foreach ($nestedResult in $nestedResults) {
                    $results.Add($nestedResult)
                }
            }
        }
    }

    $results.ToArray()
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
    $temporaryDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("azverify-bicep-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporaryDirectory -Force | Out-Null

    try {
        $armTemplatePath = Join-Path -Path $temporaryDirectory -ChildPath 'template.json'
        $buildSucceeded = Invoke-BicepBuild -TemplatePath $resolvedBicepFile -OutputPath $armTemplatePath
        if (-not $buildSucceeded) {
            Invoke-Exit -Code 1 -Message 'Bicep CLI is unavailable. Install Azure CLI with Bicep support or the standalone bicep CLI.'
        }

        $template = Get-Content -LiteralPath $armTemplatePath -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 100
        $parameterOverrides = Get-ParameterOverrides -ParameterFilePath $resolvedParamFile -WorkingDirectory $temporaryDirectory
        $parameters = Get-ArmParameters -Template $template -Overrides $parameterOverrides
        $variables = @{}
        $resourceIndex = @{}
        $resourceGroupName = Get-ResourceGroupNameFromTemplatePath -TemplatePath $resolvedBicepFile
        $subscriptionId = '<subscription-id>'
        $location = if ($parameters.ContainsKey('location')) { [string]$parameters.location.value } else { 'resourceGroup().location' }
        $depthLevel = Get-DepthLevel -DepthName $Depth
        $sourceRoot = Split-Path -Path $resolvedBicepFile -Parent

        $context = @{
            ResourceIndex     = $resourceIndex
            TemplatePath      = $resolvedBicepFile
            ResourceGroupName = $resourceGroupName
            SubscriptionId    = $subscriptionId
            Location          = $location
        }

        $resources = New-Object System.Collections.Generic.List[object]
        Write-Diag 'Enumerating top-level ARM resources.'
        $topLevelResources = Get-EnumerableResources -Resources $template.resources
        Write-Diag ("Top-level ARM resource count: " + $topLevelResources.Count)
        foreach ($resource in $topLevelResources) {
            Write-Diag 'Converting top-level ARM resource.'
            $sourceFile = if ($resource.PSObject.Properties['sourceFile']) {
                [string]$resource.sourceFile
            }
            else {
                [System.IO.Path]::GetRelativePath($sourceRoot, $resolvedBicepFile)
            }

            $convertedResources = Convert-ArmResourceToModel -Resource $resource -Parameters $parameters -Variables $variables -Context $context -DepthRemaining $depthLevel -SourceFile $sourceFile
            foreach ($convertedResource in $convertedResources) {
                $resources.Add($convertedResource)
            }
        }

        foreach ($resource in $resources) {
            if (-not [string]::IsNullOrWhiteSpace($resource.parent) -and $resourceIndex.ContainsKey([string]$resource.parent)) {
                $parentResource = $resourceIndex[[string]$resource.parent]
                $resource.relationships += [PSCustomObject]@{
                    targetId = $parentResource.id
                    type = 'contains'
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
    }
}
catch {
    Invoke-Exit -Code 1 -Message "Bicep template conversion failed: $($_.Exception.Message)"
}
