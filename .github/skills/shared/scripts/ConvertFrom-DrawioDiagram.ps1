#Requires -Version 5.1
<#
.SYNOPSIS
Parses a Draw.io diagram file and emits an Azure resource model.
.DESCRIPTION
Reads a Draw.io XML file, classifies mxCell elements as Azure resources or containers
using a reverse image-path lookup against the stencil mapping, builds containment and
typed relationships, and emits a resource model JSON per the shared contract.
.PARAMETER DiagramPath
Path to the .drawio XML file to parse.
.PARAMETER StencilMapping
Optional path to the azure-stencil-mapping.json file.
Defaults to the shared/azure-stencil-mapping.json alongside this script.
.PARAMETER OutFile
Optional path to write the JSON resource model. If omitted, output is written to stdout.
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Icon-only cells (id ending with '-icon') and edge cells are skipped. Optional diagram
configuration metadata supplies annotated expected properties and values from a
selected diagram baseline. Annotations take precedence over baseline values.
.EXAMPLE
pwsh ConvertFrom-DrawioDiagram.ps1 -DiagramPath architecture.drawio
.EXAMPLE
pwsh ConvertFrom-DrawioDiagram.ps1 -DiagramPath architecture.drawio -OutFile model.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DiagramPath,

    [Parameter()]
    [string]$StencilMapping = (Join-Path $PSScriptRoot '..\azure-stencil-mapping.json'),

    [Parameter()]
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '_Common.ps1')

function Get-AttributeValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$Node,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    # XmlElement.GetAttribute returns '' (never $null) for a missing attribute.
    $Node.GetAttribute($Name)
}

function Get-ResourceTypeFromImagePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ImagePath,

        [Parameter()]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [hashtable]$ReverseLookup,

        [Parameter(Mandatory = $true)]
        [hashtable]$FallbackLookup
    )

    $normalized = $ImagePath.Trim().Replace('\', '/')
    $candidates = @()

    if ($ReverseLookup.ContainsKey($normalized)) {
        $candidates += @($ReverseLookup[$normalized])
    }

    if ($FallbackLookup.ContainsKey($normalized)) {
        $candidates += @($FallbackLookup[$normalized])
    }

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($normalized)
    if ($FallbackLookup.ContainsKey($fileName)) {
        $candidates += @($FallbackLookup[$fileName])
    }

    if ($candidates.Count -eq 0) {
        return "Microsoft.Resources/unknown:$fileName"
    }

    if ($candidates.Count -gt 1) {
        if ($Label -match 'email' -and ($candidates -match 'emailServices')) {
            return ($candidates | Where-Object { $_ -match 'emailServices' } | Select-Object -First 1)
        }

        if ($Label -match 'Communication Services' -and ($candidates -match 'communicationServices')) {
            return ($candidates | Where-Object { $_ -match 'communicationServices' } | Select-Object -First 1)
        }

        if ($Label -match 'Function App' -and ($candidates -match 'sites\[functionapp\]')) {
            return ($candidates | Where-Object { $_ -match 'sites\[functionapp\]' } | Select-Object -First 1)
        }
    }

    $candidates[0]
}

function Get-ContainerTypeFromStyle {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Style
    )

    if ($Style -match 'fillColor=#fff2cc') { return 'Microsoft.Resources/resourceGroups' }
    if ($Style -match 'fillColor=#dae8fc') { return 'Microsoft.Network/virtualNetworks' }
    if ($Style -match 'fillColor=#e1d5e7') { return 'Microsoft.Network/virtualNetworks/subnets' }
    if ($Style -match 'fillColor=#f5f5f5') { return 'Microsoft.Resources/resourceGroups' }

    $null
}

function Get-RelationshipTypeFromStyle {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Style
    )

    if ($Style -match 'strokeColor=#0078D4') { return 'connects' }
    if ($Style -match 'strokeColor=#E81123') { return 'secures' }
    if ($Style -match 'strokeColor=#00A4EF') { return 'peers' }
    if ($Style -match 'strokeColor=#999999' -and $Style -match 'dashed=1') { return 'depends' }

    'connects'
}

function Get-NormalizedName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    [System.Net.WebUtility]::HtmlDecode($Value).Replace("`r", '').Replace("`n", ' ').Trim()
}

function Get-CellMetadataAttribute {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$Cell,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Cell.HasAttribute($Name) -and -not [string]::IsNullOrWhiteSpace($Cell.GetAttribute($Name))) {
        return $Cell.GetAttribute($Name)
    }

    $wrapper = $Cell.ParentNode
    if ($wrapper -is [System.Xml.XmlElement] -and $wrapper.LocalName -in @('object', 'UserObject')) {
        $wrapperAttribute = if ($Name -eq 'value') { 'label' } else { $Name }
        if ($wrapper.HasAttribute($wrapperAttribute)) {
            return $wrapper.GetAttribute($wrapperAttribute)
        }
    }

    if ($Cell.HasAttribute($Name)) { return $Cell.GetAttribute($Name) }
    ''
}

