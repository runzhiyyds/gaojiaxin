import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:love_story/core/debug_log.dart';
import 'package:love_story/core/settings_prefs.dart';

/// 默认登录账号（仅限家人使用，无登录界面）
const _defaultEmail = '18613544351@163.com';
const _defaultPassword = '123456';

/// 是否要求邮箱确认后才能登录；当前内测阶段为 false，与注册页文案保持一致。
const bool _requireEmailConfirm = false;

class AuthService extends ChangeNotifier {
  AuthService() {
    _authSubscription = _auth.onAuthStateChange.listen((data) {
      final session = data.session;
      _session = session;
      notifyListeners();
    });
    _session = _auth.currentSession;
  }

  final GoTrueClient _auth = Supabase.instance.client.auth;
  late final StreamSubscription<AuthState> _authSubscription;
  Session? _session;

  /// 取消 auth 状态订阅（单测或替换 Provider 时调用，根 Provider 通常不 dispose）
  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Session? get session => _session;
  User? get currentUser => _session?.user;
  bool get isLoggedIn => _session != null;

  /// 自动使用默认账号登录，支持多台设备同时登录
  Future<void> autoSignIn() async {
    if (_session != null) return;
    try {
      await _auth.signInWithPassword(email: _defaultEmail, password: _defaultPassword);
      _session = _auth.currentSession;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? nickname,
  }) async {
    await _auth.signUp(
      email: email,
      password: password,
      data: nickname != null ? {'nickname': nickname} : null,
    );
    // 强制登出，确保必须到邮箱点击确认链接后再登录（即使用户端返回了 session）
    await _auth.signOut();
    _session = null;
    notifyListeners();
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    // #region agent log
    debugLog(
      location: 'auth_service.dart:signInWithPassword:entry',
      message: 'signInWithPassword called',
      hypothesisId: 'H4',
    );
    // #endregion
    await _auth.signInWithPassword(email: email, password: password);
    // #region agent log
    debugLog(
      location: 'auth_service.dart:signInWithPassword:afterSignIn',
      message: 'signInWithPassword succeeded, calling getUser',
      hypothesisId: 'H1',
    );
    // #endregion
    // 从服务端拉取用户信息，以服务端为准判断是否已验证邮箱（本地 session 可能被缓存）
    User? user;
    try {
      final response = await _auth.getUser();
      user = response.user;
    } catch (e, st) {
      // #region agent log
      debugLog(
        location: 'auth_service.dart:signInWithPassword:getUserError',
        message: 'getUser threw',
        data: <String, dynamic>{
          'error': e.toString(),
          'stack': st.toString().split('\n').take(3).join(' '),
        },
        hypothesisId: 'H1',
      );
      // #endregion
      rethrow;
    }
    // #region agent log
    debugLog(
      location: 'auth_service.dart:signInWithPassword:afterGetUser',
      message: 'getUser returned',
      data: <String, dynamic>{
        'userNotNull': user != null,
        'emailConfirmedAt': user?.emailConfirmedAt,
        'emailConfirmedAtLength': user?.emailConfirmedAt?.length,
      },
      hypothesisId: 'H1,H2,H3,H5',
    );
    // #endregion
    // 服务端可能未开启「Confirm email」导致未点链接也返回 email_confirmed_at，用本地「待确认邮箱」二次拦截
    final pendingEmail = await SettingsPrefs.getPendingConfirmEmail();
    final rejectByPending = user != null &&
        pendingEmail != null &&
        pendingEmail.isNotEmpty &&
        user.email?.toLowerCase() == pendingEmail.toLowerCase();
    final needRejectByServer = user != null &&
        (user.emailConfirmedAt == null || user.emailConfirmedAt!.isEmpty);
    final needReject = _requireEmailConfirm && (needRejectByServer || rejectByPending);
    // #region agent log
    debugLog(
      location: 'auth_service.dart:signInWithPassword:check',
      message: needReject ? 'will reject (unconfirmed)' : 'will allow',
      data: <String, dynamic>{
        'needReject': needReject,
        'rejectByPending': rejectByPending,
        'needRejectByServer': needRejectByServer,
      },
      hypothesisId: 'H2,H3',
    );
    // #endregion
    if (needReject) {
      // #region agent log
      debugLog(
        location: 'auth_service.dart:signInWithPassword:rejecting',
        message: 'signOut and throw email_not_confirmed',
        hypothesisId: 'H1,H2',
      );
      // #endregion
      await _auth.signOut();
      _session = null;
      notifyListeners();
      throw const AuthException(
        '邮箱尚未确认，请先前往邮箱点击确认链接后再登录。',
        statusCode: 'email_not_confirmed',
      );
    }
    // #region agent log
    debugLog(
      location: 'auth_service.dart:signInWithPassword:proceed',
      message: 'email confirmed, notifyListeners',
      hypothesisId: 'H3',
    );
    // #endregion
    notifyListeners();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _session = null;
    notifyListeners();
  }
}
