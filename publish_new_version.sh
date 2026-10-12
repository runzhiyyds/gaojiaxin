#!/usr/bin/env bash
# Preserve ./publish_new_version.sh VERSION "NOTE"; --check never publishes.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/app/scripts/workflow_common.sh"
MODE=publish
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) [[ "${MODE}" == publish || "${MODE}" == check ]] || { echo "--check 与 --build-only 不能同时使用。" >&2; exit 2; }; MODE=check; shift ;;
    --build-only) [[ "${MODE}" == publish || "${MODE}" == build ]] || { echo "--check 与 --build-only 不能同时使用。" >&2; exit 2; }; MODE=build; shift ;;
    --help|-h)
      echo '用法：./publish_new_version.sh <版本号> "<更新说明>" [--check|--build-only]'
      echo '--check：只检查配置、工具和蒲公英现有应用；不改版本、不构建、不上传。'
      echo '--build-only：更新本地版本并构建 APK，不上传。'
      exit 0 ;;
    --*) echo "未知参数：$1" >&2; exit 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
[[ ${#POSITIONAL[@]} -ge 1 && ${#POSITIONAL[@]} -le 2 ]] || { echo '请提供版本号，例如 ./publish_new_version.sh 1.6.3 "全面优化" --check' >&2; exit 2; }
VERSION="${POSITIONAL[0]}"
RELEASE_NOTE="${POSITIONAL[1]:-修复问题和性能优化}"
workflow_config
python3 "${WORKFLOW_HELPER}" version-check "${VERSION}"
if [[ "${MODE}" != build ]]; then
  workflow_require curl
  if [[ -f "${WORKFLOW_ROOT}/pgyer_config.sh" ]]; then source "${WORKFLOW_ROOT}/pgyer_config.sh"; fi
  export PGYER_API_KEY="${PGYER_API_KEY:-}"
  python3 "${WORKFLOW_HELPER}" pgyer-check "${WORKFLOW_APP}/env.json"
fi
if [[ "${MODE}" == check ]]; then
  echo "发布命令检查通过：${VERSION}；未修改版本、构建或上传。"
  exit 0
fi
workflow_prepare
flutter test --no-pub
python3 "${WORKFLOW_HELPER}" set-version "${WORKFLOW_APP}/pubspec.yaml" "${VERSION}"
if [[ -f "${WORKFLOW_APP}/assets/icons/APP_ICON.jpg" ]]; then
  echo "更新应用图标…"
  dart run flutter_launcher_icons
fi
echo "构建爱情心意值 ${VERSION}…"
flutter build apk --release --no-pub --dart-define-from-file="${WORKFLOW_APP}/env.json"
APK_PATH="${WORKFLOW_APP}/build/app/outputs/flutter-apk/app-release.apk"
[[ -s "${APK_PATH}" ]] || { echo "构建没有生成有效 APK。" >&2; exit 1; }
echo "APK 已生成：${APK_PATH}"
if [[ "${MODE}" == build ]]; then
  echo "仅构建完成，未上传蒲公英。"
  exit 0
fi
python3 "${WORKFLOW_HELPER}" upload "${APK_PATH}" "${RELEASE_NOTE}"
