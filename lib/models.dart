// データモデル（移動記録・区間・設定）

/// 交通手段
enum TransportMode {
  train('電車'),
  bus('バス'),
  taxi('タクシー'),
  other('その他');

  const TransportMode(this.label);
  final String label;

  static TransportMode parse(String? s) =>
      TransportMode.values.firstWhere((m) => m.name == s, orElse: () => TransportMode.other);
}

/// 運賃の入力元
enum FareSource {
  manual('手入力'),
  ic('ICカード');

  const FareSource(this.label);
  final String label;

  static FareSource parse(String? s) =>
      FareSource.values.firstWhere((m) => m.name == s, orElse: () => FareSource.manual);
}

/// GPSで記録した1点
class RoutePoint {
  RoutePoint(this.lat, this.lng, this.time);
  final double lat;
  final double lng;
  final DateTime time;

  Map<String, dynamic> toJson() => {'a': lat, 'o': lng, 't': time.millisecondsSinceEpoch};

  factory RoutePoint.fromJson(Map<String, dynamic> j) => RoutePoint(
        (j['a'] as num).toDouble(),
        (j['o'] as num).toDouble(),
        DateTime.fromMillisecondsSinceEpoch(j['t'] as int),
      );
}

/// 地点（座標と名称）
class Place {
  Place({this.lat, this.lng, this.name = ''});
  double? lat;
  double? lng;
  String name;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'name': name};

  factory Place.fromJson(Map<String, dynamic>? j) => j == null
      ? Place()
      : Place(
          lat: (j['lat'] as num?)?.toDouble(),
          lng: (j['lng'] as num?)?.toDouble(),
          name: j['name'] as String? ?? '',
        );
}

/// 乗り物1回分（1つの移動に複数の乗り継ぎがありうる）
class Leg {
  Leg({
    required this.mode,
    this.from = '',
    this.to = '',
    this.fare = 0,
    this.source = FareSource.manual,
    this.receiptPath,
    this.icKey,
  });

  TransportMode mode;
  String from;
  String to;
  int fare;
  FareSource source;

  /// 領収書写真（アプリ内に保存したファイルのパス）
  String? receiptPath;

  /// ICカード履歴から取り込んだときの識別子（二重取り込み防止）
  String? icKey;

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'from': from,
        'to': to,
        'fare': fare,
        'source': source.name,
        'receipt': receiptPath,
        'icKey': icKey,
      };

  factory Leg.fromJson(Map<String, dynamic> j) => Leg(
        mode: TransportMode.parse(j['mode'] as String?),
        from: j['from'] as String? ?? '',
        to: j['to'] as String? ?? '',
        fare: (j['fare'] as num?)?.toInt() ?? 0,
        source: FareSource.parse(j['source'] as String?),
        receiptPath: j['receipt'] as String?,
        icKey: j['icKey'] as String?,
      );
}

/// 1回の移動
class Trip {
  Trip({
    required this.id,
    required this.start,
    this.end,
    Place? startPlace,
    Place? endPlace,
    List<RoutePoint>? route,
    List<Leg>? legs,
    this.destination = '',
    this.purpose = '',
    this.memo = '',
    this.noTime = false,
  })  : startPlace = startPlace ?? Place(),
        endPlace = endPlace ?? Place(),
        route = route ?? [],
        legs = legs ?? [];

  final String id;
  DateTime start;
  DateTime? end;
  Place startPlace;
  Place endPlace;
  List<RoutePoint> route;
  List<Leg> legs;

  /// 用務先（訪問先）
  String destination;

  /// 目的
  String purpose;
  String memo;

  /// 時刻が不明（ICカード履歴から作った記録は日付しかわからない）
  bool noTime;

  bool get isRecording => end == null;
  int get totalFare => legs.fold(0, (s, l) => s + l.fare);

  String get modesLabel {
    final seen = <TransportMode>{};
    for (final l in legs) {
      seen.add(l.mode);
    }
    return seen.map((m) => m.label).join('・');
  }

  /// 区間の表示（区間が入力されていればそれを、無ければ出発地→到着地）
  String get sectionLabel {
    final parts = legs
        .where((l) => l.from.isNotEmpty || l.to.isNotEmpty)
        .map((l) => '${l.from}→${l.to}')
        .toList();
    if (parts.isNotEmpty) return parts.join('、');
    final a = startPlace.name.isEmpty ? '出発地' : startPlace.name;
    final b = endPlace.name.isEmpty ? '到着地' : endPlace.name;
    return '$a→$b';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.millisecondsSinceEpoch,
        'end': end?.millisecondsSinceEpoch,
        'startPlace': startPlace.toJson(),
        'endPlace': endPlace.toJson(),
        'route': route.map((p) => p.toJson()).toList(),
        'legs': legs.map((l) => l.toJson()).toList(),
        'destination': destination,
        'purpose': purpose,
        'memo': memo,
        'noTime': noTime,
      };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        start: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
        end: j['end'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['end'] as int),
        startPlace: Place.fromJson(j['startPlace'] as Map<String, dynamic>?),
        endPlace: Place.fromJson(j['endPlace'] as Map<String, dynamic>?),
        route: ((j['route'] as List?) ?? [])
            .map((e) => RoutePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        legs: ((j['legs'] as List?) ?? []).map((e) => Leg.fromJson(e as Map<String, dynamic>)).toList(),
        destination: j['destination'] as String? ?? '',
        purpose: j['purpose'] as String? ?? '',
        memo: j['memo'] as String? ?? '',
        noTime: j['noTime'] as bool? ?? false,
      );
}

/// 締め日の種類
enum ClosingType {
  endOfMonth('1日〜月末'),
  day15('16日〜翌月15日');

  const ClosingType(this.label);
  final String label;

  static ClosingType parse(String? s) =>
      ClosingType.values.firstWhere((m) => m.name == s, orElse: () => ClosingType.endOfMonth);
}

/// 設定（PDFのヘッダーに載せる情報など）
class Settings {
  Settings({
    this.name = '',
    this.department = '',
    this.employeeNo = '',
    this.closing = ClosingType.endOfMonth,
    this.recordRoute = true,
  });

  String name;
  String department;
  String employeeNo;
  ClosingType closing;
  bool recordRoute;

  Map<String, dynamic> toJson() => {
        'name': name,
        'department': department,
        'employeeNo': employeeNo,
        'closing': closing.name,
        'recordRoute': recordRoute,
      };

  factory Settings.fromJson(Map<String, dynamic>? j) => j == null
      ? Settings()
      : Settings(
          name: j['name'] as String? ?? '',
          department: j['department'] as String? ?? '',
          employeeNo: j['employeeNo'] as String? ?? '',
          closing: ClosingType.parse(j['closing'] as String?),
          recordRoute: j['recordRoute'] as bool? ?? true,
        );
}
