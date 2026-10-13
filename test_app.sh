#!/usr/bin/env bash
# One entry for Chrome, Android, automated tests and performance verification.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/app/scripts/workflow_common.sh"
MODE=auto
DEVICE=""
CHECK=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    auto|web|phone|profile|smoke|test|menu) MODE="$1"; shift ;;
    --device) [[ $# -ge 2 ]] || { echo "--device 需要设备 ID" >&2; exit 2; }; DEVICE="$2"; shift 2 ;;
    --check) CHECK=true; shift ;;
    --help|-h)
      echo "用法：./test_app.sh [auto|web|phone|profile|smoke|test|menu] [--device ID] [--check]"
      echo "auto：优先已连接的 Android 手机，否则 Chrome；menu：退出运行后可继续切换。"
      echo "profile：真机性能验证；smoke：真机自动启动测试；test：单元/组件测试。"
      exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done
TMP_WORKFLOW="$(mktemp -d "${TMPDIR:-/tmp}/love-story-verify.XXXXXX")"
trap 'rm -rf "${TMP_WORKFLOW}"' EXIT

run_mode() {
  local selected="$1" target config_path
  workflow_config || return
  if [[ "${selected}" == test ]]; then
    if "${CHECK}"; then echo "检查通过：将运行单元/组件测试，不会启动应用。"; return; fi
    workflow_prepare || return
    flutter test --no-pub || return
    return
  fi
  flutter devices --machine > "${TMP_WORKFLOW}/devices.json" || return
  if [[ -n "${DEVICE}" ]]; then
    target="$(python3 "${WORKFLOW_HELPER}" device "${TMP_WORKFLOW}/devices.json" "${selected}" "${DEVICE}")" || return
  else
    target="$(python3 "${WORKFLOW_HELPER}" device "${TMP_WORKFLOW}/devices.json" "${selected}")" || return
  fi
  config_path="${WORKFLOW_APP}/env.json"
  if [[ "${target}" == chrome ]]; then
    [[ -f "${WORKFLOW_APP}/web/index.html" ]] || { echo "项目缺少 Web 入口。" >&2; return 1; }
    python3 "${WORKFLOW_HELPER}" web-config "${config_path}" "${TMP_WORKFLOW}/web-env.json" || return
    config_path="${TMP_WORKFLOW}/web-env.json"
  fi
  if "${CHECK}"; then
    echo "检查通过：模式=${selected}，目标=${target}；不会构建、安装或上传。"
    return
  fi
  workflow_prepare || return
  case "${selected}" in
    smoke)
      # flutter test uninstalls the app at completion; keep the owner's data.
      flutter drive --no-pub --driver=test_driver/integration_driver.dart \
        --target=integration_test/app_test.dart --keep-app-running \
        -d "${target}" --dart-define-from-file="${config_path}" ;;
    profile)
      echo "真机性能模式；退出运行按 q。"
      flutter run --no-pub --profile -d "${target}" --dart-define-from-file="${config_path}" ;;
    *)
      echo "启动验证；r 热重载，R 重启，q 退出。Web 不包含 Android 安装更新和原生推送。"
      if [[ "${target}" == chrome ]]; then
        flutter run --no-pub --no-web-resources-cdn -d "${target}" --dart-define-from-file="${config_path}"
      else
        flutter run --no-pub -d "${target}" --dart-define-from-file="${config_path}"
      fi ;;
  esac
}

if [[ "${MODE}" == menu ]]; then
  [[ -t 0 ]] || { echo "menu 需要交互终端，请直接指定 web/phone 等模式。" >&2; exit 2; }
  while true; do
    echo "1 自动选择  2 Web  3 Android 手机  4 真机性能  5 真机启动测试  6 单元测试  q 退出"
    read -r -p "请选择：" choice
    case "${choice}" in
      1) run_mode auto || echo "本次验证未成功，可重新选择。" ;;
      2) run_mode web || echo "本次验证未成功，可重新选择。" ;;
      3) run_mode phone || echo "本次验证未成功，可重新选择。" ;;
      4) run_mode profile || echo "本次验证未成功，可重新选择。" ;;
      5) run_mode smoke || echo "本次验证未成功，可重新选择。" ;;
      6) run_mode test || echo "本次验证未成功，可重新选择。" ;;
      q|Q) break ;;
      *) echo "请选择 1–6 或 q。" ;;
    esac
  done
else
  run_mode "${MODE}"
fi
