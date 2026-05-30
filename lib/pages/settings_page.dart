import 'dart:io';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:pixes/appdata.dart';
import 'package:pixes/network/models.dart';
import 'package:pixes/components/keyboard.dart';
import 'package:pixes/components/md.dart';
import 'package:pixes/components/message.dart';
import 'package:pixes/components/page_route.dart';
import 'package:pixes/components/title_bar.dart';
import 'package:pixes/foundation/app.dart';
import 'package:pixes/foundation/history.dart';
import 'package:pixes/pages/main_page.dart';
import 'package:pixes/pages/sync_page.dart';
import 'package:pixes/utils/io.dart';
import 'package:pixes/utils/translation.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'logs.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Helper: show a simple hex color picker (RGB sliders)
  Future<void> _pickHexColor(String title, String settingKey) async {
    // parse existing hex or default to white
    String current = (appdata.settings[settingKey] ?? "");
    int r = 255, g = 255, b = 255;
    if (current.startsWith('#') && current.length == 7) {
      try {
        r = int.parse(current.substring(1, 3), radix: 16);
        g = int.parse(current.substring(3, 5), radix: 16);
        b = int.parse(current.substring(5, 7), radix: 16);
      } catch (_) {}
    }
    double rVal = r.toDouble();
    double gVal = g.toDouble();
    double bVal = b.toDouble();
    await showDialog(
      context: context,
      builder: (c) => ContentDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, innerSetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('R'),
              Slider(min: 0, max: 255, divisions: 255, value: rVal, onChanged: (v) => innerSetState(() => rVal = v)),
              const Text('G'),
              Slider(min: 0, max: 255, divisions: 255, value: gVal, onChanged: (v) => innerSetState(() => gVal = v)),
              const Text('B'),
              Slider(min: 0, max: 255, divisions: 255, value: bVal, onChanged: (v) => innerSetState(() => bVal = v)),
              const SizedBox(height: 8),
              Container(width: 40, height: 40, color: Color.fromRGBO(rVal.toInt(), gVal.toInt(), bVal.toInt(), 1)),
            ],
          ),
        ),
        actions: [
          Button(
            child: Text('Confirm'.tl),
            onPressed: () {
              final hex = '#'
                  '${rVal.toInt().toRadixString(16).padLeft(2, '0')}'
                  '${gVal.toInt().toRadixString(16).padLeft(2, '0')}'
                  '${bVal.toInt().toRadixString(16).padLeft(2, '0')}';
              setState(() {
                appdata.settings[settingKey] = hex;
              });
              appdata.writeData();
              StateController.findOrNull(tag: "MyApp")?.update();
              c.pop();
            },
          ),
        ],
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: CustomScrollView(
        slivers: [
          SliverTitleBar(title: "Settings".tl),
          buildHeader("Account".tl),
          buildAccount(),
          buildHeader("Browse".tl),
          buildBrowse(),
          buildHeader("Download".tl),
          buildDownload(),
           buildHeader("Appearance".tl),
           buildAppearance(),
            buildHeader("Security".tl),
            buildSecurity(),
            buildHeader("Sync".tl),
            buildSync(),
            buildHeader("About".tl),
           buildAbout(),
          SliverPadding(
              padding: EdgeInsets.only(bottom: context.padding.bottom)),
        ],
      ),
    );
  }

  Widget buildHeader(String text) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Text(text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget buildItem({required String title, String? subtitle, Widget? action}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.zero,
      child: ListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: action,
      ),
    );
  }

  Widget buildAccount() {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          buildItem(
            title: "Logout".tl,
            action: Button(
              onPressed: () {
                showDialog<String>(
                  context: App.rootNavigatorKey.currentContext!,
                  builder: (context) => ContentDialog(
                    title: Text('Logout'.tl),
                    content: Text('Are you sure you want to logout?'.tl),
                    actions: [
                      Button(
                        child: Text('Continue'.tl),
                        onPressed: () {
                          appdata.account = null;
                          appdata.writeData();
                          App.rootNavigatorKey.currentState!.pushAndRemoveUntil(
                              AppPageRoute(
                                  builder: (context) => const MainPage()),
                              (route) => false);
                        },
                      ),
                      FilledButton(
                        child: Text('Cancel'.tl),
                        onPressed: () => context.pop(),
                      ),
                    ],
                  ),
                );
              },
              child: Text("Continue".tl).fixWidth(64),
            ),
          ),
          buildItem(
              title: "Account Settings".tl,
              action: Button(
                child: Text("Edit".tl).fixWidth(64),
                onPressed: () {
                  launchUrlString("https://www.pixiv.net/setting_user.php");
                },
              )),
          buildItem(
              title: "Hide Email".tl,
              action: ToggleSwitch(
                  checked: appdata.settings["hideEmail"],
                  onChanged: (value) {
                    setState(() {
                      appdata.settings["hideEmail"] = value;
                    });
                    appdata.writeData();
                  })),
          buildItem(
              title: "Hide Account Icon".tl,
              action: ToggleSwitch(
                  checked: appdata.settings["hideAccountIcon"],
                  onChanged: (value) {
                    setState(() {
                      appdata.settings["hideAccountIcon"] = value;
                    });
                    appdata.writeData();
                  })),
          buildItem(
              title: "Hide Account Name".tl,
              action: ToggleSwitch(
                  checked: appdata.settings["hideAccountName"],
                  onChanged: (value) {
                    setState(() {
                      appdata.settings["hideAccountName"] = value;
                    });
                    appdata.writeData();
                  })),
        ],
      ),
    );
  }

  Widget buildDownload() {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          buildItem(
            title: "Download Path".tl,
            subtitle: appdata.settings["downloadPath"],
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (App.isMacOS)
                  _MacosDownloadPathSelectButton(onSelected: (path) {
                    setState(() {
                      appdata.settings["downloadPath"] = path;
                    });
                    appdata.writeSettings();
                  })
                else ...[
                  Button(
                    child: Text("Browse".tl).fixWidth(64),
                    onPressed: () async {
                      if (Platform.isIOS) {
                        showToast(context, message: "Unsupported platform".tl);
                        return;
                      }
                      final String? dir = await getDirectoryPath(
                        initialDirectory: appdata.settings["downloadPath"],
                      );
                      if (dir != null) {
                        setState(() {
                          appdata.settings["downloadPath"] = dir;
                        });
                        appdata.writeSettings();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  Button(
                    child: Text("Manage".tl).fixWidth(64),
                    onPressed: () {
                      if (Platform.isIOS) {
                        showToast(context, message: "Unsupported platform".tl);
                        return;
                      }
                      context.to(() => _SetSingleFieldPage(
                            "Download Path".tl,
                            "downloadPath",
                            check: (text) {
                              if (!Directory(text).havePermission()) {
                                return "No permission".tl;
                              } else {
                                return null;
                              }
                            },
                          ));
                    }),
                  const SizedBox(width: 8),
                  Button(
                    child: Text("Reset".tl).fixWidth(64),
                    onPressed: () {
                      setState(() {
                        appdata.settings["downloadPath"] = null;
                      });
                      appdata.writeSettings();
                    },
                  ),
                ],
              ],
            ),
          ),
          buildItem(
            title: "Subpath".tl,
            subtitle: appdata.settings["downloadSubPath"],
            action: Button(
                child: Text("Manage".tl).fixWidth(64),
                onPressed: () {
                  context.to(() => const _SetDownloadSubPathPage());
                }),
          ),
          buildItem(
            title: "Max parallels".tl,
            action: SizedBox(
              width: 64,
              height: 32,
              child: NumberBox<int>(
                value: appdata.settings["maxParallels"],
                autofocus: false,
                onChanged: (value) {
                  appdata.settings["maxParallels"] = value;
                  appdata.writeSettings();
                },
                clearButton: false,
                mode: SpinButtonPlacementMode.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAbout() {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          buildItem(title: "Version", subtitle: App.version),
          buildItem(
              title: "Check for updates on startup".tl,
              action: ToggleSwitch(
                  checked: appdata.settings["checkUpdate"],
                  onChanged: (value) {
                    setState(() {
                      appdata.settings["checkUpdate"] = value;
                    });
                    appdata.writeData();
                  })),
          buildItem(
              title: "Github",
              action: IconButton(
                icon: const Icon(
                  MdIcons.open_in_new,
                  size: 18,
                ),
                onPressed: () =>
                    launchUrlString("https://github.com/nananankona/pixes"),
              )),
          buildItem(
              title: "Telegram",
              action: IconButton(
                icon: const Icon(
                  MdIcons.open_in_new,
                  size: 18,
                ),
                onPressed: () => launchUrlString("https://t.me/venera_dev"),
              )),
          buildItem(
              title: "Logs",
              action: IconButton(
                  icon: const Icon(
                    MdIcons.open_in_new,
                    size: 18,
                  ),
                  onPressed: () => context.to(() => const LogsPage()))),
        ],
      ),
    );
  }

  Widget buildBrowse() {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          buildItem(
              title: "Initial Page".tl,
              action: Button(
                child: Text("Edit".tl).fixWidth(64),
                onPressed: () {
                  context.to(() => const _SetInitialPageWidget());
                },
              )),
          buildItem(
              title: "Proxy".tl,
              action: Button(
                child: Text("Edit".tl).fixWidth(64),
                onPressed: () {
                  context.to(() => _SetSingleFieldPage(
                        "Http ${"Proxy".tl}",
                        "proxy",
                      ));
                },
              )),
          buildItem(
              title: "Block(Account)".tl,
              action: Button(
                child: Text("Edit".tl).fixWidth(64),
                onPressed: () {
                  launchUrlString("https://www.pixiv.net/setting_mute.php");
                },
              )),
          buildItem(
              title: "Block(Local)".tl,
              action: Button(
                child: Text("Edit".tl).fixWidth(64),
                onPressed: () {
                  context.to(() => const _BlockTagsPage());
                },
              )),
          buildItem(
              title: "Shortcuts".tl,
              action: Button(
                child: Text("Edit".tl).fixWidth(64),
                onPressed: () {
                  context.to(() => const ShortcutsSettings());
                },
              )),
          buildItem(
              title: "Display the original image on the details page".tl,
              action: ToggleSwitch(
                  checked: appdata.settings['showOriginalImage'],
                  onChanged: (value) {
                    setState(() {
                      appdata.settings['showOriginalImage'] = value;
                    });
                    appdata.writeData();
                  })),
          buildItem(
              title: "Emphasize artworks from following artists".tl,
              subtitle: "The border of the artworks will be darker".tl,
              action: ToggleSwitch(
                  checked:
                      appdata.settings['emphasizeArtworksFromFollowingArtists'],
                  onChanged: (value) {
                    setState(() {
                      appdata.settings[
                          'emphasizeArtworksFromFollowingArtists'] = value;
                    });
                    appdata.writeData();
                  })),
        ],
      ),
    );
  }

  Widget buildAppearance() {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          buildItem(
                  title: "Theme".tl,
                  action: DropDownButton(
                      title: Text(appdata.settings["theme"] ?? "System".tl),
                      items: [
                        MenuFlyoutItem(
                            text: Text("System".tl),
                            onPressed: () {
                              setState(() {
                                appdata.settings["theme"] = "System";
                              });
                              appdata.writeData();
                              StateController.findOrNull(tag: "MyApp")?.update();
                            }),
                        MenuFlyoutItem(
                            text: Text("light".tl),
                            onPressed: () {
                              setState(() {
                                appdata.settings["theme"] = "Light";
                              });
                              appdata.writeData();
                              StateController.findOrNull(tag: "MyApp")?.update();
                            }),
                        MenuFlyoutItem(
                            text: Text("dark".tl),
                            onPressed: () {
                              setState(() {
                                appdata.settings["theme"] = "Dark";
                              });
                              appdata.writeData();
                              StateController.findOrNull(tag: "MyApp")?.update();
                            }),
                      ])),
                        // Background image selection (disabled – custom theme removed)
                        // buildItem(
                        //   title: "Background Image".tl,
                        //   subtitle: appdata.settings["themeBackground"]?.isEmpty ?? true ? "Default".tl : appdata.settings["themeBackground"],
                        //   action: Button(
                        //     child: Text("Select".tl).fixWidth(64),
                        //     onPressed: () async {
                        //       final XFile? file = await openFile(
                        //         acceptedTypeGroups: [
                        //           XTypeGroup(label: 'Image', extensions: ['png', 'jpg', 'jpeg', 'webp'])
                        //         ],
                        //       );
                        //       if (file != null) {
                        //         setState(() {
                        //           appdata.settings["themeBackground"] = file.path;
                        //         });
                        //         appdata.writeData();
                        //         StateController.findOrNull(tag: "MyApp")?.update();
                        //       }
                        //     },
                        //   ),
                        // ),
// Primary color (hex) with color picker (disabled – custom theme removed)
            // buildItem(
            //   title: "Primary Color".tl,
            //   subtitle: appdata.settings["themeColor"]?.isEmpty ?? true ? "Default".tl : appdata.settings["themeColor"],
            //   action: Button(
            //     child: Text("Set".tl).fixWidth(64),
            //     onPressed: () async {
            //       await _pickHexColor("Primary Color".tl, "themeColor");
            //     },
            //   ),
            // ),
          buildItem(
              title: "Language".tl,
              action: DropDownButton(
                  title: Text(appdata.settings["language"] ?? "System"),
                  items: [
                    MenuFlyoutItem(
                        text: const Text("System"),
                        onPressed: () {
                          setState(() {
                            appdata.settings["language"] = "System";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        }),
                    MenuFlyoutItem(
                        text: const Text("English"),
                        onPressed: () {
                          setState(() {
                            appdata.settings["language"] = "English";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        }),
                    MenuFlyoutItem(
                        text: const Text("简体中文"),
                        onPressed: () {
                          setState(() {
                            appdata.settings["language"] = "简体中文";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        }),
                    MenuFlyoutItem(
                        text: const Text("繁體中文"),
                        onPressed: () {
                          setState(() {
                            appdata.settings["language"] = "繁體中文";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        }),
                    MenuFlyoutItem(
                        text: const Text("日本語"),
                        onPressed: () {
                          setState(() {
                            appdata.settings["language"] = "日本語";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        }),
                  ])),

            // Background opacity (disabled – custom theme removed)
            // buildItem(
            //   title: "Background Opacity".tl,
            //   subtitle: ((appdata.settings["themeBackgroundOpacity"] as num?)?.toDouble() ?? 1.0).toStringAsFixed(2),
            //   action: Slider(
            //     value: (appdata.settings["themeBackgroundOpacity"] as num?)?.toDouble() ?? 1.0,
            //     min: 0.0,
            //     max: 1.0,
            //     onChanged: (v) {
            //       setState(() {
            //         appdata.settings["themeBackgroundOpacity"] = v;
            //       });
            //       appdata.writeData();
            //       StateController.findOrNull(tag: "MyApp")?.update();
            //     },
            //   ),
            // ),
// Background color with color picker (disabled – custom theme removed)
            // buildItem(
            //   title: "Background Color".tl,
            //   subtitle: appdata.settings["themeBackgroundColor"]?.isEmpty ?? true ? "Default".tl : appdata.settings["themeBackgroundColor"],
            //   action: Button(
            //     child: Text("Set".tl).fixWidth(64),
            //     onPressed: () async {
            //       await _pickHexColor("Background Color".tl, "themeBackgroundColor");
            //     },
            //   ),
            // ),
// Text color with color picker
            // Text color with color picker (disabled – custom theme removed)
            // buildItem(
            //   title: "Text Color".tl,
            //   subtitle: appdata.settings["textColor"]?.isEmpty ?? true ? "Default".tl : appdata.settings["textColor"],
            //   action: Button(
            //     child: Text("Set".tl).fixWidth(64),
            //     onPressed: () async {
            //       await _pickHexColor("Text Color".tl, "textColor");
            //     },
            //   ),
            // ),
// Icon color with color picker
            // Icon color with color picker (disabled – custom theme removed)
            // buildItem(
            //   title: "Icon Color".tl,
            //   subtitle: appdata.settings["iconColor"]?.isEmpty ?? true ? "Default".tl : appdata.settings["iconColor"],
            //   action: Button(
            //     child: Text("Set".tl).fixWidth(64),
            //     onPressed: () async {
            //       await _pickHexColor("Icon Color".tl, "iconColor");
            //     },
            //   ),
            // ),
          // Font selection
          buildItem(
              title: "Font".tl,
              subtitle: appdata.settings["customFont"]?.isEmpty ?? true
                  ? "Default".tl
                  : appdata.settings["customFont"],
              action: Button(
                child: Text("Select".tl).fixWidth(64),
                onPressed: () {
                  context.to(() => const _FontSelectionPage());
                },
              )),
        ],
      ),
    );
  }

  Widget buildSecurity() {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          buildItem(
              title: "Lock App".tl,
              action: ToggleSwitch(
                  checked: appdata.settings["lockEnabled"] ?? false,
                  onChanged: (value) {
                    setState(() {
                      appdata.settings["lockEnabled"] = value;
                    });
                    appdata.writeData();
                  })),
          buildItem(
              title: "Password".tl,
              action: Button(
                child: Text("Set".tl).fixWidth(64),
                onPressed: () {
                  context.to(() => _SetSingleFieldPage(
                        "Password".tl,
                        "lockPassword",
                      ));
                },
              )),
          buildItem(
              title: "PIN".tl,
              action: Button(
                child: Text("Set".tl).fixWidth(64),
                onPressed: () {
                  context.to(() => _SetSingleFieldPage(
                        "PIN".tl,
                        "lockPin",
                      ));
                },
              )),
          // Private Mode toggle
          buildItem(
              title: "Private Mode".tl,
              action: ToggleSwitch(
                  checked: appdata.settings["privateMode"] ?? false,
                  onChanged: (value) {
                    setState(() {
                      appdata.settings["privateMode"] = value;
                    });
                    appdata.writeData();
                  })),
          // Export / Import Data
          buildItem(
              title: "Export Data".tl,
              action: Button(
                child: Text("Export".tl).fixWidth(64),
                onPressed: () async {
                  final browsingHistory = HistoryManager().getAll().map((h) => {
                    'id': h.id,
                    'imgPath': h.imgPath,
                    'time': h.time.millisecondsSinceEpoch,
                    'imageCount': h.imageCount,
                    'isR18': h.isR18 ? 1 : 0,
                    'isR18G': h.isR18G ? 1 : 0,
                    'isAi': h.isAi ? 1 : 0,
                    'isGif': h.isGif ? 1 : 0,
                    'width': h.width,
                    'height': h.height,
                  }).toList();
                  final jsonData = jsonEncode({
                    "settings": appdata.settings,
                    "account": appdata.account?.toJson(),
                    "searchHistory": appdata.getSearchHistory().map((e) => e.toJson()).toList(),
                    "browsingHistory": browsingHistory,
                  });
                  final tempFile = File('${Directory.systemTemp.path}/pixes_export_${DateTime.now().millisecondsSinceEpoch}.json');
                  await tempFile.writeAsString(jsonData);
                  // reuse saveFile utility
                  saveFile(tempFile, 'pixes_export.json');
                },
              )),
          buildItem(
              title: "Import Data".tl,
              action: Button(
                child: Text("Import".tl).fixWidth(64),
                onPressed: () async {
                  final XFile? file = await openFile(
                    acceptedTypeGroups: [
                      XTypeGroup(label: 'JSON', extensions: ['json'])
                    ],
                  );
                  if (file != null) {
                    final String content = await file.readAsString();
                    final Map<String, dynamic> map = jsonDecode(content);
                    if (map.containsKey('settings')) {
                      appdata.settings = {...appdata.settings, ...map['settings']};
                    }
                    if (map.containsKey('account') && map['account'] != null) {
                      appdata.account = Account.fromJson(map['account']);
                    }
                    if (map.containsKey('searchHistory')) {
                      final list = (map['searchHistory'] as List)
                          .map((e) => SearchHistoryEntry.fromJson(e as Map<String, dynamic>))
                          .toList();
                      appdata.importSearchHistory(list);
                    }
                    if (map.containsKey('browsingHistory')) {
                      final list = (map['browsingHistory'] as List).map((h) => IllustHistory(
                        h['id'],
                        h['imgPath'],
                        DateTime.fromMillisecondsSinceEpoch(h['time']),
                        h['imageCount'],
                        h['isR18'] == 1,
                        h['isR18G'] == 1,
                        h['isAi'] == 1,
                        h['isGif'] == 1,
                        h['width'],
                        h['height'],
                      )).toList();
                      HistoryManager().importAll(list);
                    }
                    appdata.writeData();
                    StateController.findOrNull(tag: "MyApp")?.update();
                  }
                },
              )),
          buildItem(
              title: "Search history limit".tl,
              subtitle: (appdata.settings["searchHistoryLimit"] as int? ?? 50) <= 0
                  ? "Unlimited".tl
                  : appdata.settings["searchHistoryLimit"].toString(),
              action: Button(
                child: Text("Manage".tl).fixWidth(64),
                onPressed: () async {
                  int value = appdata.settings["searchHistoryLimit"] as int? ?? 50;
                  await showDialog(
                    context: context,
                    builder: (c) => ContentDialog(
                      title: Text("Search history limit".tl),
                      content: StatefulBuilder(
                        builder: (context, setDialogState) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text("Set 0 for unlimited".tl),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: 100,
                              child: NumberBox<int>(
                                value: value,
                                mode: SpinButtonPlacementMode.none,
                                min: 0,
                                max: 99999,
                                onChanged: (v) => setDialogState(() { if (v != null) value = v; }),
                              ),
                            ),
                          ],
                        ),
                      ),
                      actions: [
                        Button(
                          child: Text("Cancel".tl),
                          onPressed: () => c.pop(),
                        ),
                        FilledButton(
                          child: Text("Save".tl),
                          onPressed: () {
                            setState(() {
                              appdata.settings["searchHistoryLimit"] = value;
                            });
                            appdata.writeData();
                            c.pop();
                          },
                        ),
                      ],
                    ),
                  );
                },
              )),
        ],
      ),
    );
    }

  Widget buildSync() {
    return SliverToBoxAdapter(
      child: Column(
        children: [
          buildItem(
              title: "Sync Settings".tl,
              subtitle: appdata.settings["syncEnabled"] == true
                  ? "Enabled".tl
                  : "Disabled".tl,
              action: Button(
                child: Text("Open".tl).fixWidth(64),
                onPressed: () {
                  context.to(() => const SyncPage());
                },
              )),
        ],
      ),
    );
  }

}

