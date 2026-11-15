// ICカードの利用履歴の読み取りと取り込み
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../felica.dart';
import '../main.dart';
import '../models.dart';
import '../pdf_report.dart';
import '../store.dart';

/// 直前に読んだ結果（同じ画面を開き直したときに、かざし直さなくて済むように）
IcCardResult? _lastRead;

/// カードをかざすよう案内し、読み取った結果を返す部品
class IcReadPanel extends StatefulWidget {
  const IcReadPanel({super.key, required this.builder});

  final Widget Function(BuildContext context, IcCardResult result, VoidCallback reread) builder;

  @override
  State<IcReadPanel> createState() => _IcReadPanelState();
}

class _IcReadPanelState extends State<IcReadPanel> {
  IcCardResult? _result = _lastRead;
  String? _error;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    if (_result == null) _read();
  }

  @override
  void dispose() {
    if (_reading) FeliCaReader.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      if (!await FeliCaReader.available()) {
        throw Exception('この端末ではNFCが使えないか、オフになっています');
      }
      final r = await FeliCaReader.read();
      _lastRead = r;
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    if (r != null && !_reading) return widget.builder(context, r, _read);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.contactless, size: 96, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          _reading
              ? (Platform.isIOS ? '画面の案内に従って、ICカードをiPhoneの上部に当ててください' : 'ICカードをスマホの背面に当ててください')
              : (_error ?? ''),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text('Suica・PASMO・ICOCA などの交通系ICカードに対応\n（カードに残っている直近20件まで）',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
        const SizedBox(height: 16),
        if (_reading && Platform.isAndroid) const CircularProgressIndicator(),
        if (!_reading) FilledButton.icon(onPressed: _read, icon: const Icon(Icons.refresh), label: const Text('もう一度読む')),
      ]),
    );
  }
}

String _icTitle(IcHistory h) => '${DateFormat('M/d(E)').format(h.date)}　${h.kind.label}';

Widget _icIcon(IcHistory h) => Icon(switch (h.kind) {
      IcKind.train => Icons.train,
      IcKind.bus => Icons.directions_bus,
      IcKind.charge => Icons.savings_outlined,
      IcKind.shopping => Icons.shopping_bag_outlined,
      IcKind.other => Icons.help_outline,
    });

/// 区間の運賃をICの履歴から選ぶシート
class IcPickSheet extends StatelessWidget {
  const IcPickSheet({super.key, required this.date, required this.mode});

  final DateTime date;
  final TransportMode mode;

  @override
  Widget build(BuildContext context) {
    final imported = store.importedIcKeys;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: IcReadPanel(builder: (context, r, reread) {
          bool sameDay(DateTime d) => d.year == date.year && d.month == date.month && d.day == date.day;
          final list = r.history.where((h) => h.isFare).toList()
            ..sort((a, b) => (sameDay(b.date) ? 1 : 0) - (sameDay(a.date) ? 1 : 0));
          return ListView(shrinkWrap: true, children: [
            ListTile(
              title: const Text('使った履歴を選んでください'),
              subtitle: Text('${DateFormat('M月d日').format(date)}の分を上に表示しています'),
              trailing: IconButton(onPressed: reread, icon: const Icon(Icons.refresh), tooltip: '読み直す'),
            ),
            if (list.isEmpty) const ListTile(title: Text('電車・バスの履歴がありません')),
            for (final h in list)
              ListTile(
                leading: _icIcon(h),
                title: Text(_icTitle(h)),
                subtitle: Text([
                  if (sameDay(h.date)) '同じ日',
                  if (imported.contains(h.key)) '取り込み済み',
                  '残額 ${yen(h.balance)}',
                ].join('・')),
                trailing: Text(h.amount == null ? '不明' : yen(h.amount!), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                enabled: h.amount != null,
                onTap: () => Navigator.pop(context, h),
              ),
          ]);
        }),
      ),
    );
  }
}

/// ホームの「ICカード取り込み」：履歴をまとめて記録にする
class IcImportScreen extends StatefulWidget {
  const IcImportScreen({super.key});

  @override
  State<IcImportScreen> createState() => _IcImportScreenState();
}

class _IcImportScreenState extends State<IcImportScreen> {
  final Set<String> _selected = {};
  String? _initFor;

  Future<void> _import(List<IcHistory> list) async {
    var attached = 0;
    var created = 0;
    for (final h in list.where((h) => _selected.contains(h.key))) {
      final mode = h.kind.mode ?? TransportMode.other;
      // 同じ日の記録に、運賃が未入力の同じ交通機関の区間があれば、そこに入れる
      Leg? target;
      Trip? owner;
      for (final t in store.trips) {
        if (t.isRecording) continue;
        if (t.start.year != h.date.year || t.start.month != h.date.month || t.start.day != h.date.day) continue;
        for (final l in t.legs) {
          if (l.mode == mode && l.fare == 0 && l.icKey == null) {
            target = l;
            owner = t;
            break;
          }
        }
        if (target != null) break;
      }
      if (target != null && owner != null) {
        target
          ..fare = h.amount ?? 0
          ..source = FareSource.ic
          ..icKey = h.key;
        await store.upsert(owner);
        attached++;
      } else {
        final t = Trip(
          id: Store.newId(),
          start: h.date,
          end: h.date,
          noTime: true,
          legs: [Leg(mode: mode, fare: h.amount ?? 0, source: FareSource.ic, icKey: h.key)],
        );
        await store.upsert(t);
        created++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text([
        if (attached > 0) '$attached件を既存の記録に入れました',
        if (created > 0) '$created件を新しい記録にしました（一覧で区間や用務先を入力できます）',
      ].join('\n')),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ICカード取り込み')),
      body: IcReadPanel(builder: (context, r, reread) {
        final imported = store.importedIcKeys;
        final list = r.history.where((h) => h.isFare && h.amount != null).toList();
        if (_initFor != r.idm) {
          _initFor = r.idm;
          _selected
            ..clear()
            ..addAll(list.where((h) => !imported.contains(h.key)).map((h) => h.key));
        }
        return Column(children: [
          ListTile(
            title: Text('残額 ${yen(r.history.isEmpty ? 0 : r.history.first.balance)}'),
            subtitle: const Text('取り込む履歴にチェックを入れてください'),
            trailing: TextButton.icon(onPressed: reread, icon: const Icon(Icons.refresh), label: const Text('読み直す')),
          ),
          const Divider(height: 1),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('電車・バスの履歴がありません'))
                : ListView(children: [
                    for (final h in list)
                      CheckboxListTile(
                        value: _selected.contains(h.key),
                        onChanged: (v) => setState(() => v == true ? _selected.add(h.key) : _selected.remove(h.key)),
                        secondary: _icIcon(h),
                        title: Text('${_icTitle(h)}　${yen(h.amount!)}'),
                        subtitle: imported.contains(h.key) ? const Text('取り込み済み') : null,
                        controlAffinity: ListTileControlAffinity.trailing,
                        isThreeLine: false,
                      ),
                    for (final h in r.history.where((h) => !h.isFare))
                      ListTile(
                        enabled: false,
                        leading: _icIcon(h),
                        title: Text(_icTitle(h)),
                        trailing: Text(h.amount == null ? '' : yen(h.amount!)),
                      ),
                  ]),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty ? null : () => _import(list),
                  child: Text('${_selected.length}件を記録に取り込む'),
                ),
              ),
            ),
          ),
        ]);
      }),
    );
  }
}
