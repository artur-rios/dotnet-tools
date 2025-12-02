<#
.SYNOPSIS
  Scaffold a minimal .NET library repository (no NuGet metadata, no test project).
.DESCRIPTION
  Creates a root folder (by name/path) with src, docs, tests; generates .editorconfig, .gitignore,
  .wakatime-project, LICENSE (MIT), README.md; creates solution + minimal class library project
  with no NuGet packaging metadata. Tests folder contains only a .gitkeep.

.USAGE
  dotnet-tools init-min [--root <RootName|Path>] [--solution Name] [--project Name] [--author "Full Name"] \
                        [--description "Project description"] [--json path/to/params.json]
.EXAMPLE
  dotnet-tools init-min --root MyLib --solution MyLib --project MyLib --author "Jane Doe" --description "My library"
#>

$ErrorActionPreference = 'Stop'

function Log($msg) { Write-Host $msg }
function ErrorExit($msg) { Log "[ERROR] $msg"; exit 1 }

function Show-InitMinUsage {
    Write-Host "Usage: dotnet-tools init-min [--root <RootName|Path>] [--solution Name] [--project Name] [--author <Full Name>] [--description <Description>] [--json path/to/params.json]"
    Write-Host "All flags are optional. When omitted, values are read from parameters/init-parameters.json or from the file provided via --json."
    exit 1
}

${CliArgs} = $args
if ($CliArgs -and $CliArgs[0] -in @('-h', '--help', 'help')) { Show-InitMinUsage }

$CliArgs = if ($CliArgs.Length -gt 0 -and $CliArgs[0] -eq 'init-min') { $CliArgs[1..($CliArgs.Length - 1)] } else { $CliArgs }
$JsonPath = $null
$Root = $null
$Solution = $null
$Project = $null
$Author = $null
$Description = $null

$i = 0
while ($i -lt $CliArgs.Length) {
    $token = $CliArgs[$i]
    if ($token -match '^--[^=]+=') {
        $parts = $token.Split('=', 2)
        $flag = $parts[0]
        $val = $parts[1]
        switch ($flag) {
            '--root' { $Root = $val }
            '--solution' { $Solution = $val }
            '--project' { $Project = $val }
            '--author' { $Author = $val }
            '--description' { $Description = $val }
            '--json' { $JsonPath = $val }
            default { ErrorExit "Unknown flag: $flag" }
        }
        $i++; continue
    }
    switch ($token) {
        '--root' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --root' }; $Root = $CliArgs[$i + 1]; $i += 2; continue }
        '--solution' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --solution' }; $Solution = $CliArgs[$i + 1]; $i += 2; continue }
        '--project' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --project' }; $Project = $CliArgs[$i + 1]; $i += 2; continue }
        '--author' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --author' }; $Author = $CliArgs[$i + 1]; $i += 2; continue }
        '--description' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --description' }; $Description = $CliArgs[$i + 1]; $i += 2; continue }
        '--json' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --json' }; $JsonPath = $CliArgs[$i + 1]; $i += 2; continue }
        default { if ($token.StartsWith('--')) { ErrorExit "Unknown flag: $token" } else { ErrorExit "Positional arguments are not supported. Unexpected token: '$token'" } }
    }
}

# Load parameters from JSON (either provided or default file). Do not mix with flags.
if ($JsonPath) {
    $flagVars = @($Root, $Solution, $Project, $Author, $Description) | Where-Object { $_ }
    if ($flagVars.Count -gt 0) { ErrorExit 'Do not mix --json with other flags. Provide either a JSON file or flags, never both.' }
}

