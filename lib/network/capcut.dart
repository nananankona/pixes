import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Shared bits ported from kuwacom/CapCut-TTS (MIT).
/// v1 (legacy token + WebSocket) and v2 (session + bundle) flows.

const String kCapCutWebUrl = 'https://www.capcut.com';
const String kCapCutEditApiUrl = 'https://edit-api-sg.capcut.com';
const String kCapCutLoginHost = 'https://login-row.www.capcut.com';
const String kCapCutFallbackLoginHost = 'https://login.us.capcut.com';
const String kCapCutAppId = '348188';
const String kCapCutLoginSdkVersion = '2.1.10-tiktok';
const String kCapCutWebAppVersion = '5.8.0';
const String kCapCutEditorAppVersion = '5.8.0';
const String kCapCutPlatformId = '7';
const String kCapCutSignVersion = '1';
const String kCapCutVoicePanel = 'tone';
const String kCapCutVoicePanelSource = 'heycan';
const int kCapCutTtsSmartToolType = 39;
const int kCapCutTtsScene = 3;
const int kCapCutTtsPlatform = 1;
const int kCapCutVoiceCacheMs = 10 * 60 * 1000;
const int kCapCutSessionValidateMs = 10 * 60 * 1000;
const int kCapCutTtsPollIntervalMs = 700;
const int kCapCutTtsMaxPollAttempts = 30;
const String kCapCutUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36';
const String kCapCutLocale = 'ja-JP';
const String kCapCutPageLocale = 'ja-jp';
const String kCapCutRegion = 'JP';
const String kCapCutStoreCountryCode = 'jp';

const String kLegacyCapCutApiUrl = 'https://edit-api-sg.capcut.com/lv/v1';
const String kLegacyByteIntlApiUrl =
    'wss://sami-sg1.internal.byteintlapi.com/internal/api/v1';
const String kLegacyCapCutAppVersion = '5.8.0';
const String kLegacyCapCutPlatform = '7';
const int kLegacyCapCutSampleRate = 24000;
const String kLegacyDefaultSpeaker = 'BV016_streaming';
const String kLegacyAppIdNum = '348188';

/// Same sign algorithm as createEditApiSignature.
Map<String, String> createCapCutSignature(
  String requestUrl,
  String platformId,
  String appVersion,
  String tdid, {
  String prefix = '9e2c',
  String suffix = '11ac',
  int pathTailLength = 7,
}) {
  final uri = Uri.parse(requestUrl);
  final path = uri.path;
  final tail = path.length <= pathTailLength
      ? path
      : path.substring(path.length - pathTailLength);
  final deviceTime = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  final raw = '$prefix|$tail|$platformId|$appVersion|$deviceTime|$tdid|$suffix';
  final sign = md5.convert(utf8.encode(raw)).toString().toLowerCase();
  return {'sign': sign, 'deviceTime': deviceTime};
}

class CapCutApiException implements Exception {
  final String message;
  final int? statusCode;
  final int? errorCode;

  CapCutApiException(this.message, {this.statusCode, this.errorCode});

  bool get isSessionExpired => RegExp(
        r'check login error|account info failed|workspace list was empty',
        caseSensitive: false,
      ).hasMatch(message);

  @override
  String toString() => message;
}

/// Minimal cookie jar (port of CookieJar.ts).
class CapCutCookieJar {
  final Map<String, Map<String, dynamic>> _cookies = {};

  void clear() => _cookies.clear();

  void hydrate(List<dynamic> cookies) {
    _cookies.clear();
    for (final c in cookies) {
      if (c is! Map) continue;
      final name = c['name']?.toString() ?? '';
      final domain = c['domain']?.toString() ?? '';
      final path = c['path']?.toString() ?? '/';
      if (name.isEmpty) continue;
      _cookies['$domain;$path;$name'] = {
        'name': name,
        'value': c['value']?.toString() ?? '',
        'domain': domain,
        'path': path,
        'expiresAt': c['expiresAt'],
        'hostOnly': c['hostOnly'] ?? false,
        'secure': c['secure'] ?? false,
      };
    }
  }

