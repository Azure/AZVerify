# Common utility functions for AZVerify scripts.
# Some functions are already defined for later use
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Diag {
    # Write a diagnostic message to the error stream, prefixed with "[AzVerify]".
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    [Console]::Error.WriteLine("[AzVerify] $Message")
}

function Read-ResourceModel {
    # Read a resource model from a JSON file or standard input and return it as a PowerShell object.
    [CmdletBinding()]
    param(
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

    return $content | ConvertFrom-Json -Depth 100
}

function Write-ResourceModel {
    # Write a resource model to a JSON file or standard output.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Model,

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
    # Calculate the Levenshtein distance between two strings.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Left,

        [Parameter(Mandatory = $true)]
        [string]$Right
    )

    if ($null -eq $Left) {
        $left = ''
    }
    else {
        $left = [string]$Left
    }

    if ($null -eq $Right) {
        $right = ''
    }
    else {
        $right = [string]$Right
    }

    if ($left.Length -eq 0) { return $right.Length }
    if ($right.Length -eq 0) { return $left.Length }

    $previous = [int[]](0..$right.Length)
    $current = New-Object int[] ($right.Length + 1)

    for ($i = 1; $i -le $left.Length; $i++) {
        $current[0] = $i

        for ($j = 1; $j -le $right.Length; $j++) {
            $cost = if ($left[$i - 1] -eq $right[$j - 1]) { 0 } else { 1 }
            $current[$j] = [Math]::Min(
                [Math]::Min($previous[$j] + 1, $current[$j - 1] + 1),
                $previous[$j - 1] + $cost
            )
        }

        $temp = $previous
        $previous = $current
        $current = $temp
    }

    return $previous[$right.Length]
}

function Invoke-Exit {
    # Exit the script with a given exit code and optional diagnostic message.   
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$Code,

        [string]$Message
    )

    if ($Message) {
        Write-Diag $Message
    }

    exit $Code
}
