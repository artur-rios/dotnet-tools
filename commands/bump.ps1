$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'
function Write-Log($msg) { Write-Information $msg }
function Stop-Execution($msg) { Write-Error $msg; throw $msg }

# Defensively ignore a stray subcommand token forwarded by the wrapper
$args = @($args | Where-Object { $_ -ne 'bump' })

if ($args.Count -lt 1) { Write-Information 'Usage: bump <version|--major|--minor|--patch> [<csproj-or-directory>]'; throw 'Missing required arguments' }
$arg = $args[0]

function Resolve-Csproj([string[]]$argv) {
    if ($argv.Count -ge 2) {
        $supplied = $argv[1]
        $item = Get-Item -LiteralPath $supplied -ErrorAction SilentlyContinue
        if (-not $item) { Stop-Execution "Path not found: $supplied" }
        if ($item.PSIsContainer) {
            $candidates = Get-ChildItem -LiteralPath $item.FullName -Filter '*.csproj' -File | Sort-Object Name
            if (-not $candidates) { Stop-Execution "No .csproj file found in directory: $supplied" }
            if ($candidates.Count -gt 1) { $names = ($candidates | Select-Object -ExpandProperty Name) -join ', '; Stop-Execution "Multiple .csproj files found in directory (choose one explicitly): $names" }
            return $candidates[0].FullName
        }
        else {
            if ($item.Extension.ToLowerInvariant() -ne '.csproj') { Stop-Execution "File is not a .csproj: $supplied" }
            return $item.FullName
        }
    }
    else {
        $searchDir = Join-Path (Get-Location) 'src'
        if (-not (Test-Path $searchDir -PathType Container)) { Stop-Execution "Auto-discovery failed: directory does not exist: $searchDir" }
        $candidates = Get-ChildItem -LiteralPath $searchDir -Filter '*.csproj' -File | Sort-Object Name
        if (-not $candidates) { Stop-Execution "Auto-discovery found no .csproj under: $searchDir" }
        if ($candidates.Count -gt 1) { $names = ($candidates | Select-Object -ExpandProperty Name) -join ', '; Stop-Execution "Auto-discovery found multiple .csproj files under $searchDir (specify one explicitly): $names" }
        return $candidates[0].FullName
    }
}

function Get-CurrentVersion([string]$csproj) {
    $raw = Get-Content -LiteralPath $csproj -Raw -Encoding UTF8
    $m = [regex]::Match($raw, '<Version>(\d+\.\d+\.\d+)</Version>')
    if ($m.Success) { return $m.Groups[1].Value } else { return $null }
}

function Get-TargetVersion([string]$arg, [string]$current) {
    if ($arg -in @('--major', '--minor', '--patch') -and -not $current) { Stop-Execution "$arg requires existing version (<Version> tag missing in csproj)" }
    if ($arg -eq '--major') {
        try {
            $v = [Version]$current
            return ('{0}.0.0' -f ($v.Major + 1))
        }
        catch {
            $parts = $current -split '\.'
            if ($parts.Count -ge 1) { return ('{0}.0.0' -f ([int]$parts[0] + 1)) }
            Stop-Execution "Invalid current version: $current"
        }
    }
    elseif ($arg -eq '--minor') {
        try {
            $v = [Version]$current
            return ('{0}.{1}.0' -f $v.Major, ($v.Minor + 1))
        }
        catch {
            $parts = $current -split '\.'
            if ($parts.Count -ge 2) { return ('{0}.{1}.0' -f ([int]$parts[0]), ([int]$parts[1] + 1)) }
            Stop-Execution "Invalid current version: $current"
        }
    }
    elseif ($arg -eq '--patch') {
        try {
            $v = [Version]$current
            return ('{0}.{1}.{2}' -f $v.Major, $v.Minor, ($v.Build + 1))
        }
        catch {
            $parts = $current -split '\.'
            if ($parts.Count -ge 3) { return ('{0}.{1}.{2}' -f ([int]$parts[0]), ([int]$parts[1]), ([int]$parts[2] + 1)) }
            Stop-Execution "Invalid current version: $current"
        }
    }
    else {
        return $arg
    }
}

function Test-Version([string]$v) { if (-not ($v -match '^[0-9]+\.[0-9]+\.[0-9]+$')) { Stop-Execution "Invalid version format: $v" } }

