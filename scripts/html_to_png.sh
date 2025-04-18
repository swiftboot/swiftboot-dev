#!/usr/bin/env bash
# html_to_png.sh
# Render an HTML file to a PNG image using headless Chromium and ImageMagick

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
# bootstrap interface to libraries: works in both container and GITROOT contexts
source "${BASH_SOURCE[0]%/scripts/*}/scripts/lib/bootstrap_lib.sh"

function main() {
  log::init
  log::info 'Starting HTML to PNG conversion'

  local -r input_html="${1:-}"
  if [[ ! -f "${input_html}" ]]; then
    log::error "Input HTML file not found: ${input_html}"
  fi
  log::info "Input HTML validated: ${input_html}"

  local is_dark_mode=1
  if system_profiler SPDisplaysDataType | grep -q 'Interface Style: Dark'; then
    log::info 'Detected macOS dark mode'
  else
    log::warn 'Unable to verify macOS appearance; using default dark mode'
  fi

  # Compose wrapped HTML with inline CSS
  local -r temp_html="/tmp/${input_html##*/}.wrapped.html"
  log::info "Composing full HTML document: ${temp_html}"
  cat > "${temp_html}" <<HEREDOC
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    body {
      font-family: sans-serif;
      margin: 0;
      padding: 2rem;
      background: #111;
      color: #eee;
    }
    @media (prefers-color-scheme: dark) {
      body {
        background: #111;
        color: #eee;
      }
    }
  </style>
</head>
<body>
HEREDOC
  cat "${input_html}" >> "${temp_html}"
  printf '</body></html>\n' >> "${temp_html}"

  # Define Chromium output
  local -r temp_png="/tmp/${input_html##*/}.raw.png"
  local -r final_png="${input_html%.html}.png"
  log::info "Rendering with Chromium headless to: ${temp_png}"

  local -r CHROMIUM_PATH="/Applications/Chromium.app/Contents/MacOS/Chromium"
  local -a chromium_flags=(
    --headless
    --no-sandbox
    --disable-gpu
    --disable-software-rasterizer
    --disable-gl-drawing-for-tests
    --use-gl=disabled
    --disable-software-compositing-fallback
    --disable-features=UseMacSystemKeychain
    --disable-sync
    --run-all-compositor-stages-before-draw
    --no-first-run
    --no-default-browser-check
    --password-store=basic
    --user-data-dir="/tmp/chrome-profile-$$"
    --virtual-time-budget=3000
    --hide-scrollbars
    --force-dark-mode
    --blink-settings=preferredColorScheme=2
    --screenshot="${temp_png}"
    --window-size=1280,10000
    "file://${temp_html}"
  )

  if ! timeout 10s "${CHROMIUM_PATH}" "${chromium_flags[@]}" 2>&1 | tee >(grep 'bytes written' || true); then
    if [[ -s "${temp_png}" ]]; then
      log::warn 'Chromium exited abnormally, but PNG file was produced'
    else
      log::error 'Chromium did not confirm successful render'
    fi
  fi

  # Crop the resulting image
  log::info 'Cropping rendered image using ImageMagick'
  if ! command -v magick >/dev/null; then
    log::error 'ImageMagick (magick) not installed'
  fi
  magick convert "${temp_png}" -trim +repage "${final_png}"
  log::info "Trimmed PNG saved to: ${final_png}"

  log::shutdown
}

main "$@"
