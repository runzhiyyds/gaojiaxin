import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/core/notifications/device_registration.dart';

class CoupleService extends ChangeNotifier {
  CoupleService() {
    _authSubscription = _client.auth.onAuthStateChange.listen((_) {
      _loadBinding();
    });
    _loadBinding();
  }

  static const _inviteCodeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _inviteCodeLength = 6;

  final SupabaseClient _client = Supabase.instance.client;
  late final StreamSubscription<AuthState> _authSubscription;

  String? _coupleSpaceId;
  String? _inviteCode;
  String? _partnerId;
  Map<String, dynamic>? _myProfile;
  Map<String, dynamic>? _partnerProfile;
  bool _loading = true;
  String? _error;

  String? get coupleSpaceId => _coupleSpaceId;
  String? get inviteCode => _inviteCode;
  /// 对方用户 id，未关联时为 null
  String? get partnerId => _partnerId;
  /// 对方是否已注册并关联（user_b_id 已填）
  bool get hasPartner => _partnerId != null;
  Map<String, dynamic>? get myProfile => _myProfile;
  Map<String, dynamic>? get partnerProfile => _partnerProfile;
  bool get loading => _loading;
  String? get error => _error;
  bool get isBound => _coupleSpaceId != null && _coupleSpaceId!.isNotEmpty;

  Future<void> _loadBinding() async {
    _loading = true;
    _error = null;
    notifyListeners();

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      _coupleSpaceId = null;
      _inviteCode = null;
      _partnerId = null;
      _myProfile = null;
      _partnerProfile = null;
      _loading = false;
      notifyListeners();
      return;
    }

