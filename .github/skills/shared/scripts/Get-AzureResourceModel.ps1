<#
.SYNOPSIS
Builds an Azure resource model from live Azure resources or a captured JSON payload.
.DESCRIPTION
Uses `az resource list` (Azure CLI) or `Get-AzResource` (Az PowerShell) as the
primary discovery source, optionally enriches each resource with targeted
`az resource show`/`Get-AzResource -ResourceId` calls, and emits the shared
resource model JSON contract. When Azure CLI (az) is not on PATH, the script
automatically falls back to the Az PowerShell (Az.Resources) module, so live
discovery works with either tool. Offline verification is supported through
`-FromJson`, which accepts a captured `az resource list` (or equivalent) JSON
payload. The script can optionally apply the shared filtering rules before
returning the model.
.PARAMETER ResourceGroup
Optional Azure resource group name to scope discovery.
.PARAMETER SubscriptionId
Optional Azure subscription id to scope discovery.
.PARAMETER Enrich
When set, performs targeted per-resource enrichment calls (`az resource show`
or `Get-AzResource -ResourceId`) and extracts configured properties from
`shared/data/azure-property-paths.json`.
.PARAMETER StripReadOnly
When set, removes read-only and ARM-internal properties using the rules in
`shared/data/arm-readonly-properties.json`. Use for Bicep generation; leave off
for drift comparison, which may need the full property bag.
.PARAMETER FromJson
Optional path to a captured `az resource list` (or equivalent) JSON payload for offline mode.
.PARAMETER Mode
Optional filter mode. When provided, the script invokes `Select-AzureResources.ps1`
before returning the model.
.PARAMETER OutFile
Optional path to write the JSON resource model. If omitted, output is written to stdout.
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
Live mode requires either Azure CLI (az) on PATH or an authenticated Az PowerShell
session (Connect-AzAccount) with the Az.Resources module installed; Azure CLI is
preferred when both are available. Offline mode only requires a captured JSON file.
.EXAMPLE
pwsh Get-AzureResourceModel.ps1 -ResourceGroup rg-demo -Enrich
.EXAMPLE
pwsh Get-AzureResourceModel.ps1 -ResourceGroup rg-demo -Enrich -Mode bicep -StripReadOnly -OutFile model.json
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

    [Parameter()]
    [switch]$StripReadOnly,

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

$propertyConfigPath = Resolve-Path -Path (Join-Path $PSScriptRoot '../data/azure-property-paths.json') -ErrorAction Stop
$propertyConfig = Get-Content -LiteralPath $propertyConfigPath -Raw | ConvertFrom-Json

# Index config once so per-resource lookups are O(1) instead of rescanning the arrays.
$resourceTypeConfigIndex = @{}
foreach ($resourceTypeEntry in $propertyConfig.resourceTypes) {
    $resourceTypeConfigIndex[[string]$resourceTypeEntry.resourceType] = $resourceTypeEntry
}

$compositeRuleIndex = @{}
foreach ($compositeRule in $propertyConfig.compositeRules) {
    $compositeRuleIndex[('{0}|{1}' -f $compositeRule.resourceType, $compositeRule.property)] = $compositeRule
}

$readOnlyConfigPath = Resolve-Path -Path (Join-Path $PSScriptRoot '../data/arm-readonly-properties.json') -ErrorAction Stop
$readOnlyConfig = Get-Content -LiteralPath $readOnlyConfigPath -Raw | ConvertFrom-Json

$alwaysRemoveAnyDepth = [System.Collections.Generic.HashSet[string]]::new([string[]]$readOnlyConfig.alwaysRemoveAnyDepth, [System.StringComparer]::OrdinalIgnoreCase)
$alwaysRemoveAtRoot = [System.Collections.Generic.HashSet[string]]::new([string[]]$readOnlyConfig.alwaysRemoveAtRoot, [System.StringComparer]::OrdinalIgnoreCase)
$secretNameRegexes = foreach ($pattern in $readOnlyConfig.secretPatterns.namePatterns) { [System.Management.Automation.WildcardPattern]::new($pattern, 'IgnoreCase') }
$secretExclusionRegexes = foreach ($pattern in $readOnlyConfig.secretPatterns.nameExclusionPatterns) { [System.Management.Automation.WildcardPattern]::new($pattern, 'IgnoreCase') }
$maskedValueRegex = [regex]::new($readOnlyConfig.secretPatterns.maskedValueRegex)

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