class _SetSingleFieldPage extends StatefulWidget {
  const _SetSingleFieldPage(this.title, this.field, {this.check});

  final String title;

  final String field;

  final String? Function(String)? check;

  @override
  State<_SetSingleFieldPage> createState() => _SetSingleFieldPageState();
}

class _SetSingleFieldPageState extends State<_SetSingleFieldPage> {
  late final controller =
      TextEditingController(text: appdata.settings[widget.field]);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TitleBar(title: widget.title),
        TextBox(
          controller: controller,
        ).paddingHorizontal(16),
        const SizedBox(
          height: 8,
        ),
        Button(
          child: Text("Confirm".tl),
          onPressed: () {
            var text = controller.text;
            var checkRes = widget.check?.call(text);
            if (checkRes == null) {
              appdata.settings[widget.field] = text;
              appdata.writeData();
              context.pop();
            } else {
              showToast(context, message: checkRes);
            }
          },
        ).toAlign(Alignment.centerRight).paddingRight(16),
      ],
    );
    }

}


class _SetDownloadSubPathPage extends StatefulWidget {
  const _SetDownloadSubPathPage();

  @override
  State<_SetDownloadSubPathPage> createState() =>
      __SetDownloadSubPathPageState();
}

class __SetDownloadSubPathPageState extends State<_SetDownloadSubPathPage> {
  final controller =
      TextEditingController(text: appdata.settings["downloadSubPath"]);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TitleBar(title: "Download subpath".tl),
          Text("Rule".tl)
              .padding(const EdgeInsets.symmetric(vertical: 8, horizontal: 16)),
          TextBox(
            controller: controller,
          ).paddingHorizontal(16),
          const SizedBox(
            height: 8,
          ),
          Button(
            child: Text("Confirm".tl),
            onPressed: () {
              var text = controller.text;
              if (check(text)) {
                appdata.settings["downloadSubPath"] = text;
                appdata.writeData();
                context.pop();
              } else {
                showToast(context, message: "Invalid".tl);
              }
            },
          ).toAlign(Alignment.centerRight).paddingRight(16),
          const SizedBox(
            height: 16,
          ),
          SelectableText(_instruction).paddingHorizontal(16)
        ],
      ),
    );
  }

  bool check(String text) {
    if (text.startsWith('/') || text.startsWith('\\')) {
      return true;
    }
    return false;
  }

  String get _instruction => """
${"Edit the rule for where to save an image.".tl}
${"Note: The rule should include the filename.".tl}

${"Some keywords will be replaced by the following rule:".tl}
  \${title} -> ${"Title of the work".tl}
  \${author} -> ${"Name of the author".tl}
  \${id} -> ${"Artwork ID".tl}
  \${index} -> ${"Index of the image in the artwork".tl}
  \${page} -> ${"Replace with '-p\${index}' if the work have more than one images, otherwise replace with blank.".tl}
  \${ext} -> ${"File extension".tl}
  \${AI} -> ${"Replace with 'AI' if the work was generated by AI, otherwise replace with blank".tl}
  \${tag(*)} -> ${"Replace with * if the work have tag *, otherwise replace with blank.".tl}

${"Multiple path separators will be automatically replaced with a single".tl}
""";

  // Helper: show a simple hex color picker (RGB sliders)
  Future<void> _pickHexColor(String title, String settingKey) async {
    // parse existing hex or default to white
    String current = (appdata.settings[settingKey] ?? "");
    int r = 255, g = 255, b = 255;
    if (current.startsWith('#') && current.length == 7) {
      try {
        r = int.parse(current.substring(1, 3), radix: 16);
        g = int.parse(current.substring(3, 5), radix: 16);
        b = int.parse(current.substring(5, 7), radix: 16);
      } catch (_) {}
    }
    double rVal = r.toDouble();
    double gVal = g.toDouble();
    double bVal = b.toDouble();
    await showDialog(
      context: context,
      builder: (c) => ContentDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, innerSetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('R'),
              Slider(
                min: 0,
                max: 255,
                divisions: 255,
                value: rVal,
                onChanged: (v) => innerSetState(() => rVal = v),
              ),
              const Text('G'),
              Slider(
                min: 0,
                max: 255,
                divisions: 255,
                value: gVal,
                onChanged: (v) => innerSetState(() => gVal = v),
              ),
              const Text('B'),
              Slider(
                min: 0,
                max: 255,
                divisions: 255,
                value: bVal,
                onChanged: (v) => innerSetState(() => bVal = v),
              ),
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 40,
                color: Color.fromRGBO(rVal.toInt(), gVal.toInt(), bVal.toInt(), 1),
              ),
            ],
          ),
        ),
        actions: [
          Button(
            child: Text('Confirm'.tl),
            onPressed: () {
              final hex = '#'
                  '${rVal.toInt().toRadixString(16).padLeft(2, '0')}'
                  '${gVal.toInt().toRadixString(16).padLeft(2, '0')}'
                  '${bVal.toInt().toRadixString(16).padLeft(2, '0')}';
              setState(() {
                appdata.settings[settingKey] = hex;
              });
              appdata.writeData();
              StateController.findOrNull(tag: "MyApp")?.update();
              c.pop();
            },
          ),
        ],
      ),
    );
    }

}


