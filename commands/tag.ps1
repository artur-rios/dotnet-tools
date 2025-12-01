$ErrorActionPreference = 'Stop'
function Log($msg) { Write-Host $msg }
function ErrorExit($msg) { Log "[ERROR] $msg"; exit 1 }

$argv = $args
# Defensively ignore a stray subcommand token forwarded by the wrapper
$argv = @($argv | Where-Object { $_ -ne 'tag' })

function Get-Flags([string[]]$argv) {
    $push = ($argv -contains '--push')
    $remote = 'origin'
    for ($i = 0; $i -lt $argv.Count; $i++) { if ($argv[$i] -eq '--remote' -and $i + 1 -lt $argv.Count) { $remote = $argv[$i + 1] } }
    return , @($push, $remote)
}

function Resolve-BasePath([string[]]$argv) {
    $positional = $null
    for ($i = 0; $i -lt $argv.Count; $i++) {
        $a = $argv[$i]
        if ($a -eq '--remote') { $i++; continue }
        if ($a.StartsWith('-')) { continue }
        $positional = $a; break
    }
    if ($positional) {
        $p = Get-Item -LiteralPath $positional -ErrorAction SilentlyContinue
        if (-not $p -or -not $p.PSIsContainer) { ErrorExit "Provided path does not exist or is not a directory: '$positional'" }
        return $p.FullName
    }
    $default = Join-Path (Get-Location) 'src'
    if (-not (Test-Path $default -PathType Container)) { ErrorExit "No path argument provided and 'src' directory was not found in current working directory." }
    return (Resolve-Path $default).Path
}

function Find-SingleCsproj([string]$base) {
    $csprojs = Get-ChildItem -LiteralPath $base -Recurse -Filter '*.csproj' -File
    if (-not $csprojs) { ErrorExit "No .csproj file found under '$base'." }
    if ($csprojs.Count -gt 1) {
        $names = ($csprojs | Select-Object -First 5 | Select-Object -ExpandProperty Name)
        $list = ($names -join ', ')
        if ($csprojs.Count -gt 5) { $list = "$list..." }
        ErrorExit "Multiple .csproj files found. Please provide a more specific path. Found: $list"
    }
    return $csprojs[0].FullName
}

function Read-Version([string]$csproj) {
    try {
        [xml]$xml = Get-Content -LiteralPath $csproj -Raw
        $version = $null
        foreach ($pg in $xml.Project.PropertyGroup) {
            if ($pg.Version) { $version = $pg.Version; break }
        }
        if (-not $version) {
            $all = $xml.SelectNodes('//*')
            foreach ($node in $all) { if ($node.Name -like '*Version' -and $node.InnerText) { $version = $node.InnerText.Trim(); break } }
        }
        if ($version) { return $version }
        ErrorExit "Could not find <Version> property in '$csproj'."
    }
    catch {
        ErrorExit "Failed to parse csproj '$csproj': $($_.Exception.Message)"
    }
}

function Run($cmd, $info) { if ($info) { Log "[INFO] $info" } & $cmd; if ($LASTEXITCODE -ne 0) { ErrorExit "Command failed with exit code $LASTEXITCODE." } }

function New-GitTag([string]$version) {
    $tag = "v$version"
    # Quietly verify fully-qualified tag ref to avoid stderr noise under ErrorActionPreference=Stop
    & git rev-parse --quiet --verify "refs/tags/$tag" *> $null
    if ($LASTEXITCODE -eq 0) { ErrorExit "Tag '$tag' already exists." }
    Run { git tag -a $tag -m "Release $version" } "Creating git tag $tag"
    return $tag
}

function Push-GitTag([string]$tag, [string]$remote) { Run { git push $remote $tag } "Pushing git tag $tag to remote '$remote'" }

Log '[INIT] Tagging...'
Log '[STEP] 1/5 Parse flags and resolve base path'
$flags = Get-Flags $argv
$push = $flags[0]; $remote = $flags[1]
$base = Resolve-BasePath $argv
Log "[INFO] Base path: '$base'"
Log "[INFO] push: $push"
Log "[INFO] remote: $remote"

Log '[STEP] 2/5 Locate project file (.csproj)'
$csproj = Find-SingleCsproj $base
Log "[INFO] Project file: $csproj"

Log '[STEP] 3/5 Read version from project'
$version = Read-Version $csproj
Log "[INFO] Version: $version"

Log '[STEP] 4/5 Create git tag'
$tagName = New-GitTag $version

if ($push) {
    Log '[STEP] 5/5 Push tag to remote'
    Push-GitTag $tagName $remote
    Log '[SUCCESS] Tag created and pushed'
}
else {
    Log '[STEP] 5/5 Done'
    Log '[SUCCESS] Tag created'
}
exit 0