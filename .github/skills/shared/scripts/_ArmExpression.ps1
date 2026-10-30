# ARM template expression evaluator used by ConvertFrom-BicepTemplate.ps1.
# Evaluates compiled Bicep (ARM JSON) offline: parameters, variables, user-defined and
# imported functions (__bicep.*, _1.*), copy loops, module scopes and module outputs.
# Values that cannot be known offline evaluate to an [ArmUnresolved] marker.
# Internal helpers use simple functions (no CmdletBinding) because they are called
# hundreds of thousands of times while expanding imported naming functions.

class ArmUnresolved {
    [string]$Reason
    ArmUnresolved([string]$reason) { $this.Reason = $reason }
    [string] ToString() { return "<unresolved: $($this.Reason)>" }
}

class ArmExpressionParser {
    [string]$Text
    [int]$Position

    ArmExpressionParser([string]$text) {
        $this.Text = $text
        $this.Position = 0
    }

    [bool] AtEnd() { return $this.Position -ge $this.Text.Length }

    [char] Peek() {
        if ($this.AtEnd()) { return [char]0 }
        return $this.Text[$this.Position]
    }

    [void] SkipWhitespace() {
        while (-not $this.AtEnd() -and [char]::IsWhiteSpace($this.Text[$this.Position])) { $this.Position++ }
    }

    [void] Expect([char]$expected) {
        $this.SkipWhitespace()
        if ($this.Peek() -ne $expected) {
            throw "Expected '$expected' at position $($this.Position) in: $($this.Text)"
        }
        $this.Position++
    }

    [bool] IsIdentifierChar([char]$c) {
        return [char]::IsLetterOrDigit($c) -or $c -eq '_' -or $c -eq '$'
    }

    [hashtable] ParseExpression() {
        $this.SkipWhitespace()
        if ($this.AtEnd()) { throw "Unexpected end of expression: $($this.Text)" }

        $c = $this.Peek()
        $node = $null

        if ($c -eq "'") {
            $this.Position++
            $builder = New-Object System.Text.StringBuilder
            while ($true) {
                if ($this.AtEnd()) { throw "Unterminated string in: $($this.Text)" }
                $ch = $this.Text[$this.Position]
                if ($ch -eq "'") {
                    if ($this.Position + 1 -lt $this.Text.Length -and $this.Text[$this.Position + 1] -eq "'") {
                        [void]$builder.Append("'")
                        $this.Position += 2
                        continue
                    }
                    $this.Position++
                    break
                }
                [void]$builder.Append($ch)
                $this.Position++
            }
            $node = @{ Kind = 'literal'; Value = $builder.ToString() }
        }
        elseif ([char]::IsDigit($c) -or ($c -eq '-' -and $this.Position + 1 -lt $this.Text.Length -and [char]::IsDigit($this.Text[$this.Position + 1]))) {
            $start = $this.Position
            $this.Position++
            while (-not $this.AtEnd() -and ([char]::IsDigit($this.Text[$this.Position]) -or $this.Text[$this.Position] -eq '.')) { $this.Position++ }
            $token = $this.Text.Substring($start, $this.Position - $start)
            if ($token.Contains('.')) {
                $node = @{ Kind = 'literal'; Value = [double]::Parse($token, [System.Globalization.CultureInfo]::InvariantCulture) }
            }
            else {
                $node = @{ Kind = 'literal'; Value = [long]$token }
            }
        }
        else {
            $start = $this.Position
            while (-not $this.AtEnd() -and ($this.IsIdentifierChar($this.Text[$this.Position]) -or $this.Text[$this.Position] -eq '.')) { $this.Position++ }
            $identifier = $this.Text.Substring($start, $this.Position - $start)
            if ($identifier -eq '') { throw "Unexpected character '$c' at position $($this.Position) in: $($this.Text)" }

            $this.SkipWhitespace()
            if ($this.Peek() -eq '(') {
                $this.Position++
                $arguments = New-Object System.Collections.Generic.List[object]
                while ($true) {
                    $this.SkipWhitespace()
                    if ($this.Peek() -eq ')') { $this.Position++; break }
                    $arguments.Add($this.ParseExpression())
                    $this.SkipWhitespace()
                    if ($this.Peek() -eq ',') { $this.Position++ }
                    elseif ($this.Peek() -ne ')') { throw "Expected ',' or ')' at position $($this.Position) in: $($this.Text)" }
                }
                $node = @{ Kind = 'call'; Name = $identifier; Arguments = $arguments.ToArray() }
            }
            else {
                switch ($identifier) {
                    'true' { $node = @{ Kind = 'literal'; Value = $true } }
                    'false' { $node = @{ Kind = 'literal'; Value = $false } }
                    'null' { $node = @{ Kind = 'literal'; Value = $null } }
                    default { throw "Unexpected identifier '$identifier' in: $($this.Text)" }
                }
            }
        }

        while ($true) {
            $this.SkipWhitespace()
            if ($this.AtEnd()) { break }
            $c = $this.Peek()
            if ($c -eq '.') {
                $this.Position++
                $start = $this.Position
                while (-not $this.AtEnd() -and $this.IsIdentifierChar($this.Text[$this.Position])) { $this.Position++ }
                $node = @{ Kind = 'property'; Target = $node; Name = $this.Text.Substring($start, $this.Position - $start) }
            }
            elseif ($c -eq '[') {
                $this.Position++
                $index = $this.ParseExpression()
                $this.Expect(']')
                $node = @{ Kind = 'index'; Target = $node; Index = $index }
            }
            else { break }
        }

        return $node
    }
}

