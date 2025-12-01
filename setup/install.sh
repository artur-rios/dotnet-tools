#!/usr/bin/env bash
set -euo pipefail

log(){ echo "$*"; }
err(){ echo "[ERROR] $*" >&2; exit 1; }

SCRIPT_PATH="${BASH_SOURCE[0]:-$0}"
SETUP_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
REPO_DIR="$(cd "$SETUP_DIR/.." && pwd)"

SRC_CMD="$REPO_DIR/dotnet-tools.cmd"
SRC_SH="$REPO_DIR/dotnet-tools"
SRC_DIR="$REPO_DIR/commands"
[[ -d "$SRC_DIR" ]] || err "commands/ folder not found at repo root: $SRC_DIR"
[[ -f "$SRC_SH" ]] || log "[WARN] dotnet-tools (bash) not found at repo root: $SRC_SH"

TARGET_DIR="${1:-}"

find_writable_path_dir(){
  IFS=: read -r -a PARTS <<< "$PATH"
  for d in "${PARTS[@]}"; do
    [[ -d "$d" && -w "$d" ]] && { echo "$d"; return; }
  done
  local fb="$HOME/.local/bin"
  mkdir -p "$fb"
  if ! echo ":$PATH:" | grep -q ":$fb:"; then
    if [[ -f "$HOME/.bashrc" ]]; then
      echo "export PATH=\"\$PATH:$fb\"" >> "$HOME/.bashrc"
      log "[INFO] Added $fb to PATH in ~/.bashrc"
    else
      log "[WARN] ~/.bashrc not found; please add $fb to PATH manually"
    fi
  fi
  echo "$fb"
}

if [[ -z "$TARGET_DIR" ]]; then
  TARGET_DIR="$(find_writable_path_dir)"
fi

mkdir -p "$TARGET_DIR"
log "[INFO] Installing to: $TARGET_DIR"

# Copy wrappers
if [[ -f "$SRC_SH" ]]; then
  install -m 0755 "$SRC_SH" "$TARGET_DIR/"
fi
if [[ -f "$SRC_CMD" ]]; then
  # Not required on Linux, but harmless if present
  cp -f "$SRC_CMD" "$TARGET_DIR/"
fi

# Copy commands directory
rm -rf "$TARGET_DIR/commands"
mkdir -p "$TARGET_DIR/commands"
cp -a "$SRC_DIR/." "$TARGET_DIR/commands/"

chmod +x "$TARGET_DIR/dotnet-tools" 2>/dev/null || true

log "[SUCCESS] Installed dotnet-tools wrappers and commands."
log "[NEXT] Open a new shell and run: dotnet-tools build"