  List<Map<String, dynamic>> serialize() =>
      _cookies.values.map((e) => Map<String, dynamic>.from(e)).toList();

  void set(String name, String value, String domain,
      [String path = '/', bool hostOnly = false]) {
    _cookies['$domain;$path;$name'] = {
      'name': name,
      'value': value,
      'domain': domain,
      'path': path,
      'hostOnly': hostOnly,
      'secure': true,
    };
  }

  String? get(String name, [String? url]) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final c in _cookies.values) {
      if (c['name'] != name) continue;
      final exp = c['expiresAt'];
      if (exp is num && exp <= now) continue;
      if (url == null || _matches(c, Uri.parse(url), now)) {
        return c['value']?.toString();
      }
    }
    return null;
  }

  String cookieHeader(String url) {
    final uri = Uri.parse(url);
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = _cookies.values.where((c) => _matches(c, uri, now)).toList()
      ..sort((a, b) =>
          (b['path'] as String).length.compareTo((a['path'] as String).length));
    return list.map((c) => "${c['name']}=${c['value']}").join('; ');
  }

  void storeFromHeaders(Map<String, List<String>> headers, String url) {
    final setCookies = headers['set-cookie'] ?? headers['Set-Cookie'] ?? [];
    for (final h in setCookies) {
      _store(h, url);
    }
  }

  void _store(String header, String requestUrl) {
    final request = Uri.parse(requestUrl);
    final parts =
        header.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return;
    final eq = parts.first.indexOf('=');
    if (eq <= 0) return;
    final name = parts.first.substring(0, eq).trim();
    final value = parts.first.substring(eq + 1).trim();
    var domain = request.host.toLowerCase();
    var path = _defaultPath(request.path);
    int? expiresAt;
    var secure = false;
    var hostOnly = true;
    for (final attr in parts.skip(1)) {
      final idx = attr.indexOf('=');
      final key = (idx < 0 ? attr : attr.substring(0, idx)).toLowerCase();
      final val = idx < 0 ? '' : attr.substring(idx + 1).trim();
      if (key == 'domain' && val.isNotEmpty) {
        domain = val.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
        hostOnly = false;
      } else if (key == 'path' && val.isNotEmpty) {
        path = val;
      } else if (key == 'max-age') {
        final secs = int.tryParse(val);
        if (secs != null) {
          expiresAt = DateTime.now().millisecondsSinceEpoch + secs * 1000;
        }
      } else if (key == 'expires') {
        final parsed = DateTime.tryParse(val)?.millisecondsSinceEpoch;
        if (parsed != null) expiresAt = parsed;
      } else if (key == 'secure') {
        secure = true;
      }
    }
    final k = '$domain;$path;$name';
    if (expiresAt != null && expiresAt <= DateTime.now().millisecondsSinceEpoch) {
      _cookies.remove(k);
      return;
    }
    _cookies[k] = {
      'name': name,
      'value': value,
      'domain': domain,
      'path': path,
      'expiresAt': expiresAt,
      'hostOnly': hostOnly,
      'secure': secure,
    };
  }

  String _defaultPath(String pathname) {
    if (pathname.isEmpty || pathname == '/') return '/';
    final last = pathname.lastIndexOf('/');
    return last <= 0 ? '/' : pathname.substring(0, last);
  }

  bool _matches(Map<String, dynamic> c, Uri uri, int now) {
    final exp = c['expiresAt'];
    if (exp is num && exp <= now) return false;
    if ((c['secure'] as bool? ?? false) && uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    final domain = (c['domain'] as String).toLowerCase();
    final domainOk = (c['hostOnly'] as bool? ?? false)
        ? host == domain
        : (host == domain || host.endsWith('.$domain'));
    if (!domainOk) return false;
    final p = uri.path.isEmpty ? '/' : uri.path;
    return p.startsWith(c['path'] as String? ?? '/');
  }
}

class CapCutSpeaker {
  final String title;
  final String description;
  final String? speaker;
  final String effectId;
  final String resourceId;
  final int? ttsPlatform;
  final bool isVip;
  final String style;
  final String language;

