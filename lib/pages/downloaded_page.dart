import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:pixes/components/animated_image.dart';
import 'package:pixes/components/grid.dart';
import 'package:pixes/components/md.dart';
import 'package:pixes/components/title_bar.dart';
import 'package:pixes/components/ugoira.dart';
import 'package:pixes/foundation/app.dart';
import 'package:pixes/network/download.dart';
import 'package:pixes/pages/illust_page.dart';
import 'package:pixes/utils/translation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../utils/io.dart';
import 'main_page.dart';

class DownloadedPage extends StatefulWidget {
  const DownloadedPage({super.key});

  @override
  State<DownloadedPage> createState() => _DownloadedPageState();
}

class _DownloadedPageState extends State<DownloadedPage> {
  var illusts = <DownloadedIllust>[];
  var illustTags = <int, List<String>>{};
  var novels = <DownloadedNovel>[];
  var flyoutControllers = <FlyoutController>[];
  var novelTexts = <String, String>{};

  String statsText = "";

  bool showNovels = false;
  String query = "";
  int _illustLimit = 50;
  int _novelLimit = 50;

  Future<void> _updateStats() async {
    try {
      var imgCount = 0;
      var bytes = 0;
      for (final it in illusts) {
        imgCount += it.imageCount;
        try {
          for (final path in DownloadManager().getImagePaths(it.illustId)) {
            final f = File(path);
            if (await f.exists()) bytes += await f.length();
          }
        } catch (_) {}
      }
      for (final n in novels) {
        bytes += n.fileSize;
      }
      final sizeStr = bytes >= 1024 * 1024 * 1024
          ? (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2) + " GB"
          : (bytes / (1024 * 1024)).toStringAsFixed(1) + " MB";
      if (mounted) {
        setState(() {
          statsText = illusts.length.toString() + " works / " +
              imgCount.toString() + " images / " +
              novels.length.toString() + " novels / " +
              sizeStr;
        });
      }
    } catch (_) {}
  }

  void loadData() {
    illusts = DownloadManager().listAll();
    illustTags = {};
    for (final it in illusts) {
      try {
        final paths = DownloadManager().getImagePaths(it.illustId);
        if (paths.isEmpty) continue;
        final dir = File(paths.first).parent.path;
        final infoFile = File('$dir/info_${it.illustId}.json');
        if (!infoFile.existsSync()) continue;
        final info =
            jsonDecode(infoFile.readAsStringSync()) as Map<String, dynamic>;
        final tags = (info['tags'] as List? ?? [])
            .map((t) => t is Map
                ? '${t['name'] ?? ''} ${t['translated'] ?? ''}'.toLowerCase()
                : '')
            .where((t) => t.trim().isNotEmpty)
            .toList();
        if (tags.isNotEmpty) illustTags[it.illustId] = tags;
      } catch (_) {}
    }
    novels = DownloadManager().listNovels();
    novelTexts = {};
    for (final n in novels) {
      try {
        novelTexts[n.filePath] =
            File(n.filePath).readAsStringSync().toLowerCase();
      } catch (_) {}
    }
    flyoutControllers =
        List.generate(illusts.length, (index) => FlyoutController());
    unawaited(_updateStats());
  }

  @override
  void initState() {
    loadData();
    super.initState();
  }

