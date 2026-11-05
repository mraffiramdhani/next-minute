import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'history.dart';
import 'reminders.dart';
import 'task.dart';
import 'theme.dart';
import 'tour.dart';

/// Column geometry shared by header, rows and the empty ruled filler.
class Cols {
  static const start = 54.0;
  static const end = 54.0;
  static const action = 50.0;
  static const minRow = 50.0;
}

/// Space between the screen edge and the paper sheet.
const kEdge = 16.0;

class NotebookPage extends StatefulWidget {
  const NotebookPage({
    super.key,
    required this.prefs,
    required this.onToggleTheme,
  });

  final SharedPreferences prefs;
  final VoidCallback onToggleTheme;

  @override
  State<NotebookPage> createState() => _NotebookPageState();
}

class _NotebookPageState extends State<NotebookPage>
    with WidgetsBindingObserver {
  static const _tasksKey = 'tasks_v1';
  static const _tourKey = 'tour_seen_v1';
  static const _pageDayKey = 'page_day_v1';

  late final HistoryStore _history = HistoryStore(widget.prefs);
  late int _reminderMins =
      widget.prefs.getInt(Reminders.prefsKey) ?? Reminders.defaultMinutes;
  Timer? _midnight;

  final List<TaskEntry> _tasks = [];
  final Map<String, TextEditingController> _ctrl = {};
  final Map<String, FocusNode> _focus = {};
  final ScrollController _scroll = ScrollController();
  int _idSeq = 0;

  // Tour targets.
  final _kStart = GlobalKey();
  final _kEnd = GlobalKey();
  final _kTask = GlobalKey();
  final _kAction = GlobalKey();
  final _kMenu = GlobalKey();
  bool _showTour = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    final carried = _rollover();
    Reminders.instance.sync(_tasks, _reminderMins);
    _scheduleMidnight();
    _showTour = !(widget.prefs.getBool(_tourKey) ?? false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (carried != null) _announceNewDay(carried);
      if (!_showTour) _focusBlank();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkNewDay();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    _midnight = Timer(next.difference(now), () {
      _checkNewDay();
      _scheduleMidnight();
    });
  }

  void _checkNewDay() {
    if (!mounted) return;
    int? carried;
    setState(() => carried = _rollover());
    if (carried != null) _announceNewDay(carried!);
  }

  /// Day of the page on screen. Older installs have no stored day, so it is
  /// guessed from the newest time written on the page.
  String _pageDay() {
    final stored = widget.prefs.getString(_pageDayKey);
    if (stored != null) return stored;
    DateTime? latest;
    for (final t in _tasks) {
      for (final d in [t.start, t.end]) {
        if (d != null && (latest == null || d.isAfter(latest))) latest = d;
      }
    }
    return dayKey(latest ?? DateTime.now());
  }

  /// When the page belongs to an earlier day: file it under Past days and
  /// start today's page with that day's unfinished tasks (times cleared).
  /// Returns how many tasks were carried over, or null if nothing happened.
  int? _rollover() {
    final today = dayKey(DateTime.now());
    final pageDay = _pageDay();
    widget.prefs.setString(_pageDayKey, today);
    if (pageDay == today) return null;

    final written = _tasks.where((t) => !t.isBlank).toList();
    if (written.isEmpty) return null;
    _history.append(pageDay, written);

    final dropped = _tasks.where((t) => t.isBlank || t.done).toList();
    _tasks.removeWhere(dropped.contains);
    for (final t in _tasks) {
      t.start = null;
      t.end = null;
    }
    _ensureTrailingBlank();
    _save();
    _disposeLater(dropped);
    return _tasks.where((t) => !t.isBlank).length;
  }

  /// Controllers may still be attached to fields in the current frame.
  void _disposeLater(Iterable<TaskEntry> gone) {
    final ctrls = [for (final t in gone) _ctrl.remove(t.id)];
    final nodes = [for (final t in gone) _focus.remove(t.id)];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in ctrls) {
        c?.dispose();
      }
      for (final f in nodes) {
        f?.dispose();
      }
    });
  }

  void _announceNewDay(int carried) {
    if (!mounted) return;
    final what = carried == 0
        ? 'Fresh page for today.'
        : '$carried unfinished task${carried == 1 ? '' : 's'} carried over.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('New day! $what Yesterday is in Past days.'),
          action: SnackBarAction(label: 'View', onPressed: _openHistory),
        ),
      );
  }

  void _openHistory() {
    FocusScope.of(context).unfocus();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => HistoryPage(store: _history)));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnight?.cancel();
    for (final c in _ctrl.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  // ---------- persistence ----------

  void _load() {
    final raw = widget.prefs.getString(_tasksKey);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => TaskEntry.fromJson(e as Map<String, dynamic>))
            .where((t) => !t.isBlank)
            .toList();
        _tasks.addAll(list);
      } catch (_) {
        /* corrupted – start fresh */
      }
    }
    for (final t in _tasks) {
      _attach(t);
    }
    _ensureTrailingBlank();
  }

  void _save() {
    final data = _tasks
        .where((t) => !t.isBlank)
        .map((t) => t.toJson())
        .toList();
    widget.prefs.setString(_tasksKey, jsonEncode(data));
    Reminders.instance.sync(_tasks, _reminderMins);
  }

  Future<void> _chooseReminder() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Long task reminder'),
        contentPadding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Get a nudge when a task has been open this long.',
              style: TextStyle(fontSize: 17, color: context.nb.fadedInk),
            ),
          ),
          for (final m in Reminders.choices)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(reminderLabel(m), style: const TextStyle(fontSize: 19)),
              trailing: m == _reminderMins
                  ? Icon(Icons.check_rounded, color: context.nb.ink)
                  : null,
              onTap: () => Navigator.pop(c, m),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _reminderMins = picked);
    widget.prefs.setInt(Reminders.prefsKey, picked);
    Reminders.instance.sync(_tasks, picked);
  }

  void _shareToday() {
    final written = _tasks.where((t) => !t.isBlank).toList();
    if (written.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Nothing on this page yet.')));
      return;
    }
    sharePage(context, DateTime.now(), written);
  }

  // ---------- task helpers ----------

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idSeq++}';

  void _attach(TaskEntry t) {
    _ctrl[t.id] = TextEditingController(text: t.text);
    _focus[t.id] = FocusNode();
  }

  void _ensureTrailingBlank() {
    if (_tasks.isEmpty || !_tasks.last.isBlank) {
      final t = TaskEntry(id: _newId());
      _attach(t);
      _tasks.add(t);
    }
  }

  void _focusBlank() {
    if (!mounted || _tasks.isEmpty) return;
    _focus[_tasks.last.id]?.requestFocus();
  }

  void _onChanged(TaskEntry t, String value) {
    t.text = value;
    if (t.isBlank && t != _tasks.last) {
      // Clearing text resets the times so the row reads as a fresh line.
      t.start = null;
      t.end = null;
    }
    setState(_ensureTrailingBlank);
    _save();
  }

  /// Enter on the on-screen keyboard: stamp start time and move to next line.
  void _onSubmitted(TaskEntry t) {
    if (t.isBlank) {
      _focus[t.id]?.requestFocus();
      return;
    }
    setState(() {
      t.start ??= DateTime.now();
      _ensureTrailingBlank();
    });
    _save();
    final next = _tasks[_tasks.indexOf(t) + 1];
    // Focusing the field scrolls it into view by itself.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focus[next.id]?.requestFocus(),
    );
  }

  void _onCheck(TaskEntry t, bool value) {
    if (t.isBlank) return;
    HapticFeedback.lightImpact();
    setState(() {
      if (value) {
        final now = DateTime.now();
        t.start ??= now;
        t.end = now;
      } else {
        t.end = null;
      }
    });
    _save();
  }

  /// Tap on a start/end cell: set it to now, pick a time, or clear it.
  Future<void> _editTime(TaskEntry t, {required bool start}) async {
    if (t.isBlank) return;
    FocusScope.of(context).unfocus();
    final nb = context.nb;
    final current = start ? t.start : t.end;
    final label = start ? 'Start time' : 'End time';

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: nb.paper,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  current == null ? label : '$label · ${formatTime(current)}',
                  style: TextStyle(
                    fontFamily: kTitleFont,
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: nb.ink,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  t.text.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, color: nb.fadedInk),
                ),
              ),
              ListTile(
                leading: Icon(Icons.bolt_rounded, color: nb.ink),
                title: const Text('Set to now', style: TextStyle(fontSize: 19)),
                onTap: () => Navigator.pop(c, 'now'),
              ),
              ListTile(
                leading: Icon(Icons.schedule_rounded, color: nb.ink),
                title: const Text(
                  'Pick a time…',
                  style: TextStyle(fontSize: 19),
                ),
                onTap: () => Navigator.pop(c, 'pick'),
              ),
              if (current != null)
                ListTile(
                  leading: Icon(Icons.close_rounded, color: nb.ink),
                  title: const Text('Clear', style: TextStyle(fontSize: 19)),
                  onTap: () => Navigator.pop(c, 'clear'),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;

    DateTime? value;
    switch (choice) {
      case 'now':
        value = DateTime.now();
      case 'clear':
        value = null;
      case 'pick':
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
          helpText: label.toUpperCase(),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
        if (picked == null || !mounted) return;
        final base = current ?? (start ? t.end : t.start) ?? DateTime.now();
        value = DateTime(
          base.year,
          base.month,
          base.day,
          picked.hour,
          picked.minute,
        );
    }

    HapticFeedback.selectionClick();
    setState(() {
      if (start) {
        t.start = value;
      } else {
        t.end = value;
      }
    });
    _save();
  }

  void _delete(TaskEntry t) {
    final idx = _tasks.indexOf(t);
    setState(() {
      _tasks.removeAt(idx);
      _ensureTrailingBlank();
    });
    _save();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Task removed'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              setState(() => _tasks.insert(idx.clamp(0, _tasks.length), t));
              _save();
            },
          ),
        ),
      );
  }

  Future<void> _newPage() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Start a new page?'),
        content: const Text(
          'This page moves to Past days and you get a blank one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('New page'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final gone = List.of(_tasks);
    _history.append(dayKey(DateTime.now()), gone.where((t) => !t.isBlank));
    setState(() {
      _tasks.clear();
      _ensureTrailingBlank();
    });
    _disposeLater(gone);
    _save();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusBlank());
  }

  void _clearDone() {
    final gone = _tasks.where((t) => t.done).toList();
    _history.append(dayKey(DateTime.now()), gone);
    setState(() {
      _tasks.removeWhere(gone.contains);
      _ensureTrailingBlank();
    });
    _disposeLater(gone);
    _save();
  }

  void _startTour() {
    FocusScope.of(context).unfocus();
    setState(() => _showTour = true);
  }

  void _endTour() {
    widget.prefs.setBool(_tourKey, true);
    setState(() => _showTour = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusBlank());
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final nb = context.nb;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final doneCount = _tasks.where((t) => t.done).length;
    final total = _tasks.where((t) => !t.isBlank).length;

    final scaffold = AnnotatedRegion<SystemUiOverlayStyle>(
      value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kEdge),
            child: Column(
              children: [
                _TopBar(
                  done: doneCount,
                  total: total,
                  spent: formatTotal(_tasks),
                  reminderMins: _reminderMins,
                  dark: dark,
                  menuKey: _kMenu,
                  onToggleTheme: widget.onToggleTheme,
                  onMenu: (v) {
                    switch (v) {
                      case 'clear':
                        _clearDone();
                      case 'new':
                        _newPage();
                      case 'history':
                        _openHistory();
                      case 'share':
                        _shareToday();
                      case 'reminder':
                        _chooseReminder();
                      case 'tour':
                        _startTour();
                    }
                  },
                ),
                Expanded(child: _paper(nb)),
              ],
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        scaffold,
        if (_showTour)
          TourOverlay(
            onFinish: _endTour,
            steps: [
              const TourStep(
                title: 'Welcome to Next Minute',
                body:
                    'Don\'t plan the whole day. Write down only the very next '
                    'thing you\'re about to do, do it, then write the next one.',
              ),
              TourStep(
                target: _kTask,
                title: 'Task',
                body:
                    'Type your next task here. Long tasks wrap onto new lines '
                    'and push the ruled line down.',
              ),
              TourStep(
                target: _kStart,
                title: 'Start',
                body:
                    'Tap Enter on your keyboard when you\'re done typing. The '
                    'start time fills in and a fresh line appears.',
              ),
              TourStep(
                target: _kAction,
                title: 'Done',
                body: 'Tick the box when the task is finished.',
              ),
              TourStep(
                target: _kEnd,
                title: 'End',
                body:
                    'Ticking the box writes the end time here. Untick to clear it. '
                    'Got a time wrong? Tap it to change it.',
              ),
              TourStep(
                target: _kMenu,
                title: 'More',
                body:
                    'Swipe a task left to delete it. Each morning you get a fresh '
                    'page with yesterday\'s unfinished tasks; old pages live in '
                    'Past days in this menu. The sun/moon switches themes.',
              ),
            ],
          ),
      ],
    );
  }

  /// The sheet of paper: rounded, inset from the screen edges.
  Widget _paper(NotebookColors nb) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : kEdge),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: nb.paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: nb.columnRule.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: nb.shadow,
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              _Header(
                kStart: _kStart,
                kEnd: _kEnd,
                kTask: _kTask,
                kAction: _kAction,
              ),
              Expanded(child: _list()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list() {
    return LayoutBuilder(
      builder: (context, box) => ListView.builder(
        controller: _scroll,
        padding: EdgeInsets.zero,
        itemCount: _tasks.length + 1,
        itemBuilder: (context, i) {
          if (i == _tasks.length) {
            // Empty ruled lines that fill the rest of the page.
            final lines = (box.maxHeight / Cols.minRow).ceil() + 1;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _focusBlank,
              child: Column(
                children: List.generate(lines, (_) => const _RuledLine()),
              ),
            );
          }
          final t = _tasks[i];
          final row = _TaskRow(
            task: t,
            controller: _ctrl[t.id]!,
            focusNode: _focus[t.id]!,
            onChanged: (v) => _onChanged(t, v),
            onSubmitted: () => _onSubmitted(t),
            onCheck: (v) => _onCheck(t, v),
            onEditTime: (start) => _editTime(t, start: start),
          );
          // Always the same wrapper type so the TextField keeps focus
          // when a blank line receives its first character.
          return Dismissible(
            key: ValueKey(t.id),
            direction: t.isBlank
                ? DismissDirection.none
                : DismissDirection.endToStart,
            background: const _DeleteBackground(),
            onDismissed: (_) => _delete(t),
            child: row,
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.done,
    required this.total,
    required this.spent,
    required this.reminderMins,
    required this.dark,
    required this.menuKey,
    required this.onToggleTheme,
    required this.onMenu,
  });

  final int done, total;
  final String spent;
  final int reminderMins;
  final bool dark;
  final Key menuKey;
  final VoidCallback onToggleTheme;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final nb = context.nb;
    final progress = total == 0 ? 0.0 : done / total;

    Widget roundButton({Key? key, required Widget child}) => Container(
      key: key,
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: nb.paper,
        shape: BoxShape.circle,
        border: Border.all(color: nb.columnRule.withValues(alpha: 0.35)),
      ),
      child: child,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 0, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next Minute',
                      style: TextStyle(
                        fontFamily: kTitleFont,
                        fontSize: 40,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                        color: nb.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      longDateLabel(DateTime.now()),
                      style: TextStyle(fontSize: 17, color: nb.fadedInk),
                    ),
                  ],
                ),
              ),
              roundButton(
                child: IconButton(
                  tooltip: dark ? 'Light theme' : 'Dark theme',
                  iconSize: 20,
                  color: nb.ink,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (c, a) => RotationTransition(
                      turns: a,
                      child: FadeTransition(opacity: a, child: c),
                    ),
                    child: Icon(
                      dark
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      key: ValueKey(dark),
                    ),
                  ),
                  onPressed: onToggleTheme,
                ),
              ),
              const SizedBox(width: 8),
              roundButton(
                key: menuKey,
                child: PopupMenuButton<String>(
                  tooltip: 'More',
                  iconSize: 20,
                  iconColor: nb.ink,
                  icon: const Icon(Icons.more_horiz),
                  offset: const Offset(0, 48),
                  onSelected: onMenu,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'clear',
                      child: Text('Clear finished tasks'),
                    ),
                    const PopupMenuItem(value: 'new', child: Text('New page')),
                    const PopupMenuItem(value: 'history', child: Text('Past days')),
                    const PopupMenuItem(
                      value: 'share',
                      child: Text("Share today's page"),
                    ),
                    PopupMenuItem(
                      value: 'reminder',
                      child: Text('Reminder: ${reminderLabel(reminderMins)}'),
                    ),
                    const PopupMenuItem(
                      value: 'tour',
                      child: Text('Show tour again'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: progress),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => LinearProgressIndicator(
                      value: v,
                      minHeight: 5,
                      color: nb.ink,
                      backgroundColor: nb.columnRule.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                spent.isEmpty ? '$done of $total done' : '$done of $total done · $spent',
                style: TextStyle(fontSize: 16, color: nb.fadedInk),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

BoxDecoration _cellDivider(NotebookColors nb) => BoxDecoration(
  border: Border(
    right: BorderSide(color: nb.columnRule.withValues(alpha: 0.6), width: 0.7),
  ),
);

class _Header extends StatelessWidget {
  const _Header({
    required this.kStart,
    required this.kEnd,
    required this.kTask,
    required this.kAction,
  });

  final Key kStart, kEnd, kTask, kAction;

  @override
  Widget build(BuildContext context) {
    final nb = context.nb;
    final style = TextStyle(fontSize: 18, color: nb.ink);

    Widget cell(
      Key key,
      String label, {
      double? width,
      bool divider = true,
      Alignment align = Alignment.center,
    }) {
      final c = Container(
        key: key,
        width: width,
        height: 44,
        alignment: align,
        padding: align == Alignment.centerLeft
            ? const EdgeInsets.only(left: 12)
            : null,
        decoration: divider ? _cellDivider(nb) : null,
        child: Text(label, style: style),
      );
      return width == null ? Expanded(child: c) : c;
    }

    // Double rule under the header, like a printed notebook.
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: nb.rule, width: 1.2)),
      ),
      padding: const EdgeInsets.only(bottom: 2.5),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: nb.rule, width: 1.2)),
        ),
        child: Row(
          children: [
            cell(kStart, 'Start', width: Cols.start),
            cell(kEnd, 'End', width: Cols.end),
            cell(kTask, 'Task', align: Alignment.centerLeft),
            cell(kAction, 'Done', width: Cols.action, divider: false),
          ],
        ),
      ),
    );
  }
}