class _BlockTagsPage extends StatefulWidget {
  const _BlockTagsPage();

  @override
  State<_BlockTagsPage> createState() => __BlockTagsPageState();
}

class __BlockTagsPageState extends State<_BlockTagsPage> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TitleBar(
          title: "Block".tl,
          action: FilledButton(
            child: Text("Add".tl),
            onPressed: () {
              var controller = TextEditingController();

              void finish(BuildContext context) {
                var text = controller.text;
                if (text.isNotEmpty &&
                    !(appdata.settings["blockTags"] as List).contains(text)) {
                  setState(() {
                    appdata.settings["blockTags"].add(text);
                  });
                  appdata.writeSettings();
                }
                context.pop();
              }

              showDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (context) {
                    return ContentDialog(
                      title: Text("Add".tl),
                      content: SizedBox(
                        width: 300,
                        height: 32,
                        child: TextBox(
                          controller: controller,
                          onSubmitted: (v) => finish(context),
                        ),
                      ),
                      actions: [
                        FilledButton(
                            child: Text("Submit".tl),
                            onPressed: () {
                              finish(context);
                            })
                      ],
                    );
                  });
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: appdata.settings["blockTags"].length,
            itemBuilder: (context, index) {
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: EdgeInsets.zero,
                child: ListTile(
                  title: Text(appdata.settings["blockTags"][index]),
                  trailing: Button(
                    child: Text("Delete".tl),
                    onPressed: () {
                      setState(() {
                        (appdata.settings["blockTags"] as List).removeAt(index);
                      });
                      appdata.writeSettings();
                    },
                  ),
                ),
              );
            },
          ),
        )
      ],
    );
    }

}


