import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 将异常转为用户可读的中文文案；调试时原始异常会通过 [debugPrint] 输出。
String toUserMessage(Object e, {String? context}) {
  if (kDebugMode && e.toString().isNotEmpty) {
    debugPrint('${context != null ? "[$context] " : ""}$e');
  }
  if (e is PostgrestException) {
    final code = e.code;
    final msg = (e.message?.toString() ?? '').toLowerCase();
    final details = (e.details?.toString() ?? '').toLowerCase();
    if (code == '23503') {
      if (msg.contains('users') || details.contains('users')) {
        return '账号信息尚未同步，请退出登录后重新登录再试。';
      }
      if (msg.contains('point_records') || msg.contains('point_items') || details.contains('point_')) {
        return '心意项目可能已删除或已变更，请返回列表刷新后再试。';
      }
      return '数据关联异常，请稍后重试。';
    }
    if (code == '23505') return '该项已存在，请勿重复操作。';
    if (code == '42501' || msg.contains('permission') || msg.contains('row level')) {
      return '暂无权限执行该操作。';
    }
    if (code == '3F000' && (msg.contains('schema') && msg.contains('net'))) {
      return '记录失败：服务器推送扩展未配置。请在 Supabase 控制台启用 pg_net 扩展，或重新执行项目中的 supabase_push_notifications.sql 更新触发器后重试。';
    }
    return '操作失败，请稍后重试。';
  }
  if (e is AuthException) {
    final m = (e.message?.toString() ?? '').toLowerCase();
    if (m.contains('email not confirmed') || m.contains('email_not_confirmed')) {
      return '请先到邮箱点击确认链接后再登录。';
    }
    if (m.contains('invalid') && m.contains('credentials')) return '邮箱或密码错误。';
    return e.message?.toString() ?? '登录失败，请稍后重试。';
  }
  final s = e.toString();
  if (s.contains('兑换余额不足')) return '兑换余额不足，请先积累心意值后再兑换。';
  if (s.contains('库存不足')) return '库存不足，无法兑换。';
  if (s.contains('商品不存在')) return '商品不存在或已下架。';
  return '操作失败，请稍后重试。';
}
