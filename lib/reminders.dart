import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'task.dart';

/// "Still on it?" nudges for tasks that run longer than [minutes].
///
/// Every call is best-effort: on platforms without the plugin (tests,
/// desktop) failures are swallowed so the notebook keeps working.
class Reminders {
  Reminders._();
  static final instance = Reminders._();

  static const prefsKey = 'reminder_minutes';
  static const defaultMinutes = 25;
  static const choices = [0, 15, 25, 45, 60];

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<bool>? _ready;
  bool _asked = false;
  String _lastSig = '';

  Future<bool> _init() => _ready ??= () async {
    try {
      tzdata.initializeTimeZones();
      // On iOS the result reports permission (not requested here), so
      // only an exception means the plugin is unusable.
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Reminders unavailable: $e');
      return false;
    }
  }();

  Future<void> _askPermission() async {
    if (_asked) return;
    _asked = true;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true);
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  static int _idFor(TaskEntry t) => t.id.hashCode & 0x7fffffff;

  /// Reschedules reminders to match [tasks]: one for every started,
  /// unfinished task, [minutes] after its start. 0 turns them off.
  Future<void> sync(Iterable<TaskEntry> tasks, int minutes) async {
    final open = [
      for (final t in tasks)
        if (!t.isBlank && t.start != null && t.end == null) t,
    ];
    final sig = '$minutes|${open.map((t) => '${t.id}@${t.start}').join(',')}';
    if (sig == _lastSig) return;
    _lastSig = sig;
    if (!await _init()) return;

    try {
      await _plugin.cancelAllPendingNotifications();
      if (minutes <= 0) return;
      final now = DateTime.now();
      final due = [
        for (final t in open)
          if (t.start!.add(Duration(minutes: minutes)).isAfter(now)) t,
      ];
      if (due.isEmpty) return;
      await _askPermission();
      for (final t in due) {
        final at = t.start!.add(Duration(minutes: minutes)).toUtc();
        // The permission prompt may have taken a while; past dates throw.
        if (!at.isAfter(DateTime.now().toUtc())) continue;
        await _plugin.zonedSchedule(
          id: _idFor(t),
          scheduledDate: tz.TZDateTime.from(at, tz.UTC),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: 'Still on it? · $minutes min',
          body: t.text.trim(),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'long_task',
              'Long-running tasks',
              channelDescription:
                  'A nudge when a task has been open for a while.',
              importance: Importance.defaultImportance,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      }
    } catch (e) {
      debugPrint('Reminder scheduling failed: $e');
    }
  }
}

/// "Off", "15 min", ...
String reminderLabel(int minutes) => minutes <= 0 ? 'Off' : '$minutes min';
