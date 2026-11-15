// 記録の保存（アプリ内の JSON ファイル）
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class Store extends ChangeNotifier {
  Store._(this._dir);

  final Directory _dir;
  final List<Trip> trips = [];
  Settings settings = Settings();

  static Future<Store> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final s = Store._(dir);
    await s._load();
    return s;
  }

  File get _tripsFile => File('${_dir.path}/trips.json');
  File get _settingsFile => File('${_dir.path}/settings.json');
  Directory get receiptDir => Directory('${_dir.path}/receipts');

  Future<void> _load() async {
    try {
      if (await _tripsFile.exists()) {
        final list = jsonDecode(await _tripsFile.readAsString()) as List;
        trips
          ..clear()
          ..addAll(list.map((e) => Trip.fromJson(e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('trips.json の読み込みに失敗: $e');
    }
    try {
      if (await _settingsFile.exists()) {
        settings = Settings.fromJson(jsonDecode(await _settingsFile.readAsString()) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('settings.json の読み込みに失敗: $e');
    }
    _sort();
  }

  void _sort() => trips.sort((a, b) => b.start.compareTo(a.start));

  Future<void> _saveTrips() async {
    final tmp = File('${_tripsFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(trips.map((t) => t.toJson()).toList()));
    await tmp.rename(_tripsFile.path);
  }

  /// 記録中の移動（無ければ null）
  Trip? get current {
    for (final t in trips) {
      if (t.isRecording) return t;
    }
    return null;
  }

  Future<void> upsert(Trip t) async {
    final i = trips.indexWhere((e) => e.id == t.id);
    if (i < 0) {
      trips.add(t);
    } else {
      trips[i] = t;
    }
    _sort();
    notifyListeners();
    await _saveTrips();
  }

  Future<void> delete(Trip t) async {
    trips.removeWhere((e) => e.id == t.id);
    for (final l in t.legs) {
      final p = l.receiptPath;
      if (p != null) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
    }
    notifyListeners();
    await _saveTrips();
  }

  /// GPSの点を足す（頻繁に呼ばれるので保存は間引く）
  DateTime _lastSave = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> addRoutePoint(Trip t, RoutePoint p) async {
    t.route.add(p);
    notifyListeners();
    if (DateTime.now().difference(_lastSave).inSeconds >= 30) {
      _lastSave = DateTime.now();
      await _saveTrips();
    }
  }

  Future<void> saveSettings(Settings s) async {
    settings = s;
    notifyListeners();
    await _settingsFile.writeAsString(jsonEncode(s.toJson()));
  }

  /// ICカードから取り込み済みのキー
  Set<String> get importedIcKeys => {
        for (final t in trips)
          for (final l in t.legs)
            if (l.icKey != null) l.icKey!,
      };

  /// 領収書の写真をアプリ内にコピーして、そのパスを返す
  Future<String> saveReceipt(String srcPath) async {
    await receiptDir.create(recursive: true);
    final ext = srcPath.contains('.') ? srcPath.substring(srcPath.lastIndexOf('.')) : '.jpg';
    final dst = File('${receiptDir.path}/${DateTime.now().microsecondsSinceEpoch}$ext');
    await File(srcPath).copy(dst.path);
    return dst.path;
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}
