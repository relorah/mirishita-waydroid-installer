# Mirishita Waydroid Installer (MWI) 0.2.2

CachyOS / Arch Linux / Fedora + Waydroid Android 11環境で「アイドルマスター ミリオンライブ！ シアターデイズ（ミリシタ）」の動作環境を構築します。必要なホストパッケージを確認し、システム更新と併せて導入します。

## 対応環境

- x86_64、AMD Radeon（`amdgpu`）
- CachyOS / Arch Linux
- dnf版Fedora（KDE Plasmaを含む、実機未検証。Kinoiteなどrpm-ostree版は対象外）
- Wayland

## テスト環境

- AMD Ryzen 7 9700X + Radeon RX 6600 XT
- AMD BC250

インストーラーはCachyOSで実行済み。今回追加したWaydroidネットワークFixとFedora対応は実機未確認です。

## 使い方

x86_64・AMD GPU・Wayland・binderfs対応カーネル・sudo権限が必要です。
ZIPを展開し、`mirishita-waydroid-installer`内で通常ユーザーとして実行します。

```bash
chmod +x install.sh
./install.sh
```

既存Waydroidがあれば、診断・修復・退避して新規導入を選べます。

## 導入内容

新規導入はAndroid 11 GAPPS（2025-06-28版）。Houdiniは固定コミットのwaydroid_scriptから取得し、同梱libnbとNativeBridge設定を適用します。

ネットワークはDHCP・route・DNS・forwarding・NAT・HTTPSを確認し、必要に応じて再起動・route補完・UFW転送許可を行います。firewalldでは確認後に`waydroid0`のみ実行中のtrusted zoneへ追加します（Androidからホストへの通信も許可、firewalld再起動で解除）。既存の独自zone・nftablesルールは上書きしません。

**背景化時はAndroid sessionが停止します。** route補完は現在の起動中のみ有効で、追加したUFWルールは復元対象外です。

## 修復・復元

- `./install.sh --diagnose`：診断
- `./install.sh --repair`：Android 11環境のHoudini・libnb修復とネットワーク確認
- `./install.sh --reset`：既存環境を退避して新規導入（`RESET_WAYDROID=1 ./install.sh`も同じ）
- `./install.sh --restore BACKUP`：修復前の設定・overlayを復元

reset後はゲーム・ログイン状態を引き継ぎません。resetの退避は`--restore`の対象外です。
バックアップは`/var/lib/mwi/backups/`、ログは通常`~/.local/state/mwi/logs/`に保存します。

## 出典

[mogareta7731氏](https://zenn.dev/mogareta7731/articles/f502aac11bb8ae)が配布したAndroid-x86 ISOに同梱されていたパッチ済み`test_nb`を、バイナリ・LICENSEとも無改変で使用しています。元プロジェクトは[qwerty12356-wart氏のtest_libnb](https://github.com/qwerty12356-wart/test_libnb)、BSD 2-Clauseです。MWI本体はMIT Licenseです。
両氏および[Waydroid](https://github.com/waydroid/waydroid)・[waydroid_script](https://github.com/casualsnek/waydroid_script)の作者・貢献者に感謝します。
