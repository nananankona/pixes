import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pixes/services/sync_service.dart';
import 'package:pixes/utils/io.dart';

import 'foundation/app.dart';
import 'foundation/log.dart';
import 'network/models.dart';

class _Appdata {
  static const MethodChannel _macosDownloadPathChannel =
      MethodChannel("pixes/macos/download_path");

  Account? account;

  var searchOptions = SearchOptions();

  Map<String, dynamic> settings = {
    "downloadPath": null,
    "downloadSubPath": r"/${id}-p${index}.${ext}",
    "maxParallels": 3,
    "proxy": "",
    "darkMode": "System",
    "language": "System",
    "readingFontSize": 16.0,
    "readingLineHeight": 1.5,
    "readingParagraphSpacing": 8.0,
    "blockTags": [],
    "shortcuts": <int>[
      LogicalKeyboardKey.arrowDown.keyId,
      LogicalKeyboardKey.arrowUp.keyId,
      LogicalKeyboardKey.arrowRight.keyId,
      LogicalKeyboardKey.arrowLeft.keyId,
      LogicalKeyboardKey.enter.keyId,
      LogicalKeyboardKey.keyD.keyId,
      LogicalKeyboardKey.keyF.keyId,
      LogicalKeyboardKey.keyC.keyId,
      LogicalKeyboardKey.keyG.keyId,
    ],
    "showOriginalImage": false,
    "preloadMode": 0,
    "checkUpdate": true,
    "emphasizeArtworksFromFollowingArtists": true,
    "initialPage": 4,
    "hideEmail": false,
    "hideAccountIcon": false,
    "hideAccountName": false,
    "customFont": "",
    "accentColor": "",
    "themeBackground": "",
    "themeBackgroundOpacity": 0.5,
    "themeBackgroundColor": "",
    "themeBackgroundBlur": 0.0,
    "themeTextShadow": false,
    "themeShadowColor": "",
    "themeCardOpacity": 0.82,
    "themeTextColor": "",
    "themeIconColor": "",
    "privateMode": false,
    "lockEnabled": false,
    "lockPassword": "",
    "lockPin": "",
    "searchHistoryLimit": 50,
    "cacheLimitMB": 2048,
    "autoDownload": 0,
    "readingAutoScrollSpeed": 60.0,
    "illustAutoScrollSpeed": 200.0,
    "autoAdvanceArtwork": false,
    "ttsEngine": 0,
    "ttsSpeed": 1.0,
    "ttsVolume": 1.0,
    "voicevoxUrl": "http://127.0.0.1:50021",
    "voicevoxSpeaker": 1,
    "capcutServerUrl": "http://127.0.0.1:8080",
    "capcutV1Type": 0,
    "capcutV1WsUrl": "wss://sami-sg1.internal.byteintlapi.com/internal/api/v1/ws",
    "capcutV2Speaker": "labebe",
    "capcutEmail": "",
    "capcutPassword": "",
    "slideshowInterval": 3,
    "slideshowLoop": false,
    "folderMode": 0,
    "readerDim": 0.0,
    "themeBackgroundHistory": <String>[],
    "recentColors": <String>[],
    "safeOnly": false,
    "networkMode": 0,
    "imageMirror": "",
    "favoriteAutoSave": false,
    "saveAutoFavorite": false,
    "novelPositions": <String, int>{},
    "yumePairs": <String, String>{},
    "novelBreakLength": 0,
  };

  bool lock = false;

  void writeData() async {
    while (lock) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    lock = true;
    try {
      await File("${App.dataPath}/account.json")
          .writeAsString(jsonEncode(account));
      await File("${App.dataPath}/settings.json")
          .writeAsString(jsonEncode(settings));
    } finally {
      lock = false;
    }
    syncService.notifyChange();
  }

  void writeSettings() async {
    while (lock) {
      await Future.delayed(const Duration(milliseconds: 20));
    }
    lock = true;
    try {
      await File("${App.dataPath}/settings.json")
          .writeAsString(jsonEncode(settings));
    } finally {
      lock = false;
    }
    syncService.notifyChange();
  }

