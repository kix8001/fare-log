// 近くの駅・バス停を探す（OpenStreetMap の Overpass API、無料・キー不要）
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

  /// 見つかるまで範囲を広げながら探す半径（メートル）
  static const _busRadii = [500, 1000, 2000];
  static const _trainRadii = [1500, 3000, 6000];

  /// 近い順に駅またはバス停を返す。
  static Future<NearbyResult> nearby(double lat, double lng, TransportMode mode) async {
    final radii = mode == TransportMode.bus ? _busRadii : _trainRadii;
    var radius = radii.first;
    for (radius in radii) {
      final r = await _search(lat, lng, mode, radius);
      if (r == null) {
        return NearbyResult([], radius, error: '検索サーバーにつながりませんでした。電波の良い場所でもう一度試してください。');
      }
      if (r.isNotEmpty) return NearbyResult(r, radius);
    }
    return NearbyResult([], radius);
  }

  /// 通信に失敗したら null
  static Future<List<NearbyPlace>?> _search(double lat, double lng, TransportMode mode, int radius) async {
    final a = 'around:$radius,$lat,$lng';
    final filter = mode == TransportMode.bus
        ? '''
nwr($a)[highway=bus_stop][name];
nwr($a)[public_transport=platform][bus=yes][name];
nwr($a)[public_transport=stop_position][bus=yes][name];
nwr($a)[amenity=bus_station][name];
'''
        : '''
nwr($a)[railway~"^(station|halt)\$"][name];
nwr($a)[public_transport=station][name];
''';
    final query = '[out:json][timeout:20];($filter);out center tags;';
    for (final ep in _endpoints) {
      try {
        final res = await http
            .post(
              Uri.parse(ep),
              headers: {'User-Agent': 'FareLog/1.0 (personal fare log app)'},
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 25));
        if (res.statusCode != 200) {
          debugPrint('Overpass($ep) HTTP ${res.statusCode}');
          continue;
        }
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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
      } catch (e) {
        debugPrint('Overpass($ep) 失敗: $e');
      }
    }
    return null;
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
