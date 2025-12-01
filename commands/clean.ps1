$ErrorActionPreference = 'Stop'
function Log($msg) { Write-Host $msg }
function ErrorExit($msg) { Log "[ERROR] $msg"; exit 1 }

$argv = $args
# In some shells/wrappers, the subcommand name (e.g., "clean") may be forwarded
# as the first argument unexpectedly. Filter it out defensively.
$argv = @($argv | Where-Object { $_ -ne 'clean' })

function Resolve-TargetDir([string[]]$argv) {
    if ($argv.Count -gt 0) {
        $raw = $argv[0].Trim('"').Trim("'")
        if ($raw -eq '.' -or $raw -eq './') { $path = (Get-Location).Path } else { $path = $raw }
        $p = Resolve-Path -LiteralPath $path -ErrorAction SilentlyContinue
        if (-not $p) { ErrorExit "Provided path does not exist or is not a directory: '$path'" }
        $dir = (Get-Item -LiteralPath $p).FullName
        if (-not (Test-Path $dir -PathType Container)) { ErrorExit "Provided path does not exist or is not a directory: '$dir'" }
        return $dir
    }
    $candidate = Join-Path (Get-Location) 'src'
    if (-not (Test-Path $candidate -PathType Container)) {
        ErrorExit "No path argument provided and 'src' directory was not found in current working directory.
Current working directory: '$(Get-Location)'
Usage: dotnet-tools clean [<path-to-src>]" 
    }
    return (Resolve-Path $candidate).Path
}

function Remove-DirTree([string]$path) {
    if (Test-Path $path -PathType Container) {
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
            Log "[OK] Removed directory: $path"
        }
        catch {
            Log "[WARN] Failed to remove $($path): $($_.Exception.Message)"
        }
    }
}

$target = Resolve-TargetDir $argv
Log '[INIT] Cleaning...'
Log '[STEP] 1/3 Resolve target path'
Log "[INFO] Target path: '$target'"
if (-not (Test-Path $target -PathType Container)) {
    ErrorExit "Target directory not found: '$target'.
Usage: dotnet-tools clean [<path-to-src>]
Hint: provide an explicit path or ensure ./src exists." 
}

Log '[STEP] 2/3 Scan and remove bin/ and obj/ folders'
$removed = 0
Get-ChildItem -LiteralPath $target -Recurse -Directory | ForEach-Object {
    if ($_.Name -in @('bin', 'obj')) {
        $parent = Split-Path $_.FullName -Leaf
        Log "[INFO] Cleaning $($_.Name) folder on project $parent"
        Remove-DirTree $_.FullName
        $removed += 1
    }
}
Log "[OK] Cleaned $removed folders"
Log '[STEP] 3/3 Done'
Log '[SUCCESS] Clean complete'
exit 0