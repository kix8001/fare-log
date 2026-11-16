// 記録画面：スタート／移動完了
import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../main.dart';
import '../models.dart';
import '../pdf_report.dart';
import '../period.dart';
import '../tracker.dart';
import 'ic_import.dart';
import 'route_map.dart';
import 'trip_edit.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (store.current != null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    _tick?.cancel();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final err = await Tracker.ensurePermission();
      if (err != null) {
        _snack(err);
        return;
      }
      await tracker.start();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish(Trip t) async {
    setState(() => _busy = true);
    try {
      await tracker.finish(t);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripEditScreen(trip: t, isNew: true)));
  }

  Future<void> _cancel(Trip t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('記録を取り消しますか？'),
        content: const Text('この移動の記録を削除します。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('続ける')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('取り消す')),
        ],
      ),
    );
    if (ok != true) return;
    tracker.stopRoute();
    await store.delete(t);
  }

  Future<void> _addManual() async {
    final now = DateTime.now();
    final t = Trip(id: 'm${now.microsecondsSinceEpoch}', start: now, end: now);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripEditScreen(trip: t, isNew: true)));
  }

  @override
  Widget build(BuildContext context) {
    final cur = store.current;
    return Scaffold(
      appBar: AppBar(title: const Text('運賃記録')),
      body: SafeArea(
        child: cur == null ? _idle(context) : _recording(context, cur),
      ),
    );
  }

  Widget _idle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final period = Period.of(DateTime.now(), store.settings.closing);
    final inPeriod = store.trips.where((t) => !t.isRecording && period.contains(t.start)).toList();
    final total = inPeriod.fold<int>(0, (s, t) => s + t.totalFare);
    final today = DateTime.now();
    final todays = store.trips
        .where((t) => t.start.year == today.year && t.start.month == today.month && t.start.day == today.day)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            title: Text('${period.title}（${period.label}）'),
            subtitle: Text('${inPeriod.length}件'),
            trailing: Text(yen(total), style: Theme.of(context).textTheme.headlineSmall),
          ),
        ),
        const SizedBox(height: 32),
        Center(
          child: SizedBox(
            width: 200,
            height: 200,
            child: FilledButton(
              style: FilledButton.styleFrom(shape: const CircleBorder(), elevation: 4),
              onPressed: _busy ? null : _start,
              child: _busy
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, size: 72),
                        Text('スタート', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text('出発するときに押すと、現在地とルートを記録します',
            textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 28),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const IcImportScreen())),
              icon: const Icon(Icons.contactless),
              label: const Text('ICカード取り込み'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _addManual,
              icon: const Icon(Icons.edit_note),
              label: const Text('手動で追加'),
            ),
          ),
        ]),
        if (todays.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('今日の記録', style: Theme.of(context).textTheme.titleMedium),
          for (final t in todays) TripTile(trip: t),
        ],
      ],
    );
  }

  Widget _recording(BuildContext context, Trip t) {
    final scheme = Theme.of(context).colorScheme;
    final el = DateTime.now().difference(t.start);
    String two(int v) => v.toString().padLeft(2, '0');
    final elapsed = '${el.inHours}:${two(el.inMinutes % 60)}:${two(el.inSeconds % 60)}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Icon(Icons.fiber_manual_record, color: scheme.error, size: 16),
          const SizedBox(width: 6),
          Text('記録中', style: TextStyle(color: scheme.error, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(elapsed, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
        const SizedBox(height: 8),
        Text('出発 ${DateFormat('H:mm').format(t.start)}　${t.startPlace.lat == null ? (el.inSeconds < 60 ? '（現在地を取得中…）' : '（現在地を取得できません。屋外や窓の近くで改善します）') : (t.startPlace.name.isEmpty ? '（住所を取得中…）' : t.startPlace.name)}'),
        const SizedBox(height: 12),
        RouteMap(trip: t, height: 300, follow: true),
        const SizedBox(height: 4),
        Text(store.settings.recordRoute ? '記録した地点：${t.route.length}　経過時間に関係なく「移動完了」を押せます' : 'ルート記録はオフです（設定で変更できます）',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 24),
        SizedBox(
          height: 72,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: _busy ? null : () => _finish(t),
            icon: _busy
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                : const Icon(Icons.flag, size: 32),
            label: const Text('移動完了', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: _busy ? null : () => _cancel(t), child: const Text('この記録を取り消す')),
      ],
    );
  }
}

/// 一覧の1行
class TripTile extends StatelessWidget {
  const TripTile({super.key, required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final time = t.noTime ? '' : DateFormat('H:mm').format(t.start);
    final icon = switch (t.legs.isEmpty ? null : t.legs.first.mode) {
      TransportMode.train => Icons.train,
      TransportMode.bus => Icons.directions_bus,
      TransportMode.taxi => Icons.local_taxi,
      _ => Icons.place,
    };
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(icon),
        title: Text(t.destination.isNotEmpty ? t.destination : t.sectionLabel, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [time, if (t.destination.isNotEmpty) t.sectionLabel, t.modesLabel].where((s) => s.isNotEmpty).join('　'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: t.isRecording
            ? const Text('記録中')
            : Text(t.legs.isEmpty ? '未入力' : yen(t.totalFare),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: t.legs.isEmpty ? Theme.of(context).colorScheme.error : null,
                )),
        onTap: t.isRecording
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripEditScreen(trip: t))),
      ),
    );
  }
}
