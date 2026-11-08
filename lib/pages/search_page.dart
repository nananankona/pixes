import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:pixes/appdata.dart';
import 'package:pixes/components/loading.dart';
import 'package:pixes/components/novel.dart';
import 'package:pixes/components/page_route.dart';
import 'package:pixes/components/search_field.dart';
import 'package:pixes/components/user_preview.dart';
import 'package:pixes/foundation/app.dart';
import 'package:pixes/network/download.dart';
import 'package:pixes/network/network.dart';
import 'package:pixes/pages/illust_page.dart';
import 'package:pixes/pages/novel_page.dart';
import 'package:pixes/pages/user_info_page.dart';
import 'package:pixes/utils/app_links.dart';
import 'package:pixes/utils/block.dart';
import 'package:pixes/utils/debounce.dart';
import 'package:pixes/utils/ext.dart';
import 'package:pixes/utils/translation.dart';

import '../components/animated_image.dart';
import '../components/grid.dart';
import '../components/illust_widget.dart';
import '../components/md.dart';
import '../foundation/image_provider.dart';

const searchTypes = [
  "Search artwork",
  "Search novel",
  "Search user",
  "Artwork ID",
  "Artist ID",
  "Novel ID"
];

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  int searchType = 0;
  int historyKey = 0;
  bool showHistory = false;

  void search(String text) {
    if (text.isURL && handleLink(Uri.parse(text))) {
      return;
    } else if ("https://$text".isURL &&
        handleLink(Uri.parse("https://$text"))) {
      return;
    }
    switch (searchType) {
      case 0:
        context.to(() => SearchResultPage(text));
      case 1:
        context.to(() => SearchNovelResultPage(text));
      case 2:
        context.to(() => SearchUserResultPage(text));
      case 3:
        appdata.addSearchHistory(text, 3);
        context.to(() => IllustPageWithId(text));
      case 4:
        appdata.addSearchHistory(text, 4);
        context.to(() => UserInfoPage(text));
      case 5:
        appdata.addSearchHistory(text, 5);
        context.to(() => NovelPageWithId(text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      padding: const EdgeInsets.only(top: 8),
      content: Column(
        children: [
          _SearchBar(
            searchType: searchType,
            showHistory: showHistory,
            onTypeChanged: (type) {
              setState(() {
                searchType = type;
              });
            },
            onSearch: (text) {
              if (text.isEmpty) {
                return;
              }
              search(text);
              setState(() => historyKey++);
            },
            onHistoryToggle: () {
              setState(() {
                showHistory = !showHistory;
                historyKey++;
              });
            },
          ),
          Expanded(
            child: showHistory
                ? _SearchHistoryView(
                    key: ValueKey(historyKey),
                    onSearch: (entry) {
                      appdata.searchOptions.matchType = entry.matchType;
                      appdata.searchOptions.favoriteNumber = entry.favoriteNumber;
                      appdata.searchOptions.sort = entry.sort;
                      appdata.searchOptions.startTime = entry.startTime;
                      appdata.searchOptions.endTime = entry.endTime;
                      appdata.searchOptions.ageLimit = entry.ageLimit;
                      appdata.searchOptions.includeAiGeneratedWorks =
                          entry.includeAiGeneratedWorks;
                      switch (entry.searchType) {
                        case 0:
                          context.to(() => SearchResultPage(entry.keyword));
                        case 1:
                          context.to(() => SearchNovelResultPage(entry.keyword));
                        case 2:
                          context.to(() => SearchUserResultPage(entry.keyword));
                        case 3:
                          context.to(() => IllustPageWithId(entry.keyword));
                        case 4:
                          context.to(() => UserInfoPage(entry.keyword));
                        case 5:
                          context.to(() => NovelPageWithId(entry.keyword));
                      }
                    },
                    onClearAll: () {
                      appdata.clearSearchHistory();
                      setState(() => historyKey++);
                    },
                  )
                : const _TrendingTagsView(),
          ),
        ],
      ),
    );
  }
}

class _TrendingTagsView extends StatefulWidget {
  const _TrendingTagsView();

  @override
  State<_TrendingTagsView> createState() => _TrendingTagsViewState();
}

class _TrendingTagsViewState
    extends LoadingState<_TrendingTagsView, List<TrendingTag>> {
  @override
  Widget buildContent(BuildContext context, List<TrendingTag> data) {
    return MasonryGridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 8.0) +
          EdgeInsets.only(bottom: context.padding.bottom),
      gridDelegate: const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
      ),
      itemCount: data.length,
      itemBuilder: (context, index) {
        return buildItem(data[index]);
      },
    );
  }

  Widget buildItem(TrendingTag tag) {
    final illust = tag.illust;

    var text = tag.tag.name;
    if (tag.tag.translatedName != null) {
      text += "/${tag.tag.translatedName}";
    }

    return LayoutBuilder(builder: (context, constrains) {
      final width = constrains.maxWidth;
      final height = illust.height * width / illust.width;
      return Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
        child: Card(
          padding: EdgeInsets.zero,
          margin: EdgeInsets.zero,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () {
                context.to(() => SearchResultPage(tag.tag.name));
              },
              child: Stack(
                children: [
                  Positioned.fill(
                      child: ClipRRect(
                    borderRadius: BorderRadius.circular(4.0),
                    child: AnimatedImage(
                      image: CachedImageProvider(illust.images.first.medium),
                      fit: BoxFit.cover,
                      width: width - 16.0,
                      height: height - 16.0,
                    ),
                  )),
                  Positioned(
                    bottom: -2,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                          color: FluentTheme.of(context)
                              .micaBackgroundColor
                              .toOpacity(0.84),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(text)
                          .paddingHorizontal(4)
                          .paddingVertical(6)
                          .paddingBottom(2),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  @override
  Future<Res<List<TrendingTag>>> loadData() {
    return Network().getHotTags();
  }
}

class _SearchHistoryView extends StatefulWidget {
  const _SearchHistoryView({
    super.key,
    required this.onSearch,
    required this.onClearAll,
  });

  final void Function(SearchHistoryEntry) onSearch;
  final VoidCallback onClearAll;

  @override
  State<_SearchHistoryView> createState() => _SearchHistoryViewState();
}

class _SearchHistoryViewState extends State<_SearchHistoryView> {
  static const int pageSize = 20;
  final _scrollController = ScrollController();
  List<SearchHistoryEntry> _displayed = [];
  List<SearchHistoryEntry> _all = [];
  int _loaded = 0;
  int _filterType = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  List<SearchHistoryEntry> _filtered(List<SearchHistoryEntry> all) {
    if (_filterType < 0) return all;
    return all.where((e) => e.searchType == _filterType).toList();
  }

  void _loadMore() {
    _all = appdata.getSearchHistory();
    final limit = appdata.settings["searchHistoryLimit"] as int? ?? 50;
    final capped = limit > 0 && _all.length > limit ? _all.sublist(0, limit) : _all;
    final filtered = _filtered(capped);
    if (_loaded >= filtered.length) return;
    final end = (_loaded + pageSize > filtered.length) ? filtered.length : _loaded + pageSize;
    setState(() {
      _displayed.addAll(filtered.sublist(_loaded, end));
      _loaded = end;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_displayed.isEmpty) {
      return Center(child: Text("No search history".tl));
    }
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 16),
            Text("Search History".tl, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            Button(
              onPressed: widget.onClearAll,
              child: Text("Clear all".tl),
            ),
            const SizedBox(width: 16),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _filterChip("All".tl, -1),
              for (var i = 0; i < searchTypes.length; i++)
                _filterChip(searchTypes[i].tl, i),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            itemCount: _displayed.length + 1,
            itemBuilder: (context, index) {
              if (index == _displayed.length) {
                final limit = appdata.settings["searchHistoryLimit"] as int? ?? 50;
                final capped = limit > 0 && _all.length > limit ? _all.sublist(0, limit) : _all;
                final filtered = _filtered(capped);
                if (_loaded >= filtered.length) {
                  return const SizedBox.shrink();
                }
                return const Center(child: Padding(
                  padding: EdgeInsets.all(16),
                  child: ProgressRing(),
                ));
              }
              final entry = _displayed[index];
              final typeLabel = searchTypes.length > entry.searchType
                  ? searchTypes[entry.searchType].tl
                  : "";
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                child: GestureDetector(
                  onTap: () => widget.onSearch(entry),
                  child: Card(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Row(
                        children: [
                          Icon(FluentIcons.clock, size: 14, color: ColorScheme.of(context).onSurface.toOpacity(0.6)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.keyword, style: const TextStyle(fontWeight: FontWeight.w500)),
                                const SizedBox(height: 2),
                                Text(
                                  "$typeLabel / ${entry.sort.toString().tl}",
                                  style: TextStyle(fontSize: 12, color: ColorScheme.of(context).onSurface.toOpacity(0.6)),
                                ),
                              ],
                            ),
                          ),
                          Icon(FluentIcons.chevron_right, size: 14, color: ColorScheme.of(context).onSurface.toOpacity(0.4)),
                          IconButton(
                            icon: const Icon(FluentIcons.delete, size: 14),
                            onPressed: () {
                              appdata.removeSearchHistory(
                                  entry.keyword, entry.searchType);
                              setState(() {
                                _displayed.removeAt(index);
                                _loaded--;
                                _all = appdata.getSearchHistory();
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, int type) {
    final selected = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ToggleButton(
        checked: selected,
        onChanged: (value) {
          setState(() {
            _filterType = type;
            _displayed.clear();
            _loaded = 0;
            _all = appdata.getSearchHistory();
          });
          _loadMore();
        },
        child: Text(label, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class SearchSettings extends StatefulWidget {
  const SearchSettings({this.onChanged, this.isNovel = false, super.key});

  final void Function()? onChanged;

  final bool isNovel;

  @override
  State<SearchSettings> createState() => _SearchSettingsState();
}

class _SearchSettingsState extends State<SearchSettings> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            child: Text(
              "Search Settings".tl,
              style: const TextStyle(fontSize: 18),
            ),
          ).toAlign(Alignment.centerLeft),
          buildItem(
              title: "Safe only".tl,
              child: ToggleSwitch(
                checked: appdata.settings["safeOnly"] == true,
                onChanged: (value) {
                  setState(() {
                    appdata.settings["safeOnly"] = value;
                  });
                  appdata.writeData();
                  widget.onChanged?.call();
                },
              )),
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: Text(
              "Tip: use A OR B to combine keywords (up to 5)".tl,
              style: const TextStyle(fontSize: 12),
            ),
          ).toAlign(Alignment.centerLeft),
          buildItem(
              title: "Match".tl,
              child: DropDownButton(
                title: Text(appdata.searchOptions.matchType.toString().tl),
                items: KeywordMatchType.values
                    .map((e) => MenuFlyoutItem(
                        text: Text(e.toString().tl),
                        onPressed: () {
                          if (appdata.searchOptions.matchType != e) {
                            setState(() => appdata.searchOptions.matchType = e);
                            widget.onChanged?.call();
                          }
                        }))
                    .toList(),
              )),
          if (!widget.isNovel)
            buildItem(
                title: "Favorite number".tl,
                child: DropDownButton(
                  title:
                      Text(appdata.searchOptions.favoriteNumber.toString().tl),
                  items: FavoriteNumber.values
                      .map((e) => MenuFlyoutItem(
                          text: Text(e.toString().tl),
                          onPressed: () {
                            if (appdata.searchOptions.favoriteNumber != e) {
                              setState(() =>
                                  appdata.searchOptions.favoriteNumber = e);
                              widget.onChanged?.call();
                            }
                          }))
                      .toList(),
                )),
          buildItem(
              title: "Sort".tl,
              child: DropDownButton(
                title: Text(appdata.searchOptions.sort.toString().tl),
                items: SearchSort.values
                    .map((e) => MenuFlyoutItem(
                        text: Text(e.toString().tl),
                        onPressed: () {
                          if (appdata.searchOptions.sort != e) {
                            setState(() => appdata.searchOptions.sort = e);
                            widget.onChanged?.call();
                          }
                        }))
                    .toList(),
              )),
          buildItem(
              title: "Include AI-generated works".tl,
              child: ToggleSwitch(
                checked: appdata.searchOptions.includeAiGeneratedWorks,
                onChanged: (value) {
                  if (appdata.searchOptions.includeAiGeneratedWorks != value) {
                    setState(() {
                      appdata.searchOptions.includeAiGeneratedWorks = value;
                    });
                    widget.onChanged?.call();
                  }
                },
              )),
          if (!widget.isNovel)
            Card(
                padding: EdgeInsets.zero,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      Text(
                        "Start Time".tl,
                        style: const TextStyle(fontSize: 16),
                      )
                          .paddingVertical(8)
                          .toAlign(Alignment.centerLeft)
                          .paddingLeft(16),
                      DatePicker(
                        selected: appdata.searchOptions.startTime,
                        onChanged: (t) {
                          if (appdata.searchOptions.startTime != t) {
                            setState(() => appdata.searchOptions.startTime = t);
                            widget.onChanged?.call();
                          }
                        },
                      ),
                      const SizedBox(
                        height: 8,
                      )
                    ],
                  ),
                )),
          if (!widget.isNovel)
            Card(
                padding: EdgeInsets.zero,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      Text(
                        "End Time".tl,
                        style: const TextStyle(fontSize: 16),
                      )
                          .paddingVertical(8)
                          .toAlign(Alignment.centerLeft)
                          .paddingLeft(16),
                      DatePicker(
                        selected: appdata.searchOptions.endTime,
                        onChanged: (t) {
                          if (appdata.searchOptions.endTime != t) {
                            setState(() => appdata.searchOptions.endTime = t);
                            widget.onChanged?.call();
                          }
                        },
                      ),
                      const SizedBox(
                        height: 8,
                      )
                    ],
                  ),
                )),
          if (!widget.isNovel)
            buildItem(
                title: "Age limit".tl,
                child: DropDownButton(
                  title: Text(appdata.searchOptions.ageLimit.toString().tl),
                  items: AgeLimit.values
                      .map((e) => MenuFlyoutItem(
                          text: Text(e.toString().tl),
                          onPressed: () {
                            if (appdata.searchOptions.ageLimit != e) {
                              setState(
                                  () => appdata.searchOptions.ageLimit = e);
                              widget.onChanged?.call();
                            }
                          }))
                      .toList(),
                )),
          const SizedBox(height: 4),
          _PresetSection(
            onChanged: widget.onChanged,
          ),
          const SizedBox(height: 4),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(FluentIcons.info, size: 16),
                const SizedBox(
                  width: 4,
                ),
                Text("Close the pane to apply the settings".tl)
              ],
            ),
          ),
          SizedBox(
            height: context.padding.bottom,
          )
        ],
      ),
    );
  }

  Widget buildItem({required String title, required Widget child}) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.zero,
      child: ListTile(
        title: Text(title),
        trailing: child,
      ),
    );
  }
}

