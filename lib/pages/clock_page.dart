import 'dart:async';
import 'dart:ui' show FontFeature;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClockPage extends StatefulWidget {
  const ClockPage({super.key});

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  List<DateTime> _punches = [];
  DateTime _now = DateTime.now();
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _loadToday();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  Future<void> _loadToday() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(DateTime.now());
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

  Future<void> _saveToday() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _keyFor(DateTime.now());
    await prefs.setStringList(
      key,
      _punches.map((d) => d.toIso8601String()).toList(),
    );
  }

  String _keyFor(DateTime d) =>
      'punches_${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _punch() async {
    setState(() => _punches.add(DateTime.now()));
    await _saveToday();
  }

  Duration _calcWorkDuration(DateTime date, List<DateTime> punches) {
    if (punches.isEmpty) return Duration.zero;
    punches = List.of(punches)..sort();

    Duration total = Duration.zero;
    for (int i = 0; i < punches.length; i += 2) {
      final start = punches[i];
      final end = (i + 1 < punches.length) ? punches[i + 1] : DateTime.now();
      total += end.difference(start).isNegative ? Duration.zero : end.difference(start);
    }

    final isWeekend = date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    if (!isWeekend) {
      // 工作日扣除中午 12:00-13:30 的 1.5 小时（如有覆盖）
      final lunchStart = DateTime(date.year, date.month, date.day, 12, 0);
      final lunchEnd = DateTime(date.year, date.month, date.day, 13, 30);

      Duration overlap = Duration.zero;
      for (int i = 0; i < punches.length; i += 2) {
        final aStart = punches[i];
        final aEnd = (i + 1 < punches.length) ? punches[i + 1] : DateTime.now();
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
    final dur = _calcWorkDuration(now, _punches);
    String fmt(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      return '${h}h ${m}m';
    }

    String two(int v) => v.toString().padLeft(2, '0');
    final timeStr = '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
    final dateStr = '${now.year}-${two(now.month)}-${two(now.day)}';
    final nextIsClockIn = _punches.length % 2 == 0;

    return Scaffold(
      appBar: AppBar(title: const Text('上班打卡')),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Text(dateStr, style: Theme.of(context).textTheme.titleMedium),
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
          Text('今日工时 ${fmt(dur)}'),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: ButtonStyle(
                  padding: WidgetStateProperty.all(const EdgeInsets.symmetric(vertical: 16)),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    return nextIsClockIn ? Colors.green : Colors.orange;
                  }),
                  foregroundColor: WidgetStateProperty.all(Colors.white),
                ),
                onPressed: _punch,
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
                        await _saveToday();
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
                    final picked = await _pickTimeCupertino(context, now);
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
                        await _saveToday();
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
}