function Test-PropertyPathRule {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [string[]]$Rules,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    foreach ($rule in $Rules) {
        if ($Path.Equals($rule, [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ($Path.EndsWith(".$rule", [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }

    $false
}

function Remove-ReadOnlyProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject,

        [Parameter()]
        [string]$Path = ''
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in @($InputObject.Keys)) {
            $name = [string]$key
            $childPath = if ($Path) { "$Path.$name" } else { $name }

            if (Test-PropertyPathRule -Rules $readOnlyConfig.keepPaths -Path $childPath) {
                $result[$key] = $InputObject[$key]
                continue
            }

            if (
                (Test-PropertyPathRule -Rules $readOnlyConfig.removePaths -Path $childPath) -or
                $alwaysRemoveAnyDepth.Contains($name) -or
                ($Path -eq '' -and $alwaysRemoveAtRoot.Contains($name))
            ) {
                continue
            }

            $result[$key] = Remove-ReadOnlyProperty -InputObject $InputObject[$key] -Path $childPath
        }

        return $result
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $InputObject) {
            $items.Add((Remove-ReadOnlyProperty -InputObject $item -Path $Path))
        }

        return $items.ToArray()
    }

    $InputObject
}

function Test-SecretName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Name
    )

    foreach ($exclusion in $secretExclusionRegexes) {
        if ($exclusion.IsMatch($Name)) { return $false }
    }

    foreach ($pattern in $secretNameRegexes) {
        if ($pattern.IsMatch($Name)) { return $true }
    }

    return $false
}

function Find-SecretProperty {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]]$Found,

        [Parameter()]
        [string]$Path = ''
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        # name/value pairs (app settings, connection strings) carry the secret in 'value'.
        if ($InputObject.Contains('name') -and $InputObject.Contains('value') -and (Test-SecretName -Name ([string]$InputObject['name']))) {
            $settingPath = if ($Path) { "$Path[$($InputObject['name'])]" } else { [string]$InputObject['name'] }
            if (-not $Found.Contains($settingPath)) {
                $Found.Add($settingPath)
            }

            $InputObject['value'] = '***'
            return
        }

        foreach ($key in @($InputObject.Keys)) {
            $name = [string]$key
            $childPath = if ($Path) { "$Path.$name" } else { $name }
            $value = $InputObject[$key]

            $isSecret = Test-SecretName -Name $name
            if (-not $isSecret -and $value -is [string] -and $maskedValueRegex.IsMatch($value)) {
                $isSecret = $true
            }

            if ($isSecret) {
                if (-not $Found.Contains($childPath)) {
                    $Found.Add($childPath)
                }

                $InputObject[$key] = '***'
                continue
            }

            Find-SecretProperty -InputObject $value -Found $Found -Path $childPath
        }

        return
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        foreach ($item in $InputObject) {
            Find-SecretProperty -InputObject $item -Found $Found -Path $Path
        }
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

$script:azureDiscoveryMethod = $null

function Resolve-AzureDiscoveryMethod {
    <#
    .SYNOPSIS
    Determines whether live discovery should use Azure CLI (az) or Az PowerShell,
    preferring Azure CLI when both are available. Result is cached for the
    lifetime of the script run so the detection only happens once.
    #>
    [CmdletBinding()]
    param()

    if ($script:azureDiscoveryMethod) {
        return $script:azureDiscoveryMethod
    }

    $azCommand = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($azCommand) {
        Write-Diag "Using Azure CLI ('$($azCommand.Source)') for live discovery."
        $script:azureDiscoveryMethod = 'AzureCLI'
        return $script:azureDiscoveryMethod
    }

    $azPowerShellContext = $null
    try {
        $azPowerShellContext = Get-AzContext -ErrorAction Stop
    }
    catch {
        $azPowerShellContext = $null
    }

    if ($azPowerShellContext -and $azPowerShellContext.Account) {
        Write-Diag "Azure CLI (az) not found; using Az PowerShell context '$($azPowerShellContext.Account.Id)' for live discovery."
        $script:azureDiscoveryMethod = 'AzPowerShell'
        return $script:azureDiscoveryMethod
    }

    throw 'Live discovery requires either Azure CLI (az) on PATH or an authenticated Az PowerShell session (run Connect-AzAccount, with the Az.Resources module installed).'
}

