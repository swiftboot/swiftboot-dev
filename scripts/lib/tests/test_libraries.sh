#!/usr/bin/env bash
# test_libraries.sh
# Test harness for bootstrap, log, and traps libraries with normal and torture test lanes.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

# default globals to configure logging
export LOG_FILE="/tmp/test_libraries.$(date +%s).log"
export LOG_TS="$(date +%Y%m%d_%H%M%S)"
export LOG_ARCHIVE=0
export LOG_DRY_RUN=0
export LOG_DEBUG=0

#export PS4='+ [${BASH_SOURCE}:${LINENO} PID=$$ DEPTH=${SHLVL}] '
#set -x

# bootstrap interface to libraries: works in both container and GITROOT contexts
source "${BASH_SOURCE[0]%/scripts/*}/scripts/lib/bootstrap_lib.sh"
source "$(bootstrap::resolve_library_path './lib/log_lib.sh')" > /dev/stderr
source "$(bootstrap::resolve_library_path './lib/traps_lib.sh')" > /dev/stderr

function main() {
  local -r test_group="${1:-help}"
  setup_test_env
  validate_log_env
  log::init
  dispatch_test_group "${test_group}"
  wait  # ✅ ensure all background jobs finish
  log::shutdown
}

function validate_log_env() {
  [[ -z "${LOG_FILE:-}" ]] && printf '🛑 ERROR: LOG_FILE is not set\n' >&2 && exit 1
  [[ -z "${LOG_TS:-}" ]] && printf '🛑 ERROR: LOG_TS is not set\n' >&2 && exit 1
  [[ -z "${LOG_ARCHIVE:-}" ]] && printf '🛑 ERROR: LOG_ARCHIVE is not set\n' >&2 && exit 1
  [[ -z "${LOG_DRY_RUN:-}" ]] && printf '🛑 ERROR: LOG_DRY_RUN is not set\n' >&2 && exit 1
  [[ -z "${LOG_DEBUG:-}" ]] && printf '🛑 ERROR: LOG_DEBUG is not set\n' >&2 && exit 1
  return 0
}

function setup_test_env() {
  export LOG_FILE="/tmp/test_libraries.$(date +%s).log"
  export LOG_TS="$(date +%Y%m%d_%H%M%S)"
  export LOG_ARCHIVE=0
  export LOG_DRY_RUN=0
  export LOG_DEBUG=1
  return 0
}

function dispatch_test_group() {
  local -r group="${1}"
  case "${group}" in
    normal)  run_normal_tests ;;
    torture) run_torture_tests ;;
    all)     run_all_tests ;;
    help|*)  print_help ;;
  esac
}

function run_normal_tests() {
  log::info '🔹 Running normal usage tests...'
#  test_log_info
#  test_log_warn
#  test_log_error
#  test_log_success
#  test_log_debug
#  test_log_trace
#  test_log_function
#  test_log_if_not_dry_run
#  test_bootstrap_get_results_dir
#  test_bootstrap_get_scripts_dir
#  test_bootstrap_get_src_dir
  test_trap_registration
  test_traps_list_and_flush
}

function run_torture_tests() {
  log::info '🔥 Running torture tests (subshells, concurrency, traps)...'
  simulate_subshell_race
  simulate_parallel_logging
  ( simulate_trap_storm ) || log::warn 'Expected early exit from SIGINT storm'
}

function run_all_tests() {
  run_normal_tests
  run_torture_tests
}

function print_help() {
  printf '%s\n' "🧪 Usage: ${0##*/} <test group>"
  printf '%s\n' "Available test groups:"
  printf '  %-10s%s\n' 'normal'  'Standard unit tests for all libraries'
  printf '  %-10s%s\n' 'torture' 'Simulated race and signal tests (traps, subshells, parallel logs)'
  printf '  %-10s%s\n' 'all'     'Run all test groups sequentially'
  printf '  %-10s%s\n' 'help'    'Show this help message'
}

function test_log_info() {
  log::info 'ℹ️  Info message test' && log::success 'log::info succeeded.' || log::fail 'log::info failed.'
}

