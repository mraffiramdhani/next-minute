import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task.dart';
import 'theme.dart';

/// `2026-11-04` style key for a calendar day.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String k) => DateTime.parse(k);

/// "Wednesday, 4 November" (year added when it isn't the current one).
String longDateLabel(DateTime d) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final base = '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]}';
  return d.year == DateTime.now().year ? base : '$base ${d.year}';
}

/// Plain-text version of a page, for sharing.
String pageAsText(DateTime day, List<TaskEntry> tasks) {
  final b = StringBuffer('Next Minute — ${longDateLabel(day)}\n');
  final done = tasks.where((t) => t.done).length;
  final total = formatTotal(tasks);
  b.writeln('$done of ${tasks.length} done${total.isEmpty ? '' : ' · $total'}');
  b.writeln();
  for (final t in tasks) {
    final times = t.start == null && t.end == null
        ? ''
        : '${formatTime(t.start).isEmpty ? '–' : formatTime(t.start)}'
              '–${formatTime(t.end)}';
    final dur = formatDuration(t.start, t.end);
    final meta = [if (times.isNotEmpty) times, if (dur.isNotEmpty) '($dur)'].join(' ');
    b.writeln('${t.done ? '✓' : '○'} ${meta.isEmpty ? '' : '$meta  '}${t.text.trim()}');
  }
  return b.toString().trimRight();
}

/// Opens the system share sheet with [tasks] as text.
Future<void> sharePage(
  BuildContext context,
  DateTime day,
  List<TaskEntry> tasks,
) async {
  final box = context.findRenderObject() as RenderBox?;
  try {
    await SharePlus.instance.share(
      ShareParams(
        text: pageAsText(day, tasks),
        subject: 'Next Minute — ${longDateLabel(day)}',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (e) {
    debugPrint('Share failed: $e');
  }
}

/// Past pages, stored as `{ "2026-11-04": [task, ...], ... }`.
class HistoryStore {
  HistoryStore(this.prefs);
  final SharedPreferences prefs;
  static const key = 'history_v1';

  Map<String, List<TaskEntry>> load() {
    final raw = prefs.getString(key);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (day, list) => MapEntry(
          day,
          (list as List)
              .map((e) => TaskEntry.fromJson(e as Map<String, dynamic>))
              .toList(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  /// Adds [tasks] to [day]'s page. Serialises immediately, so callers may
  /// mutate the tasks afterwards.
  void append(String day, Iterable<TaskEntry> tasks) {
    final list = tasks.toList();
    if (list.isEmpty) return;
    final raw = prefs.getString(key);
    Map<String, dynamic> map = {};
    if (raw != null) {
      try {
        map = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {}
    }
    final existing = (map[day] as List?) ?? [];
    map[day] = [...existing, ...list.map((t) => t.toJson())];
    prefs.setString(key, jsonEncode(map));
  }
}

/// Read-only list of previous days' pages, newest first.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key, required this.store});
  final HistoryStore store;

  @override
  Widget build(BuildContext context) {
    final nb = context.nb;
    final days = store.load().entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 14),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: nb.paper,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: nb.columnRule.withValues(alpha: 0.35),
                        ),
                      ),
                      child: IconButton(
                        tooltip: 'Back',
                        iconSize: 20,
                        color: nb.ink,
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Past days',
                      style: TextStyle(
                        fontFamily: kTitleFont,
                        fontSize: 40,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                        color: nb.ink,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: days.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Nothing here yet.\nEach day\'s page moves here '
                            'when a new day starts.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 19, color: nb.fadedInk),
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(context).bottom + 16,
                        ),
                        itemCount: days.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 14),
                        itemBuilder: (_, i) =>
                            _DayCard(day: days[i].key, tasks: days[i].value),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({required this.day, required this.tasks});
  final String day;
  final List<TaskEntry> tasks;

  @override
  Widget build(BuildContext context) {
    final nb = context.nb;
    final done = tasks.where((t) => t.done).length;

    return Container(
      decoration: BoxDecoration(
        color: nb.paper,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: nb.columnRule.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  longDateLabel(parseDayKey(day)),
                  style: TextStyle(fontSize: 20, color: nb.ink),
                ),
              ),
              Text(
                '$done of ${tasks.length} done'
                '${formatTotal(tasks).isEmpty ? '' : ' · ${formatTotal(tasks)}'}',
                style: TextStyle(fontSize: 16, color: nb.fadedInk),
              ),
              IconButton(
                tooltip: 'Share',
                visualDensity: VisualDensity.compact,
                iconSize: 19,
                color: nb.fadedInk,
                icon: const Icon(Icons.ios_share_rounded),
                onPressed: () => sharePage(context, parseDayKey(day), tasks),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final t in tasks)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: nb.rule.withValues(alpha: 0.5),
                    width: 0.7,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      '${formatTime(t.start).isEmpty ? '–' : formatTime(t.start)}'
                      ' – '
                      '${formatTime(t.end).isEmpty ? '' : formatTime(t.end)}'
                      '${formatDuration(t.start, t.end).isEmpty ? '' : '\n${formatDuration(t.start, t.end)}'}',
                      style: TextStyle(fontSize: 16, height: 1.15, color: nb.fadedInk),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      t.text,
                      style: TextStyle(
                        fontSize: 18,
                        color: t.done ? nb.fadedInk : nb.ink,
                        decoration: t.done ? TextDecoration.lineThrough : null,
                        decorationColor: nb.fadedInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 18,
                    child: t.done
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: nb.fadedInk,
                            semanticLabel: 'Done',
                          )
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
