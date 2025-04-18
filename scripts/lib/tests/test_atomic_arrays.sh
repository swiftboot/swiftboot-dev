#!/usr/bin/env bash
# test_atomic_arrays.sh
# Full test suite for process_state_db.sh using SwiftBoot log_lib on macOS

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

# default globals to configure logging
declare LOG_FILE
LOG_FILE="/tmp/$(basename "/tmp/${BASH_SOURCE[0]%.*}").$(date +%s).log"
export LOG_FILE
declare LOG_TS
LOG_TS="$(date +%Y%m%d_%H%M%S)"
export LOG_TS
export LOG_ARCHIVE=0
export LOG_DRY_RUN=0
export LOG_DEBUG=0

# --- Instance File Setup ---
declare -r TEST_FILE="/tmp/atomic_arrays_test_data.${LOG_TS}.txt"
declare -x ATOMIC_ARRAYS_INSTANCE_FILE="${TEST_FILE}"

#export PS4='+ [${BASH_SOURCE}:${LINENO} PID=$$ DEPTH=${SHLVL}] '
#set -x

# bootstrap interface to libraries: works in both container and GITROOT contexts
source "${BASH_SOURCE[0]%/scripts/*}/scripts/lib/bootstrap_lib.sh"
source "$(bootstrap::resolve_library_path './lib/log_lib.sh')" > /dev/stderr

function test::setup() {
  atomic::arrays::destroy || true
}

function test::teardown() {
  atomic::arrays::destroy || true
}

function test::expect_eq() {
  local -r expected="${1}"
  local -r actual="${2}"
  if [[ "${actual}" != "${expected}" ]]; then
    log::error "Expected [${expected}], got [${actual}]"
    exit 1
  fi
}

function test::get_pid() {
  ( printf '%d' "${PPID}")
}

# --- Tests ---

function test::basic_add_and_get() {
  test::setup
  local pid
  pid="$(test::get_pid)"
  atomic::arrays::add "apple" "red" "fruit" "${pid}" || true
  local result
  atomic::arrays::assign_var result atomic::arrays::get "apple" "red" "fruit"
  test::expect_eq $'apple\tred\tfruit\t'"${pid}" "${result}"
  log::success "basic_add_and_get"
  test::teardown
}

function test::add_duplicate_same_pid() {
  test::setup
  local pid
  pid="$(test::get_pid)"
  atomic::arrays::add "banana" "yellow" "fruit" "${pid}" || true
  atomic::arrays::add "banana" "yellow" "fruit" "${pid}" || true
  local matches
  atomic::arrays::assign_var matches atomic::arrays::get "banana"
  count=$(wc -l <<<${matches})
  test::expect_eq "1" $(( count ))
  log::success "add_duplicate_same_pid"
  test::teardown
}

function test::add_duplicate_different_pid() {
  test::setup
  local saved_uniqueness="${ATOMIC_ARRAYS_ROWS_UNIQUE_PER_PROCESS}"
  export ATOMIC_ARRAYS_ROWS_UNIQUE_PER_PROCESS=0
  local parent_pid="${PPID}"
  atomic::arrays::add "grape" "purple" "fruit" "${parent_pid}" || true
  # ✅ Force fork with a backgrounded subshell
  (
    atomic::arrays::add "grape" "purple" "fruit" "${parent_pid}"
  ) &
  wait  # ensure the background add finishes before we validate

  local matches
  atomic::arrays::assign_var matches atomic::arrays::get "grape"
  count=$(grep -v '^$' <<<"${matches}" | wc -l || true)
  test::expect_eq "2" $(( count ))
  log::success "add_duplicate_different_pid"
  export ATOMIC_ARRAYS_ROWS_UNIQUE_PER_PROCESS="${saved_uniqueness}"
  set +x
  test::teardown
}

function test::delete_entry() {
  test::setup
  local pid
  pid="$(test::get_pid)"
  atomic::arrays::add "kiwi" "green" "fruit" "${pid}" || true
  atomic::arrays::delete "kiwi" "green" "fruit"
  local matches
  atomic::arrays::assign_var matches atomic::arrays::get "kiwi"
  count=$(grep -v '^$' <<<"${matches}" | wc -l || true)
  test::expect_eq "0" $(( count ))
  log::success "delete_entry"
  test::teardown
}