function ConvertTo-GenericResourceModel {
    <#
    .SYNOPSIS
    Normalizes an Az PowerShell resource object (from Get-AzResource) into the
    same PSCustomObject shape produced by parsing az CLI JSON output, so
    downstream code can consume either source interchangeably.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $AzResource
    )

    $propertyNames = $AzResource.PSObject.Properties.Name

    return [PSCustomObject]@{
        id            = [string]$AzResource.ResourceId
        name          = [string]$AzResource.Name
        type          = [string]$AzResource.ResourceType
        resourceGroup = [string]$AzResource.ResourceGroupName
        location      = if ($propertyNames -contains 'Location') { [string]$AzResource.Location } else { $null }
        tags          = if ($propertyNames -contains 'Tags' -and $AzResource.Tags) { $AzResource.Tags } else { $null }
        sku           = if ($propertyNames -contains 'Sku' -and $AzResource.Sku) { $AzResource.Sku } else { $null }
        kind          = if ($propertyNames -contains 'Kind' -and $AzResource.Kind) { [string]$AzResource.Kind } else { $null }
        identity      = if ($propertyNames -contains 'Identity' -and $AzResource.Identity) { $AzResource.Identity } else { $null }
        properties    = if ($propertyNames -contains 'Properties') { $AzResource.Properties } else { $null }
    }
}

function Set-AzPowerShellSubscriptionContext {
    <#
    .SYNOPSIS
    Switches the active Az PowerShell context to the requested subscription, if
    it isn't already active, mirroring az CLI's per-call '--subscription' scoping.
    #>
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
        return
    }

    $currentContext = Get-AzContext -ErrorAction SilentlyContinue
    if ($currentContext -and $currentContext.Subscription.Id -eq $SubscriptionId) {
        return
    }

    Write-Diag "Switching Az PowerShell context to subscription '$SubscriptionId'."
    $null = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
}

function Assert-AzResourcesModule {
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name 'Get-AzResource' -ErrorAction SilentlyContinue)) {
        throw "The 'Az.Resources' PowerShell module is required for Az PowerShell discovery. Install it with: Install-Module Az.Resources -Scope CurrentUser"
    }
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

    # Assign before returning: Windows PowerShell 5.1's ConvertFrom-Json does not
    # enumerate array results onto the pipeline (PS 7+ does), so piping straight into
    # 'return' silently collapses arrays to a single element. Assignment captures the
    # array correctly in both versions; a plain 'return' of the variable then unrolls
    # it consistently.
    $parsedJson = $jsonText | ConvertFrom-Json
    return $parsedJson
}

