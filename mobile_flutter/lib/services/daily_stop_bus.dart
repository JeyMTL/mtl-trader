import 'package:flutter/foundation.dart';

/// Lets a settings screen ask the daily-stop gate to re-read the day at once
/// instead of waiting for its minute timer.
class DailyStopBus {
  DailyStopBus._();

  static final ValueNotifier<int> version = ValueNotifier<int>(0);

  static void refresh() => version.value++;
}
