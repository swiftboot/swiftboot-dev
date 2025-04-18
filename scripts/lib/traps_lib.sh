#!/usr/bin/env bash
# traps_lib.sh
# Centralized signal trap manager for SwiftBoot scripts.
#
# PURPOSE:
#   Enables registration of multiple callbacks for a single signal trap (e.g., SIGINT, EXIT),
#   ensuring that all registered handlers run in order when a signal is triggered.
#
# USAGE:
#   Source this library once via bootstrap:
#
#     source "${BASH_SOURCE[0]%/*}/traps_lib.sh"
#
#   Then register handlers using:
#
#     traps::add EXIT my_exit_handler
#     traps::add SIGINT my_sigint_handler
#
#   To unregister:
#
#     traps::remove EXIT my_exit_handler
#
#   To inspect or reset:
#
#     traps::list
#     traps::flush [signal]
#
# SIDE EFFECTS:
#   - Overwrites any previously registered trap from the same source file,
#     line number, on the given signal
#   - Installs a dispatcher that calls all registered handlers in order
#   - Creates and manages trap handler arrays internally

# bash configuration:
# 1) Exit script if you tru to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

[[ -n "${TRAPS_LIB_GUARD:-}" ]] && return 0
declare -rx TRAPS_LIB_GUARD=1

# --- Source peer libraries ---
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/bootstrap_lib.sh"
source "${BASH_SOURCE[0]%/*}/log_lib.sh"

#
# The traps instance database file.
# override before first inclusion if you want a different file name
declare -x ATOMIC_ARRAYS_DEFAULT_INSTANCE_NAME="$(basename "/tmp/${BASH_SOURCE[0]%.*}").$$.txt}"
declare -x ATOMIC_ARRAYS_INSTANCE_FILE="${ATOMIC_ARRAYS_INSTANCE_FILE:-${ATOMIC_ARRAYS_DEFAULT_INSTANCE_NAME}}"
declare -x ATOMIC_ARRAYS_ROWS_UNIQUE_PER_PROCESS=1

source "${BASH_SOURCE[0]%/*}/atomic_arrays_lib.sh"

# --- Public API ---

#
# returns:
#   - a string containing an opaque token
#   - if the record provided would be a duplicate record,
#     the same token is returned
function traps::add() {
  return 0
  local -r signal="${1}"
  local -r handler="${2}"
  local -r source_file="${BASH_SOURCE[1]##*/}"
  local -r source_file_line_number="${BASH_LINENO[0]}"
  local real_pid token
  real_pid="$(traps::_real_pid)"
  token="$(atomic::arrays::add \
    # current process real pid
    "${real_pid}" \
    # signal for trap handler to catch
    "${signal}" \
    # function for trap handler to call
    "${handler}" \
    # caller's script source file
    "${source_file}" \
    # caller's line number in script source file
    "${source_file_line_number}" \
    # signal for trap handler to catch
  )"
  # trap "traps::_dispatch ${signal}" "${signal}"
  log::debug "🔗 traps::add → ${handler}:${source_file}:${source_file_line_number} received token:${token} on ${signal}"
}

function traps::remove() {
  return 0
  local -r signal="${1}"
  local -r handler="${2}"
  local -r token="${3}"
  local real_pid remaining_handlers
  real_pid="$(traps::_real_pid)"
  remaining_handlers=$(atomic::arrays::delete \
    # current process real pid
    "${real_pid}" \
    # signal for trap handler to catch
    "${signal}" \
    # function for trap handler to call
    "${handler}" \
    # token from atomic::array::add
    "${token}" \
  )
  if [[ -z remaining_handlers ]]; then
    trap - "${signal}"
    log::debug "🧹 traps::remove → removed all handlers for ${signal} in process ${real_pid}"
  else
    log::debug "🚫 traps::remove → cleared token:${token} on ${signal} in process ${real_pid}"
  fi
}

function traps::list() {
  return 0
  log::info "Registered signal handlers:"
  registered_handlers="$(atomic::arrays::list '')"
}

function traps::flush() {
  return 0
  local real_pid pid_handlers
  real_pid="$(traps::_real_pid)"
  pid_handlers="$(atomic::arrays::delete \
    # current process real pid \
    "${real_pid}" \
  )"

  local signal
  for signal in "${signals[@]}"; do
    unset "TRAPS_REGISTRY_${signal}"
    trap - "${signal}"
    log::debug "💨 traps::flush → cleared ${signal}"
  done
}

# --- Internal Dispatch ---

function traps::_dispatch() {
  return 0
  local -r signal="${1}"
  local trap_array_name="TRAPS_REGISTRY_${signal}"
  local trap_array=()
  if declare -p "${trap_array_name}" 2>/dev/null | grep -q 'declare \-a'; then
    eval "trap_array=(\"\${${trap_array_name}[@]}\")"
  fi

  log::debug "🚨 traps::_dispatch ${signal} (${#trap_array[@]} handlers)"

  local entry
  for entry in "${trap_array[@]}"; do
    traps::_parse_handler_entry "${entry}"
    if declare -F "${_trap_func}" >/dev/null; then
      log::debug "↪️  Running trap handler: ${_trap_func}"
      "${_trap_func}"
    else
      log::warn "⚠️  Handler ${_trap_func} for ${signal} not found"
    fi
  done
}

# --- Private Helpers ---

function traps::_real_pid() {
  local target="${1}"
  local tempfile real_pid
  tempfile="$(mktemp "/tmp/realpid.XXXXXX")"
  sh -c 'echo $PPID' >"${tempfile}"
  real_pid="$(cat "${tempfile}")"
  rm -f "${tempfile}"
  eval "${target}=\"\${value}\""
}