class _RuledLine extends StatelessWidget {
  const _RuledLine();

  @override
  Widget build(BuildContext context) {
    final nb = context.nb;
    return Container(
      height: Cols.minRow,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: nb.rule, width: 0.7)),
      ),
      child: Row(
        children: [
          Container(width: Cols.start, decoration: _cellDivider(nb)),
          Container(width: Cols.end, decoration: _cellDivider(nb)),
          Expanded(child: Container(decoration: _cellDivider(nb))),
          const SizedBox(width: Cols.action),
        ],
      ),
    );
  }
}

class _DeleteBackground extends StatelessWidget {
  const _DeleteBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFD9534F),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Delete', style: TextStyle(color: Colors.white, fontSize: 18)),
          SizedBox(width: 6),
          Icon(Icons.delete_outline, color: Colors.white, size: 20),
        ],
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    required this.task,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onCheck,
    required this.onEditTime,
  });

  final TaskEntry task;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final ValueChanged<bool> onCheck;
  final ValueChanged<bool> onEditTime;

  @override
  Widget build(BuildContext context) {
    final nb = context.nb;
    final timeStyle = TextStyle(fontSize: 17, color: nb.ink);

    // Times fade/slide in as if just written down.
    // Written rows: tap a time to correct it.
    Widget timeCell(
      DateTime? t,
      double w, {
      required bool start,
    }) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: task.isBlank ? null : () => onEditTime(start),
      child: Semantics(
        button: !task.isBlank,
        label: start ? 'Start time' : 'End time',
        child: Container(
          width: w,
          decoration: _cellDivider(nb),
          padding: const EdgeInsets.only(top: 14),
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
                child: c,
              ),
            ),
            child: Text(formatTime(t), key: ValueKey(t), style: timeStyle),
          ),
        ),
      ),
    );

    final spent = formatDuration(task.start, task.end);

    return Container(
      constraints: const BoxConstraints(minHeight: Cols.minRow),
      decoration: BoxDecoration(
        color: nb.paper,
        border: Border(bottom: BorderSide(color: nb.rule, width: 0.7)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            timeCell(task.start, Cols.start, start: true),
            Stack(
              children: [
                timeCell(task.end, Cols.end, start: false),
                if (spent.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 34,
                    child: IgnorePointer(
                      child: Text(
                        spent,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, height: 1.0, color: nb.fadedInk),
                      ),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: Container(
                decoration: _cellDivider(nb),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  // onEditingComplete (instead of onSubmitted) stops Flutter
                  // from closing the keyboard, so focus can hop to the next line.
                  onEditingComplete: onSubmitted,
                  // Soft-wrap freely but keep Enter as a "submit" key.
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  maxLines: null,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                    fontFamily: kHandFont,
                    fontSize: 20,
                    height: 1.3,
                    color: task.done ? nb.fadedInk : nb.ink,
                    decoration: task.done ? TextDecoration.lineThrough : null,
                    decorationColor: nb.fadedInk,
                    decorationThickness: 1.5,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    hintText: task.isBlank ? 'What\'s next?' : null,
                    hintStyle: TextStyle(
                      fontFamily: kHandFont,
                      fontSize: 20,
                      color: nb.fadedInk.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: Cols.action,
              child: Align(
                alignment: Alignment.topCenter,
                child: _InkCheckbox(
                  value: task.done,
                  enabled: !task.isBlank,
                  onChanged: onCheck,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded, softly animated checkbox that looks inked onto the page.
class _InkCheckbox extends StatelessWidget {
  const _InkCheckbox({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final nb = context.nb;
    return Semantics(
      checked: value,
      enabled: enabled,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged(!value) : null,
        child: SizedBox(
          width: Cols.action,
          height: Cols.minRow,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: value ? nb.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: enabled
                      ? nb.rule
                      : nb.columnRule.withValues(alpha: 0.5),
                  width: 1.6,
                ),
              ),
              child: AnimatedScale(
                scale: value ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                child: Icon(Icons.check_rounded, size: 18, color: nb.paper),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
