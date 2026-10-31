. "$PSScriptRoot\_ResourceProjection.ps1"
. "$PSScriptRoot\_AzureRead.ps1"

function Get-ExpectedAzureModel {
    <#
    .SYNOPSIS
    Discovers an inventory and reads only expected resources needing verification.
    .DESCRIPTION
    Explicit drift-only path. Legacy discovery, generation fields and failure
    semantics remain in Get-AzureResourceModel.ps1's default path.
    .PARAMETER ExpectedModel
    Filtered expected resource model path.
    .PARAMETER ResourceGroup
    Verified target resource group.
    .PARAMETER SubscriptionId
    Explicit subscription for every request.
    .PARAMETER ManagementEndpoint
    Resource Manager endpoint from the active Azure cloud.
    .PARAMETER ThrottleLimit
    Maximum concurrent detail GETs on PowerShell 7; 5.1 uses serial GETs.
    .PARAMETER MaxRetry
    Maximum transient retries per GET.
    .PARAMETER TimeoutSeconds
    Timeout per GET.
    .PARAMETER Mode
    Existing shared exclusion mode.
    .EXAMPLE
    Get-ExpectedAzureModel -ExpectedModel $path -ResourceGroup rg -SubscriptionId $id
    .OUTPUTS
    Shared resource model with comparisonProperties, issues and request metrics.
    .NOTES
    Tokens and raw responses are never persisted.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ExpectedModel,
        [Parameter(Mandatory)][string]$ResourceGroup,
        [Parameter(Mandatory)][string]$SubscriptionId,
        [string]$ManagementEndpoint = 'https://management.azure.com/',
        [ValidateRange(1, 16)][int]$ThrottleLimit = 4,
        [ValidateRange(0, 5)][int]$MaxRetry = 2,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 30,
        [ValidateSet('diagram', 'bicep')][string]$Mode = 'bicep'
    )

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $config = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\data\azure-property-paths.json') -Raw | ConvertFrom-Json
    $expected = Read-ResourceModel -InputFile $ExpectedModel
    $inventory = @(Invoke-AzJson -Arguments @('resource', 'list', '--resource-group', $ResourceGroup, '--subscription', $SubscriptionId, '--output', 'json'))
    $inventoryModel = @{ resources = @($inventory | ForEach-Object {
        [pscustomobject]@{ id = $_.id; type = $_.type; name = $_.name; resourceGroup = $ResourceGroup; tags = $_.tags; properties = @{}; relationships = @() }
    }) }
    $filterInput = Join-Path (Split-Path -Parent $ExpectedModel) ('inventory-' + [guid]::NewGuid().ToString('N') + '.json')
    $filterOutput = $filterInput + '.filtered'
    try {
        Write-ResourceModel $inventoryModel -OutFile $filterInput
        & (Join-Path $PSScriptRoot 'Select-AzureResources.ps1') -InputFile $filterInput -Mode $Mode -OutFile $filterOutput
        if ($LASTEXITCODE -ne 0) { throw 'Inventory filtering failed.' }
        $filtered = Read-ResourceModel -InputFile $filterOutput
    }
    finally {
        foreach ($path in @($filterInput, $filterOutput)) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
    }
    $actual = @{}
    $rawIndex = @{}
    foreach ($resource in $inventory) { $rawIndex[[string]$resource.id] = $resource }
    foreach ($resource in $filtered.resources) { $actual[[string]$resource.id] = $resource }
    $work = [System.Collections.Generic.List[object]]::new()
    $issues = [System.Collections.Generic.List[object]]::new()
    foreach ($resource in $expected.resources) {
        $id = [string]$resource.id
        if ((Test-ModelUnresolved $id) -or (Get-ModelMember $resource 'existenceUnknown')) { continue }
        $properties = Get-TrackedProperty -Resource $resource -Configuration $config
        if ($actual.ContainsKey($id)) {
            $projected = Get-TrackedProperty -Resource $rawIndex[$id] -Configuration $config -PropertyName @($properties.Keys)
            $actual[$id] | Add-Member -NotePropertyName comparisonProperties -NotePropertyValue $projected
            $missing = @($properties.Keys | Where-Object { Test-ModelUnresolved $projected[$_] })
            if ($missing.Count -eq 0) { continue }
        }
        $version = [string](Get-ModelMember $resource 'apiVersion')
        if (-not $version) {
            $issues.Add(@{ resourceId = $id; errorCode = 'MissingDeclaredApiVersion' })
            continue
        }
        $work.Add([pscustomobject]@{ id = $id; apiVersion = $version; resource = $resource; properties = @($properties.Keys) })
    }
    $requests = 1
    $retries = 0
    $results = @()
    if ($work.Count -gt 0) {
        $tokenDocument = Invoke-AzJson -Arguments @('account', 'get-access-token', '--subscription', $SubscriptionId, '--resource', $ManagementEndpoint, '--output', 'json')
        $token = [string]$tokenDocument.accessToken
        if (-not $token) { throw 'Azure CLI did not return an ARM access token.' }
        $endpoint = $ManagementEndpoint.TrimEnd('/')
        $helperPath = Join-Path $PSScriptRoot '_AzureRead.ps1'
        try {
            if ($PSVersionTable.PSVersion.Major -ge 7 -and $ThrottleLimit -gt 1) {
                $results = @($work | ForEach-Object -Parallel {
                    . $using:helperPath
                    $item = $_
                    $response = Invoke-ArmRead -Uri ("{0}{1}?api-version={2}" -f $using:endpoint, $item.id, $item.apiVersion) `
                        -Token $using:token -MaxRetry $using:MaxRetry -TimeoutSeconds $using:TimeoutSeconds
                    [pscustomobject]@{ item = $item; response = $response }
                } -ThrottleLimit $ThrottleLimit)
            }
            else {
                $results = @(foreach ($item in $work) {
                    [pscustomobject]@{ item = $item; response = (Invoke-ArmRead -Uri ("{0}{1}?api-version={2}" -f $endpoint, $item.id, $item.apiVersion) `
                        -Token $token -MaxRetry $MaxRetry -TimeoutSeconds $TimeoutSeconds) }
                })
            }
            $providerCache = @{}
            foreach ($result in $results) {
                $response = $result.response
                $item = $result.item
                $requests += $response.requests
                $retries += $response.retries
                if ($response.errorCode -in @('NoRegisteredProviderFound', 'InvalidApiVersionParameter', 'UnsupportedApiVersion', 'InvalidResourceType')) {
                    $segments = $item.resource.type -split '/', 2
                    $namespace = $segments[0]
                    if (-not $providerCache.ContainsKey($namespace)) {
                        $providerCache[$namespace] = Invoke-ArmRead -Uri "$endpoint/subscriptions/$SubscriptionId/providers/${namespace}?api-version=2021-04-01" `
                            -Token $token -MaxRetry $MaxRetry -TimeoutSeconds $TimeoutSeconds
                        $requests += $providerCache[$namespace].requests
                        $retries += $providerCache[$namespace].retries
                    }
                    $provider = $providerCache[$namespace]
                    if ($provider.status -eq 'Found') {
                        $types = @($provider.data.resourceTypes | Where-Object { $_.resourceType -eq $segments[1] })
                        if ($types.Count -eq 1) {
                            $versions = @($types[0].apiVersions | Where-Object { $_ -ne $item.apiVersion -and $_ -notmatch 'preview' } | Sort-Object -Descending)
                            if ($versions.Count -gt 0) {
                                $response = Invoke-ArmRead -Uri ("{0}{1}?api-version={2}" -f $endpoint, $item.id, $versions[0]) -Token $token -MaxRetry $MaxRetry -TimeoutSeconds $TimeoutSeconds
                                $requests += $response.requests
                                $retries += $response.retries
                            }
                        }
                    }
                }
                if ($response.status -eq 'Absent') {
                    [void]$actual.Remove($item.id)
                    continue
                }
                $projected = @{}
                if ($response.status -eq 'Found') {
                    if ($response.data.id -ne $item.id) { throw "ARM returned an unexpected resource ID for '$($item.id)'." }
                    $projected = Get-TrackedProperty -Resource $response.data -Configuration $config -PropertyName $item.properties
                }
                else {
                    foreach ($name in $item.properties) { $projected[$name] = 'unknown' }
                    $issues.Add(@{ resourceId = $item.id; errorCode = $response.errorCode })
                }
                if (-not $actual.ContainsKey($item.id)) {
                    $actual[$item.id] = [pscustomobject]@{
                        id = $item.id; type = $item.resource.type; name = $item.resource.name
                        resourceGroup = $ResourceGroup; properties = @{}; tags = @{}; relationships = @()
                    }
                }
                $actual[$item.id] | Add-Member -NotePropertyName comparisonProperties -NotePropertyValue $projected -Force
                $actual[$item.id] | Add-Member -NotePropertyName discoveryStatus -NotePropertyValue $response.status -Force
            }
        }
        finally { $token = $null; $tokenDocument = $null }
    }
    $timer.Stop()
    Write-Diag ("Discovered {0}; retained {1}; detail checks {2}; unavailable {3}." -f $inventory.Count, $actual.Count, $work.Count, $issues.Count)
    return @{
        resources = @($actual.Values)
        issues = @($issues)
        metrics = @{ inventoryRequests = 1; armRequests = $requests; retries = $retries; detailChecks = $work.Count; elapsedMilliseconds = $timer.ElapsedMilliseconds; throttleLimit = $ThrottleLimit }
    }
}
