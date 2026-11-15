// 移動の編集：交通手段・区間・運賃・用務先
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../felica.dart';
import '../main.dart';
import '../models.dart';
import '../pdf_report.dart';
import '../places.dart';
import 'ic_import.dart';
import 'route_map.dart';
import '../tracker.dart';

class TripEditScreen extends StatefulWidget {
  const TripEditScreen({super.key, required this.trip, this.isNew = false});

  final Trip trip;
  final bool isNew;

  @override
  State<TripEditScreen> createState() => _TripEditScreenState();
}

class _TripEditScreenState extends State<TripEditScreen> {
  late Trip t;
  late final TextEditingController _dest;
  late final TextEditingController _purpose;
  late final TextEditingController _memo;
  late final TextEditingController _from;
  late final TextEditingController _to;
  final List<_LegForm> _legs = [];

  @override
  void initState() {
    super.initState();
    // 編集はコピーに対して行い、保存時に反映する
    t = Trip.fromJson(widget.trip.toJson());
    _dest = TextEditingController(text: t.destination);
    _purpose = TextEditingController(text: t.purpose);
    _memo = TextEditingController(text: t.memo);
    _from = TextEditingController(text: t.startPlace.name);
    _to = TextEditingController(text: t.endPlace.name);
    for (final l in t.legs) {
      _legs.add(_LegForm(l));
    }
    if (_legs.isEmpty) _legs.add(_LegForm(Leg(mode: TransportMode.train)));
  }

