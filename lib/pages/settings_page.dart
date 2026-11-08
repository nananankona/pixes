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
import 'package:pixes/foundation/cache_manager.dart';
import 'package:pixes/foundation/history.dart';
import 'package:pixes/pages/main_page.dart';
import 'package:pixes/pages/sync_page.dart';
import 'package:pixes/utils/io.dart';
import 'package:pixes/utils/update.dart';
import 'package:pixes/utils/translation.dart';
import 'package:pixes/utils/theme_background.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'logs.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // Helper: HSV color picker with hex input + recent colors
  Future<void> _pickHexColor(String title, String settingKey) async {
    Color current = _parseHexColor(
            (appdata.settings[settingKey] as String?) ?? "") ??
        Colors.white;
    var hsv = HSVColor.fromColor(current);
    final hexCtl = TextEditingController(
        text:
            '#${current.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}');
    await showDialog(
      context: context,
      builder: (c) => ContentDialog(
        title: Text(title),
        content: StatefulBuilder(
          builder: (context, innerSetState) {
            void applyHsv(HSVColor v) {
              hsv = v;
              final col = v.toColor();
              hexCtl.text =
                  '#${col.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
            }

            final raw = appdata.settings["recentColors"];
            final recents = raw is List
                ? raw.map((e) => e.toString()).take(8).toList()
                : <String>[];
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: hsv.toColor(),
                      border: Border.all(
                          color: ColorScheme.of(context).outlineVariant),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('H'),
                  Slider(
                      min: 0,
                      max: 360,
                      value: hsv.hue,
                      onChanged: (v) => innerSetState(
                          () => applyHsv(hsv.withHue(v)))),
                  const Text('S'),
                  Slider(
                      min: 0,
                      max: 1,
                      value: hsv.saturation,
                      onChanged: (v) => innerSetState(
                          () => applyHsv(hsv.withSaturation(v)))),
                  const Text('V'),
                  Slider(
                      min: 0,
                      max: 1,
                      value: hsv.value,
                      onChanged: (v) =>
                          innerSetState(() => applyHsv(hsv.withValue(v)))),
                  const SizedBox(height: 4),
                  TextBox(
                    controller: hexCtl,
                    placeholder: '#RRGGBB',
                    onChanged: (v) {
                      final col = _parseHexColor(v);
                      if (col != null) {
                        innerSetState(() {
                          hsv = HSVColor.fromColor(col);
                        });
                      }
                    },
                  ),
                  if (recents.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Recent'.tl,
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final hex in recents)
                          GestureDetector(
                            onTap: () {
                              final col = _parseHexColor(hex);
                              if (col != null) {
                                innerSetState(() {
                                  applyHsv(HSVColor.fromColor(col));
                                });
                              }
                            },
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _parseHexColor(hex),
                                border: Border.all(
                                    color: ColorScheme.of(context)
                                        .outlineVariant),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        actions: [
          Button(
            child: Text('Confirm'.tl),
            onPressed: () {
              var hex = hexCtl.text.trim();
              if (!hex.startsWith('#')) hex = '#$hex';
              final col = _parseHexColor(hex) ?? hsv.toColor();
              hex =
                  '#${col.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
              final raw = appdata.settings["recentColors"];
              final recents = raw is List
                  ? raw.map((e) => e.toString()).toList()
                  : <String>[];
              recents.remove(hex);
              recents.insert(0, hex);
              appdata.settings["recentColors"] =
                  recents.take(8).toList();
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

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    var cleaned = hex.replaceFirst('#', '');
    if (cleaned.length == 6) cleaned = 'FF$cleaned';
    if (cleaned.length != 8) return null;
    final v = int.tryParse(cleaned, radix: 16);
    if (v == null) return null;
    return Color(v);
  }

  Widget _accentDot(BuildContext context, String? hex) {
    final current = (appdata.settings["accentColor"] as String?) ?? "";
    final selected =
        (hex == null && current.isEmpty) || (hex != null && hex.toUpperCase() == current.toUpperCase());
    final color = hex == null
        ? FluentTheme.of(context).accentColor.normal
        : _parseHexColor(hex) ?? FluentTheme.of(context).accentColor.normal;
    return GestureDetector(
      onTap: () {
        setState(() {
          appdata.settings["accentColor"] = hex ?? "";
        });
        appdata.writeData();
        StateController.findOrNull(tag: "MyApp")?.update();
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hex == null ? null : color,
          gradient: hex == null
              ? LinearGradient(colors: [
                  FluentTheme.of(context).accentColor.light,
                  FluentTheme.of(context).accentColor.dark,
                ])
              : null,
          border: Border.all(
            color: selected
                ? FluentTheme.of(context).accentColor
                : ColorScheme.of(context).outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: hex == null
            ? const Icon(FluentIcons.clear, size: 14)
            : null,
      ),
    );
  }

  Widget _themeColorDot(
      BuildContext context, String settingKey, String? hex) {
    final current = (appdata.settings[settingKey] as String?) ?? "";
    final selected =
        (hex == null && current.isEmpty) || (hex != null && hex.toUpperCase() == current.toUpperCase());
    final color = hex == null
        ? null
        : _parseHexColor(hex) ?? FluentTheme.of(context).accentColor.normal;
    return GestureDetector(
      onTap: () {
        setState(() {
          appdata.settings[settingKey] = hex ?? "";
        });
        appdata.writeData();
        StateController.findOrNull(tag: "MyApp")?.update();
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected
                ? FluentTheme.of(context).accentColor
                : ColorScheme.of(context).outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: hex == null
            ? const Icon(FluentIcons.clear, size: 14)
            : null,
      ),
    );
  }

  Widget _bgColorDot(BuildContext context, String? hex) {
    final current = (appdata.settings["themeBackgroundColor"] as String?) ?? "";
    final selected =
        (hex == null && current.isEmpty) || (hex != null && hex.toUpperCase() == current.toUpperCase());
    final color = hex == null
        ? null
        : _parseHexColor(hex) ?? FluentTheme.of(context).accentColor.normal;
    return GestureDetector(
      onTap: () {
        setState(() {
          appdata.settings["themeBackgroundColor"] = hex ?? "";
        });
        appdata.writeData();
        StateController.findOrNull(tag: "MyApp")?.update();
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected
                ? FluentTheme.of(context).accentColor
                : ColorScheme.of(context).outlineVariant,
            width: selected ? 3 : 1,
          ),
        ),
        child: hex == null
            ? const Icon(FluentIcons.clear, size: 14)
            : null,
      ),
    );
  }

  @override
  int section = 0;

  String settingsQuery = "";

  static const _settingIndex = [
    [0, "Logout"], [0, "Account Settings"], [0, "Hide Email"],
    [0, "Hide Account Icon"], [0, "Hide Account Name"],
    [1, "Initial Page"], [1, "Proxy"], [1, "Block(Account)"],
    [1, "Block(Local)"], [1, "Shortcuts"],
    [1, "Display the original image on the details page"],
    [1, "Preload images"], [1, "Slideshow interval (seconds)"],
    [1, "Loop slideshow"],
    [1, "Emphasize artworks from following artists"],
    [1, "Novel auto-scroll speed"], [1, "Illust auto-scroll speed"],
    [3, "Text shadow"], [3, "Text color"], [3, "Icon color"],
    [3, "Shadow color"], [3, "Card opacity"],
    [1, "Network mode"], [1, "Image mirror host"],
    [2, "Auto-save on bookmark"], [2, "Auto-bookmark on save"],
    [1, "Auto advance to next artwork"],
    [2, "Download Path"], [2, "Subpath"], [2, "Max parallels"],
    [2, "Folder organization"], [2, "Auto download on view"],
    [2, "Cache limit (MB)"], [2, "Clear image cache"],
    [3, "Theme"], [3, "Accent color"], [3, "Background image"],
    [3, "Background opacity"], [3, "Background color"],
    [3, "Background blur"], [3, "Language"], [3, "Font"],
    [4, "Lock App"], [4, "Password"], [4, "PIN"], [4, "Private Mode"],
    [4, "Export Data"], [4, "Import Data"],
    [4, "Search history limit"],
    [5, "Sync Settings"],
    [6, "Version"], [6, "Check for updates on startup"],
    [6, "Github"], [6, "Twitter"], [6, "Logs"],
  ];

  List<List<dynamic>> get _settingMatches {
    final q = settingsQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _settingIndex.where((e) {
      final title = (e[1] as String);
      return title.toLowerCase().contains(q) ||
          title.tl.toLowerCase().contains(q);
    }).toList();
  }


  static const _sectionTitles = [
    "Account",
    "Browse",
    "Download",
    "Appearance",
    "Security",
    "Sync",
    "About",
  ];

  static const _sectionIcons = [
    MdIcons.person,
    MdIcons.explore,
    MdIcons.download,
    MdIcons.palette,
    MdIcons.security,
    MdIcons.sync,
    MdIcons.info,
  ];

  List<Widget> _sectionSlivers() {
    final title = _sectionTitles[section].tl;
    final Widget body;
    switch (section) {
      case 0:
        body = buildAccount();
        break;
      case 1:
        body = buildBrowse();
        break;
      case 2:
        body = buildDownload();
        break;
      case 3:
        body = buildAppearance();
        break;
      case 4:
        body = buildSecurity();
        break;
      case 5:
        body = buildSync();
        break;
      default:
        body = buildAbout();
        break;
    }
    return [
      SliverTitleBar(title: title),
      body,
      SliverPadding(padding: EdgeInsets.only(bottom: context.padding.bottom)),
    ];
  }

  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.widthOf(context) < 640;
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextBox(
              placeholder: "Search settings".tl,
              onChanged: (v) => setState(() => settingsQuery = v),
            ),
          ),
          Expanded(
            child: settingsQuery.trim().isNotEmpty
                ? _buildSearchResults()
                : (isNarrow ? _buildNarrowBody() : _buildWideBody()),
          ),
        ],
      ),
    );
  }

  Widget _buildWideBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 208,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ListView.builder(
            itemCount: _sectionTitles.length,
            itemBuilder: (context, i) {
              final selected = i == section;
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => section = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? FluentTheme.of(context)
                              .accentColor
                              .withValues(alpha: 0.15)
                          : null,
                      borderRadius: BorderRadius.circular(6),
                      border: selected
                          ? Border.all(
                              color: FluentTheme.of(context).accentColor)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Icon(_sectionIcons[i], size: 18),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_sectionTitles[i].tl)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(direction: Axis.vertical),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.02, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: CustomScrollView(
              key: ValueKey(section),
              slivers: _sectionSlivers(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNarrowBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: DropDownButton(
            title: Text(_sectionTitles[section].tl),
            items: [
              for (var i = 0; i < _sectionTitles.length; i++)
                MenuFlyoutItem(
                  text: Text(_sectionTitles[i].tl),
                  onPressed: () => setState(() => section = i),
                ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.02, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: CustomScrollView(
              key: ValueKey(section),
              slivers: _sectionSlivers(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final matches = _settingMatches;
    if (matches.isEmpty) {
      return Center(child: Text("No results".tl));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: matches.length,
      itemBuilder: (context, i) {
        final sec = matches[i][0] as int;
        final title = matches[i][1] as String;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: EdgeInsets.zero,
          child: ListTile(
            title: Text(title.tl),
            subtitle: Text(_sectionTitles[sec].tl),
            trailing: const Icon(FluentIcons.chevron_right, size: 14),
            onPressed: () => setState(() {
              section = sec;
              settingsQuery = "";
            }),
          ),
        );
      },
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
                        showToast(context,
                            message: "Saved to the Files app".tl);
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
                  if (!Platform.isIOS)
                    Button(
                        child: Text("Manage".tl).fixWidth(64),
                        onPressed: () {
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
          if ((appdata.settings["folderMode"] as int? ?? 0) == 3)
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
          buildItem(
              title: "Folder organization".tl,
              subtitle: switch (
                  appdata.settings["folderMode"] as int? ?? 0) {
                1 => "By author".tl,
                2 => "By author and artwork".tl,
                3 => "Custom pattern".tl,
                _ => "Off".tl,
              },
              action: DropDownButton(
                  title: Text(switch (
                      appdata.settings["folderMode"] as int? ?? 0) {
                    1 => "By author".tl,
                    2 => "By author and artwork".tl,
                    3 => "Custom pattern".tl,
                    _ => "Off".tl,
                  }),
                  items: [
                    for (final entry in [
                      (0, "Off"),
                      (1, "By author"),
                      (2, "By author and artwork"),
                      (3, "Custom pattern"),
                    ])
                      MenuFlyoutItem(
                          text: Text(entry.$2.tl),
                          onPressed: () {
                            setState(() {
                              appdata.settings["folderMode"] = entry.$1;
                            });
                            appdata.writeSettings();
                          }),
                  ])),
          buildItem(
              title: "Auto download on view".tl,
              action: DropDownButton(
                  title: Text(switch (
                      appdata.settings["autoDownload"] as int? ?? 0) {
                    1 => "Images only".tl,
                    2 => "Novels only".tl,
                    3 => "Both".tl,
                    _ => "Off".tl,
                  }),
                  items: [
                    for (final entry in [
                      (0, "Off"),
                      (1, "Images only"),
                      (2, "Novels only"),
                      (3, "Both"),
                    ])
                      MenuFlyoutItem(
                          text: Text(entry.$2.tl),
                          onPressed: () {
                            setState(() {
                              appdata.settings["autoDownload"] = entry.$1;
                            });
                            appdata.writeSettings();
                          }),
                  ])),
          buildItem(
              title: "Auto-save on bookmark".tl,
              subtitle: "Download when bookmarking".tl,
              action: ToggleSwitch(
                  checked:
                      appdata.settings["favoriteAutoSave"] == true,
                  onChanged: (value) {
                    setState(() {
                      appdata.settings["favoriteAutoSave"] = value;
                    });
                    appdata.writeData();
                  })),
          buildItem(
              title: "Auto-bookmark on save".tl,
              subtitle: "Bookmark when download completes".tl,
              action: ToggleSwitch(
                  checked:
                      appdata.settings["saveAutoFavorite"] == true,
                  onChanged: (value) {
                    setState(() {
                      appdata.settings["saveAutoFavorite"] = value;
                    });
                    appdata.writeData();
                  })),
          buildItem(
            title: "Cache limit (MB)".tl,
            subtitle: _cacheUsageText(),
            action: SizedBox(
              width: 96,
              height: 32,
              child: NumberBox<int>(
                value: appdata.settings["cacheLimitMB"],
                autofocus: false,
                min: 128,
                max: 32768,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    appdata.settings["cacheLimitMB"] = value;
                  });
                  CacheManager()
                      .setLimitSize(value * 1024 * 1024);
                  appdata.writeSettings();
                },
                clearButton: false,
                mode: SpinButtonPlacementMode.none,
              ),
            ),
          ),
          buildItem(
              title: "Clear image cache".tl,
              action: Button(
                child: Text("Clear".tl).fixWidth(64),
                onPressed: () async {
                  await CacheManager().clear();
                  if (mounted) {
                    context.showToast(message: "Done".tl);
                    setState(() {});
                  }
                },
              )),
        ],
      ),
    );
  }

  String _cacheUsageText() {
    final size = CacheManager().currentSize;
    if (size <= 0) return "Calculating...".tl;
    if (size >= 1024 * 1024 * 1024) {
      return "${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB";
    }
    return "${(size / 1024 / 1024).toStringAsFixed(1)} MB";
  }

  Widget buildAbout() {
    final accent = FluentTheme.of(context).accentColor;
    return SliverToBoxAdapter(
      child: Column(
        children: [
          // Hero header (same Card language as the rest)
          Card(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            padding: EdgeInsets.zero,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Row(
                children: [
                  const Icon(FluentIcons.picture, size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text("pixes",
                                style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Text("v${App.version}",
                                style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text("Unofficial Pixiv client".tl,
                            style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Feature highlights
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in [
                  (FluentIcons.picture, "Custom theme".tl),
                  (FluentIcons.sync, "Sync".tl),
                  (FluentIcons.speakers, "TTS".tl),
                  (FluentIcons.download, "Download".tl),
                  (FluentIcons.history, "History".tl),
                  (FluentIcons.search, "Search".tl),
                ])
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: accent.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(f.$1, size: 14, color: accent),
                        const SizedBox(width: 6),
                        Text(f.$2, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
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
              title: "Check for updates".tl,
              action: Button(
                child: Text("Check now".tl).fixWidth(64),
                onPressed: () => checkUpdate(manual: true),
              )),
          buildItem(
              title: "Github",
              subtitle: "nananankona/pixes",
              action: IconButton(
                icon: const Icon(
                  MdIcons.open_in_new,
                  size: 18,
                ),
                onPressed: () =>
                    launchUrlString("https://github.com/nananankona/pixes"),
              )),
          buildItem(
              title: "Twitter",
              subtitle: "@nananankona",
              action: IconButton(
                icon: const Icon(
                  MdIcons.open_in_new,
                  size: 18,
                ),
                onPressed: () =>
                    launchUrlString("https://twitter.com/nananankona"),
              )),
          buildItem(
              title: "Logs",
              subtitle: "Diagnostics & history".tl,
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
              title: "Network mode".tl,
              subtitle: "Restart required".tl,
              action: DropDownButton(
                  title: Text(switch (
                      appdata.settings["networkMode"] as int? ?? 0) {
                    1 => "DoH".tl,
                    2 => "Mirror".tl,
                    _ => "Normal".tl,
                  }),
                  items: [
                    for (final entry in [
                      (0, "Normal"),
                      (1, "DoH"),
                      (2, "Mirror"),
                    ])
                      MenuFlyoutItem(
                          text: Text(entry.$2.tl),
                          onPressed: () {
                            setState(() {
                              appdata.settings["networkMode"] = entry.$1;
                            });
                            appdata.writeData();
                          }),
                  ])),
          if ((appdata.settings["networkMode"] as int? ?? 0) == 2)
            buildItem(
                title: "Image mirror host".tl,
                subtitle: (appdata.settings["imageMirror"] as String?)
                            ?.isNotEmpty ==
                        true
                    ? appdata.settings["imageMirror"]
                    : "i.pximg.net",
                action: Button(
                  child: Text("Edit".tl).fixWidth(64),
                  onPressed: () {
                    context.to(() => _SetSingleFieldPage(
                          "Image mirror host".tl,
                          "imageMirror",
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
              title: "Preload images".tl,
              action: DropDownButton(
                  title: Text(switch (
                      appdata.settings["preloadMode"] as int? ?? 0) {
                    1 => "Next page".tl,
                    2 => "Next page and artwork".tl,
                    _ => "Off".tl,
                  }),
                  items: [
                    for (final entry in [
                      (0, "Off"),
                      (1, "Next page"),
                      (2, "Next page and artwork"),
                    ])
                      MenuFlyoutItem(
                          text: Text(entry.$2.tl),
                          onPressed: () {
                            setState(() {
                              appdata.settings["preloadMode"] = entry.$1;
                            });
                            appdata.writeData();
                          }),
                  ])),
          buildItem(
              title: "Slideshow interval (seconds)".tl,
              action: SizedBox(
                width: 96,
                height: 32,
                child: NumberBox<int>(
                  value:
                      (appdata.settings["slideshowInterval"] as num?)?.toInt() ??
                          3,
                  min: 1,
                  max: 60,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      appdata.settings["slideshowInterval"] = value;
                    });
                    appdata.writeSettings();
                  },
                  clearButton: false,
                  mode: SpinButtonPlacementMode.none,
                ),
              )),
          buildItem(
              title: "Loop slideshow".tl,
              subtitle: "Restart from the first page at the end".tl,
              action: ToggleSwitch(
                  checked: appdata.settings['slideshowLoop'] == true,
                  onChanged: (value) {
                    setState(() {
                      appdata.settings['slideshowLoop'] = value;
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
          buildItem(
              title: "Novel auto-scroll speed".tl,
              subtitle:
                  "${(appdata.settings["readingAutoScrollSpeed"] as num).toDouble().toStringAsFixed(0)} px/s",
              action: SizedBox(
                width: 160,
                child: Slider(
                  value: (appdata.settings["readingAutoScrollSpeed"] as num)
                      .toDouble(),
                  min: 20,
                  max: 200,
                  divisions: 18,
                  onChanged: (value) {
                    setState(() {
                      appdata.settings["readingAutoScrollSpeed"] = value;
                    });
                    appdata.writeSettings();
                  },
                ),
              )),
          buildItem(
              title: "Illust auto-scroll speed".tl,
              subtitle:
                  "${(appdata.settings["illustAutoScrollSpeed"] as num).toDouble().toStringAsFixed(0)} px/s",
              action: SizedBox(
                width: 160,
                child: Slider(
                  value: (appdata.settings["illustAutoScrollSpeed"] as num)
                      .toDouble(),
                  min: 100,
                  max: 600,
                  divisions: 10,
                  onChanged: (value) {
                    setState(() {
                      appdata.settings["illustAutoScrollSpeed"] = value;
                    });
                    appdata.writeSettings();
                  },
                ),
              )),
          buildItem(
              title: "Auto advance to next artwork".tl,
              subtitle: "When scrolled to the end".tl,
              action: ToggleSwitch(
                  checked: appdata.settings['autoAdvanceArtwork'] == true,
                  onChanged: (value) {
                    setState(() {
                      appdata.settings['autoAdvanceArtwork'] = value;
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
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Accent color".tl, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _accentDot(context, null),
                      for (final hex in [
                        '#0078D4', '#E81123', '#FF8C00', '#10893E',
                        '#00B7C3', '#8764B8', '#E3008C',
                      ])
                        _accentDot(context, hex),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Button(
                        onPressed: () => _pickHexColor(
                            "Accent color".tl, "accentColor"),
                        child: Text("Custom".tl).fixWidth(64),
                      ),
                      const SizedBox(width: 8),
                      Button(
                        onPressed: () {
                          setState(() {
                            appdata.settings["accentColor"] = "";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        },
                        child: Text("Default".tl).fixWidth(64),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          buildItem(
            title: "Background image".tl,
            subtitle: () {
              final p = appdata.settings["themeBackground"] as String?;
              return (p == null || p.isEmpty) ? "Default".tl : p;
            }(),
            action: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Button(
                  child: Text("Select".tl).fixWidth(64),
                  onPressed: () async {
                    XFile? file;
                    try {
                      file = await openFile(
                        acceptedTypeGroups: [
                          XTypeGroup(
                            label: 'Image',
                            extensions: const [
                              'png', 'jpg', 'jpeg', 'webp'
                            ],
                            // Required on iOS (extensions are ignored there).
                            uniformTypeIdentifiers: const ['public.image'],
                          ),
                        ],
                      );
                    } catch (_) {
                      if (context.mounted) {
                        context.showToast(message: 'Failed to open file'.tl);
                      }
                      return;
                    }
                    if (file != null) {
                      final installed =
                          await installThemeBackgroundFile(file!.path);
                      if (!mounted) return;
                      setState(() {});
                      if (installed == null && mounted) {
                        context.showToast(
                            message: 'Failed to open file'.tl);
                      }
                    }
                  },
                ),
                if ((appdata.settings["themeBackground"] as String?)
                        ?.isNotEmpty ==
                    true)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Button(
                      child: Text("Clear".tl).fixWidth(64),
                      onPressed: () async {
                        for (final e in ['png', 'jpg', 'jpeg', 'webp']) {
                          final stale =
                              File('${App.dataPath}/theme_background.$e');
                          if (await stale.exists()) {
                            try {
                              await stale.delete();
                            } catch (_) {}
                          }
                        }
                        setState(() {
                          appdata.settings["themeBackground"] = "";
                        });
                        appdata.writeData();
                        StateController.findOrNull(tag: "MyApp")?.update();
                      },
                    ),
                  ),
              ],
            ),
          ),
          buildItem(
            title: "Background opacity".tl,
            subtitle: ((appdata.settings["themeBackgroundOpacity"] as num?)
                        ?.toDouble() ??
                    0.5)
                .toStringAsFixed(2),
            action: SizedBox(
              width: 160,
              child: Slider(
                value: ((appdata.settings["themeBackgroundOpacity"] as num?)
                        ?.toDouble() ??
                    0.5)
                    .clamp(0.05, 1.0),
                min: 0.05,
                max: 1.0,
                onChanged: (v) {
                  setState(() {
                    appdata.settings["themeBackgroundOpacity"] = v;
                  });
                  appdata.writeSettings();
                  StateController.findOrNull(tag: "MyApp")?.update();
                },
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Background color".tl, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _bgColorDot(context, null),
                      for (final hex in [
                        '#1E1E1E', '#2D2D30', '#0078D4', '#E81123',
                        '#FF8C00', '#10893E', '#F5F5F5',
                      ])
                        _bgColorDot(context, hex),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Button(
                        onPressed: () => _pickHexColor(
                            "Background color".tl, "themeBackgroundColor"),
                        child: Text("Custom".tl).fixWidth(64),
                      ),
                      const SizedBox(width: 8),
                      Button(
                        onPressed: () {
                          setState(() {
                            appdata.settings["themeBackgroundColor"] = "";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        },
                        child: Text("Default".tl).fixWidth(64),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          buildItem(
            title: "Background blur".tl,
            subtitle: ((appdata.settings["themeBackgroundBlur"] as num?)
                        ?.toDouble() ??
                    0.0)
                .toStringAsFixed(1),
            action: SizedBox(
              width: 160,
              child: Slider(
                value: ((appdata.settings["themeBackgroundBlur"] as num?)
                        ?.toDouble() ??
                    0.0)
                    .clamp(0.0, 30.0),
                min: 0.0,
                max: 30.0,
                onChanged: (v) {
                  setState(() {
                    appdata.settings["themeBackgroundBlur"] = v;
                  });
                  appdata.writeSettings();
                  StateController.findOrNull(tag: "MyApp")?.update();
                },
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Background history".tl,
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Builder(builder: (context) {
                    final raw =
                        appdata.settings["themeBackgroundHistory"];
                    final hist = raw is List
                        ? raw
                            .map((e) => e.toString())
                            .where((p) => File(p).existsSync())
                            .take(10)
                            .toList()
                        : <String>[];
                    if (hist.isEmpty) {
                      return Text("No history".tl,
                          style: const TextStyle(fontSize: 12));
                    }
                    final current =
                        appdata.settings["themeBackground"] as String?;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in hist)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                applyThemeBackground(p);
                              });
                            },
                            onLongPress: () async {
                              await removeThemeBackground(p);
                              if (mounted) setState(() {});
                            },
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: p == current
                                      ? FluentTheme.of(context).accentColor
                                      : ColorScheme.of(context).outlineVariant,
                                  width: p == current ? 3 : 1,
                                ),
                                image: DecorationImage(
                                  image: FileImage(File(p)),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  }),
                  const SizedBox(height: 4),
                  Text("Tap to apply, long-press to delete".tl,
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
          buildItem(
            title: "Text shadow".tl,
            subtitle: "Add shadows to text and icons".tl,
            action: ToggleSwitch(
                checked:
                    appdata.settings["themeTextShadow"] == true,
                onChanged: (value) {
                  setState(() {
                    appdata.settings["themeTextShadow"] = value;
                  });
                  appdata.writeData();
                  StateController.findOrNull(tag: "MyApp")?.update();
                }),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Text color".tl, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _themeColorDot(context, "themeTextColor", null),
                      for (final hex in [
                        '#000000', '#FFFFFF', '#E81123', '#FF8C00',
                        '#0078D4', '#10893E', '#8764B8',
                      ])
                        _themeColorDot(context, "themeTextColor", hex),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Button(
                        onPressed: () => _pickHexColor(
                            "Text color".tl, "themeTextColor"),
                        child: Text("Custom".tl).fixWidth(64),
                      ),
                      const SizedBox(width: 8),
                      Button(
                        onPressed: () {
                          setState(() {
                            appdata.settings["themeTextColor"] = "";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        },
                        child: Text("Default".tl).fixWidth(64),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Icon color".tl, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _themeColorDot(context, "themeIconColor", null),
                      for (final hex in [
                        '#000000', '#FFFFFF', '#E81123', '#FF8C00',
                        '#0078D4', '#10893E', '#8764B8',
                      ])
                        _themeColorDot(context, "themeIconColor", hex),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Button(
                        onPressed: () => _pickHexColor(
                            "Icon color".tl, "themeIconColor"),
                        child: Text("Custom".tl).fixWidth(64),
                      ),
                      const SizedBox(width: 8),
                      Button(
                        onPressed: () {
                          setState(() {
                            appdata.settings["themeIconColor"] = "";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        },
                        child: Text("Default".tl).fixWidth(64),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Shadow color".tl, style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _themeColorDot(context, "themeShadowColor", null),
                      for (final hex in [
                        '#000000', '#FFFFFF', '#E81123', '#0078D4',
                        '#FF8C00', '#10893E',
                      ])
                        _themeColorDot(context, "themeShadowColor", hex),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Button(
                        onPressed: () => _pickHexColor(
                            "Shadow color".tl, "themeShadowColor"),
                        child: Text("Custom".tl).fixWidth(64),
                      ),
                      const SizedBox(width: 8),
                      Button(
                        onPressed: () {
                          setState(() {
                            appdata.settings["themeShadowColor"] = "";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        },
                        child: Text("Default".tl).fixWidth(64),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          buildItem(
            title: "Card opacity".tl,
            subtitle: ((appdata.settings["themeCardOpacity"] as num?)
                        ?.toDouble() ??
                    0.82)
                .toStringAsFixed(2),
            action: SizedBox(
              width: 160,
              child: Slider(
                value: ((appdata.settings["themeCardOpacity"] as num?)
                        ?.toDouble() ??
                    0.82)
                    .clamp(0.2, 1.0),
                min: 0.2,
                max: 1.0,
                onChanged: (v) {
                  setState(() {
                    appdata.settings["themeCardOpacity"] = v;
                  });
                  appdata.writeSettings();
                  StateController.findOrNull(tag: "MyApp")?.update();
                },
              ),
            ),
          ),
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
                    MenuFlyoutItem(
                        text: const Text("한국어"),
                        onPressed: () {
                          setState(() {
                            appdata.settings["language"] = "한국어";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        }),
                    MenuFlyoutItem(
                        text: const Text("Español"),
                        onPressed: () {
                          setState(() {
                            appdata.settings["language"] = "Español";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        }),
                    MenuFlyoutItem(
                        text: const Text("Русский"),
                        onPressed: () {
                          setState(() {
                            appdata.settings["language"] = "Русский";
                          });
                          appdata.writeData();
                          StateController.findOrNull(tag: "MyApp")?.update();
                        }),
                    MenuFlyoutItem(
                        text: const Text("Indonesia"),
                        onPressed: () {
                          setState(() {
                            appdata.settings["language"] = "Indonesia";
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
                  XFile? file;
                  try {
                    file = await openFile(
                      acceptedTypeGroups: [
                        XTypeGroup(
                          label: 'JSON',
                          extensions: ['json'],
                          // Required on iOS (extensions are ignored there).
                          uniformTypeIdentifiers: const ['public.json'],
                        )
                      ],
                    );
                  } catch (_) {
                    if (mounted) {
                      context.showToast(message: 'Failed to open file'.tl);
                    }
                    return;
                  }
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
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4),
        child: SyncSettingsForm(showBack: false),
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
      // Required on iOS (extensions are ignored there).
      uniformTypeIdentifiers: ['public.font'],
    );

    XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: [typeGroup]);
    } catch (_) {
      if (mounted) {
        context.showToast(message: 'Failed to open file'.tl);
      }
      return;
    }

    final selected = file;
    if (selected != null) {
      setState(() {
        selectedFont = selected.path;
        appdata.settings["customFont"] = selected.path;
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