  const CapCutSpeaker({
    required this.title,
    required this.description,
    this.speaker,
    required this.effectId,
    required this.resourceId,
    this.ttsPlatform,
    this.isVip = false,
    this.style = '',
    this.language = 'unknown',
  });
}

/// Port of resolveSpeaker + speakerAliases + fallbackSpeakers.
CapCutSpeaker resolveCapCutSpeaker(
  dynamic type,
  List<CapCutSpeaker> speakers, [
  String? requested,
]) {
  final alias = _capCutSpeakerAliases[requested?.trim().toLowerCase() ?? ''];
  final target = (alias ?? requested ?? '').trim();
  if (target.isNotEmpty) {
    final hit = _findCapCutSpeaker(target, speakers) ??
        _findCapCutSpeaker(target, capCutFallbackSpeakers);
    if (hit != null) return hit;
  }
  if (type is String && RegExp(r'^\d+$').hasMatch(type.trim())) {
    final i = int.parse(type.trim());
    return capCutFallbackSpeakers.elementAtOrNull(i) ??
        speakers.elementAtOrNull(i) ??
        capCutFallbackSpeakers.first;
  }
  if (type is String && type.trim().isNotEmpty) {
    final t = _capCutSpeakerAliases[type.trim().toLowerCase()] ?? type.trim();
    final hit = _findCapCutSpeaker(t, speakers) ??
        _findCapCutSpeaker(t, capCutFallbackSpeakers);
    if (hit != null) return hit;
  }
  final i = type is int ? type : 0;
  return capCutFallbackSpeakers.elementAtOrNull(i) ??
      speakers.elementAtOrNull(i) ??
      capCutFallbackSpeakers.first;
}

CapCutSpeaker? _findCapCutSpeaker(String target, List<CapCutSpeaker> list) {
  final t = target.toLowerCase();
  for (final s in list) {
    if (s.effectId.toLowerCase() == t ||
        s.resourceId.toLowerCase() == t ||
        s.speaker?.toLowerCase() == t ||
        s.title.toLowerCase() == t) {
      return s;
    }
  }
  return null;
}

bool capCutSupportsMultiPlatform(String? speaker) =>
    speaker != null &&
    RegExp(r'^(?:ICL_[A-Za-z0-9_]+|BV\d+_streaming|jp_\d+)$')
        .hasMatch(speaker);

/// Port of splitTtsText.
List<String> splitCapCutText(String text,
    [int maxLength = 500, double boundaryRatio = 0.6]) {
  final normalized = text.trim();
  final chars = normalized.runes.map((r) => String.fromCharCode(r)).toList();
  if (chars.length <= maxLength) return [normalized];
  final chunks = <String>[];
  var start = 0;
  bool isSep(String c) =>
      c == '\n' || c == '\r' || c == ' ' || c == '\t' || c == '　';
  bool isStrong(String c) => c == '\n' ||
      c == '\r' ||
      c == '。' ||
      c == '！' ||
      c == '？' ||
      c == '!' ||
      c == '?' ||
      c == '．' ||
      c == '.';
  bool isWeak(String c) =>
      isSep(c) ||
      c == '、' ||
      c == ',' ||
      c == '，' ||
      c == '；' ||
      c == ';' ||
      c == '：' ||
      c == ':';
  while (start < chars.length) {
    final remaining = chars.length - start;
    if (remaining <= maxLength) {
      final tail = chars.sublist(start).join().trim();
      if (tail.isNotEmpty) chunks.add(tail);
      break;
    }
    final end = start + maxLength;
    final preferred =
        start + 1 + (maxLength * boundaryRatio).floor() > start + 1
            ? start + (maxLength * boundaryRatio).floor()
            : start + 1;
    var cut = end;
    var found = false;
    for (var i = end - 1; i >= preferred; i--) {
      if (isStrong(chars[i])) {
        cut = i + 1;
        found = true;
        break;
      }
    }
    if (!found) {
      for (var i = end - 1; i >= preferred; i--) {
        if (isWeak(chars[i])) {
          cut = i + 1;
          found = true;
          break;
        }
      }
    }
    if (!found) cut = end;
    final chunk = chars.sublist(start, cut).join().trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    start = cut;
    while (start < chars.length && isSep(chars[start])) {
      start++;
    }
  }
  return chunks.isNotEmpty ? chunks : [normalized];
}

