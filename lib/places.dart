// 近くの駅・バス停を探す（OpenStreetMap の Overpass API、無料・キー不要）
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class NearbyPlace {
  NearbyPlace(this.name, this.mode, this.distance, {this.line = ''});
  final String name;
  final TransportMode mode;

  /// メートル
  final double distance;

  /// 路線名・事業者名など（わかれば）
  final String line;
}

class NearbyResult {
  NearbyResult(this.places, this.radius, {this.error});

  final List<NearbyPlace> places;

  /// 最後に探した半径（メートル）
  final int radius;

  /// 通信エラーなどで検索できなかったときの理由
  final String? error;
}

class Places {
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  /// 探す半径（メートル）
  static const _busRadius = 1500;
  static const _trainRadius = 5000;

  /// 近い順に駅またはバス停を返す。
  static Future<NearbyResult> nearby(double lat, double lng, TransportMode mode) async {
    final radius = mode == TransportMode.bus ? _busRadius : _trainRadius;
    // 駅は国内の駅データ（HeartRails Express）と OpenStreetMap を同時に引き、早く返った方を使う
    final futures = <Future<List<NearbyPlace>?>>[
      _overpass(lat, lng, mode, radius),
      if (mode != TransportMode.bus) _heartRails(lat, lng),
    ];
    final r = await _firstNonEmpty(futures);
    if (r == null) {
      return NearbyResult([], radius, error: '検索サーバーにつながりませんでした。電波の良い場所でもう一度試してください。');
    }
    return NearbyResult(r, radius);
  }

  /// 最初に「1件以上」返ったものを使う。全部空なら空、全部失敗なら null。
  static Future<List<NearbyPlace>?> _firstNonEmpty(List<Future<List<NearbyPlace>?>> fs) {
    final c = Completer<List<NearbyPlace>?>();
    var pending = fs.length;
    var anyOk = false;
    for (final f in fs) {
      f.then((v) {
        if (v != null) anyOk = true;
        if (v != null && v.isNotEmpty && !c.isCompleted) c.complete(v);
      }, onError: (_) {}).whenComplete(() {
        pending--;
        if (pending == 0 && !c.isCompleted) c.complete(anyOk ? <NearbyPlace>[] : null);
      });
    }
    return c.future;
  }

  /// Overpass：複数のサーバーへ同時に問い合わせ、最初に成功した結果を使う。全部失敗なら null。
  static Future<List<NearbyPlace>?> _overpass(double lat, double lng, TransportMode mode, int radius) async {
    final a = 'around:$radius,$lat,$lng';
    final filter = mode == TransportMode.bus
        ? '''
node($a)[highway=bus_stop][name];
node($a)[public_transport=platform][bus=yes][name];
node($a)[amenity=bus_station][name];
'''
        : '''
node($a)[railway~"^(station|halt)\$"][name];
node($a)[public_transport=station][name];
''';
    final query = '[out:json][timeout:10];($filter);out tags center;';
    final c = Completer<List<NearbyPlace>?>();
    var pending = _endpoints.length;
    for (final ep in _endpoints) {
      () async {
        try {
          final res = await http
              .post(
                Uri.parse(ep),
                headers: {'User-Agent': 'FareLog/1.0 (personal fare log app)'},
                body: {'data': query},
              )
              .timeout(const Duration(seconds: 12));
          if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
          final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          if (!c.isCompleted) c.complete(_parseOverpass(data, lat, lng, mode));
        } catch (e) {
          debugPrint('Overpass($ep) 失敗: $e');
        } finally {
          pending--;
          if (pending == 0 && !c.isCompleted) c.complete(null);
        }
      }();
    }
    return c.future;
  }

  static List<NearbyPlace> _parseOverpass(Map<String, dynamic> data, double lat, double lng, TransportMode mode) {
    final out = <String, NearbyPlace>{};
    for (final e in (data['elements'] as List? ?? [])) {
      final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? {};
      final name = (tags['name:ja'] ?? tags['name']) as String?;
      if (name == null || name.isEmpty) continue;
      final c = (e['center'] as Map?) ?? e as Map;
      final eLat = (c['lat'] as num?)?.toDouble();
      final eLng = (c['lon'] as num?)?.toDouble();
      if (eLat == null || eLng == null) continue;
      final d = distanceMeters(lat, lng, eLat, eLng);
      final line = (tags['operator'] ?? tags['network'] ?? tags['route_ref'] ?? '') as String;
      final key = mode == TransportMode.bus ? name : name.replaceAll(RegExp(r'駅$'), '');
      final prev = out[key];
      if (prev == null || prev.distance > d) {
        out[key] = NearbyPlace(key, mode, d, line: line.isEmpty ? (prev?.line ?? '') : line);
      }
    }
    final list = out.values.toList()..sort((a, b) => a.distance.compareTo(b.distance));
    return list.take(20).toList();
  }

  /// HeartRails Express（国内の駅、キー不要）。失敗なら null。
  static Future<List<NearbyPlace>?> _heartRails(double lat, double lng) async {
    try {
      final uri = Uri.https('express.heartrails.com', '/api/json', {
        'method': 'getStations',
        'x': '$lng',
        'y': '$lat',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final list = ((data['response'] as Map?)?['station'] as List?) ?? [];
      final out = <String, NearbyPlace>{};
      for (final e in list) {
        final m = (e as Map).cast<String, dynamic>();
        final name = m['name'] as String? ?? '';
        if (name.isEmpty) continue;
        final d = distanceMeters(lat, lng, double.parse('${m['y']}'), double.parse('${m['x']}'));
        final line = m['line'] as String? ?? '';
        final prev = out[name];
        out[name] = NearbyPlace(
          name,
          TransportMode.train,
          prev == null || prev.distance > d ? d : prev.distance,
          line: prev == null ? line : '${prev.line}・$line',
        );
      }
      return out.values.toList()..sort((a, b) => a.distance.compareTo(b.distance));
    } catch (e) {
      debugPrint('HeartRails 失敗: $e');
      return null;
    }
  }

  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) + cos(rad(lat1)) * cos(rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * asin(sqrt(a));
  }
}
