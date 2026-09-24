# ビルドと検証

## macOS / iOS

Xcode 16.4、CMake、Python 3.12以上、XcodeGen 2.42以上を使用する。
Actionsはmacos-15のXcode 16.4を明示的に選択する。

```sh
brew install cmake xcodegen
export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
bash scripts/build_ipa.sh
bash scripts/test_simulator.sh
```

未署名IPA: `build/artifacts/AirPlayReceiver-unsigned.ipa`。
ZIP内には`Payload/Receiver.app`が入り、署名情報・プロビジョニングは含まない。
インストールには利用者側で有効な署名とプロビジョニングを付与する。
Xcodeで端末実行する場合は生成プロジェクトを開き、自分のBundle ID/Teamと署名設定を指定する。
プロジェクト既定の`CODE_SIGNING_ALLOWED=NO` / `CODE_SIGNING_REQUIRED=NO`は端末実行用に変更する。

`project.yml`がプロジェクト定義の正本。生成したxcodeprojはコミットしない。
依存物は`.deps/src`、SDK別の静的ライブラリは`.deps/iphoneos`と`.deps/iphonesimulator`。
デスクトップのGStreamer、ALSA、Homebrew版OpenSSLをiOSアプリへリンクしない。
ソースアーカイブはSHA-256検査後に展開する。

## Linuxで可能な検証

```sh
python3 scripts/fetch_dependencies.py
cmake -S . -B build/tests -DRECEIVER_BUILD_UPSTREAM=ON
cmake --build build/tests --parallel 4
ctest --test-dir build/tests --output-on-failure
python3 -m unittest discover -s Tests -p 'test_*.py'
```

システムのC/C++コンパイラ、CMake、OpenSSL開発ヘッダーが必要。
socketを禁じるサンドボックスではCTestのポート/RTSP試験が失敗するため、
ローカルUDP/TCPの許可された環境で実行する。

`upstream_tests`は実際のUxPlayを起動し、ループバックTCPでRTSP OPTIONSの成功と
受信機の再起動を検証する。発見サービスだけを試験用バックエンドに差し替え、
LANにテスト用受信機を広告しない。

## 実機での優先試験

1. 再署名してインストールし、受信開始。ローカルネットワークへのアクセスを許可する。
2. 同じWi-Fiの送信端末で受信名が表示されること、PIN認証、映像・音声を確認する。
3. 停止→再開始、回転、Wi-Fi断、音声出力切替、画面ロックを確認する。
4. 「AirPlay 2同期ポートを診断」を押し、結果と端末/OS/署名条件を記録する。
5. `docs/compatibility.md`に実測結果を記録する。ポート成功をAirPlay 2再生成功と扱わない。

音声再生時刻と映像のPTSは同じホスト時計を基準にする。キュー上限は映像4アクセスユニット、
入力音声96パケット、スケジュール済み音声96バッファ。過負荷時に無制限に蓄積しない。
停止開始時に世代番号を更新し、旧世代のキューを破棄する。上流スレッドが終了するまで
新たな受信開始を受け付けない。

## 制約

上流にはassert/exitを含む箇所が残る。すべてのネットワーク入力に対する堅牢性監査や
ファジングは完了していない。ネットワーク権限、AAC-ELD cookie、バックグラウンド動作、
マルチルームの実出力同期はシミュレーターだけでは確定できない。
