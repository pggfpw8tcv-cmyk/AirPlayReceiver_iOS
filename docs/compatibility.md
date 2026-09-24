# 互換性・実装状況

2026-09-24。ビルド成功、コードの存在、実機での再生成功を区別する。

| 機能 | 現在の状態 | 合格に必要な確認 |
| --- | --- | --- |
| UxPlayコア | 固定版の実コードを静的ライブラリ化。LinuxコンパイルとRTSP OPTIONS・再起動試験成功 | iOSでのペアリング・SETUP・メディア受信 |
| Bonjour | NSNetServiceで両サービスを公開、公開失敗をUIに通知 | ローカルネットワーク許可拒否/許可、送信機の一覧表示 |
| PIN・鍵保存 | 上流PIN処理とアプリ内の永続キー/登録クライアント保存を接続 | 初回PIN・2回目接続・アプリ再起動 |
| H.264ミラーリング | Annex B→CoreMedia→AVSampleBufferDisplayLayerを実装 | iPhone/iPad/Macそれぞれで画面・回転・30分連続再生 |
| HEVC | デコード経路はあるが、能力ビットは検証まで無効 | 対応端末でパラメーター変更と再生 |
| ALAC/AAC/AAC-ELD | AudioConverter→AVAudioEngineを実装 | 特にAAC-ELD cookie受理・音切れ・同期精度を確認 |
| 映像音声同期 | ローカル時刻をホスト時刻へ変換し再生時刻を指定 | 実測差100ms以内。ドリフト補正は未実装 |
| PTP | IPv4 UDP 319/320の排他的bindを試す診断を実装 | 実機bind、PTPパケット受信、クロック追従 |
| AirPlay 2 realtime/buffered音声 | **未実装**。Shairport Syncの移植調査を実施 | ペアリング、暗号化制御、両ストリームの受信 |
| AirPlay 2マルチルーム | **未実装** | NQPTP相当の同期、実出力時刻、リサンプリング、別受信機との共通収録 |
| HLS/写真/DRM映像 | 未実装・非広告 | 各プロトコルと必要権限の実機調査 |
| Home登録/AWDL/多チャンネル | 未実装・非広告 | 上流とiOS側の条件調査 |
| バックグラウンド音声 | audioモード宣言と割り込み時の停止を実装 | 画面ロック・前面復帰。常時待受は保証しない |
| 未署名IPA | 生成・検査スクリプトとActionsを実装 | GitHub上のmacOSジョブ実行成功 |

## AirPlay 2を阻む具体的な移植箇所

UxPlayはAirPlay 2マルチルーム音声に対応していない。Shairport Syncの
`AIRPLAY2.md`はNQPTPによるUDP 319/320の排他的利用を要求し、macOSでは
システムとの競合があると記載している。iOSでの可否はまだ測定していない。
bind成功だけでは、PTP通信や同期ができるとは判定しない。

調査したShairport Syncはアプリ組込ライブラリではなく、プロセス全体の終了、
シグナル、グローバル設定、別プロセスのNQPTP共有メモリを使用する。
AirPlay 2有効時にはFFmpeg、libgcrypt、libsodium、pair_ap、libconfig等にも依存する。
`main()`を名前変更してスレッド起動するだけではiOSの安全な停止・再起動を実現できない。

残る実装は、プロセス用処理の分離、pair_apを含む認証と暗号化制御接続、
realtime/bufferedストリーム、NQPTPのアプリ内時刻共有、Core Audioの実出力時刻に基づく
ドリフト補正、UxPlayとの単一識別情報・サービス広告の統合である。
現在のバイナリにShairport Sync/NQPTPはリンクしていない。

## 実機試験の記録形式

送信端末・OS / 受信端末・OS / 送信アプリ / 署名方式 / 接続方法 / codec /
PIN結果 / 30分再生結果 / A/V差 / 同期相手と出力差 / ログ / 試験日を記録する。
現時点で実機成功の記録はない。

上流資料:
- https://github.com/FDH2/UxPlay
- https://github.com/mikebrady/shairport-sync/blob/master/AIRPLAY2.md
- https://github.com/mikebrady/nqptp
