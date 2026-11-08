import 'package:pixes/appdata.dart';
import 'package:pixes/network/models.dart';

List<Illust> checkIllusts(List<Illust> illusts) {
  final safe = appdata.settings["safeOnly"] == true;
  illusts.removeWhere((illust) {
    if (illust.isBlocked) {
      return true;
    }
    if (safe && (illust.isR18 || illust.isR18G || illust.isAi)) {
      return true;
    }
    if (appdata.settings["blockTags"] == null) {
      return false;
    }
    if (appdata.settings["blockTags"].contains("user:${illust.author.id}")) {
      return true;
    }
    for (var tag in illust.tags) {
      if ((appdata.settings["blockTags"] as List).contains(tag.name)) {
        return true;
      }
    }
    return false;
  });
  return illusts;
}