class _PresetSection extends StatefulWidget {
  const _PresetSection({this.onChanged});

  final void Function()? onChanged;

  @override
  State<_PresetSection> createState() => _PresetSectionState();
}

class _PresetSectionState extends State<_PresetSection> {
  final _nameCtl = TextEditingController();

  @override
  void dispose() {
    _nameCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presets = appdata.getSearchPresets();
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Search Presets".tl,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextBox(
                    controller: _nameCtl,
                    placeholder: "Preset name".tl,
                  ),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: () {
                    if (_nameCtl.text.trim().isEmpty) return;
                    appdata.saveSearchPreset(_nameCtl.text);
                    _nameCtl.clear();
                    widget.onChanged?.call();
                    setState(() {});
                  },
                  child: Text("Save current".tl),
                ),
              ],
            ),
            if (presets.isNotEmpty) const SizedBox(height: 8),
            for (final p in presets)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Button(
                        onPressed: () {
                          appdata.applySearchPreset(p);
                          widget.onChanged?.call();
                          setState(() {});
                        },
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(p.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(FluentIcons.delete, size: 14),
                      onPressed: () {
                        appdata.deleteSearchPreset(p.name);
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SearchResultPage extends StatefulWidget {
  const SearchResultPage(this.keyword, {super.key});

  final String keyword;

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState
    extends MultiPageLoadingState<SearchResultPage, Illust> {
  late String keyword = widget.keyword;

  late String oldKeyword = widget.keyword;

  late final controller = TextEditingController(text: widget.keyword);

  bool selecting = false;

  final Map<int, Illust> selected = {};

  void _toggleSelect(Illust illust) {
    setState(() {
      if (selected.containsKey(illust.id)) {
        selected.remove(illust.id);
      } else {
        selected[illust.id] = illust;
      }
    });
  }

  void _downloadSelected() {
    var count = 0;
    for (final illust in selected.values) {
      if (!illust.downloaded && !illust.downloading) {
        DownloadManager().addDownloadingTask(illust);
        count++;
      }
    }
    setState(() {
      selected.clear();
      selecting = false;
    });
    if (mounted) {
      context.showToast(message: "Added to downloads".tl);
    }
  }

  @override
  void reset() {
    nextUrl = null;
    _orNextUrls = [];
    _orSeenIds.clear();
    super.reset();
  }

  void search() {
    if (keyword != oldKeyword) {
      oldKeyword = keyword;
      reset();
    }
  }

  @override
  Widget buildContent(BuildContext context, final List<Illust> data) {
    checkIllusts(data);
    return CustomScrollView(
      slivers: [
        buildSearchBar(),
        if (selecting)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: ColorScheme.of(context).primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Text("Selected".tl),
                  const SizedBox(width: 4),
                  Text("${selected.length}"),
                  const Spacer(),
                  Button(
                    onPressed: selected.isEmpty ? null : _downloadSelected,
                    child: Text("Download".tl),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: () => setState(() {
                      selected.clear();
                      selecting = false;
                    }),
                    child: Text("Cancel".tl),
                  ),
                ],
              ),
            ),
          ),
        SliverMasonryGrid(
          gridDelegate: const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index == data.length - 1) {
                nextPage();
              }
              final illust = data[index];
              final isSelected = selected.containsKey(illust.id);
              return Stack(
                children: [
                  IllustWidget(
                    illust,
                    onTap: () {
                      if (selecting) {
                        _toggleSelect(illust);
                        return;
                      }
                      // OR queries merge multiple result streams, which the
                      // gallery pager cannot continue. Open without paging.
                      final orPaging =
                          _SearchResultPageState.splitOrTerms(keyword).length >
                                  1
                              ? null
                              : nextUrl;
                      context.to(() => IllustGalleryPage(
                          illusts: data,
                          initialPage: index,
                          nextUrl: orPaging));
                    },
                  ),
                  if (isSelected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        decoration: BoxDecoration(
                          color: ColorScheme.of(context).primary,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(FluentIcons.check_mark,
                            size: 14, color: Colors.white),
                      ),
                    ),
                ],
              );
            },
            childCount: data.length,
          ),
        ).sliverPaddingHorizontal(8),
        SliverPadding(
          padding: EdgeInsets.only(bottom: context.padding.bottom),
        )
      ],
    );
  }

  Widget buildSearchBar() {
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SizedBox(
            height: 42,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constrains) {
                return SizedBox(
                  height: 42,
                  width: constrains.maxWidth,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextBox(
                          controller: controller,
                          placeholder: "Search artworks".tl,
                          onChanged: (s) => keyword = s,
                          onSubmitted: (s) => search(),
                          foregroundDecoration: WidgetStatePropertyAll(
                            BoxDecoration(
                              border: Border.all(
                                color: ColorScheme.of(context)
                                    .outlineVariant
                                    .toOpacity(0.6),
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          suffix: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: search,
                              child: const Icon(
                                FluentIcons.search,
                                size: 16,
                              ).paddingHorizontal(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 4,
                      ),
                      Button(
                        child: SizedBox(
                          height: 42,
                          child: Center(
                            child: Icon(selecting
                                ? FluentIcons.check_mark
                                : FluentIcons.bulleted_list),
                          ),
                        ),
                        onPressed: () => setState(() {
                          selecting = !selecting;
                          if (!selecting) selected.clear();
                        }),
                      ),
                      const SizedBox(
                        width: 4,
                      ),
                      Button(
                        child: const SizedBox(
                          height: 42,
                          child: Center(
                            child: Icon(FluentIcons.settings),
                          ),
                        ),
                        onPressed: () async {
                          bool isChanged = false;
                          await Navigator.of(context)
                              .push(SideBarRoute(SearchSettings(
                            onChanged: () => isChanged = true,
                          )));
                          if (isChanged) {
                            reset();
                          }
                        },
                      )
                    ],
                  ),
                );
              },
            ),
          ).paddingHorizontal(16),
        ),
      ),
    ).sliverPadding(const EdgeInsets.only(top: 12));
  }

  String? nextUrl;

  List<String?> _orNextUrls = [];
  final Set<int> _orSeenIds = {};

  static List<String> splitOrTerms(String keyword) {
    return keyword
        .split(RegExp(r'\s+OR\s+', caseSensitive: false))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(5)
        .toList();
  }

  static int compareIllusts(Illust a, Illust b, SearchSort sort) {
    switch (sort) {
      case SearchSort.oldToNew:
        return a.createDate.compareTo(b.createDate);
      case SearchSort.newToOld:
        return b.createDate.compareTo(a.createDate);
      default:
        return b.totalBookmarks.compareTo(a.totalBookmarks);
    }
  }

  @override
  Future<Res<List<Illust>>> loadData(page) async {
    if (nextUrl == "end") {
      return Res.error("No more data");
    }
    final terms = splitOrTerms(keyword);
    if (terms.length < 2) {
      if (nextUrl == null) {
        appdata.addSearchHistory(keyword, 0);
      }
      var res = nextUrl == null
          ? await Network().search(keyword, appdata.searchOptions)
          : await Network().getIllustsWithNextUrl(nextUrl!);
      if (!res.error) {
        nextUrl = res.subData;
        nextUrl ??= "end";
      }
      return res;
    }
    if (nextUrl == null) {
      appdata.addSearchHistory(keyword, 0);
      _orNextUrls = List.filled(terms.length, null);
      _orSeenIds.clear();
    }
    while (_orNextUrls.length < terms.length) {
      _orNextUrls.add(null);
    }
    final results = await Future.wait([
      for (var i = 0; i < terms.length; i++)
        () async {
          final u = _orNextUrls[i];
          if (u == "end") return null;
          try {
            final r = u == null
                ? await Network().search(terms[i], appdata.searchOptions)
                : await Network().getIllustsWithNextUrl(u);
            return MapEntry(i, r);
          } catch (_) {
            return null;
          }
        }(),
    ]);
    var merged = <Illust>[];
    var anySuccess = false;
    for (final e in results) {
      if (e == null || e.value.error) continue;
      anySuccess = true;
      _orNextUrls[e.key] = e.value.subData ?? "end";
      for (final it in e.value.data) {
        if (_orSeenIds.add(it.id)) merged.add(it);
      }
    }
    if (!anySuccess) {
      return Res.error("No more data");
    }
    merged.sort((a, b) => compareIllusts(a, b, appdata.searchOptions.sort));
    nextUrl = _orNextUrls.any((u) => u != "end") ? "more" : "end";
    return Res(merged, subData: nextUrl);
  }
}

