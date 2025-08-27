import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

class ClockPage extends StatefulWidget {
  const ClockPage({super.key});

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  List<DateTime> _punches = [];
  DateTime _now = DateTime.now();
  Timer? _ticker;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(_now.year, _now.month, _now.day);
    _loadFor(_selectedDate);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  Future<void> _loadFor(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(day);
    final list = prefs.getStringList(key) ?? [];
    setState(() {
      _punches = list.map((s) => DateTime.parse(s)).toList()..sort();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _saveFor(DateTime day) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(day);
    await prefs.setStringList(
      key,
      _punches.map((d) => d.toIso8601String()).toList(),
    );
  }

  String _keyFor(DateTime d) =>
      'punches_${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _punch() async {
    if (!_isTodaySelected) return;
    setState(() => _punches.add(DateTime.now()));
    await _saveFor(_selectedDate);
  }

  Duration _calcWorkDuration(DateTime date, List<DateTime> punches, {required bool isToday}) {
    if (punches.isEmpty) return Duration.zero;
    punches = List.of(punches)..sort();

    Duration total = Duration.zero;
    for (int i = 0; i < punches.length; i += 2) {
      final start = punches[i];
      if (i + 1 < punches.length) {
        final end = punches[i + 1];
        total += end.difference(start).isNegative ? Duration.zero : end.difference(start);
      } else if (isToday) {
        final end = DateTime.now();
        total += end.difference(start).isNegative ? Duration.zero : end.difference(start);
      } else {
        // 非当天且为奇数条，忽略未闭合区间
      }
    }

    final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    if (!isWeekend) {
      // 工作日扣除中午 12:00-13:30 的 1.5 小时（如有覆盖）
      final lunchStart = DateTime(date.year, date.month, date.day, 12, 0);
      final lunchEnd = DateTime(date.year, date.month, date.day, 13, 30);

      Duration overlap = Duration.zero;
      for (int i = 0; i < punches.length; i += 2) {
        final aStart = punches[i];
        DateTime? aEnd;
        if (i + 1 < punches.length) {
          aEnd = punches[i + 1];
        } else if (isToday) {
          aEnd = DateTime.now();
        } else {
          aEnd = null; // 非当天且未闭合，不计午休重叠
        }
        if (aEnd == null) continue;
        final s = aStart.isAfter(lunchStart) ? aStart : lunchStart;
        final e = aEnd.isBefore(lunchEnd) ? aEnd : lunchEnd;
        if (e.isAfter(s)) {
          overlap += e.difference(s);
        }
      }

      // 只扣除与午休区间的重叠时长（最多 1.5h）
      final maxLunch = const Duration(hours: 1, minutes: 30);
      total -= overlap > maxLunch ? maxLunch : overlap;
      if (total.isNegative) total = Duration.zero;
    }

    return total;
  }

  @override
  Widget build(BuildContext context) {
    final now = _now;
    final dur = _calcWorkDuration(_selectedDate, _punches, isToday: _isTodaySelected);
    String fmt(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      return '${h}h ${m}m';
    }

    String two(int v) => v.toString().padLeft(2, '0');
    final timeStr = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    final dateStr = '${_selectedDate.year}-${two(_selectedDate.month)}-${two(_selectedDate.day)}';
    final nextIsClockIn = _punches.length % 2 == 0;
    final canOperate = _isTodaySelected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('上班打卡'),
        actions: [
          IconButton(
            tooltip: '打开日历',
            icon: const Icon(Icons.calendar_month),
            onPressed: _openCalendar,
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                IconButton(
                  tooltip: '前一天',
                  onPressed: () async {
                    setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
                    await _loadFor(_selectedDate);
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      await _openCalendar();
                    },
                    child: Center(
                      child: Text(dateStr, style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '后一天',
                  onPressed: () async {
                    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
                    await _loadFor(_selectedDate);
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            timeStr,
            style: const TextStyle(
              fontSize: 64,
              letterSpacing: 2,
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Builder(builder: (context){
            final ot = _calcOvertime(dur, _selectedDate);
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('今日工时 ${fmt(dur)}'),
                const SizedBox(width: 12),
                Text('加班 ${_fmtHoursHalf(ot)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            );
          }),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 16)),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    final base = nextIsClockIn ? Colors.green : Colors.orange;
                    return canOperate ? base : base.withOpacity(0.4);
                  }),
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                ),
                onPressed: canOperate ? _punch : null,
                icon: Icon(nextIsClockIn ? Icons.login : Icons.logout),
                label: Text(nextIsClockIn ? '上班打卡' : '下班打卡'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _punches.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final t = _punches[i];
                final label = (i % 2 == 0) ? '上班' : '下班';
                final hh = two(t.hour);
                final mm = two(t.minute);
                final ss = two(t.second);
                return ListTile(
                  dense: true,
                  leading: Icon(i % 2 == 0 ? Icons.login : Icons.logout),
                  title: Text('$label  $hh:$mm:$ss'),
                  subtitle: Text('${t.year}-${two(t.month)}-${two(t.day)} ${hh}:${mm}:${ss}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('确认删除'),
                          content: Text('是否删除该${label}记录 $hh:$mm:$ss ?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
                          ],
                        ),
                      );
                      if (ok == true) {
                        setState(() => _punches.removeAt(i));
                        await _saveFor(_selectedDate);
                      }
                    },
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                const Spacer(),
                FloatingActionButton(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await _pickTimeCupertino(context, DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, now.hour, now.minute));
                    if (picked != null) {
                      final isClockIn = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('添加记录'),
                          content: const Text('选择类型：'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('上班')),
                            FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('下班')),
                          ],
                        ),
                      );
                      if (isClockIn != null) {
                        setState(() {
                          // 按选择类型插入到合适位置：上班视为偶数位， 下班视为奇数位
                          _punches.add(picked);
                          _punches.sort();
                        });
                        await _saveFor(_selectedDate);
                      }
                    }
                  },
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<DateTime?> _pickTimeCupertino(BuildContext context, DateTime baseDay) async {
    DateTime temp = baseDay;
    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (context) {
        String two(int v) => v.toString().padLeft(2, '0');
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final label = '${two(temp.hour)}:${two(temp.minute)}';
            return SafeArea(
              top: false,
              child: Container(
                color: CupertinoColors.systemBackground,
                height: 360,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                label,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop<DateTime>(context, temp),
                            child: const Text('确定'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: CupertinoTheme(
                        data: const CupertinoThemeData(
                          brightness: Brightness.light,
                          textTheme: CupertinoTextThemeData(
                            pickerTextStyle: TextStyle(fontSize: 20, color: CupertinoColors.label),
                          ),
                        ),
                        child: CupertinoDatePicker(
                          mode: CupertinoDatePickerMode.time,
                          initialDateTime: baseDay,
                          use24hFormat: true,
                          minuteInterval: 1,
                          backgroundColor: CupertinoColors.systemBackground,
                          onDateTimeChanged: (d) {
                            temp = DateTime(baseDay.year, baseDay.month, baseDay.day, d.hour, d.minute);
                            setSheetState(() {});
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  bool get _isTodaySelected {
    final t = DateTime.now();
    return _selectedDate.year == t.year && _selectedDate.month == t.month && _selectedDate.day == t.day;
  }

  Future<void> _openCalendar() async {
    // Build a map of daily durations for the current focused month
    final firstDay = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final nextMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1));
    final dayCount = lastDay.day;
    final prefs = await SharedPreferences.getInstance();
    Map<DateTime, Duration> dayToDuration = {};
    for (int d = 1; d <= dayCount; d++) {
      final day = DateTime(_selectedDate.year, _selectedDate.month, d);
      final key = _keyFor(day);
      final list = prefs.getStringList(key) ?? [];
      final punches = list.map((s) => DateTime.parse(s)).toList()..sort();
      final dur = _calcWorkDuration(day, punches, isToday: _isSameDay(day, DateTime.now()));
      dayToDuration[DateTime(day.year, day.month, day.day)] = dur;
    }

    Duration monthTotal = dayToDuration.values.fold(Duration.zero, (a, b) => a + b);
    Duration monthOvertime = dayToDuration.entries.fold(Duration.zero, (a, e) => a + _calcOvertime(e.value, e.key));

    await showDialog(
      context: context,
      builder: (context) {
        DateTime focused = _selectedDate;
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
                      selectedDayPredicate: (day) => _isSameDay(day, _selectedDate),
                      onDaySelected: (selectedDay, focusedDay) async {
                        setStateDialog(() => focused = focusedDay);
                        Navigator.pop(context);
                        setState(() => _selectedDate = DateTime(selectedDay.year, selectedDay.month, selectedDay.day));
                        await _loadFor(_selectedDate);
                      },
                      eventLoader: (day) {
                        final key = DateTime(day.year, day.month, day.day);
                        final dur = dayToDuration[key] ?? Duration.zero;
                        if (dur.inMinutes > 0) {
                          // Return a numeric string tag to render later
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [const Text('本月总工时: '), Text(_fmt(monthTotal), style: const TextStyle(fontWeight: FontWeight.w600))]),
                              const SizedBox(height: 4),
                              Row(children: [const Text('本月加班:   '), Text(_fmtHoursHalf(monthOvertime), style: const TextStyle(fontWeight: FontWeight.w600))]),
                            ],
                          ),
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

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m}m';
  }

  String _fmtHoursHalf(Duration d) {
    // Represent in hours with .5 steps
    final halfSteps = d.inMinutes ~/ 30; // floor to 0.5h
    final hoursHalf = halfSteps / 2.0;
    if (hoursHalf == hoursHalf.roundToDouble()) {
      return '${hoursHalf.toInt()}h';
    }
    return '${hoursHalf}h';
  }

  Duration _calcOvertime(Duration worked, DateTime date) {
    final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    if (isWeekend) {
      if (worked <= const Duration(hours: 1)) return Duration.zero;
      // Round down to nearest 0.5h
      final halfHours = worked.inMinutes ~/ 30;
      return Duration(minutes: halfHours * 30);
    } else {
      // Weekday: threshold 8h, must be at least +1h to count, then +0.5h steps
      if (worked <= const Duration(hours: 8)) return Duration.zero;
      final extra = worked - const Duration(hours: 8);
      if (extra < const Duration(hours: 1)) return Duration.zero;
      final remaining = extra - const Duration(hours: 1);
      final steps = remaining.inMinutes ~/ 30;
      return const Duration(hours: 1) + Duration(minutes: steps * 30);
    }
  }
}


