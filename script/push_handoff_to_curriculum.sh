#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$PROJECT_ROOT/script/lib/hq_sync_common.sh"
load_project_env "$PROJECT_ROOT"

OUTBOX_DIR="$PROJECT_ROOT/.local/handoff/outbox"
if [[ -n "${TARGET_DIR:-}" ]]; then
  SELECTED_BY="TARGET_DIR"
elif [[ -n "${HANDOFF_HQ_DIR:-}" ]]; then
  TARGET_DIR="$HANDOFF_HQ_DIR/.local/handoff/inbox"
  SELECTED_BY="HANDOFF_HQ_DIR"
elif [[ -n "${HQ_DIR:-}" ]]; then
  TARGET_DIR="$HQ_DIR/.local/handoff/inbox"
  SELECTED_BY="HQ_DIR"
elif [[ -n "${SOURCE_REPO:-}" ]]; then
  TARGET_DIR="$SOURCE_REPO/.local/handoff/inbox"
  SELECTED_BY="SOURCE_REPO"
else
  TARGET_DIR="/mnt/d/RubyOnRails/chatdox-curriculum/.local/handoff/inbox"
  SELECTED_BY="default"
fi

SOURCE_DIR=""
MIRROR_MODE="false"
DRY_RUN_MODE="false"

usage() {
  echo "Usage: $0 --source <package-dir> [--mirror] [--dry-run]" >&2
  echo "  --source must point at a single handoff package (e.g. .local/handoff/outbox/<package>)," >&2
  echo "  not the outbox root — outbox accumulates every package ever pushed, including ones HQ" >&2
  echo "  already moved to completed/, and syncing the whole tree resurrects those as spurious" >&2
  echo "  new files on the HQ side." >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      if [[ $# -lt 2 ]]; then
        echo "--source requires a directory argument" >&2
        exit 1
      fi
      SOURCE_DIR="$2"
      if [[ "$SOURCE_DIR" != /* ]]; then
        SOURCE_DIR="$PROJECT_ROOT/$SOURCE_DIR"
      fi
      shift 2
      ;;
    --mirror)
      MIRROR_MODE="true"
      shift
      ;;
    --dry-run)
      DRY_RUN_MODE="true"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$SOURCE_DIR" ]]; then
  echo "Error: --source is required." >&2
  usage
  exit 1
fi

if [[ "$(cd "$SOURCE_DIR" 2>/dev/null && pwd)" == "$OUTBOX_DIR" ]]; then
  echo "Error: --source resolves to the outbox root ($OUTBOX_DIR)." >&2
  echo "Point --source at one package directory inside it instead, e.g.:" >&2
  echo "  $0 --source .local/handoff/outbox/<package>" >&2
  exit 1
fi

PACKAGE_NAME="$(basename "$SOURCE_DIR")"
SOURCE_DIR="$(canonical_path "$SOURCE_DIR")"
TARGET_DIR="$(canonical_path "$TARGET_DIR")"
PACKAGE_TARGET_DIR="$TARGET_DIR/$PACKAGE_NAME"
MODE="$([[ "$MIRROR_MODE" == "true" ]] && echo mirror || echo copy)"

print_preflight "handoff push" "$SOURCE_DIR" "$PACKAGE_TARGET_DIR" "$MODE" "$DRY_RUN_MODE" "$SELECTED_BY"
warn_legacy_hq_dir "$SELECTED_BY"
require_path_suffix "$TARGET_DIR" "/.local/handoff/inbox" "handoff push target"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Handoff inbox not found: $TARGET_DIR" >&2
  exit 1
fi

RSYNC_OPTS=("-a" "--checksum")

if [[ "$MIRROR_MODE" == "true" ]]; then
  RSYNC_OPTS+=("--delete")
fi

if [[ "$DRY_RUN_MODE" == "true" ]]; then
  RSYNC_OPTS+=("--dry-run" "--itemize-changes")
fi

RSYNC_TARGET="$PACKAGE_TARGET_DIR"
if [[ "$DRY_RUN_MODE" == "true" ]]; then
  RSYNC_TARGET="$(dry_run_target "$PACKAGE_TARGET_DIR")"
  if [[ "$RSYNC_TARGET" != "$PACKAGE_TARGET_DIR" ]]; then
    trap 'rm -rf "$RSYNC_TARGET"' EXIT
  fi
else
  mkdir -p "$PACKAGE_TARGET_DIR"
fi

rsync "${RSYNC_OPTS[@]}" "$SOURCE_DIR/" "$RSYNC_TARGET/"

echo "Pushed handoff package to handoff inbox."
echo "Source: $SOURCE_DIR"
echo "Target: $PACKAGE_TARGET_DIR"
echo "Mode: $MODE"
echo "Dry run: $DRY_RUN_MODE"
