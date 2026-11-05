import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:next_minute/history.dart';
import 'package:next_minute/main.dart';
import 'package:next_minute/task.dart';

void main() {
  testWidgets('enter stamps start, checkbox stamps end', (tester) async {
    SharedPreferences.setMockInitialValues({'tour_seen_v1': true});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(NextMinuteApp(prefs: prefs));
    await tester.pumpAndSettle();

    Map saved() => (jsonDecode(prefs.getString('tasks_v1')!) as List).first;

    await tester.showKeyboard(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'Write the report intro');
    await tester.pump();
    expect(saved()['start'], isNull);

    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(saved()['start'], isNotNull);
    expect(saved()['end'], isNull);
    expect(find.byType(TextField, skipOffstage: false), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.check_rounded).first);
    await tester.pumpAndSettle();
    expect(saved()['end'], isNotNull);
  });

  testWidgets('tour shows on first launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(NextMinuteApp(prefs: prefs));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Next Minute'), findsOneWidget);
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Start writing'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Next Minute'), findsNothing);
    expect(prefs.getBool('tour_seen_v1'), true);
  });

  testWidgets('new day files old page and carries unfinished tasks',
      (tester) async {
    final y = DateTime.now().subtract(const Duration(days: 1));
    final t1 = DateTime(y.year, y.month, y.day, 9, 0);
    final t2 = DateTime(y.year, y.month, y.day, 9, 30);
    SharedPreferences.setMockInitialValues({
      'tour_seen_v1': true,
      'page_day_v1': dayKey(y),
      'tasks_v1': jsonEncode([
        {'id': 'a', 'text': 'Finished thing', 'start': t1.toIso8601String(),
         'end': t2.toIso8601String()},
        {'id': 'b', 'text': 'Unfinished thing', 'start': t2.toIso8601String(),
         'end': null},
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(NextMinuteApp(prefs: prefs));
    await tester.pumpAndSettle();

    final today = jsonDecode(prefs.getString('tasks_v1')!) as List;
    expect(today.length, 1);
    expect(today.first['text'], 'Unfinished thing');
    expect(today.first['start'], isNull);
    expect(prefs.getString('page_day_v1'), dayKey(DateTime.now()));

    final past = HistoryStore(prefs).load();
    expect(past[dayKey(y)]!.map((t) => t.text),
        ['Finished thing', 'Unfinished thing']);
    expect(find.textContaining('1 unfinished task carried over'), findsOneWidget);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.text('Past days'), findsOneWidget);
    expect(find.text('Finished thing'), findsOneWidget);
  });

  testWidgets('tapping a time lets you set or clear it', (tester) async {
    final start = DateTime.now().subtract(const Duration(minutes: 5));
    SharedPreferences.setMockInitialValues({
      'tour_seen_v1': true,
      'page_day_v1': dayKey(DateTime.now()),
      'tasks_v1': jsonEncode([
        {'id': 'a', 'text': 'Call Sam', 'start': start.toIso8601String(), 'end': null},
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(NextMinuteApp(prefs: prefs));
    await tester.pumpAndSettle();
    Map saved() => (jsonDecode(prefs.getString('tasks_v1')!) as List).first;
    Finder cell(String label) => find
        .byWidgetPredicate((w) => w is Semantics && w.properties.label == label)
        .first;

    // End cell: set to now marks the task done.
    await tester.tap(cell('End time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set to now'));
    await tester.pumpAndSettle();
    expect(saved()['end'], isNotNull);

    // Start cell: clear it.
    await tester.tap(cell('Start time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(saved()['start'], isNull);
    expect(saved()['end'], isNotNull);
  });

  test('durations and totals', () {
    final a = DateTime(2026, 11, 4, 9, 0, 40);
    expect(formatDuration(a, a.add(const Duration(seconds: 10))), '<1m');
    expect(formatDuration(a, DateTime(2026, 11, 4, 9, 25)), '25m');
    expect(formatDuration(a, DateTime(2026, 11, 4, 10, 5)), '1h 5m');
    expect(formatDuration(a, DateTime(2026, 11, 4, 11, 0)), '2h');
    expect(formatDuration(a, DateTime(2026, 11, 4, 8, 0)), '');
    expect(formatDuration(a, null), '');
    final tasks = [
      TaskEntry(id: '1', text: 'x', start: a, end: DateTime(2026, 11, 4, 9, 30)),
      TaskEntry(id: '2', text: 'y', start: a, end: DateTime(2026, 11, 4, 10, 15)),
      TaskEntry(id: '3', text: 'z', start: a),
    ];
    expect(formatTotal(tasks), '1h 45m');
    final text = pageAsText(DateTime(2026, 11, 4), tasks);
    expect(text, contains('2 of 3 done · 1h 45m'));
    expect(text, contains('✓ 09:00–09:30 (30m)  x'));
    expect(text, contains('○ 09:00–  z'));
  });

  testWidgets('reminder setting is saved from the menu', (tester) async {
    SharedPreferences.setMockInitialValues({'tour_seen_v1': true});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(NextMinuteApp(prefs: prefs));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Reminder: 25 min'), findsOneWidget);
    await tester.tap(find.text('Reminder: 25 min'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('45 min'));
    await tester.pumpAndSettle();
    expect(prefs.getInt('reminder_minutes'), 45);
  });
}
