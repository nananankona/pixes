import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:pixes/appdata.dart';
import 'package:pixes/foundation/app.dart';
import 'package:pixes/foundation/log.dart';
import 'package:pixes/network/capcut.dart';

/// Direct Dart port of CapCutService (v2 session flow) from
/// kuwacom/CapCut-TTS (MIT). Needs a CapCut account (email/password).
class CapCutV2Service {
  final CapCutCookieJar jar = CapCutCookieJar();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    validateStatus: (_) => true,
  ));

  String _deviceId = '';
  String _verifyFp = '';
  String _tdid = '';
  Map<String, dynamic>? _session;
  List<CapCutSpeaker> _speakers = [];
  int _speakersLoadedAt = 0;
  Map<String, dynamic> _bundle = {};
  int _bundleDiscoveredAt = 0;
  Future<void>? _bundlePromise;
  Future<Map<String, dynamic>?>? _sessionPromise;

  static const _emailSalt = 'aDy0TUhtql92P7hScCs97YWMT-jub2q9';
  static const _bundleTtlMs = 30 * 60 * 1000;

  String get _email => appdata.settings['capcutEmail'] as String? ?? '';
  String get _password => appdata.settings['capcutPassword'] as String? ?? '';

  String get _bundlePath => '${App.dataPath}/capcut_bundle_config.json';

  // ---------- low level ----------

  Future<Response<dynamic>> _fetch(
    String url, {
    String method = 'GET',
    Map<String, String>? headers,
    dynamic body,
    Map<String, dynamic>? query,
  }) async {
    final h = <String, dynamic>{...?headers};
    final cookie = jar.cookieHeader(url);
    if (cookie.isNotEmpty) h['Cookie'] = cookie;
    late Response<dynamic> res;
    if (method == 'POST') {
      res = await _dio.post(url,
          data: body,
          queryParameters: query,
          options: Options(headers: h, contentType: 'application/json'));
    } else {
      res = await _dio.get(url,
          queryParameters: query, options: Options(headers: h));
    }
    jar.storeFromHeaders(
        res.headers.map.map((k, v) => MapEntry(k, v)), url);
    return res;
  }

  dynamic _unwrap(dynamic raw, String context) {
    Map<String, dynamic>? rec;
    if (raw is String) {
      try {
        final p = jsonDecode(raw);
        if (p is Map<String, dynamic>) rec = p;
      } catch (_) {}
    } else if (raw is Map<String, dynamic>) {
      rec = raw;
    }
    if (rec == null) throw CapCutApiException('$context: unexpected payload');
    final data = rec['data'];
    final Map<String, dynamic>? nested = data is Map<String, dynamic> ? data : null;
    int? errCode;
    final e1 = nested?['error_code'];
    final e2 = rec['error_code'];
    if (e1 is num) {
      errCode = e1.toInt();
    } else if (e2 is num) {
      errCode = e2.toInt();
    }
    String msg = context;
    for (final k in ['description', 'errmsg', 'message']) {
      final v = rec[k]?.toString() ?? nested?[k]?.toString() ?? '';
      if (v.isNotEmpty) {
        msg = '$context failed: $v';
        break;
      }
    }
    if (rec['ret'] != null && rec['ret'] != '0' && rec['ret'] != 0) {
      throw CapCutApiException(msg, errorCode: errCode);
    }
    if (rec['message'] != null && rec['message'] != 'success') {
      throw CapCutApiException(msg, errorCode: errCode);
    }
    if (data is Map || data is List) return data;
    return rec;
  }

  // ---------- helpers ----------

  static String _randomDigits(int n) {
    final r = Random.secure();
    return List.generate(n, (_) => r.nextInt(10).toString()).join();
  }

  static String _createDeviceId() =>
      '${DateTime.now().millisecondsSinceEpoch}${_randomDigits(12)}'
          .substring(0, 19);

  static String _createTrackingId() =>
      '${DateTime.now().millisecondsSinceEpoch}${_randomDigits(8)}'
          .substring(0, 17);

  static String _createVerifyFp() {
    String rand(int n) {
      const chars =
          'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
      final r = Random.secure();
      return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
    }

    final prefix = DateTime.now()
        .millisecondsSinceEpoch
        .toRadixString(36)
        .padLeft(8, '0')
        .substring(0, 8);
    return 'verify_${prefix}_${rand(8)}_${rand(4)}_${rand(4)}_${rand(4)}_${rand(12)}';
  }

  static String _xor5Hex(String value) {
    final bytes = utf8.encode(value);
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write((b ^ 5).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String _sensitiveForm(Map<String, String> values, List<String> keys) {
    final params = <String, String>{};
    var mix = 0;
    for (final e in values.entries) {
      if (keys.contains(e.key)) {
        mix = 1;
        params[e.key] = _xor5Hex(e.value);
      } else {
        params[e.key] = e.value;
      }
    }
    params['mix_mode'] = '$mix';
    params['fixed_mix_mode'] = '$mix';
    return params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
  }

  static String _emailHash(String email, [String? salt]) {
    final norm = email.trim().toLowerCase();
    return sha256.convert(utf8.encode('$norm${salt ?? _emailSalt}')).toString();
  }

  static double _toPlaybackRate(num speed) =>
      double.parse((speed.clamp(1, 20) / 10).toStringAsFixed(2));

  static int _toVolumeLevel(num volume) =>
      (volume.clamp(0, 20) * 10).toInt();

  // ---------- session ----------

  Map<String, dynamic>? get session => _session;

  Future<void> _restore() async {
    final cookies = appdata.settings['capcutCookies'];
    if (cookies is List) jar.hydrate(List<dynamic>.from(cookies));
    _deviceId = appdata.settings['capcutDeviceId'] as String? ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = _createDeviceId();
      appdata.settings['capcutDeviceId'] = _deviceId;
    }
    _verifyFp = appdata.settings['capcutVerifyFp'] as String? ?? '';
    if (_verifyFp.isEmpty) {
      _verifyFp = _createVerifyFp();
      appdata.settings['capcutVerifyFp'] = _verifyFp;
    }
    _tdid = appdata.settings['capcutTdid'] as String? ?? '';
    final s = appdata.settings['capcutSession'];
    if (s is Map) _session = Map<String, dynamic>.from(s);
    appdata.writeSettings();
  }

  Future<void> _persist() async {
    appdata.settings['capcutCookies'] = jar.serialize();
    appdata.settings['capcutDeviceId'] = _deviceId;
    appdata.settings['capcutVerifyFp'] = _verifyFp;
    appdata.settings['capcutTdid'] = _tdid;
    appdata.settings['capcutSession'] = _session;
    appdata.writeSettings();
  }

  Future<Map<String, dynamic>> ensureAuthenticated({bool force = false}) async {
    await _restore();
    if (!force && _session != null) {
      final at = _session!['verifiedAt'] as int? ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - at <
          kCapCutSessionValidateMs) {
        return _session!;
      }
    }
    if (_sessionPromise != null) return (await _sessionPromise)!;
    final fut = _login().whenComplete(() => _sessionPromise = null);
    _sessionPromise = fut;
    return fut;
  }

  Map<String, String> _passportHeaders(String host) => {
        'Accept': 'application/json, text/javascript',
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': kCapCutUserAgent,
        'appid': kCapCutAppId,
        'did': _deviceId,
        'Origin': kCapCutWebUrl,
        'Referer': '$kCapCutWebUrl/$kCapCutPageLocale/login',
        'store-country-code': kCapCutStoreCountryCode,
        'store-country-code-src': 'uid',
        'x-tt-passport-csrf-token':
            jar.get('passport_csrf_token', host) ?? '',
      };

  Map<String, dynamic> _passportParams() => {
        'aid': kCapCutAppId,
        'account_sdk_source': 'web',
        'sdk_version': kCapCutLoginSdkVersion,
        'language': kCapCutLocale,
        'verifyFp': _verifyFp,
      };

  void _seedCsrf() {
    final r = Random.secure();
    final csrf = List.generate(16, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    for (final d in [
      Uri.parse(kCapCutWebUrl).host,
      Uri.parse(kCapCutLoginHost).host,
      Uri.parse(kCapCutFallbackLoginHost).host
    ]) {
      jar.set('passport_csrf_token', csrf, d);
      jar.set('passport_csrf_token_default', csrf, d);
    }
  }

  Future<Map<String, dynamic>> _login() async {
    Log.info("CapCutV2", "login flow started");
    _verifyFp = _createVerifyFp();
    jar.clear();
    _seedCsrf();
    // Prime cookies via login page.
    try {
      await _fetch('$kCapCutWebUrl/$kCapCutPageLocale/login', headers: {
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'User-Agent': kCapCutUserAgent,
      });
    } catch (e) {
      Log.info("CapCutV2", "login page bootstrap failed: $e");
    }
    final hosts = <String>[
      kCapCutLoginHost,
      kCapCutFallbackLoginHost,
    ];
    Object? lastError;
    for (final host in hosts) {
      try {
        // Preflight.
        try {
          await _fetch('$host/passport/web/user/check_email_registered/',
              method: 'POST',
              query: _passportParams(),
              headers: _passportHeaders(host),
              body: _sensitiveForm({'email': _email}, ['email']));
        } catch (e) {
          Log.info("CapCutV2", "preflight failed: $e");
        }
        final params = _passportParams();
        final headers = _passportHeaders(host);
        final body =
            _sensitiveForm({'email': _email, 'password': _password}, [
          'email',
          'password'
        ]);
        dynamic loginData;
        try {
          final res = await _fetch('$host/passport/web/email/login/',
              method: 'POST',
              query: params,
              headers: headers,
              body: body);
          loginData = _unwrap(res.data, 'CapCut email login');
        } on CapCutApiException catch (e) {
          if (e.statusCode != 404 && e.statusCode != 405) rethrow;
          Log.info("CapCutV2", "email/login fallback to user/login");
          final res = await _fetch('$host/passport/web/user/login/',
              method: 'POST', query: params, headers: headers, body: body);
          loginData = _unwrap(res.data, 'CapCut user login');
        }
        final accountRes = await _fetch(
            '$host/passport/web/account/info/',
            method: 'POST',
            query: _passportParams(),
            headers: _passportHeaders(host),
            body: '');
        final account = _unwrap(accountRes.data, 'CapCut account info')
            as Map<String, dynamic>;
        await resolveEditorBundleConfig(forceRefresh: true);
        final workspace = await _primaryWorkspace();
        final userId = (account['user_id'] ??
                loginData['user_id_str'] ??
                loginData['user_id'])
            ?.toString();
        final screenName = (account['screen_name'] ??
                loginData['screen_name'])
            ?.toString();
        final wsId = workspace['workspace_id']?.toString();
        if (userId == null || userId.isEmpty || wsId == null || wsId.isEmpty) {
          throw CapCutApiException('CapCut login exposed no user/workspace');
        }
        _session = {
          'userId': userId,
          'screenName': screenName ?? '',
          'workspaceId': wsId,
          'loginHost': host,
          'verifiedAt': DateTime.now().millisecondsSinceEpoch,
        };
        await _persist();
        return _session!;
      } catch (e) {
        lastError = e;
        Log.info("CapCutV2", "login via $host failed: $e");
        if (e is CapCutApiException && e.errorCode != null) break;
      }
    }
    _session = null;
    await _persist();
    throw lastError is Exception
        ? lastError
        : Exception('CapCut login failed');
  }

  // ---------- bundle config ----------

  Map<String, dynamic> _bundleConfig() {
    if (_bundle.isEmpty) {
      return {
        'sourceUrls': <String>[],
        'editorAppVersion': kCapCutEditorAppVersion,
        'webAppVersion': kCapCutWebAppVersion,
        'versionName': '11.0.0',
        'versionCode': '11.0.0',
        'sdkVersion': '19.3.0',
        'effectSdkVersion': '19.3.0',
        'voicePanelSource': kCapCutVoicePanelSource,
        'voiceCategoryIds': _kVoiceCategoryIds,
        'voiceListPath': '/artist/v1/effect/get_resources_by_category_id',
        'workspacePath': '/cc/v1/workspace/get_user_workspaces',
        'multiPlatformPath': '/storyboard/v1/tts/multi_platform',
        'createTaskPath': '/lv/v2/intelligence/create',
        'queryTaskPath': '/lv/v2/intelligence/query',
        'signRecipe': {'pathTailLength': 7},
        'platformId': kCapCutPlatformId,
        'signVersion': kCapCutSignVersion,
      };
    }
    return _bundle;
  }

  static const List<int> _kVoiceCategoryIds = [
    30316, 2037709420, 2037708790, 21699, 36155, 33084, 2037707014, 33082,
    21782, 33083, 33085,
  ];

  Future<void> resolveEditorBundleConfig({bool forceRefresh = false}) async {
    if (_bundlePromise != null) {
      await _bundlePromise;
      return;
    }
    final fut = _doResolveBundle(forceRefresh).whenComplete(() {
      _bundlePromise = null;
    });
    _bundlePromise = fut;
    await fut;
  }

  Future<void> _doResolveBundle(bool forceRefresh) async {
    if (!forceRefresh && _bundle.isNotEmpty) {
      if (DateTime.now().millisecondsSinceEpoch - _bundleDiscoveredAt <
              30 * 60 * 1000 &&
          _usableBundle(_bundle)) {
        return;
      }
    }
    if (_bundle.isEmpty) {
      try {
        final raw = await File(_bundlePath).readAsString();
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        final editor = parsed['editor'];
        if (editor is Map<String, dynamic>) {
          _bundle = _normalizeBundle(editor);
          _bundleDiscoveredAt =
              (parsed['discoveredAt'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
      if (!forceRefresh &&
          _bundle.isNotEmpty &&
          DateTime.now().millisecondsSinceEpoch - _bundleDiscoveredAt <
              30 * 60 * 1000 &&
          _usableBundle(_bundle)) {
        return;
      }
    }
    var merged = Map<String, dynamic>.from(_bundleConfig());
    const pages = [
      '$kCapCutWebUrl/my-edit?from_page=landing_page&start_tab=video',
      '$kCapCutWebUrl/editor?from_page=landing_page&start_tab=video',
      '$kCapCutWebUrl/tools/text-to-speech',
    ];
    try {
      for (final pageUrl in pages) {
        final res = await _fetch(pageUrl, headers: {
          'User-Agent': kCapCutUserAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        });
        if (res.statusCode != 200) continue;
        final html = res.data.toString();
        final scriptUrls = RegExp(r'''<script[^>]+src="([^"]+)"''')
            .allMatches(html)
            .map((m) => m.group(1)!)
            .map((u) => u.startsWith('http')
                ? u
                : '$kCapCutWebUrl${u.startsWith('/') ? '' : '/'}$u')
            .where((u) => RegExp(
                    r'video_online\/static\/js\/(editor|services|vendors)|smart_tools_online\/static\/js\/tts')
                .hasMatch(u))
            .toList();
        for (final scriptUrl in scriptUrls) {
          final sres = await _fetch(scriptUrl,
              headers: {'User-Agent': kCapCutUserAgent, 'Accept': '*/*'});
          if (sres.statusCode != 200) continue;
          merged = _mergeBundle(merged,
              _extractBundle(sres.data.toString(), scriptUrl));
        }
        if (_usableBundle(merged)) break;
      }
      _bundle = merged;
      _bundleDiscoveredAt = DateTime.now().millisecondsSinceEpoch;
      try {
        await File(_bundlePath).writeAsString(jsonEncode({
          'discoveredAt': _bundleDiscoveredAt,
          'editor': _bundle,
        }));
      } catch (_) {}
    } catch (e) {
      Log.info("CapCutV2", "bundle extraction failed: $e");
      if (_bundle.isEmpty) _bundle = merged;
    }
  }

  bool _usableBundle(Map<String, dynamic> c) {
    final v = c['editorAppVersion']?.toString() ?? '';
    final tail = (c['signRecipe'] is Map)
        ? ((c['signRecipe'] as Map)['pathTailLength'] as num?)?.toInt() ?? 0
        : 0;
    return RegExp(r'^\d+\.\d+\.\d+').hasMatch(v) && tail >= 7;
  }

  Map<String, dynamic> _normalizeBundle(Map<String, dynamic> m) =>
      Map<String, dynamic>.from(m);

  String? _firstGroup(String text, RegExp re) {
    final m = re.firstMatch(text);
    return m?.group(1);
  }

  Map<String, dynamic> _extractBundle(String text, String url) {
    Map<String, dynamic>? recipe;
    if (text.contains('9e2c|') && text.contains('11ac')) {
      final tail =
          int.tryParse(_firstGroup(text, RegExp(r'slice\(-(\d+)\)')) ?? '') ??
              7;
      recipe = {
        'prefix': '9e2c',
        'suffix': '11ac',
        'pathTailLength': tail,
        'platformId': _firstGroup(text, RegExp(r'''pf:"(\d+)"''')) ??
            _firstGroup(text, RegExp(r'''pf='(\d+)' ''')) ??
            _firstHeaders(text),
        'signVersion':
            _firstGroup(text, RegExp(r'''["']sign-ver["']:(\d+)''')),
      };
    }
    String? prefer(String? a, String? b) {
      if (a == null || a.isEmpty) return b;
      if (b == null || b.isEmpty) return a;
      return b.length >= a.length ? b : a;
    }

    final voiceCats = RegExp(r'right_category\\?":\\?"(\d{4,})')
        .allMatches(text)
        .map((m) => int.tryParse(m.group(1)!))
        .whereType<int>()
        .toSet()
        .toList();
    return {
      'sourceUrls': [url],
      'editorAppVersion': _firstGroup(text, RegExp(r'appvr:"(\d+\.\d+\.\d+)"')),
      'webAppVersion': _firstGroup(
          text, RegExp(r'APP_NAME:"cc_web"[^}]*?VERSION:"(\d+\.\d+\.\d+)"')),
      'versionName': _firstGroup(
          text, RegExp(r'version_code:"(\d+\.\d+\.\d+)",sdk_version:null!=')),
      'versionCode': _firstGroup(
          text, RegExp(r'version_code:"(\d+\.\d+\.\d+)",sdk_version:null!=')),
      'signRecipe': recipe,
      'multiPlatformPath': _firstGroup(
          text, RegExp(r'''["'](\/storyboard\/v1\/tts\/multi_platform)["']''')),
      'createTaskPath': _firstGroup(
              text, RegExp(r'''["'](\/lv\/v2\/intelligence\/create)["']''')) ??
          _firstGroup(text, RegExp(r'CREATE_VC_TASK:"([^"]+)"')),
      'queryTaskPath': _firstGroup(
              text, RegExp(r'''["'](\/lv\/v2\/intelligence\/query)["']''')) ??
          _firstGroup(text, RegExp(r'QUERY_VC_TASK:"([^"]+)"')),
      'workspacePath': _firstGroup(text,
          RegExp(r'''["'](\/cc\/v1\/workspace\/get_user_workspaces)["']''')),
      'voiceListPath': _firstGroup(text,
              RegExp(r'GET_HEYCAN_RESOURCES_BY_CATEGORY_ID:\{[^}]*url:"([^"]+)"')) ??
          _firstGroup(text, RegExp(r'GET_CATEGORY_RESOURCE:"([^"]+)"')),
      'voicePanelSource':
          text.contains('heycan') ? 'heycan' : null,
      'voiceCategoryIds': voiceCats,
    }..removeWhere((_, v) => v == null);
  }

  String? _firstHeaders(String text) {
    final m = RegExp(r'''u\.pf="(\d+)"''').firstMatch(text);
    return m?.group(1);
  }

  Map<String, dynamic> _mergeBundle(
      Map<String, dynamic> cur, Map<String, dynamic> next) {
    final out = Map<String, dynamic>.from(cur);
    for (final e in next.entries) {
      final v = e.value;
      if (v == null) continue;
      if (v is String && v.isEmpty) continue;
      if (v is List && v.isEmpty) continue;
      if (e.key == 'sourceUrls' && v is List) {
        out['sourceUrls'] = {...(cur['sourceUrls'] as List? ?? []), ...v}
            .map((e) => e.toString())
            .toList();
        continue;
      }
      if (e.key == 'voiceCategoryIds' && v is List) {
        out['voiceCategoryIds'] = {
          ...(cur['voiceCategoryIds'] as List? ?? []),
          ...v
        }.toList();
        continue;
      }
      if (e.key == 'signRecipe' && v is Map) {
        out['signRecipe'] = {...(cur['signRecipe'] as Map? ?? {}), ...v};
        continue;
      }
      if (v is String && cur[e.key] is String) {
        out[e.key] = v.length >= (cur[e.key] as String).length ? v : cur[e.key];
        continue;
      }
      out[e.key] = v;
    }
    return out;
  }

  // ---------- signed edit api ----------

  Future<dynamic> _signedJson({
    required String path,
    required String appVersion,
    required Map<String, dynamic> body,
    Map<String, dynamic>? searchParams,
    Map<String, String>? extraHeaders,
    String? tdid,
    required String context,
  }) async {
    await resolveEditorBundleConfig();
    final cfg = _bundleConfig();
    final target = Uri.parse(kCapCutEditApiUrl + path);
    final qp = <String, String>{};
    searchParams?.forEach((k, v) => qp[k] = v.toString());
    final fullUrl = target.replace(
        queryParameters: {...target.queryParameters, ...qp});
    final recipe = cfg['signRecipe'] is Map
        ? Map<String, dynamic>.from(cfg['signRecipe'] as Map)
        : <String, dynamic>{};
    final sig = createCapCutSignature(
      fullUrl.toString(),
      (cfg['platformId'] ?? kCapCutPlatformId).toString(),
      appVersion,
      tdid ?? '',
      pathTailLength: ((recipe['pathTailLength'] as num?)?.toInt() ?? 7)
          .clamp(7, 99),
    );
    final headers = {
      'Accept': 'application/json, text/plain, */*',
      'Content-Type': 'application/json',
      'Origin': kCapCutWebUrl,
      'Referer': '$kCapCutWebUrl/',
      'User-Agent': kCapCutUserAgent,
      'appid': kCapCutAppId,
      'appvr': appVersion,
      'device-time': sig['deviceTime']!,
      'did': _deviceId,
      'pf': (cfg['platformId'] ?? kCapCutPlatformId).toString(),
      'sign': sig['sign']!,
      'sign-ver': (cfg['signVersion'] ?? kCapCutSignVersion).toString(),
      'store-country-code': kCapCutStoreCountryCode,
      'store-country-code-src': 'uid',
      'tdid': tdid ?? '',
      ...?extraHeaders,
    };
    final res = await _fetch(fullUrl.toString(),
        method: 'POST', headers: headers, body: jsonEncode(body));
    return _unwrap(res.data, context);
  }

  // ---------- workspace / speakers ----------

  Future<Map<String, dynamic>> _primaryWorkspace() async {
    final cfg = _bundleConfig();
    final data = await _signedJson(
      path: (cfg['workspacePath'] as String?) ??
          '/cc/v1/workspace/get_user_workspaces',
      appVersion: (cfg['editorAppVersion'] as String?) ?? kCapCutEditorAppVersion,
      extraHeaders: {'lan': kCapCutLocale, 'loc': kCapCutRegion},
      body: {
        'cursor': '0',
        'count': 100,
        'need_convert_workspace': true,
      },
      context: 'CapCut workspace list',
    ) as Map<String, dynamic>;
    final infos = (data['workspace_infos'] as List?) ?? [];
    Map<String, dynamic>? pick;
    for (final w in infos) {
      if (w is Map<String, dynamic>) {
        pick ??= w;
        if (w['role'] == 'owner') {
          pick = w;
          break;
        }
      }
    }
    if (pick == null || pick['workspace_id'] == null) {
      throw CapCutApiException('CapCut workspace list was empty');
    }
    return pick;
  }

  Future<List<CapCutSpeaker>> loadSpeakers() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_speakers.isNotEmpty && now - _speakersLoadedAt < kCapCutVoiceCacheMs) {
      return _speakers;
    }
    try {
      final list = await _speakersFromPanel();
      if (list.isNotEmpty) {
        _speakers = list;
        _speakersLoadedAt = now;
        return _speakers;
      }
      final cat = await _speakersFromCategories();
      _speakers = cat.isNotEmpty ? cat : capCutFallbackSpeakers;
    } catch (e) {
      Log.info("CapCutV2", "speaker list failed, using fallback: $e");
      _speakers = capCutFallbackSpeakers;
    }
    _speakersLoadedAt = now;
    return _speakers;
  }

  Map<String, String> _catalogParams() {
    final cfg = _bundleConfig();
    return {
      'aid': kCapCutAppId,
      'version_name': (cfg['versionName'] ?? '11.0.0').toString(),
      'version_code': (cfg['versionCode'] ?? '11.0.0').toString(),
      'sdk_version': (cfg['sdkVersion'] ?? '19.3.0').toString(),
      'effect_sdk_version':
          (cfg['effectSdkVersion'] ?? '19.3.0').toString(),
      'device_platform': 'web',
      'region': kCapCutRegion,
      'language': kCapCutLocale,
      'device_type': 'web',
      'channel': 'online',
    };
  }

  Map<String, String> _catalogHeaders() => {
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/json',
        'Origin': kCapCutWebUrl,
        'Referer': '$kCapCutWebUrl/',
        'User-Agent': kCapCutUserAgent,
        'appid': kCapCutAppId,
        'did': _deviceId,
        'store-country-code': kCapCutStoreCountryCode,
        'store-country-code-src': 'uid',
      };

  Future<List<CapCutSpeaker>> _speakersFromPanel() async {
    final cfg = _bundleConfig();
    final res = await _fetch('$kCapCutEditApiUrl/artist/v1/panel/get_panel_info',
        method: 'POST',
        query: _catalogParams(),
        headers: _catalogHeaders(),
        body: jsonEncode({
          'panel': kCapCutVoicePanel,
          'panel_source': cfg['voicePanelSource'] ?? kCapCutVoicePanelSource,
          'get_all_resource': true,
        }));
    final data = _unwrap(res.data, 'CapCut voice panel');
    final cats = (data as Map<String, dynamic>)['category_resources'];
    final items = <dynamic>[];
    if (cats is Map) {
      for (final r in cats.values) {
        final list = (r as Map?)?['effect_item_list'];
        if (list is List) items.addAll(list);
      }
    }
    return _collectSpeakers(items);
  }

  Future<List<CapCutSpeaker>> _speakersFromCategories() async {
    final cfg = _bundleConfig();
    final ids = (cfg['voiceCategoryIds'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        _bundleConfig()['voiceCategoryIds'] as List<int>;
    final path = (cfg['voiceListPath'] as String?) ??
        '/artist/v1/effect/get_resources_by_category_id';
    final all = <dynamic>[];
    for (final id in ids) {
      try {
        final res = await _fetch('$kCapCutEditApiUrl$path',
            method: 'POST',
            query: _catalogParams(),
            headers: _catalogHeaders(),
            body: jsonEncode({
              'panel': kCapCutVoicePanel,
              'category_id': id,
              'category_key': '$id',
              'panel_source':
                  cfg['voicePanelSource'] ?? kCapCutVoicePanelSource,
              'pack_optional': {
                'need_tag': true,
                'need_thumb': true,
                'thumb_opt': {'is_support_webp': 1},
                'image_pack_param': {
                  'icon_limit': {
                    'static_format': 'webp',
                    'dynamic_format': 'awebp',
                    'width': 100,
                    'height': 100,
                  }
                }
              },
              'offset': 0,
              'count': 200,
            }));
        final data = _unwrap(res.data, 'CapCut voice catalog $id');
        final list = (data as Map<String, dynamic>)['effect_item_list'];
        if (list is List) all.addAll(list);
      } catch (e) {
        Log.info("CapCutV2", "voice category $id failed: $e");
      }
    }
    return _collectSpeakers(all);
  }

  List<CapCutSpeaker> _collectSpeakers(List<dynamic> items) {
    final seen = <String>{};
    final out = <CapCutSpeaker>[];
    for (final item in items) {
      final s = _parseSpeaker(item);
      if (s == null || seen.contains(s.resourceId)) continue;
      seen.add(s.resourceId);
      out.add(s);
    }
    return out;
  }

  CapCutSpeaker? _parseSpeaker(dynamic item) {
    if (item is! Map) return null;
    Map<String, dynamic>? rec(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      if (v is String && v.isNotEmpty) {
        try {
          final p = jsonDecode(v);
          if (p is Map<String, dynamic>) return p;
          if (p is Map) return Map<String, dynamic>.from(p);
        } catch (_) {}
      }
      return null;
    }

    String? str(dynamic v) {
      if (v == null) return null;
      if (v is String) return v;
      if (v is num) return v.toString();
      return null;
    }

    final common = rec(item['common_attr']);
    if (common == null) return null;
    final effectType = common['effect_type'];
    if (effectType is num && effectType != 11) return null;
    final extra = rec(common['extra']) ?? rec(item['extra']);
    final bizExtra = rec(common['biz_extra']) ?? rec(item['biz_extra']);
    Map<String, dynamic>? toneType(dynamic m) => rec(m?['tonetype']);
    final tone = toneType(extra) ?? toneType(bizExtra);
    final timbre = rec(item['timbre']);
    final voiceAlias =
        str(extra?['voice_alias_name']) ?? str(bizExtra?['voice_alias_name']);
    final title = str(common['title']);
    final speaker = str(tone?['voice_type']) ??
        str(tone?['tts_voice']) ??
        str(extra?['ttp_voice_type']) ??
        str(bizExtra?['ttp_voice_type']) ??
        str(timbre?['voice_type']) ??
        str(timbre?['voice']);
    final tonePlatform = str(tone?['platform']) ??
        str(extra?['tone_platform']) ??
        str(bizExtra?['tone_platform']);
    final description = str(common['description']) ??
        voiceAlias ??
        speaker ??
        'CapCut voice preset';
    final effectId =
        str(common['effect_id']) ?? str(common['id']);
    final resourceId = str(common['third_resource_id_str']) ??
        str(common['third_resource_id']) ??
        effectId;
    if (title == null || effectId == null || resourceId == null) return null;
    var language = 'unknown';
    if (speaker != null) {
      final m = RegExp(r'^(?:ICL_)?([a-z]{2})[_-]', caseSensitive: false)
          .firstMatch(speaker);
      if (m != null) language = m.group(1)!.toLowerCase();
    }
    return CapCutSpeaker(
      title: title,
      description: description,
      speaker: speaker,
      effectId: effectId,
      resourceId: resourceId,
      ttsPlatform: tonePlatform == '11labs' ? 2 : null,
      isVip: extra?['is_vip'] == true,
      language: language,
    );
  }

  // ---------- synthesize ----------

  Future<Uint8List> synthesize(
    String text, {
    String? speaker,
    dynamic type = 0,
    double speed = 1.0,
    double volume = 1.0,
  }) async {
    final chunks = splitCapCutText(text);
    if (chunks.length == 1) {
      return _synthesizeOne(chunks.first,
          speaker: speaker, type: type, speed: speed, volume: volume);
    }
    // Stream sequentially like the original streams chunked results.
    final out = <int>[];
    for (final c in chunks) {
      out.addAll(await _synthesizeOne(c,
          speaker: speaker, type: type, speed: speed, volume: volume));
    }
    return Uint8List.fromList(out);
  }

  Future<Uint8List> _synthesizeOne(
    String text, {
    String? speaker,
    dynamic type = 0,
    double speed = 1.0,
    double volume = 1.0,
  }) async {
    try {
      return await _synthesizeOnce(text,
          speaker: speaker, type: type, speed: speed, volume: volume);
    } on CapCutApiException catch (e) {
      if (!e.isSessionExpired) rethrow;
      Log.info("CapCutV2", "session expired, re-authenticating once");
      await ensureAuthenticated(force: true);
      return _synthesizeOnce(text,
          speaker: speaker, type: type, speed: speed, volume: volume);
    }
  }

  Future<Uint8List> _synthesizeOnce(
    String text, {
    String? speaker,
    dynamic type = 0,
    double speed = 1.0,
    double volume = 1.0,
  }) async {
    final speakers = await loadSpeakers();
    final resolved = resolveCapCutSpeaker(type, speakers, speaker);
    await ensureAuthenticated();
    if (capCutSupportsMultiPlatform(resolved.speaker)) {
      try {
        return await _viaMultiPlatform(resolved, text, speed, volume);
      } catch (e) {
        Log.info("CapCutV2",
            "multi_platform failed, falling back to editor flow: $e");
      }
    }
    final session = await ensureAuthenticated();
    final taskId = await _createTask(
        session['workspaceId'].toString(), resolved, text, speed, volume);
    final detail = await _waitTask(
        session['workspaceId'].toString(), taskId);
    final url = detail['url']?.toString() ??
        ((detail['transcode_audio_info'] as List?)?.isNotEmpty == true
            ? ((detail['transcode_audio_info'] as List).first
                    as Map<String, dynamic>)['url']
                ?.toString()
            : null);
    if (url == null || url.isEmpty) {
      throw CapCutApiException('CapCut TTS task completed without audio URL');
    }
    return _downloadAudio(url);
  }

  double _rate(double speed) =>
      double.parse((speed.clamp(0.5, 2.0) * 10).clamp(1, 20).toString()) / 10;

  int _vol(double volume) => (volume.clamp(0, 2.0) * 10).toInt();

  Future<Uint8List> _viaMultiPlatform(
    CapCutSpeaker sp,
    String text,
    double speed,
    double volume,
  ) async {
    await resolveEditorBundleConfig();
    final cfg = _bundleConfig();
    final data = await _signedJson(
      path: (cfg['multiPlatformPath'] as String?) ??
          '/storyboard/v1/tts/multi_platform',
      appVersion: (cfg['editorAppVersion'] as String?) ?? kCapCutEditorAppVersion,
      tdid: _tdid,
      body: {
        'texts': [text],
        'tts_conf': {
          'speaker': sp.speaker,
          'rate': _rate(speed),
          'volume': _vol(volume),
          'name': sp.title,
          'platform': 'sami',
          'effect_id': sp.effectId,
          'resource_id': sp.resourceId,
          'is_clone': false,
        },
        'need_url': true,
      },
      context: 'CapCut multi_platform TTS',
    ) as Map<String, dynamic>;
    final url =
        (((data['tts_materials'] as List?)?.isNotEmpty == true
                ? (data['tts_materials'] as List).first
                : null) as Map<String, dynamic>?)?['meta_data']
            ?['url']
            ?.toString();
    if (url == null || url.isEmpty) {
      throw CapCutApiException('CapCut multi_platform returned no audio URL');
    }
    return _downloadAudio(url);
  }

  Future<String> _createTask(
    String workspaceId,
    CapCutSpeaker sp,
    String text,
    double speed,
    double volume,
  ) async {
    await resolveEditorBundleConfig();
    final cfg = _bundleConfig();
    final data = await _signedJson(
      path: (cfg['createTaskPath'] as String?) ?? '/lv/v2/intelligence/create',
      appVersion: (cfg['editorAppVersion'] as String?) ?? kCapCutEditorAppVersion,
      searchParams: {
        'aid': kCapCutAppId,
        'device_platform': 'web',
        'region': kCapCutRegion,
        'web_id': _deviceId,
      },
      extraHeaders: {'lan': kCapCutLocale},
      body: {
        'workspace_id': workspaceId,
        'smart_tool_type': kCapCutTtsSmartToolType,
        'scene': kCapCutTtsScene,
        'params': jsonEncode({
          'text': text,
          'platform': sp.ttsPlatform ?? kCapCutTtsPlatform,
        }),
        'req_json': jsonEncode({
          'speaker': sp.speaker ?? sp.resourceId,
          'audio_config': {},
          'disable_caption': true,
          'commerce': {
            'resource_type': 'material_artist',
            'benefit_type': 'resource_export',
            'resource_id': sp.resourceId,
          },
        }),
      },
      context: 'CapCut TTS create',
    ) as Map<String, dynamic>;
    final taskId = data['task_id']?.toString();
    if (taskId == null || taskId.isEmpty) {
      throw CapCutApiException('CapCut TTS create did not return task_id');
    }
    return taskId;
  }

  Future<Map<String, dynamic>> _waitTask(
      String workspaceId, String taskId) async {
    await resolveEditorBundleConfig();
    final cfg = _bundleConfig();
    for (var i = 0; i < kCapCutTtsMaxPollAttempts; i++) {
      final data = await _signedJson(
        path: (cfg['queryTaskPath'] as String?) ?? '/lv/v2/intelligence/query',
        appVersion:
            (cfg['editorAppVersion'] as String?) ?? kCapCutEditorAppVersion,
        searchParams: {
          'aid': kCapCutAppId,
          'device_platform': 'web',
          'region': kCapCutRegion,
          'web_id': _deviceId,
        },
        extraHeaders: {'lan': kCapCutLocale},
        body: {
          'task_id': taskId,
          'workspace_id': workspaceId,
          'smart_tool_type': kCapCutTtsSmartToolType,
        },
        context: 'CapCut TTS query',
      ) as Map<String, dynamic>;
      final status = int.tryParse('${data['status'] ?? 0}') ?? 0;
      if (status == 2) {
        final detail = (data['task_detail'] as List?)?.isNotEmpty == true
            ? (data['task_detail'] as List).first
            : null;
        if (detail is Map<String, dynamic>) return detail;
        throw CapCutApiException('CapCut TTS query returned no detail');
      }
      if (status != 1) {
        throw CapCutApiException('CapCut TTS query failed: status $status');
      }
      await Future.delayed(
          const Duration(milliseconds: kCapCutTtsPollIntervalMs));
    }
    throw CapCutApiException('CapCut TTS query timed out');
  }

  Future<Uint8List> _downloadAudio(String url) async {
    final res = await _fetch(url, headers: {
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': kCapCutUserAgent,
    });
    if (res.statusCode != 200) {
      throw CapCutApiException(
          'CapCut audio download failed: ${res.statusCode}');
    }
    final data = res.data;
    if (data is List<int>) return Uint8List.fromList(data);
    if (data is String) return Uint8List.fromList(utf8.encode(data));
    throw CapCutApiException('CapCut audio download returned no body');
  }
}
