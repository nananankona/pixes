# pixes

[![flutter](https://img.shields.io/badge/flutter-3.41.6-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/nananankona/pixes)](https://github.com/nananankona/pixes/blob/master/LICENSE)
[![Download](https://img.shields.io/github/v/release/nananankona/pixes)](https://github.com/nananankona/pixes)
[![stars](https://img.shields.io/github/stars/nananankona/pixes)](https://github.com/nananankona/pixes/stargazers)

Unofficial Pixiv app, support Windows, Android, iOS, macOS, linux

All main features are implemented.

## Fork

This is a fork of [wgh136/pixes](https://github.com/wgh136/pixes) with the following additions:

- Custom font
- Hide email address
- Age tag display fix
- Japanese localization
- PIN lock
- Data export / import
- Token login (login with config file)
- Supabase sync (sync search/browsing history and settings across devices)

[Japanese README is here](README_JA.md)

## Download

Download from [Release](https://github.com/nananankona/pixes/releases)

## Build from source

### Install Flutter

View [Flutter Document](https://flutter.dev/docs/get-started/install)

### Build Android

Put your keystore file (`key.jks`, `key.properties`) in `android/`

Run `flutter build apk`

### Build iOS/Windows/macOS

Run `flutter build ios/windows/macos`

### Build Linux

Use`python3 debian/build.py {ARCH}` to build deb package. Replace {ARCH} with `x64` or `arm64`.

For other linux distributions, you can use `flutter build linux` to build.
You must register the `pixiv` scheme in the `.desktop` file, otherwise the login will not work.

## Sync (cross-device)

Requires a self-hosted Supabase project.

1. Create a Supabase project at [supabase.com](https://supabase.com)
2. Go to **Settings → API** and copy your **anon key**(or**service_role**)
3. In pixes, open **Settings → Sync** and enter your Supabase URL and anon key
4. Tap **Test Connection** – follow the in-app setup guide to run the SQL commands
5. Enable **Sync** – your search history, browsing history, and settings will sync across devices automatically

## Screenshots

<img src="screenshots/1.png" style="width: 400px">
<img src="screenshots/2.png" style="width: 400px">
<img src="screenshots/3.png" style="width: 400px">
<img src="screenshots/4.png" style="width: 400px">