function New-Backup([string]$csproj) {
    $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
    $backup = "$csproj.bak.$timestamp"
    Copy-Item -LiteralPath $csproj -Destination $backup -Force
    return $backup
}

function Set-VersionXml([string]$raw, [string]$version) {
    try {
        [xml]$xml = $raw
        $pg = $null
        foreach ($grp in $xml.Project.PropertyGroup) { $pg = $grp; if ($pg) { break } }
        if (-not $pg) {
            $pg = $xml.CreateElement('PropertyGroup')
            [void]$xml.Project.AppendChild($pg)
        }
        $verNode = $null
        foreach ($node in $pg.ChildNodes) { if ($node.Name -eq 'Version') { $verNode = $node; break } }
        if (-not $verNode) {
            $verNode = $xml.CreateElement('Version')
            [void]$pg.AppendChild($verNode)
        }
        $verNode.InnerText = $version

        # Pretty print XML to preserve indentation
        $settings = New-Object System.Xml.XmlWriterSettings
        $settings.Indent = $true
        $settings.NewLineChars = "`n"
        $settings.NewLineHandling = [System.Xml.NewLineHandling]::Replace
        $settings.OmitXmlDeclaration = $true
        $sw = New-Object System.IO.StringWriter
        $writer = [System.Xml.XmlWriter]::Create($sw, $settings)
        $xml.Save($writer)
        $writer.Flush(); $writer.Close()
        return $sw.ToString()
    }
    catch {
        Write-Log ("[WARN] XML parse/update failed: {0}" -f $_.Exception.Message)
        # Fallback: minimally replace inner text using regex while preserving tags
        $pattern = [regex] '(<Version>)([^<]*)(</Version>)'
        if ($pattern.IsMatch($raw)) { return ($pattern.Replace($raw, ('$1{0}$3' -f $version), 1)) }
        return ($raw + "`n    <Version>$version</Version>`n")
    }
}

function Test-VersionApplied([string]$csproj, [string]$version) {
    try {
        [xml]$xml = Get-Content -LiteralPath $csproj -Raw -Encoding UTF8
        $found = $null
        foreach ($pg in $xml.Project.PropertyGroup) {
            foreach ($node in $pg.ChildNodes) { if ($node.Name -eq 'Version') { $found = $node.InnerText; break } }
            if ($found) { break }
        }
        return ($found -eq $version)
    }
    catch { return $false }
}

Write-Log '[STEP] 1/9 Resolve project file'
$csproj = Resolve-Csproj $args
if (-not (Test-Path $csproj -PathType Leaf)) { Stop-Execution "Project file not found: $csproj" }
Write-Log "[INFO] Target csproj: $csproj"

Write-Log '[STEP] 2/9 Read current version'
$current = Get-CurrentVersion $csproj
if ($current) { Write-Log "[INFO] Current version detected: $current" } else { Write-Log '[INFO] No existing <Version> tag detected.' }

Write-Log '[STEP] 3/9 Determine target version'
$target = Get-TargetVersion $arg $current
if (-not $target) { Stop-Execution 'Failed to compute target version' }
Write-Log "[INFO] Target version: $target"

Write-Log '[STEP] 4/9 Validate version format'
Test-Version $target
Write-Log '[OK] Format validated'

Write-Log '[STEP] 5/9 Create backup'
$backup = New-Backup $csproj
Write-Log "[OK] Backup created: $backup"

Write-Log '[STEP] 6/9 Update csproj (in-place, preserving formatting)'
$raw = Get-Content -LiteralPath $csproj -Raw -Encoding UTF8
$updated = Set-VersionXml $raw $target
Set-Content -LiteralPath $csproj -Value $updated -Encoding UTF8

Write-Log '[STEP] 7/9 Verify change'
$matched = Test-VersionApplied $csproj $target
if ($matched) { Write-Log '[OK] Version tag verified in csproj' } else { Write-Log '[WARN] Could not verify updated version tag.' }

Write-Log '[STEP] 8/9 Cleanup backup (if verified)'
if ($matched) {
    try { Remove-Item -LiteralPath $backup -Force; Write-Log '[OK] Backup removed' } catch { Write-Log "[WARN] Backup not deleted: $backup" }
}
else {
    Write-Log "[INFO] Backup retained: $backup"
}

Write-Log '[STEP] 9/9 Done'
Write-Log "[SUCCESS] Version bump complete: $target"