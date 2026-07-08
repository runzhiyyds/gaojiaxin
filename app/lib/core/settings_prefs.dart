import 'package:shared_preferences/shared_preferences.dart';

/// 设置项持久化（周期起始日、通知开关）
class SettingsPrefs {
  static const _keyCycleStartWeekday = 'cycle_start_weekday';
  static const _keyNotificationEnabled = 'notification_enabled';

  static Future<SharedPreferences> get _prefs async =>
      await SharedPreferences.getInstance();

  /// 周期起始日：1=周一 … 7=周日，默认 1
  static Future<int> getCycleStartWeekday() async {
    final p = await _prefs;
    return p.getInt(_keyCycleStartWeekday) ?? 1;
  }

  static Future<void> setCycleStartWeekday(int weekday) async {
    final p = await _prefs;
    await p.setInt(_keyCycleStartWeekday, weekday.clamp(1, 7));
  }

  /// 通知开关（仅保存偏好；推送/提醒能力后续版本开放）
  static Future<bool> getNotificationEnabled() async {
    final p = await _prefs;
    return p.getBool(_keyNotificationEnabled) ?? true;
  }

  static Future<void> setNotificationEnabled(bool value) async {
    final p = await _prefs;
    await p.setBool(_keyNotificationEnabled, value);
  }

  /// 是否已看过使用手册（首次引导后设为 true）
  static const _keyHasSeenUserManual = 'has_seen_user_manual';

  static Future<bool> getHasSeenUserManual() async {
    final p = await _prefs;
    return p.getBool(_keyHasSeenUserManual) ?? false;
  }

  static Future<void> setHasSeenUserManual(bool value) async {
    final p = await _prefs;
    await p.setBool(_keyHasSeenUserManual, value);
  }

  /// 是否在「下次登录时」弹出使用手册（仅注册成功后设为 true，首次登录并进入积分页时弹出后清除）
  static const _keyShowManualOnNextLogin = 'show_manual_on_next_login';

  static Future<bool> getShowManualOnNextLogin() async {
    final p = await _prefs;
    return p.getBool(_keyShowManualOnNextLogin) ?? false;
  }

  static Future<void> setShowManualOnNextLogin(bool value) async {
    final p = await _prefs;
    await p.setBool(_keyShowManualOnNextLogin, value);
  }

  /// 刚注册尚未点击邮件确认链接的邮箱（用于在服务端错误地提前设置 email_confirmed_at 时仍拒绝登录）
  static const _keyPendingConfirmEmail = 'pending_confirm_email';

  static Future<String?> getPendingConfirmEmail() async {
    final p = await _prefs;
    return p.getString(_keyPendingConfirmEmail);
  }

  static Future<void> setPendingConfirmEmail(String email) async {
    final p = await _prefs;
    await p.setString(_keyPendingConfirmEmail, email);
  }

  static Future<void> clearPendingConfirmEmail() async {
    final p = await _prefs;
    await p.remove(_keyPendingConfirmEmail);
  }
}
