// 締め期間の計算
import 'package:intl/intl.dart';

import 'models.dart';

/// 締め期間（開始日〜終了日、両端を含む）
class Period {
  Period(this.start, this.end);

  /// 開始日 0:00
  final DateTime start;

  /// 終了日 0:00（この日の終わりまでを含む）
  final DateTime end;

  bool contains(DateTime t) {
    final d = DateTime(t.year, t.month, t.day);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  String get label {
    final f = DateFormat('yyyy年M月d日');
    return '${f.format(start)}〜${f.format(end)}';
  }

  /// 「2026年11月分」のような呼び名（締めの月）
  String get title => '${end.year}年${end.month}月分';

  @override
  bool operator ==(Object other) => other is Period && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  /// 日付 [t] を含む締め期間
  static Period of(DateTime t, ClosingType type) {
    switch (type) {
      case ClosingType.endOfMonth:
        return Period(DateTime(t.year, t.month, 1), DateTime(t.year, t.month + 1, 0));
      case ClosingType.day15:
        if (t.day >= 16) {
          return Period(DateTime(t.year, t.month, 16), DateTime(t.year, t.month + 1, 15));
        }
        return Period(DateTime(t.year, t.month - 1, 16), DateTime(t.year, t.month, 15));
    }
  }

  Period previous(ClosingType type) => of(start.subtract(const Duration(days: 1)), type);
  Period next(ClosingType type) => of(end.add(const Duration(days: 1)), type);
}
