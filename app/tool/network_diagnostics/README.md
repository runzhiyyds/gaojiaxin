# Android 网络分层诊断

这些 Java 探针独立于 Flutter APP，可通过 Android 调试工具运行。只使用公开主机名，不需要密码、API Key 或 Token。

- `NetworkProbe`：系统 DNS → 每个地址 TCP 443 → TLS 默认模式及 TLS 1.2 → HTTP 响应。完整 TLS 握手保留证书与主机名校验。额外固定相同 IP、对比公开域名的 TLS 和 HTTP。
- `TLSHelloProbe`：固定同一 IP，发送带不同 SNI 主机名的 TLS 1.2 ClientHello，读取首个 TLS 记录头。它不完成登录或发送 HTTP/用户信息，只用于区分首次 TLS 响应前后的重置。
- `GatewayProbe`：读取实际部署的 HTTPS `/health`，打印状态和最多 2 KiB 的诊断 JSON；保留证书校验，拒绝含凭据、查询参数或其他业务路径的 URL。

本次使用 Java 8 目标编译、Android build-tools 36.1.0 的 D8、min-api 26，在 Android 12 真机运行。这些工具只用于 Supabase/Cloudflare 入口排查；换用不兼容的 IP/域名组合可能正常产生证书或路由错误，不能据此判定网络限制。

在已连接、已授权的 Android 手机上复现（路径对应本机现有 SDK）：

```bash
cd /Users/guochenyuan/Desktop/高佳欣
DIAG_DIR="$(mktemp -d)"
DIAG_SDK="/Users/guochenyuan/Library/Android/sdk"
javac --release 8 -d "$DIAG_DIR" app/tool/network_diagnostics/*.java
"$DIAG_SDK/build-tools/36.1.0/d8" --min-api 26 --lib "$DIAG_SDK/platforms/android-36.1/android.jar" --output "$DIAG_DIR" "$DIAG_DIR/NetworkProbe.class" "$DIAG_DIR/TLSHelloProbe.class" "$DIAG_DIR/GatewayProbe.class"
(cd "$DIAG_DIR" && jar cf probes.jar classes.dex)
DIAG_REMOTE="/data/local/tmp/$(basename "$DIAG_DIR")-probes.jar"
"$DIAG_SDK/platform-tools/adb" push "$DIAG_DIR/probes.jar" "$DIAG_REMOTE"
"$DIAG_SDK/platform-tools/adb" shell env "CLASSPATH=$DIAG_REMOTE" app_process /system/bin NetworkProbe uebeyflmmpesjolcrhnp.supabase.co
"$DIAG_SDK/platform-tools/adb" shell env "CLASSPATH=$DIAG_REMOTE" app_process /system/bin TLSHelloProbe uebeyflmmpesjolcrhnp.supabase.co
"$DIAG_SDK/platform-tools/adb" shell env "CLASSPATH=$DIAG_REMOTE" app_process /system/bin GatewayProbe https://gaojiaxin-check.pet-food-advisor.asia/health
"$DIAG_SDK/platform-tools/adb" shell rm "$DIAG_REMOTE"
```

先确认当前默认网络，分别在移动数据和已保存的 Wi-Fi 上运行相同测试；完成后恢复原来的网络设置。保留不含敏感信息的输出用于服务提供商排查。
