$ErrorActionPreference = 'Stop'
function Log($msg) { Write-Host $msg }
function ErrorExit($msg) { Log "[ERROR] $msg"; exit 1 }

$argv = $args

$noRestore = ($argv -contains '--no-restore' -or $argv -contains '--noRestore')
$solutionName = $null
$configuration = $null
for ($i = 0; $i -lt $argv.Count; $i++) {
    if ($argv[$i] -eq '--solution' -and $i + 1 -lt $argv.Count) { $solutionName = $argv[$i + 1] }
    if ($argv[$i] -eq '--configuration' -and $i + 1 -lt $argv.Count) { $configuration = $argv[$i + 1] }
}
if ($configuration -and ($configuration -ne 'Debug' -and $configuration -ne 'Release')) { ErrorExit "--configuration must be either 'Debug' or 'Release'" }

$skipNext = $false
$target = $null
for ($i = 0; $i -lt $argv.Count; $i++) {
    if ($skipNext) { $skipNext = $false; continue }
    if ($argv[$i] -in @('--solution', '--configuration')) { $skipNext = $true; continue }
    if ($argv[$i].StartsWith('-')) { continue }
    if ($argv[$i].ToLower() -eq 'build') { continue }
    $candidate = Resolve-Path -LiteralPath $argv[$i] -ErrorAction SilentlyContinue
    if (-not $candidate) { ErrorExit "Target path not found: '$($argv[$i])'." }
    $target = (Get-Item -LiteralPath $candidate).FullName
    break
}
if (-not $target) {
    $defaultSrc = Join-Path (Get-Location) 'src'
    if (-not (Test-Path $defaultSrc)) { ErrorExit "No 'src' folder found in the current working directory. Specify a path or run from a directory containing 'src'." }
    $target = (Resolve-Path $defaultSrc).Path
}

function Run($cmd, $info) { if ($info) { Log "[INFO] $info" } & $cmd; if ($LASTEXITCODE -ne 0) { ErrorExit "Command failed with exit code $LASTEXITCODE." } }

function Get-Solution([string]$base, [string]$name) {
    $solutions = Get-ChildItem -LiteralPath $base -Filter '*.sln' -File
    if ($name) {
        $candidate = Join-Path $base $name
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
        $match = $solutions | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($match) { return $match.FullName }
        ErrorExit "Specified solution '$name' was not found under '$base'."
    }
    if (-not $solutions) { ErrorExit "No solution (.sln) found under the target directory." }
    if ($solutions.Count -gt 1) {
        $names = ($solutions | Select-Object -ExpandProperty Name) -join ', '
        ErrorExit ("Multiple solutions found under the target directory. Please specify one with --solution <name.sln>. Found: $names")
    }
    return $solutions[0].FullName
}

Log '[INIT] Building...'
Log '[STEP] 1/4 Parse flags and arguments'
Log "[INFO] no_restore: $noRestore"
$solInfo = if ([string]::IsNullOrEmpty($solutionName)) { '(auto)' } else { $solutionName }
Log "[INFO] solution: $solInfo"
$cfgInfo = if ([string]::IsNullOrEmpty($configuration)) { '(Debug,Release)' } else { $configuration }
Log "[INFO] configuration: $cfgInfo"

Log '[STEP] 2/4 Resolve target path'
Log "[INFO] Target path: '$target'"
if (-not (Test-Path $target)) { ErrorExit "Target path not found: '$target'." }

Log '[STEP] 3/4 Find solution at target path'
$solution = Get-Solution $target $solutionName
Log "[INFO] Solution detected: $(Split-Path $solution -Leaf)"

Log '[STEP] 4/4 Restore (optional) and build solution'
if (-not $noRestore) { Run { dotnet restore "$solution" } "Restoring solution: $(Split-Path $solution -Leaf)" }

$configs = @()
if ($configuration) { $configs = @($configuration) } else { $configs = @('Debug', 'Release') }
foreach ($cfg in $configs) {
    $buildArgs = @('build', $solution, '-c', $cfg)
    if ($noRestore) { $buildArgs += '--no-restore' }
    Run { dotnet @buildArgs } "Building solution: $(Split-Path $solution -Leaf) (Configuration: $cfg)"
}

Log '[SUCCESS] Build complete'
exit 0