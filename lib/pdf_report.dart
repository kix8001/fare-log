// 交通費精算書のPDFを作る
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'models.dart';
import 'period.dart';

final _yen = NumberFormat('#,##0');
String yen(int v) => '¥${_yen.format(v)}';

class PdfReport {
  static Future<Uint8List> build({
    required Period period,
    required List<Trip> trips,
    required Settings settings,
    bool includeReceipts = true,
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/BIZUDGothic-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/BIZUDGothic-Bold.ttf'));
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final doc = pw.Document(title: '交通費精算書 ${period.title}', theme: theme);

    final sorted = [...trips]..sort((a, b) => a.start.compareTo(b.start));
    final total = sorted.fold<int>(0, (s, t) => s + t.totalFare);
    final dateF = DateFormat('M/d(E)', 'ja');
    final timeF = DateFormat('H:mm');

    // 交通機関別の小計
    final byMode = <TransportMode, int>{};
    for (final t in sorted) {
      for (final l in t.legs) {
        byMode[l.mode] = (byMode[l.mode] ?? 0) + l.fare;
      }
    }

    const headerStyle = pw.TextStyle(fontSize: 8.5, color: PdfColors.white);
    const cellStyle = pw.TextStyle(fontSize: 8.5);

    pw.Widget infoCell(String label, String value, {double width = 160}) => pw.Container(
          width: width,
          padding: const pw.EdgeInsets.symmetric(vertical: 3),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.5)),
          ),
          child: pw.Row(children: [
            pw.SizedBox(width: 48, child: pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))),
            pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: 10.5))),
          ]),
        );

    pw.Widget stampBox(String label) => pw.Container(
          width: 56,
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey600, width: 0.5)),
          child: pw.Column(children: [
            pw.Container(
              width: double.infinity,
              color: PdfColors.grey200,
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              alignment: pw.Alignment.center,
              child: pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
            ),
            pw.SizedBox(height: 46),
          ]),
        );

    final rows = <List<String>>[];
    var no = 0;
    for (final t in sorted) {
      no++;
      final legs = t.legs.isEmpty ? [Leg(mode: TransportMode.other)] : t.legs;
      for (var i = 0; i < legs.length; i++) {
        final l = legs[i];
        final section = (l.from.isNotEmpty || l.to.isNotEmpty) ? '${l.from} → ${l.to}' : (i == 0 ? t.sectionLabel : '');
        final time = t.end == null ? timeF.format(t.start) : '${timeF.format(t.start)}〜${timeF.format(t.end!)}';
        rows.add([
          i == 0 ? '$no' : '',
          i == 0 ? '${dateF.format(t.start)}\n$time' : '',
          i == 0 ? t.destination : '',
          i == 0 ? t.purpose : '',
          section,
          t.legs.isEmpty ? '' : l.mode.label + (l.source == FareSource.ic ? '\n(IC)' : ''),
          t.legs.isEmpty ? '' : yen(l.fare),
        ]);
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 32, 28, 32),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 6),
                child: pw.Text('交通費精算書 ${period.title}　${settings.name}',
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ),
        build: (ctx) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('交通費精算書', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('対象期間：${period.label}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('作成日：${DateFormat('yyyy年M月d日').format(DateTime.now())}',
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    pw.SizedBox(height: 10),
                    pw.Wrap(spacing: 16, runSpacing: 2, children: [
                      infoCell('所属', settings.department, width: 220),
                      infoCell('社員番号', settings.employeeNo, width: 140),
                      infoCell('氏名', settings.name, width: 220),
                    ]),
                  ],
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Row(children: [stampBox('承認'), stampBox('確認'), stampBox('本人')]),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey800, width: 1)),
            child: pw.Row(children: [
              pw.Text('合計金額', style: const pw.TextStyle(fontSize: 11)),
              pw.SizedBox(width: 12),
              pw.Text(yen(total), style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Spacer(),
              pw.Text(
                [
                  for (final m in TransportMode.values)
                    if ((byMode[m] ?? 0) > 0) '${m.label} ${yen(byMode[m]!)}',
                  '件数 ${sorted.length}件',
                ].join('　'),
                style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey800),
              ),
            ]),
          ),
          pw.SizedBox(height: 10),
          if (rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(20),
              child: pw.Text('この期間の記録はありません'),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: ['No', '日付', '用務先', '目的', '区間', '交通機関', '金額'],
              data: rows,
              headerStyle: headerStyle,
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
              cellStyle: cellStyle,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
              border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
              columnWidths: const {
                0: pw.FixedColumnWidth(20),
                1: pw.FixedColumnWidth(58),
                2: pw.FlexColumnWidth(2.2),
                3: pw.FlexColumnWidth(1.8),
                4: pw.FlexColumnWidth(3.4),
                5: pw.FixedColumnWidth(42),
                6: pw.FixedColumnWidth(50),
              },
              cellAlignments: const {
                0: pw.Alignment.center,
                6: pw.Alignment.centerRight,
              },
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            ),
          if (rows.isNotEmpty)
            pw.Container(
              alignment: pw.Alignment.centerRight,
              padding: const pw.EdgeInsets.only(top: 4, right: 3),
              child: pw.Text('合計　${yen(total)}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ),
        ],
      ),
    );

    // 領収書の写真
    if (includeReceipts) {
      for (final t in sorted) {
        for (final l in t.legs) {
          final p = l.receiptPath;
          if (p == null) continue;
          final f = File(p);
          if (!await f.exists()) continue;
          final img = pw.MemoryImage(await f.readAsBytes());
          doc.addPage(pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(32),
            build: (ctx) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('領収書　${DateFormat('yyyy年M月d日').format(t.start)}　${l.mode.label}　${yen(l.fare)}',
                    style: const pw.TextStyle(fontSize: 11)),
                if (t.destination.isNotEmpty)
                  pw.Text('用務先：${t.destination}', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(height: 8),
                pw.Expanded(child: pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain))),
              ],
            ),
          ));
        }
      }
    }

    return doc.save();
  }
}
