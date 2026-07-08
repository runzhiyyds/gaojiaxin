import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:love_story/firebase_options.dart';

/// 全局前台/后台消息处理入口（需在 main.dart 中注册）
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
}

class NotificationService {
  NotificationService._internal();

  static final NotificationService instance = NotificationService._internal();

  FirebaseMessaging? _messaging;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// 初始化 Firebase Messaging & 本地通知；未配置 Firebase 时仅做兜底不抛错
  Future<void> init() async {
    if (_initialized) return;

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _messaging = FirebaseMessaging.instance;
    } catch (_) {
      if (kDebugMode) debugPrint('Firebase 未配置或初始化失败，推送功能将不可用');
      _messaging = null;
    }

    // 本地通知初始化（用于前台消息）
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: darwinInit);

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // TODO: 之后接入 notification_router，根据 payload 跳转
        debugPrint('Notification tapped: ${details.payload}');
      },
    );

    // Android 13+ 请求通知权限（仅一次）
    final androidImpl =
        _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();

    _initialized = true;
  }

  /// 请求通知权限（主要针对 iOS）；未配置 Firebase 时静默返回
  Future<void> requestPermissionsIfNeeded() async {
    await init();
    if (_messaging == null) return;
    final settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (kDebugMode) {
      debugPrint('Notification permission: ${settings.authorizationStatus}');
    }
  }

  /// 注册前台消息监听，并在前台弹出本地通知；未配置 Firebase 时不注册
  void listenForegroundMessages() {
    if (_messaging == null) return;
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final notification = message.notification;
      final android = notification?.android;
      final title = notification?.title ?? '新提醒';
      final body = notification?.body ?? '';

      // 仅在前台时通过本地通知展示，保持体验一致
      const androidDetails = AndroidNotificationDetails(
        'transaction_reminder',
        '事务提醒',
        channelDescription: '积分变动、兑换成功等事务型提醒',
        importance: Importance.max,
        priority: Priority.high,
      );
      const darwinDetails = DarwinNotificationDetails();
      const details =
          NotificationDetails(android: androidDetails, iOS: darwinDetails);

      await _local.show(
        notification.hashCode,
        title,
        body.isEmpty ? null : body,
        details,
      payload: message.data.isNotEmpty ? jsonEncode(message.data) : null,
      );

      if (kDebugMode) {
        debugPrint('Foreground message: ${message.data}, android: $android');
      }
    });
  }
}

