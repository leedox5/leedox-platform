#!/usr/bin/env bash

SYNC_ENV_KEYS=(
  HANDOFF_HQ_DIR
  CURRICULUM_HQ_DIR
  HQ_DIR
  SOURCE_REPO
  SOURCE_DIR
  TARGET_DIR
)

load_project_env() {
  local project_root="$1" env_file="$1/.env" key
  declare -A explicit_values=()

  for key in "${SYNC_ENV_KEYS[@]}"; do
    if [[ -v "$key" ]]; then
      explicit_values["$key"]="${!key}"
    fi
  done

  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
  fi

  for key in "${!explicit_values[@]}"; do
    printf -v "$key" '%s' "${explicit_values[$key]}"
    export "$key"
  done
}

canonical_path() {
  realpath -m -- "$1"
}

require_path_suffix() {
  local path="$1" suffix="$2" role="$3"

  if [[ "$path" != *"$suffix" ]]; then
    echo "Invalid $role: $path" >&2
    echo "Expected a path ending in $suffix." >&2
    exit 1
  fi
}

print_preflight() {
  local operation="$1" source="$2" target="$3" mode="$4" dry_run="$5" selected_by="$6"

  echo "Preflight:"
  echo "  Operation: $operation"
  echo "  Source: $source"
  echo "  Target: $target"
  echo "  Mode: $mode"
  echo "  Delete enabled: $([[ "$mode" == "mirror" ]] && echo true || echo false)"
  echo "  Dry run: $dry_run"
  echo "  Selected by: $selected_by"
}

warn_legacy_hq_dir() {
  local selected_by="$1"

  if [[ "$selected_by" == "HQ_DIR" ]]; then
    echo "Notice: HQ_DIR is a legacy fallback; prefer HANDOFF_HQ_DIR or CURRICULUM_HQ_DIR." >&2
  fi
}

dry_run_target() {
  local actual_target="$1"

  if [[ -d "$actual_target" ]]; then
    printf '%s\n' "$actual_target"
    return
  fi

  mktemp -d
}
