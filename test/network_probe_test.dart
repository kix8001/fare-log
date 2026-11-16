// ignore_for_file: avoid_print
// 検索サーバーへの接続確認（CI のログに結果を出すだけで、失敗にはしない）
import 'package:fare_log/models.dart';
import 'package:fare_log/places.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('検索サーバーの応答', () async {
    const lat = 35.6812, lng = 139.7671; // 東京駅
    const q = '[out:json][timeout:10];(node(around:500,$lat,$lng)[highway=bus_stop][name];);out tags center;';
    for (final ep in [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.private.coffee/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
    ]) {
      try {
        final sw = Stopwatch()..start();
        final r = await http
            .post(Uri.parse(ep), headers: {'User-Agent': 'FareLog/1.0 (personal fare log app)'}, body: {'data': q})
            .timeout(const Duration(seconds: 20));
        final body = r.body.length > 300 ? r.body.substring(0, 300) : r.body;
        print('PROBE $ep -> ${r.statusCode} ${sw.elapsedMilliseconds}ms ${body.replaceAll('\n', ' ')}');
      } catch (e) {
        print('PROBE $ep -> 例外 $e');
      }
    }
    final bus = await Places.nearby(lat, lng, TransportMode.bus);
    print('PROBE bus: error=${bus.error} n=${bus.places.length} ${bus.places.take(3).map((p) => p.name).toList()}');
    final train = await Places.nearby(lat, lng, TransportMode.train);
    print('PROBE train: error=${train.error} n=${train.places.length} ${train.places.take(3).map((p) => p.name).toList()}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
