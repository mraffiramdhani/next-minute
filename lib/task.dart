/// One line in the notebook.
class TaskEntry {
  TaskEntry({required this.id, this.text = '', this.start, this.end});

  final String id;
  String text;
  DateTime? start;
  DateTime? end;

  bool get done => end != null;
  bool get isBlank => text.trim().isEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'start': start?.toIso8601String(),
    'end': end?.toIso8601String(),
  };

  factory TaskEntry.fromJson(Map<String, dynamic> json) => TaskEntry(
    id: json['id'] as String,
    text: (json['text'] as String?) ?? '',
    start: json['start'] == null ? null : DateTime.parse(json['start']),
    end: json['end'] == null ? null : DateTime.parse(json['end']),
  );
}

String formatTime(DateTime? t) {
  if (t == null) return '';
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

String _fmtMins(int mins) {
  if (mins < 60) return '${mins}m';
  final h = mins ~/ 60, m = mins % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

int? _minutes(DateTime? start, DateTime? end) {
  if (start == null || end == null) return null;
  // Compare whole minutes, matching what the HH:mm cells show.
  DateTime trim(DateTime d) => DateTime(d.year, d.month, d.day, d.hour, d.minute);
  final mins = trim(end).difference(trim(start)).inMinutes;
  return mins < 0 ? null : mins;
}

/// Time spent between [start] and [end]: "<1m", "25m", "1h 5m".
/// Empty when either is missing or the end is before the start.
String formatDuration(DateTime? start, DateTime? end) {
  final mins = _minutes(start, end);
  if (mins == null) return '';
  return mins < 1 ? '<1m' : _fmtMins(mins);
}

/// Total time on finished tasks, same format; empty when there is none.
String formatTotal(Iterable<TaskEntry> tasks) {
  var total = 0;
  for (final t in tasks) {
    total += _minutes(t.start, t.end) ?? 0;
  }
  return total == 0 ? '' : _fmtMins(total);
}
