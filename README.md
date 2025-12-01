# Dotnet Tools

Unified cross-shell wrappers to run common .NET repo tasks from PowerShell, CMD, or Bash using a single entrypoint: `dotnet-tools`.

These thin wrappers dispatch to PowerShell command scripts that live alongside them, so you get a consistent CLI across shells for build, test (with coverage), version bump, clean, and tag.

## Structure

```folder-structure
dotnet-tools/
├─ dotnet-tools           # Bash wrapper (Git Bash/WSL/Linux)
├─ dotnet-tools.cmd       # Windows CMD/PowerShell wrapper
├─ commands/              # PowerShell command scripts (the implementation)
│  ├─ build.ps1
│  ├─ bump.ps1
│  ├─ clean.ps1
│  ├─ tag.ps1
│  └─ test.ps1
└─ setup/                 # Install helpers to place wrappers on PATH
  ├─ install.ps1
  └─ install.sh
```

- The wrappers must stay sibling to the `commands/` folder; they resolve scripts by relative path.

## Usage

Once the repo directory is on your `PATH`, call `dotnet-tools <command> [args]` from any shell.

Examples:

- Build a solution (auto-detects single `.sln` under `src` or specify a path):
  - `dotnet-tools build [<path-to-src>] [--no-restore] [--solution Name.sln] [--configuration Debug|Release]`
- Bump project version in a `.csproj`:
  - `dotnet-tools bump <version|--major|--minor|--patch> [<csproj-or-directory>]`
- Clean all `bin/` and `obj/` under `src` (or a specified path):
  - `dotnet-tools clean [<path-to-src>]`
- Create a git tag from csproj `<Version>` (optionally push to remote):
  - `dotnet-tools tag [<path>] [--push] [--remote <name>]`
- Run tests with code coverage (HTML report):
  - `dotnet-tools test [<tests-root>]`

## Prerequisites

- .NET SDK installed (`dotnet --version`)
- For coverage HTML report: ReportGenerator (optional)
  - Install as a global .NET tool: `dotnet tool install -g dotnet-reportgenerator-globaltool`
  - Ensure `~/.dotnet/tools` (or Windows equivalent) is on your `PATH`

## Install Scripts

You can install the wrappers into a tools directory on your PATH using the provided scripts.

### Install on Windows (PowerShell)

Run from the repo root:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
./setup/install.ps1                # auto-picks a writable PATH dir or $HOME/bin
# or specify a target directory explicitly
./setup/install.ps1 -Target "$env:USERPROFILE\bin"
```

After installation, open a new shell and run `dotnet-tools build` to verify.

### Install on Linux / WSL / Git Bash

Run from the repo root:

```bash
chmod +x ./setup/install.sh
./setup/install.sh                  # auto-picks a writable PATH dir or ~/.local/bin
# or specify a target directory explicitly
./setup/install.sh /usr/local/bin   # may require: sudo ./setup/install.sh /usr/local/bin
```

The installer ensures the `commands/` folder sits alongside `dotnet-tools` in the chosen directory and attempts to add the fallback directory to your PATH (e.g., `~/.local/bin`) if needed.

## Manually add to PATH

You have two options: add the repo folder to `PATH` (recommended), or copy the wrapper + `commands/` folder into an existing tools directory already on `PATH`.

Important: `dotnet-tools`/`dotnet-tools.cmd` and `commands/` must live together in the same directory you place on `PATH`.

### Windows (PowerShell)

- Add for the current session only:

```powershell
$p = 'D:\\Repositories\\bat-dotnet-tools'
$env:Path = "$env:Path;$p"
```

- Persist for the current user (new shells will pick it up):

```powershell
$p = 'D:\\Repositories\\bat-dotnet-tools'
$u = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $u.Split(';') -contains $p) {
  [Environment]::SetEnvironmentVariable('Path', ($u.TrimEnd(';') + ';' + $p), 'User')
}
```

Then open a new PowerShell/CMD and run e.g. `dotnet-tools build`.

### Git Bash on Windows

Git Bash can call the same `dotnet-tools` wrapper. Ensure the repo folder is in `PATH` within your bash profile.

```bash
echo 'export PATH="$PATH:/d/Repositories/bat-dotnet-tools"' >> ~/.bashrc
source ~/.bashrc
# Optional: ensure executable bit is set for the bash wrapper
chmod +x /d/Repositories/bat-dotnet-tools/dotnet-tools
```

### Linux / WSL

If you’re on Linux or WSL with PowerShell 7 (`pwsh`) installed, the bash wrapper will call `pwsh` directly. Add the repo folder to your `PATH`:

```bash
# Example: clone into ~/.local/share/dotnet-tools
mkdir -p ~/.local/share
cd ~/.local/share
git clone https://example.com/your/bat-dotnet-tools.git

# Add to PATH via profile (adjust path as needed)
echo 'export PATH="$PATH:$HOME/.local/share/bat-dotnet-tools"' >> ~/.bashrc
source ~/.bashrc

# Ensure the bash wrapper is executable
chmod +x "$HOME/.local/share/bat-dotnet-tools/dotnet-tools"
```

If `powershell.exe` is available (on WSL), the wrapper prefers it; otherwise it falls back to `pwsh`.

## Notes & Troubleshooting

- Execution policy: wrappers invoke PowerShell with `-ExecutionPolicy Bypass`, so you typically do not need to change your system policy.
- Multiple solutions/projects: commands auto-discover where practical, but will ask you to specify a path or solution if multiple are found.
- Coverage report: `dotnet-tools test` writes coverage into `docs/coverage-report` (when running with a repo root containing `docs`) or into `<tests-root>/coverage-report` if you pass a base path.
- Errors about missing `reportgenerator`: install it via `dotnet tool install -g dotnet-reportgenerator-globaltool` and ensure your tools path is on `PATH`.

## Commands Summary

- `build`: Restore (optional) and build the solution in Debug/Release
- `bump`: Insert or update `<Version>` in a `.csproj` (supports `--major|--minor|--patch`)
- `clean`: Remove `bin/` and `obj/` under `src` or a specified path
- `tag`: Create `v<Version>` git tag from `.csproj` and optionally push
- `test`: Run tests in discovered test projects and generate HTML coverage report
