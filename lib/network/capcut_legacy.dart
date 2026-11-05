import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pixes/appdata.dart';
import 'package:pixes/foundation/log.dart';
import 'package:pixes/network/capcut.dart';

/// Direct port of LegacyCapCutService (v1 token + WebSocket flow).
/// No account needed.
class CapCutLegacyService {
  String _token = '';
  String _appKey = '';
  int _refreshedAt = 0;
  Future<void>? _refreshing;
  Timer? _refreshTimer;

  static const _tokenTtlMs = 60 * 60 * 1000;
  static const _retryDelayMs = 60 * 1000;

  bool get _ready => _token.isNotEmpty && _appKey.isNotEmpty;

  Future<void> _ensureToken() async {
    if (_ready &&
        DateTime.now().millisecondsSinceEpoch - _refreshedAt < _tokenTtlMs) {
      return;
    }
    if (_refreshing != null) {
      await _refreshing;
      return;
    }
    final future = _fetchToken().then((t) {
      _token = t.$1;
      _appKey = t.$2;
      _refreshedAt = DateTime.now().millisecondsSinceEpoch;
      _scheduleRefresh();
    }).catchError((Object e) {
      _scheduleRefresh(retry: true);
      if (!_ready) throw e;
      Log.info("CapCutV1",
          "Token refresh failed, using previous token until next retry");
    }).whenComplete(() {
      _refreshing = null;
    });
    _refreshing = future;
    await future;
  }

  void _scheduleRefresh({bool retry = false}) {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(
        Duration(
            milliseconds: retry ? _retryDelayMs : _tokenTtlMs), () {
      _refreshing = null;
      _ensureToken().catchError((_) {});
    });
  }

  Future<(String, String)> _fetchToken() async {
    const url = '$kLegacyCapCutApiUrl/common/tts/token';
    final sig = createCapCutSignature(
        url, kLegacyCapCutPlatform, kLegacyCapCutAppVersion, '');
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
    final res = await dio.post(url,
        options: Options(headers: {
          'Appvr': kLegacyCapCutAppVersion,
          'Device-Time': sig['deviceTime'],
          'Origin': kCapCutWebUrl,
          'Pf': kLegacyCapCutPlatform,
          'Sign': sig['sign'],
          'Sign-Ver': '1',
          'User-Agent': kCapCutUserAgent,
        }));
    final data = res.data is Map
        ? (res.data as Map)['data']
        : (jsonDecode(res.data.toString()) as Map)['data'];
    final token = data?['token']?.toString() ?? '';
    final appKey = data?['app_key']?.toString() ?? '';
    if (token.isEmpty || appKey.isEmpty) {
      throw CapCutApiException('CapCut v1 token response lacked metadata');
    }
    return (token, appKey);
  }

  String _speakerFor(int type) {
    if (type >= 0 && type < capCutLegacySpeakers.length) {
      return capCutLegacySpeakers[type].speaker!;
    }
    return kLegacyDefaultSpeaker;
  }

  String get _wsUrl {
    final v = (appdata.settings['capcutV1WsUrl'] as String? ?? '').trim();
    return v.isEmpty ? '$kLegacyByteIntlApiUrl/ws' : v;
  }

  /// Synthesize [text] into wav bytes.
  Future<Uint8List> synthesize(
    String text, {
    int type = 0,
    int pitch = 10,
    int speed = 10,
    int volume = 10,
  }) async {
    await _ensureToken();
    final speaker = _speakerFor(type);
    final payload = {
      'text': text,
      'speaker': speaker,
      'pitch': pitch,
      'speed': speed,
      'volume': volume,
      'rate': kLegacyCapCutSampleRate,
      'appid': kLegacyAppIdNum,
    };
    final message = jsonEncode({
      'token': _token,
      'appkey': _appKey,
      'namespace': 'TTS',
      'event': 'StartTask',
      'payload': jsonEncode(payload),
    });

    final ws = await WebSocket.connect(_wsUrl)
        .timeout(const Duration(seconds: 15));
    final completer = Completer<Uint8List>();
    final chunks = <int>[];
    var settled = false;
    Timer? guard;
    void done(Uint8List? data, Object? error) {
      if (settled) return;
      settled = true;
      guard?.cancel();
      try {
        ws.close();
      } catch (_) {}
      if (error != null) {
        completer.completeError(error);
      } else {
        completer.complete(Uint8List.fromList(data ?? []));
      }
    }

    guard = Timer(const Duration(seconds: 120), () {
      done(null, TimeoutException('CapCut v1 synthesis timed out'));
    });
    ws.listen((dynamic data) {
      Map<String, dynamic>? status;
      if (data is String) {
        try {
          final parsed = jsonDecode(data);
          if (parsed is Map<String, dynamic>) status = parsed;
        } catch (_) {
          status = null;
        }
      } else if (data is List<int>) {
        // Binary audio chunk.
        chunks.addAll(data);
        return;
      } else {
        return;
      }
      if (status == null) return;
      final event = status['event']?.toString();
      if (event == 'TaskStarted') return;
      if (event == 'TaskFinished') {
        done(Uint8List.fromList(chunks), null);
        return;
      }
      final code = status['status_code'];
      if (event == 'TaskFailed' ||
          (code is num && code >= 400) ||
          (code is String && (int.tryParse(code) ?? 0) >= 400)) {
        done(
            null,
            CapCutApiException(
                'CapCut v1 task failed: ${status['status_code']} ${status['status_text']}'));
      }
      // Unknown JSON messages are ignored (same as original).
    }, onError: (Object e) {
      done(null, e is Exception ? e : Exception('CapCut v1 websocket error'));
    }, onDone: () {
      done(null, const FormatException(
          'CapCut v1 websocket closed before the task finished'));
    }, cancelOnError: false);

    try {
      ws.add(message);
    } catch (e) {
      done(null, e is Exception ? e : Exception('CapCut v1 send failed'));
    }
    return completer.future;
  }
}
