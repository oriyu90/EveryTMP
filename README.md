# EveryTMP（エブリー・ティーエムピー）

Apple Silicon MacのCPU/GPU温度をメニューバーに `xx°C` と表示する、軽量なメニューバー常駐アプリです。

A lightweight menu-bar app for Apple Silicon Macs that shows the CPU/GPU temperature as `xx°C` right in the menu bar.

- Author: Yuki_Orita（折田悠希 / おりたゆうき）
- License: MIT（`LICENSE` 参照）
- Repository: https://github.com/oriyu90/EveryTMP
- 開発者公式サイト: https://studio-rizi.pages.dev/
- X(旧Twitter): https://x.com/InovateofRIZI
- コミュニティDiscord（バグ報告・告知用）: https://discord.gg/x7KXhNTD8M

## 機能 / Features

- メニューバーに現在の温度を `42°C` のように常時表示（日本語・英語完全対応UI）
- 表示対象の切替: **CPU** / **GPU** / **高い方**（CPUとGPUのうち高い方を表示）
- 更新間隔の切替: 1秒 / 2秒（既定） / 5秒 / 10秒
- ログイン時に開く（macOS標準の仕組みを使用）
- 診断ウィンドウ（取得元SMCキー・接続状態・システム情報を表示、`--probe` CLIでも取得可）
- 軽量・単一プロセス・ドック非表示・特権デーモンなし・管理者権限不要・ネットワーク通信なし

## 動作環境 / Requirements

- Apple Silicon搭載Mac（M1/M2/M3/M4/M5シリーズ）
- macOS 13 Ventura以降（macOS 26/27での動作を実機確認）
- Intel Macでは温度を取得できない場合 `--°C` と表示します（クラッシュしません）

## インストール / Install

1. [Releases](https://github.com/oriyu90/EveryTMP/releases) から最新の `EveryTMP-x.y.z.dmg` をダウンロードします
2. DMGを開き、`EveryTMP` を `Applications` フォルダにドラッグします
3. 初回起動時にGatekeeperのダイアログが出たら **「キャンセル」** を押し、**「システム設定 → プライバシーとセキュリティ」** の一番下にある **「開く」** をクリックします（2回目のダイアログでも「開く」）。これはApple Developer Programに未加入のため **ad-hoc署名・未公証** で配布しているためで、macOSが記憶するため次回以降は不要です

> 注意: 本アプリはad-hoc署名（`codesign --sign -`）・未公証の配布です。「Developer ID署名済み」「公証済み」ではありません。

## 使い方 / Usage

- メニューバーの `xx°C` をクリックするとメニューが開きます
- 「表示する温度」で CPU / GPU / 高い方 を切り替えます
- 「更新間隔」で 1/2/5/10秒 を切り替えます
- 「ログイン時に開く」で自動起動のON/OFFを切り替えます
- 「診断情報を表示…」で取得元キーや接続状態を確認できます

## 仕組み / How it works

温度はSMC（System Management Controller）から直接読み取ります（`powermetrics` のような管理者権限も、常駐デーモンも不要な読み取り専用アクセスです）。

- CPU: `TCMz`（CPUダイ・ホットスポット。TG Proの「CPU Die (Hotspot)」と同一の読み値）を最優先し、`TCMb`→`TCDX`→`TCHP`→`TC0P`→`TPMP` の順にフォールバック
- GPU: `TRDX`（GPUダイ・ホットスポット）を最優先し、`TG0D`→`TG0P`→`Tg0e` の順にフォールバック
- 読み取れないキー（そのMacに存在しない・将来のSoCで名称変更など）は自動でスキップし、すべて失敗した場合は `--°C` と表示します
- 駐車中センサーの番兵値（約4.6°C/約6.7°C）や範囲外の値は除外します
- キー選定の根拠: MacMonitor `SENSORS.md`（M2実測＋mactop相互検証）のCPU/GPUドメイン分類。SMCアクセスの実装パターンはMacFanControl（いずれもMITライセンス）を参考に再実装しています

## ビルド / Build

```bash
swift build -c release --arch arm64
swift test
VERSION=1.0.0 BUILD=1 scripts/build-app.sh        # dist/EveryTMP.app
VERSION=1.0.0 BUILD=1 BUILD_DMG=1 scripts/build-app.sh  # + DMGと.sha256
```

診断用の1回読み取り（アプリを起動せずにSMCを確認できます）:

```bash
swift run EveryTMP --probe
```

## プライバシー / Privacy

- ネットワーク通信を行いません。温度データがMacの外に出ることはありません
- 設定はお使いのMacのUserDefaultsにのみ保存します
- ファイルログや一時ファイルを作成しません

## English summary

EveryTMP is a lightweight, single-process, Dock-less menu-bar app for Apple Silicon Macs. It reads CPU/GPU die temperatures straight from the SMC (read-only, no admin rights, no daemon, no network) and shows `xx°C` in the menu bar. You can switch between CPU, GPU, or the higher of the two, with refresh intervals of 1/2/5/10 seconds. The UI is fully localized in Japanese and English. Distributed ad-hoc signed and unnotarized (no paid Apple Developer account), so the first launch needs a one-time approval in System Settings → Privacy & Security.
