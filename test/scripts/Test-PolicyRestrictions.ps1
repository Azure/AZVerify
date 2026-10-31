#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SubscriptionId,

    [ValidateSet('AzVerify1', 'AzVerify2')]
    [string]$ResourceGroup = 'AzVerify2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$assignmentName = 'azverify-functional-test-allowed-locations'
$assignmentDescription = 'Temporary policy created by AzVerify functional tests.'
$policyId = 'e56962a6-4747-49cd-b67b-bf8b01975c4c'
$templatePath = Join-Path $PSScriptRoot '..\assets\test-storage.bicep'
$groupId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup"
$assignmentCreated = $false
$cleanupSucceeded = $true

function Invoke-AzCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $output = & az @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "az $($Arguments -join ' ') failed (exit $exitCode): $text"
    }

    [pscustomobject]@{
        ExitCode = $exitCode
        Text     = $text
    }
}

try {
    $group = (Invoke-AzCommand -Arguments @(
        'group', 'show', '--name', $ResourceGroup, '--subscription', $SubscriptionId, '--output', 'json'
    )).Text | ConvertFrom-Json

    $existingAssignments = (Invoke-AzCommand -Arguments @(
        'policy', 'assignment', 'list', '--scope', $groupId, '--subscription', $SubscriptionId, '--output', 'json'
    )).Text | ConvertFrom-Json
    $existingAssignment = @($existingAssignments | Where-Object { $_.name -eq $assignmentName })

    if ($existingAssignment.Count -gt 0) {
        if ($existingAssignment[0].description -ne $assignmentDescription) {
            throw "An unrelated policy assignment already uses '$assignmentName'; refusing to modify it."
        }

        Invoke-AzCommand -Arguments @(
            'policy', 'assignment', 'delete', '--name', $assignmentName, '--scope', $groupId, '--subscription', $SubscriptionId
        ) | Out-Null
    }

    $definition = (Invoke-AzCommand -Arguments @(
        'policy', 'definition', 'show', '--name', $policyId, '--subscription', $SubscriptionId, '--output', 'json'
    )).Text | ConvertFrom-Json
    if (-not $definition.parameters.listOfAllowedLocations) {
        throw "Built-in policy '$policyId' does not expose listOfAllowedLocations."
    }

    $parameters = @{
        listOfAllowedLocations = @{ value = @('northeurope') }
        effect = @{ value = 'Deny' }
    } | ConvertTo-Json -Depth 10 -Compress
    $created = (Invoke-AzCommand -Arguments @(
        'policy', 'assignment', 'create',
        '--name', $assignmentName,
        '--scope', $groupId,
        '--policy', $policyId,
        '--params', $parameters,
        '--description', $assignmentDescription,
        '--subscription', $SubscriptionId,
        '--output', 'json'
    )).Text | ConvertFrom-Json
    $assignmentCreated = $true

    $accountName = 'azvpolicytestaccount'
    $resourceContent = @{
        type = 'Microsoft.Storage/storageAccounts'
        name = $accountName
        location = [string]$group.location
        kind = 'StorageV2'
        sku = @{ name = 'Standard_LRS' }
        properties = @{
            minimumTlsVersion = 'TLS1_2'
            supportsHttpsTrafficOnly = $true
        }
    }
    $requestBody = @{
        resourceDetails = @{
            apiVersion = '2023-05-01'
            resourceContent = $resourceContent
        }
    } | ConvertTo-Json -Depth 20 -Compress
    $policyUrl = "$groupId/providers/Microsoft.PolicyInsights/checkPolicyRestrictions?api-version=2022-03-01"
    $policyResponse = (Invoke-AzCommand -Arguments @(
        'rest', '--method', 'POST', '--url', $policyUrl, '--body', $requestBody, '--output', 'json'
    )).Text | ConvertFrom-Json

    $validation = Invoke-AzCommand -Arguments @(
        'deployment', 'group', 'validate',
        '--resource-group', $ResourceGroup,
        '--subscription', $SubscriptionId,
        '--name', 'azverify-policy-probe',
        '--template-file', $templatePath,
        '--parameters', "storageAccountName=$accountName",
        '--output', 'json'
    ) -AllowFailure
    $policyEvaluations = @($policyResponse.contentEvaluationResult.policyEvaluations)
    $evaluationCount = $policyEvaluations.Count
    $restrictionCount = @($policyResponse.fieldRestrictions).Count
    $temporaryAssignmentId = ([string]$created.id).TrimEnd('/')
    $temporaryAssignmentDenialCount = @($policyEvaluations | Where-Object {
        $evaluationResult = $_.PSObject.Properties['evaluationResult']
        $effectDetails = $_.PSObject.Properties['effectDetails']
        $assignmentId = $_.PSObject.Properties['policyAssignmentId']
        $effect = if ($effectDetails) { $effectDetails.Value.PSObject.Properties['effect'] }

        $evaluationResult -and $evaluationResult.Value -ieq 'NonCompliant' -and
        $effect -and $effect.Value -ieq 'deny' -and
        $assignmentId -and ([string]$assignmentId.Value).TrimEnd('/') -ieq $temporaryAssignmentId
    }).Count
    $policyCheckDetectedDenial = $temporaryAssignmentDenialCount -gt 0
    $validationDetectedDenial = $validation.ExitCode -ne 0 -and $validation.Text -match 'RequestDisallowedByPolicy|policy violation'

    [pscustomobject]@{
        resourceGroup = $ResourceGroup
        assignmentName = $created.name
        evaluationCount = $evaluationCount
        fieldRestrictionCount = $restrictionCount
        temporaryAssignmentDenialCount = $temporaryAssignmentDenialCount
        policyCheckDetectedDenial = $policyCheckDetectedDenial
        validationDetectedDenial = $validationDetectedDenial
        validationExitCode = $validation.ExitCode
        passed = $policyCheckDetectedDenial -and $validationDetectedDenial
    } | ConvertTo-Json -Depth 10
}
finally {
    if ($assignmentCreated) {
        $cleanup = Invoke-AzCommand -Arguments @(
            'policy', 'assignment', 'delete',
            '--name', $assignmentName,
            '--scope', $groupId,
            '--subscription', $SubscriptionId
        ) -AllowFailure
        $cleanupSucceeded = $cleanup.ExitCode -eq 0
        if (-not $cleanupSucceeded) {
            [Console]::Error.WriteLine("Failed to remove temporary policy assignment '$assignmentName': $($cleanup.Text)")
        }
    }
}

if (-not $cleanupSucceeded) {
    exit 1
}

if (-not $policyCheckDetectedDenial -or -not $validationDetectedDenial) {
    exit 1
}
