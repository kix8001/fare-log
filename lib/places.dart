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

class Places {
  static const _endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ];

  /// 近い順に駅とバス停を返す。電車なら [mode]=train、バスなら bus。
  static Future<List<NearbyPlace>> nearby(double lat, double lng, TransportMode mode) async {
    final radius = mode == TransportMode.bus ? 400 : 1500;
    final filter = mode == TransportMode.bus
        ? '''
node(around:$radius,$lat,$lng)[highway=bus_stop][name];
node(around:$radius,$lat,$lng)[public_transport=platform][bus=yes][name];
'''
        : '''
node(around:$radius,$lat,$lng)[railway~"^(station|halt)\$"][name];
node(around:$radius,$lat,$lng)[public_transport=station][name];
''';
    final query = '[out:json][timeout:15];($filter);out body;';
    for (final ep in _endpoints) {
      try {
        final res = await http
            .post(Uri.parse(ep), body: {'data': query})
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final out = <String, NearbyPlace>{};
        for (final e in (data['elements'] as List? ?? [])) {
          final tags = (e['tags'] as Map?)?.cast<String, dynamic>() ?? {};
          final name = (tags['name:ja'] ?? tags['name']) as String?;
          if (name == null || name.isEmpty) continue;
          final d = distanceMeters(lat, lng, (e['lat'] as num).toDouble(), (e['lon'] as num).toDouble());
          final line = (tags['operator'] ?? tags['network'] ?? tags['route_ref'] ?? '') as String;
          final key = mode == TransportMode.bus ? name : name.replaceAll(RegExp(r'駅$'), '');
          final prev = out[key];
          if (prev == null || prev.distance > d) {
            out[key] = NearbyPlace(
              mode == TransportMode.bus ? name : key,
              mode,
              d,
              line: line,
            );
          }
        }
        final list = out.values.toList()..sort((a, b) => a.distance.compareTo(b.distance));
        return list.take(15).toList();
      } catch (e) {
        debugPrint('Overpass($ep) 失敗: $e');
      }
    }
    return [];
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
