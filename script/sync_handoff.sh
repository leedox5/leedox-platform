#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -z "${HQ_DIR:-}" ]] && [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -a
  source "$PROJECT_ROOT/.env"
  set +a
fi
HQ_BASE="${HQ_DIR:-${SOURCE_REPO:-/mnt/d/RubyOnRails/leedox-hq}}"
SOURCE_DIR="${SOURCE_DIR:-$HQ_BASE/.local/handoff}"
TARGET_DIR="$PROJECT_ROOT/.local/handoff"
MIRROR_MODE="false"
DRY_RUN_MODE="false"
YES_MODE="false"

for arg in "$@"; do
  case "$arg" in
    --mirror)
      MIRROR_MODE="true"
      ;;
    --dry-run)
      DRY_RUN_MODE="true"
      ;;
    --yes|--force)
      YES_MODE="true"
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--mirror] [--dry-run] [--yes]" >&2
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

# A real (non-dry-run) --mirror deletes local files, and a --dry-run run from
# an earlier, separate invocation is not a trustworthy preview of that: the
# two calls can see different environment/source state (this is exactly what
# happened in leedox_revert_chatdox_season_experiment_r1 -- see backlog 017).
# So compute the delete preview and ask for confirmation inside this same
# invocation, immediately before the real rsync runs, unless --yes/--force
# was passed (for scripted/handoff-automation use).
if [[ "$MIRROR_MODE" == "true" ]] && [[ "$DRY_RUN_MODE" != "true" ]]; then
  DELETE_PREVIEW="$(rsync -ain --delete "$SOURCE_DIR/" "$TARGET_DIR/" | grep '^\*deleting' || true)"
  if [[ -n "$DELETE_PREVIEW" ]]; then
    DELETE_COUNT="$(printf '%s\n' "$DELETE_PREVIEW" | wc -l | tr -d ' ')"
    echo "The following $DELETE_COUNT item(s) will be deleted from $TARGET_DIR:" >&2
    if [[ "$DELETE_COUNT" -gt 50 ]]; then
      printf '%s\n' "$DELETE_PREVIEW" | head -50 >&2
      echo "  ... and $((DELETE_COUNT - 50)) more" >&2
    else
      printf '%s\n' "$DELETE_PREVIEW" >&2
    fi

    if [[ "$YES_MODE" != "true" ]]; then
      REPLY=""
      read -r -p "Proceed with deletion? [y/N] " REPLY || true
      if [[ "$REPLY" != "y" && "$REPLY" != "Y" ]]; then
        echo "Aborted -- no changes made. Re-run with --yes to skip this prompt." >&2
        exit 1
      fi
    fi
  fi
fi

rsync "${RSYNC_OPTS[@]}" "$SOURCE_DIR/" "$TARGET_DIR/"

echo "Synced handoff files."
echo "Source: $SOURCE_DIR"
echo "Target: $TARGET_DIR"
echo "Mode: $([[ "$MIRROR_MODE" == "true" ]] && echo "mirror" || echo "copy")"
echo "Dry run: $DRY_RUN_MODE"
