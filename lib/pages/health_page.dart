import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  DateTime? _sleepStart;
  List<List<DateTime>> _sessions = [];

  @override
  void initState() {
    super.initState();
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
    final now = DateTime.now();
    final key = _windowKey(now);
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
    final now = DateTime.now();
    final key = _windowKey(now);
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

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final (wStart, wEnd) = _windowRange(now);
    final total = _totalSleepNow();
    String two(int v) => v.toString().padLeft(2, '0');
    final wLabel = '${wStart.month}/${two(wStart.day)} 22:00 - ${wEnd.month}/${two(wEnd.day)} 12:00';

    return Scaffold(
      appBar: AppBar(
        title: const Text('睡眠记录'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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


