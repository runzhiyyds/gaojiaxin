import 'package:flutter_test/flutter_test.dart';
import 'package:love_story/core/background_read_retry.dart';

void main() {
  test('schedules a read retry and resets after success', () async {
    final controller = BackgroundReadRetry(
      delays: const [Duration(milliseconds: 1)],
    );
    var calls = 0;

    controller.schedule(() async => calls++);
    expect(controller.isScheduled, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls, 1);
    expect(controller.isScheduled, isFalse);

    controller.reset();
    controller.dispose();
  });

  test('does not create duplicate pending retries', () async {
    final controller = BackgroundReadRetry(
      delays: const [Duration(milliseconds: 5)],
    );
    var calls = 0;

    controller.schedule(() async => calls++);
    controller.schedule(() async => calls++);
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(calls, 1);

    controller.dispose();
  });
}
