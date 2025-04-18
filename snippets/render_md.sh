#!/usr/bin/env bash
# Convert Markdown to HTML with no wrapper

set -euo pipefail

input="${1}"
output="${2:-"${input%.md}.html"}"

pandoc "$input" -f markdown -t html5 -o "$output"

echo "✅ Rendered $input → $output"