const Map<String, String> _capCutSpeakerAliases = {
  'labebe': '7530105822785899777',
  'cool_lady': '7530107275239869713',
  'happy_dino': '7527795878967446801',
  'puppet': '7527814111502044433',
  'popular_guy': '7527779392769002769',
  'bratty_witch': '7527846655475928336',
  'game_host': '7527778973296774416',
  'calm_dubbing': '7527793325328452881',
  'gruff_uncle': '7522965008020507920',
  'witch_granny': '7522976550736710913',
  'high_tension': '7522976550736661761',
  'serious_man': '7522987643752271121',
  'manager': '7522976550736678145',
  'little_sister': '7522987643752303889',
  'young_girl': '7522965008020475152',
  'peaceful_woman': '7114563483257016833',
};

const List<CapCutSpeaker> capCutFallbackSpeakers = [
  CapCutSpeaker(title: 'ラベベさん', description: '英語の明るい女性ボイス', speaker: 'ICL_en_female_jiaoao', effectId: '7530105822785899777', resourceId: '7530105822785899777'),
  CapCutSpeaker(title: '冷静なレディ', description: '英語の落ち着いた女性ボイス', speaker: 'ICL_en_female_guanggao', effectId: '7530107275239869713', resourceId: '7530107275239869713'),
  CapCutSpeaker(title: 'ハッピーディノ', description: 'スペイン語の陽気な男性ボイス', speaker: 'ICL_es_male_barney', effectId: '7527795878967446801', resourceId: '7527795878967446801'),
  CapCutSpeaker(title: 'おかしなあやつり人形', description: 'スペイン語のコミカルな男性ボイス', speaker: 'ICL_es_male_elmo', effectId: '7527814111502044433', resourceId: '7527814111502044433'),
  CapCutSpeaker(title: 'モテ男', description: 'スペイン語の低めな男性ボイス', speaker: 'ICL_es_male_cixing', effectId: '7527779392769002769', resourceId: '7527779392769002769'),
  CapCutSpeaker(title: '生意気な魔女', description: 'スペイン語のクセのある女性ボイス', speaker: 'ICL_es_female_dianpo', effectId: '7527846655475928336', resourceId: '7527846655475928336'),
  CapCutSpeaker(title: 'ゲームホスト', description: 'スペイン語の軽快な男性ボイス', speaker: 'ICL_es_male_dorado', effectId: '7527778973296774416', resourceId: '7527778973296774416'),
  CapCutSpeaker(title: '穏やかな吹き替え', description: 'スペイン語の穏やかな女性ボイス', speaker: 'ICL_es_female_dianyingpeiyin', effectId: '7527793325328452881', resourceId: '7527793325328452881'),
  CapCutSpeaker(title: '濁声おじさん', description: '低く濁った男性ボイス', speaker: 'ICL_es_male_taici', effectId: '7522965008020507920', resourceId: '7522965008020507920'),
  CapCutSpeaker(title: '魔婆', description: '年配女性風の日本語ボイス', speaker: 'ICL_ja_female_laopopo', effectId: '7522976550736710913', resourceId: '7522976550736710913'),
  CapCutSpeaker(title: 'マネージャー', description: '早口で張りのある日本語ボイス', speaker: 'ICL_ja_female_kuaizui02', effectId: '7522976550736678145', resourceId: '7522976550736678145'),
  CapCutSpeaker(title: '妹系', description: '若い女性寄りの日本語ボイス', speaker: 'ICL_ja_female_shuanglang', effectId: '7522987643752303889', resourceId: '7522987643752303889'),
  CapCutSpeaker(title: '幼い女の子', description: '幼い少女風の日本語ボイス', speaker: 'ICL_jp_female_jidongshaonv', effectId: '7522965008020475152', resourceId: '7522965008020475152'),
  CapCutSpeaker(title: '高テンション', description: '勢いのある日本語男性ボイス', speaker: 'ICL_ja_male_gaoxiao', effectId: '7522976550736661761', resourceId: '7522976550736661761'),
  CapCutSpeaker(title: '真面目男', description: '落ち着いた日本語男性ボイス', speaker: 'ICL_ja_male_gaoxiao02', effectId: '7522987643752271121', resourceId: '7522987643752271121'),
];

