import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:love_story/core/cache/app_cache.dart';
import 'package:love_story/core/cache/persistent_snapshot_store.dart';

class AuthService extends ChangeNotifier {
  AuthService({
    GoTrueClient? client,
    PersistentSnapshotStore? snapshotStore,
  })  : _auth = client ?? Supabase.instance.client.auth,
        _snapshotStore = snapshotStore ?? PersistentSnapshotStore.instance {
    _session = _auth.currentSession;
    _authSubscription = _auth.onAuthStateChange.listen((data) {
      // Password login is committed after its response has been validated.
      if (_authenticating) return;
      final previousId = _session?.user.id;
      _session = data.session;
      if (previousId != _session?.user.id) {
        AppCache.instance.clear();
        if (previousId != null) {
          unawaited(_clearSnapshot(previousId));
        }
        notifyListeners();
      }
    }, onError: (Object error, StackTrace stack) {
      // A background token-refresh network failure must not log the user out.
      if (kDebugMode) debugPrint('Session refresh unavailable: $error');
    });
  }

  final GoTrueClient _auth;
  final PersistentSnapshotStore _snapshotStore;
  late final StreamSubscription<AuthState> _authSubscription;
  Session? _session;
  bool _authenticating = false;

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  Session? get session => _session;
  User? get currentUser => _session?.user;
  bool get isLoggedIn => _session != null;

  Future<void> _clearSnapshot(String userId) async {
    try {
      await _snapshotStore.clearUser(userId);
    } catch (_) {
      // Local cleanup failures must not break login or logout navigation.
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? nickname,
  }) async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      await _auth.signUp(
        email: email,
        password: password,
        data: nickname != null ? {'nickname': nickname} : null,
      );
      // Registration returns to login even when server email confirmation is off.
      await _auth.signOut(scope: SignOutScope.local);
      _session = null;
      AppCache.instance.clear();
    } finally {
      _authenticating = false;
      notifyListeners();
    }
  }

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      // The password endpoint already returns the server's user and session.
      // Avoid a second getUser request that can fail after a successful login.
      final response =
          await _auth.signInWithPassword(email: email, password: password);
      if (response.session == null) {
        throw const AuthException('登录未完成，请重试。');
      }
      _session = response.session;
      AppCache.instance.clear();
    } finally {
      _authenticating = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final previousId = _session?.user.id;
    await _auth.signOut(scope: SignOutScope.local);
    _session = null;
    AppCache.instance.clear();
    if (previousId != null) await _clearSnapshot(previousId);
    notifyListeners();
  }
}
