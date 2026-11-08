import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:pixes/appdata.dart';
import 'package:pixes/foundation/app.dart';
import 'package:pixes/foundation/log.dart';
import 'package:pixes/network/app_dio.dart';
import 'package:pixes/network/network.dart';
import 'package:pixes/utils/block.dart';
import 'package:pixes/utils/io.dart';
import 'package:sqlite3/sqlite3.dart';

extension IllustExt on Illust {
  bool get downloaded => DownloadManager().checkDownloaded(id);

  bool get downloading =>
      DownloadManager().tasks.any((element) => element.illust.id == id);
}

class DownloadedIllust {
  final int illustId;
  final String title;
  final String author;
  final int imageCount;

  DownloadedIllust({
    required this.illustId,
    required this.title,
    required this.author,
    required this.imageCount,
  });
}

class DownloadedNovel {
  final int novelId;
  final String title;
  final String filePath;
  final int fileSize;

  DownloadedNovel({
    required this.novelId,
    required this.title,
    required this.filePath,
    required this.fileSize,
  });
}

/// Auto-download on view. Called when an artwork/novel is actually displayed
/// (not on pre-built neighbors). Respects private mode and block list.
void maybeAutoDownloadIllust(Illust illust) {
  final mode = appdata.settings["autoDownload"] as int? ?? 0;
  if (mode != 1 && mode != 3) return;
  if (appdata.settings["privateMode"] == true) return;
  if (illust.downloaded || illust.downloading) return;
  if (checkIllusts([illust]).isEmpty) return;
  final manager = DownloadManager();
  // Cap the auto queue so mass browsing doesn't flood downloads.
  if (manager.tasks.length >= manager.maxConcurrentTasks * 3) {
    Log.info("Download", "Auto download skipped (queue full): ${illust.id}");
    return;
  }
  Log.info("Download", "Auto download started: ${illust.id}");
  manager.addDownloadingTask(illust);
}

Future<void> maybeAutoDownloadNovel(Novel novel, String text) async {
  final mode = appdata.settings["autoDownload"] as int? ?? 0;
  if (mode != 2 && mode != 3) return;
  if (appdata.settings["privateMode"] == true) return;
  try {
    final downloadPath = appdata.settings["downloadPath"] as String?;
    if (downloadPath == null || downloadPath.isEmpty) return;
    final dir = Directory("$downloadPath/novel");
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final safeTitle = novel.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final file = File("${dir.path}/${novel.id}_$safeTitle.txt");
    if (await file.exists()) return;
    await file.writeAsString(
        "${novel.title}\n${novel.author.name} (id:${novel.author.id})\n\n$text");
  } catch (e) {
    Log.error("Download", "Auto novel save failed: $e");
  }
}

class DownloadingTask {
  final Illust illust;

  void Function(int)? receiveBytesCallback;

  void Function(DownloadingTask)? onCompleted;

  DownloadingTask(this.illust, {this.receiveBytesCallback, this.onCompleted});

  int _downloadingIndex = 0;

  int get totalImages => illust.images.length;

  int get downloadedImages => _downloadingIndex;

  bool _stop = true;

  String? error;

  void start() {
    _stop = false;
    _download();
  }

  Dio get dio => Network().dio;

  void cancel() {
    _stop = true;
    DownloadManager().tasks.remove(this);
    for(var path in imagePaths) {
      File(path).deleteIfExists();
    }
  }

  List<String> imagePaths = [];

