#Requires -Version 7.0
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Diag {
    <#
    .SYNOPSIS
    Writes a diagnostic message to stderr.
    .PARAMETER Message
    The diagnostic message to write.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    [Console]::Error.WriteLine("[AzVerify] $Message")
}

function Read-ResourceModel {
    <#
    .SYNOPSIS
    Reads a resource model from a JSON file or stdin.
    .PARAMETER InputFile
    Optional path to the resource model JSON file. If omitted, reads from stdin.
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    .EXAMPLE
    Read-ResourceModel -InputFile 'model.json'
    .EXAMPLE
    Get-Content model.json | Read-ResourceModel
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$InputFile
    )

    $content = if ($InputFile) {
        if (-not (Test-Path -LiteralPath $InputFile)) {
            throw "Input file not found: $InputFile"
        }

        Get-Content -LiteralPath $InputFile -Raw -ErrorAction Stop
    }
    else {
        [Console]::In.ReadToEnd()
    }

    if ([string]::IsNullOrWhiteSpace($content)) {
        return @{ resources = @() }
    }

    $content | ConvertFrom-Json
}

function Write-ResourceModel {
    <#
    .SYNOPSIS
    Writes a resource model as JSON to a file or stdout.
    .PARAMETER Model
    The resource model object to serialize.
    .PARAMETER OutFile
    Optional path to write the JSON output. If omitted, writes to stdout.
    .EXAMPLE
    Write-ResourceModel -Model $model -OutFile 'output.json'
    .EXAMPLE
    Write-ResourceModel -Model $model
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Model,

        [Parameter()]
        [string]$OutFile
    )

    $json = $Model | ConvertTo-Json -Depth 100

    if ($OutFile) {
        Set-Content -LiteralPath $OutFile -Value $json -Encoding utf8
    }
    else {
        Write-Output $json
    }
}

function Get-LevenshteinDistance {
    <#
    .SYNOPSIS
    Calculates the Levenshtein edit distance between two strings.
    .PARAMETER Left
    The first string.
    .PARAMETER Right
    The second string.
    .OUTPUTS
    System.Int32
    .EXAMPLE
    Get-LevenshteinDistance -Left 'vnet01' -Right 'vnet-01'
    # Returns 1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Left,

        [Parameter(Mandatory = $true)]
        [string]$Right
    )

    $leftStr = if ($null -eq $Left) { '' } else { [string]$Left }
    $rightStr = if ($null -eq $Right) { '' } else { [string]$Right }

    if ($leftStr.Length -eq 0) { return $rightStr.Length }
    if ($rightStr.Length -eq 0) { return $leftStr.Length }

    $previous = [int[]](0..$rightStr.Length)
    $current = New-Object int[] ($rightStr.Length + 1)

    for ($i = 1; $i -le $leftStr.Length; $i++) {
        $current[0] = $i

        for ($j = 1; $j -le $rightStr.Length; $j++) {
            $cost = if ($leftStr[$i - 1] -eq $rightStr[$j - 1]) { 0 } else { 1 }
            $current[$j] = [Math]::Min(
                [Math]::Min($previous[$j] + 1, $current[$j - 1] + 1),
                $previous[$j - 1] + $cost
            )
        }

        $temp = $previous
        $previous = $current
        $current = $temp
    }

    return $previous[$rightStr.Length]
}

function Invoke-Exit {
    <#
    .SYNOPSIS
    Writes an optional diagnostic message and exits the script with the given code.
    .PARAMETER Code
    The exit code. Use 0 for success, non-zero for failure.
    .PARAMETER Message
    Optional message written to stderr before exiting.
    .EXAMPLE
    Invoke-Exit -Code 0 -Message 'Done.'
    .EXAMPLE
    Invoke-Exit -Code 1 -Message 'Authentication failed.'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Code,

        [Parameter()]
        [string]$Message
    )

    if ($Message) {
        Write-Diag $Message
    }

    exit $Code
}
