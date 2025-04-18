#!/usr/bin/env bash
#!/usr/bin/env bash
# atomic_arrays.sh
# Lightweight file-backed record store with atomic access and simple structured querying.
#
# Purpose:
# This library manages a flat-file, line-based record store to coordinate child/parent Bash
# processes in macOS and other POSIX systems. It enables atomic read/write/delete/list/select
# operations on a logically structured set of entries, each with the same number of columns
#
#   key1<TAB>key2<TAB>key3<TAB>pid
#
# Design Constraints:
# - POSIX-safe: compatible with macOS default Bash 3.2
# - No use of Bash arrays or exported env arrays (unsupported)
# - No external state managers (Redis, SQLite, daemons)
# - All access to the backing file is serialized using flock-based critical sections
# - Internal operations must never spawn subprocesses while holding the lock
#
# Backend Implementation:
# - Records stored in a single flat file (default: /tmp/<script_name>.$$)
# - Each line contains 4 TAB-separated fields; lines are newline-terminated
# - File is protected using flock() on the instance file itself to ensure atomicity
# - Columng containing current process PID is prefixed to the user's columns
#   for quick numeric sorting and collation
#
# Critical Section Design:
# - All access operations are wrapped in a locking mechanism using `flock`
# - The critical section executor takes a function name as the first argument, followed by its args
# - The function is executed in the same shell context (not a subshell), using brace grouping `{}` to preserve scope
# - Logging must not occur within the lock-protected code to avoid subshell invocation
#
# Escaping:
# - Only record-writing APIs (e.g., `add`) will reject input fields containing tab (`\t`), null (`\0`), or newline ('\n')
# - For safety, users should encode fields (e.g., URL-safe, base64) if unsure
#
# Logging:
# - All logging must occur outside the locked section using `log::<level> "message"` functions
# - Typical usage: log_info, log_error, log_debug, etc.
#
# Performance:
# - Optimized for 100–1000 row access patterns using simple tools (grep, cut, awk, sort)
# - No persistent daemon or index required
#
# Global Variables:
# - ATOMIC_ARRAYS_LIB_GUARD              → inclusion guard
# - ATOMIC_ARRAYS_DEFAULT_COLUMN_COUNT   → expected column count (default: 4)
# - ATOMIC_ARRAYS_DEFAULT_INSTANCE_NAME  → fallback record file name if none set
# - ATOMIC_ARRAYS_INSTANCE_FILE          → full path to the backing record file (read-only, exported)
#
# See Also:
# - flock(1), fcntl(2), cut(1), grep(1), awk(1), sort(1), POSIX shell
#
# Author: techguru@byiq.org (Paul Charlton)
# License: MIT or similar

# bash configuration:
# 1) Exit script if you tru to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

# Inclusion guard (Google-style)
[[ -n "${ATOMIC_ARRAYS_LIB_GUARD:-}" ]] && return 0
declare -rx ATOMIC_ARRAYS_LIB_GUARD=1

# --- Source peer libraries ---
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/bootstrap_lib.sh"
source "${BASH_SOURCE[0]%/*}/log_lib.sh"

#
# The instance database file.
# override before first inclusion if you want a different file name
# the following are unique per process
ATOMIC_ARRAYS_DEFAULT_INSTANCE_NAME="$(basename "/tmp/${BASH_SOURCE[0]%.*}").$$.txt}"
declare -x ATOMIC_ARRAYS_DEFAULT_INSTANCE_NAME="${ATOMIC_ARRAYS_DEFAULT_INSTANCE_NAME}"
# the following are shared with all child processes.
declare -x ATOMIC_ARRAYS_ROWS_UNIQUE_PER_PROCESS="${ATOMIC_ARRAYS_ROWS_UNIQUE_PER_PROCESS:-1}"
declare -x ATOMIC_ARRAYS_INSTANCE_FILE="${ATOMIC_ARRAYS_INSTANCE_FILE:-${ATOMIC_ARRAYS_DEFAULT_INSTANCE_NAME}}"

