#Requires -Version 7.0
<#
.SYNOPSIS
Builds an Azure resource model from live Azure resources or captured az JSON.
.DESCRIPTION
Uses `az resource list` as the primary discovery source, optionally enriches each
resource with targeted `az resource show` calls, and emits the shared resource
model JSON contract. Offline verification is supported through `-FromJson`, which
accepts a captured `az resource list` payload. The script can optionally apply the
shared filtering rules before returning the model.
.PARAMETER ResourceGroup
Optional Azure resource group name to scope discovery.
.PARAMETER SubscriptionId
Optional Azure subscription id to scope discovery.
.PARAMETER Enrich
When set, performs targeted `az resource show` calls and extracts configured
properties from `shared/data/azure-property-paths.json`.
.PARAMETER FromJson
Optional path to a captured `az resource list` JSON payload for offline mode.
.PARAMETER Mode
Optional filter mode. When provided, the script invokes `Select-AzureResources.ps1`
before returning the model.
.PARAMETER OutFile
Optional path to write the JSON resource model. If omitted, output is written to stdout.
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Requires Azure CLI for live mode. Offline mode only requires a captured JSON file.
.EXAMPLE
pwsh Get-AzureResourceModel.ps1 -ResourceGroup rg-demo -Enrich
.EXAMPLE
pwsh Get-AzureResourceModel.ps1 -FromJson .\captured-resource-list.json -Enrich -Mode diagram -OutFile model.json
#>
[CmdletBinding(DefaultParameterSetName = 'Live')]
param(
    [Parameter(ParameterSetName = 'Live')]
    [string]$ResourceGroup,

    [Parameter(ParameterSetName = 'Live')]
    [string]$SubscriptionId,

    [Parameter()]
    [switch]$Enrich,

    [Parameter(Mandatory = $true, ParameterSetName = 'Offline')]
    [string]$FromJson,

    [Parameter()]
    [ValidateSet('diagram', 'bicep')]
    [string]$Mode,

    [Parameter()]
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_Common.ps1"

$propertyConfigPath = Resolve-Path -Path (Join-Path $PSScriptRoot '..\data\azure-property-paths.json') -ErrorAction Stop
$propertyConfig = Get-Content -LiteralPath $propertyConfigPath -Raw | ConvertFrom-Json -Depth 100
$isOfflineMode = $PSCmdlet.ParameterSetName -eq 'Offline'

function ConvertTo-Hashtable {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return @{}
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[[string]$key] = ConvertTo-Hashtable -InputObject $InputObject[$key]
        }

        return $hash
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $hash = @{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
        }

        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $InputObject) {
            $items.Add((ConvertTo-Hashtable -InputObject $item))
        }

        return $items.ToArray()
    }

    return $InputObject
}

function Get-JsonPathValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ($null -eq $InputObject -or [string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $current = $InputObject
    foreach ($segment in ($Path -split '\.')) {
        if ($null -eq $current) {
            return $null
        }

        $segmentMatch = [regex]::Match($segment, '^(.+)\[(\d+)\]$')
        if ($segmentMatch.Success) {
            $propertyName = $segmentMatch.Groups[1].Value
            $index = [int]$segmentMatch.Groups[2].Value

            if ($current -is [System.Management.Automation.PSCustomObject]) {
                if (-not ($current.PSObject.Properties.Name -contains $propertyName)) { return $null }
                $current = $current.$propertyName
            }
            elseif ($current -is [System.Collections.IDictionary]) {
                if (-not $current.Contains($propertyName)) { return $null }
                $current = $current[$propertyName]
            }
            else {
                $current = $current.$propertyName
            }

            if ($null -eq $current) {
                return $null
            }

            $array = @($current)
            if ($index -ge $array.Count) {
                return $null
            }

            $current = $array[$index]
            continue
        }

        if ($current -is [System.Management.Automation.PSCustomObject]) {
            if (-not ($current.PSObject.Properties.Name -contains $segment)) { return $null }
            $current = $current.$segment
        }
        elseif ($current -is [System.Collections.IDictionary]) {
            if (-not $current.Contains($segment)) { return $null }
            $current = $current[$segment]
        }
        else {
            $current = $current.$segment
        }
    }

    return $current
}

function Get-ResourceTypeConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceType
    )

    foreach ($entry in $propertyConfig.resourceTypes) {
        if ($entry.resourceType -eq $ResourceType) {
            return $entry
        }
    }

    return $null
}

function Get-CompositePropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Rule,

        [Parameter(Mandatory = $true)]
        $ResourceJson
    )

    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($path in $Rule.assembledFrom) {
        $value = Get-JsonPathValue -InputObject $ResourceJson -Path $path
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            $parts.Add([string]$value)
        }
    }

    if ($parts.Count -eq 0) {
        return $null
    }

    if ($Rule.format -eq 'publisher:offer:sku:version') {
        return ($parts -join ':')
    }

    return ($parts -join ' ')
}

