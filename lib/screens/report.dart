// PDFのプレビュー・印刷・共有
import 'package:material_ui/material_ui.dart';
import 'package:printing/printing.dart';

import '../main.dart';
import '../pdf_report.dart';
import '../period.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key, required this.period});
  final Period period;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  bool _receipts = true;

  @override
  Widget build(BuildContext context) {
    final p = widget.period;
    final trips = store.trips.where((t) => !t.isRecording && p.contains(t.start)).toList();
    final hasReceipts = trips.any((t) => t.legs.any((l) => l.receiptPath != null));
    final s = store.settings;
    return Scaffold(
      appBar: AppBar(title: Text('交通費精算書 ${p.title}')),
      body: Column(children: [
        if (s.name.isEmpty || s.department.isEmpty)
          MaterialBanner(
            content: const Text('氏名・所属が未設定です。「設定」タブで入力するとPDFに載ります。'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('戻る'))],
          ),
        if (hasReceipts)
          SwitchListTile(
            title: const Text('領収書の写真を付ける'),
            value: _receipts,
            onChanged: (v) => setState(() => _receipts = v),
          ),
        Expanded(
          child: PdfPreview(
            key: ValueKey(_receipts),
            build: (format) => PdfReport.build(period: p, trips: trips, settings: s, includeReceipts: _receipts),
            pdfFileName: '交通費精算書_${p.end.year}${p.end.month.toString().padLeft(2, '0')}.pdf',
            canChangePageFormat: false,
            canChangeOrientation: false,
            canDebug: false,
            allowPrinting: true,
            allowSharing: true,
          ),
        ),
      ]),
    );
  }
}