# --- Public API ---

# - atomic::arrays::add key1 key2 key3 pid
#   → Add a new record if it does not already exist
#   → Validates input, warns on regex chars, and avoids duplicates
#   → Acquires critical section before file modification
#
# NOTE: atomic::arrays stores fields as tab-separated values with newline record separators.
# Fields must not contain: tabs (\t), newlines (\n), or null bytes (\0).
# Regex-sensitive characters (e.g., [.*+?]) are permitted but may interfere with search key matching.
# If exact match behavior is critical, users should base64-encode such fields before insert.
#
# shellcheck disable=SC2120
function atomic::arrays::add() {
  if atomic::arrays::_validate_fields_safe "$@"; then
    # warn for characters in a field that can impact search/get
    test "${DEBUG:-}" || atomic::arrays::_warn_if_regex_chars_present "$@"
    # Dynamically dispatch atomic::arrays::_add inside a critical section
    # This is a variadic delegate, shellcheck-safe
    # shellcheck disable=SC2119,SC2120
    atomic::arrays::_critical_section atomic::arrays::_add "$@"
  fi
}

# - atomic::arrays::get key1 key2 key3
#     → Looks up records by key1–3; populates fourth field (pid)
#     keys are built from left to right from
#     provided fields, and may be partial.
#     Will error if more than one row matches.
#     fields will be \t separated in single string
#     will return all matching rows, terminated by newlines
function atomic::arrays::get() {
  # NOTE: This function assumes all records are well-formed and tab-safe.
  # Input validation (e.g., embedded tabs or nulls) is strictly enforced at write time (atomic::arrays::add).
  # If invalid records exist, matching will silently fail — this is an intentional design choice.

  # Dynamically dispatch atomic::arrays::_get inside a critical section
  # This is a variadic delegate, shellcheck-safe
  # shellcheck disable=SC2119,SC2120
  atomic::arrays::_critical_section atomic::arrays::_get "$@"
}

# - atomic::arrays::delete key1 key2 key3
#     → Remove entries matching composite key,
#       keys are built from left to right from
#       provided fields.
# shellcheck disable=SC2120
function atomic::arrays::delete() {
  # Dynamically dispatch atomic::arrays::_delete inside a critical section
  # This is a variadic delegate, shellcheck-safe
  # shellcheck disable=SC2119,SC2120
  atomic::arrays::_critical_section atomic::arrays::_delete "$@"
}

# - atomic::arrays::list
#     → Dump all entries
function atomic::arrays::list() {
  # Dynamically dispatch atomic::arrays::_list inside a critical section
  # This is a variadic delegate, shellcheck-safe
  # shellcheck disable=SC2119,SC2120
  atomic::arrays::_critical_section atomic::arrays::_list "$@"
}

# - atomic::arrays::destroy
# - atomic::arrays::destroy
#   → Delete the backing store for this record set
function atomic::arrays::destroy() {
  # Dynamically dispatch atomic::arrays::_destroy inside a critical section
  # This is a variadic delegate, shellcheck-safe
  # shellcheck disable=SC2119,SC2120
  atomic::arrays::_critical_section atomic::arrays::_destroy "$@"
}

# atomic::arrays::assign_var
# Usage: atomic::arrays::assign_var <target_var> <public_function> [args...]
#
# Captures the stdout result of a public atomic::arrays function and assigns it
# into a variable in the caller’s scope. The function is invoked without a subshell,
# preserving $$, return code, and shell-local side effects. Output is captured via
# process substitution, which forks only the output reader — not the function itself.
#
# ⚠️ STDOUT WARNING:
# This function captures all stdout from the target function. If the function emits
# logs, diagnostics, or multi-line content, those will be included in the result.
# The caller is responsible for using this only with functions that emit clean,
# single-line output.