$paramsJson = $null
$defaultJsonPathRoot = Join-Path -Path $PSScriptRoot -ChildPath '..'
$defaultJsonPathParams = Join-Path -Path $defaultJsonPathRoot -ChildPath 'parameters'
$defaultJsonPath = Join-Path -Path $defaultJsonPathParams -ChildPath 'init-parameters.json'
if ($JsonPath) {
    $resolvedJson = Resolve-Path -LiteralPath $JsonPath -ErrorAction SilentlyContinue
    if (-not $resolvedJson) { ErrorExit "JSON file not found: $JsonPath" }
    try { $paramsJson = (Get-Content -LiteralPath $resolvedJson.Path -Raw | ConvertFrom-Json) } catch { ErrorExit "Failed to parse JSON: $JsonPath" }
}
else {
    if (-not (Test-Path -LiteralPath $defaultJsonPath)) { ErrorExit "Default parameters JSON not found at: $defaultJsonPath" }
    try { $paramsJson = (Get-Content -LiteralPath $defaultJsonPath -Raw | ConvertFrom-Json) } catch { ErrorExit "Failed to parse default parameters JSON: $defaultJsonPath" }
}

# Validate only the minimal required properties when using JSON
$requiredKeys = @('RootFolder', 'SolutionName', 'ProjectName', 'Author', 'Description')
$missing = @()
foreach ($k in $requiredKeys) {
    $hasProp = $paramsJson.PSObject.Properties.Name -contains $k
    $val = if ($hasProp) { $paramsJson.$k } else { $null }
    if (-not $hasProp -or ([string]::IsNullOrWhiteSpace([string]$val))) { $missing += $k }
}
if ($missing.Count -gt 0) { ErrorExit ("Parameters JSON missing required properties: {0}" -f ($missing -join ', ')) }

# Apply JSON defaults for missing flag values
function Coalesce($curr, $jsonVal) { if ($curr) { return $curr } elseif ($jsonVal) { return $jsonVal } else { return $null } }
function JsonVal($obj, $name) {
    if ($null -ne $obj -and ($obj.PSObject.Properties.Name -contains $name)) { return $obj.$name }
    return $null
}
$Root = Coalesce $Root (JsonVal $paramsJson 'RootFolder')
$Solution = Coalesce $Solution (JsonVal $paramsJson 'SolutionName')
$Project = Coalesce $Project (JsonVal $paramsJson 'ProjectName')
$Author = Coalesce $Author (JsonVal $paramsJson 'Author')
$Description = Coalesce $Description (JsonVal $paramsJson 'Description')

# Resolve and validate target path
$RootPath = Resolve-Path -LiteralPath $Root -ErrorAction SilentlyContinue
if ($RootPath) { ErrorExit "Target path already exists: $RootPath" }
$RootFull = [System.IO.Path]::GetFullPath($Root)

if (-not $Solution) { $Solution = [System.IO.Path]::GetFileName($RootFull) }
if (-not $Project) { $Project = $Solution }
if (-not $Author) {
    $Author = $env:GIT_AUTHOR_NAME
    if ([string]::IsNullOrWhiteSpace($Author)) { $Author = $env:USER }
    if ([string]::IsNullOrWhiteSpace($Author)) { $Author = $env:USERNAME }
    if ([string]::IsNullOrWhiteSpace($Author)) { $Author = 'Unknown Author' }
}
if (-not $Description) { $Description = "$Project library" }

Log '[INIT-MIN] Initializing minimal scaffold...'
Log '[STEP] 1/7 Parse and resolve inputs'
Log "[INFO] root: $RootFull"
Log "[INFO] solution: $Solution"
Log "[INFO] project: $Project"
Log "[INFO] author: $Author"
Log "[INFO] description: $Description"

Log '[STEP] 2/7 Create directory structure'
New-Item -ItemType Directory -Path $RootFull | Out-Null
$srcDir = Join-Path $RootFull 'src'
$docsDir = Join-Path $RootFull 'docs'
$testsDir = Join-Path $RootFull 'tests'
New-Item -ItemType Directory -Path $srcDir, $docsDir, $testsDir | Out-Null
Set-Content -Path (Join-Path $docsDir '.gitkeep') -Value '' -Encoding UTF8
Set-Content -Path (Join-Path $testsDir '.gitkeep') -Value '' -Encoding UTF8
Log '[OK] Created directories: src, docs, tests (with .gitkeep)'