function ConvertFrom-JsonObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    try {
        $value = ConvertFrom-Json -InputObject $Json -ErrorAction Stop
    }
    catch {
        throw "Invalid JSON in $Description metadata: $($_.Exception.Message)"
    }

    if ($null -eq $value -or $value -isnot [System.Management.Automation.PSCustomObject]) {
        throw "$Description metadata must be a JSON object."
    }

    $value
}

function Get-DiagramConfiguration {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Xml.XmlElement]$Diagram
    )

    if ($null -eq $Diagram -or -not $Diagram.HasAttribute('azverifyConfig')) {
        return $null
    }

    $configuration = ConvertFrom-JsonObject -Json $Diagram.GetAttribute('azverifyConfig') -Description 'azverifyConfig'
    if (-not $configuration.PSObject.Properties['version'] -or [int]$configuration.version -ne 1) {
        throw 'azverifyConfig metadata must declare version 1.'
    }

    if (-not $configuration.PSObject.Properties['selectedBaseline']) {
        throw 'azverifyConfig metadata must declare selectedBaseline.'
    }

    $baselineName = [string]$configuration.selectedBaseline
    if ([string]::IsNullOrWhiteSpace($baselineName)) {
        return $configuration
    }

    if (-not $configuration.PSObject.Properties['baselines'] -or
        -not $configuration.baselines.PSObject.Properties[$baselineName]) {
        throw "Selected diagram baseline '$baselineName' is not defined in azverifyConfig.baselines."
    }

    $selectedBaseline = $configuration.baselines.PSObject.Properties[$baselineName].Value
    if ($null -eq $selectedBaseline -or
        -not $selectedBaseline.PSObject.Properties['resources'] -or
        $selectedBaseline.resources -isnot [System.Management.Automation.PSCustomObject]) {
        throw "Selected diagram baseline '$baselineName' must define a resources object."
    }

    $configuration
}

function Get-ExpectedPropertiesForCell {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Xml.XmlElement]$Cell,

        [Parameter(Mandatory = $true)]
        [string]$ResourceId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceType,

        [Parameter()]
        [object]$Configuration,

        [Parameter(Mandatory = $true)]
        [object]$PropertyConfiguration
    )

    $baselineValues = [ordered]@{}
    $baselineName = $null
    if ($Configuration -and -not [string]::IsNullOrWhiteSpace([string]$Configuration.selectedBaseline)) {
        $baselineName = [string]$Configuration.selectedBaseline
        $resourceBaselines = $Configuration.baselines.PSObject.Properties[$baselineName].Value.resources

        foreach ($lookupKey in @($ResourceType, $ResourceId)) {
            $baselineEntry = $resourceBaselines.PSObject.Properties[$lookupKey]
            if ($baselineEntry) {
                if ($baselineEntry.Value -isnot [System.Management.Automation.PSCustomObject]) {
                    throw "Baseline values for '$lookupKey' must be a JSON object."
                }

                foreach ($property in $baselineEntry.Value.PSObject.Properties) {
                    $baselineValues[$property.Name] = $property.Value
                }
            }
        }
    }

    $annotationValues = $null
    $annotationJson = Get-CellMetadataAttribute -Cell $Cell -Name 'azverifyProperties'
    if (-not [string]::IsNullOrWhiteSpace($annotationJson)) {
        $annotationValues = ConvertFrom-JsonObject -Json $annotationJson -Description "azverifyProperties for resource '$ResourceId'"
    }

    $expectedProperties = [ordered]@{}
    $propertySources = [ordered]@{}

    foreach ($property in $baselineValues.Keys) {
        $expectedProperties[$property] = $baselineValues[$property]
        $propertySources[$property] = "selectedBaseline:$baselineName"
    }

    if ($annotationValues) {
        foreach ($property in $annotationValues.PSObject.Properties) {
            $expectedProperties[$property.Name] = $property.Value
            $propertySources[$property.Name] = 'annotation'
        }
    }

    $allowedProperties = @($PropertyConfiguration.globalSkuRules |
        Where-Object { $ResourceType -like $_.resourceTypePattern } |
        ForEach-Object { $_.property })
    $allowedProperties += @($PropertyConfiguration.resourceTypes |
        Where-Object { $_.resourceType -eq $ResourceType } |
        ForEach-Object { $_.properties } |
        ForEach-Object { $_.name })
    foreach ($property in $expectedProperties.Keys) {
        if ($property -notin $allowedProperties) {
            throw "Unknown tracked property '$property' for diagram resource '$ResourceId' ($ResourceType)."
        }
    }

    [PSCustomObject]@{
        Values  = $expectedProperties
        Sources = $propertySources
    }
}

