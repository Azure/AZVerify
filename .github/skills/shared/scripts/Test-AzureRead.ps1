#Requires -Version 5.1
<#
.SYNOPSIS
Regression-tests ARM read authentication and response handling without network access.
.DESCRIPTION
Mocks Invoke-WebRequest and Azure CLI responses to verify the outgoing bearer token
header, provider-version fallback, response statuses, and that tokens stay out of
returned data and diagnostics.
.EXAMPLE
pwsh .github/skills/shared/scripts/Test-AzureRead.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_Common.ps1"
. "$PSScriptRoot/_ExpectedAzureDiscovery.ps1"

$script:mockToken = 'mock-arm-token-regression-only'
$script:mockScenario = ''
$script:mockRequests = [System.Collections.Generic.List[object]]::new()

function Assert-Equal {
    param([string]$Name, $Expected, $Actual)
    if ($Expected -ne $Actual) {
        throw "$Name failed. Expected '$Expected', got '$Actual'."
    }
}

function Assert-True {
    param([string]$Name, [bool]$Condition)
    if (-not $Condition) { throw "$Name failed." }
}

function Assert-BearerHeader {
    param([string]$Name, [string]$Header, [string]$Token)
    Assert-True "$Name has bearer prefix" ($Header.StartsWith('Bearer ', [System.StringComparison]::Ordinal))
    Assert-Equal "$Name token" $Token ($Header.Substring(7))
}

function Reset-MockRequests {
    $script:mockRequests.Clear()
}

function Throw-MockHttpError {
    param([int]$StatusCode, [string]$Body)
    $exception = [System.Exception]::new("Mock HTTP $StatusCode")
    $response = [pscustomobject]@{ StatusCode = $StatusCode; Headers = @{} }
    $exception | Add-Member -NotePropertyName Response -NotePropertyValue $response
    $record = [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'MockHttpError',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $null
    )
    if ($Body) { $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Body) }
    throw $record
}

function Invoke-WebRequest {
    param(
        [string]$Uri,
        [string]$Method,
        [hashtable]$Headers,
        [int]$TimeoutSec
    )

    $script:mockRequests.Add([pscustomobject]@{
        Uri = $Uri
        Authorization = [string]$Headers.Authorization
    })

    if ($script:mockScenario -eq 'provider-fallback') {
        if ($Uri -match '/providers/Microsoft\.Storage\?') {
            return [pscustomobject]@{
                Content = '{"resourceTypes":[{"resourceType":"storageAccounts","apiVersions":["2024-01-01","2023-01-01"]}]}'
            }
        }
        if ($Uri -match 'api-version=2019-01-01') {
            Throw-MockHttpError -StatusCode 400 -Body '{"error":{"code":"NoRegisteredProviderFound"}}'
        }
        if ($Uri -match 'api-version=2024-01-01') {
            return [pscustomobject]@{
                Content = '{"id":"/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/sample","type":"Microsoft.Storage/storageAccounts","name":"sample","properties":{"minimumTlsVersion":"TLS1_2"}}'
            }
        }
        throw "Unexpected fallback test URI: $Uri"
    }

    switch ($script:mockScenario) {
        'found' {
            return [pscustomobject]@{ Content = '{"id":"mock-resource","properties":{"value":"ok"}}' }
        }
        'not-found' {
            Throw-MockHttpError -StatusCode 404 -Body '{"error":{"code":"ResourceNotFound"}}'
        }
        'forbidden' {
            Throw-MockHttpError -StatusCode 403 -Body '{"error":{"code":"AuthorizationFailed"}}'
        }
        'throttled' {
            Throw-MockHttpError -StatusCode 429 -Body '{"error":{"code":"TooManyRequests"}}'
        }
        default { throw "Unknown mock scenario '$script:mockScenario'." }
    }
}

function Invoke-AzJson {
    param([string[]]$Arguments)
    $global:LASTEXITCODE = 0
    if ($Arguments[0] -eq 'resource') {
        return [pscustomobject]@{
            id = '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/sample'
            type = 'Microsoft.Storage/storageAccounts'
            name = 'sample'
            tags = @{}
            properties = @{}
        }
    }
    if ($Arguments[0] -eq 'account') {
        return [pscustomobject]@{ accessToken = $script:mockToken }
    }
    throw "Unexpected Azure CLI arguments: $($Arguments -join ' ')"
}

$workDirectory = Join-Path $PSScriptRoot '.azure-read-regression-work'
$expectedPath = Join-Path $workDirectory 'expected-model.json'
$originalError = [Console]::Error
$diagnostics = [System.IO.StringWriter]::new()

try {
    [Console]::SetError($diagnostics)
    New-Item -ItemType Directory -Path $workDirectory -Force | Out-Null

    $cases = @(
        @{ Scenario = 'found'; Status = 'Found' },
        @{ Scenario = 'not-found'; Status = 'Absent' },
        @{ Scenario = 'forbidden'; Status = 'Unavailable' },
        @{ Scenario = 'throttled'; Status = 'Unavailable' }
    )
    foreach ($case in $cases) {
        Reset-MockRequests
        $script:mockScenario = $case.Scenario
        $result = Invoke-ArmRead -Uri 'https://management.azure.com/mock-resource' `
            -Token $script:mockToken -MaxRetry 0
        Assert-Equal "$($case.Scenario) status" $case.Status $result.status
        Assert-Equal "$($case.Scenario) request count" 1 $script:mockRequests.Count
        Assert-BearerHeader "$($case.Scenario) Authorization header" $script:mockRequests[0].Authorization $script:mockToken
    }

    Reset-MockRequests
    $script:mockScenario = 'provider-fallback'
    $expectedModel = @{
        resources = @(
            @{
                id = '/subscriptions/sub/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/sample'
                type = 'Microsoft.Storage/storageAccounts'
                name = 'sample'
                apiVersion = '2019-01-01'
                properties = @{ minimumTlsVersion = 'TLS1_2' }
            }
        )
    }
    $expectedModel | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $expectedPath -Encoding UTF8
    $discovered = Get-ExpectedAzureModel -ExpectedModel $expectedPath -ResourceGroup 'rg' `
        -SubscriptionId 'sub' -ManagementEndpoint 'https://management.azure.com/' `
        -ThrottleLimit 1 -MaxRetry 0 -Mode bicep

    Assert-Equal 'provider fallback request count' 3 $script:mockRequests.Count
    foreach ($request in $script:mockRequests) {
        Assert-BearerHeader 'provider fallback Authorization header' $request.Authorization $script:mockToken
    }
    Assert-True 'provider endpoint requested' ($script:mockRequests[1].Uri -match '/providers/Microsoft\.Storage\?')
    Assert-True 'fallback API version requested' ($script:mockRequests[2].Uri -match 'api-version=2024-01-01')
    Assert-Equal 'fallback discovery status' 'Found' $discovered.resources[0].discoveryStatus

    $serializedResult = $discovered | ConvertTo-Json -Depth 20
    Assert-True 'token omitted from returned data' (-not $serializedResult.Contains($script:mockToken))
    Assert-True 'token omitted from diagnostics' (-not $diagnostics.ToString().Contains($script:mockToken))

    Write-Output 'PASS: Azure read headers, provider-version fallback, status handling, and token redaction.'
}
finally {
    [Console]::SetError($originalError)
    $diagnostics.Dispose()
    if (Test-Path -LiteralPath $workDirectory) {
        Remove-Item -LiteralPath $workDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