  void _download() async{
    try{
      if (illust.isUgoira) {
        await _downloadUgoira();
        onCompleted?.call(this);
        return;
      }
      while(_downloadingIndex < illust.images.length) {
        if(_stop) return;
        var url = illust.images[_downloadingIndex].original;
        var ext = url.split('.').last;
        if(!["jpg", "png", "gif", "webp", "jpeg", "avif"].contains(ext)) {
          ext = "jpg";
        }
        var path = _generateFilePath(illust, _downloadingIndex, ext);
        final time = DateFormat("yyyy-MM-dd'T'HH:mm:ss'+00:00'").format(DateTime.now());
        final hash = md5.convert(utf8.encode(time + Network.hashSalt)).toString();
        var file = File(path);
        var resumeFrom = 0;
        if (file.existsSync()) {
          resumeFrom = file.lengthSync();
        } else {
          file.createSync(recursive: true);
        }
        final headers = {
          "referer": "https://app-api.pixiv.net/",
          "user-agent": "PixivAndroidApp/5.0.234 (Android 14; Pixes)",
          "x-client-time": time,
          "x-client-hash": hash,
          "accept-enconding": "gzip",
          if (resumeFrom > 0) "Range": "bytes=$resumeFrom-",
        };
        var res = await dio.get<ResponseBody>(url, options: Options(
          responseType: ResponseType.stream,
          headers: headers,
        ));
        if (resumeFrom > 0 && res.statusCode != 206) {
          // Server ignored Range: restart the file instead of appending.
          await file.writeAsBytes([], mode: FileMode.write);
          resumeFrom = 0;
        }
        await for (var data in res.data!.stream) {
          await file.writeAsBytes(data, mode: FileMode.append);
          receiveBytesCallback?.call(data.length);
        }
        imagePaths.add(path);
        _downloadingIndex++;
        _retryCount = 0;
      }
      onCompleted?.call(this);
    }
    catch(e, s) {
      _handleError(e);
      Log.error("Download", "Download error: $e\n$s");
    }
  }

  int _retryCount = 0;

  /// Ugoira frames live in a zip archive, not in illust.images.
  /// Downloads the zip, a cover image, and records frame metadata
  /// for local playback and change detection.
  List<Map<String, dynamic>> ugoiraFrames = [];

  Future<void> _downloadUgoira() async {
    var metaRes =
        await Network().apiGet('/v1/ugoira/metadata?illust_id=${illust.id}');
    if (metaRes.error) {
      throw metaRes.errorMessage ?? "Failed to get ugoira metadata";
    }
    final meta = metaRes.data['ugoira_metadata'] as Map<String, dynamic>;
    final zipUrl = (meta['zip_urls'] as Map)['medium'] as String;
    ugoiraFrames = ((meta['frames'] as List).map((e) => {
          'file': (e as Map)['file'],
          'delay': e['delay'],
        })).toList();
    var path = _generateFilePath(illust, 0, 'zip');
    final time = DateFormat("yyyy-MM-dd'T'HH:mm:ss'+00:00'").format(DateTime.now());
    final hash = md5.convert(utf8.encode(time + Network.hashSalt)).toString();
    var file = File(path);
    var resumeFrom = 0;
    if (file.existsSync()) {
      resumeFrom = file.lengthSync();
    } else {
      file.createSync(recursive: true);
    }
    var res = await dio.get<ResponseBody>(zipUrl, options: Options(
      responseType: ResponseType.stream,
      headers: {
        "referer": "https://app-api.pixiv.net/",
        "user-agent": "PixivAndroidApp/5.0.234 (Android 14; Pixes)",
        "x-client-time": time,
        "x-client-hash": hash,
        "accept-enconding": "gzip",
        if (resumeFrom > 0) "Range": "bytes=$resumeFrom-",
      },
    ));
    if (resumeFrom > 0 && res.statusCode != 206) {
      await file.writeAsBytes([], mode: FileMode.write);
    }
    await for (var data in res.data!.stream) {
      await file.writeAsBytes(data, mode: FileMode.append);
      receiveBytesCallback?.call(data.length);
    }
    imagePaths.add(path);
    _downloadingIndex = illust.images.length;
    _retryCount = 0;
    await _saveUgoiraCover(path);
  }

