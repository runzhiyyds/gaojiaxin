/// 运行前请替换为你的 Supabase 项目 URL 与 anon key。
/// 在 Supabase Dashboard -> Settings -> API 中获取。
/// 打 release 包时必须传 --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...，
/// 否则会显示「未配置 Supabase」界面。
///
/// 蒲公英更新：上传 APK 后在应用管理页获取 appKey，在 账户 -> API 信息 获取 _api_key。
/// 二者任一为空则不检查更新。
class Config {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://REPLACE_ME.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'REPLACE_ME',
  );

  /// Keep the original project's session namespace when using another API host.
  /// Empty preserves the SDK's default key for other projects.
  static const String supabaseAuthStorageKey = String.fromEnvironment(
    'SUPABASE_AUTH_STORAGE_KEY',
    defaultValue: '',
  );

  /// 是否为未替换的占位配置（未传 --dart-define 时的 release 包）
  static bool get isSupabaseConfigured =>
      !supabaseUrl.contains('REPLACE_ME') && !supabaseAnonKey.contains('REPLACE_ME');

  /// 蒲公英 API Key（鉴权），空则跳过更新检查
  static const String pgyerApiKey = String.fromEnvironment(
    'PGYER_API_KEY',
    defaultValue: '',
  );
  /// 蒲公英应用 AppKey（上传 APK 后应用管理页可见），空则跳过更新检查
  static const String pgyerAppKey = String.fromEnvironment(
    'PGYER_APP_KEY',
    defaultValue: '',
  );
}
