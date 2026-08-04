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
Icon-only cells (id ending with '-icon') and edge cells are skipped.
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

try {
    if (-not (Test-Path -LiteralPath $DiagramPath)) {
        Invoke-Exit -Code 1 -Message "Diagram file not found: $DiagramPath"
    }

    if (-not (Test-Path -LiteralPath $StencilMapping)) {
        Invoke-Exit -Code 1 -Message "Stencil mapping file not found: $StencilMapping"
    }

    $mapping = Get-Content -LiteralPath $StencilMapping -Raw -ErrorAction Stop | ConvertFrom-Json -Depth 100
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
        $cellId = $cell.GetAttribute('id')
        if ($cellId) { $cellById[$cellId] = $cell }
    }

    $resources = New-Object System.Collections.Generic.List[object]
    $resourceMap = @{}
    $parentByResourceId = @{}

    foreach ($cell in $cells) {
        $id = Get-AttributeValue -Node $cell -Name 'id'
        $style = Get-AttributeValue -Node $cell -Name 'style'
        $edge = Get-AttributeValue -Node $cell -Name 'edge'
        $parent = Get-AttributeValue -Node $cell -Name 'parent'
        $value = Get-AttributeValue -Node $cell -Name 'value'
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

        $containerName = $null
        if ($parent -and $parent -ne '1') {
            $containerCell = $cellById[$parent]
            if ($containerCell) {
                $containerName = Get-NormalizedName -Value (Get-AttributeValue -Node $containerCell -Name 'value')
                if ([string]::IsNullOrWhiteSpace($containerName)) {
                    $containerName = (Get-AttributeValue -Node $containerCell -Name 'id')
                }

                $resource.location = $containerName

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
