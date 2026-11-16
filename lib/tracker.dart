// GPSによる位置取得とルート記録
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale, debugPrint;
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';

import 'models.dart';
import 'store.dart';

class Tracker {
  Tracker(this.store);

  final Store store;
  StreamSubscription<Position>? _sub;

  bool get running => _sub != null;

  static final _geocoding = geo.Geocoding(locale: const Locale('ja', 'JP'));

  /// 位置情報の権限を確認・要求する。使えないときは理由の文字列を返す。
  static Future<String?> ensurePermission({bool background = false}) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return '端末の位置情報がオフになっています。設定でオンにしてください。';
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied) return '位置情報の利用が許可されませんでした。';
    if (p == LocationPermission.deniedForever) {
      return '位置情報の利用が許可されていません。端末の設定アプリから許可してください。';
    }
    return null;
  }

  /// 現在地を取る。時間がかかるときは段階的に精度を落とし、最後は直前の位置を使う。
  static Future<Position?> currentPosition({Duration timeout = const Duration(seconds: 10)}) async {
    Position? last;
    try {
      last = await Geolocator.getLastKnownPosition();
    } catch (_) {}
    // 2分以内の位置があれば、それをすぐ使う
    if (last != null &&
        DateTime.now().difference(last.timestamp).inSeconds.abs() < 120 &&
        last.accuracy < 200) {
      return last;
    }
    for (final acc in [LocationAccuracy.high, LocationAccuracy.medium]) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(accuracy: acc, timeLimit: timeout),
        ).timeout(timeout + const Duration(seconds: 2));
      } catch (e) {
        debugPrint('現在地の取得に失敗（$acc）: $e');
      }
    }
    return last;
  }

  /// 座標から住所（短め）を得る
  static Future<String> addressOf(double lat, double lng) async {
    try {
      final list = await _geocoding.placemarkFromCoordinates(lat, lng).timeout(const Duration(seconds: 8));
      if (list.isEmpty) return '';
      final p = list.first;
      final parts = [p.administrativeArea, p.locality, p.subLocality, p.thoroughfare]
          .whereType<String>()
          .where((s) => s.isNotEmpty)
          .toList();
      // 重複（「東京都 東京都」など）を除く
      final out = <String>[];
      for (final s in parts) {
        if (!out.contains(s)) out.add(s);
      }
      return out.join('');
    } catch (e) {
      debugPrint('住所の取得に失敗: $e');
      return '';
    }
  }

  LocationSettings _streamSettings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: '移動を記録中',
          notificationText: '移動ルートを記録しています',
          enableWakeLock: false,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 30,
        activityType: ActivityType.otherNavigation,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: true,
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 30);
  }

  /// 記録中の移動に対してルート記録を始める
  void startRoute(Trip trip) {
    stopRoute();
    _sub = Geolocator.getPositionStream(locationSettings: _streamSettings()).listen(
      (pos) {
        // 精度の悪すぎる点は捨てる（屋内などでは 100m を超えることがある）
        if (pos.accuracy > 250) return;
        _setStartIfMissing(trip, pos);
        if (!store.settings.recordRoute) return;
        store.addRoutePoint(trip, RoutePoint(pos.latitude, pos.longitude, pos.timestamp));
      },
      onError: (e) => debugPrint('位置の追跡でエラー: $e'),
    );
  }

  void stopRoute() {
    _sub?.cancel();
    _sub = null;
  }

  /// 出発地がまだ無ければ、この位置を出発地にして住所を調べる
  void _setStartIfMissing(Trip trip, Position pos) {
    if (trip.startPlace.lat != null || !trip.isRecording) return;
    trip.startPlace = Place(lat: pos.latitude, lng: pos.longitude);
    if (trip.route.isEmpty) trip.route.add(RoutePoint(pos.latitude, pos.longitude, trip.start));
    store.upsert(trip);
    addressOf(pos.latitude, pos.longitude).then((a) {
      trip.startPlace.name = a.isNotEmpty ? a : coordLabel(pos.latitude, pos.longitude);
      store.upsert(trip);
    });
  }

  static String coordLabel(double lat, double lng) => '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  /// スタート：すぐに記録を始め、現在地は取れしだい入れる
  Future<Trip> start() async {
    final trip = Trip(id: Store.newId(), start: DateTime.now());
    await store.upsert(trip);
    startRoute(trip);
    currentPosition(timeout: const Duration(seconds: 15)).then((pos) {
      if (pos != null) _setStartIfMissing(trip, pos);
    });
    return trip;
  }

  /// 移動完了：到着地を記録してルート記録を止める
  Future<void> finish(Trip trip) async {
    stopRoute();
    final now = DateTime.now();
    trip.end = now;
    // 1分以内に記録した点があればそれを到着地にする（待たずに済む）
    final recent = trip.route.isNotEmpty && now.difference(trip.route.last.time).inSeconds.abs() < 60
        ? trip.route.last
        : null;
    double? lat = recent?.lat;
    double? lng = recent?.lng;
    if (lat == null) {
      final pos = await currentPosition(timeout: const Duration(seconds: 8));
      if (pos != null) {
        lat = pos.latitude;
        lng = pos.longitude;
        trip.route.add(RoutePoint(lat, lng, now));
      }
    }
    if (lat != null && lng != null) {
      final a = await addressOf(lat, lng);
      trip.endPlace = Place(lat: lat, lng: lng, name: a.isNotEmpty ? a : coordLabel(lat, lng));
    }
    if (trip.startPlace.lat == null && trip.route.isNotEmpty) {
      final p = trip.route.first;
      trip.startPlace = Place(lat: p.lat, lng: p.lng, name: coordLabel(p.lat, p.lng));
    }
    await store.upsert(trip);
  }
}
