#!/usr/bin/env bash
set -euo pipefail

# Replaces `git subtree pull --prefix docs/curriculum` (REQ 0022, chatdox-curriculum).
# Subtree kept causing large add/add conflicts on pull, and pulled the entire HQ repo
# (QA/, SETUP/, TIPS/, prompts/, internal/, service-desk tooling, etc.) even though
# this app only ever reads three specific folders. This instead exports the exact
# git-tracked snapshot of chatdox-curriculum at a given ref and mirrors ONLY the
# folders actually used at runtime, under hq/ so it's clear this content is
# provided by HQ (chatdox-curriculum) and not owned/authored by DEV:
#
#   HQ docs/                 -> DEV hq/chatdox/
#   HQ claudox/               -> DEV hq/claudox/
#   HQ service-desk/requests/ -> DEV hq/service-desk/
#
# No shared git history, no subtree merge machinery, no unused content. Commit the
# result in this repo like any other change.

SOURCE_REPO="/mnt/d/RubyOnRails/chatdox-curriculum"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="main"
DRY_RUN_MODE="false"

for arg in "$@"; do
  case "$arg" in
    --ref=*)
      REF="${arg#--ref=}"
      ;;
    --dry-run)
      DRY_RUN_MODE="true"
      ;;
    *)
      echo "Unknown option: $arg" >&2
      echo "Usage: $0 [--ref=<git-ref>] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

if [[ ! -d "$SOURCE_REPO/.git" ]]; then
  echo "Source repo not found: $SOURCE_REPO" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

git -C "$SOURCE_REPO" archive "$REF" | tar -x -C "$TMP_DIR"

# chatdox-curriculum's .gitattributes forces `eol=crlf` on every text file, so
# `git archive` always emits CRLF regardless of ref/content. Without normalizing
# that away, every file compares as changed against DEV's LF copies on every
# single run (size + content both differ by a \r per line), even when HQ hasn't
# actually touched the content. Strip it here so the sync is a real diff.
#
# This MUST skip binary files. Every PNG's fixed 8-byte signature contains
# `0d 0a` (89 50 4e 47 0d 0a 1a 0a) by spec, so a blanket `sed -i 's/\r$//'`
# silently corrupts the signature of every synced image (1 byte shorter, all
# following bytes shifted) -- git itself never CRLF-converts these files (its
# own `text=auto` binary detection skips them at archive time), so this step
# must replicate that same distinction instead of applying to every file
# unconditionally. `grep -Iq ''` uses grep's own binary-content heuristic
# (same idea as git's: bail out if the file looks binary) -- exit status 1
# means "binary", so skip. See leedox_image_binary_corruption_fix_r1.
find "$TMP_DIR" -type f -print0 | while IFS= read -r -d '' f; do
  if grep -Iq '' "$f"; then
    sed -i 's/\r$//' "$f"
  fi
done

RSYNC_OPTS=("-a" "--delete" "--checksum")
if [[ "$DRY_RUN_MODE" == "true" ]]; then
  RSYNC_OPTS+=("--dry-run" "--itemize-changes")
fi

sync_one() {
  local src="$1" dest="$2"
  mkdir -p "$dest"
  if [[ "$DRY_RUN_MODE" == "true" ]]; then
    # --itemize-changes lists every file rsync considered, including the ones
    # left untouched (leading `.`). Only the leading-non-`.` lines are files
    # that will actually be created/updated/deleted, so drop the rest.
    rsync "${RSYNC_OPTS[@]}" "$TMP_DIR/$src/" "$dest/" | grep -v '^\.' || true
  else
    rsync "${RSYNC_OPTS[@]}" "$TMP_DIR/$src/" "$dest/"
    restore_mtimes "$src" "$dest"
  fi
  echo "  $src -> ${dest#$PROJECT_ROOT/}"
}

# `git archive` stamps every extracted file with the archive (checkout) time, not
# the time the file's content actually last changed, and rsync -a preserves that.
# So every single sync — even a no-op one — makes every file look "just modified",
# which breaks File.mtime-based "last updated" displays in the app. Fix it up here:
# look up each file's real last-commit time in the HQ source repo and stamp that
# instead, so unchanged files keep a stable mtime across repeated syncs.
#
# That mtime stamp only survives locally, though -- it's filesystem metadata,
# not something `git commit`/`git push` stores. Once this repo's commit gets
# checked out again (Railway's deploy does exactly that), every file in the
# checkout is stamped with the checkout time, identically across the whole
# tree, and the distinct per-file mtimes set below are lost. So also write out
# the same commit_dates as a JSON manifest (.last_updated.json) alongside the
# content -- as real file *content*, git preserves it exactly across any
# checkout, so the app can read "true" last-updated times in production
# without depending on filesystem mtime at all. See
# leedox_last_updated_timestamp_fix_r1 and app/models/content_manifest.rb.
restore_mtimes() {
  local src="$1" dest="$2"
  local rel_path="" commit_date=""
  declare -A commit_dates=()

  # A NUL-byte separator (the usual trick for this) can't survive here: it gets
  # truncated out of the argv string before git even sees it, and bash `read`
  # can't hold a NUL in a variable either. Use a plain marker prefix instead —
  # it can never collide with a real path under hq/.
  while IFS= read -r line; do
    if [[ "$line" == COMMIT_DATE:* ]]; then
      commit_date="${line#COMMIT_DATE:}"
    elif [[ -n "$line" ]]; then
      rel_path="${line#"$src"/}"
      # git log lists newest commit first, so the first date seen per file is its
      # most recent change — keep only that one.
      if [[ -z "${commit_dates[$rel_path]:-}" ]]; then
        commit_dates["$rel_path"]="$commit_date"
      fi
    fi
  done < <(git -C "$SOURCE_REPO" log --format="COMMIT_DATE:%cI" --name-only "$REF" -- "$src")

  while IFS= read -r file; do
    rel_path="${file#$dest/}"
    if [[ -n "${commit_dates[$rel_path]:-}" ]]; then
      touch -d "${commit_dates[$rel_path]}" "$file"
    fi
  done < <(find "$dest" -type f)

  {
    while IFS= read -r file; do
      rel_path="${file#$dest/}"
      if [[ -n "${commit_dates[$rel_path]:-}" ]]; then
        printf '%s\t%s\n' "$rel_path" "${commit_dates[$rel_path]}"
      fi
    done < <(find "$dest" -type f)
  } | ruby -rjson -e '
    entries = {}
    STDIN.each_line do |line|
      path, date = line.chomp.split("\t", 2)
      entries[path] = date
    end
    puts JSON.pretty_generate(entries)
  ' > "$dest/.last_updated.json"
}

echo "Syncing chatdox-curriculum ($REF), runtime folders only:"
sync_one "docs" "$PROJECT_ROOT/hq/chatdox"
sync_one "claudox" "$PROJECT_ROOT/hq/claudox"
sync_one "service-desk/requests" "$PROJECT_ROOT/hq/service-desk"

echo "Dry run: $DRY_RUN_MODE"