class SearchUserResultPage extends StatefulWidget {
  const SearchUserResultPage(this.keyword, {super.key});

  final String keyword;

  @override
  State<SearchUserResultPage> createState() => _SearchUserResultPageState();
}

class _SearchUserResultPageState
    extends MultiPageLoadingState<SearchUserResultPage, UserPreview> {
  @override
  Widget buildContent(BuildContext context, final List<UserPreview> data) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Text(
            "${"Search".tl}: ${widget.keyword}",
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ).paddingVertical(12).paddingHorizontal(16),
        ),
        SliverGridViewWithFixedItemHeight(
          delegate: SliverChildBuilderDelegate((context, index) {
            if (index == data.length - 1) {
              nextPage();
            }
            return UserPreviewWidget(data[index]);
          }, childCount: data.length),
          minCrossAxisExtent: 440,
          itemHeight: 136,
        ).sliverPaddingHorizontal(8),
        SliverPadding(
          padding: EdgeInsets.only(bottom: context.padding.bottom),
        )
      ],
    );
  }

  String? nextUrl;

  @override
  Future<Res<List<UserPreview>>> loadData(page) async {
    if (nextUrl == "end") {
      return Res.error("No more data");
    }
    if (nextUrl == null) {
      appdata.addSearchHistory(widget.keyword, 2);
    }
    var res = await Network().searchUsers(widget.keyword, nextUrl);
    if (!res.error) {
      nextUrl = res.subData;
      nextUrl ??= "end";
    }
    return res;
  }
}

