#!/usr/bin/env bash
# log_lib.sh
# SwiftBoot shared logging functions for scripts and libraries.
#
# PURPOSE:
#   Provides structured, color-coded logging with dual output to file and stdout,
#   lifecycle support for setup and teardown, dry-run awareness, and error trapping.
#
# USAGE:
#   Must explicitly call:
#
#     log::init
#
#   before using any log functions. If not, all log:: functions will call log::init themselves.
#
# LIFECYCLE:
#   - log::init        ← sets up logging, FDs, and installs shutdown trap (idempotent, thread-safe)
#   - log::shutdown    ← safely tears down/archives logs and clears the guard (idempotent, best-effort)
#
# REQUIREMENTS:
#   The caller must define:
#     - LOG_FILE       (absolute path to log file)
#     - LOG_TS         (timestamp for archive naming)
#     - LOG_ARCHIVE    (1 to archive, 0 to skip; default: 1)
#     - LOG_DRY_RUN    (1 = dry run mode, 0 = execute)
#     - LOG_DEBUG      (1 = enable debug output)

# bash configuration:
# 1) Exit script if you tru to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

[[ -n "${LOG_LIB_GUARD:-}" ]] && return 0
declare -rx LOG_LIB_GUARD=1

# --- Source peer libraries ---
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/bootstrap_lib.sh"
source "${BASH_SOURCE[0]%/*}/traps_lib.sh"

# --- Public Lifecycle API ---

log::init() {
  [[ -n "${LOG_LIB_INITIALIZED:-}" ]] && return 0
  if [[ -z "${LOG_FILE:-}" ]]; then
    printf '🛑 ERROR: LOG_FILE must be defined before using log_lib\n' >&2
    exit 1
  fi

  mkdir -p "$(dirname "${LOG_FILE}")"
  touch "${LOG_FILE}"
  exec 200>>"${LOG_FILE}" || {
    printf '🛑 ERROR: Could not open lock FD on %s\n' "${LOG_FILE}" >&2
    exit 1
  }

  {
    flock -x 200
    log::_init_critical_section
  }

  eval "exec 200>&-"
}

log::_init_critical_section() {
  [[ -n "${LOG_LIB_INITIALIZED:-}" ]] && return 0

  if [[ "${BASH_SUBSHELL:-0}" -gt 0 || "$$" != "${BASHPID:-$$}" ]]; then
    printf '🛑 ERROR: log::init must be called from top-level shell\n' >&2
    exit 1
  fi

  log::_setup_logging
  traps::add EXIT log::shutdown
  traps::add SIGINT log::_trap_sigint
  export LOG_LIB_INITIALIZED=1
  log::info "Logging to ${LOG_FILE}"
}

log::shutdown() {
  [[ -z "${LOG_LIB_INITIALIZED:-}" ]] && return 0
  traps::remove SIGINT log::_trap_sigint
  traps::remove EXIT log::shutdown

  if log::_is_archive_required; then
    log::_process_archive || true
  else
    log::_teardown_log_streams || true
  fi

  unset LOG_LIB_INITIALIZED
}

# --- Logging Setup / Teardown ---

log::_setup_logging() {
  mkdir -p "$(dirname "${LOG_FILE}")"
  touch "${LOG_FILE}"
  exec 5>>"${LOG_FILE}"
  exec 6>&1
}

log::_teardown_log_streams() {
  exec 6>&-
  exec 5>&-
  sleep 0.2
  sync
}

# --- Archive Support ---

log::_is_archive_required() {
  [[ "${LOG_ARCHIVE:-1}" -eq 1 && -e "${LOG_FILE}" ]]
}

log::_process_archive() {
  local results_dir
  results_dir="$(bootstrap::get_results_dir 'lifecycle')"
  mkdir -p "${results_dir}"
  log::info "Moving log to ${results_dir}/update_new_kernel_${LOG_TS}.log"
  log::_teardown_log_streams
  cp "${LOG_FILE}" "${results_dir}/update_new_kernel_${LOG_TS}.log" && rm -f "${LOG_FILE}"
}

# --- Logging Interface ---

log::info() {
  log::init
  local -r msg="${1}"
  printf '\033[1;34mℹ️  INFO:\033[0m %s\n' "${msg}" | log::_stream
}

log::trace() {
  log::init
  log::info '🔍 Enabling shell trace (set -x)'
  set -x
}

log::untrace() {
  log::init
  log::info '🙈 Disabling shell trace (set +x)'
  set +x
}

function log::success() {
  log::init
  local -r msg="${1}"
  printf '\033[1;32m✅ SUCCESS:\033[0m %s\n' "${msg}" | log::_stream
}

log::warn() {
  log::init
  local -r msg="${1}"
  printf '\033[1;33m⚠️  WARNING:\033[0m %s\n' "${msg}" | log::_stream
}

log::debug() {
  # Subshell-safe: do not call log::init if we're in a child shell
  if [[ "${BASH_SUBSHELL:-0}" -gt 0 || "$$" != "${BASHPID:-$$}" ]]; then
    return 0  # Silent no-op
  fi

  log::init
  if [[ "${LOG_DEBUG:-0}" -eq 1 ]]; then
    local -r msg="${1}"
    printf '\033[0;36m🐛 DEBUG:\033[0m %s\n' "${msg}" | log::_stream
  fi
}

log::error() {
  log::init
  local -r msg="${1}"
  printf '\033[1;31m🛑 ERROR:\033[0m %s\n' "${msg}" | log::_stream
  if [[ -n "${BASH_SUBSHELL:-}" && "${BASH_SUBSHELL}" -gt 0 ]]; then
    kill -s TERM "$PPID"
  else
    exit 1
  fi
}

log::function() {
  log::init
  local -r label="${1}"
  shift
  log::info "↪ Running ${label}"
  { "${@}"; } 2>&1 | log::_stream
  log::info "✅ Finished ${label}"
}

log::if_not_dry_run() {
  log::init
  if [[ "${LOG_DRY_RUN:-0}" -eq 0 ]]; then
    "${@}"
  else
    log::info "(dry-run) would run: ${*}"
  fi
}

log::_trap_sigint() {
  log::init
  printf '\n🛑 INTERRUPTED: Caught Ctrl-C (SIGINT)\n' >&2
  log::_backtrace
  exit 130
}

log::_backtrace() {
  log::init
  local i=0 indent=""
  : "${indent}"  # keep shellcheck and intellij happy with scope
  log::_stream <<< $'\n\033[1;36m🔙 BACKTRACE:\033[0m'
  {
    while caller "$i"; do
      indent+="  "
      caller "$i" | sed "s/^/${indent}/"
      ((i++))
    done
  } | log::_stream
}

# --- Stream Handler ---

log::_stream() {
  local input
  input=$(cat)

  [[ -e /dev/fd/5 ]] && printf '%s\n' "${input}" >&5
  [[ -e /dev/fd/6 ]] && printf '%s\n' "${input}" >&6 || printf '%s\n' "${input}"
}
