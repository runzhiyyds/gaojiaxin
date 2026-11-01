import 'dart:convert';

import 'package:love_story/features/points/point_item_model.dart';
import 'package:love_story/features/points/point_record_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef SharedPreferencesLoader = Future<SharedPreferences> Function();

/// A small, account-scoped disk snapshot used only to paint the last known UI.
/// Supabase remains the source of truth and always refreshes this snapshot in
/// the background.
class PersistentSnapshotStore {
  PersistentSnapshotStore({SharedPreferencesLoader? preferencesLoader})
      : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static final instance = PersistentSnapshotStore();

  static const _prefix = 'love_story.snapshot.v1.';
  static const _couplePrefix = '${_prefix}couple.';
  static const _pointsPrefix = '${_prefix}points.';

  final SharedPreferencesLoader _preferencesLoader;

  String _coupleKey(String userId) => '$_couplePrefix$userId';
  String _pointsKey(String userId, String spaceId) =>
      '$_pointsPrefix$userId.$spaceId';

  Future<CoupleBindingSnapshot?> readCoupleBinding(String userId) async {
    final preferences = await _preferencesLoader();
    final raw = preferences.getString(_coupleKey(userId));
    if (raw == null) return null;
    try {
      final snapshot = CoupleBindingSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (snapshot.userId != userId) return null;
      return snapshot;
    } catch (_) {
      await preferences.remove(_coupleKey(userId));
      return null;
    }
  }

  Future<void> writeCoupleBinding(CoupleBindingSnapshot snapshot) async {
    final preferences = await _preferencesLoader();
    await preferences.setString(
      _coupleKey(snapshot.userId),
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<PointsHomeSnapshot?> readPointsHome(
    String userId,
    String spaceId,
  ) async {
    final preferences = await _preferencesLoader();
    final key = _pointsKey(userId, spaceId);
    final raw = preferences.getString(key);
    if (raw == null) return null;
    try {
      final snapshot = PointsHomeSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      if (snapshot.userId != userId || snapshot.spaceId != spaceId) {
        return null;
      }
      return snapshot;
    } catch (_) {
      await preferences.remove(key);
      return null;
    }
  }

  Future<void> writePointsHome(PointsHomeSnapshot snapshot) async {
    final preferences = await _preferencesLoader();
    await preferences.setString(
      _pointsKey(snapshot.userId, snapshot.spaceId),
      jsonEncode(snapshot.toJson()),
    );
  }

  Future<void> clearUser(String userId) async {
    final preferences = await _preferencesLoader();
    final coupleKey = _coupleKey(userId);
    final pointsPrefix = '$_pointsPrefix$userId.';
    final keys = preferences
        .getKeys()
        .where((key) => key == coupleKey || key.startsWith(pointsPrefix))
        .toList(growable: false);
    await Future.wait(keys.map(preferences.remove));
  }
}

class CoupleBindingSnapshot {
  CoupleBindingSnapshot({
    required this.userId,
    required this.savedAt,
    required this.profile,
    required this.spaceId,
    required this.inviteCode,
    required this.partnerId,
    required this.partner,
  });

  final String userId;
  final DateTime savedAt;
  final Map<String, dynamic>? profile;
  final String? spaceId;
  final String? inviteCode;
  final String? partnerId;
  final Map<String, dynamic>? partner;

  factory CoupleBindingSnapshot.fromJson(Map<String, dynamic> json) =>
      CoupleBindingSnapshot(
        userId: json['user_id'] as String,
        savedAt: DateTime.parse(json['saved_at'] as String),
        profile: json['profile'] == null
            ? null
            : Map<String, dynamic>.from(json['profile'] as Map),
        spaceId: json['space_id'] as String?,
        inviteCode: json['invite_code'] as String?,
        partnerId: json['partner_id'] as String?,
        partner: json['partner'] == null
            ? null
            : Map<String, dynamic>.from(json['partner'] as Map),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'profile': profile,
        'space_id': spaceId,
        'invite_code': inviteCode,
        'partner_id': partnerId,
        'partner': partner,
      };
}

class PointsHomeSnapshot {
  PointsHomeSnapshot({
    required this.userId,
    required this.spaceId,
    required this.savedAt,
    required this.items,
    required this.records,
    required this.partnerTotalEarned,
    required this.partnerTotalSpent,
    required this.myTotalEarned,
    required this.myTotalSpent,
    required this.myLocked,
    required this.partnerLocked,
  });

  final String userId;
  final String spaceId;
  final DateTime savedAt;
  final List<PointItemModel> items;
  final List<PointRecordModel> records;
  final int partnerTotalEarned;
  final int partnerTotalSpent;
  final int myTotalEarned;
  final int myTotalSpent;
  final int myLocked;
  final int partnerLocked;

  factory PointsHomeSnapshot.fromJson(Map<String, dynamic> json) =>
      PointsHomeSnapshot(
        userId: json['user_id'] as String,
        spaceId: json['space_id'] as String,
        savedAt: DateTime.parse(json['saved_at'] as String),
        items: (json['items'] as List)
            .map((item) => PointItemModel.fromJson(
                  Map<String, dynamic>.from(item as Map),
                ))
            .toList(growable: false),
        records: (json['records'] as List)
            .map((record) => PointRecordModel.fromJson(
                  Map<String, dynamic>.from(record as Map),
                ))
            .toList(growable: false),
        partnerTotalEarned: (json['partner_total_earned'] as num).toInt(),
        partnerTotalSpent: (json['partner_total_spent'] as num).toInt(),
        myTotalEarned: (json['my_total_earned'] as num).toInt(),
        myTotalSpent: (json['my_total_spent'] as num).toInt(),
        myLocked: (json['my_locked'] as num).toInt(),
        partnerLocked: (json['partner_locked'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'space_id': spaceId,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'items': items.map((item) => item.toJson()).toList(growable: false),
        'records':
            records.map((record) => record.toJson()).toList(growable: false),
        'partner_total_earned': partnerTotalEarned,
        'partner_total_spent': partnerTotalSpent,
        'my_total_earned': myTotalEarned,
        'my_total_spent': myTotalSpent,
        'my_locked': myLocked,
        'partner_locked': partnerLocked,
      };
}
