import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:pixes/appdata.dart';
import 'package:pixes/foundation/app.dart';
import 'package:pixes/foundation/log.dart';

/// Installs an image file as the app background wallpaper.
/// Copies it into app data, updates settings + history (max 10).
/// Returns the installed path, or null on failure.
Future<String?> installThemeBackgroundFile(String srcPath) async {
  try {
    final src = File(srcPath);
    if (!await src.exists()) return null;
    var ext = 'png';
    if (srcPath.contains('.')) {
      final e = srcPath.split('.').last.toLowerCase();
      if (['png', 'jpg', 'jpeg', 'webp'].contains(e)) ext = e;
    }
    final dest = File(
        '${App.dataPath}/theme_background_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await dest.writeAsBytes(await src.readAsBytes());
    final raw = appdata.settings["themeBackgroundHistory"];
    final hist =
        raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
    hist.remove(dest.path);
    hist.insert(0, dest.path);
    while (hist.length > 10) {
      final old = hist.removeLast();
      try {
        final f = File(old);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    // Remove the legacy single-file copy if it exists.
    for (final e in ['png', 'jpg', 'jpeg', 'webp']) {
      final legacy = File('${App.dataPath}/theme_background.$e');
      try {
        if (await legacy.exists()) await legacy.delete();
      } catch (_) {}
    }
    appdata.settings["themeBackgroundHistory"] = hist;
    appdata.settings["themeBackground"] = dest.path;
    appdata.writeData();
    StateController.findOrNull(tag: "MyApp")?.update();
    return dest.path;
  } catch (e) {
    Log.error("Theme", "Failed to install background: $e");
    return null;
  }
}

/// Applies an existing history entry as the background.
void applyThemeBackground(String path) {
  appdata.settings["themeBackground"] = path;
  final raw = appdata.settings["themeBackgroundHistory"];
  final hist =
      raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
  hist.remove(path);
  hist.insert(0, path);
  appdata.settings["themeBackgroundHistory"] = hist;
  appdata.writeData();
  StateController.findOrNull(tag: "MyApp")?.update();
}

/// Removes a history entry (and its file, unless currently applied).
Future<void> removeThemeBackground(String path) async {
  final raw = appdata.settings["themeBackgroundHistory"];
  final hist =
      raw is List ? raw.map((e) => e.toString()).toList() : <String>[];
  hist.remove(path);
  appdata.settings["themeBackgroundHistory"] = hist;
  if (appdata.settings["themeBackground"] == path) {
    appdata.settings["themeBackground"] = hist.isNotEmpty ? hist.first : "";
  }
  appdata.writeData();
  StateController.findOrNull(tag: "MyApp")?.update();
  try {
    final f = File(path);
    if (await f.exists() &&
        appdata.settings["themeBackground"] != path) {
      await f.delete();
    }
  } catch (_) {}
}
