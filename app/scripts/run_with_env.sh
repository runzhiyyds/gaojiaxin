#!/usr/bin/env bash
# Compatible entry: automatically chooses connected Android phone or Chrome.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec "${PROJECT_ROOT}/test_app.sh" "$@"
