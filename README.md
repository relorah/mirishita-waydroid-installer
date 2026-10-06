# Mirishita Waydroid Installer (MWI)

MWIは、x86_64 Linux PCで「アイドルマスター ミリオンライブ！ シアターデイズ（以下、ミリシタ）」を動かす環境を整えるツールです。

## 対応環境

- x86_64、AMD Radeon（`amdgpu`）
- CachyOS / Arch Linux
- dnf版Fedora（KDE Plasmaを含む）
- Wayland

Ubuntu対応は予定です。

## インストール方法

```bash
git clone https://github.com/relorah/mirishita-waydroid-installer.git
cd mirishita-waydroid-installer
chmod +x install.sh
./install.sh
```

## 実行内容

Android 11 + Google Play、Houdini（`waydroid_script`経由）、MWI用`test_libnb`を導入し、Waydroidのネットワークを設定します。Houdiniは実行時に取得します。ミリシタAPKは要求・配布しません。

## インストール後

Google Playにログインし、ミリシタをインストールしてください。

## Credits / License

Waydroid、[casualsnek/waydroid_script](https://github.com/casualsnek/waydroid_script)、[qwerty12356-wart/test_libnb](https://github.com/qwerty12356-wart/test_libnb)に感謝します。

MWIにはルートの`LICENSE`を適用します。`third_party/test_libnb/`にはソースと各ライセンスを収録しています。