  List<DownloadedIllust> get filteredIllusts {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return illusts;
    return illusts
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.author.toLowerCase().contains(q) ||
            e.illustId.toString().contains(q) ||
            (illustTags[e.illustId]?.any((t) => t.contains(q)) ?? false))
        .toList();
  }

  List<DownloadedNovel> get filteredNovels {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return novels;
    return novels
        .where((e) =>
            e.title.toLowerCase().contains(q) ||
            e.novelId.toString().contains(q) ||
            e.author.toLowerCase().contains(q) ||
            e.tags.any((t) => t.toLowerCase().contains(q)) ||
            (q.length >= 2 &&
                (novelTexts[e.filePath]?.contains(q) ?? false)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TitleBar(
          title: "Downloaded".tl,
          action: Button(
            child: Text("Delete Invalid Items".tl),
            onPressed: () async {
              await DownloadManager().checkAndClearInvalidItems();
              setState(() {
                loadData();
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Row(
            children: [
              Button(
                onPressed: showNovels
                    ? () => setState(() => showNovels = false)
                    : null,
                child: Text("Illust".tl).fixWidth(56),
              ),
              const SizedBox(width: 6),
              Button(
                onPressed: showNovels
                    ? null
                    : () => setState(() => showNovels = true),
                child: Text("Novel".tl).fixWidth(56),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextBox(
                  placeholder: "Search".tl,
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
            ],
          ),
        ),
        if (statsText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(statsText, style: const TextStyle(fontSize: 12)),
            ),
          ),
        Expanded(
          child: showNovels ? buildNovelBody() : buildBody(),
        ),
      ],
    );
  }

  Widget buildNovelBody() {
    final items = filteredNovels;
    if (items.isEmpty) {
      return Center(child: Text("No results".tl));
    }
    final total = items.length;
    final view =
        total > _novelLimit ? items.sublist(0, _novelLimit) : items;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: view.length + (view.length < total ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= view.length) {
          if (view.length < total) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _novelLimit < total) {
                setState(() => _novelLimit += 50);
              }
            });
          }
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 24,
                height: 24,
                child: ProgressRing(strokeWidth: 2),
              ),
            ),
          );
        }
        final novel = view[index];
        final kb = (novel.fileSize / 1024).toStringAsFixed(1);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: EdgeInsets.zero,
          child: ListTile(
            title: Text(novel.title,
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [novel.novelId.toString(), if (novel.author.isNotEmpty) novel.author, ...novel.tags.take(3), "${kb}KB"].join("  •  "),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Button(
                  child: Text("Open".tl).fixWidth(48),
                  onPressed: () {
                    context.to(
                        () => _DownloadedNovelViewPage(novel));
                  },
                ),
                const SizedBox(width: 6),
                Button(
                  child: Text("Delete".tl).fixWidth(48),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (c) => ContentDialog(
                        title: Text('Are you sure you want to delete?'.tl),
                        actions: [
                          Button(
                            child: Text('Cancel'.tl),
                            onPressed: () => Navigator.of(c).pop(false),
                          ),
                          FilledButton(
                            child: Text('Yes'.tl),
                            onPressed: () => Navigator.of(c).pop(true),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      DownloadManager().deleteNovel(novel);
                      setState(loadData);
                    }
                  },
                ),
              ],
            ),
            onPressed: () {
              context.to(() => _DownloadedNovelViewPage(novel));
            },
          ),
        );
      },
    );
  }

  Widget buildBody() {
    final items = filteredIllusts;
    if (items.isEmpty) {
      return Center(child: Text("No results".tl));
    }
    final total = items.length;
    final view =
        total > _illustLimit ? items.sublist(0, _illustLimit) : items;
    return GridViewWithFixedItemHeight(
        itemCount: view.length + (view.length < total ? 1 : 0),
        itemHeight: 152,
        maxCrossAxisExtent: 742,
        builder: (context, index) {
          if (index >= view.length) {
            if (view.length < total) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _illustLimit < total) {
                  setState(() => _illustLimit += 50);
                }
              });
            }
            return const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: ProgressRing(strokeWidth: 2),
              ),
            );
          }
          final item = view[index];
          var image = DownloadManager().getImage(item.illustId, 0);
          final isUgoiraZip =
              image != null && image.path.toLowerCase().endsWith('.zip');
          Widget? thumbnail;
          if (isUgoiraZip) {
            final cover = File(
                '${File(image!.path).parent.path}/cover_${item.illustId}.jpg');
            thumbnail = cover.existsSync()
                ? AnimatedImage(
                    image: FileImage(cover),
                    cacheWidth: 192,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    filterQuality: FilterQuality.medium,
                  )
                : const Icon(MdIcons.play_circle_outline, size: 36);
          } else if (image != null) {
            thumbnail = AnimatedImage(
              image: FileImage(image),
              cacheWidth: 192,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              filterQuality: FilterQuality.medium,
            );
          }
          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                context.to(() =>
                    IllustPageWithId(item.illustId.toString()));
              },
              child: Row(
                children: [
                  Container(
                    width: 96,
                    height: double.infinity,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: ColorScheme.of(context).secondaryContainer),
                    clipBehavior: Clip.antiAlias,
                    child: thumbnail,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.author,
                          style: const TextStyle(
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          "${item.imageCount}P",
                          style: const TextStyle(
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            const Spacer(),
                            Button(
                              child: Text("View".tl).fixWidth(42),
                              onPressed: () {
                                if (isUgoiraZip) {
                                    App.rootNavigatorKey.currentContext?.to(() =>
                                        _DownloadedUgoiraViewPage(
                                            item.illustId, image!.path));
                                } else {
                                    App.rootNavigatorKey.currentContext?.to(() =>
                                        _DownloadedIllustViewPage(DownloadManager()
                                        .getImagePaths(item.illustId)));
                                }
                              },
                            ),
                            const SizedBox(width: 6),
                            FlyoutTarget(
                              controller: flyoutControllers[illusts.indexOf(item)],
                              child: Button(
                                child: Text("Delete".tl).fixWidth(42),
                                onPressed: () {
                                  flyoutControllers[illusts.indexOf(item)].showFlyout(
                                      navigatorKey:
                                          App.rootNavigatorKey.currentState,
                                      builder: (context) {
                                        return FlyoutContent(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Are you sure you want to delete?'
                                                    .tl,
                                                style: const TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold),
                                              ),
                                              const SizedBox(height: 12.0),
                                              Button(
                                                onPressed: () {
                                                  Flyout.of(context).close();
                                                  DownloadManager()
                                                      .delete(item);
                                                  setState(loadData);
                                                },
                                                child: Text('Yes'.tl),
                                              ),
                                            ],
                                          ),
                                        );
                                      });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }).paddingHorizontal(8);
  }
}

