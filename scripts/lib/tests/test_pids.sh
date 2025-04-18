#!/usr/bin/env bash
# pid_test.sh
# Show how $$ and $PPID behave in different contexts (top-level, subshell, command substitution)

set -o nounset
set -o errexit
set -o pipefail

function section() {
  printf '\n--- %s ---\n' "$1"
}

function show_pids_top_level() {
  section "1. Top-level in Bash"
  printf 'BASH $$=%s PPID=%s\n' "$$" "$PPID"

  section "1b. Top-level via sh"
  sh -c 'printf "sh $$=%s PPID=%s\n" "$$" "$PPID"'
}

function show_pids_command_substitution() {
  section "2. Inside \$() command substitution"
  result="$(printf 'BASH $$=%s PPID=%s\n' "$$" "$PPID")"
  printf '%s\n' "$result"

  section "2b. Inside \$() via sh"
  result="$(sh -c 'printf "sh $$=%s PPID=%s\n" "$$" "$PPID"')"
  printf '%s\n' "$result"
}

function show_pids_subshell() {
  section "3. Inside ( ) subshell"
  (
    printf 'BASH $$=%s PPID=%s\n' "$$" "$PPID"
  ) &
  wait

  section "3b. Inside ( ) via sh"
  (
    sh -c 'printf "sh $$=%s PPID=%s\n" "$$" "$PPID"'
  ) &
  wait
}

# Main
show_pids_top_level
show_pids_command_substitution
show_pids_subshell