function test::get_partial_key() {
  test::setup
  local pid
  pid="$(test::get_pid)"
  atomic::arrays::add "lemon" "yellow" "fruit" "${pid}" || true
  local result
  atomic::arrays::assign_var result atomic::arrays::get "lemon"
  test::expect_eq $'lemon\tyellow\tfruit\t'"${pid}" "${result}"
  log::success "get_partial_key"
  test::teardown
}

function test::select_multiple_rows() {
  test::setup
  local pid
  pid="$(test::get_pid)"
  atomic::arrays::add "berry" "blue" "fruit" "${pid}" || true
  atomic::arrays::add "berry" "red" "fruit" "${pid}" || true
  local matches
  atomic::arrays::assign_var matches atomic::arrays::get "berry"
  count=$(grep -v '^$' <<<"${matches}" | wc -l || true)
  test::expect_eq "2" $(( count ))
  log::success "select_multiple_rows"
  test::teardown
}

function test::destroy_database() {
  test::setup
  local pid
  pid="$(test::get_pid)"
  atomic::arrays::add "plum" "purple" "fruit" "${pid}" || true
  atomic::arrays::destroy
  if [[ -f "${TEST_FILE}" ]]; then
    log::error "File still exists after destroy"
    exit 1
  fi
  log::success "destroy_database"
}

function test::atomic_arrays_add_on_empty_file() {
  : > "${ATOMIC_ARRAYS_INSTANCE_FILE}"
  atomic::arrays::add "maui" "butter" "chicken" $$
  local result
  result="$(cat "${ATOMIC_ARRAYS_INSTANCE_FILE}")"
  local count
  count=$(echo "${result}" | wc -l | tr -d ' ')
  test::expect_eq "1" "${count}" "Expected 1 record after add on empty file"
  log::success "atomic_arrays_add_on_empty_file"
}

function test::atomic_arrays_get_on_empty_file() {
  : > "${ATOMIC_ARRAYS_INSTANCE_FILE}"
  local record
  atomic::arrays::assign_var record atomic::arrays::get "oahu" "frozen" "vegetables"
  local value="${record:-}"
  if [[ -n "${value}" ]]; then
    log:error "Expected no value assigned from get on empty file"
  else
    log::success "atomic_arrays_get_on_empty_file"
  fi
}

function test::atomic_arrays_delete_on_empty_file() {
  : > "${ATOMIC_ARRAYS_INSTANCE_FILE}"
  atomic::arrays::delete "no" "such" "row"
  local result count
  result="$(cat "${ATOMIC_ARRAYS_INSTANCE_FILE}")"
  count=$(grep -v '^$' <<<"${result}" | wc -l || true)
  test::expect_eq "0" "$((count))" "Expected 0 records after delete on empty file"
  log::success "atomic_arrays_delete_on_empty_file"
}

function test::atomic_arrays_destroy_on_empty_file() {
  : > "${ATOMIC_ARRAYS_INSTANCE_FILE}"
  atomic::arrays::destroy
  if [[ -f "${ATOMIC_ARRAYS_INSTANCE_FILE}" ]]; then
    log::error "Expected backing file to be deleted"
  else
    log::success "atomic_arrays_destroy_on_empty_file"
  fi
}

function test::atomic_arrays_list_on_empty_file() {
  : > "${ATOMIC_ARRAYS_INSTANCE_FILE}"
  local result count
  atomic::arrays::assign_var result atomic::arrays::list "non" "existent" "keys"
  count=$(grep -v '^$' <<<"${result}" | wc -l || true)
  test::expect_eq "0" "$((count))" "Expected 0 records from list on empty file"
  log::success "atomic_arrays_list_on_empty_file"
}

function test::empty_files() {
  test::atomic_arrays_add_on_empty_file
  test::atomic_arrays_get_on_empty_file
  test::atomic_arrays_delete_on_empty_file
  test::atomic_arrays_destroy_on_empty_file
  test::atomic_arrays_list_on_empty_file
}

# --- Test Runner ---

function test::run_all() {
  log::init
  log::info "📦 Starting atomic array test suite"
  echo "pid v1: $$"
  echo "pid v2: $(eval 'echo -n "${PPID}"')"
  test::basic_add_and_get
  test::add_duplicate_same_pid
  test::add_duplicate_different_pid
  test::delete_entry
  test::get_partial_key
  test::select_multiple_rows
  test::destroy_database
  test::empty_files
  log::success "🎉 All atomic array tests passed"
  log::shutdown
}

trap "[[ -f '${ATOMIC_ARRAYS_INSTANCE_FILE}' ]] && cat '${ATOMIC_ARRAYS_INSTANCE_FILE}'" EXIT
test::run_all

