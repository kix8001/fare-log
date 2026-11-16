// 全国のバス停データ（アプリ内蔵、通信不要）
//
// 出典：国土数値情報（バス停留所データ、令和4年）国土交通省
// tool/build_busstops.py で assets/busstops.tsv.gz を作る。
// 形式（gzip した UTF-8 テキスト）：
//   #ops の後に事業者名を1行ずつ、#stops の後に「緯度×1e5 TAB 経度×1e5 TAB 名前 TAB 事業者番号」を緯度順に。
import 'dart:convert' show utf8;
import 'dart:io' show gzip;
import 'dart:math' show cos, pi, sqrt;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

class BusStopHit {
  BusStopHit(this.name, this.operator, this.distance);
  final String name;
  final String operator;
  final double distance;
}

class _Db {
  _Db(this.lat, this.lng, this.names, this.opIdx, this.ops);
  final Int32List lat;
  final Int32List lng;
  final List<String> names;
  final Uint16List opIdx;
  final List<String> ops;
}

_Db _parse(Uint8List gz) {
  final s = utf8.decode(gzip.decode(gz));
  final lines = s.split('\n');
  final ops = <String>[];
  var i = 0;
  if (lines.isNotEmpty && lines[0] == '#ops') i = 1;
  while (i < lines.length && lines[i] != '#stops') {
    ops.add(lines[i]);
    i++;
  }
  i++;
  final n = lines.length - i;
  final lat = Int32List(n);
  final lng = Int32List(n);
  final names = List<String>.filled(n, '');
  final opIdx = Uint16List(n);
  var k = 0;
  for (; i < lines.length; i++) {
    final l = lines[i];
    if (l.isEmpty) continue;
    final p = l.split('\t');
    if (p.length < 4) continue;
    lat[k] = int.parse(p[0]);
    lng[k] = int.parse(p[1]);
    names[k] = p[2];
    opIdx[k] = int.parse(p[3]);
    k++;
  }
  return _Db(
    Int32List.sublistView(lat, 0, k),
    Int32List.sublistView(lng, 0, k),
    names.sublist(0, k),
    Uint16List.sublistView(opIdx, 0, k),
    ops,
  );
}

class BusStops {
  static Future<_Db>? _db;

  /// 先読み（初回は1秒ほどかかるため、アプリ起動後に呼んでおく）
  static Future<void> preload() => _load();

  static Future<_Db> _load() => _db ??= () async {
        final data = await rootBundle.load('assets/busstops.tsv.gz');
        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        return compute(_parse, bytes);
      }();

  /// [radius] メートル以内のバス停を近い順に返す
  static Future<List<BusStopHit>> nearby(double lat, double lng, {int radius = 1000, int limit = 20}) async {
    final db = await _load();
    final la = (lat * 1e5).round();
    final lo = (lng * 1e5).round();
    // 緯度1度 ≒ 111km
    final dLat = (radius / 111000 * 1e5).ceil();
    final cosLat = cos(lat * pi / 180);
    final dLng = (radius / (111000 * cosLat) * 1e5).ceil();
    var a = _lowerBound(db.lat, la - dLat);
    final hits = <BusStopHit>[];
    for (; a < db.lat.length && db.lat[a] <= la + dLat; a++) {
      final x = db.lng[a];
      if (x < lo - dLng || x > lo + dLng) continue;
      final dy = (db.lat[a] - la) / 1e5 * 111000;
      final dx = (x - lo) / 1e5 * 111000 * cosLat;
      final d = sqrt(dx * dx + dy * dy);
      if (d > radius) continue;
      hits.add(BusStopHit(db.names[a], db.ops[db.opIdx[a]], d));
    }
    hits.sort((p, q) => p.distance.compareTo(q.distance));
    // 同じ名前（上り・下りなど）は近い方だけ残す
    final seen = <String>{};
    final out = <BusStopHit>[];
    for (final h in hits) {
      if (seen.add(h.name)) out.add(h);
      if (out.length >= limit) break;
    }
    return out;
  }

  static int _lowerBound(Int32List a, int v) {
    var lo = 0, hi = a.length;
    while (lo < hi) {
      final m = (lo + hi) >> 1;
      if (a[m] < v) {
        lo = m + 1;
      } else {
        hi = m;
      }
    }
    return lo;
  }
}
