import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 将异常转为用户可读的中文文案；调试时原始异常会通过 [debugPrint] 输出。
String toUserMessage(Object e, {String? context}) {
  if (kDebugMode && e.toString().isNotEmpty) {
    debugPrint('${context != null ? "[$context] " : ""}$e');
  }
  // GoTrue wraps transport errors in AuthRetryableFetchException, so classify
  // network failures before displaying any server message.
  if (isNetworkTimeout(e)) {
    return '连接服务超时，请切换 Wi-Fi 或移动网络后重试。';
  }
  if (isNetworkFailure(e)) {
    return '暂时无法连接服务，请检查网络或切换网络后重试。';
  }
  if (e is PostgrestException) {
    final code = e.code;
    final msg = e.message.toLowerCase();
    final details = (e.details?.toString() ?? '').toLowerCase();
    if (code == '23503') {
      if (msg.contains('users') || details.contains('users')) {
        return '账号信息尚未同步，请退出登录后重新登录再试。';
      }
      if (msg.contains('point_records') ||
          msg.contains('point_items') ||
          details.contains('point_')) {
        return '心意项目可能已删除或已变更，请返回列表刷新后再试。';
      }
      return '数据关联异常，请稍后重试。';
    }
    if (code == '23505') return '该项已存在，请勿重复操作。';
    if (code == '42501' ||
        msg.contains('permission') ||
        msg.contains('row level')) {
      return '暂无权限执行该操作。';
    }
    if (code == '3F000' && (msg.contains('schema') && msg.contains('net'))) {
      return '记录失败：服务器推送扩展未配置。请在 Supabase 控制台启用 pg_net 扩展，或重新执行项目中的 supabase_push_notifications.sql 更新触发器后重试。';
    }
    return '操作失败，请稍后重试。';
  }
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('email not confirmed') ||
        m.contains('email_not_confirmed')) {
      return '请先到邮箱点击确认链接后再登录。';
    }
    if (m.contains('invalid') && m.contains('credentials')) return '邮箱或密码错误。';
    if (m.contains('rate limit') || e.statusCode == '429') {
      return '尝试次数过多，请稍后再试。';
    }
    if (m.contains('already registered') || m.contains('already exists')) {
      return '该邮箱已注册，请直接登录。';
    }
    return context == '注册' ? '注册失败，请稍后重试。' : '登录失败，请稍后重试。';
  }
  final s = e.toString();
  if (s.contains('账号资料尚未同步')) return '账号资料尚未同步，请稍后重新加载。';
  if (s.contains('暂时无法读取情侣空间')) return '暂时无法读取情侣空间，请重新加载。';
  if (s.contains('兑换余额不足')) return '兑换余额不足，请先积累心意值后再兑换。';
  if (s.contains('库存不足')) return '库存不足，无法兑换。';
  if (s.contains('商品不存在')) return '商品不存在或已下架。';
  return '操作失败，请稍后重试。';
}

bool isNetworkTimeout(Object error) {
  final message = error.toString().toLowerCase();
  return error is TimeoutException ||
      message.contains('timed out') ||
      message.contains('timeoutexception') ||
      message.contains('connection timeout') ||
      message.contains('连接服务超时');
}

bool isNetworkFailure(Object error) {
  if (isNetworkTimeout(error) ||
      error is http.ClientException ||
      error is AuthRetryableFetchException) return true;
  final message = error.toString().toLowerCase();
  return message.contains('socketexception') ||
      message.contains('failed host lookup') ||
      message.contains('network is unreachable') ||
      message.contains('connection reset') ||
      message.contains('connection refused') ||
      message.contains('handshakeexception');
}
