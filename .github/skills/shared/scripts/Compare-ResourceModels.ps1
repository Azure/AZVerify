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

    if ($null -eq $Value) { 
        return '' 
    }
    $Value.Trim().ToLowerInvariant()
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

    $null
}

function Get-ParentContext {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Resource
    )

    $context = ''
    if ($Resource -and $Resource.PSObject.Properties['resourceGroup'] -and $Resource.resourceGroup) {
        $context += $Resource.resourceGroup.Trim().ToLowerInvariant()
    }

    $parentId = Get-ParentId -Resource $Resource
    if ($parentId) {
        $context += '|' + $parentId.Trim().ToLowerInvariant()
    }

    $context
}

function New-ResourceRecord {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Resource
    )

    # Normalize type/name/parent-context once so matching passes avoid recomputing them.
    [pscustomobject]@{
        Resource = $Resource
        Type     = Format-NormalizedText -Value $Resource.type
        Name     = Format-NormalizedText -Value $Resource.name
        Context  = Get-ParentContext -Resource $Resource
    }
}

$baseA = Read-ResourceModel -InputFile $ModelA
$baseB = Read-ResourceModel -InputFile $ModelB
$resourcesA = if ($baseA.resources) { @($baseA.resources) } else { @() }
$resourcesB = if ($baseB.resources) { @($baseB.resources) } else { @() }

$recordsA = @($resourcesA | ForEach-Object { New-ResourceRecord -Resource $_ })
$recordsB = @($resourcesB | ForEach-Object { New-ResourceRecord -Resource $_ })

$matchedA = [System.Collections.Generic.HashSet[object]]::new()
$matchedB = [System.Collections.Generic.HashSet[object]]::new()
$comparisonMatches = [System.Collections.Generic.List[object]]::new()

# Rule 1: Type + exact name + parent-context match, resolved via a key index so each
# candidate lookup is O(1) instead of scanning the full B list per A resource.
$exactIndexB = @{}
foreach ($rb in $recordsB) {
    $key = "$($rb.Type)|$($rb.Name)|$($rb.Context)"
    if (-not $exactIndexB.ContainsKey($key)) {
        $exactIndexB[$key] = [System.Collections.Generic.Queue[object]]::new()
    }
    $exactIndexB[$key].Enqueue($rb)
}

foreach ($ra in $recordsA) {
    $key = "$($ra.Type)|$($ra.Name)|$($ra.Context)"
    if ($exactIndexB.ContainsKey($key) -and $exactIndexB[$key].Count -gt 0) {
        $rb = $exactIndexB[$key].Dequeue()
        $comparisonMatches.Add(@{ status = 'In Sync'; resourceA = $ra.Resource; resourceB = $rb.Resource; note = 'Exact type and name match' })
        [void]$matchedA.Add($ra)
        [void]$matchedB.Add($rb)
    }
}

# Group remaining candidates by type + parent-context once, so Rule 2/3 look up a
# single bucket per A resource instead of re-filtering both full lists each time.
$typeGroupA = @{}
foreach ($ra in $recordsA) {
    $key = "$($ra.Type)|$($ra.Context)"
    if (-not $typeGroupA.ContainsKey($key)) {
        $typeGroupA[$key] = [System.Collections.Generic.List[object]]::new()
    }
    $typeGroupA[$key].Add($ra)
}

$typeGroupB = @{}
foreach ($rb in $recordsB) {
    $key = "$($rb.Type)|$($rb.Context)"
    if (-not $typeGroupB.ContainsKey($key)) {
        $typeGroupB[$key] = [System.Collections.Generic.List[object]]::new()
    }
    $typeGroupB[$key].Add($rb)
}

# Rule 2 and 3: Type match with unique count or fuzzy name.
foreach ($ra in $recordsA) {
    if ($matchedA.Contains($ra)) { continue }

    $key = "$($ra.Type)|$($ra.Context)"
    $groupA = if ($typeGroupA.ContainsKey($key)) { $typeGroupA[$key] } else { @() }
    $groupB = if ($typeGroupB.ContainsKey($key)) { $typeGroupB[$key] } else { @() }
    $unmatchedB = @($groupB | Where-Object { -not $matchedB.Contains($_) })

    if ($groupA.Count -eq 1 -and $unmatchedB.Count -eq 1) {
        $candidate = $unmatchedB[0]
        if ($ra.Name -ne $candidate.Name) {
            $comparisonMatches.Add(@{ status = 'In Sync (name differs)'; resourceA = $ra.Resource; resourceB = $candidate.Resource; note = 'Unique type in both models with different names' })
            [void]$matchedA.Add($ra)
            [void]$matchedB.Add($candidate)
            continue
        }
    }

    foreach ($candidate in $unmatchedB) {
        $nameA = $ra.Name
        $nameB = $candidate.Name
        $isSubstring = ($nameA -ne '' -and $nameB -ne '' -and ($nameA.Contains($nameB) -or $nameB.Contains($nameA)))
        $distance = Get-LevenshteinDistance -Left $nameA -Right $nameB

        if ($isSubstring -or $distance -le 3) {
            $comparisonMatches.Add(@{ status = 'In Sync (name differs)'; resourceA = $ra.Resource; resourceB = $candidate.Resource; note = "Fuzzy name match (substring or Levenshtein <= 3, distance=$distance)" })
            [void]$matchedA.Add($ra)
            [void]$matchedB.Add($candidate)
            break
        }
    }
}

# Final unmatched resources.
foreach ($ra in $recordsA) {
    if ($matchedA.Contains($ra)) { continue }
    $comparisonMatches.Add(@{ status = "$LabelA Only"; resourceA = $ra.Resource; resourceB = $null; note = 'Present only in first model' })
}

foreach ($rb in $recordsB) {
    if ($matchedB.Contains($rb)) { continue }
    $comparisonMatches.Add(@{ status = "$LabelB Only"; resourceA = $null; resourceB = $rb.Resource; note = 'Present only in second model' })
}

$summary = @{
    total          = $comparisonMatches.Count
    inSync         = 0
    inSyncNameDiff = 0
    onlyA          = 0
    onlyB          = 0
}

foreach ($entry in $comparisonMatches) {
    switch ($entry.status) {
        'In Sync' { $summary.inSync++ }
        'In Sync (name differs)' { $summary.inSyncNameDiff++ }
        "$LabelA Only" { $summary.onlyA++ }
        "$LabelB Only" { $summary.onlyB++ }
    }
}

$report = @{
    labelA  = $LabelA
    labelB  = $LabelB
    summary = $summary
    matches = @($comparisonMatches)
}

Write-ResourceModel -Model $report -OutFile $OutFile