class SearchNovelResultPage extends StatefulWidget {
  const SearchNovelResultPage(this.keyword, {super.key});

  final String keyword;

  @override
  State<SearchNovelResultPage> createState() => _SearchNovelResultPageState();
}

class _SearchNovelResultPageState
    extends MultiPageLoadingState<SearchNovelResultPage, Novel> {
  late String keyword = widget.keyword;

  late String oldKeyword = widget.keyword;

  late final controller = TextEditingController(text: widget.keyword);

  List<String?> _orNextUrls = [];
  final Set<String> _orSeenKeys = {};

  @override
  void reset() {
    nextUrl = null;
    _orNextUrls = [];
    _orSeenKeys.clear();
    super.reset();
  }

  void search() {
    if (keyword != oldKeyword) {
      oldKeyword = keyword;
      reset();
    }
  }

  static int compareNovels(Novel a, Novel b, SearchSort sort) {
    switch (sort) {
      case SearchSort.oldToNew:
        return a.createDate.compareTo(b.createDate);
      case SearchSort.newToOld:
        return b.createDate.compareTo(a.createDate);
      default:
        return b.totalBookmarks.compareTo(a.totalBookmarks);
    }
  }

  @override
  Widget buildContent(BuildContext context, final List<Novel> data) {
    return CustomScrollView(
      slivers: [
        buildSearchBar(),
        SliverGridViewWithFixedItemHeight(
          itemHeight: 164,
          minCrossAxisExtent: 400,
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              if (index == data.length - 1) {
                nextPage();
              }
              return NovelWidget(data[index]);
            },
            childCount: data.length,
          ),
        ).sliverPaddingHorizontal(8),
        SliverPadding(
          padding: EdgeInsets.only(bottom: context.padding.bottom),
        )
      ],
    );
  }

  Widget buildSearchBar() {
    return SliverToBoxAdapter(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SizedBox(
            height: 42,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constrains) {
                return SizedBox(
                  height: 42,
                  width: constrains.maxWidth,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextBox(
                          controller: controller,
                          placeholder: "Search artworks".tl,
                          onChanged: (s) => keyword = s,
                          onSubmitted: (s) => search(),
                          foregroundDecoration: WidgetStatePropertyAll(
                            BoxDecoration(
                                border: Border.all(
                                    color: ColorScheme.of(context)
                                        .outlineVariant
                                        .toOpacity(0.6)),
                                borderRadius: BorderRadius.circular(4)),
                          ),
                          suffix: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: GestureDetector(
                              onTap: search,
                              child: const Icon(
                                FluentIcons.search,
                                size: 16,
                              ).paddingHorizontal(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 4,
                      ),
                      Button(
                        child: const SizedBox(
                          height: 42,
                          child: Center(
                            child: Icon(FluentIcons.settings),
                          ),
                        ),
                        onPressed: () async {
                          bool isChanged = false;
                          await Navigator.of(context)
                              .push(SideBarRoute(SearchSettings(
                            onChanged: () => isChanged = true,
                            isNovel: true,
                          )));
                          if (isChanged) {
                            reset();
                          }
                        },
                      )
                    ],
                  ),
                );
              },
            ),
          ).paddingHorizontal(16),
        ),
      ),
    ).sliverPadding(const EdgeInsets.only(top: 12));
  }

  String? nextUrl;

  @override
  Future<Res<List<Novel>>> loadData(page) async {
    if (nextUrl == "end") {
      return Res.error("No more data");
    }
    final terms = _SearchResultPageState.splitOrTerms(keyword);
    if (terms.length < 2) {
      if (nextUrl == null) {
        appdata.addSearchHistory(keyword, 1);
      }
      var res = nextUrl == null
          ? await Network().searchNovels(keyword, appdata.searchOptions)
          : await Network().getNovelsWithNextUrl(nextUrl!);
      if (!res.error) {
        nextUrl = res.subData;
        nextUrl ??= "end";
      }
      return res;
    }
    if (nextUrl == null) {
      appdata.addSearchHistory(keyword, 1);
      _orNextUrls = List.filled(terms.length, null);
      _orSeenKeys.clear();
    }
    while (_orNextUrls.length < terms.length) {
      _orNextUrls.add(null);
    }
    final results = await Future.wait([
      for (var i = 0; i < terms.length; i++)
        () async {
          final u = _orNextUrls[i];
          if (u == "end") return null;
          try {
            final r = u == null
                ? await Network().searchNovels(terms[i], appdata.searchOptions)
                : await Network().getNovelsWithNextUrl(u);
            return MapEntry(i, r);
          } catch (_) {
            return null;
          }
        }(),
    ]);
    var merged = <Novel>[];
    var anySuccess = false;
    for (final e in results) {
      if (e == null || e.value.error) continue;
      anySuccess = true;
      _orNextUrls[e.key] = e.value.subData ?? "end";
      for (final it in e.value.data) {
        if (_orSeenKeys.add('${it.id}')) merged.add(it);
      }
    }
    if (!anySuccess) {
      return Res.error("No more data");
    }
    merged.sort(
        (a, b) => _SearchNovelResultPageState.compareNovels(a, b, appdata.searchOptions.sort));
    nextUrl = _orNextUrls.any((u) => u != "end") ? "more" : "end";
    return Res(merged, subData: nextUrl);
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.searchType,
    required this.onTypeChanged,
    required this.onSearch,
    this.showHistory = false,
    this.onHistoryToggle,
  });

  final int searchType;

  final void Function(int) onTypeChanged;

  final void Function(String) onSearch;

  final bool showHistory;

  final VoidCallback? onHistoryToggle;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final optionController = FlyoutController();

  final textController = TextEditingController();

  var autoCompleteItems = <AutoCompleteItem>[];

  var debouncer = Debounce(delay: const Duration(milliseconds: 300));

  var autoCompleteKey = 0;

  var isLoadingAutoCompleteItems = false;

  Widget buildSearchOption(BuildContext context) {
    return MenuFlyout(
      items: List.generate(
        searchTypes.length,
        (index) => MenuFlyoutItem(
          text: Text(searchTypes[index].tl),
          onPressed: () => widget.onTypeChanged(index),
        ),
      ),
    );
  }

  void onTextChanged(String text) {
    if (widget.searchType == 3 ||
        widget.searchType == 4 ||
        widget.searchType == 5) {
      return;
    }

    if (text.isEmpty) {
      setState(() {
        autoCompleteItems = [];
        isLoadingAutoCompleteItems = false;
      });
      return;
    }
    setState(() {
      isLoadingAutoCompleteItems = true;
    });
    debouncer.call(() async {
      var key = ++autoCompleteKey;

      var res = await Network().getAutoCompleteTags(text);
      if (res.error) {
        return;
      }
      var items = res.data.map((e) {
        return AutoCompleteItem(
          title: e.name,
          subtitle: e.translatedName,
          onTap: () {
            textController.text = e.name;
            widget.onSearch(e.name);
          },
        );
      }).toList();

      if (key != autoCompleteKey) {
        return; // ignore old request
      }

      setState(() {
        autoCompleteItems = items;
        isLoadingAutoCompleteItems = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: SizedBox(
        height: 42,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constrains) {
            return SizedBox(
              height: 42,
              width: constrains.maxWidth,
              child: Row(
                children: [
                  Expanded(
                    child: SearchField(
                      enableAutoComplete: widget.searchType != 3 &&
                          widget.searchType != 4 &&
                          widget.searchType != 5,
                      textEditingController: textController,
                      autoCompleteNoResultsText: "No results found".tl,
                      isLoadingAutoCompleteItems: isLoadingAutoCompleteItems,
                      autoCompleteItems: autoCompleteItems,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      placeholder:
                          '${searchTypes[widget.searchType].tl} / ${"Open link".tl}',
                      onChanged: onTextChanged,
                      onSubmitted: widget.onSearch,
                      foregroundDecoration: WidgetStatePropertyAll(
                        BoxDecoration(
                          border: Border.all(
                            color: ColorScheme.of(context)
                                .outlineVariant
                                .toOpacity(0.6),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      trailing: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => widget.onSearch(textController.text),
                          child: const Icon(
                            FluentIcons.search,
                            size: 16,
                          ).paddingHorizontal(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  FlyoutTarget(
                    controller: optionController,
                    child: Button(
                      child: const SizedBox(
                        height: 42,
                        child: Center(
                          child: Icon(FluentIcons.chevron_down),
                        ),
                      ),
                      onPressed: () {
                        optionController.showFlyout(
                          placementMode: FlyoutPlacementMode.bottomCenter,
                          builder: buildSearchOption,
                          barrierColor: Colors.transparent,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Button(
                    child: const SizedBox(
                      height: 42,
                      child: Center(
                        child: Icon(FluentIcons.settings),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(SideBarRoute(SearchSettings(
                        isNovel: widget.searchType == 1,
                      )));
                    },
                  ),
                  const SizedBox(width: 4),
                  Button(
                    child: SizedBox(
                      height: 42,
                      child: Center(
                        child: Icon(
                          widget.showHistory ? FluentIcons.history : FluentIcons.clock,
                        ),
                      ),
                    ),
                    onPressed: widget.onHistoryToggle,
                  ),
                ],
              ),
            );
          },
        ),
      ).paddingHorizontal(16),
    );
  }
}
