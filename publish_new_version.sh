#!/usr/bin/env bash
# Preserve ./publish_new_version.sh VERSION "NOTE"; --check never publishes.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/app/scripts/workflow_common.sh"
STAGE="参数和配置检查"
trap 'echo "发布未完成：${STAGE}失败，流程已停止。" >&2' ERR
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
STAGE="依赖准备"
workflow_prepare
STAGE="自动化测试"
echo "[1/4] 运行自动化测试…"
flutter test --no-pub
STAGE="版本和图标准备"
echo "[2/4] 准备版本和图标…"
python3 "${WORKFLOW_HELPER}" set-version "${WORKFLOW_APP}/pubspec.yaml" "${VERSION}"
if [[ -f "${WORKFLOW_APP}/assets/icons/APP_ICON.jpg" ]]; then
  echo "更新应用图标…"
  dart run flutter_launcher_icons
fi
STAGE="Android 正式版构建"
echo "[3/4] 构建爱情心意值 ${VERSION}；重新生成正式版插件配置…"
# Do not use --no-pub: tests/pub get register dev plugins such as integration_test.
# The release build must regenerate native registrants with dev plugins filtered.
flutter build apk --release --dart-define-from-file="${WORKFLOW_APP}/env.json"
APK_PATH="${WORKFLOW_APP}/build/app/outputs/flutter-apk/app-release.apk"
[[ -s "${APK_PATH}" ]] || { echo "构建没有生成有效 APK。" >&2; exit 1; }
echo "APK 已生成：${APK_PATH}"
if [[ "${MODE}" == build ]]; then
  echo "仅构建完成，未上传蒲公英。"
  exit 0
fi
STAGE="蒲公英上传"
echo "[4/4] 上传蒲公英…"
python3 "${WORKFLOW_HELPER}" upload "${APK_PATH}" "${RELEASE_NOTE}"
