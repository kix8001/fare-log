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

  static Future<Position?> currentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (e) {
      debugPrint('現在地の取得に失敗: $e');
      return Geolocator.getLastKnownPosition();
    }
  }

  /// 座標から住所（短め）を得る
  static Future<String> addressOf(double lat, double lng) async {
    try {
      final list = await _geocoding.placemarkFromCoordinates(lat, lng);
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
    if (!store.settings.recordRoute) return;
    _sub = Geolocator.getPositionStream(locationSettings: _streamSettings()).listen(
      (pos) {
        // 精度の悪い点は捨てる
        if (pos.accuracy > 100) return;
        store.addRoutePoint(trip, RoutePoint(pos.latitude, pos.longitude, pos.timestamp));
      },
      onError: (e) => debugPrint('位置の追跡でエラー: $e'),
    );
  }

  void stopRoute() {
    _sub?.cancel();
    _sub = null;
  }

  /// スタート：現在地を取って新しい移動を作る
  Future<Trip> start() async {
    final now = DateTime.now();
    final trip = Trip(id: Store.newId(), start: now);
    final pos = await currentPosition();
    if (pos != null) {
      trip.startPlace = Place(lat: pos.latitude, lng: pos.longitude);
      trip.route.add(RoutePoint(pos.latitude, pos.longitude, now));
    }
    await store.upsert(trip);
    startRoute(trip);
    if (pos != null) {
      // 住所は後から埋める（オフラインでも開始できるように）
      addressOf(pos.latitude, pos.longitude).then((a) {
        if (a.isNotEmpty && trip.startPlace.name.isEmpty) {
          trip.startPlace.name = a;
          store.upsert(trip);
        }
      });
    }
    return trip;
  }

  /// 移動完了：到着地を記録してルート記録を止める
  Future<void> finish(Trip trip) async {
    stopRoute();
    final now = DateTime.now();
    final pos = await currentPosition();
    trip.end = now;
    if (pos != null) {
      trip.endPlace = Place(lat: pos.latitude, lng: pos.longitude);
      trip.route.add(RoutePoint(pos.latitude, pos.longitude, now));
      final a = await addressOf(pos.latitude, pos.longitude);
      if (a.isNotEmpty) trip.endPlace.name = a;
    }
    await store.upsert(trip);
  }
}
