#Requires -Version 7.0
<#
.SYNOPSIS
Filters an Azure resource model for diagram or Bicep use.
.DESCRIPTION
Reads a resource model JSON object, applies centralized exclusion rules from
shared/data/resource-filter-rules.json, and emits a filtered resource model.
Tag-based rules (hidden-* and hidden-related:* prefixes) are also applied.
.PARAMETER Mode
Choose 'diagram' to filter for architecture diagrams or 'bicep' to filter for Bicep deployments.
Defaults to 'diagram'.
.PARAMETER InputFile
Optional path to the resource model JSON file. If omitted, the script reads JSON from stdin.
.PARAMETER OutFile
Optional path to write the filtered JSON model. If omitted, output is written to stdout.
.PARAMETER ExtraExclude
Optional type or name patterns (wildcards supported) to exclude in addition to the built-in rules.
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
The script uses shared data from shared/data/resource-filter-rules.json.
.EXAMPLE
pwsh Select-AzureResources.ps1 -InputFile model.json -Mode diagram
.EXAMPLE
pwsh Select-AzureResources.ps1 -InputFile model.json -Mode bicep -ExtraExclude 'Microsoft.Insights/*' -OutFile filtered.json
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('diagram', 'bicep')]
    [string]$Mode = 'diagram',

    [Parameter()]
    [string]$InputFile,

    [Parameter()]
    [string]$OutFile,

    [Parameter()]
    [string[]]$ExtraExclude
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_Common.ps1"

$rulePath = Join-Path $PSScriptRoot '..\data\resource-filter-rules.json'
$rulePath = Resolve-Path -Path $rulePath -ErrorAction Stop
$ruleDocument = Get-Content -LiteralPath $rulePath -Raw | ConvertFrom-Json -Depth 100
$rules = $ruleDocument.rules

$script:RegexCache = @{}

function Convert-WildcardToRegex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $regex = $script:RegexCache[$Pattern]
    if ($null -ne $regex) { return $regex }

    $escaped = [regex]::Escape($Pattern)
    $regexText = '^' + $escaped.Replace('\*', '.*') + '$'
    $regex = [regex]::new($regexText, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $script:RegexCache[$Pattern] = $regex
    $regex
}

function Test-PatternMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Pattern) -or [string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }
    $regex = Convert-WildcardToRegex -Pattern $Pattern
    $regex.IsMatch($Value)
}

function Test-RuleMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceType,

        [Parameter(Mandatory = $true)]
        [string]$RuleType
    )

    if ($RuleType -eq 'Diagnostic settings (child resources)') {
        return $ResourceType -match '(?i)diagnosticsettings'
    }

    Test-PatternMatch -Pattern $RuleType.Trim() -Value $ResourceType
}

function Get-TagKeys {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Tags
    )

    if ($null -eq $Tags) { return @() }
    if ($Tags -is [System.Collections.IDictionary]) {
        return @($Tags.Keys)
    }
    if ($Tags -is [System.Management.Automation.PSCustomObject]) {
        $names = foreach ($property in $Tags.PSObject.Properties) { $property.Name }
        return @($names)
    }
    @()
}

function Test-AllTagsHidden {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$TagKeys
    )

    if (-not $TagKeys -or $TagKeys.Count -eq 0) { return $false }
    foreach ($key in $TagKeys) {
        if (-not $key.StartsWith('hidden-', [System.StringComparison]::InvariantCultureIgnoreCase)) {
            return $false
        }
    }
    $true
}

function Test-HiddenRelatedTag {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$TagKeys
    )

    if (-not $TagKeys) { return $false }
    foreach ($key in $TagKeys) {
        if ($key.StartsWith('hidden-related:', [System.StringComparison]::InvariantCultureIgnoreCase)) {
            return $true
        }
    }
    $false
}

function Test-ExtraExcludeMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Resource,

        [Parameter()]
        [string[]]$Patterns
    )

    if (-not $Patterns) {
        return $false
    }

    foreach ($pattern in $Patterns) {
        if (Test-PatternMatch -Pattern $pattern -Value $Resource.type) {
            return $true
        }

        if (Test-PatternMatch -Pattern $pattern -Value $Resource.name) {
            return $true
        }
    }
    $false
}

$model = Read-ResourceModel -InputFile $InputFile
$resources = [System.Collections.Generic.List[object]]::new()
$excludedCount = 0

foreach ($resource in $model.resources) {
    $shouldExclude = $false
    $resourceType = $resource.type
    $tagKeys = Get-TagKeys -Tags $resource.tags

    if (Test-AllTagsHidden -TagKeys $tagKeys) {
        $shouldExclude = $true
        Write-Diag "Excluding resource '$($resource.name)' because all tags start with hidden-."
    }

    if ((-not $shouldExclude) -and (Test-HiddenRelatedTag -TagKeys $tagKeys)) {
        if ($Mode -eq 'diagram') {
            $shouldExclude = $true
            Write-Diag "Excluding resource '$($resource.name)' from diagram because it has hidden-related:* tags."
        }
    }

    foreach ($rule in $rules) {
        if ($shouldExclude) { break }
        if (-not (Test-RuleMatch -ResourceType $resourceType -RuleType $rule.resourceType)) {
            continue
        }

        $excludeForMode = if ($Mode -eq 'diagram') { $rule.excludeForDiagram } else { $rule.excludeForBicep }
        if ($excludeForMode -is [System.Boolean] -and $excludeForMode) {
            $shouldExclude = $true
            Write-Diag "Excluding resource '$($resource.name)' due to rule '$($rule.resourceType)'."
            break
        }
    }

    if ((-not $shouldExclude) -and (Test-ExtraExcludeMatch -Resource $resource -Patterns $ExtraExclude)) {
        $shouldExclude = $true
        Write-Diag "Excluding resource '$($resource.name)' because it matched an extra exclusion pattern."
    }

    if ($shouldExclude) {
        $excludedCount++
        continue
    }

    $resources.Add($resource)
}

Write-Diag "Filtered $excludedCount resource(s); returning $($resources.Count) resource(s)."
Write-ResourceModel -Model @{ resources = $resources } -OutFile $OutFile
