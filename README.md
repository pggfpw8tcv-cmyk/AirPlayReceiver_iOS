# AirPlayReceiver_iOS

iPhone/iPadをAirPlay受信機にする開発中のアプリ。SwiftUI + Objective-C++ + UxPlayを使用します。

**現在はミラーリング受信の実装とビルド基盤を追加した段階です。AirPlay 2マルチルーム音声は未実装で、iOS実機の動作確認もまだです。**

## 未署名IPAを生成

GitHub Actionsの **Build unsigned iOS IPA** を実行してください。`main` / `feat/**`へのpush、PR、手動実行に対応しています。
成功した実行のArtifactsから **AirPlayReceiver-unsigned** を取得できます。Appleの証明書やSecretsはビルドに不要です。
未署名IPAのインストールには利用者側で再署名が必要です。

ローカルのMacでは:

```sh
brew install cmake xcodegen
bash scripts/build_ipa.sh
```

成果物は`build/artifacts/AirPlayReceiver-unsigned.ipa`です。

## 含まれる実装

- UxPlayの実際の受信コア、Bonjour発見、PIN認証と永続キー
- H.264サンプルバッファ表示、ALAC/AAC/AAC-ELD音声デコード経路
- 受信開始/停止、全画面表示、音声割り込み処理、診断ログ
- AirPlay 2移植に向けたUDP 319/320の実機ポート診断
- バージョン・ハッシュ固定の依存物、arm64/iPhoneOS/未署名のIPA検査
- Linuxの実コア統合テストとmacOSのiOSビルド・シミュレーターテスト

[実装状況・未対応機能](docs/compatibility.md) / [ビルドと実機試験](docs/development.md) / [設計](docs/superpowers/specs/2026-09-24-ios-airplay-receiver-design.md)

GPL-3.0-or-later。移植元のライセンス・著作権表記は保持しています。[依存物の表記](THIRD_PARTY_NOTICES.md)
