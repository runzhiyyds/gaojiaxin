#!/usr/bin/env bash
# Release 构建。使用 app 目录下的 env.json 一次性配置 Supabase + 蒲公英，无需每次传参。
# 详见 app/打包说明.md：复制 env.json.example 为 env.json，填好 4 项后执行本脚本即可。

set -e
cd "$(dirname "$0")/.."

if [ -f "env.json" ]; then
  echo "使用 env.json 中的配置构建..."
  flutter build apk --release --dart-define-from-file=env.json
else
  if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
    echo "未找到 env.json，且未设置环境变量。"
    echo "请任选一种方式："
    echo "  1) 复制 env.json.example 为 env.json，填入 SUPABASE_URL、SUPABASE_ANON_KEY 后重新运行本脚本；"
    echo "  2) 或设置环境变量：export SUPABASE_URL=... SUPABASE_ANON_KEY=..."
    exit 1
  fi
  ARGS=(
    --dart-define=SUPABASE_URL="$SUPABASE_URL"
    --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  )
  if [ -n "$PGYER_APP_KEY" ] && [ -n "$PGYER_API_KEY" ]; then
    ARGS+=(--dart-define=PGYER_APP_KEY="$PGYER_APP_KEY" --dart-define=PGYER_API_KEY="$PGYER_API_KEY")
  fi
  flutter build apk --release "${ARGS[@]}"
fi

echo "APK 已生成: build/app/outputs/flutter-apk/app-release.apk"