class ShortcutsSettings extends StatefulWidget {
  const ShortcutsSettings({super.key});

  @override
  State<ShortcutsSettings> createState() => _ShortcutsSettingsState();
}

class _ShortcutsSettingsState extends State<ShortcutsSettings> {
  int listening = -1;

  KeyEventListenerState? listener;

  @override
  void initState() {
    listener = KeyEventListener.of(context);
    super.initState();
  }

  @override
  void dispose() {
    listener?.removeAll();
    super.dispose();
  }

  final settings = <String>[
    "Page down",
    "Page up",
    "Next work",
    "Previous work",
    "Add to favorites",
    "Download",
    "Follow the artist",
    "Show comments",
    "Show original image"
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(children: [
        TitleBar(title: "Shortcuts".tl),
        ...settings.map((e) => buildItem(e, settings.indexOf(e)))
      ]),
    );
  }

  Widget buildItem(String text, int index) {
    var keyText = listening == index
        ? "Waiting..."
        : LogicalKeyboardKey(appdata.settings['shortcuts'][index]).keyLabel;
    return Card(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
      child: ListTile(
        title: Text(text.tl),
        trailing: Button(
          child: Text(keyText),
          onPressed: () {
            if (listening != -1) {
              listener?.removeAll();
            }
            setState(() {
              listening = index;
            });
            listener?.addHandler((key) {
              if (key == LogicalKeyboardKey.escape) return;
              setState(() {
                appdata.settings['shortcuts'][index] = key.keyId;
                listening = -1;
                appdata.writeData();
              });
              Future.microtask(() => listener?.removeAll());
            });
          },
        ),
      ),
    );
    }

}


