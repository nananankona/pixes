import "dart:async";
import "dart:io";
import "dart:ui";

import "package:dynamic_color/dynamic_color.dart";
import "package:fluent_ui/fluent_ui.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart" as md;
import "package:flutter/services.dart";
import "package:pixes/appdata.dart";
import "package:pixes/components/keyboard.dart";
import "package:pixes/components/md.dart";
import "package:pixes/components/message.dart";
import "package:pixes/foundation/app.dart";
import "package:pixes/foundation/cache_manager.dart";
import "package:pixes/foundation/history.dart";
import "package:pixes/foundation/log.dart";
import "package:pixes/network/app_dio.dart";
import "package:pixes/pages/main_page.dart";
import "package:pixes/pages/lock/lock_page.dart";
import "package:pixes/services/sync_service.dart";
import "package:pixes/utils/app_links.dart";
import "package:pixes/utils/loop.dart";
import "package:pixes/utils/translation.dart";
import "package:pixes/utils/update.dart";
import "package:pixes/utils/window.dart";
import "package:window_manager/window_manager.dart";

AppLifecycleListener? _lifecycleListener;

void main() {
  runZonedGuarded(() async {
    final stopwatch = Stopwatch()..start();
    void logStage(String name) {
      Log.info("Startup", "$name: ${stopwatch.elapsedMilliseconds}ms");
    }

    Future.delayed(const Duration(seconds: 3), checkUpdate);
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      Log.error("Unhandled", "${details.exception}\n${details.stack}");
    };
    setSystemProxy();
    await App.init();
    logStage("App.init");
    await appdata.readData();
    logStage("appdata.readData");
    CacheManager().setLimitSize(
        ((appdata.settings["cacheLimitMB"] as num?)?.toInt() ?? 2048) *
            1024 *
            1024);
    await Translation.init();
    logStage("Translation.init");
    HistoryManager().init();
    logStage("HistoryManager.init");
    // Defer sync pull until after first frame so startup isn't janky.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 5), () {
        syncService.init();
        logStage("syncService.init");
      });
    });
    handleLinks();
    if (App.isDesktop) {
      await WindowManager.instance.ensureInitialized();
      windowManager.waitUntilReadyToShow().then((_) async {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: App.isMacOS,
        );
        if (App.isLinux) {
          // https://github.com/leanflutter/window_manager/issues/460
          return;
        }
       
        if (App.isMacOS) {
          await windowManager.setMinimumSize(const Size(650, 600));
        } else {
          await windowManager.setMinimumSize(const Size(500, 600));
        }
        var placement = await WindowPlacement.loadFromFile();
        await placement.applyToWindow();
        await windowManager.show();
        Loop.register(WindowPlacement.loop);
      });
    }
    Loop.start();
    Log.info("APP", "Application started");
    runApp(const MyApp());
    _lifecycleListener = AppLifecycleListener(
      onResume: () => syncService.init(),
    );
  }, (error, stack) {
    Log.error("Unhandled Exception", "$error\n$stack");
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    return StateBuilder<SimpleController>(
        init: SimpleController(),
        tag: "MyApp",
        builder: (controller) {
          Brightness brightness =
              PlatformDispatcher.instance.platformBrightness;

          if (appdata.settings["theme"] == "Dark") {
            brightness = Brightness.dark;
          } else if (appdata.settings["theme"] == "Light") {
            brightness = Brightness.light;
          }

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              systemNavigationBarColor: Colors.transparent,
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: brightness.opposite,
              systemNavigationBarIconBrightness: brightness.opposite,
            ),
            child: DynamicColorBuilder(
              builder: (light, dark) {
                final colorScheme =
                    (brightness == Brightness.light ? light : dark) ??
                        md.ColorScheme.fromSeed(
                            seedColor: Colors.blue, brightness: brightness);
                final bgFile = _backgroundFile();
                bool hasBg = bgFile != null;
                Color accentBase;
                try {
                  final custom = appdata.settings["accentColor"] as String?;
                  accentBase = (custom != null && custom.isNotEmpty) ? _hexToColor(custom) : colorScheme.primary;
                } catch (_) {
                  accentBase = colorScheme.primary;
                }
                Color? bgTint;
                try {
                  final customBg = appdata.settings["themeBackgroundColor"] as String?;
                  bgTint = (customBg != null && customBg.isNotEmpty) ? _hexToColor(customBg) : null;
                } catch (_) {
                  bgTint = null;
                }
                final bgBlur = ((appdata.settings["themeBackgroundBlur"] as num?)?.toDouble() ?? 0.0).clamp(0.0, 30.0);
                hasBg = hasBg || bgTint != null;
                final textShadow = appdata.settings["themeTextShadow"] == true;
                // Translucent surfaces so the wallpaper shows through
                // cards, menus, flyouts and dialogs instead of solid white.
                final cardTranslucent = hasBg
                    ? colorScheme.surfaceContainer.withValues(alpha: 0.82)
                    : null;
                final menuTranslucent = hasBg
                    ? colorScheme.surfaceContainer.withValues(alpha: 0.9)
                    : null;
return FluentApp(
                     navigatorKey: App.rootNavigatorKey,
                     debugShowCheckedModeBanner: false,
                     title: 'pixes',
theme: FluentThemeData(
                          brightness: brightness,
                          scaffoldBackgroundColor: hasBg ? Colors.transparent : null,
                          micaBackgroundColor: hasBg ? Colors.transparent : null,
                          navigationPaneTheme: NavigationPaneThemeData(
                            backgroundColor: hasBg ? Colors.transparent : null,
                          ),
                          cardColor: cardTranslucent,
                          menuColor: menuTranslucent,
                          fontFamily: _getCustomFont() ?? (App.isWindows ? "Microsoft YaHei UI" : null),
                          // apply primary color from settings if provided
                          accentColor: AccentColor.swatch({
                            'darkest': darken(accentBase, 30),
                            'darker': darken(accentBase, 20),
                            'dark': darken(accentBase, 10),
                            'normal': accentBase,
                            'light': lighten(accentBase, 10),
                            'lighter': lighten(accentBase, 20),
                            'lightest': lighten(accentBase, 30)
                          }),
// Icon color from settings
iconTheme: IconThemeData(
  color: colorScheme.onSurface,
),
                          focusTheme: const FocusThemeData(
                            primaryBorder: BorderSide.none,
                            secondaryBorder: BorderSide.none,
                          )),
                      home: appdata.settings["lockEnabled"] == true 
                         ? const LockPage() 
                         : const MainPage(),
                     builder: (context, child) {
                       ErrorWidget.builder = (details) {
                         if (details.exception
                             .toString()
                             .contains("RenderFlex overflowed")) {
                           return const SizedBox.shrink();
                         }
                         Log.error(
                             "UI", "${details.exception}\n${details.stack}");
                         return Text(details.exception.toString());
                       };
                       if (child == null) {
                         throw "widget is null";
                       }

                       String? font;
                       List<String>? fallback;
                        if (App.isLinux || App.isWindows || App.isAndroid || App.isIOS) {
                          font = _getCustomFont() ?? (App.isLinux || App.isWindows ? 'Noto Sans CJK' : null);
                          fallback = [
                            'Segoe UI',
                            'Noto Sans SC',
                            'Noto Sans TC',
                            'Noto Sans',
                            'Microsoft YaHei',
                            'PingFang SC',
                            'Arial',
                            'sans-serif'
                          ];
                        }

                       Widget widget = MdTheme(
                         data: MdThemeData.from(
                             colorScheme: colorScheme, useMaterial3: true),
                         child: DefaultTextStyle.merge(
style: TextStyle(
                              fontFamily: font,
                              fontFamilyFallback: fallback,
                              color: colorScheme.onSurface,
                              shadows: textShadow
                                  ? [
                                      Shadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.75),
                                        offset: const Offset(0, 1),
                                        blurRadius: 4,
                                      ),
                                    ]
                                  : null,
                            ),
                           child: OverlayWidget(child),
                         ),
                       );

                        


                       if (textShadow) {
                          widget = IconTheme(
                            data: IconTheme.of(context).merge(
                              const IconThemeData(
                                shadows: [
                                  Shadow(
                                    color: Color(0xBF000000),
                                    offset: Offset(0, 1),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            child: widget,
                          );
                        }
                       if (bgFile != null || bgTint != null) {
                          final bgOpacity = ((appdata.settings["themeBackgroundOpacity"] as num?)?.toDouble() ?? 0.5).clamp(0.05, 1.0);
                          Widget bgLayer = bgTint != null
                              ? Container(color: bgTint)
                              : const SizedBox.shrink();
                          if (bgFile != null) {
                            Widget bgImage = Image.file(bgFile, fit: BoxFit.cover);
                            if (bgBlur > 0.01) {
                              bgImage = ImageFiltered(
                                imageFilter: ImageFilter.blur(sigmaX: bgBlur, sigmaY: bgBlur),
                                child: bgImage,
                              );
                            }
                            bgImage = Opacity(opacity: bgOpacity, child: bgImage);
                            bgLayer = Stack(
                              children: [
                                bgLayer,
                                Positioned.fill(child: bgImage),
                              ],
                            );
                          }
                          widget = Stack(
                            children: [
                              Positioned.fill(child: bgLayer),
                              Positioned.fill(child: widget),
                            ],
                          );
                        }
                       return KeyEventListener(child: widget);
                     });
              },
            ),
          );
        });
  }
}

