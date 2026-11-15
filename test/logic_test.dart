import 'dart:io';
import 'dart:typed_data';

import 'package:fare_log/felica.dart';
import 'package:fare_log/models.dart';
import 'package:fare_log/pdf_report.dart';
import 'package:fare_log/period.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

Uint8List block(int term, int usage, DateTime d, int balance, int seq) {
  final b = Uint8List(16);
  b[0] = term;
  b[1] = usage;
  final v = ((d.year - 2000) << 9) | (d.month << 5) | d.day;
  b[4] = v >> 8;
  b[5] = v & 0xFF;
  b[10] = balance & 0xFF;
  b[11] = balance >> 8;
  b[12] = seq >> 16;
  b[13] = (seq >> 8) & 0xFF;
  b[14] = seq & 0xFF;
  return b;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('締め期間', () {
    expect(Period.of(DateTime(2026, 11, 15), ClosingType.day15).label, '2026年10月16日〜2026年11月15日');
    expect(Period.of(DateTime(2026, 11, 16), ClosingType.day15).label, '2026年11月16日〜2026年12月15日');
    expect(Period.of(DateTime(2026, 1, 3), ClosingType.day15).label, '2025年12月16日〜2026年1月15日');
    expect(Period.of(DateTime(2026, 2, 10), ClosingType.endOfMonth).label, '2026年2月1日〜2026年2月28日');
    final p = Period.of(DateTime(2026, 12, 20), ClosingType.day15);
    expect(p.next(ClosingType.day15).label, '2026年12月16日〜2027年1月15日'.replaceFirst('2026年12月16日', '2027年1月16日').replaceFirst('2027年1月15日', '2027年2月15日'));
    expect(p.previous(ClosingType.day15).label, '2026年11月16日〜2026年12月15日');
  });

  test('IC履歴の解析', () {
    final d = DateTime(2026, 11, 14);
    // 新しい順：バス210円、電車178円、チャージ1000円
    final blocks = [
      block(0x05, 0x0D, d, 1612, 5),
      block(0x16, 0x01, d, 1822, 4),
      block(0x08, 0x02, DateTime(2026, 11, 13), 2000, 3),
      block(0x16, 0x01, DateTime(2026, 11, 12), 1000, 2),
    ];
    final h = FeliCaReader.parse('01', blocks);
    expect(h[0].kind, IcKind.bus);
    expect(h[0].amount, 210);
    expect(h[1].kind, IcKind.train);
    expect(h[1].amount, 178);
    expect(h[2].kind, IcKind.charge);
    expect(h[2].amount, 1000);
    expect(h[3].amount, null);
    expect(h[0].date, d);
  });

  test('PDF', () async {
    Intl.defaultLocale = 'ja';
    await initializeDateFormatting('ja');
    final trips = <Trip>[];
    for (var i = 0; i < 30; i++) {
      final s = DateTime(2026, 11, 1 + i % 14, 9 + i % 8, 10);
      trips.add(Trip(
        id: '$i',
        start: s,
        end: s.add(const Duration(minutes: 45)),
        startPlace: Place(name: '東京都千代田区丸の内'),
        endPlace: Place(name: '神奈川県横浜市西区'),
        destination: i % 3 == 0 ? '株式会社サンプル商事 横浜支店' : '○○病院',
        purpose: '打合せ',
        legs: [
          Leg(mode: TransportMode.train, from: '東京', to: '横浜', fare: 483, source: FareSource.ic),
          if (i % 4 == 0) Leg(mode: TransportMode.bus, from: '横浜駅東口', to: 'みなとみらい', fare: 220),
          if (i % 7 == 0) Leg(mode: TransportMode.taxi, from: 'みなとみらい', to: '関内', fare: 1580),
        ],
      ));
    }
    final bytes = await PdfReport.build(
      period: Period.of(DateTime(2026, 11, 5), ClosingType.endOfMonth),
      trips: trips,
      settings: Settings(name: '山田 太郎', department: '営業部 第二課', employeeNo: '012345'),
    );
    File('build/sample.pdf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  });
}
