#!/bin/sh
# The `build` check: there is nothing to compile, so it checks the scripts and runs the end-to-end test suite.
#   1. Syntax: `bash -n` for the Bash scripts (dotnet-tools, setup/install.sh), PowerShell's own parser for every
#      .ps1 (commands/, setup/, tests/, ci/), and parameters/init-parameters.json must parse as JSON.
#   2. The Bash suites of tests/run.ps1 (`dotnet-tools bash-test-all`, as the README runs them): init-lib and init-min
#      scaffold mock repositories under tests/mock/ (ignored by git), then build, bump, tag, test (with the coverage
#      report) and clean them through the Bash wrapper. The suite always exits 0, so this reads its last line,
#      "[SUMMARY] <passed> of <total> tests passed", and fails unless every test passed.
# Left out: the CMD suites (cmd-test-*), which need cmd.exe, and dotnet-tools.cmd itself.
#
# The scaffolded projects target net10.0, hence the .NET 10 SDK image, which also has the bash, git and
# PowerShell 7 the suite needs. `dotnet-tools test` needs ReportGenerator, which is not in the image: a pinned
# version is installed into a temporary directory and put on the PATH.
#
# yggdrasil.yml runs it in that image from the repository's root; by hand, from that root:
#   docker run --rm -v "$PWD:/src" -w /src <image> sh ci/build.sh
set -eu

# The repository's root, wherever this is run from.
cd "$(dirname "$0")/.."

export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

# renovate: datasource=nuget depName=dotnet-reportgenerator-globaltool
REPORTGENERATOR_VERSION=5.5.11

echo "== bash -n"
for script in dotnet-tools setup/install.sh; do
  bash -n "$script"
  echo "$script: ok"
done

echo "== PowerShell parser, JSON"
# shellcheck disable=SC2016 # PowerShell code: the shell must not expand it.
pwsh -NoProfile -NonInteractive -Command '
  $failed = 0
  foreach ($file in Get-ChildItem -Path commands, setup, tests, ci -Recurse -Filter *.ps1 | Where-Object { $_.FullName -notmatch "[\/]tests[\/]mock[\/]" }) {
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$null, [ref]$errors)
    foreach ($e in $errors) {
      Write-Output "$($file.FullName):$($e.Extent.StartLineNumber): $($e.Message)"
      $failed++
    }
    if (-not $errors) { Write-Output "$(Resolve-Path -Relative $file.FullName): ok" }
  }
  $null = Get-Content -Raw parameters/init-parameters.json | ConvertFrom-Json
  Write-Output "parameters/init-parameters.json: ok"
  if ($failed) { exit 1 }
'

tools=$(mktemp -d)
trap 'rm -rf "$tools"' EXIT
dotnet tool install dotnet-reportgenerator-globaltool --version "$REPORTGENERATOR_VERSION" --tool-path "$tools"
export PATH="$tools:$PATH"

echo "== dotnet-tools bash-test-all"
bash dotnet-tools bash-test-all | tee "$tools/tests.log"
summary=$(grep '^\[SUMMARY\]' "$tools/tests.log" | tail -n 1)
passed=$(echo "$summary" | sed -n 's/^\[SUMMARY\] \([0-9][0-9]*\) of \([0-9][0-9]*\) tests passed.*/\1/p')
total=$(echo "$summary" | sed -n 's/^\[SUMMARY\] \([0-9][0-9]*\) of \([0-9][0-9]*\) tests passed.*/\2/p')
if [ -z "$total" ] || [ "$total" -eq 0 ] || [ "$passed" != "$total" ]; then
  echo "ci/build.sh: the test suite did not pass: ${summary:-no [SUMMARY] line}" >&2
  exit 1
fi
