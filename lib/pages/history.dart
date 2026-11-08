import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:pixes/appdata.dart';
import 'package:pixes/components/loading.dart';
import 'package:pixes/components/segmented_button.dart';
import 'package:pixes/components/title_bar.dart';
import 'package:pixes/foundation/app.dart';
import 'package:pixes/foundation/history.dart';
import 'package:pixes/network/download.dart';
import 'package:pixes/network/network.dart';
import 'package:pixes/utils/translation.dart';

import '../components/illust_widget.dart';
import 'illust_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TitleBar(
          title: "History".tl,
          action: SegmentedButton<int>(
            options: [
              SegmentedButtonOption(0, "Local".tl,),
              SegmentedButtonOption(1, "Network".tl,),
            ],
            value: page,
            onPressed: (key) {
              setState(() {
                page = key;
              });
            },
          ),
          ),
        Expanded(
          child: page == 0
              ? const LocalHistoryPage()
              : const NetworkHistoryPage(),
        ),
      ],
    );
  }
}

class LocalHistoryPage extends StatefulWidget {
  const LocalHistoryPage({super.key});

  @override
  State<LocalHistoryPage> createState() => _LocalHistoryPageState();
}

class _LocalHistoryPageState extends State<LocalHistoryPage> {
  int page = 1;

  var data = <IllustHistory>[];

  bool selecting = false;

  final Set<int> selected = {};

  bool _busy = false;

  Future<void> _downloadSelected() async {
    if (selected.isEmpty || _busy) return;
    setState(() => _busy = true);
    var count = 0;
    for (final id in selected.toList()) {
      try {
        final res = await Network().getIllustByID(id.toString());
        if (!res.error &&
            !res.data.downloaded &&
            !res.data.downloading) {
          DownloadManager().addDownloadingTask(res.data);
          count++;
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        selected.clear();
        selecting = false;
        _busy = false;
      });
      context.showToast(message: "Added to downloads".tl);
    } else {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: Row(
            children: [
              Button(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          selecting = !selecting;
                          if (!selecting) selected.clear();
                        }),
                child: Text(selecting ? "Done".tl : "Select".tl),
              ),
              if (selecting) ...[
                const SizedBox(width: 8),
                Text("Selected".tl),
                const SizedBox(width: 4),
                Text("${selected.length}"),
                const Spacer(),
                Button(
                  onPressed:
                      (selected.isEmpty || _busy) ? null : _downloadSelected,
                  child: Text(_busy ? "..." : "Download".tl),
                ),
                const SizedBox(width: 8),
                Button(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            selected.clear();
                            selecting = false;
                          }),
                  child: Text("Cancel".tl),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, constrains) {
            return MasonryGridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8) +
                  EdgeInsets.only(bottom: context.padding.bottom),
              gridDelegate:
                  const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 240,
              ),
              itemCount: HistoryManager().length,
              itemBuilder: (context, index) {
                if (index == data.length) {
                  data.addAll(HistoryManager().getHistories(page));
                  page++;
                }
                final item = data[index];
                return IllustHistoryWidget(
                  item,
                  selected: selected.contains(item.id),
                  onTap: selecting
                      ? () => setState(() {
                            if (selected.contains(item.id)) {
                              selected.remove(item.id);
                            } else {
                              selected.add(item.id);
                            }
                          })
                      : null,
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

class NetworkHistoryPage extends StatefulWidget {
  const NetworkHistoryPage({super.key});

  @override
  State<NetworkHistoryPage> createState() => _NetworkHistoryPageState();
}

class _NetworkHistoryPageState
    extends MultiPageLoadingState<NetworkHistoryPage, Illust> {
  @override
  Widget buildContent(BuildContext context, final List<Illust> data) {
    return LayoutBuilder(builder: (context, constrains) {
      return MasonryGridView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 8) +
            EdgeInsets.only(bottom: context.padding.bottom),
        gridDelegate: const SliverSimpleGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
        ),
        itemCount: data.length,
        itemBuilder: (context, index) {
          if (index == data.length - 1) {
            nextPage();
          }
          return IllustWidget(data[index], onTap: () {
            context.to(() => IllustGalleryPage(
                  illusts: data,
                  initialPage: index,
                ));
          });
        },
      );
    });
  }

  @override
  Future<Res<List<Illust>>> loadData(page) {
    if (appdata.account?.user.isPremium != true) {
      return Future.value(Res.error("Premium Required".tl));
    }
    return Network().getHistory(page);
  }
}