  /// Saves the zip's first frame as a cover image for lists.
  Future<void> _saveUgoiraCover(String zipPath) async {
    try {
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive) {
        if (f.isFile && f.content != null) {
          final dir = File(zipPath).parent.path;
          await File('$dir/cover_${illust.id}.jpg')
              .writeAsBytes(Uint8List.fromList(f.content as List<int>));
          return;
        }
      }
    } catch (e) {
      Log.error("Download", "Failed to save ugoira cover: $e");
    }
  }

  void _handleError(Object e) async{
    _retryCount++;
    if(_retryCount > 3) {
      _stop = true;
      error = e.toString();
      Log.error("Download", "Download failed (id=${illust.id}): $e");
      return;
    }
    await Future.delayed(Duration(seconds: 1 << _retryCount));
    _download();
  }

  static String _sanitizeComponent(String s) {
    var cleaned = s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (cleaned.isEmpty) cleaned = '_';
    if (cleaned.length > 100) cleaned = cleaned.substring(0, 100);
    return cleaned;
  }

  static const _defaultSubPath = r"/${id}-p${index}.${ext}";

  static String _generateFilePath(Illust illust, int index, String ext) {
    final String downloadPath = appdata.settings["downloadPath"];
    var mode = appdata.settings["folderMode"] as int? ?? 0;
    // Backward compat: users with a customized pattern keep using it.
    if (mode == 0 &&
        (appdata.settings["downloadSubPath"] as String? ??
                _defaultSubPath) !=
            _defaultSubPath) {
      mode = 3;
    }
    if (mode == 3) {
      var subPathPatten = appdata.settings["downloadSubPath"];
      subPathPatten = subPathPatten.replaceAll(r"${id}", illust.id.toString());
      subPathPatten = subPathPatten.replaceAll(r"${title}", illust.title);
      subPathPatten = subPathPatten.replaceAll(r"${author}", illust.author.name);
      subPathPatten = subPathPatten.replaceAll(r"${index}", index.toString());
      subPathPatten = subPathPatten.replaceAll(r"${page}",
          illust.images.length == 1 ? "" : "-p$index");
      subPathPatten = subPathPatten.replaceAll(r"${ext}", ext);
      subPathPatten = subPathPatten.replaceAll(r"${AI}", illust.isAi ? "AI" : "");
      List<String> extractTags(String input) {
        final regex = RegExp(r'\$\{tag\((.*?)\)\}');
        final matches = regex.allMatches(input);
        return matches.map((match) => match.group(1)!).toList();
      }
      var tags = extractTags(subPathPatten);
      for (var tag in tags) {
        if (illust.tags.where((e) => e.name == tag || e.translatedName == tag).isNotEmpty) {
          subPathPatten = subPathPatten.replaceAll("\${tag($tag)}", tag);
        }
      }
      return _cleanFilePath("$downloadPath$subPathPatten");
    }
    String rel;
    if (mode == 1) {
      rel = "/${_sanitizeComponent(illust.author.name)}/${illust.id}-p$index.$ext";
    } else if (mode == 2) {
      rel = "/${_sanitizeComponent(illust.author.name)}/${_sanitizeComponent(illust.title)}_${illust.id}/$index.$ext";
    } else {
      rel = "/${illust.id}-p$index.$ext";
    }
    return _cleanFilePath("$downloadPath$rel");
  }

  static String _cleanFilePath(String filePath) {
    const invalidChars = ['*', '?', '"', '<', '>', '|'];

    String cleanedPath =
        filePath.replaceAll(RegExp('[${invalidChars.join(' ')}]'), '');

    cleanedPath = cleanedPath.replaceAll(RegExp(r'[/\\]+'), '/');

    return cleanedPath;
  }

  void retry() {
    error = null;
    _stop = false;
    _download();
  }

  void pause() {
    _stop = true;
  }
}

class DownloadManager {
  factory DownloadManager() => instance ??= DownloadManager._();

  static DownloadManager? instance;

  DownloadManager._(){
    init();
  }

  late Database _db;

  int _currentBytes = 0;
  int _bytesPerSecond = 0;

  int get bytesPerSecond => _bytesPerSecond;

  Timer? _loop;

  var tasks = <DownloadingTask>[];

  void Function()? uiUpdateCallback;

  void registerUiUpdater(void Function() callback) {
    uiUpdateCallback = callback;
  }

  void removeUiUpdater() {
    uiUpdateCallback = null;
  }

  void init() {
    _db = sqlite3.open("${App.dataPath}/download.db");
    _db.execute('''
      create table if not exists download (
        illust_id integer primary key not null,
        title text not null,
        author text not null,
        imageCount int not null
      );
    ''');
    _db.execute('''
      create table if not exists images (
        illust_id integer not null,
        image_index integer not null,
        path text not null,
        primary key (illust_id, image_index)
      );
    ''');
  }

  void saveInfo(Illust illust, List<String> imagePaths) {
    _db.execute('''
      insert into download (illust_id, title, author, imageCount)
      values (?, ?, ?, ?)
    ''', [illust.id, illust.title, illust.author.name, imagePaths.length]);
    for (var i = 0; i < imagePaths.length; i++) {
      _db.execute('''
        insert into images (illust_id, image_index, path)
        values (?, ?, ?)
      ''', [illust.id, i, imagePaths[i]]);
    }
  }