class _SetInitialPageWidget extends StatefulWidget {
  const _SetInitialPageWidget();

  @override
  State<_SetInitialPageWidget> createState() => _SetInitialPageWidgetState();
}

class _SetInitialPageWidgetState extends State<_SetInitialPageWidget> {
  int index = appdata.settings["initialPage"] ?? 4;

  static const pageNames = [
    "Search",
    "Downloading",
    "Downloaded",
    "Explore",
    "Bookmarks",
    "Following",
    "History",
    "Ranking",
    "Recommendation",
    "Bookmarks",
    "Following",
    "Ranking",
  ];

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: TitleBar(title: "Initial Page".tl),
      content: ListView.builder(
        itemCount: pageNames.length + 2,
        itemBuilder: (context, index) {
          if (index == 3) {
            return Text('${"Illustrations".tl}/${"Manga".tl}')
                .paddingHorizontal(16)
                .paddingVertical(8);
          } else if (index > 3) {
            index--;
          }
          if (index == 8) {
            return Text("Novel".tl).paddingHorizontal(16).paddingVertical(8);
          } else if (index > 8) {
            index--;
          }

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: EdgeInsets.zero,
            child: ListTile(
              title: Text(pageNames[index].tl),
              trailing: RadioButton(
                checked: this.index - 1 == index,
                onChanged: (value) {
                  setState(() {
                    this.index = index + 1;
                    appdata.settings["initialPage"] = index + 1;
                    appdata.writeData();
                  });
                },
              ),
            ),
          );
        },
      ),
    );
    }

}


