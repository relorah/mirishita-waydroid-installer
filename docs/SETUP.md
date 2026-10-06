# セットアップ・復旧ガイド

本ガイドはMWI v0.1.0向けです。新規構築のみを対象とし、既存Waydroidを検出した場合は停止します。

## 実行前の確認

- CachyOS / Arch Linux、または通常のdnf版Fedora Workstation / KDE Plasma Desktop / Spin
- x86_64 CPU、AMD Radeon GPU、`amdgpu` カーネルモジュール、DRM render node
- Waylandデスクトップセッション
- `sudo` を利用できる通常ユーザー（rootでは実行しない）
- 数GB以上の空き領域と安定したネット接続

Android system/vendorイメージの取得だけで約1.1 GBを使います。イメージの展開領域とキャッシュ領域も必要です。

Fedora Atomic/Silverblue/Kinoite、Intelのみ、NVIDIAのみ、既存Waydroidは対象外です。Ubuntu対応は今後の予定です。

## インストール

```bash
git clone https://github.com/relorah/mirishita-waydroid-installer.git
cd mirishita-waydroid-installer
chmod +x install.sh
./install.sh
```

installerはディストリビューションとCPUアーキテクチャを確認し、同梱 `test_libnb` のSHA-256を検査してから `sudo` による管理者操作を行います。既存Waydroidがある場合、データを消去せず停止します。

## 初回起動

1. WaydroidにAndroidの初回セットアップ画面が出たら完了します。
2. Google Playを開き、自分のGoogleアカウントでログインします。
3. Google Playでミリシタを検索してインストールします。
4. 画面・タッチ・性能調整が必要な場合はMWMを別途利用します。

ミリシタAPKを用意する必要はありません。MWIはAPKの取得やサイドロードを行いません。

## installerが確認すること

- AndroidイメージZIPの読み取りと `system.img` / `vendor.img` の存在
- Waydroid上のAndroid 11起動とPlay Storeパッケージ
- NativeBridge設定が `libnb.so` であること、ARM64 ABIが公開されていること
- Waydroidゲストのデフォルトルート、IPv4疎通、DNS名前解決

Googleアカウントの認証、端末登録、ミリシタのログインやゲーム動作は確認しません。ユーザーアカウントと実機環境での確認が必要です。

## ログと復旧

- MWIの作業・キャッシュ: `${XDG_STATE_HOME:-$HOME/.local/state}/mwi/`
- Waydroid session log: MWI作業ディレクトリの `session.log`
- Waydroid UI log: MWI作業ディレクトリの `full-ui.log`
- Waydroid診断: `waydroid log`

失敗した場合は、キャッシュとログを保持し、止まった工程を記録してください。v0.1.0は途中まで適用したパッケージ、sysctl、ファイアウォール設定を自動ロールバックしません。バックアップと削除の意思がない限り、`/var/lib/waydroid` やユーザーデータを削除しないでください。

## 既知の制限

- Bash構文と同梱ファイルは静的確認済みです。2026-10-06に、CachyOSのRyzen 7 9700X + Radeon RX 6600 XT環境とBC250環境で導入成功の利用者報告を受けています。Arch Linux単体とFedoraの実機導入結果は未確認です。
- Androidイメージは2025-06-28版の固定ファイルです。SourceForge一覧からSHA-256を確認できないため、ZIP整合性と内部ファイル名のみ検査します。
- `waydroid_script` のソースcommitは固定していますが、実行時に取得するPython依存パッケージはバージョン固定していません。
- Fedoraのパッケージ可用性は有効なdnfリポジトリに依存します。MWIはFedoraの追加リポジトリを登録しません。
- Google Playの初回設定や端末登録が必要となる場合があります。
- Fedoraでのファイアウォール・SELinux処理はベストエフォートで、各Fedoraリリースでの実機確認が必要です。
- installerはホストパッケージ、sysctl、ファイアウォール、Waydroid system overlayを変更する場合があります。必要なら実行前に `install.sh` を確認してください。