int _floatToInt8(double x) {
  return (x * 255.0).round() & 0xff;
}

Color darken(Color c, [int percent = 10]) {
  assert(1 <= percent && percent <= 100);
  var f = 1 - percent / 100;
  return Color.fromARGB(
    _floatToInt8(c.a),
    _floatToInt8(c.r * f),
    _floatToInt8(c.g * f),
    _floatToInt8(c.b * f),
  );
}

Color lighten(Color c, [int percent = 10]) {
  assert(1 <= percent && percent <= 100);
  var p = percent / 100;
  return Color.fromARGB(
    _floatToInt8(c.a),
    _floatToInt8(c.r + (1 - c.r) * p),
    _floatToInt8(c.g + (1 - c.g) * p),
    _floatToInt8(c.b + (1 - c.b) * p),
  );
}

File? _backgroundFile() {
  try {
    final p = appdata.settings["themeBackground"] as String?;
    if (p == null || p.isEmpty) return null;
    final f = File(p);
    return f.existsSync() ? f : null;
  } catch (_) {
    return null;
  }
}

/// Convert a hex color string like "#RRGGBB" or "RRGGBB" to a [Color]
Color _hexToColor(String hex) {
  var cleaned = hex.replaceFirst('#', '');
  if (cleaned.length == 6) {
    cleaned = 'FF' + cleaned; // add opaque alpha
  }
  return Color(int.parse(cleaned, radix: 16));
}

String? _getCustomFont() {
  final customFont = appdata.settings["customFont"];
  if (customFont == null || customFont.isEmpty) {
    return null;
  }

  // For system fonts, extract the font family name from the path
  // This is a simplified approach - in a real implementation, you'd need
  // to parse the font file to get the actual family name
  if (customFont.contains(Platform.pathSeparator)) {
    // It's a file path - for now, we'll just return the filename without extension
    // In a full implementation, you'd load the font and register it
    final fileName = customFont.split(Platform.pathSeparator).last;
    final fontName = fileName.split('.').first;
    return fontName;
  }

  return customFont;
}
