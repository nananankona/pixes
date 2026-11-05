import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:pixes/foundation/app.dart';
import 'package:pixes/foundation/log.dart';
import 'package:pixes/pages/illust_page.dart';
import 'package:pixes/pages/novel_page.dart';
import 'package:pixes/pages/search_page.dart';
import 'package:pixes/pages/user_info_page.dart';
import 'package:pixes/utils/ext.dart';
import 'package:pixes/utils/translation.dart';
import 'package:win32_registry/win32_registry.dart';

Future<void> _register(String scheme) async {
  String appPath = Platform.resolvedExecutable;

  String protocolRegKey = 'Software\\Classes\\$scheme';
  RegistryValue protocolRegValue = const RegistryValue.string(
    'URL Protocol',
    '',
  );
  String protocolCmdRegKey = 'shell\\open\\command';
  RegistryValue protocolCmdRegValue = RegistryValue.string(
    '',
    '"$appPath" "%1"',
  );

  final regKey = Registry.currentUser.createKey(protocolRegKey);
  regKey.createValue(protocolRegValue);
  regKey.createKey(protocolCmdRegKey).createValue(protocolCmdRegValue);
}

void _registerPixiv() async {
  try {
    await _register("pixiv");
  } catch (e) {
    // 注册失败会导致登录不可用
    while (App.mainNavigatorKey == null) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    Future.delayed(const Duration(seconds: 1), () async {
      showDialog(
          context: App.rootNavigatorKey.currentContext!,
          builder: (context) => ContentDialog(
                title: Text("Error".tl),
                content: Text("${"Failed to register URL scheme.".tl}\n$e"),
                actions: [
                  FilledButton(
                      child: Text("Retry".tl),
                      onPressed: () {
                        context.pop();
                        _registerPixiv();
                      })
                ],
              ));
    });
  }
}

bool Function(Uri uri)? onLink;

bool _firstLink = true;

void handleLinks() async {
  if (App.isWindows) {
    _registerPixiv();
  }
  final appLinks = AppLinks();

  void dispatch(Uri uri) {
    Log.info("App Link", uri.toString());
    if (onLink?.call(uri) == true) {
      return;
    }
    // Login flow sets `onLink` to capture pixiv://?code=...
    // If the app was cold-started via protocol, `onLink` may not be set yet.
    // Retry shortly so the login page can still capture the code.
    if (uri.scheme == "pixiv" && uri.queryParameters.containsKey("code")) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (onLink?.call(uri) == true) return;
      });
      return;
    }
    handleLink(uri);
  }

  // Cold start (app launched via protocol / #31 Windows/Linux).
  try {
    final initial = await appLinks.getInitialLink();
    if (initial != null) {
      // Delay until navigator keys are ready (main() calls handleLinks early).
      Future.delayed(const Duration(milliseconds: 500), () => dispatch(initial));
    }
  } catch (e) {
    Log.error("App Link", "getInitialLink failed: $e");
  }

  appLinks.uriLinkStream.listen((uri) async {
    if (_firstLink) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    _firstLink = false;
    dispatch(uri);
  });
}

bool handleLink(Uri uri) {
  if (uri.scheme == "pixiv") {
    var path = uri.toString().split("/").sublist(2);
    if (path.isEmpty) {
      return false;
    }
    switch (path[0]) {
      case "users":
        if (path.length == 2) {
          App.mainNavigatorKey?.currentContext?.to(() => UserInfoPage(path[1]));
          return true;
        }
      case "novels":
        if (path.length == 2) {
          App.mainNavigatorKey?.currentContext
              ?.to(() => NovelPageWithId(path[1]));
          return true;
        }
      case "illusts":
        if (path.length == 2) {
          App.mainNavigatorKey?.currentContext
              ?.to(() => IllustPageWithId(path[1]));
          return true;
        }
    }
    return false;
  } else if (uri.scheme == "https") {
    var path = uri.toString().split("/").sublist(3);
    switch (path[0]) {
      case "users":
        if (path.length >= 2) {
          App.mainNavigatorKey?.currentContext?.to(() => UserInfoPage(path[1]));
          return true;
        }
      case "novel":
        if (path.length == 2) {
          App.mainNavigatorKey?.currentContext
              ?.to(() => NovelPageWithId(path[1].nums));
          return true;
        }
      case "artworks":
        if (path.length == 2) {
          App.mainNavigatorKey?.currentContext
              ?.to(() => IllustPageWithId(path[1]));
          return true;
        }
      case "tags":
        if (path.length == 2) {
          App.mainNavigatorKey?.currentContext
              ?.to(() => SearchResultPage(path[1]));
          return true;
        }
    }
  }
  return false;
}
