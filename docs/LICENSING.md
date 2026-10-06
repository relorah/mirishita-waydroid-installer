# ライセンスと出典

## MWI作成部分

ルートの[`LICENSE`](../LICENSE)は、個別のライセンス表示や第三者帰属を含まないMWI作成のinstaller・文書に適用します。第三者コード、同梱 `test_libnb`、Androidイメージ、Google Play、Houdini、セットアップ時に取得するソフトウェアへライセンスを付け替えるものではありません。

## 同梱 `test_libnb`

`test_libnb/src/libnb_mwi.cpp` と同梱32-bit/64-bit `libnb.so` は、Android-x86 NativeBridge forwarding実装（Copyright (C) 2015-2017 The Android-x86 Open Source Project、Chih-Wei Huang）を含み、GPL-2.0-or-laterで提供されます。GPL v2本文は[`LICENSES/GPL-2.0.txt`](../LICENSES/GPL-2.0.txt)に収録しています。対応するソースとビルドスクリプトも `test_libnb/` に含めています。

アプリ別patch処理には、`qwerty12356-wart/test_libnb` のソース参照commit `4f89b1f622d83082bc644fc216a9d6c70d7df8f7` に基づく部分があります。BSD-2-Clauseの著作権表示と条件を[`LICENSES/test_libnb-BSD-2-Clause.txt`](../LICENSES/test_libnb-BSD-2-Clause.txt)に保持しています。

ミリシタ固有の `Patch_exp_01` は、mogareta7731氏の公開した互換性説明を参考にしています。同氏のバイナリは同梱していません。詳細は[`NOTICE`](../NOTICE)に記載しています。

## 実行時に取得するソフトウェア

- WaydroidのAndroid system/vendorイメージはWaydroidのSourceForgeプロジェクトから取得します。各イメージのライセンス・条件が適用されます。
- `casualsnek/waydroid_script` は `install.sh` で固定したcommitから実行時に取得します。本リポジトリには複製していません。[同プロジェクトのライセンスと説明](https://github.com/casualsnek/waydroid_script)を参照してください。
- Houdiniは実行時に同ツールが取得します。MWIはHoudiniバイナリを配布せず、利用に関する法的判断も示しません。
- Google Playは選択したGAppsイメージの構成要素であり、MWI作成物ではありません。
- ミリシタは利用者がGoogle Playから導入します。MWIはAPKを扱いません。

この文書は当リポジトリの構成と出典を説明するもので、法律上の助言や第三者ソフトの権利判断ではありません。