  File? getImage(int illustId, int index) {
    var res = _db.select('''
      select * from images
      where illust_id = ? and image_index = ?;
    ''', [illustId, index]);
    if (res.isEmpty) return null;
    var file = File(res.first["path"] as String);
    if (!file.existsSync()) return null;
    return file;
  }

  bool checkDownloaded(int illustId) {
    var res = _db.select('''
      select * from download
      where illust_id = ?;
    ''', [illustId]);
    return res.isNotEmpty;
  }

  List<DownloadedIllust> listAll() {
    var res = _db.select('''
      select * from download;
    ''');
    return res.map((e) =>
        DownloadedIllust(
          illustId: e["illust_id"] as int,
          title: e["title"] as String,
          author: e["author"] as String,
          imageCount: e["imageCount"] as int,
        )).toList();
  }

  /// Novels auto-saved as "$downloadPath/novel/<id>_<title>.txt".
  List<DownloadedNovel> listNovels() {
    try {
      final downloadPath = appdata.settings["downloadPath"] as String?;
      if (downloadPath == null || downloadPath.isEmpty) return [];
      final dir = Directory("$downloadPath/novel");
      if (!dir.existsSync()) return [];
      final out = <DownloadedNovel>[];
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        if (!e.path.toLowerCase().endsWith('.txt')) continue;
        try {
          final name = e.path.split(RegExp(r'[/\\]')).last;
          final stem = name.substring(0, name.length - 4);
          final sep = stem.indexOf('_');
          final id = sep > 0 ? int.tryParse(stem.substring(0, sep)) ?? 0 : 0;
          var title = sep >= 0 ? stem.substring(sep + 1) : stem;
          if (title.isEmpty) title = stem;
          out.add(DownloadedNovel(
            novelId: id,
            title: title,
            filePath: e.path,
            fileSize: e.existsSync() ? e.lengthSync() : 0,
          ));
        } catch (_) {}
      }
      out.sort((a, b) => a.title.compareTo(b.title));
      return out;
    } catch (_) {
      return [];
    }
  }

  void deleteNovel(DownloadedNovel novel) {
    try {
      File(novel.filePath).deleteIfExists();
    } catch (e) {
      Log.error("Download", "Failed to delete novel: $e");
    }
  }

  void addDownloadingTask(Illust illust) {
    if(illust.downloaded || illust.downloading) return;
    var task = DownloadingTask(illust, receiveBytesCallback: receiveBytes, onCompleted: (task) {
      saveInfo(illust, task.imagePaths);
      saveArtworkMetadata(illust, task.imagePaths,
          task.ugoiraFrames.isEmpty ? null : task.ugoiraFrames);
      tasks.remove(task);
      if (appdata.settings["saveAutoFavorite"] == true &&
          !illust.isBookmarked) {
        Network()
            .addBookmark(illust.id.toString(), "add", "public")
            .then((res) {
          if (!res.error) illust.isBookmarked = true;
        });
      }
    });
    tasks.add(task);
    run();
  }

  /// Saves a snapshot of the post (info.json) and first-page comments
  /// (comments.json) next to the downloaded files. Used for change
  /// detection (edited posts / deleted comments) when reopening.
  Future<void> saveArtworkMetadata(Illust illust, List<String> imagePaths,
      [List<Map<String, dynamic>>? ugoiraFrames]) async {
    try {
      if (imagePaths.isEmpty) return;
      final dir = File(imagePaths.first).parent;
      if (!await dir.exists()) return;
      final info = {
        'id': illust.id,
        'title': illust.title,
        'caption': illust.caption,
        'author': {
          'id': illust.author.id,
          'name': illust.author.name,
          'account': illust.author.account,
        },
        'tags': illust.tags
            .map((t) => {'name': t.name, 'translated': t.translatedName})
            .toList(),
        'pageCount': illust.pageCount,
        'width': illust.width,
        'height': illust.height,
        'totalViews': illust.totalView,
        'totalBookmarks': illust.totalBookmarks,
        'isAi': illust.isAi,
        'isUgoira': illust.isUgoira,
        'isR18': illust.isR18,
        'isR18G': illust.isR18G,
        'createDate': illust.createDate.toIso8601String(),
        'downloadedAt': DateTime.now().toIso8601String(),
        'files': imagePaths.map((p) => p.split(RegExp(r'[/\\]')).last).toList(),
        if (ugoiraFrames != null) 'ugoiraFrames': ugoiraFrames,
      };
      await File('${dir.path}/info_${illust.id}.json')
          .writeAsString(jsonEncode(info));
      try {
        final commentsRes =
            await Network().getComments(illust.id.toString());
        if (!commentsRes.error) {
          final comments = {
            'illustId': illust.id,
            'fetchedAt': DateTime.now().toIso8601String(),
            // First page only; used to detect deleted comments later.
            'hasMore': true,
            'comments': commentsRes.data
                .map((c) => {
                      'id': c.id,
                      'uid': c.uid,
                      'name': c.name,
                      'comment': c.comment,
                      'date': c.date.toIso8601String(),
                    })
                .toList(),
          };
          await File('${dir.path}/comments_${illust.id}.json')
              .writeAsString(jsonEncode(comments));
        }
      } catch (e) {
        Log.error("Download", "Failed to save comments snapshot: $e");
      }
    } catch (e) {
      Log.error("Download", "Failed to save artwork metadata: $e");
    }
  }

  void receiveBytes(int bytes) {
    _currentBytes += bytes;
  }

  int get maxConcurrentTasks => appdata.settings["maxParallels"];

  bool _paused = false;

  bool get paused => _paused;

  void pause() {
    _paused = true;
    for(var task in tasks) {
      task.pause();
    }
  }

  void run() {
    _loop ??= Timer.periodic(const Duration(seconds: 1), (timer) {
      if(_paused) return;
      _bytesPerSecond = _currentBytes;
      _currentBytes = 0;
      uiUpdateCallback?.call();
      for(int i=0; i<maxConcurrentTasks; i++) {
        var task = tasks.elementAtOrNull(i);
        if(task != null && task._stop && task.error == null) {
          task.start();
        }
      }
      if(tasks.isEmpty) {
        timer.cancel();
        _loop = null;
        _currentBytes = 0;
        _bytesPerSecond = 0;
      }
    });
  }

  void delete(DownloadedIllust illust) {
    _db.execute('''
      delete from download
      where illust_id = ?;
    ''', [illust.illustId]);
    var images = _db.select('''
      select * from images
      where illust_id = ?;
    ''', [illust.illustId]);
    String? dir;
    for(var image in images) {
      final path = image["path"] as String;
      dir ??= File(path).parent.path;
      File(path).deleteIgnoreError();
    }
    if (dir != null) {
      // Sidecar files written at download time.
      for (final name in [
        'info_${illust.illustId}.json',
        'comments_${illust.illustId}.json',
        'cover_${illust.illustId}.jpg',
      ]) {
        File('$dir/$name').deleteIgnoreError();
      }
    }
    _db.execute('''
      delete from images
      where illust_id = ?;
    ''', [illust.illustId]);
  }

  List<String> getImagePaths(int illustId) {
    var res = _db.select('''
      select * from images
      where illust_id = ?;
    ''', [illustId]);
    return res.map((e) => e["path"] as String).toList();
  }

  Future<void> batchDownload(Future<Res<List<Illust>>> request, int maxCount) async{
    List<Illust> all = [];
    String? nextUrl;
    int retryCount = 0;
    while(nextUrl != "end" && all.length < maxCount) {
      if(nextUrl != null) {
        request = Network().getIllustsWithNextUrl(nextUrl);
      }
      var res = await request;
      if(res.error) {
        retryCount++;
        if(retryCount > 3) {
          throw res.error;
        }
        await Future.delayed(Duration(seconds: 1 << retryCount));
        continue;
      }
      all.addAll(res.data);
      nextUrl = res.subData ?? "end";
    }
    int i = 0;
    for(var illust in all) {
      if(i > maxCount)  return;
      addDownloadingTask(illust);
      i++;
    }
  }

  Future<void> checkAndClearInvalidItems() async{
    var illusts = listAll();
    var shouldDelete = <DownloadedIllust>[];
    for(var item in illusts) {
      var paths = getImagePaths(item.illustId);
      var validPaths = <String>[];
      for(var path in paths) {
        if(await File(path).exists()) {
          validPaths.add(path);
        }
      }
      if(validPaths.isEmpty) {
        shouldDelete.add(item);
      }
    }
    for(var item in shouldDelete) {
      delete(item);
    }
  }

  void resume() {
    _paused = false;
  }
}