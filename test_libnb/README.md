# MWI `test_libnb` payload

このディレクトリには、MWI v0.1.0で使用するソース、ビルド手順、32-bit x86 / 64-bit x86_64の `libnb.so` を収録しています。

## 出典とライセンス

- upstream参照: [`qwerty12356-wart/test_libnb`](https://github.com/qwerty12356-wart/test_libnb)、commit `4f89b1f622d83082bc644fc216a9d6c70d7df8f7`
- NativeBridge forwarding実装はAndroid-x86由来で、GPL-2.0-or-laterです。ソース、ビルドスクリプト、バイナリ、GPL v2本文を同梱しています。
- upstream patch処理に関するBSD-2-Clauseの著作権表示と条件は [`LICENSES/test_libnb-BSD-2-Clause.txt`](../LICENSES/test_libnb-BSD-2-Clause.txt) に保持しています。
- ミリシタ向け処理はBlue Archive向け `Patch_Performance_pkey_mprotect` に `Patch_exp_01` を追加します。mogareta7731氏の公開説明を参考にしましたが、同氏のバイナリは含みません。

詳細は [`docs/LICENSING.md`](../docs/LICENSING.md) とルートの [`NOTICE`](../NOTICE) を参照してください。

## 再ビルド

Clang/Clang++とLLDが利用できるLinux環境で実行します。

```bash
./build-test-libnb.sh
```

Android API 30向けi686およびx86_64を対象にしています。コンパイラのバージョンは固定していないため、再ビルドした成果物のバイト列が一致するとは限りません。同梱バイナリのSHA-256は [`SHA256SUMS`](SHA256SUMS) に記録しています。

この説明は、第三者の互換性参考情報が第三者著作物へのライセンスを与えることを意味しません。改変版を再配布する場合は、各ソースの表示とライセンス条件を確認してください。
