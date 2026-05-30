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

## スクリーンショット

<img src="screenshots/1.png" style="width: 400px">
<img src="screenshots/2.png" style="width: 400px">
<img src="screenshots/3.png" style="width: 400px">
<img src="screenshots/4.png" style="width: 400px">