$script:ArmAstCache = @{}
$script:ArmDeploymentOutputCache = @{}

function Get-ArmExpressionAst {
    param([string]$Expression)

    if (-not $script:ArmAstCache.ContainsKey($Expression)) {
        $parser = [ArmExpressionParser]::new($Expression)
        $ast = $parser.ParseExpression()
        $parser.SkipWhitespace()
        if (-not $parser.AtEnd()) { throw "Unexpected trailing text at position $($parser.Position) in: $Expression" }
        $script:ArmAstCache[$Expression] = $ast
    }

    $script:ArmAstCache[$Expression]
}

function ConvertTo-ArmObject {
    # ConvertFrom-Json -AsHashtable is PowerShell 7 only; this keeps Windows PowerShell 5.1 working.
    param($Value)

    if ($null -eq $Value) { return $null }

    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-ArmObject $property.Value
        }
        return , $result
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $result[[string]$key] = ConvertTo-ArmObject $Value[$key]
        }
        return , $result
    }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) { $items.Add((ConvertTo-ArmObject $item)) }
        return , $items.ToArray()
    }

    $Value
}

function Find-ArmKey {
    param($Dictionary, [string]$Key)

    if ($Dictionary -isnot [System.Collections.IDictionary]) { return $null }
    if ($Dictionary.Contains($Key)) { return $Key }
    foreach ($candidate in $Dictionary.Keys) {
        if ([string]::Equals([string]$candidate, $Key, [System.StringComparison]::OrdinalIgnoreCase)) { return $candidate }
    }
    $null
}

function Test-ArmList {
    param($Value)
    ($Value -is [System.Collections.IList]) -and ($Value -isnot [string])
}

function ConvertTo-ArmString {
    param($Value)

    if ($null -eq $Value) { return '' }
    if ($Value -is [bool]) { if ($Value) { return 'True' } else { return 'False' } }
    if ($Value -is [System.Collections.IDictionary] -or (Test-ArmList $Value)) {
        return (ConvertTo-Json -InputObject $Value -Depth 30 -Compress)
    }
    [string]$Value
}

function Test-ArmEqual {
    param($Left, $Right)

    if ($null -eq $Left -and $null -eq $Right) { return $true }
    if ($null -eq $Left -or $null -eq $Right) { return $false }
    if ($Left -is [string] -and $Right -is [string]) {
        return [string]::Equals($Left, $Right, [System.StringComparison]::OrdinalIgnoreCase)
    }
    if ($Left -is [System.ValueType] -and $Right -is [System.ValueType] -and $Left -isnot [bool] -and $Right -isnot [bool]) {
        return [double]$Left -eq [double]$Right
    }
    (ConvertTo-Json -InputObject $Left -Depth 30 -Compress) -eq (ConvertTo-Json -InputObject $Right -Depth 30 -Compress)
}

function Test-ArmEmpty {
    param($Value)

    if ($null -eq $Value) { return $true }
    if ($Value -is [string]) { return $Value.Length -eq 0 }
    if ($Value -is [System.Collections.ICollection]) { return $Value.Count -eq 0 }
    $false
}

function Get-ArmCount {
    param($Value)

    if ($null -eq $Value) { return 0 }
    if ($Value -is [string]) { return $Value.Length }
    if ($Value -is [System.Collections.ICollection]) { return $Value.Count }
    1
}

function Merge-ArmObject {
    param($Left, $Right)

    $result = [ordered]@{}
    foreach ($key in $Left.Keys) { $result[$key] = $Left[$key] }
    foreach ($key in $Right.Keys) {
        $existingKey = Find-ArmKey $result $key
        if ($null -ne $existingKey -and $result[$existingKey] -is [System.Collections.IDictionary] -and $Right[$key] -is [System.Collections.IDictionary]) {
            $result[$existingKey] = Merge-ArmObject $result[$existingKey] $Right[$key]
        }
        elseif ($null -ne $existingKey) { $result[$existingKey] = $Right[$key] }
        else { $result[$key] = $Right[$key] }
    }
    , $result
}

function New-ArmResourceId {
    param([string]$Prefix, [string]$Type, [object[]]$Names)

    $typeSegments = $Type.Split('/')
    $id = "$Prefix/providers/$($typeSegments[0])"
    for ($i = 1; $i -lt $typeSegments.Count; $i++) {
        $segmentName = if ($i - 1 -lt $Names.Count) { $Names[$i - 1] } else { '' }
        $id += "/$($typeSegments[$i])/$segmentName"
    }
    $id
}

function Copy-ArmScope {
    param([hashtable]$Scope)

    $copy = $Scope.Clone()
    $copy.CopyIndex = $Scope.CopyIndex.Clone()
    $copy.Locals = $Scope.Locals.Clone()
    $copy
}

function Get-ArmFunctionTable {
    param($Template)

    $table = @{}
    if ($Template -isnot [System.Collections.IDictionary] -or -not $Template.Contains('functions')) { return $table }
    foreach ($namespace in @($Template['functions'])) {
        if ($null -eq $namespace -or -not $namespace.Contains('members')) { continue }
        foreach ($member in $namespace['members'].Keys) {
            $table["$($namespace['namespace']).$member"] = $namespace['members'][$member]
        }
    }
    $table
}

