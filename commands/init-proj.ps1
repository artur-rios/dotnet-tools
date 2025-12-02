<#
.SYNOPSIS
  Scaffold a single project folder with a minimal or NuGet-metadata csproj.
.DESCRIPTION
  Creates a directory named after the provided --name flag and places a generated
  <Name>.csproj inside. Two modes:
    --min   : Uses templates/project.minimal.csproj.template (default if no mode flag provided)
    --nuget : Uses templates/project.nuget.csproj.template but blanks all NuGet metadata values

.USAGE
  dotnet-tools init-proj --name MyProject [--min|--nuget]
.EXAMPLES
  dotnet-tools init-proj --name Utils            # minimal (default)
  dotnet-tools init-proj --name Utils --min      # explicit minimal
  dotnet-tools init-proj --name Package --nuget  # nuget template with empty metadata
.NOTES
  --name is mandatory. --min and --nuget are mutually exclusive. If both are supplied, error.
#>

$ErrorActionPreference = 'Stop'

function Log($m) { Write-Host $m }
function ErrorExit($m) { Log "[ERROR] $m"; exit 1 }
function ShowUsage {
    Write-Host "Usage: dotnet-tools init-proj --name <ProjectName> [--min|--nuget]"
    Write-Host "--name is required. Defaults to --min if neither --min nor --nuget supplied."
    exit 1
}

$CliArgs = $args
if ($CliArgs -and $CliArgs[0] -in @('-h', '--help', 'help')) { ShowUsage }

$ProjectName = $null
$ModeMin = $false
$ModeNuget = $false

$i = 0
while ($i -lt $CliArgs.Length) {
    $t = $CliArgs[$i]
    if ($t -match '^--name=') {
        $ProjectName = $t.Substring(7)
        $i++; continue
    }
    switch ($t) {
        '--name' {
            if ($i + 1 -ge $CliArgs.Length) { ErrorExit 'Missing value for --name' }
            $ProjectName = $CliArgs[$i + 1]; $i += 2; continue
        }
        '--min' { $ModeMin = $true; $i++; continue }
        '--nuget' { $ModeNuget = $true; $i++; continue }
        default { ErrorExit "Unknown flag: $t" }
    }
}

if (-not $ProjectName) { ErrorExit '--name is mandatory' }
if ($ModeMin -and $ModeNuget) { ErrorExit 'Do not specify both --min and --nuget' }
if (-not $ModeMin -and -not $ModeNuget) { $ModeMin = $true }

# Resolve target path
$TargetDirFull = [System.IO.Path]::GetFullPath($ProjectName)
if (Test-Path -LiteralPath $TargetDirFull) { ErrorExit "Target directory already exists: $TargetDirFull" }

# Templates folder
$templateBaseRoot = Join-Path -Path $PSScriptRoot -ChildPath '..'
$templateBase = Join-Path -Path $templateBaseRoot -ChildPath 'templates'
try { $templateBase = (Resolve-Path -LiteralPath $templateBase -ErrorAction Stop).Path } catch { ErrorExit "Templates folder not found: $templateBase" }

$tplMin = Join-Path $templateBase 'project.minimal.csproj.template'
$tplNuget = Join-Path $templateBase 'project.nuget.csproj.template'
foreach ($f in @($tplMin, $tplNuget)) { if (-not (Test-Path -LiteralPath $f)) { ErrorExit "Missing required template: $(Split-Path -Leaf $f)" } }

Log '[INIT-PROJ] Creating project folder'
New-Item -ItemType Directory -Path $TargetDirFull | Out-Null

$csprojPath = Join-Path $TargetDirFull ("$ProjectName.csproj")

if ($ModeMin) {
    Log '[MODE] minimal'
    $content = Get-Content -LiteralPath $tplMin -Raw
    Set-Content -Path $csprojPath -Value $content -Encoding UTF8
}
else {
    Log '[MODE] nuget (blank metadata)'
    $content = Get-Content -LiteralPath $tplNuget -Raw
    # Replace placeholder tokens with empty strings
    $content = $content.Replace('__PACKAGE_ID__', '').Replace('__VERSION__', '').Replace('__AUTHOR__', '').Replace('__DESCRIPTION__', '').Replace('__REPOSITORY_URL__', '').Replace('__COMPANY__', '')
    # Blank fixed metadata values that may remain
    $tagsToBlank = @('PackageLicenseExpression', 'PackageReadmeFile', 'Authors', 'Company', 'Description', 'PackageId', 'Version', 'RepositoryUrl')
    foreach ($tag in $tagsToBlank) {
        $content = [regex]::Replace($content, "<$tag>.*?</$tag>", "<$tag></$tag>", 'Singleline')
    }
    Set-Content -Path $csprojPath -Value $content -Encoding UTF8
}

Log "[OK] Created: $csprojPath"
Log '[DONE] Project scaffold complete'
Log "Next: cd '$TargetDirFull'"