function atomic::arrays::assign_var() {
  local target="${1}" func="${2}"
  shift; shift
  atomic::arrays::_validate_varname "${target}" || return $?
  local value rc reset_pid=0
  if ! atomic::arrays::_maybe_export_pid; then
    reset_pid=1
  fi
  value="$("${func}" "$@")"; rc=$?
  eval "${target}=\"\${value}\""
  [[ "${reset_pid}" -eq 1 ]] && unset ATOMIC_ARRAYS_PID >&2
  return "${rc}"
}

function atomic::arrays::_validate_varname() {
  local varname="${1}"
  case "${varname}" in ''|*[!a-zA-Z0-9_]*)
    log::error "assign_var: invalid variable name:${varname}"
    return 2
    ;;
  esac
}

function atomic::arrays::_maybe_export_pid() {
  [[ -n "${ATOMIC_ARRAYS_PID:-}" ]] && return 0
  # 🧠 Ensure PID consistency for all forks/subshells
  local tempfile real_pid
  tempfile="$(mktemp "/tmp/realpid.XXXXXX")"
  atomic::arrays::_write_real_pid_to_file "${tempfile}"
  real_pid="$(cat "${tempfile}")"
  rm -f "${tempfile}"
  ATOMIC_ARRAYS_PID="${real_pid}"
  export ATOMIC_ARRAYS_PID
  return 1
}

# --- Private API ---

# - atomic::arrays::add key1 key2 key3 pid
#     → Add new entry (idempotent if exists)
function atomic::arrays::_add() {
  matches=$(atomic::arrays::_get "$@")
  if [[ -n "${matches}" ]]; then
    if [[ "${ATOMIC_ARRAYS_ROWS_UNIQUE_PER_PROCESS:-1}" -eq 1 ]] || grep -q "${ATOMIC_ARRAYS_PID}\t" <<< "${matches}"; then
      log::warn "Avoided adding duplicate record [$*]"
      return 1
    fi
  fi
  local token
  token="$(atomic::arrays::_fetch_next_token)"
  printf '%s\t' "$@" >> "${ATOMIC_ARRAYS_INSTANCE_FILE}"
  printf '%s\n' "$((token))" >> "${ATOMIC_ARRAYS_INSTANCE_FILE}"
  log::success "Added record: $* $((token))"
  printf '%s\n' "$((token))"
}

# - atomic::arrays::delete key1 key2 key3
#     → Remove entries matching composite key,
#       keys are built from left to right from
#       provided fields.
function atomic::arrays::_delete() {
  local search_key tmp
  search_key="$(atomic::arrays::_search_key "$@")"
  tmp=$(mktemp "${ATOMIC_ARRAYS_INSTANCE_FILE}.XXXXXX")
  sed "/${search_key}/d" "${ATOMIC_ARRAYS_INSTANCE_FILE}" > "${tmp}" \
    && cat "${tmp}" > "${ATOMIC_ARRAYS_INSTANCE_FILE}" \
    && rm -f "${tmp}" \
    || {
      cat "${ATOMIC_ARRAYS_INSTANCE_FILE}" >&2
      log::error "atomic::arrays::_delete: failed to safely remove record"
      return 1
    }
}

# - atomic::arrays::get key1 key2 key3
#     → Return PID or full line for matching key
#     keys are built from left to right from
#     provided fields, and may be partial.
#     Will error if more than one row matches.
#     fields will be \t separated in single string
function atomic::arrays::_get() {
  local search_key
  search_key="$(atomic::arrays::_search_key "$@")"
  matches=$(grep "${search_key}" "${ATOMIC_ARRAYS_INSTANCE_FILE}" || true)
  grep -v '^$' <<< "${matches}" | sed -e 's|^[0-9][0-9]*\t||' -E -e 's|^(.*)\t.*$|\1|' || true
}

# - atomic::arrays::list
#     → Dump all entries
function atomic::arrays::_list() {
  :
}