const List<CapCutSpeaker> capCutLegacySpeakers = [
  CapCutSpeaker(title: '謎1 男子1', description: '男性ボイス', speaker: 'BV525_streaming', effectId: 'BV525_streaming', resourceId: 'BV525_streaming', language: 'ja'),
  CapCutSpeaker(title: '坊や', description: '少年風ボイス', speaker: 'BV528_streaming', effectId: 'BV528_streaming', resourceId: 'BV528_streaming', language: 'ja'),
  CapCutSpeaker(title: 'カワボ', description: 'かわいい女性ボイス', speaker: 'BV017_streaming', effectId: 'BV017_streaming', resourceId: 'BV017_streaming', language: 'ja'),
  CapCutSpeaker(title: 'お姉さん', description: '女性ボイス', speaker: 'BV016_streaming', effectId: 'BV016_streaming', resourceId: 'BV016_streaming', language: 'ja'),
  CapCutSpeaker(title: '少女', description: '少女風ボイス', speaker: 'BV023_streaming', effectId: 'BV023_streaming', resourceId: 'BV023_streaming', language: 'ja'),
  CapCutSpeaker(title: '女子', description: '女性ボイス', speaker: 'BV024_streaming', effectId: 'BV024_streaming', resourceId: 'BV024_streaming', language: 'ja'),
  CapCutSpeaker(title: '男子2', description: '男性ボイス', speaker: 'BV018_streaming', effectId: 'BV018_streaming', resourceId: 'BV018_streaming', language: 'ja'),
  CapCutSpeaker(title: '坊ちゃん', description: '少年風ボイス', speaker: 'BV523_streaming', effectId: 'BV523_streaming', resourceId: 'BV523_streaming', language: 'ja'),
  CapCutSpeaker(title: '女子"', description: '女性ボイス', speaker: 'BV521_streaming', effectId: 'BV521_streaming', resourceId: 'BV521_streaming', language: 'ja'),
  CapCutSpeaker(title: '女子アナ', description: '女性アナウンサーボイス', speaker: 'BV522_streaming', effectId: 'BV522_streaming', resourceId: 'BV522_streaming', language: 'ja'),
  CapCutSpeaker(title: '男性アナ', description: '男性アナウンサーボイス', speaker: 'BV524_streaming', effectId: 'BV524_streaming', resourceId: 'BV524_streaming', language: 'ja'),
  CapCutSpeaker(title: '元気ロリ', description: '元気な少女風ボイス', speaker: 'BV520_streaming', effectId: 'BV520_streaming', resourceId: 'BV520_streaming', language: 'ja'),
  CapCutSpeaker(title: '明るいハニー', description: '明るい女性ボイス', speaker: 'VOV401_bytesing3_kangkangwuqu', effectId: 'VOV401_bytesing3_kangkangwuqu', resourceId: 'VOV401_bytesing3_kangkangwuqu', language: 'ja'),
  CapCutSpeaker(title: '優しいレディー', description: '優しい女性ボイス', speaker: 'VOV402_bytesing3_oh', effectId: 'VOV402_bytesing3_oh', resourceId: 'VOV402_bytesing3_oh', language: 'ja'),
  CapCutSpeaker(title: '風雅メゾソプラノ', description: 'メゾソプラノ風ボイス', speaker: 'VOV402_bytesing3_aidelizan', effectId: 'VOV402_bytesing3_aidelizan', resourceId: 'VOV402_bytesing3_aidelizan', language: 'ja'),
  CapCutSpeaker(title: 'Sakura', description: 'Sakura ボイス', speaker: 'jp_005', effectId: 'jp_005', resourceId: 'jp_005', language: 'ja'),
];
