function Invoke-ArmRead {
    <#
    .SYNOPSIS
    Performs a bounded, read-only ARM GET with explicit retry accounting.
    .DESCRIPTION
    Keeps authentication in memory and returns structured absence/unavailability.
    Only throttling and transient server/transport failures are retried.
    .PARAMETER Uri
    Fully scoped ARM GET URI.
    .PARAMETER Token
    ARM access token. Never written to diagnostics or results.
    .PARAMETER MaxRetry
    Maximum retries after the first request.
    .PARAMETER TimeoutSeconds
    Timeout for each request.
    .PARAMETER MaxRetryDelaySeconds
    Maximum permitted retry delay. Longer server delays stop retries.
    .EXAMPLE
    Invoke-ArmRead -Uri $uri -Token $token
    .OUTPUTS
    PSCustomObject with status, data, errorCode, requests, and retries.
    .NOTES
    No mutation verbs are supported.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token,
        [ValidateRange(0, 5)][int]$MaxRetry = 2,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 30,
        [ValidateRange(1, 120)][int]$MaxRetryDelaySeconds = 30
    )

    for ($attempt = 0; $attempt -le $MaxRetry; $attempt++) {
        $statusCode = 0
        $errorCode = 'TransportError'
        $delay = [int][Math]::Pow(2, $attempt)
        try {
            $response = Invoke-WebRequest -Uri $Uri -Method Get -UseBasicParsing `
                -Headers @{ Authorization = "Bearer $Token" } -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            $data = $response.Content | ConvertFrom-Json -ErrorAction Stop
            return [pscustomobject]@{ status = 'Found'; data = $data; errorCode = $null; requests = $attempt + 1; retries = $attempt }
        }
        catch {
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
                $retryAfter = $_.Exception.Response.Headers['Retry-After']
                if ($retryAfter) {
                    $seconds = 0
                    if ([int]::TryParse([string](@($retryAfter)[0]), [ref]$seconds)) { $delay = [Math]::Max(0, $seconds) }
                    else {
                        $date = [datetimeoffset]::MinValue
                        if ([datetimeoffset]::TryParse([string](@($retryAfter)[0]), [ref]$date)) {
                            $delay = [Math]::Max(0, [int][Math]::Ceiling(($date - [datetimeoffset]::UtcNow).TotalSeconds))
                        }
                    }
                }
            }
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                try {
                    $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop
                    if ($errorBody.error.code) { $errorCode = [string]$errorBody.error.code }
                }
                catch { $errorCode = "Http$statusCode" }
            }
            if ($statusCode -eq 404 -and $errorCode -in @('ResourceNotFound', 'ParentResourceNotFound', 'ResourceGroupNotFound')) {
                return [pscustomobject]@{ status = 'Absent'; data = $null; errorCode = $errorCode; requests = $attempt + 1; retries = $attempt }
            }
            $retryable = $statusCode -eq 0 -or $statusCode -eq 429 -or $statusCode -ge 500
            if (-not $retryable -or $attempt -eq $MaxRetry -or $delay -gt $MaxRetryDelaySeconds) {
                return [pscustomobject]@{ status = 'Unavailable'; data = $null; errorCode = $errorCode; requests = $attempt + 1; retries = $attempt }
            }
            Start-Sleep -Seconds $delay
        }
    }
}