# .wakatime-project
Set-Content -Path (Join-Path $RootFull '.wakatime-project') -Value $Project -Encoding UTF8
Log '[INFO] Wrote .wakatime-project'

# README.md
$readme = "# $Solution`n`n$Description`n"
Log '[STEP] 3/7 Generate README'
Set-Content -Path (Join-Path $RootFull 'README.md') -Value $readme -Encoding UTF8
Log '[OK] README created'

# Locate templates
$templateBaseRoot = Join-Path -Path $PSScriptRoot -ChildPath '..'
$templateBase = Join-Path -Path $templateBaseRoot -ChildPath 'templates'
Log '[STEP] 4/7 Validate templates'
try { $templateBase = (Resolve-Path -LiteralPath $templateBase -ErrorAction Stop).Path } catch { ErrorExit "Templates folder not found: $templateBase" }

$tplEditor = Join-Path $templateBase '.editorconfig.template'
$tplGit = Join-Path $templateBase '.gitignore.template'
$tplLicense = Join-Path $templateBase 'LICENSE.MIT.template'
$tplProjMin = Join-Path $templateBase 'project.minimal.csproj.template'
$tplSln = Join-Path $templateBase 'solution.sln.template'
$required = @($tplEditor, $tplGit, $tplLicense, $tplProjMin, $tplSln)
foreach ($f in $required) { if (-not (Test-Path -LiteralPath $f)) { ErrorExit "Missing required template: $(Split-Path -Leaf $f)" } }
Log '[OK] All template files present'

# Copy editorconfig & gitignore
Log '[STEP] 5/7 Copy template config files'
Copy-Item -LiteralPath $tplEditor -Destination (Join-Path $RootFull '.editorconfig') -Force
Copy-Item -LiteralPath $tplGit    -Destination (Join-Path $RootFull '.gitignore') -Force
Log '[OK] Config files copied'

# Render LICENSE from template
$licenseContent = (Get-Content -LiteralPath $tplLicense -Raw)
$year = (Get-Date).Year
$licenseContent = $licenseContent.Replace('__YEAR__', [string]$year).Replace('__AUTHOR__', $Author)
Set-Content -Path (Join-Path $RootFull 'LICENSE') -Value $licenseContent -Encoding UTF8
Log '[OK] LICENSE generated'

# Project and solution (no NuGet metadata)
Log '[STEP] 6/7 Generate project and solution'
# Create project folder under src and place csproj inside it
$projectDir = Join-Path $srcDir $Project
if (-not (Test-Path -LiteralPath $projectDir)) { New-Item -ItemType Directory -Path $projectDir | Out-Null }
$csprojPath = Join-Path $projectDir ("$Project.csproj")
$projTemplate = (Get-Content -LiteralPath $tplProjMin -Raw)
Set-Content -Path $csprojPath -Value $projTemplate -Encoding UTF8
Log '[INFO] Project file created under src/<Project>/'

$solutionGuid = [Guid]::NewGuid().ToString().ToUpper()
$slnTemplate = (Get-Content -LiteralPath $tplSln -Raw)
$slnRendered = $slnTemplate.Replace('__PROJECT_NAME__', $Project).Replace('__PROJECT_GUID__', $solutionGuid).Replace('__SOLUTION_NAME__', $Solution)
Set-Content -Path (Join-Path $srcDir "$Solution.sln") -Value $slnRendered -Encoding UTF8
Log '[INFO] Solution file created'

# Copy README next to project for convenience
Copy-Item -Path (Join-Path $RootFull 'README.md') -Destination (Join-Path $srcDir 'README.md') -Force
Log '[OK] README copied to src'

Log '[STEP] 7/7 Done'
Log "[INFO] Solution path: $srcDir\$Solution.sln"
Log "[INFO] Project path:  $csprojPath"
Log '[SUCCESS] Minimal scaffold complete'
Log "Next: cd '$RootFull'"
