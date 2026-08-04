#Requires -Version 7.0
<#
.SYNOPSIS
Checks whether the current user is authenticated to Azure.
.DESCRIPTION
Attempts to discover an authenticated Azure session using the Az PowerShell module first,
and falls back to Azure CLI if the Az module is unavailable.
The script emits a JSON object describing the authentication state and exits with code 1
when no authenticated session is found (hard gate for skill workflows).
.PARAMETER OutFile
Optional path to write the JSON output. If omitted, output is written to stdout.
.OUTPUTS
System.Management.Automation.PSCustomObject
.NOTES
This script is intended to be used as a deterministic gate for skill workflows.
Exit code 0 = authenticated; exit code 1 = not authenticated.
.EXAMPLE
pwsh Test-AzureAuth.ps1
.EXAMPLE
pwsh Test-AzureAuth.ps1 -OutFile auth.json
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_Common.ps1"

function Get-AzModuleContext {
    [CmdletBinding()]
    param()

    try {
        if (-not (Get-Command -Name Get-AzContext -ErrorAction SilentlyContinue)) {
            return $null
        }

        $context = Get-AzContext -ErrorAction Stop
        if (-not $context) {
            return $null
        }

        return @{
            method           = 'AzPowerShell'
            subscriptionName = $context.Subscription.Name
            subscriptionId   = $context.Subscription.Id
            tenantId         = $context.Tenant.Id
            account          = $context.Account.Id
        }
    }
    catch {
        return $null
    }
}

function Get-AzCliContext {
    [CmdletBinding()]
    param()

    try {
        if (-not (Get-Command -Name az -ErrorAction SilentlyContinue)) {
            return $null
        }

        $azOutput = az account show --output json 2>$null
        if ([string]::IsNullOrWhiteSpace($azOutput)) {
            return $null
        }

        $parsed = $azOutput | ConvertFrom-Json -ErrorAction Stop
        return @{
            method           = 'AzureCLI'
            subscriptionName = $parsed.name
            subscriptionId   = $parsed.id
            tenantId         = $parsed.tenantId
            account          = $parsed.user.name
        }
    }
    catch {
        return $null
    }
}

$authContext = Get-AzModuleContext
if (-not $authContext) {
    $authContext = Get-AzCliContext
}

$result = @{
    authenticated    = $false
    subscriptionName = $null
    subscriptionId   = $null
    tenantId         = $null
    account          = $null
    method           = $null
}

if ($authContext) {
    $result.authenticated    = $true
    $result.subscriptionName = $authContext.subscriptionName
    $result.subscriptionId   = $authContext.subscriptionId
    $result.tenantId         = $authContext.tenantId
    $result.account          = $authContext.account
    $result.method           = $authContext.method
    Write-ResourceModel -Model $result -OutFile $OutFile
    Invoke-Exit -Code 0 -Message 'Azure authentication verified.'
}

Write-Diag 'Azure authentication not found. Please log in with Connect-AzAccount or az login.'
Write-ResourceModel -Model $result -OutFile $OutFile
Invoke-Exit -Code 1 -Message 'Azure authentication check failed.'
