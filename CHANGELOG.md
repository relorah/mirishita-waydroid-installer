# 更新履歴

## v0.1.0 — 2026-10-06

- CachyOS/Archと通常のdnf版Fedora向けに、公開用ソース構成を整理。
- Android 11 + GApps、固定commitの `waydroid_script` を通じたHoudini導入、MWI用 `test_libnb`、Google Playまでの責務を明文化。
- 既存Waydroidを削除する処理を取り除き、既存環境検出時は停止するよう変更。
- AndroidイメージZIPの整合性と内部ファイル、同梱 `test_libnb` のSHA-256を検査。
- ミリシタAPKとHoudiniバイナリを同梱しないことを明記。
- ライセンス、出典、セットアップ制限を文書化。
- 公開パッケージは静的検証済み。各ディストリビューションでの新規インストール実機確認は未実施。
