// 一覧：締め期間ごとの記録とPDF出力
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../main.dart';
import '../pdf_report.dart';
import '../period.dart';
import 'home.dart';
import 'report.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  Period? _period;

  @override
  void initState() {
    super.initState();
    store.addListener(_changed);
  }

  @override
  void dispose() {
    store.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final type = store.settings.closing;
    var period = _period ?? Period.of(DateTime.now(), type);
    // 設定で締め日を変えたら、期間を合わせ直す
    if (Period.of(period.start, type) != period) period = Period.of(DateTime.now(), type);
    final trips = store.trips.where((t) => !t.isRecording && period.contains(t.start)).toList();
    final total = trips.fold<int>(0, (s, t) => s + t.totalFare);
    final missing = trips.where((t) => t.legs.isEmpty || t.totalFare == 0).length;

    // 日付ごとにまとめる
    final groups = <DateTime, List<dynamic>>{};
    for (final t in trips) {
      final d = DateTime(t.start.year, t.start.month, t.start.day);
      groups.putIfAbsent(d, () => []).add(t);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('一覧・PDF')),
      body: Column(children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Column(children: [
            Row(children: [
              IconButton(onPressed: () => setState(() => _period = period.previous(type)), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Column(children: [
                  Text(period.title, style: Theme.of(context).textTheme.titleLarge),
                  Text(period.label, style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              IconButton(onPressed: () => setState(() => _period = period.next(type)), icon: const Icon(Icons.chevron_right)),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                Text('${trips.length}件　合計 ', style: Theme.of(context).textTheme.titleMedium),
                Text(yen(total), style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReportScreen(period: period))),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF・印刷'),
                ),
              ]),
            ),
          ]),
        ),
        if (missing > 0)
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.errorContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('金額が未入力の記録が$missing件あります', style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
          ),
        Expanded(
          child: trips.isEmpty
              ? const Center(child: Text('この期間の記録はありません'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  children: [
                    for (final e in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                        child: Text(DateFormat('M月d日(E)').format(e.key), style: Theme.of(context).textTheme.titleSmall),
                      ),
                      for (final t in e.value) TripTile(trip: t),
                    ],
                  ],
                ),
        ),
      ]),
    );
  }
}
