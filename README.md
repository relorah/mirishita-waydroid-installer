# Mirishita Waydroid Installer (MWI) 0.2.5

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
配布ZIP `MWI_0.2.5.zip` を展開し、`MWI_0.2.5/` 内で通常ユーザーとして実行します（ディレクトリ名は `MWI_[ver]` 形式）。

```bash
cd MWI_0.2.5
chmod +x install.sh
./install.sh
```

既存Waydroidがあれば、1: 診断、2: Houdini・libnb修復、3: 全環境退避して新規導入、4: 上書き再インストール（データも初期化）、0: 終了を選べます。
変更前の確認はすべて `[y/N]` 表示です。続行する場合は `y` または `Y` を入力してください。空入力やそれ以外の入力では拒否します（必須操作は中止、任意のUFW例外は追加せず続行）。

## 配布ZIPの生成

リポジトリ内で `python3 tools/build_zip.py` を実行すると、READMEの版番号に合わせた `dist/MWI_0.2.5.zip` を生成します。ZIP内のトップディレクトリは `MWI_0.2.5/` です。GitHubの自動生成ソースZIPはこの配布ZIPとは異なります。

## 導入内容

新規導入はAndroid 11 GAPPS（2025-06-28版）。Houdiniは固定コミットのwaydroid_scriptから取得し、同梱libnbとNativeBridge設定を適用します。

ネットワークはDHCP・route・DNS・forwarding・NAT・HTTPSを確認し、必要に応じて再起動を行います。UFW例外は任意で、インストール・修復時にUFWがactiveかつ必要ルールが不足している場合のみ `Waydroid用のUFW例外を追加しますか [y/N]` と確認します。`y` / `Y` の場合のみ不足するDHCP UDP/67・DNS UDP/TCP 53・転送許可を追加し、`n` / Enterなら変更せず続行します。同じ実行中の再確認や既存ルールの重複追加は行わず、他のUFW設定は変更しません。拒否後にネットワーク検証が失敗した場合は、DHCP/DNSがUFWに遮断されている可能性と確認箇所を表示します。firewalldでは確認後に`waydroid0`のみ実行中のtrusted zoneへ追加します（Androidからホストへの通信も許可、firewalld再起動で解除）。既存の独自zone・nftablesルールは上書きしません。

**背景化時はAndroid sessionが停止します。** 追加したUFWルールは復元対象外です。

## 修復・復元

- `./install.sh --diagnose`：診断
- `./install.sh --repair`：Android 11環境のHoudini・libnb修復とネットワーク確認
- `./install.sh --reset`：既存環境を退避して新規導入（`RESET_WAYDROID=1 ./install.sh`も同じ）
- `./install.sh --reinstall`：上書き再インストール。既存Waydroid・現在ユーザーのゲーム／ログインデータ・指定イメージを削除し、Android 11 GAPPS + Houdini + libnbを再導入
- `./install.sh --restore BACKUP`：修復前の設定・overlayを復元

**上書き再インストール（4 / `--reinstall`）は退避せず削除します。削除対象は `/var/lib/waydroid`、現在ユーザーのWaydroidデータ（通常 `~/.local/share/waydroid`）、`/etc/waydroid-extra/images` です。削除前に `[y/N]` で確認し、両イメージのダウンロード・ZIP検査に成功してから停止・削除します。削除した環境は `--restore` では戻せません。**

reset後はゲーム・ログイン状態を引き継ぎません。resetの退避は`--restore`の対象外です。
バックアップは`/var/lib/mwi/backups/`、ログは通常`~/.local/state/mwi/logs/`に保存します。

## 出典・謝辞

[mogareta7731氏](https://zenn.dev/mogareta7731/articles/94204fa83b239b)が配布したAndroid-x86 ISOに同梱されていたパッチ済み`test_nb`を、バイナリ・LICENSEとも無改変で使用しています。元プロジェクトは[qwerty12356-wart氏のtest_libnb](https://github.com/qwerty12356-wart/test_libnb)、BSD 2-Clauseです。MWI本体はMIT Licenseです。
両氏および[Waydroid](https://github.com/waydroid/waydroid)・[waydroid_script](https://github.com/casualsnek/waydroid_script)の作者に心より感謝します。

## 0.2.5: UFW DHCP修復

UFWがactiveの場合、起動・修復・ネットワーク再起動の前に、waydroid0のDHCP UDP/67（IPv4 broadcastと未取得クライアントを含む）、192.168.240.0/24から192.168.240.1へのDNS UDP/TCP 53、同subnetから検出したIPv4 uplinkへのroute forwardingを許可します。inactive・未導入のUFWは変更しません。uplinkを検出できない場合はルール追加前に停止します。

UFWのinsertで同等ルールの重複と既存コメントの書き換えを防ぎます。限定ルールを先頭に配置するため、既存の包括的denyよりWaydroid例外が優先されます。既存ルールの削除、default policyの変更、reset、enable、reloadは行いません。追加ルールは永続化され、従来どおりrestore対象外です。uplink変更時には新uplink向けルールを追加し、旧ルールは削除しません。

DHCP待機失敗時も修復前に即終了せず、再起動後の診断を保存して判定します。最終的にAndroid IPv4に対応するlease、IPv4、全routing table・policy ruleの診断、gateway疎通、NAT、forwarding、DNS、HTTPSを再検証します。ログはnetwork-dhcp-leases.txt、network-ufw-before.txt、network-ufw-apply.txtおよび既存network-*に保存します。

MWI 01の実機結果（DHCP/IPv4/gateway/外部IP/DNS成功、main tableにdefaultなし）を反映し、Android netdのpolicy routingを尊重します。main tableのdefault必須判定と手動route追加を廃止し、DNS・HTTPSの実際の通信を最終判定に使います。gateway/外部IPのpingは診断用途で、ICMPが拒否されてもHTTPS成功を妨げません。全tableとip ruleを保存し、ネットワーク検証コマンドはstdinからWaydroid shellへ渡します。
