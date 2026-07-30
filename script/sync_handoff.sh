#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${HQ_DIR:-}" ]] && [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi
HQ_BASE="${HQ_DIR:-${SOURCE_REPO:-/mnt/d/RubyOnRails/chatdox-curriculum}}"
SOURCE_DIR="${SOURCE_DIR:-$HQ_BASE/.local/handoff}"
TARGET_DIR="$PROJECT_ROOT/.local/handoff"
MIRROR_MODE="false"
DRY_RUN_MODE="false"

for arg in "$@"; do
  case "$arg" in
    --mirror)
      MIRROR_MODE="true"
      ;;
    --dry-run)
      DRY_RUN_MODE="true"
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--mirror] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"

# Copy all contents, including hidden files, while preserving timestamps and permissions.
RSYNC_OPTS=("-a")

if [[ "$MIRROR_MODE" == "true" ]]; then
  RSYNC_OPTS+=("--delete")
fi

if [[ "$DRY_RUN_MODE" == "true" ]]; then
  RSYNC_OPTS+=("--dry-run" "--itemize-changes")
fi

rsync "${RSYNC_OPTS[@]}" "$SOURCE_DIR/" "$TARGET_DIR/"

echo "Synced handoff files."
echo "Source: $SOURCE_DIR"
echo "Target: $TARGET_DIR"
echo "Mode: $([[ "$MIRROR_MODE" == "true" ]] && echo "mirror" || echo "copy")"
echo "Dry run: $DRY_RUN_MODE"
