# CLAUDE.md

## 概要

「運賃記録」：公共交通（電車・バス）とタクシーの移動を記録し、交通費精算書PDFを作る個人用アプリ。Flutter（iOS / Android 共通）、パッケージ名 `fare_log`、アプリID `app.farelog.fare_log`。

- ユーザーへの説明、UI文言、コードコメント、コミットメッセージは日本語。
- Flutter 3.50 では Material が `package:material_ui/material_ui.dart` に分かれている。`flutter/material.dart` ではなくこちらを import する。

## ビルド

- APK と iOS（署名なし）は GitHub Actions でビルドする。push 後は Actions の結果まで確認する。
- `flutter analyze` と `flutter test`（`test/logic_test.dart`：締め期間・IC履歴の解析・PDF作成）は CI でも実行する。
- リリースのたびに `pubspec.yaml` の `version` を上げる。
- Android の署名鍵 `android/app/farelog.jks` とパスワードは、上書きインストールのため意図的にリポジトリに置いている。

## 構成（lib/）

- `models.dart`：Trip（移動）／Leg（乗り物1回分）／Settings。保存は `store.dart` が JSON ファイルで行う。
- `tracker.dart`：geolocator で現在地とルートを記録する。Android はフォアグラウンドサービス、iOS はバックグラウンド位置更新。
- `places.dart`：近くの駅・バス停を探す。駅は HeartRails Express と Overpass API（OpenStreetMap）に同時に問い合わせる。バス停は Overpass が不安定なため、`busstops.dart` の内蔵データ（`assets/busstops.tsv.gz`、国土数値情報 P11 を `tool/build_busstops.py` で変換、約28万件）から通信なしで探す。
- `felica.dart`：nfc_manager で交通系ICカードの履歴（サービスコード 0x090F）を読み、運賃を残額の差から求める。駅コードを駅名にする表は持っていない。iOS は Info.plist の FeliCa システムコード `0003` と NFC の entitlements が必要。
- `period.dart`：締め期間（1日〜月末／16日〜翌月15日）。
- `pdf_report.dart`：交通費精算書PDF。フォントは `assets/fonts` の BIZ UDゴシック。
- `screens/`：記録（home）、移動の編集（trip_edit）、IC取り込み（ic_import）、一覧（history）、PDF（report）、設定（settings）。