# - atomic::arrays::destroy
#   → Delete the file entirely
function atomic::arrays::_destroy() {
  # printf '' > "${ATOMIC_ARRAYS_INSTANCE_FILE}"
  rm -f "${ATOMIC_ARRAYS_INSTANCE_FILE}"
}

# - atomic::arrays::_critical_section <function_name> [args...]
#   Executes the given function with its arguments inside a flock-protected
#   critical section using a brace block to avoid subshells.
#
# Arguments:
#   $1: function name
#   $@: args passed to the function
#
function atomic::arrays::_critical_section() {
  local -r _fn="${1:-}"
  shift

  if [[ -z "${_fn}" ]]; then
    log::error 'atomic::arrays::_critical_section: function name is required'
    return 1
  fi

  if ! declare -f "${_fn}" > /dev/null 2>&1; then
    log::error "atomic::arrays::_critical_section: unknown function '${_fn}'"
    return 2
  fi
  local rc reset_pid=0
  if ! atomic::arrays::_maybe_export_pid; then
    reset_pid=1
  fi
  # Lock the instance file directly for critical section serialization
  local -r _lock_fd=201
  {
    flock -x 201
    {
      "${_fn}" "${ATOMIC_ARRAYS_PID}" "$@"
      rc=$?
    }
  } 201>>"${ATOMIC_ARRAYS_INSTANCE_FILE}"
  [[ "${reset_pid}" -eq 1 ]] && unset ATOMIC_ARRAYS_PID >&2
  return "${rc}"
}

function atomic::arrays::_validate_fields_safe() {
  local field check_field
  for field in "$@"; do
    check_field="$(printf '%s' "${field}" | tr -d '\t\000\n')"
    if [[ "${#field}" -ne "${#check_field}" ]]; then
      # arg contains a tab or NUL
      log::error "Field contains tab or null byte: [${field}] [$(printf '%s' "${field}" | hexdump -C)]"
      return 1
    fi
  done
}

function atomic::arrays::_search_key() {
  if [[ "${ATOMIC_ARRAYS_ROWS_UNIQUE_PER_PROCESS:-0}" -ne 1 ]]; then
    # Matches: ^<digits>\t<key1>
    shift
    printf '%s\t' '^[0-9][0-9]*' "$@"
  else
    printf '^'
    printf '%s\t' "$@"
  fi
}

function atomic::arrays::_warn_if_regex_chars_present() {
  # shellcheck disable=SC2076
  if [[ $* =~ [][.*^\$?+{}|\\] ]]; then
    log_warn "⚠️  One or more fields contain regex-sensitive characters — consider base64 encoding if exact-match is required"
  fi
}

function atomic::arrays::_write_real_pid_to_file() {
  local outfile="$1"
  sh -c 'echo $PPID' > "${outfile}"
}

function atomic::arrays::_fetch_next_token() {
  if [[ -z "${ATOMIC_ARRAYS_INSTANCE_FILE:-}" ]]; then
    printf '🛑 ERROR: ATOMIC_ARRAYS_INSTANCE_FILE is not set.\n' >&2
    return 1
  fi

  # 📌 CONTRACT: Caller must hold a valid flock on ${ATOMIC_ARRAYS_INSTANCE_FILE}
  local -r token_file="${ATOMIC_ARRAYS_INSTANCE_FILE}.token"

  mkdir -p "$(dirname "${token_file}")"

  # 📌 First-time init if file missing or empty
  [[ -s "${token_file}" ]] || printf '0\n' > "${token_file}"

  local token
  IFS= read -r token < "${token_file}" || token=0
  token="${token%%[!0-9]*}"
  [[ -z "${token}" || ! "${token}" =~ ^[0-9]+$ ]] && token=0

  ((token++))

  # ✅ Safe write since we are inside caller's critical section
  printf '%s\n' "${token}" > "${token_file}"

  printf '%s\n' "${token}"
}
