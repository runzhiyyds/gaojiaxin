import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:love_story/core/user_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('toUserMessage', () {
    group('PostgrestException', () {
      test('23503 with users -> 账号信息尚未同步', () {
        final e = PostgrestException(
          message: 'foreign key users',
          code: '23503',
          details: 'references users',
        );
        expect(
          toUserMessage(e),
          '账号信息尚未同步，请退出登录后重新登录再试。',
        );
      });

      test('23503 without users -> 数据关联异常', () {
        final e = PostgrestException(
          message: 'foreign key',
          code: '23503',
        );
        expect(toUserMessage(e), '数据关联异常，请稍后重试。');
      });

      test('23505 -> 该项已存在', () {
        final e = PostgrestException(
          message: 'duplicate',
          code: '23505',
        );
        expect(toUserMessage(e), '该项已存在，请勿重复操作。');
      });

      test('42501 -> 暂无权限', () {
        final e = PostgrestException(
          message: 'permission denied',
          code: '42501',
        );
        expect(toUserMessage(e), '暂无权限执行该操作。');
      });

      test('other code -> 操作失败请稍后重试', () {
        final e = PostgrestException(
          message: 'unknown',
          code: '50000',
        );
        expect(toUserMessage(e), '操作失败，请稍后重试。');
      });
    });

    group('AuthException', () {
      test('email not confirmed', () {
        final e = AuthException('Email not confirmed');
        expect(
          toUserMessage(e),
          '请先到邮箱点击确认链接后再登录。',
        );
      });

      test('email_not_confirmed', () {
        final e = AuthException('email_not_confirmed');
        expect(
          toUserMessage(e),
          '请先到邮箱点击确认链接后再登录。',
        );
      });

      test('invalid credentials', () {
        final e = AuthException('Invalid login credentials');
        expect(toUserMessage(e), '邮箱或密码错误。');
      });

      test('generic auth -> 登录失败', () {
        final e = AuthException('Unknown auth error');
        expect(toUserMessage(e), '登录失败，请稍后重试。');
      });
    });

    group('business message strings', () {
      test('兑换余额不足', () {
        expect(
          toUserMessage(Exception('兑换余额不足')),
          '兑换余额不足，请先积累心意值后再兑换。',
        );
      });

      test('库存不足', () {
        expect(
          toUserMessage(Exception('库存不足')),
          '库存不足，无法兑换。',
        );
      });

      test('商品不存在', () {
        expect(
          toUserMessage(Exception('商品不存在')),
          '商品不存在或已下架。',
        );
      });
    });

    test('auth-wrapped socket timeout is actionable without exposing internals', () {
      final message = toUserMessage(AuthRetryableFetchException(
          message: 'ClientException with SocketException: Connection timed out, uri=https://secret.test'));
      expect(message, '连接服务超时，请切换 Wi-Fi 或移动网络后重试。');
      expect(message, isNot(contains('secret.test')));
    });
    test('direct timeout', () {
      expect(toUserMessage(TimeoutException('timeout')), contains('连接服务超时'));
    });
    test('DNS failure', () {
      expect(toUserMessage(http.ClientException('Failed host lookup')),
          '暂时无法连接服务，请检查网络或切换网络后重试。');
    });
    test('unknown exception -> 操作失败请稍后重试', () {
      expect(
        toUserMessage(Exception('Network error')),
        '操作失败，请稍后重试。',
      );
    });
  });
}