class _MacosDownloadPathSelectButton extends StatefulWidget {
  const _MacosDownloadPathSelectButton({this.onSelected});

  final void Function(String)? onSelected;

  @override
  State<_MacosDownloadPathSelectButton> createState() =>
      _MacosDownloadPathSelectButtonState();
}

class _MacosDownloadPathSelectButtonState
    extends State<_MacosDownloadPathSelectButton> {
  static const _channel = MethodChannel("pixes/macos/download_path");

  bool _selecting = false;

  @override
  Widget build(BuildContext context) {
    return Button(
      onPressed: _selecting
          ? null
          : () async {
              setState(() {
                _selecting = true;
              });
              try {
                final selectedPath = await _channel.invokeMethod<String>(
                  "selectDownloadDirectory",
                  {"initialPath": appdata.settings["downloadPath"]},
                );
                if (!context.mounted || selectedPath == null) {
                  return;
                }
                widget.onSelected?.call(selectedPath);
              } on PlatformException catch (e) {
                if (context.mounted) {
                  showToast(context, message: e.message ?? e.code);
                }
              } finally {
                if (context.mounted) {
                  setState(() {
                    _selecting = false;
                  });
                }
              }
            },
      child: Text(_selecting ? "..." : "Manage".tl).fixWidth(64),
    );
    }

}


