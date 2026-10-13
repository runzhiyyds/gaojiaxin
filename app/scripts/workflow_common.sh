#!/usr/bin/env bash
# Shared, portable paths and preflight checks; never print private configuration.
WORKFLOW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORKFLOW_APP="${WORKFLOW_ROOT}/app"
WORKFLOW_HELPER="${WORKFLOW_APP}/tool/workflow_support.py"

workflow_require() {
  local tool
  for tool in "$@"; do
    command -v "${tool}" >/dev/null 2>&1 || { echo "缺少 ${tool}，请先安装。" >&2; return 1; }
  done
}

workflow_config() {
  workflow_require python3 flutter || return
  python3 "${WORKFLOW_HELPER}" config "${WORKFLOW_APP}/env.json"
}

workflow_prepare() {
  python3 "${WORKFLOW_HELPER}" cache "${WORKFLOW_APP}" || return
  cd "${WORKFLOW_APP}" || return
  flutter pub get --offline || flutter pub get
}