function Get-ArmSymbolTable {
    param($Template)

    $symbols = [ordered]@{}
    if ($Template -isnot [System.Collections.IDictionary] -or -not $Template.Contains('resources')) { return , $symbols }
    $resources = $Template['resources']
    if ($resources -is [System.Collections.IDictionary]) {
        foreach ($key in $resources.Keys) { $symbols[[string]$key] = $resources[$key] }
    }
    else {
        $index = 0
        foreach ($resource in @($resources)) {
            if ($null -ne $resource) { $symbols["resource$index"] = $resource }
            $index++
        }
    }
    , $symbols
}

function New-ArmScope {
    param(
        $Template,
        [string]$SubscriptionId,
        [string]$ResourceGroupName,
        $Location,
        [string]$Path,
        [string]$DeploymentName,
        [string]$SourceFile
    )

    $variables = if ($Template.Contains('variables') -and $Template['variables'] -is [System.Collections.IDictionary]) { $Template['variables'] } else { [ordered]@{} }
    $scope = @{
        Template          = $Template
        Params            = @{}
        Vars              = $variables
        VarCache          = @{}
        Functions         = (Get-ArmFunctionTable $Template)
        Symbols           = (Get-ArmSymbolTable $Template)
        SubscriptionId    = $SubscriptionId
        ResourceGroupName = $ResourceGroupName
        Location          = $Location
        Path              = $Path
        DeploymentName    = $DeploymentName
        SourceFile        = $SourceFile
        Locals            = @{}
        CopyIndex         = @{}
        ConditionUnknown  = $false
    }
    $scope.Root = $scope
    $scope
}

function Set-ArmScopeParameters {
    # Supplied values win; defaults are evaluated afterwards because they may reference other parameters.
    param([hashtable]$Scope, [System.Collections.IDictionary]$Supplied)

    $template = $Scope.Template
    if (-not $template.Contains('parameters') -or $null -eq $template['parameters']) { return }

    $pending = New-Object System.Collections.Generic.List[string]
    foreach ($name in $template['parameters'].Keys) {
        $definition = $template['parameters'][$name]
        $suppliedKey = Find-ArmKey $Supplied $name
        if ($null -ne $suppliedKey) {
            $Scope.Params[$name] = $Supplied[$suppliedKey]
        }
        elseif ($definition -is [System.Collections.IDictionary] -and $definition.Contains('defaultValue')) {
            $pending.Add($name)
        }
        elseif ($definition -is [System.Collections.IDictionary] -and $definition.Contains('nullable') -and $definition['nullable']) {
            $Scope.Params[$name] = $null
        }
        else {
            $Scope.Params[$name] = [ArmUnresolved]::new("parameter $name has no value")
        }
    }

    foreach ($name in $pending) {
        $Scope.Params[$name] = Resolve-ArmValue $template['parameters'][$name]['defaultValue'] $Scope
    }
}