class _FontSelectionPage extends StatefulWidget {
  const _FontSelectionPage();

  @override
  State<_FontSelectionPage> createState() => _FontSelectionPageState();
}

class _FontSelectionPageState extends State<_FontSelectionPage> {
  List<String> systemFonts = [];
  List<String> filteredFonts = [];
  String? selectedFont;
  bool isLoading = true;
  final TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    selectedFont = appdata.settings["customFont"];
    loadSystemFonts();
    searchController.addListener(() {
      filterFonts();
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  void filterFonts() {
    final query = searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        filteredFonts = systemFonts;
      } else {
        filteredFonts = systemFonts.where((font) {
          final fontName = font.split(Platform.pathSeparator).last.toLowerCase();
          return fontName.contains(query);
        }).toList();
      }
    });
  }

  Future<void> loadSystemFonts() async {
    setState(() {
      isLoading = true;
    });

    List<String> fonts = [];

    if (Platform.isWindows) {
      fonts = await _getWindowsFonts();
    } else if (Platform.isMacOS) {
      fonts = await _getMacOSFonts();
    } else if (Platform.isLinux) {
      fonts = await _getLinuxFonts();
    }

    setState(() {
      systemFonts = fonts;
      filteredFonts = fonts;
      isLoading = false;
    });
  }

  Future<List<String>> _getWindowsFonts() async {
    final fontsDir = Directory(r'C:\Windows\Fonts');
    if (!await fontsDir.exists()) {
      return [];
    }

    final fontFiles = fontsDir.listSync().where((entity) {
      final name = entity.path.toLowerCase();
      return name.endsWith('.ttf') || name.endsWith('.otf') || name.endsWith('.ttc');
    }).toList();

    return fontFiles.map((f) => f.path).toList();
  }

  Future<List<String>> _getMacOSFonts() async {
    final fontDirs = [
      Directory('/Library/Fonts'),
      Directory('~/Library/Fonts'),
    ];

    List<String> fonts = [];
    for (final dir in fontDirs) {
      if (await dir.exists()) {
        final fontFiles = dir.listSync().where((entity) {
          final name = entity.path.toLowerCase();
          return name.endsWith('.ttf') || name.endsWith('.otf') || name.endsWith('.ttc');
        }).toList();
        fonts.addAll(fontFiles.map((f) => f.path));
      }
    }

    return fonts;
  }

  Future<List<String>> _getLinuxFonts() async {
    final fontDirs = [
      Directory('/usr/share/fonts'),
      Directory('/usr/local/share/fonts'),
      Directory('~/.local/share/fonts'),
    ];

    List<String> fonts = [];
    for (final dir in fontDirs) {
      if (await dir.exists()) {
        final fontFiles = dir.listSync(recursive: true).where((entity) {
          final name = entity.path.toLowerCase();
          return name.endsWith('.ttf') || name.endsWith('.otf') || name.endsWith('.ttc');
        }).toList();
        fonts.addAll(fontFiles.map((f) => f.path));
      }
    }

    return fonts;
  }

  Future<void> _selectFontFile() async {
    const XTypeGroup typeGroup = XTypeGroup(
      label: 'Font files',
      extensions: ['ttf', 'otf', 'ttc'],
    );

    final XFile? file = await openFile(acceptedTypeGroups: [typeGroup]);

    if (file != null) {
      setState(() {
        selectedFont = file.path;
        appdata.settings["customFont"] = file.path;
      });
      appdata.writeData();
      StateController.findOrNull(tag: "MyApp")?.update();
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: TitleBar(title: "Font Selection".tl),
      content: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Button(
                  child: Text("Select Font File".tl),
                  onPressed: _selectFontFile,
                ),
                const SizedBox(width: 16),
                Button(
                  child: Text("Reset to Default".tl),
                  onPressed: () {
                    setState(() {
                      selectedFont = "";
                      appdata.settings["customFont"] = "";
                    });
                    appdata.writeData();
                    StateController.findOrNull(tag: "MyApp")?.update();
                    context.pop();
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextBox(
              controller: searchController,
              placeholder: "Search fonts".tl,
              prefix: const Icon(FluentIcons.search),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          Expanded(
            child: isLoading
                ? const Center(child: ProgressRing())
                : ListView.builder(
                    itemCount: filteredFonts.length,
                    itemBuilder: (context, index) {
                      final fontPath = filteredFonts[index];
                      final fontName = fontPath.split(Platform.pathSeparator).last;
                      final isSelected = selectedFont == fontPath;

return ListTile(
                          // Show font family name (file name without extension) and full path
                          title: Text(fontPath.split(Platform.pathSeparator).last.split('.').first),
                          subtitle: Text(fontPath, style: const TextStyle(fontSize: 12)),
                          leading: isSelected ? const Icon(FluentIcons.check_mark) : null,
                          onPressed: () {
                            setState(() {
                              selectedFont = fontPath;
                              appdata.settings["customFont"] = fontPath;
                            });
                            appdata.writeData();
                            StateController.findOrNull(tag: "MyApp")?.update();
                            context.pop();
                          },
                        );
                    },
                  ),
          ),
        ],
      ),
    );
    }

}