class _DownloadedIllustViewPage extends StatefulWidget {
  const _DownloadedIllustViewPage(this.imagePaths);

  final List<String> imagePaths;

  @override
  State<_DownloadedIllustViewPage> createState() =>
      _DownloadedIllustViewPageState();
}

class _DownloadedIllustViewPageState extends State<_DownloadedIllustViewPage>
    with WindowListener {
  int windowButtonKey = 0;

  @override
  void initState() {
    windowManager.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() {
      windowButtonKey++;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      windowButtonKey++;
    });
  }

  var controller = PageController();

  int currentPage = 0;

  var menuController = FlyoutController();

  Future<File?> getFile() async {
    var file = File(widget.imagePaths[currentPage]);
    if (file.existsSync()) {
      return file;
    }
    return null;
  }

  void showMenu() {
    menuController.showFlyout(
        builder: (context) => MenuFlyout(
              items: [
                MenuFlyoutItem(
                    text: Text("Save to".tl),
                    onPressed: () async {
                      var file = await getFile();
                      if (file != null) {
                        saveFile(file);
                      }
                    }),
                MenuFlyoutItem(
                    text: Text("Share".tl),
                    onPressed: () async {
                      var file = await getFile();
                      if (file != null) {
                        var ext = file.path.split('.').last;
                        var mediaType = switch (ext) {
                          'jpg' => 'image/jpeg',
                          'jpeg' => 'image/jpeg',
                          'png' => 'image/png',
                          'gif' => 'image/gif',
                          'webp' => 'image/webp',
                          _ => 'application/octet-stream'
                        };
                        Share.shareXFiles([
                          XFile(file.path,
                              mimeType: mediaType,
                              name: file.path.split('/').last)
                        ]);
                      }
                    }),
              ],
            ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      color: FluentTheme.of(context).micaBackgroundColor,
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent &&
              !HardwareKeyboard.instance.isControlPressed) {
            if (event.scrollDelta.dy > 0 &&
                controller.page!.toInt() < widget.imagePaths.length - 1) {
              controller.jumpToPage(controller.page!.toInt() + 1);
            } else if (event.scrollDelta.dy < 0 &&
                controller.page!.toInt() > 0) {
              controller.jumpToPage(controller.page!.toInt() - 1);
            }
          }
        },
        child: LayoutBuilder(
          builder: (context, constrains) {
            var height = constrains.maxHeight;
            return Stack(
              children: [
                Positioned.fill(
                    child: PhotoViewGallery.builder(
                  pageController: controller,
                  backgroundDecoration:
                      const BoxDecoration(color: Colors.transparent),
                  itemCount: widget.imagePaths.length,
                  builder: (context, index) {
                    return PhotoViewGalleryPageOptions(
                      imageProvider: FileImage(File(widget.imagePaths[index])),
                    );
                  },
                  onPageChanged: (index) {
                    setState(() {
                      currentPage = index;
                    });
                  },
                )),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SizedBox(
                    height: 36,
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 6,
                        ),
                        IconButton(
                            icon: const Icon(FluentIcons.back).paddingAll(2),
                            onPressed: () => context.pop()),
                        const Expanded(
                          child: DragToMoveArea(
                            child: SizedBox.expand(),
                          ),
                        ),
                        buildActions(),
                        if (App.isDesktop)
                          WindowButtons(
                            key: ValueKey(windowButtonKey),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: height / 2 - 9,
                  child: IconButton(
                    icon: const Icon(
                      FluentIcons.chevron_left,
                      size: 18,
                    ),
                    onPressed: () {
                      controller.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ).paddingAll(8),
                ),
                Positioned(
                  right: 0,
                  top: height / 2 - 9,
                  child: IconButton(
                    icon: const Icon(FluentIcons.chevron_right, size: 18),
                    onPressed: () {
                      controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  ).paddingAll(8),
                ),
                Positioned(
                  left: 12,
                  bottom: 8,
                  child: Text(
                    "${currentPage + 1}/${widget.imagePaths.length}",
                  ),
                )
              ],
            );
          },
        ),
      ),
    );
  }

  Widget buildActions() {
    var width = MediaQuery.of(context).size.width;
    return FlyoutTarget(
      controller: menuController,
      child: width > 600
          ? Button(
              onPressed: showMenu,
              child: const Row(
                children: [
                  Icon(
                    MdIcons.menu,
                    size: 18,
                  ),
                  SizedBox(
                    width: 8,
                  ),
                  Text('Actions'),
                ],
              ))
          : IconButton(
              icon: const Icon(
                MdIcons.more_horiz,
                size: 20,
              ),
              onPressed: showMenu),
    );
  }
}

