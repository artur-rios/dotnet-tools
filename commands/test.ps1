$ErrorActionPreference = 'Stop'
function Log($msg) { Write-Host $msg }
function ErrorExit($msg) { Log "[ERROR] $msg"; exit 1 }

function New-Directory([string]$p) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
function Clear-Directory([string]$p) { if (Test-Path $p) { Get-ChildItem -LiteralPath $p -Force | ForEach-Object { if ($_.PSIsContainer) { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue } else { try { Remove-Item -LiteralPath $_.FullName -Force } catch {} } } } }
function Run([ScriptBlock]$cmd) {
    Log ("[INFO] Running: {0}" -f $cmd)
    & $cmd
    if ($LASTEXITCODE -ne 0) {
        ErrorExit ("Command failed with exit code {0}: {1}" -f $LASTEXITCODE, $cmd)
    }
    else {
        Log '[OK] Command finished successfully'
    }
}
function Test-SetupPath([string]$p) { return (($p -split '\\') | ForEach-Object { $_.ToLower() -eq 'setup' } | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count) -gt 0 }

# Defensively ignore a stray subcommand token forwarded by the wrapper
$args = @($args | Where-Object { $_ -ne 'test' })

$argsPath = if ($args.Count -ge 1) { $args[0] } else { $null }
Log '[STEP] 1/6 Resolve paths'
$cwd = Get-Location
if ($argsPath) {
    $basePath = (Resolve-Path -LiteralPath $argsPath -ErrorAction SilentlyContinue)
    if (-not $basePath) { ErrorExit "Provided path does not exist: $argsPath" }
    $basePath = $basePath.Path
    $searchBase = $basePath
    $testResultsPath = Join-Path $basePath 'TestResults'
    $coveragePath = Join-Path $basePath 'coverage-report'
}
else {
    $testsDir = Join-Path $cwd 'tests'
    if (-not (Test-Path $testsDir -PathType Container)) { ErrorExit "Could not find a 'tests' directory relative to current working directory." }
    $searchBase = (Resolve-Path $testsDir).Path
    $testResultsPath = Join-Path $testsDir 'TestResults'
    $docsDir = Join-Path $cwd 'docs'
    New-Directory $docsDir
    $coveragePath = Join-Path $docsDir 'coverage-report'
}
Log "[INFO] Search base path: $searchBase"
Log "[INFO] Test results path: $testResultsPath"
Log "[INFO] Coverage reports path: $coveragePath"

Log '[STEP] 2/6 Prepare output directories'
New-Directory $testResultsPath
New-Directory $coveragePath
Log '[INFO] Cleaning previous test results...'
Clear-Directory $testResultsPath
Log '[INFO] Cleaning previous coverage reports...'
Clear-Directory $coveragePath
Log '[OK] Cleanup completed'

Log '[STEP] 3/6 Discover test projects'
$testProjects = Get-ChildItem -LiteralPath $searchBase -Recurse -Filter '*.csproj' -File | Where-Object { -not ((($_.FullName -split '\\') -contains 'Setup') -or ($_.FullName -match '\\Setup\\')) }
if (-not $testProjects -or $testProjects.Count -eq 0) {
    Log '[WARN] No test projects found. Skipping test run.'
    Log '[STEP] 6/6 Done'
    Log '[SUCCESS] Test script completed'
    exit 0
}
Log "[INFO] Found $($testProjects.Count) test project(s)"

Log '[STEP] 4/6 Run tests with coverage collection'
foreach ($tp in $testProjects) {
    Log "[INFO] Running tests for project: $($tp.FullName)"
    Run { dotnet test "$($tp.FullName)" --collect:"XPlat Code Coverage;Format=json,lcov,cobertura" --results-directory "$testResultsPath" }
}

Log '[STEP] 5/6 Generate coverage report'
$reportsPattern = Join-Path $testResultsPath '**/coverage.cobertura.xml'
Run { reportgenerator "-reports:$reportsPattern" "-targetdir:$coveragePath" '-reporttypes:Html' }
Log "[SUCCESS] Coverage report generated in $coveragePath"

Log '[STEP] 6/6 Done'
Log '[SUCCESS] Test script completed'
exit 0