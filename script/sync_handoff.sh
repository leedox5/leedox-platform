#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_ROOT/script/lib/hq_sync_common.sh"
load_project_env "$PROJECT_ROOT"

if [[ -n "${SOURCE_DIR:-}" ]]; then
  SELECTED_BY="SOURCE_DIR"
elif [[ -n "${HANDOFF_HQ_DIR:-}" ]]; then
  SOURCE_DIR="$HANDOFF_HQ_DIR/.local/handoff"
  SELECTED_BY="HANDOFF_HQ_DIR"
elif [[ -n "${HQ_DIR:-}" ]]; then
  SOURCE_DIR="$HQ_DIR/.local/handoff"
  SELECTED_BY="HQ_DIR"
elif [[ -n "${SOURCE_REPO:-}" ]]; then
  SOURCE_DIR="$SOURCE_REPO/.local/handoff"
  SELECTED_BY="SOURCE_REPO"
else
  SOURCE_DIR="/mnt/d/RubyOnRails/chatdox-curriculum/.local/handoff"
  SELECTED_BY="default"
fi

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

SOURCE_DIR="$(canonical_path "$SOURCE_DIR")"
TARGET_DIR="$(canonical_path "$TARGET_DIR")"
MODE="$([[ "$MIRROR_MODE" == "true" ]] && echo mirror || echo copy)"

print_preflight "handoff pull" "$SOURCE_DIR" "$TARGET_DIR" "$MODE" "$DRY_RUN_MODE" "$SELECTED_BY"
warn_legacy_hq_dir "$SELECTED_BY"
require_path_suffix "$SOURCE_DIR" "/.local/handoff" "handoff pull source"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

# Copy all contents, including hidden files, while preserving timestamps and permissions.
RSYNC_OPTS=("-a")

if [[ "$MIRROR_MODE" == "true" ]]; then
  RSYNC_OPTS+=("--delete")
fi

if [[ "$DRY_RUN_MODE" == "true" ]]; then
  RSYNC_OPTS+=("--dry-run" "--itemize-changes")
fi

if [[ "$MIRROR_MODE" == "true" ]] && [[ -d "$TARGET_DIR" ]]; then
  DELETE_PREVIEW="$(rsync -ain --delete "$SOURCE_DIR/" "$TARGET_DIR/")"
  DANGEROUS_DELETIONS="$(
    printf '%s\n' "$DELETE_PREVIEW" |
      sed -nE 's/^\*deleting[[:space:]]+(outbox|completed|shared)(\/.*)?$/\1\//p' |
      sort -u
  )"
  if [[ -n "$DANGEROUS_DELETIONS" ]]; then
    echo "WARNING: mirror will delete protected handoff history/workspace paths:" >&2
    while IFS= read -r deletion; do
      printf '  - %s\n' "$deletion" >&2
    done <<< "$DANGEROUS_DELETIONS"
  fi
fi

RSYNC_TARGET="$TARGET_DIR"
if [[ "$DRY_RUN_MODE" == "true" ]]; then
  RSYNC_TARGET="$(dry_run_target "$TARGET_DIR")"
  if [[ "$RSYNC_TARGET" != "$TARGET_DIR" ]]; then
    trap 'rm -rf "$RSYNC_TARGET"' EXIT
  fi
else
  mkdir -p "$TARGET_DIR"
fi

rsync "${RSYNC_OPTS[@]}" "$SOURCE_DIR/" "$RSYNC_TARGET/"

echo "Synced handoff files."
echo "Source: $SOURCE_DIR"
echo "Target: $TARGET_DIR"
echo "Mode: $MODE"
echo "Dry run: $DRY_RUN_MODE"
