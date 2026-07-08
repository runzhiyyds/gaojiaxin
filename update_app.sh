#!/bin/bash

# APP更新脚本
# 使用方法: ./update_app.sh [版本号]

VERSION=${1:-"1.0.1"}
APP_NAME="顺顺佳猫爱情故事"

echo "🚀 开始构建 ${APP_NAME} v${VERSION}..."

# 进入app目录
cd "/Users/guochenyuan/Desktop/高佳欣/app"

# 更新版本号
echo "📝 更新版本号到 ${VERSION}..."
sed -i '' "s/version: .*/version: ${VERSION}+$(date +%s)/" pubspec.yaml

# 清理并构建
echo "🧹 清理项目..."
flutter clean
flutter pub get

echo "🔨 构建Release APK..."
flutter build apk --release

# 检查构建是否成功
if [ $? -eq 0 ]; then
    echo "✅ APK构建成功！"
    
    # 复制APK到下载页面
    echo "📦 更新下载页面..."
    cp "build/app/outputs/flutter-apk/app-release.apk" "../download-page/app-release.apk"
    
    # 获取文件大小
    SIZE=$(du -h "../download-page/app-release.apk" | cut -f1)
    
    # 更新HTML页面中的版本信息
    sed -i '' "s/v[0-9]\+\.[0-9]\+\.[0-9]\+/v${VERSION}/g" "../download-page/index.html"
    sed -i '' "s/[0-9]\+\.[0-9]\+ MB/${SIZE}B/g" "../download-page/index.html"
    
    echo "🎉 更新完成！"
    echo "📱 新版本: v${VERSION}"
    echo "📦 文件大小: ${SIZE}B"
    echo "🌐 请重新部署下载页面到CloudStudio"
    
else
    echo "❌ 构建失败，请检查错误信息"
    exit 1
fi