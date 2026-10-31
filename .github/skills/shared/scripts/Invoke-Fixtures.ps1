#Requires -Version 5.1
<#
.SYNOPSIS
Smoke-tests the Phase 1 scripts against all example fixtures.
.DESCRIPTION
Runs ConvertFrom-DrawioDiagram, ConvertFrom-BicepTemplate, Select-AzureResources,
and Compare-ResourceModels against each example fixture set in the examples/ directory.
Validates that parsers produce non-empty resource models and that filter+compare
runs without error. Exits with code 1 if any fixture fails.
.OUTPUTS
System.Management.Automation.PSCustomObject — one result object per fixture per test.
.NOTES
Requires az CLI with Bicep support (or standalone bicep CLI) for the Bicep tests.
The examples/ directory must exist relative to the repository root.
.EXAMPLE
pwsh Invoke-Fixtures.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot/_Common.ps1"

$repoRoot    = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\..')
$examplesRoot = Join-Path -Path $repoRoot -ChildPath 'examples'
$scriptRoot  = $PSScriptRoot
# Stay inside the workspace; the agent may lack permissions on the system temp folder.
$workRoot    = Join-Path -Path $repoRoot -ChildPath '.azverify-tmp'
New-Item -ItemType Directory -Path $workRoot -Force | Out-Null

$failures = 0
$results  = New-Object System.Collections.Generic.List[object]

function Add-Result {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Fixture,

        [Parameter(Mandatory = $true)]
        [string]$Test,

        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [Parameter()]
        [string]$Detail
    )

    $results.Add([PSCustomObject]@{
        Fixture = $Fixture
        Test    = $Test
        Passed  = $Passed
        Detail  = $Detail
    })

    if (-not $Passed) {
        Write-Diag "FAIL [$Fixture / $Test]: $Detail"
        $script:failures++
    }
    else {
        Write-Diag "PASS [$Fixture / $Test]$(if ($Detail) { ': ' + $Detail })"
    }
}

$fixtures = Get-ChildItem -LiteralPath $examplesRoot -Directory