function test_log_warn() {
  log::warn '⚠️  Warn message test' && log::success 'log::warn succeeded.' || log::fail 'log::warn failed.'
}

function test_log_error() {
  ( log::error '🛑 Error message test (expect exit)' ) || log::success 'log::error triggered exit as expected.'
}

function test_log_success() {
  log::success '✅ Success message test'
}

function test_log_debug() {
  export LOG_DEBUG=1
  log::debug '🐛 Debug message with LOG_DEBUG=1'
  export LOG_DEBUG=0
  log::debug '⛔ Debug message with LOG_DEBUG=0 (should not show)'
}

function test_log_trace() {
  log::trace
  log::info 'Tracing ON'
  log::untrace
  log::info 'Tracing OFF'
}

function test_log_function() {
  dummy_fn() { log::info '👷 Running inside dummy_fn'; sleep 0.1; }
  log::function 'dummy_fn execution' dummy_fn
}

function test_log_if_not_dry_run() {
  export LOG_DRY_RUN=1
  log::if_not_dry_run echo '❌ This should be a dry-run log only.'
  export LOG_DRY_RUN=0
  log::if_not_dry_run echo '✅ This should actually run.'
}

function test_bootstrap_get_results_dir() {
  local dir
  dir="$(bootstrap::get_results_dir 'audit')"
  [[ -d "${dir}" ]] && log::success "get_results_dir: ${dir}" || log::fail "get_results_dir failed"
}

function test_bootstrap_get_scripts_dir() {
  local dir
  dir="$(bootstrap::get_scripts_dir)"
  [[ -d "${dir}" ]] && log::success "get_scripts_dir: ${dir}" || log::fail "get_scripts_dir failed"
}

function test_bootstrap_get_src_dir() {
  local dir
  dir="$(bootstrap::get_src_dir)"
  [[ -d "${dir}" ]] && log::success "get_src_dir: ${dir}" || log::fail "get_src_dir failed"
}

function test_trap_registration() {
  traps::add EXIT trap_cleanup_handler
  log::success "Completed: test_trap_registration"
}

function trap_cleanup_handler() {
  log::info '🧼 Trap cleanup ran successfully.'
  log::success "Completed: trap_cleanup_handler"
}

function test_traps_list_and_flush() {
  traps::add EXIT test_handler
  traps::list
  traps::flush EXIT
  log::success "Completed: test_traps_list_and_flush"
}

function test_handler() {
  log::info "🧪 test_handler ran"
}

function simulate_subshell_race() {
  log::info ''
  log::info 'stating subshell races'
  traps::list
  local i
  for i in {1..5}; do
    (
      log::init
      log::info "[Subshell ${i}] Initialized log."
      sleep 0.$((RANDOM % 5))
      log::info "[Subshell ${i}] Exiting..."
      wait
      exit 0
    ) &
  done
  wait
  log::success "We have completed simulate_subshell_race"
}

function simulate_trap_storm() {
  (
    traps::add SIGINT trap_sigint_handler
    traps::add EXIT trap_exit_handler
    kill -s SIGINT $$
    exit 0
  ) &
  wait
  log::success "We have completed simulate_trap_storm"
}

function simulate_parallel_logging() {
  for j in {1..3}; do
    (
      for k in {1..5}; do
        log::info "[Parallel ${j}] log line ${k}"
        sleep 0.$((RANDOM % 3))
      done
    ) &
  done
  wait
  log::success "We have completed simulate_parallel_logging"
}

function trap_sigint_handler() {
  if [[ "${BASH_SUBSHELL:-0}" -gt 0 || "$$" != "${BASHPID:-$$}" ]]; then
    printf '[trap] 🛑 SIGINT trap executed. (subshell, skipping log::info)\n' >&2
  else
    log::warn '🛑 SIGINT trap executed.'
  fi
}

function trap_exit_handler() {
  if [[ "${BASH_SUBSHELL:-0}" -gt 0 || "$$" != "${BASHPID:-$$}" ]]; then
    printf '[trap] 📤 EXIT trap executed (subshell, skipping log::info)\n' >&2
  else
    log::info '📤 EXIT trap executed from torture subshell.'
  fi
}

main "${1:-}"
