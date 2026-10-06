# Mirishita Waydroid Installer（MWI）

MWIは、AMD Radeon搭載のx86_64 Linux PCに、Google Playを利用できるWaydroid Android 11環境を新規構築するインストーラです。ホスト側の依存パッケージ、Android 11 + GAppsイメージ、第三者ツール `waydroid_script` 経由のHoudini、MWI用 `test_libnb`、Waydroidのネットワーク設定を用意します。

**MWIはミリシタのAPKを同梱・要求・取得・インストールしません。** セットアップ完了後、ユーザー自身がGoogle Playからインストールしてください。

## v0.1.0の対応環境

- CachyOS / Arch Linux
- dnf版Fedora（Workstation、KDE Plasma Desktop、通常のSpin）
- x86_64、AMD Radeon GPU（`amdgpu`）、DRM render node
- Waylandデスクトップセッション
- Waydroidの新規インストール

Ubuntuは今後の対応予定です。Intelのみ、NVIDIAのみ、Fedora Atomic/Silverblue/Kinoiteは対象外です。既存Waydroid環境を検出すると処理を停止し、データをリセット・削除しません。

本版は初期公開版です。スクリプト構文とパッケージの静的検証に加え、利用者から以下のCachyOS環境で導入テストを行い、問題なくインストールできたとの報告を受けています（2026-10-06）。

| OS | ハードウェア | 導入結果 |
|---|---|---|
| CachyOS | Ryzen 7 9700X + Radeon RX 6600 XT | 導入成功（利用者報告） |
| CachyOS | BC250 | 導入成功（利用者報告） |

Arch Linux単体とFedoraの実機導入結果は未確認です。この記録は導入成功の報告であり、個別のゲーム動作や全機能の確認結果を示すものではありません。[既知の制限](docs/SETUP.md#既知の制限)も確認してください。

## インストール

対応Linux PCのターミナルで、通常ユーザーとして実行します。`sudo` でinstaller自体を起動しないでください。

```bash
git clone https://github.com/relorah/mirishita-waydroid-installer.git
cd mirishita-waydroid-installer
chmod +x install.sh
./install.sh
```

Androidイメージの取得に約1.1 GBかかり、展開分と作業用キャッシュの空き容量も必要です。安定したインターネット接続を用意してください。セットアップ後、Waydroidの初回設定を完了し、自分のGoogleアカウントでPlay Storeにログインしてミリシタをインストールします。

Androidの言語がデフォルトの英語のままだとGoogle Playにログインできず、AndroidのSettings（設定）から言語を日本語に変更した後、ログインできたという利用者報告があります。再現性と原因は不明です。必須の設定や確実な解決策ではありませんが、同じ症状が出た場合の対処例として参考にしてください。

詳しくは[セットアップ・復旧ガイド](docs/SETUP.md)を参照してください。

## MWIの担当範囲

- `pacman` または `dnf` でホスト側パッケージを導入
- 固定したAndroid 11 system/vendorイメージをSourceForgeから取得し、ZIP整合性と必要なイメージファイルを確認
- Waydroidを初期化し、Android 11とPlay Storeを確認
- `install.sh`に記録したcommitの `casualsnek/waydroid_script` を取得し、Android 11向け `libhoudini` の導入を依頼
- 同梱の32-bit/64-bit `libnb.so` をWaydroid overlayへ配置し、NativeBridgeとARM64 ABIを設定・確認
- IPv4 forwardingと、利用中のUFW/firewalldに応じたWaydroidネットワーク設定
- Waydroid UIを起動し、可能ならGoogle Playを前面に表示

Houdini本体はMWIに含めず、セットアップ時に `waydroid_script` が取得します。このパッケージ方法の説明は、第三者ソフトのライセンスや利用可否について法的結論を示すものではありません。

画面表示、タッチ、解像度、フレームレート、性能調整はMWIの範囲外です。MWIはWaydroidの基盤を構築し、MWMは別の実行・表示・性能管理ツールとして動作します。

## 再現性と検証

- Androidイメージはファイル名と取得URLを固定し、ZIP整合性と内部ファイルを確認します。参照したSourceForge一覧にSHA-256値が公開されていないため、暗号学的な配布元検証は行いません。
- `waydroid_script` はcommit `48dbfaf34a6ddbe78688c530f9ba1c26522aafb2` に固定しています。
- `test_libnb` のバイナリはinstaller内のSHA-256値で検査し、一覧を [`test_libnb/SHA256SUMS`](test_libnb/SHA256SUMS) に記録しています。
- ミリシタAPKは含まれず、ユーザーがGoogle Playから導入します。

## ライセンスと注意事項

MWI作成部分にはルートの[`LICENSE`](LICENSE)が適用されます。`test_libnb`には個別のGPL-2.0-or-later/BSD-2-Clause帰属とライセンス条件があります。詳細は[`NOTICE`](NOTICE)と[ライセンス・出典の説明](docs/LICENSING.md)を確認してください。

Waydroid、LineageOS、Google Play、Houdini、ミリシタ、各ディストリビューションは第三者の製品・商標です。MWIは独立したプロジェクトで、各権利者との提携・推奨関係を示すものではありません。取得・利用する第三者ソフトやサービスの条件は、利用者が確認してください。
