# Mirishita Waydroid Installer (MWI)

x86_64 Linux PCで「アイドルマスター ミリオンライブ！ シアターデイズ（以下、ミリシタ）」をWaydroidにて動かす環境を整えるツールです。

## 対応環境

- x86_64、AMD Radeon（`amdgpu`）
- CachyOS / Arch Linux
- dnf版Fedora（KDE Plasmaを含む）
- Ubuntu 24.04 LTS（実験対応）
- Wayland

動作確認済み環境はCachyOS + KDE Plasmaのみです。Ryzen 7 9700X + Radeon RX 6600 XTおよびAMD BC250で確認しています。Arch Linux、Fedora、Ubuntuは実機での導入検証が未実施です。Ubuntuは24.04 LTS（noble）のみ実験対応しています。

## インストール方法

```bash
git clone https://github.com/relorah/mirishita-waydroid-installer.git

cd mirishita-waydroid-installer
chmod +x install.sh
./install.sh
```

CachyOSにWaydroidパッケージが既に入っていても、そのまま実行できます。手動での再インストールは不要です。installerの`pacman -Syu --needed`はシステム全体を更新し、更新不要のパッケージは再インストールしません。初期化済みのWaydroid設定またはユーザーデータがある場合は、既存データ保護のため停止します。完全に作り直す場合は `RESET_WAYDROID=1 ./install.sh` を実行してください（既存データは `~/.local/state/mwi/backups/` へ退避します）。

UbuntuではWaylandセッションにログインして実行してください。Ubuntuの`universe`と[公式Waydroidリポジトリ](https://docs.waydro.id/usage/install-on-desktops#debian-ubuntu-and-derivatives)を有効にし、`apt-get`で必要なパッケージを導入します。Ubuntu 22.04、26.04やUbuntu派生ディストリビューションは今回の実験対応に含みません。

## 実行内容

Android 11 + Google Play、Houdini（`waydroid_script`経由）、同梱のpatched `test_libnb`を導入し、Waydroidのネットワーク設定をします。UFW/firewalldが有効な場合は`waydroid0`用ルールを設定し、DHCP・default route・Internet・DNSを確認します。ミリシタAPKは同梱・要求・取得・インストールしません。セットアップ後、ユーザー自身がGoogle Playから導入してください。

Houdiniはセットアップ時にupstreamの[casualsnek/waydroid_script](https://github.com/casualsnek/waydroid_script)から固定revision `48dbfaf34a6ddbe78688c530f9ba1c26522aafb2`をdetached checkoutして導入します。MWIはHoudini binariesを再配布しません。

## インストール後

Google Playにログインし、ミリシタをインストールしてください。

## Credits / License

Waydroid、[casualsnek/waydroid_script](https://github.com/casualsnek/waydroid_script)、[qwerty12356-wart/test_libnb](https://github.com/qwerty12356-wart/test_libnb)に感謝します。

MWIにはルートの`LICENSE`を適用します。`third_party/test_libnb/`にはソースと各ライセンスを収録しています。
