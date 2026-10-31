Set-StrictMode -Version Latest

function Get-ModelMember {
    [CmdletBinding()]
    param([AllowNull()]$Value, [string]$Name)

    if ($null -eq $Value) { return $null }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains($Name)) { return , $Value[$Name] }
    }
    elseif ($Value.PSObject.Properties[$Name]) { return , $Value.$Name }
}

function Get-ModelPath {
    [CmdletBinding()]
    param([AllowNull()]$Value, [string]$Path)

    $current = $Value
    foreach ($segment in ($Path -split '\.')) {
        if ($segment -match '^(.+)\[(\d+)\]$') {
            $items = Get-ModelMember $current $Matches[1]
            $index = [int]$Matches[2]
            if ($null -eq $items -or $index -ge @($items).Count) { return $null }
            $current = @($items)[$index]
        }
        else { $current = Get-ModelMember $current $segment }
        if ($null -eq $current) { return $null }
    }
    return , $current
}

function Test-ModelUnresolved {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($Value -is [string]) {
        return ($Value -eq 'unknown' -or $Value -eq '***' -or $Value -match '<unresolved:' -or $Value -match '^\[.*\]$')
    }
    if ($Value -is [System.Collections.IDictionary]) {
        foreach ($item in $Value.Values) { if (Test-ModelUnresolved $item) { return $true } }
    }
    elseif ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) { if (Test-ModelUnresolved $property.Value) { return $true } }
    }
    elseif ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) { if (Test-ModelUnresolved $item) { return $true } }
    }
    return $false
}

function ConvertTo-TrackedValue {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject]) {
        $result = [ordered]@{}
        $names = if ($Value -is [System.Collections.IDictionary]) { @($Value.Keys) } else { @($Value.PSObject.Properties.Name) }
        $isChild = $names -contains 'properties' -and $names -contains 'name'
        foreach ($name in $names) {
            if ($name -in @('etag', 'provisioningState', 'resourceGuid')) { continue }
            if ($isChild -and $name -in @('id', 'type')) { continue }
            $result[$name] = ConvertTo-TrackedValue (Get-ModelMember $Value $name)
        }
        return , $result
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = @($Value | ForEach-Object { ConvertTo-TrackedValue $_ })
        return , $items
    }
    return $Value
}

function Get-TrackedProperty {
    <#
    .SYNOPSIS
    Projects ARM-shaped resource data to the configured comparison properties.
    .DESCRIPTION
    Opt-in projection only; it does not replace raw properties or generation data.
    Missing expected fields are omitted. Missing requested actual fields are unknown.
    .PARAMETER Resource
    ARM-shaped resource or model preserving top-level fields.
    .PARAMETER Configuration
    Parsed azure-property-paths.json.
    .PARAMETER PropertyName
    When supplied, restrict projection to these requested properties.
    .EXAMPLE
    Get-TrackedProperty -Resource $resource -Configuration $config
    .OUTPUTS
    System.Collections.Hashtable
    .NOTES
    Does not infer defaults or read Azure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Resource,
        [Parameter(Mandatory)]$Configuration,
        [string[]]$PropertyName
    )

    $type = [string](Get-ModelMember $Resource 'type')
    $rules = @{}
    foreach ($rule in $Configuration.globalSkuRules) {
        if ($type -like $rule.resourceTypePattern) { $rules[$rule.property] = $rule.armJsonPath }
    }
    foreach ($entry in $Configuration.resourceTypes) {
        if ($entry.resourceType -eq $type) {
            foreach ($rule in $entry.properties) { $rules[$rule.name] = $rule.armJsonPath }
        }
    }
    $result = @{}
    foreach ($name in $rules.Keys) {
        if ($PSBoundParameters.ContainsKey('PropertyName') -and $name -notin $PropertyName) { continue }
        $path = [string]$rules[$name]
        $value = $null
        if ($path -like 'composite:*') {
            $composite = @($Configuration.compositeRules | Where-Object { $_.resourceType -eq $type -and $_.property -eq $name })
            if ($composite.Count -eq 1) {
                $parts = @($composite[0].assembledFrom | ForEach-Object { Get-ModelPath $Resource $_ })
                if ($parts.Count -eq $composite[0].assembledFrom.Count) { $value = $parts -join ':' }
            }
        }
        elseif ($path -notmatch '^derived ') {
            foreach ($candidate in ($path -split '\s+or\s+')) {
                $value = Get-ModelPath $Resource $candidate.Trim()
                if ($null -ne $value) { break }
            }
        }
        if ($null -ne $value) { $result[$name] = ConvertTo-TrackedValue $value }
        elseif ($PSBoundParameters.ContainsKey('PropertyName')) { $result[$name] = 'unknown' }
    }
    return $result
}
