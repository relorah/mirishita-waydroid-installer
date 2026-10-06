# Mirishita Waydroid Installer (MWI)

MWIは、x86_64 Linux PCで「アイドルマスター ミリオンライブ！ シアターデイズ（以下、ミリシタ）」をWaydroidにて動かす環境を整えるツールです。

## 対応環境

- x86_64、AMD Radeon（`amdgpu`）
- CachyOS / Arch Linux
- Fedora（dnfベース、KDE Plasma含む）
- Wayland

Ryzen 7 9700X + RX 6600XT、AMD BC250にて動作確認済。

## インストール方法

```bash
git clone https://github.com/relorah/mirishita-waydroid-installer.git
cd mirishita-waydroid-installer
chmod +x install.sh
./install.sh
```

CachyOSにWaydroidパッケージが既に入っていても、そのまま実行できます。手動での再インストールは不要です。installerの`pacman -Syu --needed`は、更新不要のパッケージを再インストールせず、古いパッケージは更新します。初期化済みのWaydroid設定またはユーザーデータがある場合は、既存データ保護のため停止します。

## 実行内容

Android 11 + Google Play、Houdini（`waydroid_script`経由）、MWI用`test_libnb`を導入し、Waydroidのネットワークを設定します。Houdiniは実行時に取得します。ミリシタAPKは要求・配布しません。

## インストール後

Google Playにログインし、ミリシタをインストールしてください。

## Credits / License

Waydroid、[casualsnek/waydroid_script](https://github.com/casualsnek/waydroid_script)、[qwerty12356-wart/test_libnb](https://github.com/qwerty12356-wart/test_libnb)に感謝します。

MWIにはルートの`LICENSE`を適用します。`third_party/test_libnb/`にはソースと各ライセンスを収録しています。
