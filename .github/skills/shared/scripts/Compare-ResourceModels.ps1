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
.PARAMETER CompareProperties
When set, matched resource pairs are also compared property-by-property. Model A is
treated as the expected state: every property in a matched A resource is compared
against the B resource using normalization rules (case-insensitive enums, boolean
coercion, empty-collection equivalence, numeric strings, region names). Drifted
properties are tagged with the severity classification from
shared/data/azure-property-paths.json.
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
.EXAMPLE
pwsh Compare-ResourceModels.ps1 -ModelA bicep.json -ModelB azure.json -LabelA Bicep -LabelB Azure -CompareProperties
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
    [switch]$CompareProperties,

    [Parameter()]
    [switch]$AzureIdentity,

    [Parameter()]
    [switch]$TrackedProperties,

    [Parameter()]
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_Common.ps1"
. "$PSScriptRoot/_ResourceProjection.ps1"

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


    $parentId = Get-ParentId -Resource $Resource
    if ($parentId) {
        return $parentId.Trim().ToLowerInvariant()
    }
    if ($Resource -and $Resource.PSObject.Properties['resourceGroup'] -and -not [string]::IsNullOrWhiteSpace([string]$Resource.resourceGroup)) {
        return ([string]$Resource.resourceGroup).Trim().ToLowerInvariant()
    }

    ''
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

function Test-EmptyValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) { return $true }
    if ($Value -is [string]) { return [string]::IsNullOrWhiteSpace($Value) }
    if ($Value -is [System.Collections.IDictionary]) { return $Value.Count -eq 0 }
    if ($Value -is [System.Management.Automation.PSCustomObject]) { return @($Value.PSObject.Properties).Count -eq 0 }
    if ($Value -is [System.Collections.IEnumerable]) { return @($Value).Count -eq 0 }

    $false
}

function ConvertTo-NormalizedBoolean {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        $Value
    )

    if ($Value -is [bool]) { return $Value }
    if ($Value -is [string]) {
        switch (([string]$Value).Trim().ToLowerInvariant()) {
            'true' { return $true }
            'false' { return $false }
        }
    }

    $null
}

function ConvertTo-NormalizedNumber {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value -or $Value -is [bool]) { return $null }
    if ($Value -isnot [string] -and $Value -isnot [System.ValueType]) { return $null }

    $parsed = [decimal]0
    $styles = [System.Globalization.NumberStyles]::Number
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if ([decimal]::TryParse(([string]$Value).Trim(), $styles, $culture, [ref]$parsed)) {
        return $parsed
    }

    $null
}

function ConvertTo-PropertyMap {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        $Properties
    )

    $map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $Properties) { return $map }

    if ($Properties -is [System.Collections.IDictionary]) {
        foreach ($key in $Properties.Keys) {
            $map[[string]$key] = $Properties[$key]
        }
    }
    elseif ($Properties -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Properties.PSObject.Properties) {
            $map[$property.Name] = $property.Value
        }
    }

    # parentId and containerName are matching-context aids, not deployable properties.
    [void]$map.Remove('parentId')
    [void]$map.Remove('containerName')
    $map
}