function Get-EnrichedProperties {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Resource,

        [Parameter(Mandatory = $true)]
        $ResourceJson
    )

    $properties = @{}
    $typeConfig = Get-ResourceTypeConfig -ResourceType ([string]$Resource.type)
    if ($null -eq $typeConfig) {
        return $properties
    }

    foreach ($property in $typeConfig.properties) {
        $path = [string]$property.armJsonPath
        if ($path -like 'composite:*') {
            $compositeName = $path.Substring('composite:'.Length)
            $rule = $propertyConfig.compositeRules | Where-Object {
                $_.resourceType -eq $Resource.type -and $_.property -eq $compositeName
            } | Select-Object -First 1

            if ($null -ne $rule) {
                $compositeValue = Get-CompositePropertyValue -Rule $rule -ResourceJson $ResourceJson
                if ($null -ne $compositeValue) {
                    $properties[$property.name] = $compositeValue
                }
            }

            continue
        }

        if ($path -match '\s+or\s+') {
            foreach ($candidate in ($path -split '\s+or\s+')) {
                $candidateValue = Get-JsonPathValue -InputObject $ResourceJson -Path $candidate.Trim()
                if ($null -ne $candidateValue) {
                    $properties[$property.name] = ConvertTo-Hashtable -InputObject $candidateValue
                    break
                }
            }

            continue
        }

        $value = Get-JsonPathValue -InputObject $ResourceJson -Path $path
        if ($null -ne $value) {
            $properties[$property.name] = ConvertTo-Hashtable -InputObject $value
        }
    }

    return $properties
}

function Get-RelationshipType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    switch -Regex ($PropertyName) {
        'subnet|virtualNetwork|networkInterface|backendAddressPool|frontendIPConfiguration|publicIPAddress' { return 'connects' }
        'workspace|serverFarm|managedEnvironment|privateDnsZone|privateLinkService|vault|identity' { return 'depends' }
        'applicationGateway|loadBalancer|routeTable|networkSecurityGroup' { return 'secures' }
        default { return 'depends' }
    }
}

function Add-Relationship {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$RelationshipMap,

        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [string]$TargetId,

        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    if ([string]::IsNullOrWhiteSpace($SourceId) -or [string]::IsNullOrWhiteSpace($TargetId) -or $SourceId -eq $TargetId) {
        return
    }

    $key = "$SourceId|$TargetId|$Type"
    if (-not $RelationshipMap.ContainsKey($key)) {
        $RelationshipMap[$key] = [PSCustomObject]@{
            targetId = $TargetId
            type = $Type
        }
    }
}

function Find-ResourceIdsInObject {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$ResourceIdMatches,

        [string]$PropertyName
    )

    if ($null -eq $InputObject) {
        return
    }

    if ($InputObject -is [string]) {
        if ($InputObject -match '^/subscriptions/.+/providers/.+$') {
            $ResourceIdMatches.Add([PSCustomObject]@{
                PropertyName = $PropertyName
                ResourceId = $InputObject
            })
        }

        return
    }

    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $InputObject.PSObject.Properties) {
            Find-ResourceIdsInObject -InputObject $property.Value -ResourceIdMatches $ResourceIdMatches -PropertyName $property.Name
        }

        return
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            Find-ResourceIdsInObject -InputObject $InputObject[$key] -ResourceIdMatches $ResourceIdMatches -PropertyName ([string]$key)
        }

        return
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        foreach ($item in $InputObject) {
            Find-ResourceIdsInObject -InputObject $item -ResourceIdMatches $ResourceIdMatches -PropertyName $PropertyName
        }
    }
}

function Get-ResourceGroupFromId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceId
    )

    $resourceGroupMatch = [regex]::Match($ResourceId, '/resourceGroups/([^/]+)/')
    if ($resourceGroupMatch.Success) {
        return $resourceGroupMatch.Groups[1].Value
    }

    return $null
}

function Get-ParentResourceId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceType
    )

    $typeSegments = $ResourceType -split '/'
    if ($typeSegments.Count -le 2) {
        return $null
    }

    $idSegments = $ResourceId.Trim('/') -split '/'
    $providerIndex = [Array]::IndexOf($idSegments, 'providers')
    if ($providerIndex -lt 0) {
        return $null
    }

    $providerPrefix = $idSegments[0..($providerIndex + 1)]
    $nameSegments = $idSegments[($providerIndex + 2)..($idSegments.Length - 1)]
    if ($nameSegments.Count -lt 2) {
        return $null
    }

    $parentTypeSegments = $typeSegments[0..($typeSegments.Count - 2)]
    $parentNameSegments = $nameSegments[0..($nameSegments.Count - 2)]

    return '/' + (($providerPrefix + $parentTypeSegments + $parentNameSegments) -join '/')
}

function Invoke-AzJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $azCommand = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if (-not $azCommand) {
        throw 'Azure CLI (az) is required for live discovery mode.'
    }

    $output = & $azCommand.Source @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("Azure CLI command failed: az {0}`n{1}" -f ($Arguments -join ' '), ($output -join [Environment]::NewLine))
    }

    $jsonText = ($output | Where-Object { $_ -is [string] }) -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($jsonText)) {
        return $null
    }

    return $jsonText | ConvertFrom-Json -Depth 100
}

