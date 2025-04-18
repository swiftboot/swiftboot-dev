#!/usr/bin/env bash
# html_to_png.sh
# Converts HTML to a PNG screenshot using headless Chromium on macOS

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

# DRYness
source "${BASH_SOURCE[0]%/scripts/*}/scripts/lib/bootstrap_lib.sh"

function main() {
  log::init

  local input_html="${1:-}"  # required argument
  if [[ -z "${input_html}" || ! -f "${input_html}" ]]; then
    log::error "Input HTML file not provided or does not exist"
  fi
  log::info "Input HTML validated: ${input_html}"

  _detect_chromium_build

  local -r temp_html="/tmp/$(basename "${input_html}").wrapped.html"
  local -r temp_png="/tmp/$(basename "${input_html}").raw.png"
  local -r final_png="$(basename "${input_html}" .html).png"

  log::info "Checking for macOS system dark mode"
  local -r system_dark_mode=$(defaults read -g AppleInterfaceStyle 2>/dev/null || true)
  if [[ "${system_dark_mode}" == "Dark" ]]; then
    log::info "Detected macOS dark mode"
  else
    log::warn "Unable to verify macOS appearance; using default dark mode"
  fi

  log::info "Composing full HTML document: ${temp_html}"
  cat >"${temp_html}" <<HEREDOC_HTML
<!DOCTYPE html>
<html><head>
  <meta charset='utf-8'>
  <style>
    body {
      background-color: #121212;
      color: #eee;
      font-family: -apple-system, sans-serif;
      margin: 2em;
    }
    a { color: #81d4fa; }
    h1, h2, h3, h4 { color: #fff; }
  </style>
</head>
<body>
$(cat "${input_html}")
</body></html>
HEREDOC_HTML

  log::info "Rendering with Chromium headless to: ${temp_png}"

  local -r CHROMIUM_PATH="/Applications/Chromium.app/Contents/MacOS/Chromium"

  local -a chromium_flags=(
    --headless
    --no-sandbox
    --disable-features=UseMacSystemKeychain
    --use-mock-keychain
    --password-store=basic
    --disable-sync
    --disable-background-networking
    --disable-client-side-phishing-detection
    --no-first-run
    --no-default-browser-check
    --disable-default-apps
    --run-all-compositor-stages-before-draw
    --user-data-dir="/tmp/chrome-profile-$$"
    --virtual-time-budget=3000
    --hide-scrollbars
    --force-dark-mode
    --blink-settings=preferredColorScheme=2
    --screenshot="${temp_png}"
    --window-size=1280,10000
    "file://${temp_html}"
  )

  if timeout 10s "${CHROMIUM_PATH}" "${chromium_flags[@]}" 2>&1 | tee >(grep 'bytes written' || true); then
    log::info "Render complete. Trimming image"
    magick convert "${temp_png}" -trim +repage "${final_png}"
    log::info "Trimmed PNG saved to: ${final_png}"
  else
    log::error "Chromium did not confirm successful render"
  fi

  log::shutdown
}

function _detect_chromium_build() {
  CHROMIUM_PATH="/Applications/Chromium.app/Contents/MacOS/Chromium"
  if [[ ! -x "${CHROMIUM_PATH}" ]]; then
    log::error "Chromium binary not found at ${CHROMIUM_PATH}"
  fi
  local version_output
  version_output="$(${CHROMIUM_PATH} --version 2>/dev/null || true)"
  log::info "Chromium version: ${version_output}"
  case "${version_output}" in
    *"Chromium"*) log::info "Detected ungoogled Chromium build" ;;
    *) log::warn "Chromium is not an ungoogled (Eloston) build — you may see keychain prompts or crashes" ;;
  esac
}

main "$@"
