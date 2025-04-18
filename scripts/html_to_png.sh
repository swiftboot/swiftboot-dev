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
  local input_html="${1:-}"
  _validate_input "${input_html}"
  _detect_chromium_build
  local temp_html="/tmp/$(basename "${input_html}").wrapped.html"
  local temp_png="/tmp/$(basename "${input_html}" .html).raw.png"
  local final_png="$(basename "${input_html}" .html).png"
  _detect_dark_mode
  _compose_html_wrapper "${input_html}" "${temp_html}"
  _render_chromium "${temp_html}" "${temp_png}"
  _trim_output_png "${temp_png}" "${final_png}"
  log::shutdown
}

function _validate_input() {
  local -r html_file="${1}"
  if [[ -z "${html_file}" || ! -f "${html_file}" ]]; then
    log::error "Input HTML file not provided or does not exist"
  fi
  log::info "Input HTML validated: ${html_file}"
}

function _detect_dark_mode() {
  log::info "Checking for macOS system dark mode"
  local -r dark_mode=$(defaults read -g AppleInterfaceStyle 2>/dev/null || true)
  if [[ "${dark_mode}" == "Dark" ]]; then
    log::info "Detected macOS dark mode"
  else
    log::warn "Unable to verify macOS appearance; using default dark mode"
  fi
}

function _compose_html_wrapper() {
  local -r source_file="${1}"
  local -r dest_file="${2}"
  log::info "Composing full HTML document: ${dest_file}"
  cat >"${dest_file}" <<HEREDOC_HTML
<!DOCTYPE html>
<html><head>
  <meta charset='utf-8'>
  <style>
    body {
      margin: 0;
      padding: 0;
      height: 100%;
      max-height: 16384px;
      overflow: hidden;
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
$(cat "${source_file}")
</body></html>
HEREDOC_HTML
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

function _render_chromium() {
  local -r html_file="${1}"
  local -r out_png="${2}"
  log::info "Rendering with Chromium headless to: ${out_png}"
  local height=32000
  if [[ "${height}" -gt 8000 ]]; then
    height=8000
    log::warn "Window height clamped to macOS texture limit: ${height}"
  fi
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
    --screenshot="${out_png}"
    --window-size=1280,${height}
    --enable-software-rasterizer
    --disable-features=SharedImage
    "file://${html_file}"
  )
  if timeout 10s "${CHROMIUM_PATH}" "${chromium_flags[@]}" 2>&1 | tee >(grep 'bytes written' || true); then
    log::info "Render complete"
  else
    log::error "Chromium did not confirm successful render"
  fi
}

function _trim_output_png() {
  local -r input_png="${1}"
  local -r output_png="${2}"
  log::info "Trimming image"
  magick "${input_png}" -trim +repage "${output_png}"
  log::info "Trimmed PNG saved to: ${output_png}"
}

main "$@"
