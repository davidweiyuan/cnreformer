import 'package:flutter_test/flutter_test.dart';
import 'package:reformed_piety/core/reading_clock.dart';

void main() {
  test('reading accumulates visits and excludes background time', () {
    var time = Duration.zero;
    final clock = ReadingClock(() => time);
    clock.update(active: true);
    time += const Duration(seconds: 35);
    clock.update(active: false);
    expect(clock.takeSeconds(), 35);
    time += const Duration(minutes: 20);
    clock.update(active: true);
    expect(clock.takeSeconds(), 0);
    time += const Duration(seconds: 25);
    clock.update(active: false);
    expect(clock.takeSeconds(), 25);
  });
  test(
    'reset discards pending reading, preserves subsecond accuracy otherwise',
    () {
      var time = Duration.zero;
      final clock = ReadingClock(() => time);
      clock.update(active: true);
      time += const Duration(milliseconds: 1500);
      clock.update(active: true);
      expect(clock.takeSeconds(), 1);
      time += const Duration(milliseconds: 500);
      clock.update(active: true);
      expect(clock.takeSeconds(), 1);
      time += const Duration(seconds: 10);
      clock.update(active: true);
      clock.reset();
      expect(clock.takeSeconds(), 0);
    },
  );
}