  Future<void> readData() async {
    final file = File("${App.dataPath}/account.json");
    if (file.existsSync()) {
      var json = jsonDecode(await file.readAsString());
      if (json != null) {
        account = Account.fromJson(json);
      }
    }
    final settingsFile = File("${App.dataPath}/settings.json");
    if (settingsFile.existsSync()) {
      var json = jsonDecode(await settingsFile.readAsString());
      for (var key in json.keys) {
        if (json[key] != null) {
          if (json[key] is List && settings[key] is List) {
            for (int i = 0;
                i < json[key].length && i < settings[key].length;
                i++) {
              settings[key][i] = json[key][i];
            }
          } else {
            settings[key] = json[key];
          }
        }
      }
    }
    settings["downloadPath"] ??= await _defaultDownloadPath;
    // Migrate users with a customized subpath pattern to custom folder mode.
    if (settings["downloadSubPath"] != r"/${id}-p${index}.${ext}" &&
        (settings["folderMode"] as int? ?? 0) == 0) {
      settings["folderMode"] = 3;
    }
    if (App.isMacOS) {
      await _ensureMacOSDownloadPathPermission();
    }
  }

  List<SearchHistoryEntry>? _cachedHistory;

  String get _historyPath => "${App.dataPath}/search_history.json";

  List<SearchHistoryEntry> _loadHistoryFromFile() {
    try {
      final file = File(_historyPath);
      if (!file.existsSync()) return [];
      final raw = file.readAsStringSync();
      if (raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => SearchHistoryEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  void _saveHistoryToFile(List<SearchHistoryEntry> list) {
    try {
      File(_historyPath).writeAsStringSync(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  void addSearchHistory(String keyword, int searchType) {
    final entry = SearchHistoryEntry(
      keyword: keyword,
      searchType: searchType,
      matchType: searchOptions.matchType,
      favoriteNumber: searchOptions.favoriteNumber,
      sort: searchOptions.sort,
      startTime: searchOptions.startTime,
      endTime: searchOptions.endTime,
      ageLimit: searchOptions.ageLimit,
      includeAiGeneratedWorks: searchOptions.includeAiGeneratedWorks,
    );
    final list = getSearchHistory();
    list.removeWhere((e) => e.keyword == keyword && e.searchType == searchType);
    list.insert(0, entry);
    final limit = settings["searchHistoryLimit"] as int? ?? 50;
    if (limit > 0 && list.length > limit) list.removeRange(limit, list.length);
    _cachedHistory = list;
    _saveHistoryToFile(list);
    syncService.notifyChange();
  }

  List<SearchHistoryEntry> getSearchHistory() {
    if (_cachedHistory == null) {
      _cachedHistory = _loadHistoryFromFile();
    }
    return List.from(_cachedHistory!);
  }

  void clearSearchHistory() {
    _cachedHistory = [];
    _saveHistoryToFile([]);
    syncService.notifyChange();
    // Propagate the clear so other devices converge too.
    syncService.deleteRemoteSearchHistory();
  }

  void removeSearchHistory(String keyword, int searchType) {
    final list = getSearchHistory();
    final removed = list.length;
    list.removeWhere((e) => e.keyword == keyword && e.searchType == searchType);
    if (list.length == removed) return;
    _cachedHistory = list;
    _saveHistoryToFile(list);
    syncService.notifyChange();
    syncService.deleteRemoteSearchRow(keyword, searchType);
  }

  List<SearchPreset>? _cachedPresets;

  String get _presetPath => "${App.dataPath}/search_presets.json";

  List<SearchPreset> getSearchPresets() {
    _cachedPresets ??= _loadPresetsFromFile();
    return List.from(_cachedPresets!);
  }

  List<SearchPreset> _loadPresetsFromFile() {
    try {
      final file = File(_presetPath);
      if (!file.existsSync()) return [];
      final raw = file.readAsStringSync();
      if (raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => SearchPreset.fromJson(e as Map<String, dynamic>))
          .where((e) => e.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _savePresetsToFile(List<SearchPreset> list) {
    try {
      File(_presetPath)
          .writeAsStringSync(jsonEncode(list.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  void saveSearchPreset(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final list = getSearchPresets();
    list.removeWhere((e) => e.name == trimmed);
    list.insert(0,
        SearchPreset(name: trimmed, options: searchOptions.toJson()));
    _cachedPresets = list;
    _savePresetsToFile(list);
    syncService.notifyChange();
  }

  void applySearchPreset(SearchPreset preset) {
    searchOptions.applyJson(Map<String, dynamic>.from(preset.options));
    writeData();
  }

  void deleteSearchPreset(String name) {
    final list = getSearchPresets();
    list.removeWhere((e) => e.name == name);
    _cachedPresets = list;
    _savePresetsToFile(list);
    syncService.notifyChange();
  }

  void importSearchPresets(List<SearchPreset> list) {
    _cachedPresets = List.from(list);
    _savePresetsToFile(list);
    syncService.notifyChange();
  }

  void importSearchHistory(List<SearchHistoryEntry> list,
      {bool notify = true}) {
    _cachedHistory = List.from(list);
    _saveHistoryToFile(list);
    if (notify) syncService.notifyChange();
  }

  Future<void> _ensureMacOSDownloadPathPermission() async {
    final defaultPath = await _defaultDownloadPath;
    final currentPath = settings["downloadPath"] as String? ?? defaultPath;
    if (_normalizePath(currentPath) == _normalizePath(defaultPath)) {
      settings["downloadPath"] = defaultPath;
      return;
    }

    final restoredPath = await _restoreMacOSDownloadPathAccess(currentPath);
    if (restoredPath != null) {
      settings["downloadPath"] = restoredPath;
      Log.info(
          "DownloadPath", "Restored macOS directory access: $restoredPath");
      return;
    }

    Log.warning(
      "DownloadPath",
      "Failed to restore macOS directory access for $currentPath, requesting permission again.",
    );
    final selectedPath = await _requestMacOSDownloadPathAccess(currentPath);
    if (selectedPath != null) {
      settings["downloadPath"] = selectedPath;
      writeSettings();
      Log.info(
        "DownloadPath",
        "Re-authorized macOS directory access: $selectedPath",
      );
      return;
    }

    settings["downloadPath"] = defaultPath;
    writeSettings();
    Log.warning(
      "DownloadPath",
      "macOS directory permission denied or canceled, fallback to default path: $defaultPath",
    );
  }

  Future<String?> _restoreMacOSDownloadPathAccess(String? expectedPath) async {
    try {
      return await _macosDownloadPathChannel.invokeMethod<String>(
        "restoreDownloadDirectoryAccess",
        {"path": expectedPath},
      );
    } catch (e) {
      Log.warning("DownloadPath", "restoreDownloadDirectoryAccess failed: $e");
      return null;
    }
  }

  Future<String?> _requestMacOSDownloadPathAccess(String? initialPath) async {
    try {
      return await _macosDownloadPathChannel.invokeMethod<String>(
        "selectDownloadDirectory",
        {"initialPath": initialPath},
      );
    } catch (e) {
      Log.warning("DownloadPath", "selectDownloadDirectory failed: $e");
      return null;
    }
  }

  String _normalizePath(String path) {
    if (!App.isMacOS) {
      return path;
    }
    final home = Platform.environment["HOME"];
    if (home != null && path.startsWith("~")) {
      return path.replaceFirst("~", home);
    }
    return path;
  }

  Future<String> get _defaultDownloadPath async {
    if (App.isAndroid) {
      String? downloadPath = "/storage/emulated/0/download";
      if (!Directory(downloadPath).havePermission()) {
        downloadPath = null;
      }
      var res = downloadPath;
      res ??= (await getExternalStorageDirectory())!.path;
      return "$res/pixes";
    } else if (App.isWindows) {
      var res =
          await const MethodChannel("pixes/picture_folder").invokeMethod("");
      if (res != "error") {
        return res + "/pixes";
      }
    } else if (App.isLinux) {
      var downloadPath = (await getDownloadsDirectory())?.path;
      if (downloadPath != null && Directory(downloadPath).havePermission()) {
        return "$downloadPath/pixes";
      }
    } else if (App.isIOS) {
      // Visible in the Files app (see UIFileSharingEnabled in Info.plist).
      try {
        final docs = await getApplicationDocumentsDirectory();
        final dir = Directory("${docs.path}/pixes");
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir.path;
      } catch (_) {
        return "${App.dataPath}/download";
      }
    } else if (App.isMacOS) {
      if (Directory("~/Pictures").havePermission()) {
        return "~/Pictures/pixes";
      }
      try {
        Directory("~/Downloads/pixes").createSync(recursive: true);
        return "~/Downloads/pixes";
      } catch (e) {
        return "${App.dataPath}/download";
      }
    }

    return "${App.dataPath}/download";
  }
}

final appdata = _Appdata();
