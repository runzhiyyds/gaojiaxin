import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

enum OfflineRecordStatus { pending, sending, conflict }

class OfflineRecordPayload {
  const OfflineRecordPayload({
    required this.coupleSpaceId,
    required this.authorUserId,
    required this.partnerUserId,
    required this.pointItemId,
    required this.pointItemName,
    required this.points,
    required this.recordAt,
    required this.isDomineering,
    required this.randomBonus,
    this.note,
    this.loveDimension,
  });

  final String coupleSpaceId;
  final String authorUserId;
  final String partnerUserId;
  final String pointItemId;
  final String pointItemName;
  final int points;
  final DateTime recordAt;
  final bool isDomineering;
  final int randomBonus;
  final String? note;
  final String? loveDimension;

  Map<String, dynamic> toJson() => {
        'couple_space_id': coupleSpaceId,
        'author_user_id': authorUserId,
        'partner_user_id': partnerUserId,
        'point_item_id': pointItemId,
        'point_item_name': pointItemName,
        'points': points,
        'record_at': recordAt.toUtc().toIso8601String(),
        'is_domineering': isDomineering,
        'random_bonus': randomBonus,
        if (note != null) 'note': note,
        if (loveDimension != null) 'love_dimension': loveDimension,
      };

  factory OfflineRecordPayload.fromJson(Map<String, dynamic> json) =>
      OfflineRecordPayload(
        coupleSpaceId: json['couple_space_id'] as String,
        authorUserId: json['author_user_id'] as String,
        partnerUserId: json['partner_user_id'] as String,
        pointItemId: json['point_item_id'] as String,
        pointItemName: json['point_item_name'] as String,
        points: (json['points'] as num).toInt(),
        recordAt: DateTime.parse(json['record_at'] as String),
        isDomineering: json['is_domineering'] as bool,
        randomBonus: (json['random_bonus'] as num).toInt(),
        note: json['note'] as String?,
        loveDimension: json['love_dimension'] as String?,
      );
}

class OfflineRecordEntry {
  const OfflineRecordEntry({
    required this.id,
    required this.userId,
    required this.spaceId,
    required this.status,
    required this.createdAt,
    required this.attempts,
    this.lastError,
    this.payload,
  });

  final String id;
  final String userId;
  final String spaceId;
  final OfflineRecordStatus status;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final OfflineRecordPayload? payload;
}