function Test-NormalizedEquality {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        $Left,

        [Parameter()]
        [AllowNull()]
        $Right,

        [ValidateSet('exact', 'caseInsensitive', 'region')]
        [string]$Normalization = 'exact'
    )

    if ($Left -is [string] -and $Right -is [string]) {
        switch ($Normalization) {
            'caseInsensitive' { return [string]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase) }
            'region' { return [string]::Equals(($Left -replace '\s', ''), ($Right -replace '\s', ''), [System.StringComparison]::OrdinalIgnoreCase) }
            default { return [string]::Equals($Left, $Right, [System.StringComparison]::Ordinal) }
        }
    }
    # Keep legacy empty-collection equivalence, without normalizing string values.
    $leftEmpty = Test-EmptyValue -Value $Left
    $rightEmpty = Test-EmptyValue -Value $Right
    if ($leftEmpty -or $rightEmpty) { return ($leftEmpty -and $rightEmpty) }

    $leftIsObject = ($Left -is [System.Collections.IDictionary]) -or ($Left -is [System.Management.Automation.PSCustomObject])
    $rightIsObject = ($Right -is [System.Collections.IDictionary]) -or ($Right -is [System.Management.Automation.PSCustomObject])
    if ($leftIsObject -or $rightIsObject) {
        if (-not ($leftIsObject -and $rightIsObject)) { return $false }

        $leftMap = ConvertTo-PropertyMap -Properties $Left
        $rightMap = ConvertTo-PropertyMap -Properties $Right
        foreach ($key in $leftMap.Keys) {
            if (-not $rightMap.ContainsKey($key)) { return $false }
            if (-not (Test-NormalizedEquality -Left $leftMap[$key] -Right $rightMap[$key])) { return $false }
        }

        return $true
    }

    $leftIsCollection = ($Left -is [System.Collections.IEnumerable]) -and ($Left -isnot [string])
    $rightIsCollection = ($Right -is [System.Collections.IEnumerable]) -and ($Right -isnot [string])
    if ($leftIsCollection -or $rightIsCollection) {
        if (-not ($leftIsCollection -and $rightIsCollection)) { return $false }

        $leftItems = @($Left)
        $rightItems = @($Right)
        if ($leftItems.Count -ne $rightItems.Count) { return $false }
        for ($i = 0; $i -lt $leftItems.Count; $i++) {
            if (-not (Test-NormalizedEquality -Left $leftItems[$i] -Right $rightItems[$i])) { return $false }
        }

        return $true
    }

    $leftBool = ConvertTo-NormalizedBoolean -Value $Left
    $rightBool = ConvertTo-NormalizedBoolean -Value $Right
    if ($null -ne $leftBool -and $null -ne $rightBool) { return $leftBool -eq $rightBool }

    $leftNumber = ConvertTo-NormalizedNumber -Value $Left
    $rightNumber = ConvertTo-NormalizedNumber -Value $Right
    if ($null -ne $leftNumber -and $null -ne $rightNumber) { return $leftNumber -eq $rightNumber }

    [string]::Equals([string]$Left, [string]$Right, [System.StringComparison]::Ordinal)
}

function Get-PropertySeverity {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ResourceType,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $true)]
        [hashtable]$SeverityIndex
    )

    $typeKey = if ($ResourceType) { $ResourceType.Trim().ToLowerInvariant() } else { '' }
    if (-not $SeverityIndex.ContainsKey($typeKey)) { return 'standard' }

    $typeEntry = $SeverityIndex[$typeKey]
    if ($typeEntry.Properties.ContainsKey($PropertyName)) { return $typeEntry.Properties[$PropertyName] }

    $typeEntry.Default
}

