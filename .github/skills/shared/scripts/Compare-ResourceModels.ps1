#Requires -Version 7.0
<#
.SYNOPSIS
Compares two Azure resource models and reports matches and drift.
.DESCRIPTION
Reads two JSON resource models and applies ordered matching rules:
exact type+name, unique-type-in-both, fuzzy name (substring or Levenshtein <= 3).
The script emits a comparison report with match status and summary counts.
.PARAMETER ModelA
Path to the first resource model JSON.
.PARAMETER ModelB
Path to the second resource model JSON.
.PARAMETER LabelA
Label for the first model in the output report. Defaults to 'ModelA'.
.PARAMETER LabelB
Label for the second model in the output report. Defaults to 'ModelB'.
.PARAMETER OutFile
Optional path to write the JSON comparison report. If omitted, output is written to stdout.
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
This script is intended for diagram/Bicep/Azure resource model comparisons.
.EXAMPLE
pwsh Compare-ResourceModels.ps1 -ModelA diagram.json -ModelB bicep.json
.EXAMPLE
pwsh Compare-ResourceModels.ps1 -ModelA diagram.json -ModelB live.json -LabelA Diagram -LabelB Azure -OutFile report.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ModelA,

    [Parameter(Mandatory = $true)]
    [string]$ModelB,

    [Parameter()]
    [string]$LabelA = 'ModelA',

    [Parameter()]
    [string]$LabelB = 'ModelB',

    [Parameter()]
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_Common.ps1"

function Format-NormalizedText {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Value
    )

    if ($null -eq $Value) { return '' }
    return $Value.Trim().ToLowerInvariant()
}

function Test-TypeMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LeftType,

        [Parameter(Mandatory = $true)]
        [string]$RightType
    )

    if ([string]::IsNullOrWhiteSpace($LeftType) -or [string]::IsNullOrWhiteSpace($RightType)) {
        return $false
    }
    $pattern = '^' + [regex]::Escape($LeftType).Replace('\*', '.*') + '$'
    return [regex]::IsMatch($RightType, $pattern, 'IgnoreCase')
}

function Get-ParentId {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Resource
    )

    if (-not $Resource -or -not $Resource.PSObject.Properties['properties']) {
        return $null
    }

    $properties = $Resource.properties
    if ($null -eq $properties) {
        return $null
    }

    if ($properties -is [System.Management.Automation.PSCustomObject]) {
        # Use the indexer (not .Name -contains) — member enumeration over an empty
        # property collection throws under Set-StrictMode when properties = {}.
        $member = $properties.PSObject.Properties['parentId']
        if ($member) {
            return $member.Value
        }
        return $null
    }

    if ($properties -is [System.Collections.IDictionary]) {
        if ($properties.Contains('parentId')) {
            return $properties['parentId']
        }
        return $null
    }

    return $null
}

function Test-SameParentContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ResourceA,

        [Parameter(Mandatory = $true)]
        $ResourceB
    )

    $contextA = ''
    $contextB = ''

    $parentIdA = Get-ParentId -Resource $ResourceA
    $parentIdB = Get-ParentId -Resource $ResourceB

    if ($ResourceA -and $ResourceA.PSObject.Properties['resourceGroup'] -and $ResourceA.resourceGroup) {
        $contextA += $ResourceA.resourceGroup.Trim().ToLowerInvariant()
    }
    if ($ResourceB -and $ResourceB.PSObject.Properties['resourceGroup'] -and $ResourceB.resourceGroup) {
        $contextB += $ResourceB.resourceGroup.Trim().ToLowerInvariant()
    }

    if ($parentIdA) {
        $contextA += '|' + $parentIdA.Trim().ToLowerInvariant()
    }
    if ($parentIdB) {
        $contextB += '|' + $parentIdB.Trim().ToLowerInvariant()
    }

    return $contextA -eq $contextB
}

function Group-ResourceByType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Resources
    )

    $collection = @{}
    foreach ($resource in $Resources) {
        $type = Format-NormalizedText -Value $resource.type
        if (-not $collection.ContainsKey($type)) {
            $collection[$type] = @()
        }
        $collection[$type] += $resource
    }
    return $collection
}

$baseA = Read-ResourceModel -InputFile $ModelA
$baseB = Read-ResourceModel -InputFile $ModelB
$resourcesA = if ($baseA.resources) { @($baseA.resources) } else { @() }
$resourcesB = if ($baseB.resources) { @($baseB.resources) } else { @() }

