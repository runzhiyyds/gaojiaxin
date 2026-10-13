# 顺顺&佳猫的爱情故事

情侣积分 APP：记录与激励彼此的付出，用积分在商城中兑换约定奖励。

## 技术栈

- **客户端**：Flutter（Android APK，可扩展 iOS）
- **后端/数据**：Supabase（Auth + PostgreSQL + RLS）
- **热更新**：Shorebird Code Push

## 环境要求

- Flutter：本次已验证 3.41.1 / Dart 3.11.0，Dart 依赖最低要求 3.4
- 已配置 Android 开发环境（打 APK）
- Supabase 项目（用于登录、绑定、积分与商城数据）

## 快速开始

### 1. 克隆/打开项目

```bash
cd "高佳欣/app"
```

### 2. 安装依赖

```bash
flutter pub get
```

### 3. 配置 Supabase

1. 在 [Supabase](https://supabase.com) 创建项目。
2. 在 **SQL Editor** 中执行 [`docs/supabase_schema.sql`](docs/supabase_schema.sql) 创建表与 RLS；再执行 [`docs/supabase_migration_is_default.sql`](docs/supabase_migration_is_default.sql) 为积分项目增加「默认项目」字段；可选执行 [`docs/supabase_realtime_publication.sql`](docs/supabase_realtime_publication.sql) 开启 Realtime 实时刷新。
3. 在 **Authentication -> Providers** 中启用 Email，并可选配置确认邮件。
4. 在 **Settings -> API** 中复制 **Project URL** 与 **anon public** key。

配置到应用中任选其一：

- **环境变量**（推荐）：  
  运行或打包时传入：
  ```bash
  flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key
  ```
- **或** 直接修改 `app/lib/core/config.dart` 中的 `defaultValue`（仅限本地/测试，勿提交密钥）。

### 4. 运行

```bash
cd app
./scripts/run_with_env.sh
```

### 5. 打 APK

```bash
cd app
flutter build apk --release
```

APK 输出路径：`build/app/outputs/flutter-apk/app-release.apk`。

若使用环境变量：

```bash
flutter build apk --release --dart-define=SUPABASE_URL=xxx --dart-define=SUPABASE_ANON_KEY=xxx
```

## 热更新（Shorebird）

1. 安装 [Shorebird CLI](https://docs.shorebird.dev/getting-started)。
2. 在项目根目录执行：
   ```bash
   cd app
   shorebird init
   ```
3. 按提示完成初始化，会生成/更新 `shorebird.yaml` 中的 `app_id`。
4. 发布 patch（在已发布过 release 的前提下）：
   ```bash
   shorebird patch
   ```

应用显示首屏后在后台检查和下载可用更新，不阻塞登录与首页（见 `app/lib/core/background_tasks.dart`）。

## 应用名称与图标

- **应用名**：已在 `android/app/src/main/AndroidManifest.xml` 中设为「顺顺&佳猫的爱情故事」。
- **图标**：将你的图标图片放到 `app/assets/icons/APP_ICON.jpg`，在 `app` 目录执行 `dart run flutter_launcher_icons` 即可生成各平台图标。

## 文档

- [本地验证与发版](docs/本地验证与发版.md)
- [移动网络 TLS 故障诊断](docs/移动网络诊断-2026-10-13.md)
- [性能与体验优化记录](docs/性能与体验优化-2026-10-11.md)
- [产品说明](docs/产品说明.md)
- [UI 规范](docs/UI规范.md)
- [Supabase 表结构](docs/supabase_schema.sql)

## 账号与绑定说明

- 当前为 **邮箱 + 密码** 注册/登录（Supabase 默认），无需短信费用。
- 登录后进入「绑定」：一方创建情侣空间得到 **邀请码**，另一方输入邀请码完成绑定。
- 绑定后共享积分项目、记录、商城与周期统计。

## 深色模式

已支持系统跟随的深色模式（`ThemeMode.system`），无需额外配置。

## 变更同步

客户端变更统一同步到 [runzhiyyds/gaojiaxin](https://github.com/runzhiyyds/gaojiaxin)，具体协作约定见 [AGENTS.md](AGENTS.md)。

## Web / 真机统一验证

在项目根目录执行 `./test_app.sh`，自动优先选择已连接 Android 手机，否则使用 Chrome。
执行 `./test_app.sh menu` 可在每轮退出后继续切换；`web`、`phone`、`profile`、`smoke`、`test` 可直接指定模式。

发布命令保持 `./publish_new_version.sh 1.6.3 "全面优化"`；追加 `--check` 只检查，追加 `--build-only` 只构建。详见 [本地验证与发版](docs/本地验证与发版.md)。
