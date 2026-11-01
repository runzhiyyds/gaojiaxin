import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_story/features/points/offline_record_queue.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final payload = OfflineRecordPayload(
    coupleSpaceId: 'space-1',
    authorUserId: 'user-a',
    partnerUserId: 'user-b',
    pointItemId: 'item-1',
    pointItemName: '日常',
    points: 35,
    recordAt: DateTime.utc(2026, 11, 1, 8, 30),
    isDomineering: false,
    randomBonus: 20,
    note: '只应该出现在解密后',
    loveDimension: 'care',
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('payload JSON round-trips without losing business fields', () {
    final restored = OfflineRecordPayload.fromJson(payload.toJson());
    expect(restored.coupleSpaceId, payload.coupleSpaceId);
    expect(restored.partnerUserId, payload.partnerUserId);
    expect(restored.points, payload.points);
    expect(restored.recordAt, payload.recordAt.toUtc());
    expect(restored.note, payload.note);
    expect(restored.randomBonus, payload.randomBonus);
  });

  test('AES-256-GCM ciphertext contains no record plaintext', () async {
    final cipher = OfflinePayloadCipher();
    final encrypted = await cipher.encrypt(payload);

    expect(encrypted, isNot(contains(payload.note!)));
    expect(encrypted, isNot(contains(payload.pointItemName)));
    expect(encrypted, isNot(contains(payload.partnerUserId)));

    final restored = await cipher.decrypt(encrypted);
    expect(restored.toJson(), payload.toJson());
  });

  test('tampered ciphertext is rejected instead of yielding altered data',
      () async {
    final cipher = OfflinePayloadCipher();
    final encrypted = await cipher.encrypt(payload);
    final tampered = encrypted.replaceFirst('"c":"', '"c":"A');

    await expectLater(cipher.decrypt(tampered), throwsA(anything));
  });

  test('concurrent first writes share one durable encryption key', () async {
    final cipher = OfflinePayloadCipher();
    final encrypted = await Future.wait([
      cipher.encrypt(payload),
      cipher.encrypt(payload),
    ]);

    expect((await cipher.decrypt(encrypted.first)).toJson(), payload.toJson());
    expect((await cipher.decrypt(encrypted.last)).toJson(), payload.toJson());
  });
}
