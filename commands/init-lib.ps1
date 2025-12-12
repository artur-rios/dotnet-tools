<#
.SYNOPSIS
  Scaffold a new .NET library repository structure.
.DESCRIPTION
  Creates a root folder (by name/path) with src, tests; generates .editorconfig, .gitignore,
  .wakatime-project, LICENSE (MIT), README.md; creates solution + class library project with NuGet metadata.

.USAGE
    dotnet-tools init-lib [--root <RootName|Path>] [--solution Name] [--project Name] [--author "Full Name"] \
                                                [--description "NuGet package description"] [--version 0.1.0]
.EXAMPLE
    dotnet-tools init-lib MyLib --author "Jane Doe" --description "My sample library" --version 0.1.0
#>

$ErrorActionPreference = 'Stop'

function Log($msg) { Write-Host $msg }
function ErrorExit($msg) { Log "[ERROR] $msg"; exit 1 }

function Show-InitUsage {
    Write-Host "Usage: dotnet-tools init-lib [--root <RootName|Path>] [--solution Name] [--project Name] [--author <Full Name>] [--description <NuGet description>] [--version 0.1.0] [--packageId <Id>] [--repositoryUrl <URL>] [--json <path>]"
    Write-Host "All flags are optional. When omitted, values are read from parameters/init-parameters.json or from the file provided via --json."
    exit 1
}

${CliArgs} = $args
if ($CliArgs -and $CliArgs[0] -in @('-h', '--help', 'help')) { Show-InitUsage }

$JsonPath = $null
$CliArgs = if ($CliArgs.Length -gt 0 -and $CliArgs[0] -eq 'init-lib') { $CliArgs[1..($CliArgs.Length - 1)] } else { $CliArgs }
$Root = $null
$Solution = $null
$Project = $null
$Author = $null
$Description = $null
$Version = $null

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
            '--company' { $Company = $val }
            '--description' { $Description = $val }
            '--version' { $Version = $val }
            '--packageId' { $PackageId = $val }
            '--repositoryUrl' { $RepositoryUrl = $val }
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
        '--company' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --company' }; $Company = $CliArgs[$i + 1]; $i += 2; continue }
        '--description' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --description' }; $Description = $CliArgs[$i + 1]; $i += 2; continue }
        '--version' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --version' }; $Version = $CliArgs[$i + 1]; $i += 2; continue }
        '--packageId' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --packageId' }; $PackageId = $CliArgs[$i + 1]; $i += 2; continue }
        '--repositoryUrl' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --repositoryUrl' }; $RepositoryUrl = $CliArgs[$i + 1]; $i += 2; continue }
        '--json' { if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --json' }; $JsonPath = $CliArgs[$i + 1]; $i += 2; continue }
        default { if ($token.StartsWith('--')) { ErrorExit "Unknown flag: $token" } else { ErrorExit "Positional arguments are no longer supported. Unexpected token: '$token'" } }
    }
}

if ($JsonPath) {
    # Ensure user did not pass additional flags together with --json
    $flagVars = @($Root, $Solution, $Project, $Author, $Company, $Description, $Version, $PackageId, $RepositoryUrl) | Where-Object { $_ }
    if ($flagVars.Count -gt 0) { ErrorExit 'Do not mix --json with other flags. Provide either a JSON file or flags, never both.' }
}

# Load parameters from JSON (either provided or default file), then apply flags overriding
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

# Validate required properties in parameters JSON
$requiredKeys = @('RootFolder', 'SolutionName', 'ProjectName', 'Author', 'Company', 'Description', 'PackageId', 'RepositoryUrl', 'PackageLicenseExpression', 'Version')
$missing = @()
foreach ($k in $requiredKeys) {
    $hasProp = $paramsJson.PSObject.Properties.Name -contains $k
    $val = if ($hasProp) { $paramsJson.$k } else { $null }
    if (-not $hasProp -or ([string]::IsNullOrWhiteSpace([string]$val))) { $missing += $k }
}
if ($missing.Count -gt 0) { ErrorExit ("Parameters JSON missing required properties: {0}" -f ($missing -join ', ')) }

