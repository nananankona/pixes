import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:pixes/appdata.dart';
import 'package:pixes/components/animated_image.dart';
import 'package:pixes/components/loading.dart';
import 'package:pixes/components/md.dart';
import 'package:pixes/components/page_route.dart';
import 'package:pixes/components/title_bar.dart';
import 'package:pixes/foundation/app.dart';
import 'package:pixes/foundation/image_provider.dart';
import 'package:pixes/foundation/log.dart';
import 'package:pixes/network/download.dart';
import 'package:pixes/network/network.dart';
import 'package:pixes/network/translator.dart';
import 'package:pixes/services/tts_service.dart';
import 'package:pixes/pages/image_page.dart';
import 'package:pixes/pages/main_page.dart';
import 'package:pixes/utils/ext.dart';
import 'package:pixes/utils/translation.dart';

class NovelReadingPage extends StatefulWidget {
  const NovelReadingPage(this.novel, {super.key});

  final Novel novel;

  @override
  State<NovelReadingPage> createState() => _NovelReadingPageState();
}

class _NovelReadingPageState extends LoadingState<NovelReadingPage, String> {
  TitleBarAction? action;

  bool isShowingSettings = false;

  String? translatedContent;

  final ScrollController _scrollController = ScrollController();

  Timer? _scrollTimer;

  bool _autoScrolling = false;

  bool _ttsBusy = false;

  final Map<int, GlobalKey> _itemKeys = {};

  List<String> _speakParagraphs = [];

  List<int> _speakWidgetIndex = [];