  @override
  void dispose() {
    for (final c in [_dest, _purpose, _memo, _from, _to]) {
      c.dispose();
    }
    for (final l in _legs) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    t.destination = _dest.text.trim();
    t.purpose = _purpose.text.trim();
    t.memo = _memo.text.trim();
    t.startPlace.name = _from.text.trim();
    t.endPlace.name = _to.text.trim();
    t.legs = _legs.map((f) => f.toLeg()).toList();
    await store.upsert(t);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('この記録を削除しますか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    await store.delete(widget.trip);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: t.start,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null) return;
    setState(() {
      final dur = t.end?.difference(t.start);
      t.start = DateTime(d.year, d.month, d.day, t.start.hour, t.start.minute);
      if (dur != null) t.end = t.start.add(dur);
    });
  }

  Future<void> _pickTime(bool isStart) async {
    final base = isStart ? t.start : (t.end ?? t.start);
    final tm = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (tm == null) return;
    setState(() {
      final v = DateTime(t.start.year, t.start.month, t.start.day, tm.hour, tm.minute);
      if (isStart) {
        t.start = v;
      } else {
        t.end = v;
      }
      t.noTime = false;
    });
  }

  /// 過去に入力した値（入力候補）
  List<String> _history(String Function(Trip) f) {
    final seen = <String>{};
    for (final x in store.trips) {
      final v = f(x);
      if (v.isNotEmpty) seen.add(v);
    }
    return seen.toList();
  }

  @override
  Widget build(BuildContext context) {
    final dateF = DateFormat('yyyy年M月d日(E)');
    final timeF = DateFormat('H:mm');
    final total = _legs.fold<int>(0, (s, l) => s + l.fare);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? '移動の内容' : '記録の編集'),
        actions: [
          if (!widget.isNew || store.trips.any((x) => x.id == t.id))
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline), tooltip: '削除'),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            Text('合計 ${yen(total)}', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            FilledButton.icon(onPressed: _save, icon: const Icon(Icons.check), label: const Text('保存')),
          ]),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (t.route.isNotEmpty || t.startPlace.lat != null) ...[
            RouteMap(trip: t),
            const SizedBox(height: 12),
          ],
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ActionChip(avatar: const Icon(Icons.event, size: 18), label: Text(dateF.format(t.start)), onPressed: _pickDate),
            ActionChip(
              avatar: const Icon(Icons.schedule, size: 18),
              label: Text(t.noTime ? '出発 --:--' : '出発 ${timeF.format(t.start)}'),
              onPressed: () => _pickTime(true),
            ),
            ActionChip(
              label: Text(t.noTime || t.end == null ? '到着 --:--' : '到着 ${timeF.format(t.end!)}'),
              onPressed: () => _pickTime(false),
            ),
          ]),
          const SizedBox(height: 16),
          _AutoField(controller: _dest, label: '用務先（訪問先）', icon: Icons.business, options: _history((x) => x.destination)),
          const SizedBox(height: 12),
          _AutoField(controller: _purpose, label: '目的', icon: Icons.work_outline, options: _history((x) => x.purpose)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _from,
                decoration: const InputDecoration(labelText: '出発地', border: OutlineInputBorder(), isDense: true),
              ),
            ),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.arrow_forward)),
            Expanded(
              child: TextField(
                controller: _to,
                decoration: const InputDecoration(labelText: '到着地', border: OutlineInputBorder(), isDense: true),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          Text('利用した交通機関', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var i = 0; i < _legs.length; i++)
            _LegCard(
              key: ObjectKey(_legs[i]),
              form: _legs[i],
              trip: t,
              index: i,
              onChanged: () => setState(() {}),
              onRemove: _legs.length <= 1
                  ? null
                  : () => setState(() {
                        _legs.removeAt(i).dispose();
                      }),
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              final prev = _legs.isEmpty ? null : _legs.last;
              _legs.add(_LegForm(Leg(mode: prev?.mode ?? TransportMode.train, from: prev?.to.text ?? '')));
            }),
            icon: const Icon(Icons.add),
            label: const Text('乗り継ぎを追加'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _memo,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'メモ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// 入力候補つきのテキスト欄
class _AutoField extends StatefulWidget {
  const _AutoField({required this.controller, required this.label, required this.icon, required this.options});

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final List<String> options;

  @override
  State<_AutoField> createState() => _AutoFieldState();
}

class _AutoFieldState extends State<_AutoField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focus,
      optionsBuilder: (v) {
        final q = v.text.trim();
        if (q.isEmpty) return const [];
        return widget.options.where((o) => o.contains(q) && o != q).take(6);
      },
      fieldViewBuilder: (context, c, focus, onSubmit) => TextField(
        controller: c,
        focusNode: focus,
        decoration: InputDecoration(
          labelText: widget.label,
          prefixIcon: Icon(widget.icon),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
      optionsViewBuilder: (context, onSelected, opts) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [for (final o in opts) ListTile(dense: true, title: Text(o), onTap: () => onSelected(o))],
            ),
          ),
        ),
      ),
    );
  }
}

/// 区間1つ分の入力状態
class _LegForm {
  _LegForm(Leg l)
      : mode = l.mode,
        source = l.source,
        receiptPath = l.receiptPath,
        icKey = l.icKey,
        from = TextEditingController(text: l.from),
        to = TextEditingController(text: l.to),
        fareText = TextEditingController(text: l.fare == 0 ? '' : '${l.fare}');

  TransportMode mode;
  FareSource source;
  String? receiptPath;
  String? icKey;
  final TextEditingController from;
  final TextEditingController to;
  final TextEditingController fareText;

  int get fare => int.tryParse(fareText.text.replaceAll(',', '')) ?? 0;

  Leg toLeg() => Leg(
        mode: mode,
        from: from.text.trim(),
        to: to.text.trim(),
        fare: fare,
        source: source,
        receiptPath: receiptPath,
        icKey: icKey,
      );

  void dispose() {
    from.dispose();
    to.dispose();
    fareText.dispose();
  }
}

class _LegCard extends StatelessWidget {
  const _LegCard({
    super.key,
    required this.form,
    required this.trip,
    required this.index,
    required this.onChanged,
    required this.onRemove,
  });

