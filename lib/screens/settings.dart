// 設定：PDFに載せる情報・締め日
import 'package:material_ui/material_ui.dart';

import '../main.dart';
import '../models.dart';
import '../period.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _name = TextEditingController(text: store.settings.name);
  late final TextEditingController _dept = TextEditingController(text: store.settings.department);
  late final TextEditingController _no = TextEditingController(text: store.settings.employeeNo);

  @override
  void dispose() {
    _name.dispose();
    _dept.dispose();
    _no.dispose();
    super.dispose();
  }

  Future<void> _save({ClosingType? closing, bool? recordRoute}) async {
    final s = store.settings;
    await store.saveSettings(Settings(
      name: _name.text.trim(),
      department: _dept.text.trim(),
      employeeNo: _no.text.trim(),
      closing: closing ?? s.closing,
      recordRoute: recordRoute ?? s.recordRoute,
    ));
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final s = store.settings;
    final now = DateTime.now();
    Widget field(TextEditingController c, String label, IconData icon) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: TextField(
            controller: c,
            onChanged: (_) => _save(),
            decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: const OutlineInputBorder()),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(children: [
        const _Header('PDFに載せる情報'),
        field(_name, '氏名', Icons.person_outline),
        field(_dept, '所属', Icons.apartment),
        field(_no, '社員番号（任意）', Icons.badge_outlined),
        const _Header('締め日'),
        RadioGroup<ClosingType>(
          groupValue: s.closing,
          onChanged: (v) => _save(closing: v),
          child: Column(children: [
            for (final c in ClosingType.values)
              RadioListTile<ClosingType>(
                value: c,
                title: Text(c.label),
                subtitle: Text('今の期間：${Period.of(now, c).label}'),
              ),
          ]),
        ),
        const _Header('記録'),
        SwitchListTile(
          title: const Text('移動ルートを記録する'),
          subtitle: const Text('オフにすると出発地と到着地だけを記録します（電池の節約）'),
          value: s.recordRoute,
          onChanged: (v) => _save(recordRoute: v),
        ),
        const _Header('このアプリについて'),
        const ListTile(
          title: Text('地図・駅のデータ'),
          subtitle: Text('© OpenStreetMap contributors、HeartRails Express'),
        ),
        const ListTile(
          title: Text('バス停のデータ'),
          subtitle: Text('「国土数値情報（バス停留所データ）」（国土交通省）を加工して作成（令和4年時点）'),
        ),
        const ListTile(
          title: Text('記録の保存場所'),
          subtitle: Text('記録はこの端末の中だけに保存されます。'),
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
      );
}