try {
    if (-not (Test-Path -LiteralPath $DiagramPath)) {
        Invoke-Exit -Code 1 -Message "Diagram file not found: $DiagramPath"
    }

    if (-not (Test-Path -LiteralPath $StencilMapping)) {
        Invoke-Exit -Code 1 -Message "Stencil mapping file not found: $StencilMapping"
    }

    $mapping = Get-Content -LiteralPath $StencilMapping -Raw -ErrorAction Stop | ConvertFrom-Json
    $propertyConfiguration = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../data/azure-property-paths.json') -Raw -ErrorAction Stop | ConvertFrom-Json
    $reverseLookup = @{}

    foreach ($entry in $mapping.resourceTypes.PSObject.Properties) {
        $typeName = $entry.Name
        $details = $entry.Value

        if ($details -is [System.Management.Automation.PSCustomObject] -and $details.PSObject.Properties.Name -contains 'imagePath') {
            $path = [string]$details.imagePath
            if (-not $reverseLookup.ContainsKey($path)) {
                $reverseLookup[$path] = New-Object System.Collections.Generic.List[string]
            }

            $reverseLookup[$path].Add($typeName)
        }
    }

    $fallbackLookup = @{
        'Resource_Groups'              = 'Microsoft.Resources/resourceGroups'
        'Virtual_Networks'             = 'Microsoft.Network/virtualNetworks'
        'Subnet'                       = 'Microsoft.Network/virtualNetworks/subnets'
        'Private_Endpoint'             = 'Microsoft.Network/privateEndpoints'
        'Public_IP_Addresses'          = 'Microsoft.Network/publicIPAddresses'
        'Application_Gateways'         = 'Microsoft.Network/applicationGateways'
        'Network_Interfaces'           = 'Microsoft.Network/networkInterfaces'
        'Key_Vaults'                   = 'Microsoft.KeyVault/vaults'
        'Storage_Accounts'             = 'Microsoft.Storage/storageAccounts'
        'Managed_Identities'           = 'Microsoft.ManagedIdentity/userAssignedIdentities'
        'Azure_Communication_Services' = 'Microsoft.Communication/communicationServices'
        'Application_Insights'         = 'Microsoft.Insights/components'
        'Log_Analytics_Workspaces'     = 'Microsoft.OperationalInsights/workspaces'
        'Virtual_Machine'              = 'Microsoft.Compute/virtualMachines'
        'App_Service_Plans'            = 'Microsoft.Web/serverFarms'
        'App_Services'                 = 'Microsoft.Web/sites'
        'Function_Apps'                = 'Microsoft.Web/sites'
        'SQL_Server'                   = 'Microsoft.Sql/servers'
        'SQL_Database'                 = 'Microsoft.Sql/servers/databases'
        'DNS_Zones'                    = 'Microsoft.Network/privateDnsZones'
        'Cognitive_Services'           = 'Microsoft.CognitiveServices/accounts'
        'Event_Hubs'                   = 'Microsoft.EventHub/namespaces'
        'Container_App_Environments'   = 'Microsoft.App/managedEnvironments'
        'System_Topic'                 = 'Microsoft.EventGrid/systemTopics'
        'Event_Grid_Topics'            = 'Microsoft.EventGrid/topics'
        'Event_Grid_Domains'           = 'Microsoft.EventGrid/domains'
        'App_Configuration'            = 'Microsoft.AppConfiguration/configurationStores'
        'Service_Bus'                  = 'Microsoft.ServiceBus/namespaces'
        'Nat'                          = 'Microsoft.Network/natGateways'
        'Load_Balancers'               = 'Microsoft.Network/loadBalancers'
        'Virtual_Network_Gateways'     = 'Microsoft.Network/virtualNetworkGateways'
    }

    [xml]$diagramXml = Get-Content -LiteralPath $DiagramPath -Raw -ErrorAction Stop

    $cells = @($diagramXml.SelectNodes('//*[local-name()="mxCell"]'))
    $cellById = @{}
    foreach ($cell in $cells) {
        $cellId = Get-CellMetadataAttribute -Cell $cell -Name 'id'
        if ($cellId) { $cellById[$cellId] = $cell }
    }

    $resources = New-Object System.Collections.Generic.List[object]
    $resourceMap = @{}
    $parentByResourceId = @{}

    foreach ($cell in $cells) {
        $id = Get-CellMetadataAttribute -Cell $cell -Name 'id'
        $style = Get-AttributeValue -Node $cell -Name 'style'
        $edge = Get-AttributeValue -Node $cell -Name 'edge'
        $parent = Get-AttributeValue -Node $cell -Name 'parent'
        $value = Get-CellMetadataAttribute -Cell $cell -Name 'value'
        $imagePath = $null

        if ($style -and $style -match 'image=([^;]+)') {
            $imagePath = $Matches[1].Trim()
        }

        if ($edge -eq '1') {
            continue
        }

        if ($id -like '*-icon') {
            continue
        }

        $isContainer = $style -match 'container=1' -or $style -match 'fillColor=#fff2cc' -or $style -match 'fillColor=#dae8fc' -or $style -match 'fillColor=#e1d5e7'
        $hasImage = -not [string]::IsNullOrWhiteSpace($imagePath)

        if (-not $hasImage -and -not $isContainer) {
            continue
        }

        $name = Get-NormalizedName -Value $value
        if ([string]::IsNullOrWhiteSpace($name)) {
            $name = $id
        }

        $type = $null
        if ($hasImage) {
            $type = Get-ResourceTypeFromImagePath -ImagePath $imagePath -Label $name -ReverseLookup $reverseLookup -FallbackLookup $fallbackLookup
        }

        if (-not $type) {
            $type = Get-ContainerTypeFromStyle -Style $style
        }

        if (-not $type) {
            continue
        }

        $resource = [ordered]@{
            id            = $id
            type          = $type
            name          = $name
            resourceGroup = $null
            location      = $null
            properties    = @{}
            tags          = @{}
            relationships = @()
        }

        $diagramNode = $cell
        while ($diagramNode -and $diagramNode.LocalName -ne 'diagram') {
            $diagramNode = $diagramNode.ParentNode
        }
        $diagramConfiguration = Get-DiagramConfiguration -Diagram $diagramNode
        $expected = Get-ExpectedPropertiesForCell -Cell $cell -ResourceId $id -ResourceType $type -Configuration $diagramConfiguration -PropertyConfiguration $propertyConfiguration
        foreach ($property in $expected.Values.Keys) {
            $resource.properties[$property] = $expected.Values[$property]
        }
        $resource.comparisonProperties = $expected.Values
        if ($expected.Sources.Count -gt 0) {
            $resource.propertySources = $expected.Sources
        }

        $containerName = $null
        if ($parent -and $parent -ne '1') {
            $containerCell = $cellById[$parent]
            if ($containerCell) {
                $containerName = Get-NormalizedName -Value (Get-AttributeValue -Node $containerCell -Name 'value')
                if ([string]::IsNullOrWhiteSpace($containerName)) {
                    $containerName = (Get-CellMetadataAttribute -Cell $containerCell -Name 'id')
                }

                $resource.properties.containerName = $containerName

                if ((Get-ContainerTypeFromStyle -Style (Get-AttributeValue -Node $containerCell -Name 'style')) -eq 'Microsoft.Resources/resourceGroups') {
                    $resource.resourceGroup = $containerName
                }
            }
        }

        if ($resource.type -eq 'Microsoft.Resources/resourceGroups') {
            $resource.resourceGroup = $name
        }

        $resourceMap[$id] = $resource
        $parentByResourceId[$id] = $parent
        $resources.Add($resource)
    }

    foreach ($cell in $cells) {
        $edge = Get-AttributeValue -Node $cell -Name 'edge'
        if ($edge -ne '1') {
            continue
        }

        $sourceId = Get-AttributeValue -Node $cell -Name 'source'
        $targetId = Get-AttributeValue -Node $cell -Name 'target'
        $style = Get-AttributeValue -Node $cell -Name 'style'

        if (-not $resourceMap.ContainsKey($sourceId) -or -not $resourceMap.ContainsKey($targetId)) {
            continue
        }

        $relationType = Get-RelationshipTypeFromStyle -Style $style
        $resourceMap[$sourceId].relationships += [PSCustomObject]@{
            targetId = $targetId
            type     = $relationType
        }
    }

    foreach ($resource in $resourceMap.Values) {
        $parentId = $parentByResourceId[$resource.id]

        if ($parentId -and $parentId -ne '1' -and $resourceMap.ContainsKey($parentId)) {
            $resource.relationships += [PSCustomObject]@{
                targetId = $parentId
                type     = 'contains'
            }
        }
    }

    $model = [ordered]@{ resources = @($resources.ToArray()) }
    Write-ResourceModel -Model $model -OutFile $OutFile
}
catch {
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $_.Exception,
        'ConvertFromDrawioDiagramFailed',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $DiagramPath
    )
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}