    try {
      var res = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (res == null) {
        _loading = false;
        notifyListeners();
        return;
      }
      final meta = _client.auth.currentUser?.userMetadata;
      final metaNickname = meta?['nickname']?.toString().trim();
      final profileNickname = res['nickname']?.toString().trim();
      if ((profileNickname == null || profileNickname.isEmpty) &&
          metaNickname != null &&
          metaNickname.isNotEmpty) {
        await _client.from('profiles').update({
          'nickname': metaNickname,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', userId);
        res = await _client.from('profiles').select().eq('id', userId).single();
      }
      _myProfile = Map<String, dynamic>.from(res as Map);
      _coupleSpaceId = res['couple_space_id'] as String?;
      _inviteCode = res['invite_code'] as String?;
      _partnerId = null;

      if (_coupleSpaceId != null) {
        final spaceRes = await _client
            .from('couple_spaces')
            .select()
            .eq('id', _coupleSpaceId!)
            .maybeSingle();
        if (spaceRes != null) {
          final space = Map<String, dynamic>.from(spaceRes);
          final userA = space['user_a_id'] as String?;
          final userB = space['user_b_id'] as String?;
          final isUserA = userId == userA;
          final isUserB = userId == userB;
          if (!isUserA && !isUserB) {
            await _client.from('profiles').update({
              'couple_space_id': null,
              'updated_at': DateTime.now().toIso8601String(),
            }).eq('id', userId);
            _coupleSpaceId = null;
            _inviteCode = null;
          } else {
            final partnerId = isUserA ? userB : userA;
            _partnerId = partnerId;
            if (partnerId != null) {
              final partnerRes = await _client
                  .from('profiles')
                  .select()
                  .eq('id', partnerId)
                  .maybeSingle();
              if (partnerRes != null) {
                _partnerProfile = Map<String, dynamic>.from(partnerRes as Map);
              }
            }
          }
        }
      }

      _registerDeviceInBackground();
    } catch (e) {
      _error = toUserMessage(e, context: '_loadBinding');
    }
    _loading = false;
    notifyListeners();
  }

  void _registerDeviceInBackground() {
    final spaceId = _coupleSpaceId;
    if (spaceId == null || spaceId.isEmpty) return;
    unawaited(() async {
      // 推送设备注册不阻塞绑定/登录主流程，避免绑定页长时间停留在 loading。
      try {
        final registrar = DeviceRegistration(_client);
        await registrar
            .registerCurrentDevice(coupleSpaceId: spaceId)
            .timeout(const Duration(seconds: 6));
      } catch (_) {
        // 设备上报失败不影响主流程
      }
    }());
  }

  Future<void> refresh() => _loadBinding();

  String _generateInviteCode() {
    final r = Random();
    return List.generate(
      _inviteCodeLength,
      (_) => _inviteCodeChars[r.nextInt(_inviteCodeChars.length)],
    ).join();
  }

  /// 创建情侣空间并生成邀请码。若已有空间则不再重复创建，仅刷新并返回 true。
  Future<bool> createSpace() async {
    _error = null;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;
    if (_coupleSpaceId != null) {
      await _loadBinding();
      return true;
    }
    try {
      // 先确保 profile 存在，避免因 trigger 未执行导致 couple_spaces 外键报错
      final profileExists = await _client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();
      if (profileExists == null) {
        _error = '账号尚未就绪，请退出登录后重新登录再试。';
        notifyListeners();
        return false;
      }
      final code = _generateInviteCode();
      final spaceRes = await _client.from('couple_spaces').insert({
        'user_a_id': userId,
        'user_b_id': null,
      }).select('id').single();
      final spaceId = (spaceRes as Map)['id'] as String;
      await _client.from('profiles').update({
        'couple_space_id': spaceId,
        'invite_code': code,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
      _coupleSpaceId = spaceId;
      _inviteCode = code;
      notifyListeners();
      return true;
    } catch (e) {
      _error = toUserMessage(e, context: 'createSpace');
      notifyListeners();
      return false;
    }
  }

  /// 通过邀请码加入空间。校验与写入在服务端 RPC 内完成，避免 RLS 与客户端状态问题。
  Future<bool> joinWithCode(String code) async {
    _error = null;
    if (_client.auth.currentUser?.id == null) return false;
    final trimmed = code.trim().toUpperCase();
    if (trimmed.length != _inviteCodeLength) {
      _error = '邀请码为 $_inviteCodeLength 位，请检查后重试';
      notifyListeners();
      return false;
    }
    for (final c in trimmed.split('')) {
      if (!_inviteCodeChars.contains(c)) {
        _error = '邀请码格式不正确，仅支持大写字母与数字';
        notifyListeners();
        return false;
      }
    }
    try {
      final data = await _client.rpc(
        'join_by_invite_code',
        params: {'code_input': trimmed},
      );
      if (data is! Map) {
        _error = '邀请码无效或已失效，请确认后重试';
        notifyListeners();
        return false;
      }
      final success = data['success'] == true;
      if (success) {
        await _loadBinding();
        return true;
      }
      final err = data['error']?.toString() ?? '';
      switch (err) {
        case 'already_joined':
          _error = '你已关联过情侣空间。若需更换空间，请先在「我的」-「设置」中退出当前空间后再试';
          break;
        case 'own_code':
          _error = '这是你的邀请码，请分享给 TA 输入';
          break;
        case 'space_full':
          _error = '该情侣空间已满，邀请码已失效';
          break;
        case 'invalid_code':
        case 'invalid_length':
        default:
          _error = '邀请码无效或已失效，请确认后重试';
      }
      notifyListeners();
      return false;
    } catch (e) {
      _error = toUserMessage(e, context: 'joinWithCode');
      notifyListeners();
      return false;
    }
  }

  /// 退出当前情侣空间：先更新空间（避免先清 profile 后 RLS 导致无法改空间），再清除自己的 profile 关联。
  /// 若为被邀请方(user_b)则清空 user_b_id；若为创建者(user_a)且对方已加入则转让给对方，否则仅清除自己 profile。
  Future<bool> leaveSpace() async {
    _error = null;
    final userId = _client.auth.currentUser?.id;
    if (userId == null || _coupleSpaceId == null) return false;
    try {
      final spaceRow = await _client
          .from('couple_spaces')
          .select('user_a_id, user_b_id')
          .eq('id', _coupleSpaceId!)
          .maybeSingle();
      if (spaceRow != null) {
        final userA = spaceRow['user_a_id'] as String?;
        final userB = spaceRow['user_b_id'] as String?;
        final isUserA = userId == userA;
        final isUserB = userId == userB;
        if (isUserB) {
          await _client.from('couple_spaces').update({
            'user_b_id': null,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _coupleSpaceId!);
        } else if (isUserA && userB != null) {
          await _client.from('couple_spaces').update({
            'user_a_id': userB,
            'user_b_id': null,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('id', _coupleSpaceId!);
        }
      }
      await _client.from('profiles').update({
        'couple_space_id': null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
      await _loadBinding();
      return true;
    } catch (e) {
      _error = toUserMessage(e, context: 'leaveSpace');
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }
}