  void _onTtsParagraph() {
    final i = TtsService().paragraphIndex.value;
    if (i < 0 || i >= _speakWidgetIndex.length) return;
    final ctx = _itemKeys[_speakWidgetIndex[i]]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 300), alignment: 0.3);
    }
  }

  void _buildSpeakMapping(String raw) {
    _speakParagraphs = [];
    _speakWidgetIndex = [];
    var wi = 4; // title, spacing, divider, spacing
    for (final line in raw.split('\n')) {
      if (line.isEmpty) continue;
      if (line.startsWith('[uploadedimage:')) {
        wi++;
        continue;
      }
      var t = line;
      if (t.startsWith('[chapter:')) {
        t = t.replaceFirst('[chapter:', '');
        if (t.endsWith(']')) t = t.substring(0, t.length - 1);
        t = t.trim();
      }
      if (t.isEmpty) {
        wi++;
        continue;
      }
      _speakParagraphs.add(line);
      _speakWidgetIndex.add(wi);
      wi++;
    }
  }

  TtsEngine get _ttsEngine {
    final v = appdata.settings['ttsEngine'] as int? ?? 0;
    if (v < 0 || v >= TtsEngine.values.length) return TtsEngine.off;
    return TtsEngine.values[v];
  }

  Future<void> _toggleTts() async {
    if (TtsService().playing) {
      await TtsService().stop();
      if (mounted) setState(() {});
      return;
    }
    if (_ttsEngine == TtsEngine.off) {
      if (mounted) context.showToast(message: "Select a TTS engine first".tl);
      return;
    }
    final raw = translatedContent ?? data;
    if (raw == null) return;
    _buildSpeakMapping(raw);
    if (_speakParagraphs.isEmpty) return;
    setState(() => _ttsBusy = true);
    try {
      await TtsService().speak(_speakParagraphs, _ttsEngine);
    } catch (e) {
      if (mounted) context.showToast(message: "$e");
    } finally {
      if (mounted) setState(() => _ttsBusy = false);
    }
  }

  void _toggleAutoScroll() {
    if (_autoScrolling) {
      _stopAutoScroll();
    } else {
      final speed =
          (appdata.settings["readingAutoScrollSpeed"] as num).toDouble();
      setState(() => _autoScrolling = true);
      _scrollTimer =
          Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!_scrollController.hasClients) return;
        final pos = _scrollController.position;
        final next = pos.pixels + speed * 0.05;
        if (next >= pos.maxScrollExtent) {
          _scrollController.jumpTo(pos.maxScrollExtent);
          _stopAutoScroll();
          return;
        }
        _scrollController.jumpTo(next);
      });
    }
  }

  void _stopAutoScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
    if (mounted && _autoScrolling) {
      setState(() => _autoScrolling = false);
    } else {
      _autoScrolling = false;
    }
  }

  @override
  void initState() {
    TtsService().paragraphIndex.addListener(_onTtsParagraph);
    action = TitleBarAction(MdIcons.tune, "Settings".tl, () {
      if (!isShowingSettings) {
        _NovelReadingSettings.show(
          context,
          () {
            setState(() {});
          },
          TranslationController(
            content: data!,
            isTranslated: translatedContent != null,
            onTranslated: (s) {
              setState(() {
                translatedContent = s;
              });
            },
            revert: () {
              setState(() {
                translatedContent = null;
              });
            },
          ),
        ).then(
          (value) {
            isShowingSettings = false;
          },
        );
        isShowingSettings = true;
      } else {
        Navigator.of(context).pop();
      }
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      StateController.find<TitleBarController>().addAction(action!);
    });
    super.initState();
  }

  @override
  void dispose() {
    TtsService().paragraphIndex.removeListener(_onTtsParagraph);
    TtsService().stop();
    _scrollTimer?.cancel();
    _scrollController.dispose();
    Future.delayed(const Duration(milliseconds: 200), () {
      StateController.find<TitleBarController>().removeAction(action!);
    });
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context, String data) {
    var content = buildList(context).toList();
    final ttsPlaying = TtsService().playing;
    return ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Stack(
        children: [
          SelectionArea(
              child: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 16.0, height: 1.6),
            child: NotificationListener<UserScrollNotification>(
              onNotification: (_) {
                if (_autoScrolling) _stopAutoScroll();
                return false;
              },
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16.0),
                itemBuilder: (context, index) {
                  return KeyedSubtree(
                    key: _itemKeys.putIfAbsent(index, () => GlobalKey()),
                    child: content[index],
                  );
                },
                itemCount: content.length,
              ),
            ),
          )),
          Positioned(
            right: 16,
            bottom: 16,
            child: Button(
              onPressed: _toggleAutoScroll,
              child: Icon(_autoScrolling ? FluentIcons.pause : FluentIcons.play),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 72,
            child: Button(
              onPressed: _ttsBusy ? null : _toggleTts,
              child: _ttsBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : Icon(ttsPlaying
                      ? FluentIcons.stop
                      : FluentIcons.speakers),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Future<Res<String>> loadData() {
    return Network().getNovelContent(widget.novel.id.toString()).then((res) {
      if (!res.error) {
        maybeAutoDownloadNovel(widget.novel, res.data);
      }
      return res;
    });
  }

  Iterable<Widget> buildList(BuildContext context) sync* {
    double fontSizeAdd = appdata.settings["readingFontSize"] - 16.0;
    double fontHeight = appdata.settings["readingLineHeight"];

    yield Text(widget.novel.title,
        style: TextStyle(
            fontSize: 24.0 + fontSizeAdd, fontWeight: FontWeight.bold));
    yield const SizedBox(height: 12.0);
    yield const Divider(
      style: DividerThemeData(horizontalMargin: EdgeInsets.all(0)),
    );
    yield const SizedBox(height: 12.0);

    var novelContent = (translatedContent ?? data!).split('\n');
    for (var content in novelContent) {
      if (content.isEmpty) continue;
      if (content.startsWith('[uploadedimage:')) {
        var imageId = content.nums;
        yield GestureDetector(
          onTap: () {
            ImagePage.show(["novel:${widget.novel.id.toString()}/$imageId"]);
          },
          child: SizedBox(
            height: 300,
            width: double.infinity,
            child: AnimatedImage(
              image:
                  CachedNovelImageProvider(widget.novel.id.toString(), imageId),
              filterQuality: FilterQuality.medium,
              fit: BoxFit.contain,
              height: 300,
              width: double.infinity,
            ),
          ),
        );
      } else if (content.startsWith('[chapter:')) {
        var title = content.replaceLast(']', '').split(':')[1];
        yield Text(title,
                style: TextStyle(
                    fontSize: 20.0 + fontSizeAdd,
                    fontWeight: FontWeight.bold,
                    height: fontHeight))
            .paddingBottom(8);
      } else {
        yield Text(content,
                style:
                    TextStyle(fontSize: 16.0 + fontSizeAdd, height: fontHeight))
            .paddingBottom(appdata.settings["readingParagraphSpacing"]);
      }
    }
  }
}

class TranslationController {
  final String content;

  final bool isTranslated;

  final void Function(String translated) onTranslated;

  final void Function() revert;

  const TranslationController({
    required this.content,
    required this.isTranslated,
    required this.onTranslated,
    required this.revert,
  });
}

class _NovelReadingSettings extends StatefulWidget {
  const _NovelReadingSettings(this.callback, this.controller);

  final void Function() callback;

  final TranslationController controller;

  static Future show(
    BuildContext context,
    void Function() callback,
    TranslationController controller,
  ) {
    return Navigator.of(context).push(
      SideBarRoute(_NovelReadingSettings(callback, controller)),
    );
  }

  @override
  State<_NovelReadingSettings> createState() => __NovelReadingSettingsState();
}

class __NovelReadingSettingsState extends State<_NovelReadingSettings> {
  late final TextEditingController _voicevoxUrlCtl;
  late final TextEditingController _capServerUrlCtl;
  late final TextEditingController _capSpeakerCtl;
  late final TextEditingController _capEmailCtl;
  late final TextEditingController _capPassCtl;
  late final TextEditingController _capV1WsCtl;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _voicevoxUrlCtl = TextEditingController(
        text: (appdata.settings['voicevoxUrl'] as String?) ??
            'http://127.0.0.1:50021');
    _capServerUrlCtl = TextEditingController(
        text: (appdata.settings['capcutServerUrl'] as String?) ??
            'http://127.0.0.1:8080');
    _capSpeakerCtl = TextEditingController(
        text: (appdata.settings['capcutSpeaker'] as String?) ?? 'labebe');
    _capEmailCtl = TextEditingController(
        text: (appdata.settings['capcutEmail'] as String?) ?? '');
    _capPassCtl = TextEditingController(
        text: (appdata.settings['capcutPassword'] as String?) ?? '');
    _capV1WsCtl = TextEditingController(
        text: (appdata.settings['capcutV1WsUrl'] as String?) ??
            'wss://sami-sg1.internal.byteintlapi.com/internal/api/v1/ws');
  }

  @override
  void dispose() {
    _voicevoxUrlCtl.dispose();
    _capServerUrlCtl.dispose();
    _capSpeakerCtl.dispose();
    _capEmailCtl.dispose();
    _capPassCtl.dispose();
    _capV1WsCtl.dispose();
    super.dispose();
  }

  int get _ttsEngine => appdata.settings['ttsEngine'] as int? ?? 0;

  Future<void> _testTts() async {
    setState(() => _testing = true);
    try {
      await TtsService().speak(['こんにちは、テストです。'],
          TtsEngine.values[_ttsEngine.clamp(0, TtsEngine.values.length - 1)]);
      if (mounted) context.showToast(message: "Done".tl);
    } catch (e) {
      if (mounted) context.showToast(message: '$e');
    } finally {
      await TtsService().stop();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          TitleBar(title: "Reading Settings".tl),
          const SizedBox(height: 8),
          Card(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: Text("Font Size".tl),
              subtitle: Slider(
                value: appdata.settings["readingFontSize"],
                onChanged: (value) {
                  setState(() {
                    appdata.settings["readingFontSize"] = value;
                  });
                  appdata.writeSettings();
                  widget.callback();
                },
                min: 12.0,
                max: 24.0,
                divisions: 12,
                label: appdata.settings["readingFontSize"].toString(),
              ),
              trailing: Text(appdata.settings["readingFontSize"].toString()),
            ),
          ).paddingHorizontal(8).paddingBottom(8),
          Card(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: Text("Line Height".tl),
              subtitle: Slider(
                value: appdata.settings["readingLineHeight"],
                onChanged: (value) {
                  setState(() {
                    appdata.settings["readingLineHeight"] = value;
                  });
                  appdata.writeSettings();
                  widget.callback();
                },
                min: 1.0,
                max: 2.0,
                divisions: 10,
                label: appdata.settings["readingLineHeight"].toString(),
              ),
              trailing: Text(appdata.settings["readingLineHeight"].toString()),
            ),
          ).paddingHorizontal(8).paddingBottom(8),
          Card(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: Text("Paragraph Spacing".tl),
              subtitle: Slider(
                value: appdata.settings["readingParagraphSpacing"],
                onChanged: (value) {
                  setState(() {
                    appdata.settings["readingParagraphSpacing"] = value;
                  });
                  appdata.writeSettings();
                  widget.callback();
                },
                min: 0.0,
                max: 16.0,
                divisions: 8,
                label: appdata.settings["readingParagraphSpacing"].toString(),
              ),
              trailing:
                  Text(appdata.settings["readingParagraphSpacing"].toString()),
            ),
          ).paddingHorizontal(8).paddingBottom(8),
          Card(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: Text("Auto-scroll speed".tl),
              subtitle: Slider(
                value: (appdata.settings["readingAutoScrollSpeed"] as num)
                    .toDouble(),
                onChanged: (value) {
                  setState(() {
                    appdata.settings["readingAutoScrollSpeed"] = value;
                  });
                  appdata.writeSettings();
                  widget.callback();
                },
                min: 20.0,
                max: 200.0,
                divisions: 18,
                label: (appdata.settings["readingAutoScrollSpeed"] as num)
                    .toString(),
              ),
              trailing: Text((appdata.settings["readingAutoScrollSpeed"] as num)
                  .toString()),
            ),
          ).paddingHorizontal(8).paddingBottom(8),
          Card(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: Text("TTS Engine".tl),
              trailing: DropDownButton(
                title: Text(switch (_ttsEngine) {
                  1 => "VOICEVOX".tl,
                  2 => "CapCut Server".tl,
                  3 => "CapCut v1".tl,
                  4 => "CapCut v2".tl,
                  _ => "Off".tl,
                }),
                items: [
                  for (final entry in [
                    (0, "Off"),
                    (1, "VOICEVOX"),
                    (2, "CapCut Server"),
                    (3, "CapCut v1"),
                    (4, "CapCut v2"),
                  ])
                    MenuFlyoutItem(
                      text: Text((entry.$2 as String).tl),
                      onPressed: () {
                        setState(() {
                          appdata.settings['ttsEngine'] = entry.$1;
                        });
                        appdata.writeSettings();
                        widget.callback();
                      },
                    ),
                ],
              ),
            ),
          ).paddingHorizontal(8).paddingBottom(8),
          if (_ttsEngine == 1) ...[
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("VOICEVOX URL".tl),
                subtitle: TextBox(
                  controller: _voicevoxUrlCtl,
                  onChanged: (v) {
                    appdata.settings['voicevoxUrl'] = v;
                    appdata.writeSettings();
                  },
                ),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("Speaker ID".tl),
                trailing: SizedBox(
                  width: 96,
                  height: 32,
                  child: NumberBox<int>(
                    value: (appdata.settings['voicevoxSpeaker'] as num?)
                            ?.toInt() ??
                        1,
                    min: 0,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        appdata.settings['voicevoxSpeaker'] = v;
                      });
                      appdata.writeSettings();
                    },
                    clearButton: false,
                    mode: SpinButtonPlacementMode.none,
                  ),
                ),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
          ],
          if (_ttsEngine == 2) ...[
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("CapCut Server URL".tl),
                subtitle: TextBox(
                  controller: _capServerUrlCtl,
                  onChanged: (v) {
                    appdata.settings['capcutServerUrl'] = v;
                    appdata.writeSettings();
                  },
                ),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("Speaker".tl),
                subtitle: TextBox(
                  controller: _capSpeakerCtl,
                  onChanged: (v) {
                    appdata.settings['capcutSpeaker'] = v;
                    appdata.writeSettings();
                  },
                ),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
          ],
          if (_ttsEngine == 3) ...[
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("Voice Type".tl),
                trailing: SizedBox(
                  width: 96,
                  height: 32,
                  child: NumberBox<int>(
                    value:
                        (appdata.settings['capcutV1Type'] as num?)?.toInt() ??
                            0,
                    min: 0,
                    max: 15,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        appdata.settings['capcutV1Type'] = v;
                      });
                      appdata.writeSettings();
                    },
                    clearButton: false,
                    mode: SpinButtonPlacementMode.none,
                  ),
                ),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("WebSocket URL".tl),
                subtitle: TextBox(
                  controller: _capV1WsCtl,
                  onChanged: (v) {
                    appdata.settings['capcutV1WsUrl'] = v;
                    appdata.writeSettings();
                  },
                ),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
          ],
          if (_ttsEngine == 4) ...[
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("Speaker".tl),
                subtitle: TextBox(
                  controller: _capSpeakerCtl,
                  onChanged: (v) {
                    appdata.settings['capcutSpeaker'] = v;
                    appdata.writeSettings();
                  },
                ),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("CapCut Email".tl),
                subtitle: TextBox(
                  controller: _capEmailCtl,
                  onChanged: (v) {
                    appdata.settings['capcutEmail'] = v;
                    appdata.writeSettings();
                  },
                ),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("CapCut Password".tl),
                subtitle: TextBox(
                  controller: _capPassCtl,
                  obscureText: true,
                  onChanged: (v) {
                    appdata.settings['capcutPassword'] = v;
                    appdata.writeSettings();
                  },
                ),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
          ],
          if (_ttsEngine != 0) ...[
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("Speech Speed".tl),
                subtitle: Slider(
                  value: ((appdata.settings['ttsSpeed'] as num?)
                              ?.toDouble() ??
                          1.0)
                      .clamp(0.5, 2.0),
                  onChanged: (value) {
                    setState(() {
                      appdata.settings['ttsSpeed'] = value;
                    });
                    appdata.writeSettings();
                    widget.callback();
                  },
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  label: (appdata.settings['ttsSpeed'] as num?)?.toString(),
                ),
                trailing: Text(
                    (appdata.settings['ttsSpeed'] as num?)?.toString() ??
                        '1.0'),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("Speech Volume".tl),
                subtitle: Slider(
                  value: ((appdata.settings['ttsVolume'] as num?)
                              ?.toDouble() ??
                          1.0)
                      .clamp(0.0, 1.0),
                  onChanged: (value) {
                    setState(() {
                      appdata.settings['ttsVolume'] = value;
                    });
                    appdata.writeSettings();
                    widget.callback();
                  },
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: (appdata.settings['ttsVolume'] as num?)?.toString(),
                ),
                trailing: Text(
                    (appdata.settings['ttsVolume'] as num?)?.toString() ??
                        '1.0'),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
            Card(
              padding: EdgeInsets.zero,
              child: ListTile(
                title: Text("Test Voice".tl),
                trailing: _testing
                    ? const SizedBox(
                        width: 42,
                        height: 18,
                        child: Center(
                          child: SizedBox.square(
                            dimension: 18,
                            child: ProgressRing(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Button(onPressed: _testTts, child: Text("Play".tl)),
              ),
            ).paddingHorizontal(8).paddingBottom(8),
          ],
          // 深色模式
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: EdgeInsets.zero,
            child: ListTile(
              title: Text("Theme".tl),
              trailing: DropDownButton(
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
                  ]),
            ),
          ).paddingBottom(8),
          Card(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: Text("Translate Novel".tl),
              trailing: widget.controller.isTranslated
                  ? Button(
                      onPressed: () {
                        widget.controller.revert();
                        context.pop();
                      },
                      child: Text("Revert".tl),
                    )
                  : Button(
                      onPressed: translate,
                      child: isTranslating
                          ? const SizedBox(
                              width: 42,
                              height: 18,
                              child: Center(
                                child: SizedBox.square(
                                  dimension: 18,
                                  child: ProgressRing(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            )
                          : Text("Translate".tl),
                    ),
            ),
          ).paddingHorizontal(8).paddingBottom(8),
        ],
      ),
    );
  }

  bool isTranslating = false;

  void translate() async {
    setState(() {
      isTranslating = true;
    });
    try {
      var translated = await Translator.instance
          .translate(widget.controller.content, "zh-CN");
      widget.controller.onTranslated(translated);
      if (mounted) {
        context.pop();
      }
    } catch (e) {
      setState(() {
        isTranslating = false;
      });
      if (mounted) {
        context.showToast(message: "Failed to translate".tl);
      }
      Log.error("Translate", e.toString());
    }
  }
}