  final _LegForm form;
  final Trip trip;
  final int index;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  bool get _usesStops => form.mode == TransportMode.train || form.mode == TransportMode.bus;

  Future<void> _nearby(BuildContext context, TextEditingController target, bool isFrom) async {
    double? lat;
    double? lng;
    String where = '';
    if (isFrom && index == 0 && trip.startPlace.lat != null) {
      lat = trip.startPlace.lat;
      lng = trip.startPlace.lng;
      where = '出発地';
    } else if (!isFrom && trip.endPlace.lat != null) {
      lat = trip.endPlace.lat;
      lng = trip.endPlace.lng;
      where = '到着地';
    } else if (trip.route.isNotEmpty) {
      final p = isFrom ? trip.route.first : trip.route.last;
      lat = p.lat;
      lng = p.lng;
      where = isFrom ? '出発地' : '到着地';
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => _NearbySheet(lat: lat, lng: lng, where: where, mode: form.mode),
    );
    if (picked != null) {
      target.text = picked;
      onChanged();
    }
  }

  Future<void> _fromIc(BuildContext context) async {
    final h = await showModalBottomSheet<IcHistory>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => IcPickSheet(date: trip.start, mode: form.mode),
    );
    if (h == null) return;
    form.fareText.text = '${h.amount ?? 0}';
    form.source = FareSource.ic;
    form.icKey = h.key;
    if (h.kind.mode != null) form.mode = h.kind.mode!;
    onChanged();
  }

  Future<void> _receipt(BuildContext context) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('カメラで撮る'), onTap: () => Navigator.pop(c, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('写真から選ぶ'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
          if (form.receiptPath != null)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('領収書を外す'),
              onTap: () {
                form.receiptPath = null;
                onChanged();
                Navigator.pop(c);
              },
            ),
        ]),
      ),
    );
    if (src == null) return;
    final x = await ImagePicker().pickImage(source: src, maxWidth: 2000, imageQuality: 80);
    if (x == null) return;
    form.receiptPath = await store.saveReceipt(x.path);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(
                child: SegmentedButton<TransportMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: TransportMode.train, label: Text('電車'), icon: Icon(Icons.train)),
                    ButtonSegment(value: TransportMode.bus, label: Text('バス'), icon: Icon(Icons.directions_bus)),
                    ButtonSegment(value: TransportMode.taxi, label: Text('タクシー'), icon: Icon(Icons.local_taxi)),
                    ButtonSegment(value: TransportMode.other, label: Text('他')),
                  ],
                  selected: {form.mode},
                  onSelectionChanged: (s) {
                    form.mode = s.first;
                    onChanged();
                  },
                ),
              ),
              if (onRemove != null) IconButton(onPressed: onRemove, icon: const Icon(Icons.close), tooltip: 'この区間を削除'),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: form.from,
                  decoration: InputDecoration(
                    labelText: form.mode == TransportMode.bus ? '乗車停留所' : (form.mode == TransportMode.train ? '乗車駅' : '乗車地'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _usesStops
                        ? IconButton(
                            icon: const Icon(Icons.near_me, size: 20),
                            tooltip: '近くから選ぶ',
                            onPressed: () => _nearby(context, form.from, true),
                          )
                        : null,
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Icon(Icons.arrow_forward, size: 18)),
              Expanded(
                child: TextField(
                  controller: form.to,
                  decoration: InputDecoration(
                    labelText: form.mode == TransportMode.bus ? '降車停留所' : (form.mode == TransportMode.train ? '降車駅' : '降車地'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: _usesStops
                        ? IconButton(
                            icon: const Icon(Icons.near_me, size: 20),
                            tooltip: '近くから選ぶ',
                            onPressed: () => _nearby(context, form.to, false),
                          )
                        : null,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              SizedBox(
                width: 140,
                child: TextField(
                  controller: form.fareText,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) {
                    form.source = FareSource.manual;
                    form.icKey = null;
                    onChanged();
                  },
                  decoration: const InputDecoration(labelText: '金額', prefixText: '¥', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              if (form.source == FareSource.ic)
                Chip(
                  avatar: Icon(Icons.contactless, size: 16, color: scheme.primary),
                  label: const Text('IC'),
                  visualDensity: VisualDensity.compact,
                ),
              const Spacer(),
              if (_usesStops)
                TextButton.icon(onPressed: () => _fromIc(context), icon: const Icon(Icons.contactless), label: const Text('ICから')),
              if (form.mode == TransportMode.taxi || form.mode == TransportMode.other || form.receiptPath != null)
                TextButton.icon(
                  onPressed: () => _receipt(context),
                  icon: Icon(form.receiptPath == null ? Icons.receipt_long_outlined : Icons.receipt_long),
                  label: Text(form.receiptPath == null ? '領収書' : '領収書あり'),
                ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// 近くの駅・バス停の候補
class _NearbySheet extends StatefulWidget {
  const _NearbySheet({required this.lat, required this.lng, required this.where, required this.mode});

  /// 記録した位置（無ければ現在地で探す）
  final double? lat;
  final double? lng;
  final String where;
  final TransportMode mode;

  @override
  State<_NearbySheet> createState() => _NearbySheetState();
}

class _NearbySheetState extends State<_NearbySheet> {
  Future<NearbyResult>? _f;
  String _where = '';

  @override
  void initState() {
    super.initState();
    if (widget.lat != null && widget.lng != null) {
      _where = widget.where;
      _f = Places.nearby(widget.lat!, widget.lng!, widget.mode);
    } else {
      _searchHere();
    }
  }

  void _searchHere() {
    setState(() {
      _where = '現在地';
      _f = () async {
        final err = await Tracker.ensurePermission();
        if (err != null) return NearbyResult([], 0, error: err);
        final pos = await Tracker.currentPosition();
        if (pos == null) return NearbyResult([], 0, error: '現在地を取得できませんでした');
        return Places.nearby(pos.latitude, pos.longitude, widget.mode);
      }();
    });
  }

  String _km(int m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(m % 1000 == 0 ? 0 : 1)}km' : '${m}m';

  @override
  Widget build(BuildContext context) {
    final what = widget.mode == TransportMode.bus ? 'バス停' : '駅';
    final hereButton = TextButton.icon(
      onPressed: _searchHere,
      icon: const Icon(Icons.my_location),
      label: const Text('現在地で探す'),
    );
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: FutureBuilder<NearbyResult>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('$_where付近の$whatを探しています…'),
                ]),
              );
            }
            final r = snap.data ?? NearbyResult([], 0, error: '検索に失敗しました');
            if (r.places.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      r.error ?? '$_whereから${_km(r.radius)}以内に$whatが見つかりませんでした。\n地図データに登録されていない可能性があります。手入力してください。',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    if (_where != '現在地') hereButton,
                    if (r.error != null)
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _f = widget.lat != null && _where != '現在地'
                              ? Places.nearby(widget.lat!, widget.lng!, widget.mode)
                              : null;
                          if (_f == null) _searchHere();
                        }),
                        icon: const Icon(Icons.refresh),
                        label: const Text('もう一度'),
                      ),
                  ]),
                ),
              );
            }
            return ListView(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
                child: Row(children: [
                  Expanded(
                    child: Text('$_where付近の$what（${_km(r.radius)}以内）', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  if (_where != '現在地') hereButton,
                ]),
              ),
              for (final p in r.places)
                ListTile(
                  leading: Icon(widget.mode == TransportMode.bus ? Icons.directions_bus : Icons.train),
                  title: Text(p.name),
                  subtitle: p.line.isEmpty ? null : Text(p.line),
                  trailing: Text(_km(p.distance.round())),
                  onTap: () => Navigator.pop(context, p.name),
                ),
            ]);
          },
        ),
      ),
    );
  }
}
