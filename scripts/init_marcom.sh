#!/usr/bin/env bash
# init_sb_public_site.sh
# Initializes the SB public static site repo structure with GitHub Pages workflow

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

function log() {
  printf '[init_sb_site] %s\n' "${1}"
}

function main() {
  local repo_dir="sb-public-site"
  local -r workflow_dir=".github/workflows"

  log "Creating static site directory: ${repo_dir}"
  mkdir -p "${repo_dir}/assets/css"
  mkdir -p "${repo_dir}/assets/js"
  mkdir -p "${repo_dir}/assets/img"
  mkdir -p "${repo_dir}/${workflow_dir}"

  log "Adding index.html"
  cat > "${repo_dir}/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>SB Secure Builders</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@picocss/pico@1/css/pico.min.css">
</head>
<body>
  <main class="container">
    <header>
      <h1>SB Secure Builders</h1>
      <p>Easy. High Impact. For your hyperscaler and onprem needs.</p>
    </header>
    <footer>
      <p>© SB Inc.</p>
    </footer>
  </main>
</body>
</html>
EOF

  log "Adding README.md"
  echo "# SB Public Site" > "${repo_dir}/README.md"

  log "Adding LICENSE"
  cat > "${repo_dir}/LICENSE" <<EOF
Apache License 2.0
https://www.apache.org/licenses/LICENSE-2.0
EOF

  log "Adding GitHub Pages deploy workflow"
  cat > "${repo_dir}/${workflow_dir}/deploy.yml" <<'EOF'
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Pages
        uses: actions/configure-pages@v3

      - name: Upload site
        uses: actions/upload-pages-artifact@v2
        with:
          path: '.'

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v2
EOF

  log "Initializing Git repo"
  cd "${repo_dir}"
  git init
  git add .
  git commit -m "Initial commit: Static site scaffold with GitHub Pages deploy workflow"

  log "Done. Repo initialized in ${repo_dir}/"
}

main "$@"