$matchedB = [System.Collections.ArrayList]@()
$comparisonMatches = @()

function Find-UnmatchedResource {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Predicate
    )

    foreach ($resource in $resourcesB) {
        if ($matchedB.Contains($resource)) { continue }
        if (& $Predicate $resource) {
            return $resource
        }
    }
    return $null
}

# Rule 1: Type + exact name match.
foreach ($resourceA in $resourcesA) {
    $match = Find-UnmatchedResource -Predicate {
        param($resourceB)
        return ((Format-NormalizedText -Value $resourceA.type) -eq (Format-NormalizedText -Value $resourceB.type)) -and
               ((Format-NormalizedText -Value $resourceA.name) -eq (Format-NormalizedText -Value $resourceB.name)) -and
               (Test-SameParentContext -ResourceA $resourceA -ResourceB $resourceB)
    }

    if ($match) {
        $comparisonMatches += @{ status = 'In Sync'; resourceA = $resourceA; resourceB = $match; note = 'Exact type and name match' }
        $matchedB.Add($match) | Out-Null
    }
}

# Rule 2 and 3: Type match with unique count or fuzzy name.
foreach ($resourceA in $resourcesA) {
    if ($comparisonMatches | Where-Object { $_.resourceA -eq $resourceA }) { continue }

    $typeKey = Format-NormalizedText -Value $resourceA.type
    $sameTypeA = @($resourcesA | Where-Object { (Format-NormalizedText -Value $_.type) -eq $typeKey -and (Test-SameParentContext -ResourceA $_ -ResourceB $resourceA) })
    $sameTypeB = @($resourcesB | Where-Object { (Format-NormalizedText -Value $_.type) -eq $typeKey -and -not $matchedB.Contains($_) -and (Test-SameParentContext -ResourceA $resourceA -ResourceB $_) })

    if ($sameTypeA.Count -eq 1 -and $sameTypeB.Count -eq 1) {
        $candidate = $sameTypeB[0]
        if ((Format-NormalizedText -Value $resourceA.name) -ne (Format-NormalizedText -Value $candidate.name)) {
            $comparisonMatches += @{ status = 'In Sync (name differs)'; resourceA = $resourceA; resourceB = $candidate; note = 'Unique type in both models with different names' }
            $matchedB.Add($candidate) | Out-Null
            continue
        }
    }

    foreach ($candidate in $sameTypeB) {
        $nameA = Format-NormalizedText -Value $resourceA.name
        $nameB = Format-NormalizedText -Value $candidate.name
        $isSubstring = ($nameA -ne '' -and $nameB -ne '' -and ($nameA.Contains($nameB) -or $nameB.Contains($nameA)))
        $distance = Get-LevenshteinDistance -Left $nameA -Right $nameB

        if ($isSubstring -or $distance -le 3) {
            $comparisonMatches += @{ status = 'In Sync (name differs)'; resourceA = $resourceA; resourceB = $candidate; note = "Fuzzy name match (substring or Levenshtein <= 3, distance=$distance)" }
            $matchedB.Add($candidate) | Out-Null
            break
        }
    }
}

# Final unmatched resources.
foreach ($resourceA in $resourcesA) {
    if ($comparisonMatches | Where-Object { $_.resourceA -eq $resourceA }) { continue }
    $comparisonMatches += @{ status = "$LabelA Only"; resourceA = $resourceA; resourceB = $null; note = 'Present only in first model' }
}

foreach ($resourceB in $resourcesB) {
    if ($matchedB.Contains($resourceB)) { continue }
    $comparisonMatches += @{ status = "$LabelB Only"; resourceA = $null; resourceB = $resourceB; note = 'Present only in second model' }
}

$summary = @{
    total          = @($comparisonMatches).Count
    inSync         = @($comparisonMatches | Where-Object { $_.status -eq 'In Sync' }).Count
    inSyncNameDiff = @($comparisonMatches | Where-Object { $_.status -eq 'In Sync (name differs)' }).Count
    onlyA          = @($comparisonMatches | Where-Object { $_.status -eq "$LabelA Only" }).Count
    onlyB          = @($comparisonMatches | Where-Object { $_.status -eq "$LabelB Only" }).Count
}

$report = @{
    labelA  = $LabelA
    labelB  = $LabelB
    summary = $summary
    matches = $comparisonMatches
}

Write-ResourceModel -Model $report -OutFile $OutFile