# Apply JSON defaults for missing values
function Coalesce($curr, $jsonVal) { if ($curr) { return $curr } elseif ($jsonVal) { return $jsonVal } else { return $null } }
function JsonVal($obj, $name) {
    if ($null -ne $obj -and ($obj.PSObject.Properties.Name -contains $name)) { return $obj.$name }
    return $null
}
$Root = Coalesce $Root       (JsonVal $paramsJson 'RootFolder')
$Solution = Coalesce $Solution   (JsonVal $paramsJson 'SolutionName')
$Project = Coalesce $Project    (JsonVal $paramsJson 'ProjectName')
$Author = Coalesce $Author     (JsonVal $paramsJson 'Author')
$Company = Coalesce $Company    (JsonVal $paramsJson 'Company')
$Description = Coalesce $Description (JsonVal $paramsJson 'Description')
$Version = Coalesce $Version    (JsonVal $paramsJson 'Version')
$PackageId = Coalesce $PackageId  (JsonVal $paramsJson 'PackageId')
$RepositoryUrl = Coalesce $RepositoryUrl (JsonVal $paramsJson 'RepositoryUrl')

# Normalize & resolve intended path (allow relative)
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
if (-not $Company) { $Company = $Author }
if (-not $PackageId) { $PackageId = $Project }

Log '[INIT-LIB] Initializing scaffold...'
Log '[STEP] 1/9 Parse and resolve inputs'
Log "[INFO] root: $RootFull"
Log "[INFO] solution: $Solution"
Log "[INFO] project: $Project"
Log "[INFO] packageId: $PackageId"
Log "[INFO] author: $Author"
Log "[INFO] company: $Company"
Log "[INFO] version: $Version"
Log "[INFO] description: $Description"

Log '[STEP] 2/9 Create directory structure'
New-Item -ItemType Directory -Path $RootFull | Out-Null
$srcDir = Join-Path $RootFull 'src'
$testsDir = Join-Path $RootFull 'tests'
New-Item -ItemType Directory -Path $srcDir, $testsDir | Out-Null
Log '[OK] Created directories: src, tests'

# .wakatime-project
Set-Content -Path (Join-Path $RootFull '.wakatime-project') -Value $Project -Encoding UTF8
Log '[INFO] Wrote .wakatime-project'

# Render README.md from template
Log '[STEP] 5/9 Generate README from template'
$templateBaseRoot = Join-Path -Path $PSScriptRoot -ChildPath '..'
$templateBase = Join-Path -Path $templateBaseRoot -ChildPath 'templates'
try { $templateBase = (Resolve-Path -LiteralPath $templateBase -ErrorAction Stop).Path } catch { ErrorExit "Templates folder not found: $templateBase" }
$tplReadme = Join-Path $templateBase 'README.md.template'
if (-not (Test-Path -LiteralPath $tplReadme)) { ErrorExit "Missing required template: README.md.template" }
$readmeTemplate = (Get-Content -LiteralPath $tplReadme -Raw)
# Add versioning section after description
$versioningSection = @"


## Versioning

Semantic Versioning (SemVer). Breaking changes result in a new major version. New methods or non-breaking behavior
changes increment the minor version; fixes or tweaks increment the patch.
"@
$readmeTemplate = $readmeTemplate.Replace('__DESCRIPTION__', "__DESCRIPTION__$versioningSection")
$readmeRendered = $readmeTemplate.Replace('__SOLUTION_NAME__', $Solution).Replace('__PROJECT_NAME__', $Project).Replace('__DESCRIPTION__', $Description).Replace('__AUTHOR__', $Author)
Set-Content -Path (Join-Path $RootFull 'README.md') -Value $readmeRendered -Encoding UTF8
Log '[OK] README created from template'

# Use templates for solution, project, license (no inline generation for those)
Log '[STEP] 3/9 Validate templates'

# Validate required template files
$tplEditor = Join-Path $templateBase '.editorconfig.template'
$tplGit = Join-Path $templateBase '.gitignore.template'
$tplLicense = Join-Path $templateBase 'LICENSE.MIT.template'
$tplProj = Join-Path $templateBase 'project.nuget.csproj.template'
$tplSln = Join-Path $templateBase 'solution.sln.template'
$required = @($tplEditor, $tplGit, $tplLicense, $tplProj, $tplSln)
foreach ($f in $required) { if (-not (Test-Path -LiteralPath $f)) { ErrorExit "Missing required template: $(Split-Path -Leaf $f)" } }
Log '[OK] All template files present'