try {
    # Severity lookup index from azure-property-paths.json: per-property severity when
    # declared, otherwise the resource-type default, otherwise 'standard'.
    $severityIndex = @{}
    if ($CompareProperties.IsPresent -or $TrackedProperties.IsPresent) {
        $propertyConfigPath = Resolve-Path -Path (Join-Path $PSScriptRoot '../data/azure-property-paths.json') -ErrorAction Stop
        $propertyConfig = Get-Content -LiteralPath $propertyConfigPath -Raw | ConvertFrom-Json

        foreach ($resourceTypeEntry in $propertyConfig.resourceTypes) {
            $typeDefault = 'standard'
            if ($resourceTypeEntry.PSObject.Properties['severity'] -and -not [string]::IsNullOrWhiteSpace([string]$resourceTypeEntry.severity)) {
                $typeDefault = [string]$resourceTypeEntry.severity
            }

            $propertySeverities = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($propertyEntry in $resourceTypeEntry.properties) {
                if ($propertyEntry.PSObject.Properties['severity'] -and -not [string]::IsNullOrWhiteSpace([string]$propertyEntry.severity)) {
                    $propertySeverities[[string]$propertyEntry.name] = [string]$propertyEntry.severity
                }
            }

            $severityIndex[([string]$resourceTypeEntry.resourceType).Trim().ToLowerInvariant()] = @{
                Default    = $typeDefault
                Properties = $propertySeverities
            }
        }
    }

    $baseA = Read-ResourceModel -InputFile $ModelA
    $baseB = Read-ResourceModel -InputFile $ModelB
    if ($CompareProperties -and ($LabelA -eq 'Azure' -or $LabelB -eq 'Azure')) {
        if ($LabelA -eq 'Bicep' -or $LabelB -eq 'Bicep') { $AzureIdentity = [switch]$true }
        $TrackedProperties = [switch]$true
    }
    $resourcesA = if ($baseA.resources) { @($baseA.resources) } else { @() }
    $resourcesB = if ($baseB.resources) { @($baseB.resources) } else { @() }

    $recordsA = @($resourcesA | ForEach-Object { New-ResourceRecord -Resource $_ })
    $recordsB = @($resourcesB | ForEach-Object { New-ResourceRecord -Resource $_ })

    $matchedA = [System.Collections.Generic.HashSet[object]]::new()
    $matchedB = [System.Collections.Generic.HashSet[object]]::new()
    $comparisonMatches = [System.Collections.Generic.List[object]]::new()

    if ($AzureIdentity) {
        $identityIndex = @{}
        foreach ($rb in $recordsB) {
            $id = [string](Get-ModelMember $rb.Resource 'id')
            if ($id.StartsWith('/subscriptions/', [System.StringComparison]::OrdinalIgnoreCase) -and -not (Test-ModelUnresolved $id)) {
                if ($identityIndex.ContainsKey($id)) { throw "Duplicate actual resource ID: $id" }
                $identityIndex[$id] = $rb
            }
        }
        foreach ($ra in $recordsA) {
            $id = [string](Get-ModelMember $ra.Resource 'id')
            if (Test-ModelUnresolved $id) { continue }
            if ($identityIndex.ContainsKey($id)) {
                $rb = $identityIndex[$id]
                if ($matchedB.Contains($rb)) { throw "Duplicate expected resource ID: $id" }
                $existence = [string](Get-ModelMember $rb.Resource 'existence')
                $comparisonMatches.Add(@{
                    status = if ($existence -eq 'Unknown' -or (Get-ModelMember $ra.Resource 'existenceUnknown')) { 'Unverified' } elseif ($existence -eq 'Absent') { "$LabelA Only" } else { 'In Sync' }
                    existence = if ($existence) { $existence } else { 'Found' }
                    resourceA = $ra.Resource; resourceB = $rb.Resource; note = 'Exact ARM identity match'
                })
                [void]$matchedA.Add($ra)
                [void]$matchedB.Add($rb)
            }
        }
    }
    else {
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

    # Group remaining candidates by type only, so Rule 2/3 look up a single bucket per A
    # resource instead of re-filtering both full lists each time.
    $typeGroupA = @{}
    foreach ($ra in $recordsA) {
        $key = "$($ra.Type)"
        if (-not $typeGroupA.ContainsKey($key)) {
            $typeGroupA[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $typeGroupA[$key].Add($ra)
    }

    $typeGroupB = @{}
    foreach ($rb in $recordsB) {
        $key = "$($rb.Type)"
        if (-not $typeGroupB.ContainsKey($key)) {
            $typeGroupB[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $typeGroupB[$key].Add($rb)
    }

    # Rule 2 and 3: Type match with unique count or fuzzy name.
    foreach ($ra in $recordsA) {
        if ($matchedA.Contains($ra)) { continue }

        $key = "$($ra.Type)"
        $groupA = if ($typeGroupA.ContainsKey($key)) { $typeGroupA[$key] } else { @() }
        $groupB = if ($typeGroupB.ContainsKey($key)) { $typeGroupB[$key] } else { @() }
        $unmatchedA = @($groupA | Where-Object { -not $matchedA.Contains($_) })
        $unmatchedB = @($groupB | Where-Object { -not $matchedB.Contains($_) })

        if ($unmatchedA.Count -eq 1 -and $unmatchedB.Count -eq 1) {
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

    }

    # Final unmatched resources.
    foreach ($ra in $recordsA) {
        if ($matchedA.Contains($ra)) { continue }
        $uncertain = $AzureIdentity -and ((Test-ModelUnresolved (Get-ModelMember $ra.Resource 'id')) -or (Get-ModelMember $ra.Resource 'existenceUnknown'))
        $comparisonMatches.Add(@{ status = if ($uncertain) { 'Unresolved' } else { "$LabelA Only" }; existence = if ($uncertain) { 'Unknown' } else { 'Absent' }; resourceA = $ra.Resource; resourceB = $null; note = if ($uncertain) { 'Expected identity or existence cannot be resolved' } else { 'Present only in first model' } })
    }

    foreach ($rb in $recordsB) {
        if ($matchedB.Contains($rb)) { continue }
        $comparisonMatches.Add(@{ status = "$LabelB Only"; resourceA = $null; resourceB = $rb.Resource; note = 'Present only in second model' })
    }

    if ($CompareProperties.IsPresent -or $TrackedProperties.IsPresent) {
        # Model A is the expected state: compare each of its properties against B's value.
        # Keys only present in B are ignored (the expected model did not specify them).
        foreach ($entry in $comparisonMatches) {
            if ($entry.status -ne 'In Sync' -and $entry.status -ne 'In Sync (name differs)') { continue }

            $propertiesA = if ($entry.resourceA.PSObject.Properties['properties']) { $entry.resourceA.properties } else { $null }
            $propertiesB = if ($entry.resourceB.PSObject.Properties['properties']) { $entry.resourceB.properties } else { $null }
            $mapA = ConvertTo-PropertyMap -Properties $propertiesA
            $mapB = ConvertTo-PropertyMap -Properties $propertiesB

            if ($TrackedProperties) {
                $mapA = Get-ComparisonProperty -Resource $entry.resourceA -Configuration $propertyConfig
                $mapB = Get-ComparisonProperty -Resource $entry.resourceB -Configuration $propertyConfig -PropertyName @($mapA.Keys)
            }
            $drifts = [System.Collections.Generic.List[object]]::new()
            $uncertainties = [System.Collections.Generic.List[object]]::new()
            $comparedCount = 0
            foreach ($propertyName in $mapA.Keys) {
                $valueA = $mapA[$propertyName]
                $valueB = if ($mapB.ContainsKey($propertyName)) { $mapB[$propertyName] } else { $null }

                if ((Test-ModelUnresolved $valueA) -or (Test-ModelUnresolved $valueB)) {
                    $uncertainties.Add(@{ property = $propertyName; status = if (Test-ModelUnresolved $valueA) { 'Unresolved' } else { 'Unknown' } })
                    continue
                }
                $comparedCount++
                $normalization = Get-PropertyNormalization -Configuration $propertyConfig -ResourceType $entry.resourceA.type -PropertyName $propertyName
                if (-not (Test-NormalizedEquality -Left $valueA -Right $valueB -Normalization $normalization)) {
                    $drifts.Add(@{
                        property = $propertyName
                        valueA   = $valueA
                        valueB   = $valueB
                        severity = Get-PropertySeverity -ResourceType ([string]$entry.resourceA.type) -PropertyName $propertyName -SeverityIndex $severityIndex
                    })
                }
            }

            $entry.propertyComparison = @{
                status        = if ($uncertainties.Count -gt 0) { 'Incomplete' } elseif ($comparedCount -eq 0) { 'No Comparable Properties' } elseif ($drifts.Count -gt 0) { 'Properties Drifted' } else { 'All Properties Match' }
                comparedCount = $comparedCount
                driftCount    = $drifts.Count
                drifts        = @($drifts)
            }
            $entry.propertyComparison.uncertainties = @($uncertainties)
            $sources = Get-ModelMember $entry.resourceA 'propertySources'
            if ($null -ne $sources) { $entry.propertyComparison.propertySources = $sources }
        }
    }

    $summary = @{
        total          = $comparisonMatches.Count
        inSync         = 0
        inSyncNameDiff = 0
        onlyA          = 0
        onlyB          = 0
        confirmedMatch = 0
        incompleteComparison = 0
        noComparableProperties = 0
        unverified = 0
    }

    foreach ($entry in $comparisonMatches) {
        switch ($entry.status) {
            'In Sync' { $summary.inSync++ }
            'In Sync (name differs)' { $summary.inSyncNameDiff++ }
            "$LabelA Only" { $summary.onlyA++ }
            "$LabelB Only" { $summary.onlyB++ }
        }
        if ($entry.status -in @('Unresolved', 'Unverified')) { $summary.unverified++ }
        elseif ($entry.ContainsKey('propertyComparison')) {
            switch ($entry.propertyComparison.status) {
                'All Properties Match' { $summary.confirmedMatch++ }
                'Incomplete' { $summary.incompleteComparison++; $summary.unverified++ }
                'No Comparable Properties' { $summary.noComparableProperties++ }
            }
        }
    }

    if ($CompareProperties.IsPresent -or $TrackedProperties.IsPresent) {
        $summary.resourcesWithPropertyDrift = 0
        $summary.propertyDriftCount = 0
        foreach ($entry in $comparisonMatches) {
            if ($entry.ContainsKey('propertyComparison') -and $entry.propertyComparison.driftCount -gt 0) {
                $summary.resourcesWithPropertyDrift++
                $summary.propertyDriftCount += $entry.propertyComparison.driftCount
            }
        }
    }

    $report = @{
        labelA  = $LabelA
        labelB  = $LabelB
        summary = $summary
        matches = @($comparisonMatches)
    }

    Write-ResourceModel -Model $report -OutFile $OutFile
}
catch {
    Invoke-Exit -Code 1 -Message "Resource model comparison failed: $($_.Exception.Message)"
}
