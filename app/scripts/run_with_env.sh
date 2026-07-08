#!/usr/bin/env bash
# USB 调试运行：使用 env.json 中的 Supabase/蒲公英配置，与 Release 打包一致。
# 使用前：手机用 USB 连接电脑，开启开发者选项与 USB 调试；确保已配置 app/env.json。
# 在 app 目录执行：./scripts/run_with_env.sh

set -e
cd "$(dirname "$0")/.."

# 根据 APP_ICON.jpg 更新桌面/启动器图标（与发版脚本一致）
ICON_SRC="assets/icons/APP_ICON.jpg"
if [ -f "$ICON_SRC" ]; then
  echo "🖼️  根据 assets/icons/APP_ICON.jpg 更新桌面图标..."
  if dart run flutter_launcher_icons 2>/dev/null; then
    echo "✅ 桌面图标已更新"
  else
    echo "⚠️  桌面图标生成跳过（可忽略）"
  fi
fi

if [ -f "env.json" ]; then
  echo "使用 env.json 配置运行（与 Release 一致）..."
  flutter run --dart-define-from-file=env.json
else
  echo "未找到 env.json。请先复制 env.json.example 为 env.json 并填写配置。"
  echo "  cp env.json.example env.json"
  exit 1
fi
