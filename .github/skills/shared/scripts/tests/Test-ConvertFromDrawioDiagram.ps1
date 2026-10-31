#Requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSScriptRoot
$fixturePath = Join-Path $PSScriptRoot 'fixtures/diagram-config-metadata.drawio'
$outputDirectory = Join-Path $PSScriptRoot '.test-output'
$modelPath = Join-Path $outputDirectory 'diagram-model.json'
$parserPath = Join-Path $scriptRoot 'ConvertFrom-DrawioDiagram.ps1'

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        $Expected,
        [Parameter(Mandatory = $true)]
        $Actual,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Expected -cne $Actual) {
        throw "$Message (expected '$Expected', got '$Actual')."
    }
}

try {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    & (Get-Command pwsh -ErrorAction Stop).Source -NoProfile -File $parserPath -DiagramPath $fixturePath -OutFile $modelPath
    if ($LASTEXITCODE -ne 0) {
        throw "Diagram parser failed with exit code $LASTEXITCODE."
    }

    $model = Get-Content -LiteralPath $modelPath -Raw | ConvertFrom-Json
    $vmWithAnnotation = $model.resources | Where-Object id -eq 'vm-01'
    $vmWithBaseline = $model.resources | Where-Object id -eq 'vm-02'
    $vmWithoutExpectations = $model.resources | Where-Object id -eq 'vm-03'
    $vmWithWrapperMetadata = $model.resources | Where-Object id -eq 'vm-04'

    Assert-Equal 'Standard_D4s_v5' $vmWithAnnotation.properties.vmSize 'Annotation must override the selected baseline'
    Assert-Equal 'StandardSSD_LRS' $vmWithAnnotation.properties.osDiskType 'Baseline-only properties must be retained'
    Assert-Equal 'Linux' $vmWithAnnotation.properties.osType 'Annotated properties must be included'
    Assert-Equal 'selectedBaseline:development' $vmWithAnnotation.propertySources.osDiskType 'Baseline provenance must be retained'
    Assert-Equal 'annotation' $vmWithAnnotation.propertySources.vmSize 'Annotation provenance must override baseline provenance'
    Assert-Equal $true $vmWithAnnotation.properties.enableBootDiagnostics 'Type-level baseline properties must be applied'
    Assert-Equal 'selectedBaseline:development' $vmWithAnnotation.propertySources.enableBootDiagnostics 'Type-level baseline provenance must be retained'
    Assert-Equal $false $vmWithBaseline.properties.enableBootDiagnostics 'Cell annotations must override a type-level baseline'
    Assert-Equal 'annotation' $vmWithBaseline.propertySources.enableBootDiagnostics 'Cell annotation provenance must be retained'
    Assert-Equal 'rg-test' $vmWithAnnotation.properties.containerName 'Existing containment metadata must be preserved'
    Assert-Equal $false ($null -ne $vmWithoutExpectations.PSObject.Properties['propertySources']) 'Resources without configuration metadata must not gain provenance fields'
    Assert-Equal 0 @($vmWithoutExpectations.properties.PSObject.Properties).Count 'Unconfigured resources must retain their existing empty configuration bag'
    Assert-Equal 'Standard_D4s_v5' $vmWithAnnotation.comparisonProperties.vmSize 'The explicit comparison model must contain annotations'
    Assert-Equal 0 @($vmWithoutExpectations.comparisonProperties.PSObject.Properties).Count 'Unconfigured resources must have no expected comparison properties'
    Assert-Equal 'vm-wrapper' $vmWithWrapperMetadata.name 'A wrapper label must be used when the inner cell has no value'
    Assert-Equal 'vm-04' $vmWithWrapperMetadata.id 'A wrapper ID must be used when the inner cell has no ID'

    $actualPath = Join-Path $outputDirectory 'azure-model.json'
    $comparisonPath = Join-Path $outputDirectory 'comparison.json'
    $actual = @{ resources = @(
        @{ id = 'actual-01'; name = $vmWithAnnotation.name; type = $vmWithAnnotation.type; properties = @{
            hardwareProfile = @{ vmSize = 'Standard_B2s' }
            storageProfile = @{ osDisk = @{ osType = 'Linux'; managedDisk = @{ storageAccountType = 'StandardSSD_LRS' } } }
            diagnosticsProfile = @{ bootDiagnostics = @{ enabled = $true } }
        } },
        @{ id = 'actual-02'; name = $vmWithBaseline.name; type = $vmWithBaseline.type; properties = @{
            diagnosticsProfile = @{ bootDiagnostics = @{ enabled = $false } }
        } },
        @{ id = 'actual-03'; name = $vmWithoutExpectations.name; type = $vmWithoutExpectations.type; properties = @{} }
    ) }
    $actual | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $actualPath -Encoding utf8
    & pwsh -NoProfile -File (Join-Path $scriptRoot 'Compare-ResourceModels.ps1') `
        -ModelA $modelPath -ModelB $actualPath -LabelA Diagram -LabelB Azure -CompareProperties -OutFile $comparisonPath
    if ($LASTEXITCODE -ne 0) { throw 'Diagram deep comparison failed.' }
    $report = Get-Content -LiteralPath $comparisonPath -Raw | ConvertFrom-Json
    $annotatedComparison = @($report.matches | Where-Object { $_.resourceA.id -eq 'vm-01' })[0].propertyComparison
    $unconfiguredComparison = @($report.matches | Where-Object { $_.resourceA.id -eq 'vm-03' })[0].propertyComparison
    Assert-Equal 4 $annotatedComparison.comparedCount 'Deep mode must compare actual annotated and baseline properties'
    Assert-Equal 1 $annotatedComparison.driftCount 'Deep mode must detect the annotated VM size drift'
    Assert-Equal 'annotation' $annotatedComparison.propertySources.vmSize 'Comparison must retain annotation provenance'
    Assert-Equal 'selectedBaseline:development' $annotatedComparison.propertySources.osDiskType 'Comparison must retain baseline provenance'
    Assert-Equal 'No Comparable Properties' $unconfiguredComparison.status 'Existence-only diagrams must not claim configuration agreement'

    $invalidPath = Join-Path $outputDirectory 'invalid.drawio'
    (Get-Content -LiteralPath $fixturePath -Raw).Replace('vmSize', 'unknownTrackedProperty') | Set-Content -LiteralPath $invalidPath -Encoding utf8
    & pwsh -NoProfile -File $parserPath -DiagramPath $invalidPath -OutFile $modelPath 2>$null
    Assert-Equal 1 $LASTEXITCODE 'Unknown property annotations must fail explicitly'

    Write-Output 'PASS ConvertFrom-DrawioDiagram configuration metadata'
}
finally {
    if (Test-Path -LiteralPath $outputDirectory) {
        Remove-Item -LiteralPath $outputDirectory -Recurse -Force
    }
}