try {
    if ($isOfflineMode) {
        $resolvedPath = Resolve-Path -LiteralPath $FromJson -ErrorAction Stop
        Write-Diag "Loading offline resource list from '$resolvedPath'."
        # See comment in Invoke-AzJson: assign before using the result to avoid PS 5.1's
        # ConvertFrom-Json array-enumeration quirk.
        $discovered = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json
    }
    elseif ((Resolve-AzureDiscoveryMethod) -eq 'AzPowerShell') {
        Assert-AzResourcesModule
        Set-AzPowerShellSubscriptionContext

        $getParams = @{ ErrorAction = 'Stop'; ExpandProperties = $true }
        if (-not [string]::IsNullOrWhiteSpace($ResourceGroup)) {
            $getParams['ResourceGroupName'] = $ResourceGroup
        }

        Write-Diag 'Running Get-AzResource (Az PowerShell) for resource discovery.'
        $azResources = @(Get-AzResource @getParams)
        $discovered = @($azResources | ForEach-Object { ConvertTo-GenericResourceModel -AzResource $_ })
    }
    else {
        $arguments = @('resource', 'list', '--output', 'json')
        if (-not [string]::IsNullOrWhiteSpace($ResourceGroup)) {
            $arguments += @('--resource-group', $ResourceGroup)
        }
        if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
            $arguments += @('--subscription', $SubscriptionId)
        }

        Write-Diag 'Running az resource list.'
        $discovered = Invoke-AzJson -Arguments $arguments
    }

    $discovered = @($discovered)
    Write-Diag "Discovered $($discovered.Count) resource(s)."

    $resourceMap = @{}
    $relationshipMaps = @{}
    $modelResources = New-Object System.Collections.Generic.List[object]

    foreach ($resource in $discovered) {
        $isEnriching = $Enrich.IsPresent
        if (-not $isEnriching -or $isOfflineMode) {
            $details = $resource
        }
        elseif ((Resolve-AzureDiscoveryMethod) -eq 'AzPowerShell') {
            Assert-AzResourcesModule
            Set-AzPowerShellSubscriptionContext

            Write-Diag "Enriching '$($resource.id)' via Get-AzResource (Az PowerShell)."
            $azResource = Get-AzResource -ResourceId ([string]$resource.id) -ExpandProperties -ErrorAction Stop
            $details = ConvertTo-GenericResourceModel -AzResource $azResource
        }
        else {
            $arguments = @('resource', 'show', '--ids', [string]$resource.id, '--output', 'json')
            if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
                $arguments += @('--subscription', $SubscriptionId)
            }

            Write-Diag "Enriching '$($resource.name)' ($($resource.type))."
            $details = Invoke-AzJson -Arguments $arguments
        }

        $detailPropertyNames = $details.PSObject.Properties.Name
        $properties = @{}
        if ($detailPropertyNames -contains 'properties' -and $null -ne $details.properties) {
            $properties = ConvertTo-Hashtable -InputObject $details.properties

            if ($StripReadOnly.IsPresent) {
                $properties = Remove-ReadOnlyProperty -InputObject $properties
            }
        }

        $enrichedProperties = @{}
        if ($isEnriching) {
            $typeConfig = $resourceTypeConfigIndex[[string]$resource.type]
            if ($null -ne $typeConfig) {
                foreach ($property in $typeConfig.properties) {
                    $path = [string]$property.armJsonPath
                    if ($path -like 'composite:*') {
                        $compositeName = $path.Substring('composite:'.Length)
                        $compositeKey = '{0}|{1}' -f $resource.type, $compositeName
                        $rule = $compositeRuleIndex[$compositeKey]

                        if ($null -ne $rule) {
                            $parts = New-Object System.Collections.Generic.List[string]
                            foreach ($partPath in $rule.assembledFrom) {
                                $value = Get-JsonPathValue -InputObject $details -Path $partPath
                                if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
                                    $parts.Add([string]$value)
                                }
                            }

                            if ($parts.Count -gt 0) {
                                $enrichedProperties[$property.name] = if ($rule.format -eq 'publisher:offer:sku:version') {
                                    $parts -join ':'
                                }
                                else {
                                    $parts -join ' '
                                }
                            }
                        }

                        continue
                    }

                    if ($path -match '\s+or\s+') {
                        foreach ($candidate in ($path -split '\s+or\s+')) {
                            $candidateValue = Get-JsonPathValue -InputObject $details -Path $candidate.Trim()
                            if ($null -ne $candidateValue) {
                                $enrichedProperties[$property.name] = ConvertTo-Hashtable -InputObject $candidateValue
                                break
                            }
                        }

                        continue
                    }

                    $value = Get-JsonPathValue -InputObject $details -Path $path
                    if ($null -ne $value) {
                        $enrichedProperties[$property.name] = ConvertTo-Hashtable -InputObject $value
                    }
                }
            }

            foreach ($key in $enrichedProperties.Keys) {
                $properties[$key] = $enrichedProperties[$key]
            }
        }

        $tags = if ($detailPropertyNames -contains 'tags' -and $null -ne $details.tags) {
            ConvertTo-Hashtable -InputObject $details.tags
        }
        else {
            @{}
        }

        $deployableProperties = if ($isEnriching) { $enrichedProperties } else { @{} }

        $sku = if ($detailPropertyNames -contains 'sku' -and $null -ne $details.sku) {
            ConvertTo-Hashtable -InputObject $details.sku
        }
        else {
            @{}
        }

        $identity = @{}
        if ($detailPropertyNames -contains 'identity' -and $null -ne $details.identity) {
            $identity = ConvertTo-Hashtable -InputObject $details.identity
            if ($StripReadOnly.IsPresent) {
                $identity = Remove-ReadOnlyProperty -InputObject @{ identity = $identity }
                $identity = $identity['identity']
            }
        }

        $resourceId = [string]$details.id
        $resourceGroup = if ($detailPropertyNames -contains 'resourceGroup') {
            [string]$details.resourceGroup
        }
        else {
            $resourceGroupMatch = [regex]::Match($resourceId, '/resourceGroups/([^/]+)/')
            if ($resourceGroupMatch.Success) {
                $resourceGroupMatch.Groups[1].Value
            }
            else {
                $null
            }
        }

        $modelResource = [ordered]@{
            id = $resourceId
            type = [string]$details.type
            name = [string]$details.name
            resourceGroup = $resourceGroup
            location = if ($detailPropertyNames -contains 'location') { [string]$details.location } else { $null }
            properties = $properties
            deployableProperties = $deployableProperties
            tags = $tags
            sku = $sku
            kind = if ($detailPropertyNames -contains 'kind') { [string]$details.kind } else { $null }
            identity = $identity
            relationships = @()
        }

        # Mask secrets in the raw discovery bag before it can be written to disk, but only
        # require secure Bicep parameters for mapped values that generation can emit.
        $rawSecrets = New-Object System.Collections.Generic.List[string]
        Find-SecretProperty -InputObject $properties -Found $rawSecrets

        $deployableSecrets = New-Object System.Collections.Generic.List[string]
        Find-SecretProperty -InputObject $deployableProperties -Found $deployableSecrets

        $secrets = New-Object System.Collections.Generic.List[string]
        foreach ($secretPath in @($rawSecrets) + @($deployableSecrets)) {
            if (-not $secrets.Contains($secretPath)) {
                $secrets.Add($secretPath)
            }
        }

        if ($secrets.Count -gt 0) {
            $modelResource['secrets'] = $secrets.ToArray()
            Write-Diag "Flagged $($secrets.Count) secret-bearing property path(s) on '$($details.name)'."
        }

        $resourceMap[$resourceId] = $modelResource
        $relationshipMaps[$resourceId] = @{}
        $modelResources.Add([PSCustomObject]$modelResource)
    }

    foreach ($resource in $modelResources) {
        $parentId = $null
        $typeSegments = ([string]$resource.type) -split '/'
        if ($typeSegments.Count -gt 2) {
            $idSegments = ([string]$resource.id).Trim('/') -split '/'
            $providerIndex = [Array]::IndexOf($idSegments, 'providers')
            if ($providerIndex -ge 0) {
                $providerPrefix = $idSegments[0..($providerIndex + 1)]
                $nameSegments = $idSegments[($providerIndex + 2)..($idSegments.Length - 1)]
                if ($nameSegments.Count -ge 2) {
                    $parentNameSegments = $nameSegments[0..($nameSegments.Count - 3)]
                    $parentId = '/' + (($providerPrefix + $parentNameSegments) -join '/')
                }
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($parentId) -and $resourceMap.ContainsKey($parentId)) {
            Add-Relationship -RelationshipMap $relationshipMaps[$resource.id] -SourceId $resource.id -TargetId $parentId -Type 'contains'
        }

        $resourceIdMatches = New-Object System.Collections.Generic.List[object]
        Find-ResourceIdsInObject -InputObject $resource.properties -ResourceIdMatches $resourceIdMatches
        foreach ($match in $resourceIdMatches) {
            if ($resourceMap.ContainsKey([string]$match.ResourceId)) {
                $relationshipType = switch -Regex ([string]$match.PropertyName) {
                    'subnet|virtualNetwork|networkInterface|backendAddressPool|frontendIPConfiguration|publicIPAddress' { 'connects'; break }
                    'workspace|serverFarm|managedEnvironment|privateDnsZone|privateLinkService|vault|identity' { 'depends'; break }
                    'applicationGateway|loadBalancer|routeTable|networkSecurityGroup' { 'secures'; break }
                    default { 'depends' }
                }
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
            $model = Get-Content -LiteralPath $tempOutput -Raw | ConvertFrom-Json
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