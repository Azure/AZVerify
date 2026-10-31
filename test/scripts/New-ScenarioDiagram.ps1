#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScenarioPath,

    [Parameter(Mandatory = $true)]
    [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$stencilPath = Join-Path (Split-Path -Path $repoRoot -Parent) '.github/skills/shared/azure-stencil-mapping.json'

if (-not (Test-Path -LiteralPath $ScenarioPath)) {
    throw "Scenario file not found: $ScenarioPath"
}

if (-not (Test-Path -LiteralPath $stencilPath)) {
    throw "Stencil mapping file not found: $stencilPath"
}

$scenario = Get-Content -LiteralPath $ScenarioPath -Raw | ConvertFrom-Json
$stencil = Get-Content -LiteralPath $stencilPath -Raw | ConvertFrom-Json

$resourceMap = @{}
foreach ($entry in $scenario.resources) {
    $resourceMap[$entry.id] = $entry
}

$xml = New-Object System.Xml.XmlDocument
$xml.PreserveWhitespace = $false

$mxFile = $xml.CreateElement('mxfile')
$xml.AppendChild($mxFile) | Out-Null

$diagram = $xml.CreateElement('diagram')
$diagram.SetAttribute('name', 'Architecture Overview')
$diagram.SetAttribute('id', 'overview')
$mxFile.AppendChild($diagram) | Out-Null

$model = $xml.CreateElement('mxGraphModel')
$model.SetAttribute('dx', '0')
$model.SetAttribute('dy', '0')
$model.SetAttribute('grid', '1')
$model.SetAttribute('gridSize', '10')
$model.SetAttribute('guides', '1')
$model.SetAttribute('tooltips', '1')
$model.SetAttribute('connect', '1')
$model.SetAttribute('arrows', '1')
$model.SetAttribute('fold', '1')
$model.SetAttribute('page', '1')
$model.SetAttribute('pageScale', '1')
$model.SetAttribute('pageWidth', '1900')
$model.SetAttribute('pageHeight', '1000')
$model.SetAttribute('math', '0')
$model.SetAttribute('shadow', '0')
$diagram.AppendChild($model) | Out-Null

$root = $xml.CreateElement('root')
$model.AppendChild($root) | Out-Null

foreach ($baseId in @('0', '1')) {
    $baseCell = $xml.CreateElement('mxCell')
    $baseCell.SetAttribute('id', $baseId)
    if ($baseId -eq '1') {
        $baseCell.SetAttribute('parent', '0')
    }

    $root.AppendChild($baseCell) | Out-Null
}

function Get-StyleForContainer([string]$type) {
    switch ($type) {
        'Microsoft.Resources/resourceGroups' {
            return 'container=1;collapsible=0;pointerEvents=0;rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fillColor=#fff2cc;strokeColor=#d6b656;fontSize=14;'
        }
        'Microsoft.Network/virtualNetworks' {
            return 'container=1;collapsible=0;pointerEvents=0;rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fillColor=#dae8fc;strokeColor=#6c8ebf;dashed=1;dashPattern=5 5;fontSize=13;'
        }
        'Microsoft.Network/virtualNetworks/subnets' {
            return 'container=1;collapsible=0;pointerEvents=0;rounded=1;whiteSpace=wrap;html=1;verticalAlign=top;fontStyle=1;fillColor=#e1d5e7;strokeColor=#9673a6;dashed=1;dashPattern=2 2;fontSize=12;'
        }
        default {
            return $null
        }
    }
}

function Get-ImagePath([string]$type) {
    $entry = $stencil.resourceTypes.PSObject.Properties[$type]
    if ($entry -and $entry.Value.imagePath) {
        return [string]$entry.Value.imagePath
    }

    'img/lib/azure2/general/Azure_Resource.svg'
}

$layout = @{
    'rg1' = @{ x = 20; y = 20; w = 910; h = 930 }
    'rg2' = @{ x = 950; y = 20; w = 910; h = 930 }
    'hub' = @{ x = 30; y = 70; w = 840; h = 420 }
    'spoke' = @{ x = 40; y = 520; w = 820; h = 380 }
    'ingress' = @{ x = 20; y = 70; w = 250; h = 150 }
    'appnet' = @{ x = 290; y = 70; w = 260; h = 150 }
    'datanet' = @{ x = 570; y = 70; w = 250; h = 150 }
    'spokenet' = @{ x = 290; y = 70; w = 260; h = 150 }
    'nsg1' = @{ x = 40; y = 245 }
    'route' = @{ x = 120; y = 245 }
    'nic1' = @{ x = 300; y = 90 }
    'vm1' = @{ x = 370; y = 90 }
    'web' = @{ x = 510; y = 540 }
    'plan' = @{ x = 510; y = 460 }
    'identity' = @{ x = 580; y = 460 }
    'storage1' = @{ x = 650; y = 540 }
    'vault' = @{ x = 720; y = 540 }
    'pe' = @{ x = 620; y = 90 }
    'dns' = @{ x = 40; y = 540 }
    'logs' = @{ x = 120; y = 540 }
    'ai' = @{ x = 200; y = 540 }
    'action' = @{ x = 280; y = 540 }
    'nsg2' = @{ x = 40; y = 250 }
    'nic2' = @{ x = 300; y = 90 }
    'vm2' = @{ x = 370; y = 90 }
    'storage2' = @{ x = 460; y = 250 }
}

foreach ($resource in $scenario.resources) {
    $cell = $xml.CreateElement('mxCell')
    $cell.SetAttribute('id', [string]$resource.id)
    $cell.SetAttribute('value', [string]$resource.name)
    $cell.SetAttribute('vertex', '1')
    $cell.SetAttribute('parent', [string]$resource.parent)

    $containerStyle = Get-StyleForContainer -type ([string]$resource.type)
    if ($containerStyle) {
        $cell.SetAttribute('style', $containerStyle)
        $geometryInfo = $layout[[string]$resource.id]
        if (-not $geometryInfo) {
            $geometryInfo = @{ x = 30; y = 30; w = 350; h = 220 }
        }

        $geometry = $xml.CreateElement('mxGeometry')
        $geometry.SetAttribute('x', [string]$geometryInfo.x)
        $geometry.SetAttribute('y', [string]$geometryInfo.y)
        $geometry.SetAttribute('width', [string]$geometryInfo.w)
        $geometry.SetAttribute('height', [string]$geometryInfo.h)
        $geometry.SetAttribute('as', 'geometry')
        $cell.AppendChild($geometry) | Out-Null

        $root.AppendChild($cell) | Out-Null

        $icon = $xml.CreateElement('mxCell')
        $icon.SetAttribute('id', "$($resource.id)-icon")
        $icon.SetAttribute('style', "aspect=fixed;html=1;points=[];align=center;image;resizable=0;image=$(Get-ImagePath -type ([string]$resource.type));")
        $icon.SetAttribute('vertex', '1')
        $icon.SetAttribute('parent', [string]$resource.id)
        $iconGeom = $xml.CreateElement('mxGeometry')
        $iconGeom.SetAttribute('x', '10')
        $iconGeom.SetAttribute('y', '10')
        $iconGeom.SetAttribute('width', '30')
        $iconGeom.SetAttribute('height', '30')
        $iconGeom.SetAttribute('as', 'geometry')
        $icon.AppendChild($iconGeom) | Out-Null
        $root.AppendChild($icon) | Out-Null
        continue
    }

    $cell.SetAttribute('style', "aspect=fixed;html=1;points=[];align=center;image;resizable=0;image=$(Get-ImagePath -type ([string]$resource.type));verticalLabelPosition=bottom;verticalAlign=top;")
    $point = $layout[[string]$resource.id]
    if (-not $point) {
        $point = @{ x = 50; y = 50 }
    }

    $geometry = $xml.CreateElement('mxGeometry')
    $geometry.SetAttribute('x', [string]$point.x)
    $geometry.SetAttribute('y', [string]$point.y)
    $geometry.SetAttribute('width', '50')
    $geometry.SetAttribute('height', '50')
    $geometry.SetAttribute('as', 'geometry')
    $cell.AppendChild($geometry) | Out-Null
    $root.AppendChild($cell) | Out-Null
}

function Get-EdgeStyle([string]$type) {
    switch ($type) {
        'depends' { 'rounded=1;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#999999;strokeWidth=1;dashed=1;endArrow=open;endFill=0;' }
        'secures' { 'rounded=1;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#E81123;strokeWidth=2;endArrow=block;endFill=1;' }
        'peers' { 'rounded=1;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#00A4EF;strokeWidth=2;dashed=1;endArrow=block;endFill=1;' }
        'routes' { 'rounded=1;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#0078D4;strokeWidth=2;endArrow=block;endFill=1;' }
        default { 'rounded=1;orthogonalLoop=1;jettySize=auto;html=1;strokeColor=#0078D4;strokeWidth=2;endArrow=block;endFill=1;' }
    }
}

$edgeIndex = 1
foreach ($edge in $scenario.edges) {
    $edgeCell = $xml.CreateElement('mxCell')
    $edgeCell.SetAttribute('id', "edge-$edgeIndex")
    $edgeCell.SetAttribute('value', [string]$edge.label)
    $edgeCell.SetAttribute('edge', '1')
    $edgeCell.SetAttribute('source', [string]$edge.source)
    $edgeCell.SetAttribute('target', [string]$edge.target)
    $edgeCell.SetAttribute('parent', '1')
    $edgeCell.SetAttribute('style', (Get-EdgeStyle -type ([string]$edge.type)))
    $edgeGeometry = $xml.CreateElement('mxGeometry')
    $edgeGeometry.SetAttribute('relative', '1')
    $edgeGeometry.SetAttribute('as', 'geometry')
    $edgeCell.AppendChild($edgeGeometry) | Out-Null
    $root.AppendChild($edgeCell) | Out-Null
    $edgeIndex++
}

$outDir = Split-Path -Path $OutFile -Parent
if (-not (Test-Path -LiteralPath $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$xml.Save($OutFile)

[pscustomobject]@{
    outFile = (Resolve-Path -Path $OutFile).Path
    resourceCount = @($scenario.resources).Count
    edgeCount = @($scenario.edges).Count
} | ConvertTo-Json -Depth 6