class _DownloadedUgoiraViewPage extends StatefulWidget {
  const _DownloadedUgoiraViewPage(this.illustId, this.zipPath);

  final int illustId;
  final String zipPath;

  @override
  State<_DownloadedUgoiraViewPage> createState() =>
      __DownloadedUgoiraViewPageState();
}

class __DownloadedUgoiraViewPageState
    extends State<_DownloadedUgoiraViewPage> with WindowListener {
  int windowButtonKey = 0;

  List<Map<String, dynamic>>? frames;
  String? error;

  @override
  void initState() {
    windowManager.addListener(this);
    _loadFrames();
    super.initState();
  }

  Future<void> _loadFrames() async {
    try {
      final dir = File(widget.zipPath).parent.path;
      final infoFile = File('$dir/info_${widget.illustId}.json');
      if (!await infoFile.exists()) {
        throw 'info file not found';
      }
      final info =
          jsonDecode(await infoFile.readAsString()) as Map<String, dynamic>;
      final list = (info['ugoiraFrames'] as List?) ?? [];
      if (list.isEmpty) throw 'no frames info';
      if (!mounted) return;
      setState(() {
        frames = list
            .map((e) => {
                  'file': (e as Map)['file'].toString(),
                  'delay': (e['delay'] as num).toInt(),
                })
            .toList();
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() {
      windowButtonKey++;
    });
  }

  @override
  void onWindowUnmaximize() {
    setState(() {
      windowButtonKey++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      color: FluentTheme.of(context).micaBackgroundColor,
      child: LayoutBuilder(builder: (context, constrains) {
        Widget body;
        if (error != null) {
          body = Center(child: Text(error!));
        } else if (frames == null) {
          body = const Center(child: ProgressRing());
        } else {
          body = UgoiraWidget(
            key: ValueKey(widget.illustId),
            id: widget.illustId.toString(),
            localZipPath: widget.zipPath,
            localFrames: frames!,
            width: constrains.maxWidth,
            height: constrains.maxHeight,
          );
        }
        return Stack(
          children: [
            Positioned.fill(child: Center(child: body)),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 36,
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    IconButton(
                        icon: const Icon(FluentIcons.back).paddingAll(2),
                        onPressed: () => context.pop()),
                    const Expanded(
                      child: DragToMoveArea(
                        child: SizedBox.expand(),
                      ),
                    ),
                    if (App.isDesktop)
                      WindowButtons(
                        key: ValueKey(windowButtonKey),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _DownloadedNovelViewPage extends StatefulWidget {
  const _DownloadedNovelViewPage(this.novel);

  final DownloadedNovel novel;

  @override
  State<_DownloadedNovelViewPage> createState() =>
      _DownloadedNovelViewPageState();
}

class _DownloadedNovelViewPageState extends State<_DownloadedNovelViewPage> {
  String text = "";
  bool loading = true;
  String query = "";

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      text = await File(widget.novel.filePath).readAsString();
    } catch (_) {
      text = "";
    }
    if (mounted) setState(() => loading = false);
  }

  List<String> get _matches {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final lower = q.toLowerCase();
    return text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e.toLowerCase().contains(lower))
        .toList();
  }

  Widget _highlighted(String paragraph, String q) {
    final lower = paragraph.toLowerCase();
    final needle = q.toLowerCase();
    final spans = <TextSpan>[];
    var i = 0;
    while (true) {
      final j = lower.indexOf(needle, i);
      if (j < 0) {
        spans.add(TextSpan(text: paragraph.substring(i)));
        break;
      }
      if (j > i) spans.add(TextSpan(text: paragraph.substring(i, j)));
      spans.add(TextSpan(
        text: paragraph.substring(j, j + needle.length),
        style: TextStyle(
          backgroundColor:
              FluentTheme.of(context).accentColor.withValues(alpha: 0.35),
          fontWeight: FontWeight.bold,
        ),
      ));
      i = j + needle.length;
    }
    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: TitleBar(title: widget.novel.title),
      content: loading
          ? const Center(child: ProgressRing())
          : Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(12, 4, 12, 4),
                  child: TextBox(
                    placeholder: "Search in text".tl,
                    onChanged: (v) => setState(() => query = v),
                    suffix: query.isEmpty
                        ? const Icon(FluentIcons.search, size: 14)
                        : null,
                  ),
                ),
                if (query.trim().isNotEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "${_matches.length} ${"matches".tl}",
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                Expanded(
                  child: query.trim().isEmpty
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(text),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _matches.length,
                          itemBuilder: (context, index) {
                            final para = _matches[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  vertical: 4),
                              padding: EdgeInsets.zero,
                              child: ListTile(
                                title: _highlighted(
                                    para.length > 200
                                        ? "${para.substring(0, 200)}…"
                                        : para,
                                    query.trim()),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (c) => ContentDialog(
                                      title: Text(
                                          "${"Paragraph".tl} ${index + 1}"),
                                      content: SingleChildScrollView(
                                        child: SelectableText(para),
                                      ),
                                      actions: [
                                        Button(
                                          child: Text('Close'.tl),
                                          onPressed: () =>
                                              Navigator.of(c).pop(),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
