// 交通系ICカード（Suica・PASMO・ICOCA など）の利用履歴を読む
//
// 履歴はサービスコード 0x090F（暗号化なしで読める）に新しい順で最大20件入っている。
// 1件16バイト：
//   [0] 機器種別  [1] 利用種別  [2] 支払種別  [3] 入出場種別
//   [4-5] 日付（年7bit・月4bit・日5bit）
//   [6-7] 入場駅（線区・駅順）／バスは事業者・停留所
//   [8-9] 出場駅
//   [10-11] 残額（リトルエンディアン）
//   [12-14] 連番  [15] 地域
// 運賃＝1つ古い履歴の残額 − この履歴の残額。
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import 'models.dart';

enum IcKind {
  train('電車'),
  bus('バス'),
  charge('チャージ'),
  shopping('物販'),
  other('その他');

  const IcKind(this.label);
  final String label;

  TransportMode? get mode => switch (this) {
        IcKind.train => TransportMode.train,
        IcKind.bus => TransportMode.bus,
        _ => null,
      };
}

class IcHistory {
  IcHistory({
    required this.key,
    required this.date,
    required this.kind,
    required this.balance,
    required this.amount,
    required this.inCode,
    required this.outCode,
  });

  /// カードID＋連番（取り込み済みかどうかの判定に使う）
  final String key;
  final DateTime date;
  final IcKind kind;
  final int balance;

  /// 支払額（チャージは入金額）。最も古い履歴は計算できないので null
  final int? amount;

  /// 入場・出場駅のコード（駅名の表は持っていないので、参考表示のみ）
  final int inCode;
  final int outCode;

  bool get isFare => kind == IcKind.train || kind == IcKind.bus;
}

class IcCardResult {
  IcCardResult(this.idm, this.history);
  final String idm;
  final List<IcHistory> history;
}

class FeliCaReader {
  static const _serviceHistory = 0x090F;

  static Future<bool> available() async {
    try {
      return await NfcManager.instance.checkAvailability() == NfcAvailability.enabled;
    } catch (_) {
      return false;
    }
  }

  /// カードをかざすのを待って、履歴を読む
  static Future<IcCardResult> read() {
    final c = Completer<IcCardResult>();
    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso18092},
      alertMessageIos: 'ICカードを iPhone の上部に当ててください',
      onSessionErrorIos: (e) {
        if (!c.isCompleted) c.completeError(Exception(e.message));
      },
      onDiscovered: (tag) async {
        try {
          final r = await _readTag(tag);
          await NfcManager.instance.stopSession(alertMessageIos: '読み取りました');
          if (!c.isCompleted) c.complete(r);
        } catch (e) {
          await NfcManager.instance.stopSession(errorMessageIos: '読み取れませんでした');
          if (!c.isCompleted) c.completeError(e);
        }
      },
    );
    return c.future;
  }

  static Future<void> cancel() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  static Future<IcCardResult> _readTag(NfcTag tag) async {
    final blocks = <Uint8List>[];
    String idm;
    if (Platform.isIOS) {
      final f = FeliCaIos.from(tag);
      if (f == null) throw Exception('交通系ICカードではないようです');
      idm = _hex(f.currentIDm);
      final svc = Uint8List.fromList([_serviceHistory & 0xFF, _serviceHistory >> 8]);
      for (var i = 0; i < 20; i++) {
        final r = await f.readWithoutEncryption(
          serviceCodeList: [svc],
          blockList: [Uint8List.fromList([0x80, i])],
        );
        if (r.statusFlag1 != 0 || r.blockData.isEmpty) break;
        blocks.add(r.blockData.first);
      }
    } else {
      final f = NfcFAndroid.from(tag);
      if (f == null) throw Exception('交通系ICカードではないようです');
      final id = f.tag.id;
      idm = _hex(id);
      for (var i = 0; i < 20; i++) {
        final cmd = BytesBuilder()
          ..addByte(0) // 長さ（あとで埋める）
          ..addByte(0x06) // Read Without Encryption
          ..add(id)
          ..addByte(1) // サービス数
          ..addByte(_serviceHistory & 0xFF)
          ..addByte(_serviceHistory >> 8)
          ..addByte(1) // ブロック数
          ..addByte(0x80)
          ..addByte(i);
        final bytes = cmd.toBytes();
        bytes[0] = bytes.length;
        final res = await f.transceive(bytes);
        // 応答：[長さ][0x07][IDm×8][SF1][SF2][ブロック数][データ16]
        if (res.length < 29 || res[1] != 0x07 || res[10] != 0) break;
        blocks.add(Uint8List.sublistView(res, 13, 29));
      }
    }
    if (blocks.isEmpty) throw Exception('履歴を読めませんでした（交通系ICカードか確認してください）');
    return IcCardResult(idm, parse(idm, blocks));
  }

  /// 16バイトの履歴ブロックを解析する（新しい順のまま返す）
  static List<IcHistory> parse(String idm, List<Uint8List> blocks) {
    final out = <IcHistory>[];
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.length < 16 || b.every((x) => x == 0)) continue;
      final d = (b[4] << 8) | b[5];
      final date = DateTime(2000 + (d >> 9), (d >> 5) & 0x0F, d & 0x1F);
      final balance = b[10] | (b[11] << 8);
      final seq = (b[12] << 16) | (b[13] << 8) | b[14];
      final kind = _kind(b[0], b[1]);
      int? amount;
      if (i + 1 < blocks.length && !blocks[i + 1].every((x) => x == 0)) {
        final prev = blocks[i + 1][10] | (blocks[i + 1][11] << 8);
        amount = (kind == IcKind.charge) ? balance - prev : prev - balance;
      }
      out.add(IcHistory(
        key: '$idm-$seq',
        date: date,
        kind: kind,
        balance: balance,
        amount: amount,
        inCode: (b[6] << 8) | b[7],
        outCode: (b[8] << 8) | b[9],
      ));
    }
    return out;
  }

  static IcKind _kind(int terminal, int usage) {
    final u = usage & 0x7F;
    if (u == 0x02 || u == 0x14 || u == 0x15 || u == 0x1F || u == 0x07 || u == 0x08) {
      return IcKind.charge;
    }
    if (u == 0x0D || u == 0x0F || terminal == 0x05) return IcKind.bus;
    if (u >= 0x46 && u <= 0x4B) return IcKind.shopping;
    if (terminal == 0xC7 || terminal == 0xC8) return IcKind.shopping;
    if (u == 0x01 || u == 0x03 || u == 0x04 || u == 0x05 || u == 0x06 || u == 0x0B || u == 0x11 || u == 0x12) {
      return IcKind.train;
    }
    return IcKind.other;
  }

  static String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
