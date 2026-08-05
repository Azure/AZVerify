#Requires -Version 5.1
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

$authContext = $null

try {
    $context = Get-AzContext -ErrorAction Stop
    if ($context) {
        $authContext = @{
            method           = 'AzPowerShell'
            subscriptionName = $context.Subscription.Name
            subscriptionId   = $context.Subscription.Id
            tenantId         = $context.Tenant.Id
            account          = $context.Account.Id
        }
    }
}
catch {
    Write-Verbose "Az PowerShell context unavailable: $_"
}

if (-not $authContext) {
    try {
        $azOutput = az account show --output json 2>$null
        if (-not [string]::IsNullOrWhiteSpace($azOutput)) {
            $parsed = $azOutput | ConvertFrom-Json -ErrorAction Stop
            $authContext = @{
                method           = 'AzureCLI'
                subscriptionName = $parsed.name
                subscriptionId   = $parsed.id
                tenantId         = $parsed.tenantId
                account          = $parsed.user.name
            }
        }
    }
    catch {
        Write-Verbose "Azure CLI context unavailable: $_"
    }
}

$result = @{
    authenticated    = [bool]$authContext
    subscriptionName = if ($authContext) { $authContext.subscriptionName } else { $null }
    subscriptionId   = if ($authContext) { $authContext.subscriptionId } else { $null }
    tenantId         = if ($authContext) { $authContext.tenantId } else { $null }
    account          = if ($authContext) { $authContext.account } else { $null }
    method           = if ($authContext) { $authContext.method } else { $null }
}

Write-ResourceModel -Model $result -OutFile $OutFile

if ($authContext) {
    Invoke-Exit -Code 0 -Message 'Azure authentication verified.'
}
else {
    Write-Diag 'Azure authentication not found. Please log in with Connect-AzAccount or az login.'
    Invoke-Exit -Code 1 -Message 'Azure authentication check failed.'
}