class OfflinePayloadCipher {
  OfflinePayloadCipher({
    FlutterSecureStorage? secureStorage,
    AesGcm? algorithm,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _algorithm = algorithm ?? AesGcm.with256bits();

  static const _keyName = 'love_story.offline_record_key.v1';
  final FlutterSecureStorage _secureStorage;
  final AesGcm _algorithm;
  SecretKey? _cachedKey;
  Future<SecretKey>? _keyFuture;

  Future<SecretKey> _key() async {
    if (_cachedKey != null) return _cachedKey!;
    if (_keyFuture != null) return _keyFuture!;
    _keyFuture = _loadOrCreateKey();
    try {
      return _cachedKey = await _keyFuture!;
    } finally {
      _keyFuture = null;
    }
  }

  Future<SecretKey> _loadOrCreateKey() async {
    final saved = await _secureStorage.read(key: _keyName);
    if (saved != null) return SecretKey(base64Decode(saved));
    final key = SecretKeyData.random(length: 32);
    final bytes = await key.extractBytes();
    await _secureStorage.write(key: _keyName, value: base64Encode(bytes));
    return key;
  }

  Future<String> encrypt(OfflineRecordPayload payload) async {
    final clear = utf8.encode(jsonEncode(payload.toJson()));
    final box = await _algorithm.encrypt(clear, secretKey: await _key());
    return jsonEncode({
      'v': 1,
      'n': base64Encode(box.nonce),
      'c': base64Encode(box.cipherText),
      'm': base64Encode(box.mac.bytes),
    });
  }

  Future<OfflineRecordPayload> decrypt(String value) async {
    final envelope = Map<String, dynamic>.from(jsonDecode(value) as Map);
    final box = SecretBox(
      base64Decode(envelope['c'] as String),
      nonce: base64Decode(envelope['n'] as String),
      mac: Mac(base64Decode(envelope['m'] as String)),
    );
    final clear = await _algorithm.decrypt(box, secretKey: await _key());
    return OfflineRecordPayload.fromJson(
      Map<String, dynamic>.from(jsonDecode(utf8.decode(clear)) as Map),
    );
  }
}

class OfflineRecordStore {
  OfflineRecordStore({OfflinePayloadCipher? cipher})
      : _cipher = cipher ?? OfflinePayloadCipher();

  final OfflinePayloadCipher _cipher;
  Database? _db;

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      '$root/love_story_outbox.db',
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE offline_point_records (
          id TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          space_id TEXT NOT NULL,
          encrypted_payload TEXT NOT NULL,
          status TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      '''),
    );
    return _db!;
  }

  Future<OfflineRecordEntry> add(OfflineRecordPayload payload) async {
    final now = DateTime.now().toUtc();
    final id = const Uuid().v4();
    final encrypted = await _cipher.encrypt(payload);
    final db = await _database();
    await db.insert('offline_point_records', {
      'id': id,
      'user_id': payload.authorUserId,
      'space_id': payload.coupleSpaceId,
      'encrypted_payload': encrypted,
      'status': OfflineRecordStatus.pending.name,
      'attempts': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
    return OfflineRecordEntry(
      id: id,
      userId: payload.authorUserId,
      spaceId: payload.coupleSpaceId,
      status: OfflineRecordStatus.pending,
      createdAt: now,
      attempts: 0,
      payload: payload,
    );
  }

  Future<List<OfflineRecordEntry>> listForUser(String userId) async {
    final db = await _database();
    final rows = await db.query(
      'offline_point_records',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at ASC',
    );
    final result = <OfflineRecordEntry>[];
    for (final row in rows) {
      OfflineRecordPayload? payload;
      try {
        payload = await _cipher.decrypt(row['encrypted_payload'] as String);
      } catch (_) {
        // Keep an undecryptable row visible and removable; never discard it.
      }
      result.add(OfflineRecordEntry(
        id: row['id'] as String,
        userId: row['user_id'] as String,
        spaceId: row['space_id'] as String,
        status: OfflineRecordStatus.values.byName(row['status'] as String),
        createdAt: DateTime.parse(row['created_at'] as String),
        attempts: row['attempts'] as int,
        lastError: row['last_error'] as String?,
        payload: payload,
      ));
    }
    return result;
  }

  Future<void> mark(String id, OfflineRecordStatus status,
      {String? error}) async {
    final db = await _database();
    await db.rawUpdate(
      '''UPDATE offline_point_records
         SET status = ?, attempts = attempts + 1, last_error = ?, updated_at = ?
         WHERE id = ?''',
      [status.name, error, DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  Future<void> delete(String id) async {
    final db = await _database();
    await db.delete('offline_point_records', where: 'id = ?', whereArgs: [id]);
  }
}

enum OfflineSubmitResult { synced, queued }

class OfflineRecordQueue extends ChangeNotifier with WidgetsBindingObserver {
  OfflineRecordQueue({
    required SupabaseClient client,
    required PointsRepository pointsRepository,
    OfflineRecordStore? store,
    Connectivity? connectivity,
  })  : _client = client,
        _pointsRepository = pointsRepository,
        _store = store ?? OfflineRecordStore(),
        _connectivity = connectivity ?? Connectivity() {
    if (!kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
      _connectivitySubscription =
          _connectivity.onConnectivityChanged.listen((results) {
        if (results.any((result) => result != ConnectivityResult.none)) {
          unawaited(sync());
        }
      });
      _authSubscription = _client.auth.onAuthStateChange.listen((_) {
        unawaited(refresh());
        unawaited(sync());
      });
      unawaited(refresh());
      unawaited(sync());
    }
  }

  final SupabaseClient _client;
  final PointsRepository _pointsRepository;
  final OfflineRecordStore _store;
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _retryTimer;
  int _retryStep = 0;
  List<OfflineRecordEntry> _entries = const [];
  bool _syncing = false;

  List<OfflineRecordEntry> get entries => List.unmodifiable(_entries);
  int get pendingCount => _entries.length;
  int get conflictCount => _entries
      .where((entry) => entry.status == OfflineRecordStatus.conflict)
      .length;
  bool get syncing => _syncing;

  Future<void> refresh() async {
    if (kIsWeb) return;
    final userId = _client.auth.currentUser?.id;
    _entries = userId == null ? const [] : await _store.listForUser(userId);
    notifyListeners();
  }

  Future<OfflineSubmitResult> submit(OfflineRecordPayload payload) async {
    if (kIsWeb) {
      await _send(const Uuid().v4(), payload);
      return OfflineSubmitResult.synced;
    }
    final entry = await _store.add(payload);
    await refresh();
    try {
      await _send(entry.id, payload);
      await _store.delete(entry.id);
      _pointsRepository.invalidateForSpace(payload.coupleSpaceId);
      await refresh();
      return OfflineSubmitResult.synced;
    } catch (error) {
      if (!_shouldDefer(error)) {
        await _store.mark(entry.id, OfflineRecordStatus.conflict,
            error: toUserMessage(error, context: 'OfflineRecordQueue.submit'));
      } else {
        _scheduleRetry();
      }
      await refresh();
      return OfflineSubmitResult.queued;
    }
  }

  Future<void> sync() async {
    if (kIsWeb || _syncing || _client.auth.currentUser == null) return;
    _syncing = true;
    notifyListeners();
    try {
      await refresh();
      for (final entry in List<OfflineRecordEntry>.from(_entries)) {
        if (entry.status == OfflineRecordStatus.conflict ||
            entry.payload == null) continue;
        if (_client.auth.currentUser?.id != entry.userId) break;
        await _store.mark(entry.id, OfflineRecordStatus.sending);
        try {
          await _send(entry.id, entry.payload!);
          await _store.delete(entry.id);
          _pointsRepository.invalidateForSpace(entry.spaceId);
        } catch (error) {
          final status = _shouldDefer(error)
              ? OfflineRecordStatus.pending
              : OfflineRecordStatus.conflict;
          await _store.mark(entry.id, status,
              error: status == OfflineRecordStatus.conflict
                  ? toUserMessage(error, context: 'OfflineRecordQueue.sync')
                  : null);
          if (status == OfflineRecordStatus.pending) {
            _scheduleRetry();
            break;
          }
        }
      }
    } finally {
      _syncing = false;
      await refresh();
      if (!_entries
          .any((entry) => entry.status == OfflineRecordStatus.pending)) {
        _retryStep = 0;
        _retryTimer?.cancel();
      }
    }
  }

  Future<void> retry(String id) async {
    await _store.mark(id, OfflineRecordStatus.pending);
    await refresh();
    await sync();
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    await refresh();
  }

  Future<void> _send(String requestId, OfflineRecordPayload payload) async {
    final currentUserId = _client.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != payload.authorUserId) {
      throw const AuthException('offline record belongs to another account');
    }
    await _client.rpc('create_point_record_offline_atomic', params: {
      'p_couple_space_id': payload.coupleSpaceId,
      'p_partner_user_id': payload.partnerUserId,
      'p_point_item_id': payload.pointItemId,
      'p_points': payload.points,
      'p_record_at': payload.recordAt.toUtc().toIso8601String(),
      'p_note': payload.note,
      'p_love_dimension': payload.loveDimension,
      'p_is_domineering': payload.isDomineering,
      'p_random_bonus': payload.randomBonus,
      'p_request_id': requestId,
    }).timeout(const Duration(seconds: 14));
  }

  void _scheduleRetry() {
    if (_retryTimer?.isActive == true) return;
    const delays = [15, 30, 60, 120, 300];
    final seconds = delays[_retryStep.clamp(0, delays.length - 1)];
    if (_retryStep < delays.length - 1) _retryStep++;
    _retryTimer = Timer(Duration(seconds: seconds), () => unawaited(sync()));
  }

  bool _shouldDefer(Object error) =>
      isNetworkFailure(error) || error is AuthException;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _authSubscription?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