function Get-DiscoveredResources {
    [CmdletBinding()]
    param()

    if ($isOfflineMode) {
        $resolvedPath = Resolve-Path -LiteralPath $FromJson -ErrorAction Stop
        Write-Diag "Loading offline resource list from '$resolvedPath'."
        return Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json -Depth 100
    }

    $arguments = @('resource', 'list', '--output', 'json')
    if (-not [string]::IsNullOrWhiteSpace($ResourceGroup)) {
        $arguments += @('--resource-group', $ResourceGroup)
    }
    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
        $arguments += @('--subscription', $SubscriptionId)
    }

    Write-Diag 'Running az resource list.'
    return Invoke-AzJson -Arguments $arguments
}

function Get-ResourceDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Resource
    )

    if (-not $Enrich.IsPresent -or $isOfflineMode) {
        return $Resource
    }

    $arguments = @('resource', 'show', '--ids', [string]$Resource.id, '--output', 'json')
    if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
        $arguments += @('--subscription', $SubscriptionId)
    }

    Write-Diag "Enriching '$($Resource.name)' ($($Resource.type))."
    return Invoke-AzJson -Arguments $arguments
}

try {
    $discovered = @(Get-DiscoveredResources)
    Write-Diag "Discovered $($discovered.Count) resource(s)."

    $resourceMap = @{}
    $relationshipMaps = @{}
    $modelResources = New-Object System.Collections.Generic.List[object]

    foreach ($resource in $discovered) {
        $details = Get-ResourceDetails -Resource $resource
        $properties = @{}
        if ($details.PSObject.Properties.Name -contains 'properties' -and $null -ne $details.properties) {
            $properties = ConvertTo-Hashtable -InputObject $details.properties
        }

        if ($Enrich.IsPresent) {
            $enrichedProperties = Get-EnrichedProperties -Resource $resource -ResourceJson $details
            foreach ($key in $enrichedProperties.Keys) {
                $properties[$key] = $enrichedProperties[$key]
            }
        }

        $tags = @{}
        if ($details.PSObject.Properties.Name -contains 'tags' -and $null -ne $details.tags) {
            $tags = ConvertTo-Hashtable -InputObject $details.tags
        }

        $resourceId = [string]$details.id
        $modelResource = [ordered]@{
            id = $resourceId
            type = [string]$details.type
            name = [string]$details.name
            resourceGroup = if ($details.PSObject.Properties.Name -contains 'resourceGroup') { [string]$details.resourceGroup } else { Get-ResourceGroupFromId -ResourceId $resourceId }
            location = if ($details.PSObject.Properties.Name -contains 'location') { [string]$details.location } else { $null }
            properties = $properties
            tags = $tags
            relationships = @()
        }

        $resourceMap[$resourceId] = $modelResource
        $relationshipMaps[$resourceId] = @{}
        $modelResources.Add([PSCustomObject]$modelResource)
    }

    foreach ($resource in $modelResources) {
        $parentId = Get-ParentResourceId -ResourceId ([string]$resource.id) -ResourceType ([string]$resource.type
        )
        if (-not [string]::IsNullOrWhiteSpace($parentId) -and $resourceMap.ContainsKey($parentId)) {
            Add-Relationship -RelationshipMap $relationshipMaps[$resource.id] -SourceId $resource.id -TargetId $parentId -Type 'contains'
        }

        $resourceIdMatches = New-Object System.Collections.Generic.List[object]
        Find-ResourceIdsInObject -InputObject $resource.properties -ResourceIdMatches $resourceIdMatches
        foreach ($match in $resourceIdMatches) {
            if ($resourceMap.ContainsKey([string]$match.ResourceId)) {
                $relationshipType = Get-RelationshipType -PropertyName ([string]$match.PropertyName)
                Add-Relationship -RelationshipMap $relationshipMaps[$resource.id] -SourceId $resource.id -TargetId ([string]$match.ResourceId) -Type $relationshipType
            }
        }
    }

    foreach ($resource in $modelResources) {
        $resource.relationships = @($relationshipMaps[$resource.id].Values)
    }

    $model = [ordered]@{
        resources = $modelResources.ToArray()
    }

    if (-not [string]::IsNullOrWhiteSpace($Mode)) {
        $tempInput = Join-Path ([System.IO.Path]::GetTempPath()) ("azverify-discovery-{0}.json" -f [guid]::NewGuid().ToString('N'))
        $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("azverify-discovery-filtered-{0}.json" -f [guid]::NewGuid().ToString('N'))
        try {
            Write-ResourceModel -Model $model -OutFile $tempInput
            & (Join-Path $PSScriptRoot 'Select-AzureResources.ps1') -InputFile $tempInput -Mode $Mode -OutFile $tempOutput
            $model = Get-Content -LiteralPath $tempOutput -Raw | ConvertFrom-Json -Depth 100
        }
        finally {
            foreach ($tempFile in @($tempInput, $tempOutput)) {
                if (Test-Path -LiteralPath $tempFile) {
                    Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }

    Write-ResourceModel -Model $model -OutFile $OutFile
}
catch {
    Invoke-Exit -Code 1 -Message "Azure resource discovery failed: $($_.Exception.Message)"
}