# EveryTMP 保守メモ

このファイルは公開物(README/紹介サイト)には出さない保守向け情報を集約する。
(common rules ルール6: 対象リポジトリの `main` 直下に `{リポジトリ名}.md` で集約)

## バージョンアップ時に更新すべき箇所

| 箇所 | 内容 |
| --- | --- |
| `scripts/build-app.sh` | `VERSION` のデフォルト値 |
| `Sources/EveryTMP/Settings.swift` | `allowedIntervals`・既定モード・既定間隔を変更した場合（`LogicTests.testAllowedIntervalsUnchanged` も同時更新） |
| `Sources/EveryTMP/SMCService.swift` | `SMCKeys` の候補キー・`isPlausibleDieTemp` の範囲を変更した場合（`smc.c` のゲートと同時更新、両方のテストも更新） |
| `Resources/ja.lproj/Localizable.strings` / `en.lproj` | UI文言を追加した場合は **両方必ず** 更新（`LogicTests.testLocalizableStringsParity` の `expectedKeysUsedInCode` も同時更新） |
| `Tests/EveryTMPTests/LogicTests.swift` | 仕様変更時（表示丸め・max縮退・スナップ規則など） |
| `README.md` / 紹介サイト | バージョン・機能一覧・スクリーンショット |
| `Sources/CSMCShim/smc.c` | SMC読み取り手順・デコード・ plausibility ゲートの変更時 |

## 実装の前提と安全設計（変更時の注意）

- 読み取り専用: C shimに書き込み経路を作らないこと（ファン制御等は対象外。書き込みは特権ヘルパーが必要になり軽量・安全方針と衝突する）
- `DisplayMode` のraw値はUserDefaultsに永続化されているため **renumber禁止**（テストで固定）
- 読み取り経路に `fatalError`・強制unwrap・`try!` を置かないこと（`--probe` の `try!` はテスト用リソース読み込みのみで本番経路ではない）
- ポーリングは最短1秒・1回あたり数msのSMC読みが上限。常駐スレッド・ファイルログ・無制限キャッシュを追加しないこと
- SMC接続の自己回復（全滅3回連続→close+reopen）は `TemperatureMonitor.failuresBeforeReconnect` に集約。値を変える場合は長期稼働テストと同時に実施すること
- plausibility下限10.0°Cは駐車センサー番兵値（約4.633/約6.700）の除外が目的。寒冷地の正当な低温と衝突しないかは実機報告があれば見直す

## 実機検証の記録

- 2026-10-16 / macOS 26.4 / Apple M3 Ultra（Mac15,14）/ v1.0.0(build 1):
  - `swift build` 成功（警告0）。`swift test` 18件全緑（表示丸め・max縮退・間隔スナップ・キー表・妥当性ゲート・日英parity・メニュー配線の実発火）
  - `--probe` で全候補キーを実読: CPU `TCMz`=62.69°C（ビルド負荷時）/ GPU `TRDX`=39.44°C。Intel世代キー（TC0P/TC0D/TG0D/TG0P/Tg0e）は不在で自動スキップ
  - **重要所見**: M3 Ultraの温度キーは型 `flt`（ネイティブ順float）。当初実装のbig-endianデコードでは0.4°C等の誤値を出すことを検出し、MacMonitor準拠のmemcpyデコードへ修正済み（設計判断として記録）
  - **重要所見2**: 駐車中センサーは約4.6/約6.7°Cの番兵値に加え `Ta0x` 系がちょうど10.00°Cにclampされることを全キー走査（3369キー）で確認。妥当性下限を排他的 `>10.0` にして除外
  - メニューバーに `43°C` 表示をスクリーンショットで目視確認（日本語ロケール）
  - `leaks` で 0 leaks、physical footprint peak 11.5M を確認
  - DMG `EveryTMP-1.0.0.dmg`（`hdiutil verify` VALID）＋ `.sha256` 添付でGitHub Release `v1.0.0` を正式版として公開。ad-hoc署名、`codesign --verify --strict` 通過

## 既知の未検証項目

- Intel Macでの表示（`--°C` 縮退の実機確認は未実施。コード上は全失敗→`--°C` でクラッシュしない設計）
- M1/M2/M4/M5各世代でのキー到達性（`TCMz`/`TRDX` は世代非依存のホットスポットキーとして選定。世代別per-coreキー不使用のため到達性は高い見込みだが、世代ごとの `--probe` 報告を歓迎）
- 1年連続稼働の実証（設計上の手当て: 再接続自己回復・メニュー再構築・Timer破棄・SMC close・ログ無蓄積。実証はリリース後の長期利用報告で確認）

## 今後の開発予定

- 1.1: メニューバーアイコン（温度帯による色分け表示のON/OFF。既定は現状の単色テキストのまま）
- 1.2: 通知センター・ウィジェット対応の検討（OS標準Widgetのみ。常駐プロセス増設はしない方針）
- 2.0: Appleが温度取得の公開APIを追加した際のSMC直読からの移行 — `SMCService` 境界で差し替え可能なため `TemperatureMonitor` 以上には影響させない

## リリース手順

1. `VERSION=x.y.z BUILD=n scripts/build-app.sh`（`BUILD_DMG=1` でDMG＋.sha256も生成）
2. `swift test` を通す
3. 実機で `--probe` とメニュー動作（3モード・4間隔・診断ウィンドウ）を確認
4. git tag `vx.y.z` を付けてpush
5. `gh release create vx.y.z` でDMG＋.sha256を添付、リリースノートに ad-hoc署名/未公証 である旨とGatekeeperの許可手順を必ず記載

## 紹介サイト

- `oriyu90/studio-rizi` の `website/projects/everytmp/`（4言語: ja/en/zh/pt）
- slug: `everytmp`（変更禁止）
- 更新時は studio-rizi ルートで `npm run build && npm run validate && npm run count-files` を実行してからpush
