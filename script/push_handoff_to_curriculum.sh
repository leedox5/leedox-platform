#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTBOX_DIR="$PROJECT_ROOT/.local/handoff/outbox"
HQ_BASE="${HQ_DIR:-${SOURCE_REPO:-/mnt/d/RubyOnRails/chatdox-curriculum}}"
TARGET_DIR="${TARGET_DIR:-$HQ_BASE/.local/handoff/inbox}"
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

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

PACKAGE_NAME="$(basename "$SOURCE_DIR")"
PACKAGE_TARGET_DIR="$TARGET_DIR/$PACKAGE_NAME"

mkdir -p "$PACKAGE_TARGET_DIR"

RSYNC_OPTS=("-a" "--checksum")

if [[ "$MIRROR_MODE" == "true" ]]; then
  RSYNC_OPTS+=("--delete")
fi

if [[ "$DRY_RUN_MODE" == "true" ]]; then
  RSYNC_OPTS+=("--dry-run" "--itemize-changes")
fi

rsync "${RSYNC_OPTS[@]}" "$SOURCE_DIR/" "$PACKAGE_TARGET_DIR/"

echo "Pushed handoff package to curriculum inbox."
echo "Source: $SOURCE_DIR"
echo "Target: $PACKAGE_TARGET_DIR"
echo "Mode: $([[ "$MIRROR_MODE" == "true" ]] && echo "mirror" || echo "copy")"
echo "Dry run: $DRY_RUN_MODE"
