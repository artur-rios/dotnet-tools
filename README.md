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
│  ├─ test.ps1
│  ├─ init-lib.ps1
│  └─ init-min.ps1
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

-- Scaffold a new library repository (solution, project, metadata):

- `dotnet-tools init-lib [--root <RootName|Path>] [--solution Name] [--project Name] [--author "Full Name"] [--company "Company"] [--description "NuGet package description"] [--version 0.1.0] [--packageId Id] [--repositoryUrl URL] [--json path/to/params.json]`
- Example (flags only): `dotnet-tools init-lib --root MyLib --solution MyLib --author "Jane Doe" --company "Acme" --description "High performance utilities" --version 0.1.0 --packageId Acme.MyLib --repositoryUrl https://github.com/acme/mylib`
- Example (JSON only): `dotnet-tools init-lib --json parameters/init-parameters.json`
- Note: Do not mix `--json` with other flags; use one or the other.

-- Scaffold a minimal library repository (solution + project only):

- `dotnet-tools init-min [--root <RootName|Path>] [--solution Name] [--project Name] [--author "Full Name"] [--description "Project description"] [--json path/to/params.json]`
- Example: `dotnet-tools init-min --root MyLib --solution MyLib --project MyLib --author "Jane Doe" --description "High performance utilities"`
- Behavior: Generates solution and a minimal `.csproj` (no NuGet metadata). Does not create a test project; adds `tests/.gitkeep` instead. Uses the same `.editorconfig`, `.gitignore`, MIT `LICENSE`, and README generation as `init`.
-- Scaffold a single project folder:

- `dotnet-tools init-proj --name <ProjectName> [--min|--nuget]`
- Example (minimal default): `dotnet-tools init-proj --name Utils`
- Example (explicit minimal): `dotnet-tools init-proj --name Utils --min`
- Example (nuget blank metadata): `dotnet-tools init-proj --name Package --nuget`
- Behavior: Creates `<ProjectName>/` containing `<ProjectName>.csproj`. With `--min` (or no flag) copies `project.minimal.csproj.template`. With `--nuget` copies `project.nuget.csproj.template` but blanks all NuGet metadata property values (properties retained with empty content).

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
- `init-lib`: Scaffold a new library repo: creates root + `src/ docs/ tests/` folders, `.editorconfig`, `.gitignore`, `.wakatime-project`, `LICENSE` (MIT), `README.md`, solution and class library project with NuGet metadata (PackageId, Version, Authors, Description, License, RepositoryUrl, README).
- `init-min`: Scaffold a minimal library repo: same folders and top-level files as `init`, but creates a minimal class library `.csproj` without any NuGet packaging metadata and does not create a test project (adds `tests/.gitkeep`).
- `init-proj`: Scaffold a single project folder choosing between minimal (`--min` default) or NuGet template (`--nuget` blanks metadata values but keeps tags present).

### `init-lib` Command Details

Scaffolds a new repository structure for a class library.

Usage:

```bash
dotnet-tools init-lib [--root <RootName|Path>] [--solution Name] [--project Name] \
  [--author "Full Name"] [--company "Company"] [--description "NuGet package description"] \
  [--version 0.1.0] [--packageId Id] [--repositoryUrl URL] [--json path/to/params.json]
```

Parameters:

- `--root <RootName|Path>`: Root folder to create (must not exist). If omitted, value defaults from JSON `RootFolder`.
- `--solution`: Solution name (default: JSON `SolutionName` or `GetFileName(--root)`).
- `--project`: Project name (default: JSON `ProjectName` or `--solution`).
- `--author`: NuGet `Authors` (default: JSON `Author` or environment user).
- `--company`: NuGet `Company` (default: JSON `Company` or `--author`).
- `--description`: NuGet description (default: JSON `Description` or "<Project> library").
- `--version`: Initial `<Version>` (default: JSON `Version` or 0.1.0).
- `--packageId`: NuGet `PackageId` (default: JSON `PackageId` or `--project`).
- `--repositoryUrl`: NuGet `RepositoryUrl` (default: JSON `RepositoryUrl` or `git remote get-url origin` if available).
- `--json`: Path to parameters JSON. Mutually exclusive with other flags.

Behavior and precedence:

- Flags are optional. When a flag is not provided, values are read from `parameters/init-parameters.json` by default (or the file given via `--json`).
- Do not mix `--json` with other flags. Provide either a JSON file or use flags; mixing them returns an error.
- Root path must come from `--root` or JSON `RootFolder`. Positional arguments are not supported.
- The script validates the parameters JSON exists and includes all required keys: `RootFolder`, `SolutionName`, `ProjectName`, `Author`, `Company`, `Description`, `PackageId`, `RepositoryUrl`, `PackageLicenseExpression`, `Version`.

Generated structure:

```folder-structure
<Root>/
  .editorconfig
  .gitignore
  .wakatime-project
  LICENSE        # MIT (current year + author)
  README.md      # Header: solution name, body: description
  src/
    <Solution>.sln
    <Project>/
      <Project>.csproj  # With NuGet metadata
      README.md          # Copied for NuGet packaging
  docs/
  tests/
```

NuGet metadata added to `<Project>.csproj`:
`PackageId`, `Version`, `Authors`, `Company`, `Description`, `PackageLicenseExpression`, `RepositoryUrl` (if `git remote origin` available or provided), `PackageReadmeFile`.

Templates:

- `.editorconfig` and `.gitignore` are copied exclusively from `templates/.editorconfig.template` and `templates/.gitignore.template`.
- `LICENSE` (MIT) is rendered from `templates/LICENSE.MIT.template` with current year and author.
- Solution and project are rendered from `templates/solution.sln.template` and `templates/project.nuget.csproj.template` with placeholders replaced.

### `init-min` Command Details

Scaffolds the same repository structure as `init-lib`, but generates a minimal project with no NuGet metadata and no test project.

Usage:

```bash
dotnet-tools init-min [--root <RootName|Path>] [--solution Name] [--project Name] \
  [--author "Full Name"] [--description "Project description"] [--json path/to/params.json]
```

Behavior and notes:

- Uses the same parameter resolution rules as `init-lib`. If `--json` is provided, do not mix it with flags. Only a minimal subset of JSON keys is required: `RootFolder`, `SolutionName`, `ProjectName`, `Author`, `Description`.
- Generates: `.editorconfig`, `.gitignore`, `.wakatime-project`, `LICENSE` (MIT), `README.md`, `src/<Solution>.sln`, `src/<Project>.csproj` (minimal), `docs/.gitkeep`, `tests/.gitkeep`.
- Templates used: `templates/solution.sln.template` and `templates/project.minimal.csproj.template`.