foreach ($fixture in $fixtures) {
    $fixtureName = $fixture.Name
    $bicepFile   = Join-Path -Path $fixture.FullName -ChildPath 'main.bicep'
    $paramFile   = Get-ChildItem -LiteralPath $fixture.FullName -Filter '*.bicepparam' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    $drawioFile  = Get-ChildItem -LiteralPath $fixture.FullName -Filter '*.drawio' -File -ErrorAction SilentlyContinue | Select-Object -First 1

    $bicepModelFile  = Join-Path -Path $workRoot -ChildPath "$fixtureName-bicep-model.json"
    $diagramModelFile = Join-Path -Path $workRoot -ChildPath "$fixtureName-diagram-model.json"
    $bicepFilteredFile = Join-Path -Path $workRoot -ChildPath "$fixtureName-bicep-filtered.json"
    $diagramFilteredFile = Join-Path -Path $workRoot -ChildPath "$fixtureName-diagram-filtered.json"
    $compareReportFile = Join-Path -Path $workRoot -ChildPath "$fixtureName-compare-report.json"

    try {
        # --- ConvertFrom-DrawioDiagram ---
        if ($drawioFile) {
            try {
                & (Join-Path -Path $scriptRoot -ChildPath 'ConvertFrom-DrawioDiagram.ps1') `
                    -DiagramPath $drawioFile.FullName `
                    -OutFile $diagramModelFile

                $diagramModel = Read-ResourceModel -InputFile $diagramModelFile
                $diagramCount = @($diagramModel.resources).Count
                if ($diagramCount -gt 0) {
                    Add-Result -Fixture $fixtureName -Test 'DrawioDiagram' -Passed $true -Detail "$diagramCount resource(s)"
                }
                else {
                    Add-Result -Fixture $fixtureName -Test 'DrawioDiagram' -Passed $false -Detail 'Parser returned 0 resources'
                }
            }
            catch {
                Add-Result -Fixture $fixtureName -Test 'DrawioDiagram' -Passed $false -Detail $_.Exception.Message
            }
        }
        else {
            Write-Diag "Skipping DrawioDiagram for '$fixtureName': no .drawio file found."
        }

        # --- ConvertFrom-BicepTemplate ---
        if (Test-Path -LiteralPath $bicepFile) {
            try {
                $bicepArgs = @{
                    BicepFile = $bicepFile
                    Depth     = 'standard'
                    OutFile   = $bicepModelFile
                }
                if ($paramFile) {
                    $bicepArgs['ParamFile'] = $paramFile.FullName
                }
                if ($fixtureName -eq 'arm-module-deterministic-names') {
                    $bicepArgs.ResolveDeterministicNames = $true
                }

                & (Join-Path -Path $scriptRoot -ChildPath 'ConvertFrom-BicepTemplate.ps1') @bicepArgs

                $bicepModel = Read-ResourceModel -InputFile $bicepModelFile
                $bicepCount = @($bicepModel.resources).Count
                $bicepTypes = @($bicepModel.resources | ForEach-Object { $_.type } | Sort-Object -Unique)

                if ($bicepCount -gt 0) {
                    Add-Result -Fixture $fixtureName -Test 'BicepTemplate' -Passed $true -Detail "$bicepCount resource(s), $($bicepTypes.Count) type(s)"
                }
                else {
                    Add-Result -Fixture $fixtureName -Test 'BicepTemplate' -Passed $false -Detail 'Parser returned 0 resources'
                }

                # A raw ARM expression in a name means the evaluator skipped it rather than marking it unresolved.
                $rawExpressionNames = @($bicepModel.resources | Where-Object { ([string]$_.name).StartsWith('[') })
                Add-Result -Fixture $fixtureName -Test 'BicepTemplate-NoRawExpressions' -Passed ($rawExpressionNames.Count -eq 0) `
                    -Detail (@($rawExpressionNames | ForEach-Object { $_.name }) -join ', ')

                $expectedNamesFile = Join-Path -Path $fixture.FullName -ChildPath 'expected-names.json'
                if (Test-Path -LiteralPath $expectedNamesFile) {
                    # Parenthesise so Windows PowerShell 5.1 enumerates the top-level JSON array.
                    $expectedNames = @((Get-Content -LiteralPath $expectedNamesFile -Raw | ConvertFrom-Json) | ForEach-Object { [string]$_ })
                    $actualNames = @($bicepModel.resources |
                            Where-Object { $_.type -ne 'Microsoft.Resources/deployments' } |
                            ForEach-Object { "$($_.type)|$($_.name)" })
                    $nameDifferences = @(Compare-Object -ReferenceObject $expectedNames -DifferenceObject $actualNames -CaseSensitive |
                            ForEach-Object { "$($_.SideIndicator) $($_.InputObject)" })
                    Add-Result -Fixture $fixtureName -Test 'BicepTemplate-ExpectedNames' -Passed ($nameDifferences.Count -eq 0) `
                        -Detail ($nameDifferences -join '; ')
                }
            }
            catch {
                Add-Result -Fixture $fixtureName -Test 'BicepTemplate' -Passed $false -Detail $_.Exception.Message
            }
        }
        else {
            Write-Diag "Skipping BicepTemplate for '$fixtureName': no main.bicep found."
        }

        # --- Select-AzureResources (diagram + bicep) ---
        if (Test-Path -LiteralPath $diagramModelFile) {
            try {
                & (Join-Path -Path $scriptRoot -ChildPath 'Select-AzureResources.ps1') `
                    -InputFile $diagramModelFile `
                    -Mode 'diagram' `
                    -OutFile $diagramFilteredFile

                $filteredDiagram = Read-ResourceModel -InputFile $diagramFilteredFile
                $filteredCount = @($filteredDiagram.resources).Count
                Add-Result -Fixture $fixtureName -Test 'SelectResources-Diagram' -Passed $true -Detail "$filteredCount resource(s) after filtering"
            }
            catch {
                Add-Result -Fixture $fixtureName -Test 'SelectResources-Diagram' -Passed $false -Detail $_.Exception.Message
            }
        }

        if (Test-Path -LiteralPath $bicepModelFile) {
            try {
                & (Join-Path -Path $scriptRoot -ChildPath 'Select-AzureResources.ps1') `
                    -InputFile $bicepModelFile `
                    -Mode 'bicep' `
                    -OutFile $bicepFilteredFile

                $filteredBicep = Read-ResourceModel -InputFile $bicepFilteredFile
                $filteredCount = @($filteredBicep.resources).Count
                Add-Result -Fixture $fixtureName -Test 'SelectResources-Bicep' -Passed $true -Detail "$filteredCount resource(s) after filtering"
            }
            catch {
                Add-Result -Fixture $fixtureName -Test 'SelectResources-Bicep' -Passed $false -Detail $_.Exception.Message
            }
        }

        # --- Compare-ResourceModels (diagram vs bicep) ---
        $canCompare = (Test-Path -LiteralPath $diagramFilteredFile) -and (Test-Path -LiteralPath $bicepFilteredFile)
        if ($canCompare) {
            try {
                & (Join-Path -Path $scriptRoot -ChildPath 'Compare-ResourceModels.ps1') `
                    -ModelA $diagramFilteredFile `
                    -ModelB $bicepFilteredFile `
                    -LabelA 'Diagram' `
                    -LabelB 'Bicep' `
                    -OutFile $compareReportFile

                $report = Get-Content -LiteralPath $compareReportFile -Raw | ConvertFrom-Json
                $summary = $report.summary
                $matchedCount = $summary.inSync + $summary.inSyncNameDiff
                $detail = "InSync=$($summary.inSync) InSyncNameDiff=$($summary.inSyncNameDiff) DiagramOnly=$($summary.onlyA) BicepOnly=$($summary.onlyB)"
                if ($matchedCount -eq 0 -and $summary.total -gt 0) {
                    Add-Result -Fixture $fixtureName -Test 'CompareModels' -Passed $false `
                        -Detail "No resources matched between diagram and bicep models. $detail"
                }
                else {
                    Add-Result -Fixture $fixtureName -Test 'CompareModels' -Passed $true -Detail $detail
                }
            }
            catch {
                Add-Result -Fixture $fixtureName -Test 'CompareModels' -Passed $false -Detail $_.Exception.Message
            }
        }
    }
    finally {
        foreach ($tempFile in @($bicepModelFile, $diagramModelFile, $bicepFilteredFile, $diagramFilteredFile, $compareReportFile)) {
            if (Test-Path -LiteralPath $tempFile) {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

$regressionTests = @(
    (Join-Path $scriptRoot 'Test-AzureRead.ps1'),
    (Join-Path $scriptRoot 'tests/Test-ConvertFromDrawioDiagram.ps1'),
    (Join-Path $repoRoot 'tests/Test-ArmCaseAndModuleNames.ps1'),
    (Join-Path $repoRoot 'tests/Test-AzureDriftPipeline.ps1')
)
foreach ($testFile in $regressionTests) {
    try {
        & pwsh -NoProfile -File $testFile | ForEach-Object { Write-Diag ([string]$_) }
        if ($LASTEXITCODE -ne 0) { throw "Regression script exited with code $LASTEXITCODE." }
        Add-Result -Fixture 'regressions' -Test ([System.IO.Path]::GetFileNameWithoutExtension($testFile)) -Passed $true
    }
    catch {
        Add-Result -Fixture 'regressions' -Test ([System.IO.Path]::GetFileNameWithoutExtension($testFile)) -Passed $false -Detail $_.Exception.Message
    }
}

if (-not (Get-ChildItem -LiteralPath $workRoot -Force)) {
    Remove-Item -LiteralPath $workRoot -Force -ErrorAction SilentlyContinue
}

$results | ConvertTo-Json -Depth 10 | Write-Output

if ($failures -gt 0) {
    Invoke-Exit -Code 1 -Message "$failures fixture test(s) failed."
}

Invoke-Exit -Code 0 -Message "All fixture tests passed ($($results.Count) checks)."
