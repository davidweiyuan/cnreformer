/// Accumulates active foreground reading using monotonic elapsed time.
/// Navigation/lifecycle changes call update before changing active status.
class ReadingClock {
  final Duration Function() now;
  Duration _last = Duration.zero, _pending = Duration.zero;
  bool _active = false;
  ReadingClock(this.now) {
    _last = now();
  }
  void update({required bool active}) {
    final current = now();
    if (_active && current >= _last) _pending += current - _last;
    _last = current;
    _active = active;
  }

  int takeSeconds() {
    final seconds = _pending.inSeconds;
    _pending -= Duration(seconds: seconds);
    return seconds;
  }

  void reset() {
    _pending = Duration.zero;
    _last = now();
  }
}
