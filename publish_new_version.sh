#!/bin/bash

# 爱情积分（高佳欣）- 一键发版脚本（蒲公英）
# 项目目录: /Users/guochenyuan/Desktop/高佳欣
#
# 使用方法: ./publish_new_version.sh <版本号> "<更新说明>"
# 示例:     cd /Users/guochenyuan/Desktop/高佳欣
#           ./publish_new_version.sh 1.2.0 "修复积分商城的双方贡献逻辑"
#
# 发布前请配置:
#   1. 蒲公英 API Key（用于本脚本自动上传）：复制 pgyer_config.sh.example 为 pgyer_config.sh，填入 PGYER_API_KEY
#      获取地址：https://www.pgyer.com/account/api
#   2. app/env.json 中已填写 SUPABASE_URL、SUPABASE_ANON_KEY；可选 PGYER_APP_KEY、PGYER_API_KEY（应用内更新检查用）

# 加载蒲公英配置（与颐养年一致：只读取 pgyer_config.sh，不读取 .example）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/pgyer_config.sh" ]; then
  source "$SCRIPT_DIR/pgyer_config.sh"
fi

VERSION=${1:-"1.0.1"}
RELEASE_NOTE=${2:-"修复问题和性能优化"}
APP_NAME="爱情积分"
APP_DIR="$(cd "$SCRIPT_DIR/app" && pwd)"

echo "🚀 开始发布 ${APP_NAME} v${VERSION}..."

# 步骤1: 更新版本号
echo "📝 步骤1: 更新版本号到 ${VERSION}..."
cd "$APP_DIR"
sed -i '' "s/version: .*/version: ${VERSION}+$(date +%s)/" pubspec.yaml

echo "🧹 清理项目..."
rm -rf "$APP_DIR/build" 2>/dev/null || true
flutter clean
flutter pub get

# 步骤1.5: 根据 APP_ICON.jpg 更新桌面/启动器图标
ICON_SRC="$APP_DIR/assets/icons/APP_ICON.jpg"
if [ -f "$ICON_SRC" ]; then
  echo "🖼️  步骤1.5: 根据 app/assets/icons/APP_ICON.jpg 更新桌面图标..."
  dart run flutter_launcher_icons
  if [ $? -ne 0 ]; then
    echo "⚠️  桌面图标生成失败，继续构建（可稍后手动运行 dart run flutter_launcher_icons）"
  else
    echo "✅ 桌面图标已更新"
  fi
else
  echo "⚠️  未找到 $ICON_SRC，跳过桌面图标更新"
fi

# 步骤2: 检查 env.json 后构建
if [ -f "$APP_DIR/env.json" ]; then
  if grep -q "REPLACE_ME" "$APP_DIR/env.json" 2>/dev/null; then
    echo "⚠️  警告: env.json 中仍包含 REPLACE_ME，请先填写 SUPABASE_URL 和 SUPABASE_ANON_KEY"
    read -p "是否继续构建? (y/N) " -n 1 r; echo
    if [ "$r" != "y" ] && [ "$r" != "Y" ]; then exit 1; fi
  fi
  echo "🔨 使用 env.json 构建 Release APK..."
  flutter build apk --release --dart-define-from-file=env.json
else
  echo "⚠️  未找到 app/env.json"
  echo "  请复制 env.json.example 为 env.json 并填写 SUPABASE_URL、SUPABASE_ANON_KEY 后重试。"
  exit 1
fi

if [ $? -ne 0 ]; then
  echo "❌ APK 构建失败，请检查错误信息"
  exit 1
fi

echo "✅ APK 构建成功！"
APK_PATH="$APP_DIR/build/app/outputs/flutter-apk/app-release.apk"
SIZE=$(du -h "$APK_PATH" | cut -f1)

echo ""
echo "🎉 版本构建完成！"
echo "📱 新版本: v${VERSION}"
echo "📦 文件大小: ${SIZE}"
echo "📝 更新说明: ${RELEASE_NOTE}"
echo ""

# 自动上传到蒲公英（与颐养年逻辑一致：若已配置 PGYER_API_KEY 则上传）
if [ -n "$PGYER_API_KEY" ]; then
  echo "📤 检测到 PGYER_API_KEY，正在上传到蒲公英..."
  UPLOAD_RESULT=$(curl -s -F "file=@$APK_PATH" -F "_api_key=$PGYER_API_KEY" -F "buildUpdateDescription=${RELEASE_NOTE}" "https://www.pgyer.com/apiv2/app/upload")
  SHORTCUT=$(echo "$UPLOAD_RESULT" | grep -o '"buildShortcutUrl":"[^"]*"' | cut -d'"' -f4)
  if [ -n "$SHORTCUT" ]; then
    echo "✅ 上传成功！"
    echo "📲 下载链接: https://www.pgyer.com/${SHORTCUT}"
    echo ""
    echo "  如需应用内更新检查，请在蒲公英应用详情页确认 AppKey，并保证 app/env.json 中 PGYER_APP_KEY、PGYER_API_KEY 已配置。"
  else
    echo "❌ 上传失败，请检查 API Key 或网络。"
    echo "  响应: $UPLOAD_RESULT"
    echo ""
    echo "  可手动上传: 打开 https://www.pgyer.com 上传 APK: $APK_PATH"
    echo "     版本说明: ${RELEASE_NOTE}"
  fi
else
  echo "📋 未检测到 PGYER_API_KEY，跳过自动上传。"
  echo "  说明：脚本只读取 pgyer_config.sh（不会读取 pgyer_config.sh.example）。"
  if [ -f "$SCRIPT_DIR/pgyer_config.sh.example" ]; then
    echo "  1. 复制并配置: cp pgyer_config.sh.example pgyer_config.sh  然后编辑 pgyer_config.sh 填入 PGYER_API_KEY"
  else
    echo "  1. 新建 pgyer_config.sh，内容: export PGYER_API_KEY=\"你的Key\""
  fi
  echo "     获取地址：https://www.pgyer.com/account/api"
  echo ""
  echo "  2. 或手动上传：打开 https://www.pgyer.com，登录后上传 APK: $APK_PATH"
  echo "     版本说明: ${RELEASE_NOTE}"
fi

