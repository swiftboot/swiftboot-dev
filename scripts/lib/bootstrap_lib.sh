#!/usr/bin/env bash
# bootstrap_lib.sh
# Canonical runtime loader for SwiftBoot Bash scripts.
#
# PURPOSE:
#   Provides one public function: `bootstrap::resolve_library_path`.
#   This resolves and sources project-relative paths and ensures safe inclusion.
#
#   Also provides:
#     - `bootstrap::get_results_dir <subpath>` → Resolves and ensures a writable results subdirectory,
#       inside a container (as /swiftboot/results/<subpath>) or outside as GITROOT/.results/<subpath>
#
# USAGE:
#   Source this file at the top of any SwiftBoot script using:
#
#     source "${BASH_SOURCE[0]%/scripts/*}/scripts/lib/bootstrap_lib.sh"
#
#   Then include other project libraries using:
#
#     source "$(bootstrap::resolve_library_path 'lib/metrics_lib.sh')"
#
# SIDE EFFECTS:
#   This file only sources peer libraries:
#     - log_lib.sh (defines `log::info`, `log::warn`, etc.)
#     - traps_lib.sh (defines trap helpers)
#   These libraries must define a private _init::<lib>() and perform no top-level execution.
#
#   This library also defines `bootstrap::_init`, which is automatically invoked
#   on every public function call to ensure the runtime is correctly initialized.

# bash configuration:
# 1) Exit script if you tru to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

# Inclusion guard (Google-style)
[[ -n "${BOOTSTRAP_LIB_GUARD:-}" ]] && return 0
declare -rx BOOTSTRAP_LIB_GUARD=1

# --- Source peer libraries (no top-level logic) ---
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/log_lib.sh"
source "${BASH_SOURCE[0]%/*}/traps_lib.sh"

# --- Public API ---

# Resolves and sources a library path relative to the script root.
# Also returns the full resolved path to the caller.
# Arguments:
#   $1: Relative path from library root (e.g. "./metrics_lib.sh")
function bootstrap::resolve_library_path() {
  echo "bs:rlp ${1}" >/dev/stderr
  bootstrap::_init

  local -r relpath="$1"
  local full_path
  full_path="$(bootstrap::get_scripts_dir)/${relpath}"
  full_path="$(realpath "${full_path}")"

  echo "bs:rlp as ${full_path}" >/dev/stderr
  printf '%s\n' "${full_path}"
}

# --- Private helpers ---

# Resolves and ensures a results subdirectory exists inside the proper results root.
# Arguments:
#   $1: Subdirectory under results (e.g., 'lifecycle', 'audit', 'build')
# Returns:
#   Full path to the results subdirectory, mkdir -p guaranteed.
function bootstrap::get_results_dir() {
  bootstrap::_init

  local -r subdir="${1}"
  local base='/swiftboot/results'   # default for container context
  local git_root final=''
  git_root="$(command git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "${git_root}" ]] && base="${git_root}/.results"
  [[ -d "${base}" ]] && final="${base}/${subdir}"
  mkdir -p "${final}"
  printf '%s\n' "${final}"
}

function bootstrap::get_src_dir() {
  bootstrap::_init

  local base='/src'         # default for container context
  local git_root
  git_root="$(command git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "${git_root}" ]] && base="${git_root}"
  mkdir -p "${base}"
  printf '%s\n' "${base}"
}

function bootstrap::get_scripts_dir() {
  bootstrap::_init

  local -r scripts="${BASH_SOURCE[0]%/scripts/*}/scripts"
  local scripts_real
  scripts_real="$(realpath "${scripts}")"
  mkdir -p "${scripts_real}"
  printf '%s\n' "${scripts_real}"
}

# --- Private Initialization ---

function bootstrap::_init() {
  [[ -n "${BOOTSTRAP_LIB_INITIALIZED:-}" ]] && return 0
  export BOOTSTRAP_LIB_INITIALIZED=1
  log::debug '✅ bootstrap_lib initialized'
}
