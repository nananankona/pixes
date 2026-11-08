import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:pixes/appdata.dart';
import 'package:pixes/foundation/app.dart';
import 'package:pixes/foundation/log.dart';
import 'package:pixes/network/app_dio.dart';
import 'package:pixes/utils/translation.dart';
import 'package:url_launcher/url_launcher_string.dart';

Future<String> getLatestVersion() async {
  var dio = AppDio();
  var res = await dio
      .get("https://raw.githubusercontent.com/nananankona/pixes/refs/heads/master/pubspec.yaml");
  var lines = (res.data as String).split("\n");
  for (var line in lines) {
    if (line.startsWith("version:")) {
      return line.split(":")[1].split('+')[0].trim();
    }
  }
  throw "Failed to get latest version";
}

/// Compare two versions.
/// Return `true` if `a` is greater than `b`.
bool compareVersion(String a, String b) {
  var aList = a.split(".").map(int.parse).toList();
  var bList = b.split(".").map(int.parse).toList();
  for (var i = 0; i < aList.length; i++) {
    if (aList[i] > bList[i]) {
      return true;
    } else if (aList[i] < bList[i]) {
      return false;
    }
  }
  return false;
}

/// Latest release's MSIX asset URL (Windows), or null.
Future<String?> getWindowsInstallerUrl() async {
  try {
    var dio = AppDio();
    var res = await dio.get<Map<String, dynamic>>(
        "https://api.github.com/repos/nananankona/pixes/releases/latest");
    final assets = (res.data?['assets'] as List?) ?? [];
    for (final a in assets) {
      if (a is Map && (a['name'] as String? ?? '').endsWith('.msix')) {
        return a['browser_download_url'] as String?;
      }
    }
  } catch (e) {
    Log.warning("Update", "Failed to resolve installer: $e");
  }
  return null;
}

/// Downloads the Windows installer with progress, then opens it.
Future<void> downloadAndInstallWindows(
    void Function(int received, int total) onProgress) async {
  final url = await getWindowsInstallerUrl();
  if (url == null) throw "No installer found in the latest release";
  final tmp = File(
      '${Directory.systemTemp.path}/pixes_update_${DateTime.now().millisecondsSinceEpoch}.msix');
  var dio = AppDio();
  await dio.download(url, tmp.path, onReceiveProgress: onProgress);
  // ShellExecute the package: App Installer handles cert/install UI.
  if (App.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', tmp.path],
        runInShell: true);
  } else {
    await launchUrlString(Uri.file(tmp.path).toString());
  }
}

Future<void> checkUpdate({bool manual = false}) async {
  if (appdata.account == null && !manual) return;
  try {
    var latestVersion = await getLatestVersion();
    if (compareVersion(latestVersion, App.version)) {
      showDialog(
          context: App.rootNavigatorKey.currentContext!,
          builder: (context) => ContentDialog(
                title: Text("New version available".tl),
                content: Text(
                  "A new version of Pixes is available. Do you want to update now?"
                      .tl,
                ),
                actions: [
                  Button(
                    child: Text("Cancel".tl),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  FilledButton(
                      child: Text("Update".tl),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        if (!App.isWindows) {
                          launchUrlString(
                              "https://github.com/nananankona/pixes/releases/latest");
                          return;
                        }
                        double progress = 0;
                        bool failed = false;
                        void Function(void Function())? refresh;
                        showDialog(
                          context: App.rootNavigatorKey.currentContext!,
                          barrierDismissible: false,
                          builder: (c) => StatefulBuilder(
                            builder: (context, setState) {
                              refresh = setState;
                              return ContentDialog(
                                title: Text("Downloading update".tl),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ProgressBar(
                                        value: failed
                                            ? 0
                                            : (progress <= 0
                                                ? null
                                                : progress * 100)),
                                    const SizedBox(height: 8),
                                    Text(failed
                                        ? "Download failed".tl
                                        : "${(progress * 100).toStringAsFixed(0)}%"),
                                  ],
                                ),
                                actions: [
                                  Button(
                                    child: Text('Cancel'.tl),
                                    onPressed: () => Navigator.of(c).pop(),
                                  ),
                                ],
                              );
                            },
                          ),
                        );
                        try {
                          await downloadAndInstallWindows((rx, total) {
                            if (total > 0) {
                              refresh?.call(() {
                                progress = rx / total;
                              });
                            }
                          });
                          if (App.rootNavigatorKey.currentContext != null) {
                            Navigator.of(App.rootNavigatorKey.currentContext!)
                                .maybePop();
                          }
                        } catch (e) {
                          refresh?.call(() {
                            failed = true;
                          });
                          await Future.delayed(
                              const Duration(seconds: 2));
                          if (App.rootNavigatorKey.currentContext != null) {
                            Navigator.of(App.rootNavigatorKey.currentContext!)
                                .maybePop();
                            launchUrlString(
                                "https://github.com/nananankona/pixes/releases/latest");
                          }
                        }
                      })
                ],
              ));
    }
  } catch (e) {
    // ignore
  }
}