# Copy editorconfig & gitignore (already handled earlier but enforce no fallback)
Log '[STEP] 4/9 Copy template config files'
Copy-Item -LiteralPath $tplEditor -Destination (Join-Path $RootFull '.editorconfig') -Force
Copy-Item -LiteralPath $tplGit    -Destination (Join-Path $RootFull '.gitignore') -Force
Log '[OK] Config files copied'

# Render LICENSE from template
$licenseContent = (Get-Content -LiteralPath $tplLicense -Raw)
$year = (Get-Date).Year
$licenseContent = $licenseContent.Replace('__YEAR__', [string]$year).Replace('__AUTHOR__', $Author)
Set-Content -Path (Join-Path $RootFull 'LICENSE') -Value $licenseContent -Encoding UTF8
Log '[OK] LICENSE generated'

# Prepare project and solution in src (no project subfolder)
Log '[STEP] 6/9 Generate project and solution'
$csprojPath = Join-Path $srcDir "$Project.csproj"

# Repository URL (prefer provided/JSON value, else git remote)
$repoUrl = $RepositoryUrl
if (-not $repoUrl) { $repoUrl = (git remote get-url origin 2>$null) }
if (-not $repoUrl) { $repoUrl = '' }

# Render project csproj
$projTemplate = (Get-Content -LiteralPath $tplProj -Raw)
$projRendered = $projTemplate.Replace('__PACKAGE_ID__', $PackageId).Replace('__VERSION__', $Version).Replace('__AUTHOR__', $Author).Replace('__DESCRIPTION__', $Description).Replace('__REPOSITORY_URL__', $repoUrl)
$projRendered = $projRendered.Replace('__COMPANY__', $Company)
Set-Content -Path $csprojPath -Value $projRendered -Encoding UTF8
Log '[INFO] Project file created'

# Generate solution file from template with new project GUID
$solutionGuid = [Guid]::NewGuid().ToString().ToUpper()
$slnTemplate = (Get-Content -LiteralPath $tplSln -Raw)
$slnRendered = $slnTemplate.Replace('__PROJECT_NAME__', $Project).Replace('__PROJECT_GUID__', $solutionGuid).Replace('__SOLUTION_NAME__', $Solution)
# For init-lib, the project lives directly under src (no subfolder). Adjust the relative path in the solution.
$oldRelPath = "$Project\$Project.csproj"
$newRelPath = "$Project.csproj"
if ($slnRendered.Contains($oldRelPath)) { $slnRendered = $slnRendered.Replace($oldRelPath, $newRelPath) }
Set-Content -Path (Join-Path $srcDir "$Solution.sln") -Value $slnRendered -Encoding UTF8
Log '[INFO] Solution file created'

# Copy README next to project for NuGet packaging context
Log '[STEP] 8/9 Copy README next to project'
Copy-Item -Path (Join-Path $RootFull 'README.md') -Destination (Join-Path $srcDir 'README.md') -Force
Log '[OK] README copied to src'

# Create test project under tests
Log '[STEP] 7/9 Generate test project'
$tplProjTests = Join-Path $templateBase 'project.Tests.csproj.template'
if (-not (Test-Path -LiteralPath $tplProjTests)) { ErrorExit "Missing required template: project.Tests.csproj.template" }
$testsCsprojPath = Join-Path $testsDir ("$Project.Tests.csproj")
$projTestsTemplate = (Get-Content -LiteralPath $tplProjTests -Raw)
$projTestsRendered = $projTestsTemplate.Replace('__PROJECT_NAME__', $Project)
Set-Content -Path $testsCsprojPath -Value $projTestsRendered -Encoding UTF8
Log '[INFO] Test project file created'

Log '[STEP] 9/9 Done'
Log "[INFO] Solution path: $srcDir\$Solution.sln"
Log "[INFO] Project path:  $csprojPath"
Log '[SUCCESS] Scaffold complete'
Log "Next: cd '$RootFull'"
