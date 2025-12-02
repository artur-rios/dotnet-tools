# Test runner for dotnet-tools commands
Param(
    [ValidateSet('cmd-test-all', 'cmd-test-lib', 'cmd-test-min', 'bash-test-all', 'bash-test-lib', 'bash-test-min', 'all')]
    [string]$Suite = 'all',
    [switch]$VerboseOutput
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Paths
$RepoRoot = Split-Path -Parent $PSScriptRoot
$CmdEntrypoint = Join-Path $RepoRoot 'dotnet-tools.cmd'
$BashEntrypoint = Join-Path $RepoRoot 'dotnet-tools'
$TestsDir = Join-Path $RepoRoot 'tests'
$MockRoot = Join-Path $TestsDir 'mock'

# Utilities
function Invoke-CmdEntrypoint {
    param(
        [Parameter(Mandatory)] [string] $Command,
        [string[]] $CommandArgs
    )
    & $CmdEntrypoint $Command @CommandArgs
}

function Invoke-BashEntrypoint {
    param(
        [Parameter(Mandatory)] [string] $Command,
        [string[]] $CommandArgs
    )
    # Requires Git Bash or WSL bash available on PATH
    bash "$BashEntrypoint" $Command @CommandArgs
}

function Reset-MockFolder {
    param([Parameter(Mandatory)] [string] $SuiteName)
    if ($script:CleanNextSuite -or -not (Test-Path $MockRoot)) {
        if (Test-Path $MockRoot) {
            Remove-Item -Path $MockRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        $null = New-Item -Path $MockRoot -ItemType Directory -Force
    }
    $SuiteRoot = Join-Path $MockRoot $SuiteName
    $null = New-Item -Path $SuiteRoot -ItemType Directory -Force
    return $SuiteRoot
}

function Write-Message {
    param([string]$Message)
    Write-Host $Message
}

# Test tracking
$script:AllTests = @()
function Add-TestResult {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [bool] $Passed,
        [string] $Details
    )
    $script:AllTests += [pscustomobject]@{ Name = $Name; Passed = $Passed; Details = $Details }
}

function Assert-True {
    param(
        [Parameter(Mandatory)] [bool] $Condition,
        [Parameter(Mandatory)] [string] $TestName,
        [string] $Details
    )
    if ($Condition) { Add-TestResult -Name $TestName -Passed $true -Details $Details }
    else { Add-TestResult -Name $TestName -Passed $false -Details $Details }
}

# Common verifications
function Get-CsprojVersion {
    param([Parameter(Mandatory)] [string] $CsprojPath)
    try {
        [xml]$xml = Get-Content -Path $CsprojPath -Raw
        $pgs = @()
        if ($xml.Project.PropertyGroup) {
            if ($xml.Project.PropertyGroup -is [System.Array]) { $pgs = $xml.Project.PropertyGroup }
            else { $pgs = @($xml.Project.PropertyGroup) }
        }
        foreach ($pg in $pgs) { if ($pg.Version) { return [string]$pg.Version } }
        $all = $xml.SelectNodes('//*')
        foreach ($node in $all) { if ($node.Name -ieq 'Version' -and $node.InnerText) { return [string]$node.InnerText.Trim() } }
    } catch { }
    return $null
}

function Test-BinObj {
    param([Parameter(Mandatory)] [string] $ProjectDir)
    (Test-Path (Join-Path $ProjectDir 'bin')) -or (Test-Path (Join-Path $ProjectDir 'obj'))
}

function Remove-GitTagIfExists {
    param(
        [Parameter(Mandatory)] [string] $Tag,
        [string] $RepoRoot
    )
    if ($RepoRoot) { Assert-GitTopLevelUnderMock -RepoRoot $RepoRoot }
    $tags = if ($RepoRoot) { @(git -C $RepoRoot tag --list $Tag 2>$null) } else { @(git tag --list $Tag 2>$null) }
    if ($tags -and ($tags -contains $Tag)) {
        if ($RepoRoot) { git -C $RepoRoot tag -d $Tag 2>$null | Out-Null }
        else { git tag -d $Tag 2>$null | Out-Null }
    }
}

function Assert-GitTopLevelUnderMock {
    param([Parameter(Mandatory)] [string] $RepoRoot)
    try {
        $top = (git -C $RepoRoot rev-parse --show-toplevel 2>$null)
    } catch { $top = $null }
    if (-not $top) { return }
    $topFull = [System.IO.Path]::GetFullPath($top.Trim())
    $mockFull = [System.IO.Path]::GetFullPath($MockRoot)
    if (-not $mockFull.EndsWith([System.IO.Path]::DirectorySeparatorChar)) { $mockFull = $mockFull + [System.IO.Path]::DirectorySeparatorChar }
    if (-not $topFull.StartsWith($mockFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Safety check: Git toplevel '$topFull' is outside mock root '$mockFull'. Aborting."
    }
}

function Initialize-GitRepo {
    param([Parameter(Mandatory)] [string] $RepoRoot)
    $gitDir = Join-Path $RepoRoot '.git'
    if (-not (Test-Path -LiteralPath $gitDir -PathType Container)) {
        git -C $RepoRoot init 2>$null | Out-Null
    }
    # Silence CRLF normalization warnings and set identity (scoped to mock repo)
    git -C $RepoRoot config core.autocrlf false 2>$null | Out-Null
    git -C $RepoRoot config core.safecrlf false 2>$null | Out-Null
    git -C $RepoRoot config user.email 'tests@example.com' 2>$null | Out-Null
    git -C $RepoRoot config user.name  'Dotnet Tools Tests' 2>$null | Out-Null
    git -C $RepoRoot add -A 2>$null | Out-Null
    # Commit if there is anything to commit (only in mock repo)
    git -C $RepoRoot diff --cached --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        git -C $RepoRoot commit -m 'initial commit' 2>$null | Out-Null
    }
    Assert-GitTopLevelUnderMock -RepoRoot $RepoRoot
}

# Suite: CMD + init-lib
function Invoke-SuiteCmdLib {
    Write-Message 'Running suite: cmd-test-lib'
    $suiteRoot = Reset-MockFolder -SuiteName 'cmd-test-lib'

    $name = 'MyLibCmd'
    $author = 'Test User'
    $description = 'Library via cmd with init-lib'
    $version = '0.1.0'

    # init-lib (create under suite root)
    Push-Location $suiteRoot
    try {
        Write-Message '[TEST] Testing init-lib'
        Invoke-CmdEntrypoint -Command 'init-lib' -CommandArgs @('--root', $name, '--solution', $name, '--project', $name, '--author', $author, '--description', $description, '--version', $version) | Out-Null
    } finally { Pop-Location }
    $root = Join-Path $suiteRoot $name
    $projDir = Join-Path $root 'src'
    $csproj = Join-Path $projDir "$name.csproj"
    Initialize-GitRepo -RepoRoot $root

    $okInit = Test-Path $csproj
    Assert-True -Condition $okInit -TestName 'init-lib creates project' -Details "$csproj exists"
    Write-Message ($(if ($okInit) { '[SUCCESS] init-lib' } else { '[FAIL] init-lib' }))

    # build (target src so solution is found)
    Write-Message '[TEST] Testing build'
    $srcDir = Join-Path $root 'src'
    Invoke-CmdEntrypoint -Command 'build' -CommandArgs @($srcDir) | Out-Null
    $okBuild = (Test-BinObj -ProjectDir $projDir)
    Assert-True -Condition $okBuild -TestName 'build generates bin/obj' -Details 'bin or obj present'
    Write-Message ($(if ($okBuild) { '[SUCCESS] build' } else { '[FAIL] build' }))

    # bump
    Write-Message '[TEST] Testing patch'
    $before = Get-CsprojVersion -CsprojPath $csproj
    Invoke-CmdEntrypoint -Command 'bump' -CommandArgs @('--patch', $projDir) | Out-Null
    $after = Get-CsprojVersion -CsprojPath $csproj
    $bumped = ($before -ne $after)
    Assert-True -Condition $bumped -TestName 'bump updates version' -Details "version: $before -> $after"
    Write-Message ($(if ($bumped) { '[SUCCESS] bump --patch' } else { '[FAIL] bump --patch' }))

    # tag
    Write-Message '[TEST] Testing tag'
    $tagName = "v$after"
        Assert-GitTopLevelUnderMock -RepoRoot $root
        Remove-GitTagIfExists -Tag $tagName -RepoRoot $root
    Push-Location $root
    try { $tagCmdOk = $true; Invoke-CmdEntrypoint -Command 'tag' -CommandArgs @($projDir) 2>$null | Out-Null } catch { $tagCmdOk = $false } finally { Pop-Location }
    $tags = @(git -C $root tag --list $tagName 2>$null)
    $tagExists = $tagCmdOk -and ($tags -contains $tagName)
    Assert-True -Condition $tagExists -TestName 'tag creates git tag' -Details $tagName
    Write-Message ($(if ($tagExists) { '[SUCCESS] tag' } else { '[FAIL] tag' }))

    # test
    Write-Message '[TEST] Testing test'
    $testsDirForProject = Join-Path $root 'tests'
    try {
        Invoke-CmdEntrypoint -Command 'test' -CommandArgs @($testsDirForProject) | Out-Null
        $ok = $true
    }
    catch {
        $ok = $false
    }
    Assert-True -Condition $ok -TestName 'test runs successfully' -Details 'dotnet-tools test'
    Write-Message ($(if ($ok) { '[SUCCESS] test' } else { '[FAIL] test' }))

    # clean
    Write-Message '[TEST] Testing clean'
    Invoke-CmdEntrypoint -Command 'clean' -CommandArgs @($root) | Out-Null
    $cleaned = -not (Test-BinObj -ProjectDir $projDir)
    Assert-True -Condition $cleaned -TestName 'clean removes bin/obj' -Details 'bin/obj removed'
    Write-Message ($(if ($cleaned) { '[SUCCESS] clean' } else { '[FAIL] clean' }))
}

# Suite: CMD + without init-lib (use init-proj minimal)
function Invoke-SuiteCmdMin {
    Write-Message 'Running suite: cmd-test-min'
    $suiteRoot = Reset-MockFolder -SuiteName 'cmd-test-min'

    $name = 'MyProjCmd'
    # init-min (create under suite root)
    Push-Location $suiteRoot
    try {
        Write-Message '[TEST] Testing init-min'
        Invoke-CmdEntrypoint -Command 'init-min' -CommandArgs @('--root', $name, '--solution', $name, '--project', $name, '--author', 'Test User', '--description', 'Minimal repo') | Out-Null
    } finally { Pop-Location }
    $root = Join-Path $suiteRoot $name
    $projDir = Join-Path (Join-Path $root 'src') $name
    $csproj = Join-Path $projDir "$name.csproj"
    Initialize-GitRepo -RepoRoot $root
    $okInit = Test-Path $csproj
    Assert-True -Condition $okInit -TestName 'init-min creates project' -Details "$csproj exists"
    Write-Message ($(if ($okInit) { '[SUCCESS] init-min' } else { '[FAIL] init-min' }))

    Write-Message '[TEST] Testing build'
    $srcDir = Join-Path $root 'src'
    Invoke-CmdEntrypoint -Command 'build' -CommandArgs @($srcDir) | Out-Null
    $okBuild = (Test-BinObj -ProjectDir $projDir)
    Assert-True -Condition $okBuild -TestName 'build generates bin/obj (no init-lib)' -Details 'bin or obj present'
    Write-Message ($(if ($okBuild) { '[SUCCESS] build' } else { '[FAIL] build' }))

    Write-Message '[TEST] Testing bump'
    $before = Get-CsprojVersion -CsprojPath $csproj
    Invoke-CmdEntrypoint -Command 'bump' -CommandArgs @('0.1.0', $projDir) | Out-Null
    $after = Get-CsprojVersion -CsprojPath $csproj
    $bumped = ($after -eq '0.1.0')
    Assert-True -Condition $bumped -TestName 'bump updates version (no init-lib)' -Details "version: $before -> $after"
    Write-Message ($(if ($bumped) { '[SUCCESS] bump set' } else { '[FAIL] bump set' }))

    Write-Message '[TEST] Testing tag'
    $tagName = "v$after"
        Assert-GitTopLevelUnderMock -RepoRoot $root
        Remove-GitTagIfExists -Tag $tagName -RepoRoot $root
    Push-Location $root
    try { $tagCmdOk = $true; Invoke-CmdEntrypoint -Command 'tag' -CommandArgs @($projDir) 2>$null | Out-Null } catch { $tagCmdOk = $false } finally { Pop-Location }
    $tags = @(git -C $root tag --list $tagName 2>$null)
    $tagExists = $tagCmdOk -and ($tags -contains $tagName)
    Assert-True -Condition $tagExists -TestName 'tag creates git tag (no init-lib)' -Details $tagName
    Write-Message ($(if ($tagExists) { '[SUCCESS] tag' } else { '[FAIL] tag' }))

    Write-Message '[TEST] Testing test'
    try { Invoke-CmdEntrypoint -Command 'test' -CommandArgs @($root) | Out-Null; $ok = $true } catch { $ok = $false }
    Assert-True -Condition $ok -TestName 'test runs successfully (no init-lib)' -Details 'dotnet-tools test'
    Write-Message ($(if ($ok) { '[SUCCESS] test' } else { '[FAIL] test' }))

    Write-Message '[TEST] Testing clean'
    Invoke-CmdEntrypoint -Command 'clean' -CommandArgs @($root) | Out-Null
    $cleaned = (-not (Test-BinObj -ProjectDir $projDir))
    Assert-True -Condition $cleaned -TestName 'clean removes bin/obj (no init-lib)' -Details 'bin/obj removed'
    Write-Message ($(if ($cleaned) { '[SUCCESS] clean' } else { '[FAIL] clean' }))
}

# Suite: Bash + init-lib
function Invoke-SuiteBashLib {
    Write-Message 'Running suite: bash-test-lib'
    $suiteRoot = Reset-MockFolder -SuiteName 'bash-test-lib'

    $name = 'MyLibBash'
    $author = 'Test User'
    $description = 'Library via bash with init-lib'
    $version = '0.2.0'

    Push-Location $suiteRoot
    try {
        Write-Message '[TEST] Testing init-lib'
        Invoke-BashEntrypoint -Command 'init-lib' -CommandArgs @('--root', $name, '--solution', $name, '--project', $name, '--author', $author, '--description', $description, '--version', $version) | Out-Null
    } finally { Pop-Location }
    $root = Join-Path $suiteRoot $name
    $projDir = Join-Path $root 'src'
    $csproj = Join-Path $projDir "$name.csproj"
    Initialize-GitRepo -RepoRoot $root

    $okInit = Test-Path $csproj
    Assert-True -Condition $okInit -TestName 'init-lib (bash) creates project' -Details "$csproj exists"
    Write-Message ($(if ($okInit) { '[SUCCESS] init-lib' } else { '[FAIL] init-lib' }))

    Write-Message '[TEST] Testing build'
    $srcDir = Join-Path $root 'src'
    Invoke-BashEntrypoint -Command 'build' -CommandArgs @($srcDir) | Out-Null
    $okBuild = (Test-BinObj -ProjectDir $projDir)
    Assert-True -Condition $okBuild -TestName 'build (bash) generates bin/obj' -Details 'bin or obj present'
    Write-Message ($(if ($okBuild) { '[SUCCESS] build' } else { '[FAIL] build' }))

    Write-Message '[TEST] Testing patch'
    $before = Get-CsprojVersion -CsprojPath $csproj
    Invoke-BashEntrypoint -Command 'bump' -CommandArgs @('--patch', $projDir) | Out-Null
    $after = Get-CsprojVersion -CsprojPath $csproj
    $bumped = ($before -ne $after)
    Assert-True -Condition $bumped -TestName 'bump (bash) updates version' -Details "version: $before -> $after"
    Write-Message ($(if ($bumped) { '[SUCCESS] bump --patch' } else { '[FAIL] bump --patch' }))

    Write-Message '[TEST] Testing tag'
    $tagName = "v$after"
        Assert-GitTopLevelUnderMock -RepoRoot $root
        Remove-GitTagIfExists -Tag $tagName -RepoRoot $root
    Push-Location $root
    try { $tagCmdOk = $true; Invoke-BashEntrypoint -Command 'tag' -CommandArgs @($projDir) 2>$null | Out-Null } catch { $tagCmdOk = $false } finally { Pop-Location }
    $tags = @(git -C $root tag --list $tagName 2>$null)
    $tagExists = $tagCmdOk -and ($tags -contains $tagName)
    Assert-True -Condition $tagExists -TestName 'tag (bash) creates git tag' -Details $tagName
    Write-Message ($(if ($tagExists) { '[SUCCESS] tag' } else { '[FAIL] tag' }))

    Write-Message '[TEST] Testing test'
    try { Invoke-BashEntrypoint -Command 'test' -CommandArgs @($root) | Out-Null; $ok = $true } catch { $ok = $false }
    Assert-True -Condition $ok -TestName 'test (bash) runs successfully' -Details 'dotnet-tools test'
    Write-Message ($(if ($ok) { '[SUCCESS] test' } else { '[FAIL] test' }))

    Write-Message '[TEST] Testing clean'
    Invoke-BashEntrypoint -Command 'clean' -CommandArgs @($root) | Out-Null
    $cleaned = (-not (Test-BinObj -ProjectDir $projDir))
    Assert-True -Condition $cleaned -TestName 'clean (bash) removes bin/obj' -Details 'bin/obj removed'
    Write-Message ($(if ($cleaned) { '[SUCCESS] clean' } else { '[FAIL] clean' }))
}

# Suite: Bash + without init-lib (use init-proj minimal)
function Invoke-SuiteBashMin {
    Write-Message 'Running suite: bash-test-min'
    $suiteRoot = Reset-MockFolder -SuiteName 'bash-test-min'

    $name = 'MyProjBash'
    Push-Location $suiteRoot
    try {
        Write-Message '[TEST] Testing init-min'
        Invoke-BashEntrypoint -Command 'init-min' -CommandArgs @('--root', $name, '--solution', $name, '--project', $name, '--author', 'Test User', '--description', 'Minimal repo') | Out-Null
    } finally { Pop-Location }
    $root = Join-Path $suiteRoot $name
    $projDir = Join-Path (Join-Path $root 'src') $name
    $csproj = Join-Path $projDir "$name.csproj"
    Initialize-GitRepo -RepoRoot $root
    $okInit = Test-Path $csproj
    Assert-True -Condition $okInit -TestName 'init-min (bash) creates project' -Details "$csproj exists"
    Write-Message ($(if ($okInit) { '[SUCCESS] init-min' } else { '[FAIL] init-min' }))

    Write-Message '[TEST] Testing build'
    $srcDir = Join-Path $root 'src'
    Invoke-BashEntrypoint -Command 'build' -CommandArgs @($srcDir) | Out-Null
    $okBuild = (Test-BinObj -ProjectDir $projDir)
    Assert-True -Condition $okBuild -TestName 'build (bash) generates bin/obj (no init-lib)' -Details 'bin or obj present'
    Write-Message ($(if ($okBuild) { '[SUCCESS] build' } else { '[FAIL] build' }))

    Write-Message '[TEST] Testing bump'
    $before = Get-CsprojVersion -CsprojPath $csproj
    Invoke-BashEntrypoint -Command 'bump' -CommandArgs @('0.1.0', $projDir) | Out-Null
    $after = Get-CsprojVersion -CsprojPath $csproj
    $bumped = ($after -eq '0.1.0')
    Assert-True -Condition $bumped -TestName 'bump (bash) updates version (no init-lib)' -Details "version: $before -> $after"
    Write-Message ($(if ($bumped) { '[SUCCESS] bump set' } else { '[FAIL] bump set' }))

    Write-Message '[TEST] Testing tag'
    $tagName = "v$after"
        Assert-GitTopLevelUnderMock -RepoRoot $root
        Remove-GitTagIfExists -Tag $tagName -RepoRoot $root
    Push-Location $root
    try { $tagCmdOk = $true; Invoke-BashEntrypoint -Command 'tag' -CommandArgs @($projDir) 2>$null | Out-Null } catch { $tagCmdOk = $false } finally { Pop-Location }
    $tags = @(git -C $root tag --list $tagName 2>$null)
    $tagExists = $tagCmdOk -and ($tags -contains $tagName)
    Assert-True -Condition $tagExists -TestName 'tag (bash) creates git tag (no init-lib)' -Details $tagName
    Write-Message ($(if ($tagExists) { '[SUCCESS] tag' } else { '[FAIL] tag' }))

    Write-Message '[TEST] Testing test'
    try { Invoke-BashEntrypoint -Command 'test' -CommandArgs @($root) | Out-Null; $ok = $true } catch { $ok = $false }
    Assert-True -Condition $ok -TestName 'test (bash) runs successfully (no init-lib)' -Details 'dotnet-tools test'
    Write-Message ($(if ($ok) { '[SUCCESS] test' } else { '[FAIL] test' }))

    Write-Message '[TEST] Testing clean'
    Invoke-BashEntrypoint -Command 'clean' -CommandArgs @($root) | Out-Null
    $cleaned = (-not (Test-BinObj -ProjectDir $projDir))
    Assert-True -Condition $cleaned -TestName 'clean (bash) removes bin/obj (no init-lib)' -Details 'bin/obj removed'
    Write-Message ($(if ($cleaned) { '[SUCCESS] clean' } else { '[FAIL] clean' }))
}

# Execute suites
switch ($Suite) {
    'all' {
        $runOrder = @(
            'Invoke-SuiteCmdLib',
            'Invoke-SuiteCmdMin',
            'Invoke-SuiteBashLib',
            'Invoke-SuiteBashMin'
        )
    }
    'cmd-test-all' {
        $runOrder = @('Invoke-SuiteCmdLib', 'Invoke-SuiteCmdMin')
    }
    'cmd-test-lib' { $runOrder = @('Invoke-SuiteCmdLib') }
    'cmd-test-min' { $runOrder = @('Invoke-SuiteCmdMin') }
    'bash-test-all' {
        $runOrder = @('Invoke-SuiteBashLib', 'Invoke-SuiteBashMin')
    }
    'bash-test-lib' { $runOrder = @('Invoke-SuiteBashLib') }
    'bash-test-min' { $runOrder = @('Invoke-SuiteBashMin') }
}

$script:CleanNextSuite = $true
foreach ($suiteName in $runOrder) {
    try {
        & $suiteName
    }
    catch {
        Add-TestResult -Name $suiteName -Passed $false -Details $_.Exception.Message
    }
    $script:CleanNextSuite = $false
}

# Summary
    $passed = @($script:AllTests | Where-Object { $_.Passed }).Count
    $total = @($script:AllTests).Count

Write-Host
foreach ($t in $script:AllTests) {
    $status = if ($t.Passed) { 'PASSED' } else { 'FAILED' }
    $detailText = if ($VerboseOutput -and $t.Details) { " - $($t.Details)" } else { '' }
    Write-Host "- $($t.Name): $status$detailText"
}
Write-Host "[SUMMARY] $passed of $total tests passed"
