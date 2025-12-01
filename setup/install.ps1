$ErrorActionPreference = 'Stop'

param(
  [string]$Target
)

function Log($m) { Write-Host $m }
function ErrorExit($m) { Write-Host "[ERROR] $m"; exit 1 }

function Resolve-WriteablePath() {
  $pathDirs = @()
  if ($env:Path) { $pathDirs = ($env:Path -split ';') | Where-Object { $_ -and (Test-Path $_ -PathType Container) } }

  foreach ($d in $pathDirs) {
    try {
      $test = Join-Path $d (".__" + [System.IO.Path]::GetRandomFileName())
      New-Item -ItemType File -Path $test -Force -ErrorAction Stop | Out-Null
      Remove-Item -LiteralPath $test -Force -ErrorAction SilentlyContinue
      return $d
    }
    catch {}
  }

  $fallback = Join-Path $HOME 'bin'
  if (-not (Test-Path $fallback -PathType Container)) { New-Item -ItemType Directory -Force -Path $fallback | Out-Null }
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not ($userPath -split ';' | Where-Object { $_ -eq $fallback })) {
    Log "[INFO] Adding '$fallback' to User PATH"
    [Environment]::SetEnvironmentVariable('Path', ($userPath.TrimEnd(';') + ';' + $fallback), 'User')
  }
  return $fallback
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$SrcCmd = Join-Path $RepoRoot 'dotnet-tools.cmd'
$SrcSh = Join-Path $RepoRoot 'dotnet-tools'
$SrcDir = Join-Path $RepoRoot 'commands'
if (-not (Test-Path $SrcDir -PathType Container)) { ErrorExit "commands/ folder not found at repo root: $SrcDir" }
if (-not (Test-Path $SrcCmd -PathType Leaf)) { ErrorExit "dotnet-tools.cmd not found at repo root: $SrcCmd" }
if (-not (Test-Path $SrcSh -PathType Leaf)) { Log "[WARN] dotnet-tools (bash) not found at repo root: $SrcSh" }

if (-not $Target -or $Target.Trim() -eq '') { $Target = Resolve-WriteablePath }
$Target = (Resolve-Path -LiteralPath $Target -ErrorAction SilentlyContinue)?.Path ?? $Target
if (-not (Test-Path $Target -PathType Container)) { New-Item -ItemType Directory -Force -Path $Target | Out-Null }

Log "[INFO] Installing to: $Target"

Copy-Item -LiteralPath $SrcCmd -Destination (Join-Path $Target 'dotnet-tools.cmd') -Force
if (Test-Path $SrcSh -PathType Leaf) { Copy-Item -LiteralPath $SrcSh -Destination (Join-Path $Target 'dotnet-tools') -Force }

$DstCommands = Join-Path $Target 'commands'
if (Test-Path $DstCommands -PathType Container) { Remove-Item -LiteralPath $DstCommands -Recurse -Force -ErrorAction SilentlyContinue }
Copy-Item -LiteralPath $SrcDir -Destination $Target -Recurse -Force

# Ensure bash wrapper executable when using Git Bash/WSL
try {
  $bashWrapper = Join-Path $Target 'dotnet-tools'
  if (Test-Path $bashWrapper -PathType Leaf) {
    & Where-Object bash > $null 2>&1
    if ($LASTEXITCODE -eq 0) { bash -lc "chmod +x \"$bashWrapper\"" | Out-Null }
  }
}
catch {}

Log '[SUCCESS] Installed dotnet-tools wrappers and commands.'
Log "[NEXT] Open a new shell and run: dotnet-tools build"
exit 0
