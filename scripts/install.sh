#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="$HOME/.local/bin"
ASSUME_YES=0
NO_PATH_EDIT=0
FORCE_REPLACE=0

usage() {
  cat <<'EOF'
Install apple-code from source into a user-local bin directory.

Usage:
  ./scripts/install.sh [options]

Options:
  --target <dir>    Install destination directory (default: ~/.local/bin)
  --yes             Non-interactive mode (accept prompts)
  --no-path-edit    Never modify shell rc files
  --force           Replace existing binary without creating backup
  -h, --help        Show this help
EOF
}

resolve_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir/.."
  pwd
}

append_path_line() {
  local rc_file="$1"
  local line='export PATH="$HOME/.local/bin:$PATH"'

  if [[ -f "$rc_file" ]] && grep -Fq "$line" "$rc_file"; then
    echo "PATH line already present in $rc_file"
    return 0
  fi

  {
    echo ""
    echo "# Added by apple-code installer"
    echo "$line"
  } >> "$rc_file"

  echo "Updated $rc_file"
}

confirm() {
  local prompt="$1"

  if (( ASSUME_YES == 1 )); then
    return 0
  fi

  read -r -p "$prompt [y/N]: " answer
  case "${answer:-}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

while (( "$#" )); do
  case "$1" in
    --target)
      if [[ $# -lt 2 ]]; then
        echo "Error: --target requires a value" >&2
        exit 1
      fi
      TARGET_DIR="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    --no-path-edit)
      NO_PATH_EDIT=1
      shift
      ;;
    --force)
      FORCE_REPLACE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v swift >/dev/null 2>&1; then
  echo "Error: swift not found in PATH. Install Xcode command line tools first." >&2
  exit 1
fi

REPO_ROOT="$(resolve_repo_root)"
cd "$REPO_ROOT"

echo "Building release binary..."
swift build -c release

SOURCE_BIN="$REPO_ROOT/.build/release/apple-code"
if [[ ! -x "$SOURCE_BIN" ]]; then
  echo "Error: build succeeded but binary not found at $SOURCE_BIN" >&2
  exit 1
fi

TARGET_DIR="${TARGET_DIR/#\~/$HOME}"
mkdir -p "$TARGET_DIR"
TARGET_BIN="$TARGET_DIR/apple-code"

if [[ -e "$TARGET_BIN" ]] && (( FORCE_REPLACE == 0 )); then
  backup_path="$TARGET_BIN.backup.$(date +%Y%m%d%H%M%S)"
  echo "Existing binary found at $TARGET_BIN"
  if confirm "Create backup and replace existing binary?"; then
    mv "$TARGET_BIN" "$backup_path"
    echo "Backed up existing binary to $backup_path"
  else
    echo "Install aborted."
    exit 1
  fi
fi

if [[ -e "$TARGET_BIN" ]] && (( FORCE_REPLACE == 1 )); then
  rm -f "$TARGET_BIN"
fi

cp "$SOURCE_BIN" "$TARGET_BIN"
chmod 755 "$TARGET_BIN"
echo "Installed apple-code to $TARGET_BIN"

if [[ ":$PATH:" != *":$TARGET_DIR:"* ]]; then
  echo "Notice: $TARGET_DIR is not in PATH."

  if (( NO_PATH_EDIT == 1 )); then
    echo "Add it manually:"
    echo "  export PATH=\"$TARGET_DIR:\$PATH\""
  else
    rc_file="$HOME/.zshrc"
    if [[ "${SHELL:-}" == */bash ]]; then
      rc_file="$HOME/.bashrc"
    fi

    if [[ "$TARGET_DIR" != "$HOME/.local/bin" ]]; then
      echo "Skipping automatic PATH edit because custom --target is in use."
      echo "Add it manually:"
      echo "  export PATH=\"$TARGET_DIR:\$PATH\""
    elif confirm "Append ~/.local/bin PATH entry to $rc_file?"; then
      append_path_line "$rc_file"
      echo "Open a new shell (or run 'source $rc_file') to use 'apple-code' directly."
    else
      echo "Skipped PATH update."
      echo "Add it manually:"
      echo "  export PATH=\"$TARGET_DIR:\$PATH\""
    fi
  fi
fi

echo ""
echo "Verify install:"
echo "  $TARGET_BIN --help"
echo "  which apple-code"
