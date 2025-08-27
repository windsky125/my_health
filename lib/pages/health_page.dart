import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  DateTime? _sleepStart;
  List<List<DateTime>> _sessions = [];
  DateTime _selectedBase = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedBase = _windowBaseDate(DateTime.now());
    _loadState();
  }

  String _windowKey(DateTime now) {
    final base = _windowBaseDate(now);
    return 'sleep_sessions_${base.year}-${base.month.toString().padLeft(2, '0')}-${base.day.toString().padLeft(2, '0')}';
  }

  // If now >= 22:00, base is today; else base is yesterday
  DateTime _windowBaseDate(DateTime now) {
    final today2200 = DateTime(now.year, now.month, now.day, 22, 0);
    return now.isAfter(today2200) || now.isAtSameMomentAs(today2200)
        ? DateTime(now.year, now.month, now.day)
        : DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
  }

  (DateTime, DateTime) _windowRange(DateTime now) {
    final base = _windowBaseDate(now);
    final start = DateTime(base.year, base.month, base.day, 22, 0);
    final end = DateTime(base.year, base.month, base.day + 1, 12, 0);
    return (start, end);
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _windowKey(DateTime.now());
    final raw = prefs.getStringList(key) ?? [];
    final startStr = prefs.getString('sleep_active_start');
    setState(() {
      _sessions = raw
          .map((e) => e.split('|'))
          .where((p) => p.length == 2)
          .map((p) => [DateTime.parse(p[0]), DateTime.parse(p[1])])
          .toList();
      _sleepStart = startStr != null ? DateTime.tryParse(startStr) : null;
    });
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _windowKey(_selectedBase);
    await prefs.setStringList(
      key,
      _sessions.map((p) => '${p[0].toIso8601String()}|${p[1].toIso8601String()}').toList(),
    );
  }

  Future<void> _saveActiveStart() async {
    final prefs = await SharedPreferences.getInstance();
    if (_sleepStart == null) {
      await prefs.remove('sleep_active_start');
    } else {
      await prefs.setString('sleep_active_start', _sleepStart!.toIso8601String());
    }
  }

  void _startSleep() async {
    // 仅允许对当前窗口计时
    setState(() => _sleepStart = DateTime.now());
    await _saveActiveStart();
  }

  void _wakeUp() async {
    if (_sleepStart == null) return;
    final now = DateTime.now();
    final (wStart, wEnd) = _windowRange(now);
    // Clamp into window
    DateTime s = _sleepStart!;
    DateTime e = now;
    if (e.isAfter(wEnd)) e = wEnd;
    if (s.isBefore(wStart)) s = wStart;
    if (e.isAfter(s)) {
      setState(() {
        _sessions.add([s, e]);
        _sleepStart = null;
      });
      await _saveSessions();
      await _saveActiveStart();
    } else {
      setState(() => _sleepStart = null);
      await _saveActiveStart();
    }
  }

  Duration _totalSleepNow() {
    final now = DateTime.now();
    final (wStart, wEnd) = _windowRange(now);
    Duration total = Duration.zero;
    for (final p in _sessions) {
      final s = p[0].isAfter(wStart) ? p[0] : wStart;
      final e = p[1].isBefore(wEnd) ? p[1] : wEnd;
      if (e.isAfter(s)) total += e.difference(s);
    }
    if (_sleepStart != null) {
      DateTime s = _sleepStart!;
      DateTime e = now.isBefore(wEnd) ? now : wEnd;
      if (s.isBefore(wStart)) s = wStart;
      if (e.isAfter(s)) total += e.difference(s);
    }
    return total;
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }

  Future<void> _openCalendar() async {
    // Build day durations for current month based on sleep sessions
    String two(int v) => v.toString().padLeft(2, '0');
    final firstDay = DateTime(_selectedBase.year, _selectedBase.month, 1);
    final nextMonth = DateTime(_selectedBase.year, _selectedBase.month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1));
    final dayCount = lastDay.day;
    final prefs = await SharedPreferences.getInstance();

    Map<DateTime, Duration> dayToDuration = {};
    Duration monthTotal = Duration.zero;
    for (int d = 1; d <= dayCount; d++) {
      final day = DateTime(_selectedBase.year, _selectedBase.month, d);
      final key = 'sleep_sessions_${day.year}-${two(day.month)}-${two(day.day)}';
      final raw = prefs.getStringList(key) ?? [];
      final sessions = raw
          .map((e) => e.split('|'))
          .where((p) => p.length == 2)
          .map((p) => [DateTime.parse(p[0]), DateTime.parse(p[1])])
          .toList();
      final wStart = DateTime(day.year, day.month, day.day, 22, 0);
      final wEnd = DateTime(day.year, day.month, day.day + 1, 12, 0);
      Duration total = Duration.zero;
      for (final p in sessions) {
        final s = p[0].isAfter(wStart) ? p[0] : wStart;
        final e = p[1].isBefore(wEnd) ? p[1] : wEnd;
        if (e.isAfter(s)) total += e.difference(s);
      }
      dayToDuration[DateTime(day.year, day.month, day.day)] = total;
      monthTotal += total;
    }

    await showDialog(
      context: context,
      builder: (context) {
        DateTime focused = _selectedBase;
        return AlertDialog(
          contentPadding: EdgeInsets.zero,
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // removed in-dialog icon per request
                    TableCalendar(
                      firstDay: DateTime(2020, 1, 1),
                      lastDay: DateTime(2100, 12, 31),
                      focusedDay: focused,
                      calendarFormat: CalendarFormat.month,
                      selectedDayPredicate: (day) => day.year == _selectedBase.year && day.month == _selectedBase.month && day.day == _selectedBase.day,
                      onDaySelected: (selectedDay, focusedDay) async {
                        setStateDialog(() => focused = focusedDay);
                        Navigator.pop(context);
                        setState(() => _selectedBase = DateTime(selectedDay.year, selectedDay.month, selectedDay.day));
                        await _loadState();
                      },
                      eventLoader: (day) {
                        final key = DateTime(day.year, day.month, day.day);
                        final dur = dayToDuration[key] ?? Duration.zero;
                        if (dur.inMinutes > 0) {
                          return ['${dur.inHours}'];
                        }
                        return const [];
                      },
                      headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
                      calendarBuilders: CalendarBuilders(
                        dowBuilder: (context, day) {
                          final text = ['日','一','二','三','四','五','六'][day.weekday % 7];
                          final isSunday = day.weekday == DateTime.sunday;
                          return Center(
                            child: Text(
                              text,
                              style: TextStyle(
                                color: isSunday ? Colors.red : null,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                        markerBuilder: (context, date, events) {
                          if (events.isEmpty) return null;
                          final label = events.first.toString();
                          return Positioned(
                            bottom: 4,
                            right: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Text('本月总睡眠: '),
                          Text(_fmt(monthTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final (wStart, wEnd) = _windowRange(DateTime(_selectedBase.year, _selectedBase.month, _selectedBase.day, now.hour, now.minute));
    final total = _totalSleepNow();
    String two(int v) => v.toString().padLeft(2, '0');
    final wLabel = '${wStart.month}/${two(wStart.day)} 22:00 - ${wEnd.month}/${two(wEnd.day)} 12:00';

    return Scaffold(
      appBar: AppBar(
        title: const Text('睡眠记录'),
        actions: [
          IconButton(
            tooltip: '打开日历',
            icon: const Icon(Icons.calendar_month),
            onPressed: _openCalendar,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: '前一天',
                  onPressed: () async {
                    setState(() => _selectedBase = _selectedBase.subtract(const Duration(days: 1)));
                    await _loadState();
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      await _openCalendar();
                    },
                    child: Center(
                      child: Text('${_selectedBase.year}-${two(_selectedBase.month)}-${two(_selectedBase.day)} (${wLabel})'),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '后一天',
                  onPressed: () async {
                    setState(() => _selectedBase = _selectedBase.add(const Duration(days: 1)));
                    await _loadState();
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            Text('统计窗口: $wLabel'),
            const SizedBox(height: 8),
            Text('当前累计睡眠: ${_fmt(total)}', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _sleepStart == null ? _startSleep : _wakeUp,
                child: Text(_sleepStart == null ? '开始睡觉' : '我醒了'),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text('本窗口内片段', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                itemCount: _sessions.length + (_sleepStart != null ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (_sleepStart != null && i == _sessions.length) {
                    final s = _sleepStart!.isAfter(wStart) ? _sleepStart! : wStart;
                    final e = now.isBefore(wEnd) ? now : wEnd;
                    final d = e.isAfter(s) ? e.difference(s) : Duration.zero;
                    return ListTile(
                      leading: const Icon(Icons.nightlight_round),
                      title: const Text('进行中'),
                      subtitle: Text('${two(s.hour)}:${two(s.minute)} - ${two(e.hour)}:${two(e.minute)}  (+${_fmt(d)})'),
                    );
                  }
                  final p = _sessions[i];
                  final s = p[0];
                  final e = p[1];
                  final d = e.difference(s);
                  return ListTile(
                    leading: const Icon(Icons.bedtime),
                    title: Text('${two(s.hour)}:${two(s.minute)} - ${two(e.hour)}:${two(e.minute)}'),
                    subtitle: Text('时长 ${_fmt(d)}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('确认删除'),
                            content: Text('是否删除该睡眠片段（${two(s.hour)}:${two(s.minute)} - ${two(e.hour)}:${two(e.minute)}）？'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          setState(() {
                            _sessions.removeAt(i);
                          });
                          await _saveSessions();
                        }
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}


