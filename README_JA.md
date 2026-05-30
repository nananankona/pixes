# pixes

[![flutter](https://img.shields.io/badge/flutter-3.41.6-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/nananankona/pixes)](https://github.com/nananankona/pixes/blob/master/LICENSE)
[![Download](https://img.shields.io/github/v/release/nananankona/pixes)](https://github.com/nananankona/pixes)
[![stars](https://img.shields.io/github/stars/nananankona/pixes)](https://github.com/nananankona/pixes/stargazers)

非公式Pixivクライアント。Windows、Android、iOS、macOS、Linuxに対応。

主要な機能はすべて実装されています。

## Fork

このリポジトリは [wgh136/pixes](https://github.com/wgh136/pixes) のフォークであり、以下の機能が追加されています：

- カスタムフォント
- メールアドレス非表示
- 年齢タグ不具合修正
- 日本語対応
- PINロック
- データエクスポート / インポート
- トークンログイン（設定ファイルによるログイン）
- Supabase同期（検索履歴・閲覧履歴・設定をデバイス間で同期）

[English README](README.md)

## ダウンロード

[Release](https://github.com/nananankona/pixes/releases) からダウンロード

## ソースからビルド

### Flutterのインストール

[Flutter Document](https://flutter.dev/docs/get-started/install) を参照

### Androidのビルド

`android/` にキーストアファイル（`key.jks`、`key.properties`）を配置

`flutter build apk` を実行

### iOS/Windows/macOSのビルド

`flutter build ios/windows/macos` を実行

### Linuxのビルド

`python3 debian/build.py {ARCH}` でdebパッケージをビルド。{ARCH} は `x64` または `arm64`。

その他のLinuxディストリビューションでは `flutter build linux` でビルド可能。
ログインを機能させるには `.desktop` ファイルに `pixiv` スキームを登録する必要があります。

## 同期（デバイス間）

自己ホストのSupabaseプロジェクトが必要です。

1. [supabase.com](https://supabase.com) でSupabaseプロジェクトを作成
2. **Settings → API** から **anon key**(または**service_role**) をコピー
3. pixesの **設定 → Sync** を開き、Supabase URLとanon keyを入力
4. **接続テスト** をタップ -- アプリ内のセットアップガイドに従ってSQLを実行
5. **同期を有効化** -- 検索履歴・閲覧履歴・設定が自動で同期されます

## スクリーンショット

<img src="screenshots/1.png" style="width: 400px">
<img src="screenshots/2.png" style="width: 400px">
<img src="screenshots/3.png" style="width: 400px">
<img src="screenshots/4.png" style="width: 400px">