function New-ArmChildScope {
    param([hashtable]$Scope, $Definition, $DeploymentName)

    $properties = $Definition['properties']
    $subscriptionId = $Scope.SubscriptionId
    $resourceGroupName = $Scope.ResourceGroupName
    if ($Definition.Contains('subscriptionId')) {
        $value = Resolve-ArmValue $Definition['subscriptionId'] $Scope
        $subscriptionId = ConvertTo-ArmString $value
    }
    if ($Definition.Contains('resourceGroup')) {
        $value = Resolve-ArmValue $Definition['resourceGroup'] $Scope
        $resourceGroupName = ConvertTo-ArmString $value
    }

    $child = New-ArmScope -Template $properties['template'] -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName `
        -Location $Scope.Location -Path "$($Scope.Path)/$DeploymentName" -DeploymentName ([string]$DeploymentName) -SourceFile $Scope.SourceFile
    $child.ConditionUnknown = $Scope.ConditionUnknown

    # Bicep modules use inner expression scope: parameter values are evaluated in the parent scope.
    $supplied = [ordered]@{}
    if ($properties.Contains('parameters') -and $properties['parameters'] -is [System.Collections.IDictionary]) {
        foreach ($name in $properties['parameters'].Keys) {
            $entry = $properties['parameters'][$name]
            if ($entry -is [System.Collections.IDictionary] -and $entry.Contains('reference')) {
                $supplied[$name] = [ArmUnresolved]::new("key vault reference for parameter $name")
            }
            elseif ($entry -is [System.Collections.IDictionary] -and $entry.Contains('value')) {
                $supplied[$name] = Resolve-ArmValue $entry['value'] $Scope
            }
        }
    }
    Set-ArmScopeParameters -Scope $child -Supplied $supplied
    $child
}

function Get-ArmVariable {
    param([hashtable]$Scope, [string]$Name)

    $root = $Scope.Root
    if ($root.VarCache.ContainsKey($Name)) { return , $root.VarCache[$Name] }

    $key = Find-ArmKey $root.Vars $Name
    $value = $null
    if ($null -ne $key -and $key -ne 'copy') {
        $value = Resolve-ArmValue $root.Vars[$key] $root
    }
    elseif ($root.Vars.Contains('copy')) {
        $entry = @($root.Vars['copy'] | Where-Object { $_['name'] -eq $Name }) | Select-Object -First 1
        if ($null -ne $entry) {
            $count = Resolve-ArmValue $entry['count'] $root
            if ($count -is [ArmUnresolved]) { $value = $count }
            else {
                $items = New-Object System.Collections.Generic.List[object]
                for ($i = 0; $i -lt [int]$count; $i++) {
                    $iterationScope = Copy-ArmScope $root
                    $iterationScope.CopyIndex[$Name] = $i
                    $items.Add((Resolve-ArmValue $entry['input'] $iterationScope))
                }
                $value = $items.ToArray()
            }
        }
        else { $value = [ArmUnresolved]::new("variable $Name") }
    }
    else { $value = [ArmUnresolved]::new("variable $Name") }

    $root.VarCache[$Name] = $value
    , $value
}

function Get-ArmDeploymentOutputs {
    param([hashtable]$Scope, [string]$Symbol)

    $cacheKey = "$($Scope.Path)|$Symbol"
    if ($script:ArmDeploymentOutputCache.ContainsKey($cacheKey)) { return , $script:ArmDeploymentOutputCache[$cacheKey] }

    $definition = $Scope.Symbols[$Symbol]
    if ($definition.Contains('copy')) { return [ArmUnresolved]::new("reference to looped module $Symbol") }

    $deploymentName = Resolve-ArmValue $definition['name'] $Scope
    $child = New-ArmChildScope -Scope $Scope -Definition $definition -DeploymentName $deploymentName
    $outputs = [ordered]@{}
    $template = $child.Template
    if ($template.Contains('outputs') -and $template['outputs'] -is [System.Collections.IDictionary]) {
        foreach ($name in $template['outputs'].Keys) {
            $outputs[$name] = [ordered]@{ value = (Resolve-ArmValue $template['outputs'][$name]['value'] $child) }
        }
    }
    $result = [ordered]@{ outputs = $outputs }
    $script:ArmDeploymentOutputCache[$cacheKey] = $result
    , $result
}

function Get-ArmResourceId {
    param([hashtable]$Scope, $Definition, $Name)

    if ($Name -is [ArmUnresolved]) { return $null }
    $names = ([string]$Name).Split('/')

    if ($Definition.Contains('scope') -and $Definition['scope']) {
        $scopeValue = $Definition['scope']
        $scopeId = $null
        $symbolKey = if ($scopeValue -is [string] -and -not $scopeValue.StartsWith('[')) { Find-ArmKey $Scope.Symbols $scopeValue } else { $null }
        if ($null -ne $symbolKey) {
            $scopeDefinition = $Scope.Symbols[$symbolKey]
            $scopeName = Resolve-ArmValue $scopeDefinition['name'] $Scope
            $scopeId = Get-ArmResourceId -Scope $Scope -Definition $scopeDefinition -Name $scopeName
        }
        else {
            $resolvedScope = Resolve-ArmValue $scopeValue $Scope
            if ($resolvedScope -is [string]) {
                if ($resolvedScope.StartsWith('/')) { $scopeId = $resolvedScope }
                else { $scopeId = "/subscriptions/$($Scope.SubscriptionId)/resourceGroups/$($Scope.ResourceGroupName)/providers/$resolvedScope" }
            }
        }
        if ($null -eq $scopeId) { return $null }
        return (New-ArmResourceId -Prefix $scopeId -Type $Definition['type'] -Names $names)
    }

    $subscriptionId = $Scope.SubscriptionId
    $resourceGroupName = $Scope.ResourceGroupName
    if ($Definition.Contains('subscriptionId')) { $subscriptionId = Resolve-ArmValue $Definition['subscriptionId'] $Scope }
    if ($Definition.Contains('resourceGroup')) { $resourceGroupName = Resolve-ArmValue $Definition['resourceGroup'] $Scope }
    if ($subscriptionId -is [ArmUnresolved] -or $resourceGroupName -is [ArmUnresolved]) { return $null }
    New-ArmResourceId -Prefix "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName" -Type $Definition['type'] -Names $names
}

function Invoke-ArmNode {
    param([hashtable]$Node, [hashtable]$Scope)

    switch ($Node.Kind) {
        'literal' { return , $Node.Value }
        'property' {
            $target = Invoke-ArmNode $Node.Target $Scope
            if ($target -is [ArmUnresolved]) { return $target }
            if ($target -is [System.Collections.IDictionary]) {
                $key = Find-ArmKey $target $Node.Name
                if ($null -eq $key) { return [ArmUnresolved]::new("missing property .$($Node.Name)") }
                return , $target[$key]
            }
            return [ArmUnresolved]::new("property .$($Node.Name) on non-object")
        }
        'index' {
            $target = Invoke-ArmNode $Node.Target $Scope
            $index = Invoke-ArmNode $Node.Index $Scope
            if ($target -is [ArmUnresolved]) { return $target }
            if ($index -is [ArmUnresolved]) { return $index }
            if ($target -is [System.Collections.IDictionary]) {
                $key = Find-ArmKey $target ([string]$index)
                if ($null -eq $key) { return [ArmUnresolved]::new("missing key [$index]") }
                return , $target[$key]
            }
            if (Test-ArmList $target) {
                if ([int]$index -ge $target.Count) { return [ArmUnresolved]::new("index $index out of range") }
                return , $target[[int]$index]
            }
            return [ArmUnresolved]::new('index on non-collection')
        }
        'call' {
            $result = Invoke-ArmFunction $Node $Scope
            return , $result
        }
    }
}

function Invoke-ArmLambda {
    param($Lambda, [object[]]$Arguments)

    $lambdaScope = Copy-ArmScope $Lambda.Scope
    for ($i = 0; $i -lt $Lambda.Parameters.Count -and $i -lt $Arguments.Count; $i++) {
        $lambdaScope.Locals[$Lambda.Parameters[$i]] = $Arguments[$i]
    }
    $result = Invoke-ArmNode $Lambda.Body $lambdaScope
    , $result
}

function Invoke-ArmFunction {
    param([hashtable]$Node, [hashtable]$Scope)

    $name = $Node.Name
    $arguments = $Node.Arguments
    $lowerName = $name.ToLowerInvariant()

    # Short-circuiting functions evaluate only the arguments they need.
    switch ($lowerName) {
        'if' {
            $condition = Invoke-ArmNode $arguments[0] $Scope
            if ($condition -is [ArmUnresolved]) { return $condition }
            if ([bool]$condition) { $result = Invoke-ArmNode $arguments[1] $Scope } else { $result = Invoke-ArmNode $arguments[2] $Scope }
            return , $result
        }
        'and' {
            $unresolved = $null
            foreach ($argument in $arguments) {
                $value = Invoke-ArmNode $argument $Scope
                if ($value -is [ArmUnresolved]) { $unresolved = $value; continue }
                if (-not [bool]$value) { return $false }
            }
            if ($null -ne $unresolved) { return $unresolved }
            return $true
        }
        'or' {
            $unresolved = $null
            foreach ($argument in $arguments) {
                $value = Invoke-ArmNode $argument $Scope
                if ($value -is [ArmUnresolved]) { $unresolved = $value; continue }
                if ([bool]$value) { return $true }
            }
            if ($null -ne $unresolved) { return $unresolved }
            return $false
        }
        'coalesce' {
            foreach ($argument in $arguments) {
                $value = Invoke-ArmNode $argument $Scope
                if ($value -is [ArmUnresolved]) { return $value }
                if ($null -ne $value) { return , $value }
            }
            return $null
        }
        'lambda' {
            $parameterNames = @()
            for ($i = 0; $i -lt $arguments.Count - 1; $i++) { $parameterNames += [string]$arguments[$i].Value }
            return @{ IsLambda = $true; Parameters = $parameterNames; Body = $arguments[$arguments.Count - 1]; Scope = $Scope }
        }
    }

    $values = New-Object object[] $arguments.Count
    for ($i = 0; $i -lt $arguments.Count; $i++) { $values[$i] = Invoke-ArmNode $arguments[$i] $Scope }

    if ($lowerName -eq 'tryget') {
        $current = $values[0]
        if ($current -is [ArmUnresolved]) { return $current }
        for ($i = 1; $i -lt $values.Count; $i++) {
            if ($null -eq $current) { return $null }
            if ($current -is [System.Collections.IDictionary]) {
                $key = Find-ArmKey $current ([string]$values[$i])
                if ($null -eq $key) { return $null }
                $current = $current[$key]
            }
            elseif (Test-ArmList $current) {
                if ([int]$values[$i] -ge $current.Count) { return $null }
                $current = $current[[int]$values[$i]]
            }
            else { return $null }
        }
        return , $current
    }

    foreach ($value in $values) { if ($value -is [ArmUnresolved]) { return $value } }

    if ($name.Contains('.')) {
        $functionKey = Find-ArmKey $Scope.Functions $name
        if ($null -eq $functionKey) { return [ArmUnresolved]::new("function $name") }
        $function = $Scope.Functions[$functionKey]

        # User-defined functions only see their own parameters plus the template's variables and functions.
        $functionScope = Copy-ArmScope $Scope
        $functionScope.Params = @{}
        $functionScope.Locals = @{}
        $parameterDefinitions = @($function['parameters'])
        for ($i = 0; $i -lt $parameterDefinitions.Count; $i++) {
            if ($null -eq $parameterDefinitions[$i]) { continue }
            $functionScope.Params[$parameterDefinitions[$i]['name']] = if ($i -lt $values.Count) { $values[$i] } else { $null }
        }
        $result = Resolve-ArmValue $function['output']['value'] $functionScope
        return , $result
    }

    switch ($lowerName) {
        'parameters' {
            $key = Find-ArmKey $Scope.Params ([string]$values[0])
            if ($null -eq $key) { return [ArmUnresolved]::new("parameter $($values[0])") }
            return , $Scope.Params[$key]
        }
        'variables' {
            $result = Get-ArmVariable -Scope $Scope -Name ([string]$values[0])
            return , $result
        }
        'lambdavariables' {
            $key = Find-ArmKey $Scope.Locals ([string]$values[0])
            if ($null -eq $key) { return [ArmUnresolved]::new("lambda variable $($values[0])") }
            return , $Scope.Locals[$key]
        }
        'copyindex' {
            $index = $null
            if ($values.Count -eq 0) { $index = $Scope.CopyIndex[''] }
            elseif ($values[0] -is [string]) {
                $index = $Scope.CopyIndex[$values[0]]
                if ($null -ne $index -and $values.Count -gt 1) { $index += [int]$values[1] }
            }
            else {
                $index = $Scope.CopyIndex['']
                if ($null -ne $index) { $index += [int]$values[0] }
            }
            if ($null -eq $index) { return [ArmUnresolved]::new('copyIndex outside a loop') }
            return $index
        }
        'null' { return $null }
        'true' { return $true }
        'false' { return $false }
        'format' {
            $formatArgs = New-Object object[] ([Math]::Max(0, $values.Count - 1))
            for ($i = 1; $i -lt $values.Count; $i++) { $formatArgs[$i - 1] = ConvertTo-ArmString $values[$i] }
            return [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, [string]$values[0], $formatArgs)
        }
        'concat' {
            if ($values.Count -gt 0 -and (Test-ArmList $values[0])) {
                $items = New-Object System.Collections.Generic.List[object]
                foreach ($value in $values) { foreach ($item in $value) { $items.Add($item) } }
                return , $items.ToArray()
            }
            return (($values | ForEach-Object { ConvertTo-ArmString $_ }) -join '')
        }
        'tolower' { return ([string]$values[0]).ToLowerInvariant() }
        'toupper' { return ([string]$values[0]).ToUpperInvariant() }
        'trim' { return ([string]$values[0]).Trim() }
        'replace' { return ([string]$values[0]).Replace([string]$values[1], [string]$values[2]) }
        'take' {
            if ($values[0] -is [string]) { return $values[0].Substring(0, [Math]::Max(0, [Math]::Min([int]$values[1], $values[0].Length))) }
            return , @($values[0] | Select-Object -First ([Math]::Max(0, [int]$values[1])))
        }
        'skip' {
            if ($values[0] -is [string]) { return $values[0].Substring([Math]::Max(0, [Math]::Min([int]$values[1], $values[0].Length))) }
            return , @($values[0] | Select-Object -Skip ([Math]::Max(0, [int]$values[1])))
        }
        'substring' {
            if ($values.Count -gt 2) { return ([string]$values[0]).Substring([int]$values[1], [int]$values[2]) }
            return ([string]$values[0]).Substring([int]$values[1])
        }
        'split' {
            $delimiters = if (Test-ArmList $values[1]) { [string[]]$values[1] } else { [string[]]@([string]$values[1]) }
            return , [object[]](([string]$values[0]).Split($delimiters, [System.StringSplitOptions]::None))
        }
        'first' {
            if ($values[0] -is [string]) { if ($values[0].Length -eq 0) { return '' }; return $values[0].Substring(0, 1) }
            if ((Get-ArmCount $values[0]) -eq 0) { return $null }
            return , @($values[0])[0]
        }
        'last' {
            if ($values[0] -is [string]) { if ($values[0].Length -eq 0) { return '' }; return $values[0].Substring($values[0].Length - 1) }
            $items = @($values[0])
            if ($items.Count -eq 0) { return $null }
            return , $items[$items.Count - 1]
        }
        'length' { return (Get-ArmCount $values[0]) }
        'empty' { return (Test-ArmEmpty $values[0]) }
        'contains' {
            $container = $values[0]
            if ($container -is [string]) { return $container.IndexOf([string]$values[1], [System.StringComparison]::OrdinalIgnoreCase) -ge 0 }
            if ($container -is [System.Collections.IDictionary]) { return ($null -ne (Find-ArmKey $container ([string]$values[1]))) }
            foreach ($item in @($container)) { if (Test-ArmEqual $item $values[1]) { return $true } }
            return $false
        }
        'equals' { return (Test-ArmEqual $values[0] $values[1]) }
        'not' { return (-not [bool]$values[0]) }
        'greater' { return $values[0] -gt $values[1] }
        'less' { return $values[0] -lt $values[1] }
        'greaterorequals' { return $values[0] -ge $values[1] }
        'lessorequals' { return $values[0] -le $values[1] }
        'add' { return $values[0] + $values[1] }
        'sub' { return $values[0] - $values[1] }
        'mul' { return $values[0] * $values[1] }
        'div' { return [long][Math]::Floor($values[0] / $values[1]) }
        'mod' { return $values[0] % $values[1] }
        'min' {
            $items = if ($values.Count -eq 1) { @($values[0]) } else { $values }
            return ($items | Measure-Object -Minimum).Minimum
        }
        'max' {
            $items = if ($values.Count -eq 1) { @($values[0]) } else { $values }
            return ($items | Measure-Object -Maximum).Maximum
        }
        'int' { return [long]$values[0] }
        'float' { return [double]$values[0] }
        'bool' { if ($values[0] -is [string]) { return $values[0] -eq 'true' }; return [bool]$values[0] }
        'string' { return (ConvertTo-ArmString $values[0]) }
        'json' {
            if ([string]$values[0] -eq 'null') { return $null }
            $parsed = ConvertTo-ArmObject (ConvertFrom-Json -InputObject ([string]$values[0]))
            return , $parsed
        }
        'createarray' { return , [object[]]$values }
        'array' { if (Test-ArmList $values[0]) { return , $values[0] }; return , [object[]]@($values[0]) }
        'createobject' {
            $result = [ordered]@{}
            for ($i = 0; $i + 1 -lt $values.Count; $i += 2) { $result[[string]$values[$i]] = $values[$i + 1] }
            return , $result
        }
        'union' {
            if ($values[0] -is [System.Collections.IDictionary]) {
                $result = [ordered]@{}
                foreach ($value in $values) { if ($null -ne $value) { $result = Merge-ArmObject $result $value } }
                return , $result
            }
            $items = New-Object System.Collections.Generic.List[object]
            foreach ($value in $values) {
                foreach ($item in @($value)) {
                    $duplicate = $false
                    foreach ($existing in $items) { if (Test-ArmEqual $existing $item) { $duplicate = $true; break } }
                    if (-not $duplicate) { $items.Add($item) }
                }
            }
            return , $items.ToArray()
        }
        'intersection' {
            if ($values[0] -is [System.Collections.IDictionary]) {
                $result = [ordered]@{}
                foreach ($key in $values[0].Keys) {
                    $inAll = $true
                    for ($i = 1; $i -lt $values.Count; $i++) {
                        $otherKey = Find-ArmKey $values[$i] $key
                        if ($null -eq $otherKey -or -not (Test-ArmEqual $values[0][$key] $values[$i][$otherKey])) { $inAll = $false; break }
                    }
                    if ($inAll) { $result[$key] = $values[0][$key] }
                }
                return , $result
            }
            $items = New-Object System.Collections.Generic.List[object]
            foreach ($item in @($values[0])) {
                $inAll = $true
                for ($i = 1; $i -lt $values.Count; $i++) {
                    $found = $false
                    foreach ($other in @($values[$i])) { if (Test-ArmEqual $item $other) { $found = $true; break } }
                    if (-not $found) { $inAll = $false; break }
                }
                if ($inAll) { $items.Add($item) }
            }
            return , $items.ToArray()
        }
        'shallowmerge' {
            $result = [ordered]@{}
            foreach ($value in @($values[0])) { foreach ($key in $value.Keys) { $result[$key] = $value[$key] } }
            return , $result
        }
        'objectkeys' { return , [object[]]@($values[0].Keys) }
        'items' {
            $items = New-Object System.Collections.Generic.List[object]
            foreach ($key in ($values[0].Keys | Sort-Object)) { $items.Add([ordered]@{ key = $key; value = $values[0][$key] }) }
            return , $items.ToArray()
        }
        'range' {
            if ([long]$values[1] -le 0) { return , [object[]]@() }
            return , [object[]]@([long]$values[0]..([long]$values[0] + [long]$values[1] - 1))
        }
        'startswith' { return ([string]$values[0]).StartsWith([string]$values[1], [System.StringComparison]::OrdinalIgnoreCase) }
        'endswith' { return ([string]$values[0]).EndsWith([string]$values[1], [System.StringComparison]::OrdinalIgnoreCase) }
        'indexof' {
            if ($values[0] -is [string]) { return ([string]$values[0]).IndexOf([string]$values[1], [System.StringComparison]::OrdinalIgnoreCase) }
            $items = @($values[0])
            for ($i = 0; $i -lt $items.Count; $i++) { if (Test-ArmEqual $items[$i] $values[1]) { return $i } }
            return -1
        }
        'lastindexof' {
            if ($values[0] -is [string]) { return ([string]$values[0]).LastIndexOf([string]$values[1], [System.StringComparison]::OrdinalIgnoreCase) }
            $items = @($values[0])
            for ($i = $items.Count - 1; $i -ge 0; $i--) { if (Test-ArmEqual $items[$i] $values[1]) { return $i } }
            return -1
        }
        'padleft' {
            $padCharacter = if ($values.Count -gt 2) { [char]([string]$values[2])[0] } else { ' ' }
            return ([string]$values[0]).PadLeft([int]$values[1], $padCharacter)
        }
        'flatten' {
            $items = New-Object System.Collections.Generic.List[object]
            foreach ($value in @($values[0])) { foreach ($item in @($value)) { $items.Add($item) } }
            return , $items.ToArray()
        }
        'map' {
            $items = New-Object System.Collections.Generic.List[object]
            $index = 0
            foreach ($item in @($values[0])) {
                $items.Add((Invoke-ArmLambda $values[1] @($item, $index)))
                $index++
            }
            return , $items.ToArray()
        }
        'filter' {
            $items = New-Object System.Collections.Generic.List[object]
            $index = 0
            foreach ($item in @($values[0])) {
                $keep = Invoke-ArmLambda $values[1] @($item, $index)
                if ($keep -is [ArmUnresolved]) { return $keep }
                if ([bool]$keep) { $items.Add($item) }
                $index++
            }
            return , $items.ToArray()
        }
        'toobject' {
            $result = [ordered]@{}
            foreach ($item in @($values[0])) {
                $key = Invoke-ArmLambda $values[1] @($item)
                if ($key -is [ArmUnresolved]) { return $key }
                $result[[string]$key] = if ($values.Count -gt 2) { Invoke-ArmLambda $values[2] @($item) } else { $item }
            }
            return , $result
        }
        'resourcegroup' {
            return , [ordered]@{
                name       = $Scope.ResourceGroupName
                location   = $Scope.Location
                id         = "/subscriptions/$($Scope.SubscriptionId)/resourceGroups/$($Scope.ResourceGroupName)"
                properties = @{}
            }
        }
        'subscription' {
            return , [ordered]@{
                subscriptionId = $Scope.SubscriptionId
                id             = "/subscriptions/$($Scope.SubscriptionId)"
                tenantId       = [ArmUnresolved]::new('tenantId')
            }
        }
        'deployment' { return , [ordered]@{ name = $Scope.DeploymentName; properties = @{} } }
        'environment' {
            return , [ordered]@{
                name            = 'AzureCloud'
                resourceManager = 'https://management.azure.com/'
                authentication  = [ordered]@{ loginEndpoint = 'https://login.microsoftonline.com/' }
                suffixes        = [ordered]@{
                    storage           = 'core.windows.net'
                    acrLoginServer    = '.azurecr.io'
                    keyvaultDns       = '.vault.azure.net'
                    sqlServerHostname = '.database.windows.net'
                }
            }
        }
        { $_ -in 'resourceid', 'subscriptionresourceid', 'tenantresourceid' } {
            $typeIndex = -1
            for ($i = 0; $i -lt $values.Count; $i++) {
                if ($values[$i] -is [string] -and $values[$i] -match '^[\w-]+\.[\w.-]+/') { $typeIndex = $i; break }
            }
            if ($typeIndex -lt 0) { return [ArmUnresolved]::new("$name type") }
            $names = if ($typeIndex + 1 -lt $values.Count) { @($values[($typeIndex + 1)..($values.Count - 1)]) } else { @() }
            if ($lowerName -eq 'tenantresourceid') { return (New-ArmResourceId -Prefix '' -Type $values[$typeIndex] -Names $names) }
            $subscriptionId = $Scope.SubscriptionId
            $resourceGroupName = $Scope.ResourceGroupName
            if ($lowerName -eq 'subscriptionresourceid') {
                if ($typeIndex -eq 1) { $subscriptionId = $values[0] }
                return (New-ArmResourceId -Prefix "/subscriptions/$subscriptionId" -Type $values[$typeIndex] -Names $names)
            }
            if ($typeIndex -eq 2) { $subscriptionId = $values[0]; $resourceGroupName = $values[1] }
            elseif ($typeIndex -eq 1) { $resourceGroupName = $values[0] }
            return (New-ArmResourceId -Prefix "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName" -Type $values[$typeIndex] -Names $names)
        }
        'extensionresourceid' {
            $names = if ($values.Count -gt 2) { @($values[2..($values.Count - 1)]) } else { @() }
            return (New-ArmResourceId -Prefix ([string]$values[0]) -Type ([string]$values[1]) -Names $names)
        }
        'resourceinfo' {
            $key = Find-ArmKey $Scope.Symbols ([string]$values[0])
            if ($null -eq $key) { return [ArmUnresolved]::new("resourceInfo $($values[0])") }
            $definition = $Scope.Symbols[$key]
            $resourceName = Resolve-ArmValue $definition['name'] $Scope
            return , [ordered]@{
                id         = (Get-ArmResourceId -Scope $Scope -Definition $definition -Name $resourceName)
                name       = $resourceName
                type       = $definition['type']
                apiVersion = $definition['apiVersion']
            }
        }
        'reference' {
            $target = $values[0]
            if ($target -is [string]) {
                $key = Find-ArmKey $Scope.Symbols $target
                if ($null -ne $key -and $Scope.Symbols[$key]['type'] -eq 'Microsoft.Resources/deployments') {
                    $result = Get-ArmDeploymentOutputs -Scope $Scope -Symbol $key
                    return , $result
                }
                if ($target -match '/providers/Microsoft\.Resources/deployments/([^/]+)$') {
                    $deploymentName = $Matches[1]
                    foreach ($symbol in $Scope.Symbols.Keys) {
                        $definition = $Scope.Symbols[$symbol]
                        if ($definition['type'] -ne 'Microsoft.Resources/deployments') { continue }
                        $candidateName = Resolve-ArmValue $definition['name'] $Scope
                        if ($candidateName -is [string] -and $candidateName -eq $deploymentName) {
                            $result = Get-ArmDeploymentOutputs -Scope $Scope -Symbol $symbol
                            return , $result
                        }
                    }
                }
            }
            return [ArmUnresolved]::new("reference($target)")
        }
        'uri' { return ([System.Uri]::new([System.Uri]([string]$values[0]), [string]$values[1])).ToString() }
        default { return [ArmUnresolved]::new("function $name()") }
    }
}

function Resolve-ArmValue {
    param($Value, [hashtable]$Scope)

    if ($null -eq $Value) { return $null }

    if ($Value -is [string]) {
        if ($Value.StartsWith('[[')) { return $Value.Substring(1) }
        if ($Value.StartsWith('[') -and $Value.EndsWith(']')) {
            try {
                $result = Invoke-ArmNode (Get-ArmExpressionAst $Value.Substring(1, $Value.Length - 2)) $Scope
                return , $result
            }
            catch {
                return [ArmUnresolved]::new("evaluation error: $($_.Exception.Message)")
            }
        }
        return $Value
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $entry = $Value[$key]
            # Property copy loops: { copy: [ { name, count, input } ] }
            if ($key -eq 'copy' -and (Test-ArmList $entry) -and @($entry | Where-Object { $_ -is [System.Collections.IDictionary] -and $_.Contains('input') }).Count -gt 0) {
                foreach ($loop in $entry) {
                    $count = Resolve-ArmValue $loop['count'] $Scope
                    if ($count -is [ArmUnresolved]) { $result[$loop['name']] = $count; continue }
                    $items = New-Object System.Collections.Generic.List[object]
                    for ($i = 0; $i -lt [int]$count; $i++) {
                        $iterationScope = Copy-ArmScope $Scope
                        $iterationScope.CopyIndex[$loop['name']] = $i
                        $items.Add((Resolve-ArmValue $loop['input'] $iterationScope))
                    }
                    $result[$loop['name']] = $items.ToArray()
                }
                continue
            }
            $resolvedKey = $key
            if ($key -is [string] -and $key.StartsWith('[') -and $key.EndsWith(']')) {
                $resolvedKey = ConvertTo-ArmString (Resolve-ArmValue $key $Scope)
            }
            $result[$resolvedKey] = Resolve-ArmValue $entry $Scope
        }
        return , $result
    }

    if (Test-ArmList $Value) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) { $items.Add((Resolve-ArmValue $item $Scope)) }
        return , $items.ToArray()
    }

    , $Value
}

function ConvertTo-ArmPlainValue {
    # Replaces unresolved markers with "<unresolved: …>" strings so the result serialises cleanly.
    param($Value)

    if ($Value -is [ArmUnresolved]) { return $Value.ToString() }
    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $Value.Keys) { $result[$key] = ConvertTo-ArmPlainValue $Value[$key] }
        return , $result
    }
    if (Test-ArmList $Value) {
        $items = New-Object System.Collections.Generic.List[object]
        foreach ($item in $Value) { $items.Add((ConvertTo-ArmPlainValue $item)) }
        return , $items.ToArray()
    }
    , $Value
}
