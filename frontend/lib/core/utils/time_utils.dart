Duration durationFromSeconds(int seconds) {
  return Duration(seconds: seconds <= 0 ? 1 : seconds);
}

String relativeTime(DateTime? time) {
  if (time == null) return 'waiting';

  final seconds = DateTime.now().difference(time).inSeconds;
  if (seconds < 2) return 'just now';
  if (seconds < 60) return '$seconds sec ago';

  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min ago';

  final hours = minutes ~/ 60;
  return '$hours hr ago';
}
