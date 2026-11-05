import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pixes/appdata.dart';
import 'package:pixes/foundation/cache_manager.dart';
import 'package:pixes/foundation/log.dart';
import 'package:pixes/network/capcut.dart' show splitCapCutText;
import 'package:pixes/network/capcut_legacy.dart';
import 'package:pixes/network/capcut_v2.dart';
import 'package:pixes/network/voicevox.dart';

enum TtsEngine { off, voicevox, capcutServer, capcutV1, capcutV2 }

/// Text-to-speech orchestration for novel reading.
/// Synthesizes paragraph by paragraph, caches audio on disk,
/// and exposes the current paragraph for auto-scroll sync.
class TtsService {
  static TtsService? _instance;
  factory TtsService() => _instance ??= TtsService._();
  TtsService._();

  final AudioPlayer _player = AudioPlayer();
  final CapCutLegacyService _v1 = CapCutLegacyService();
  final CapCutV2Service _v2 = CapCutV2Service();

  bool playing = false;
  final ValueNotifier<int> paragraphIndex = ValueNotifier(-1);
  int _runId = 0;

  double get _speed =>
      (appdata.settings['ttsSpeed'] as num?)?.toDouble() ?? 1.0;
  double get _volume =>
      (appdata.settings['ttsVolume'] as num?)?.toDouble() ?? 1.0;

  Future<void> speak(List<String> paragraphs, TtsEngine engine) async {
    await stop();
    if (engine == TtsEngine.off || paragraphs.isEmpty) return;
    final run = ++_runId;
    playing = true;
    try {
      var index = -1;
      for (final para in paragraphs) {
        index++;
        final text = para.trim();
        if (text.isEmpty || text.startsWith('[uploadedimage:')) continue;
        final speakText = _stripMarkup(text);
        if (speakText.isEmpty) continue;
        for (final chunk in splitCapCutText(speakText)) {
          if (run != _runId) return;
          paragraphIndex.value = index;
          final audio = await _synthesize(chunk, engine);
          if (run != _runId) return;
          await _player.setVolume(_volume.clamp(0.0, 1.0));
          await _player.play(BytesSource(audio));
          await _player.onPlayerComplete.first;
        }
      }
    } catch (e) {
      Log.error("TTS", "speak failed: $e");
      rethrow;
    } finally {
      if (run == _runId) {
        playing = false;
        paragraphIndex.value = -1;
      }
    }
  }

  String _stripMarkup(String text) {
    var t = text;
    if (t.startsWith('[chapter:')) {
      t = t.replaceFirst('[chapter:', '');
      if (t.endsWith(']')) t = t.substring(0, t.length - 1);
    }
    return t.trim();
  }

  Future<void> stop() async {
    _runId++;
    playing = false;
    paragraphIndex.value = -1;
    try {
      await _player.stop();
    } catch (_) {}
  }

  void dispose() {
    _player.dispose();
  }

  String _voiceTag(TtsEngine engine) {
    switch (engine) {
      case TtsEngine.voicevox:
        return 'vox${appdata.settings['voicevoxSpeaker'] ?? 1}';
      case TtsEngine.capcutServer:
        return 'cap${appdata.settings['capcutSpeaker'] ?? 'labebe'}';
      case TtsEngine.capcutV1:
        return 'v1t${appdata.settings['capcutV1Type'] ?? 0}';
      case TtsEngine.capcutV2:
        return 'v2s${appdata.settings['capcutSpeaker'] ?? 'labebe'}';
      case TtsEngine.off:
        return 'off';
    }
  }

  Future<Uint8List> _synthesize(String text, TtsEngine engine) async {
    final hash = md5.convert(utf8.encode(text)).toString();
    final key =
        'tts:${_voiceTag(engine)}:s${_speed.toStringAsFixed(2)}:$hash';
    final cached = await CacheManager().findCache(key);
    if (cached != null) {
      try {
        final bytes = await File(cached).readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      } catch (_) {}
    }
    final bytes = await _synthesizeOnline(text, engine);
    await CacheManager().writeCache(key, bytes);
    return bytes;
  }

  Future<Uint8List> _synthesizeOnline(String text, TtsEngine engine) async {
    switch (engine) {
      case TtsEngine.voicevox:
        final rawUrl = appdata.settings['voicevoxUrl'] as String?;
        final url = (rawUrl == null || rawUrl.trim().isEmpty)
            ? 'http://127.0.0.1:50021'
            : rawUrl.trim();
        return VoicevoxService(baseUrl: url).synthesize(
          text,
          speaker: (appdata.settings['voicevoxSpeaker'] as num?)?.toInt() ?? 1,
          speedScale: _speed,
        );
      case TtsEngine.capcutServer:
        final rawUrl = appdata.settings['capcutServerUrl'] as String?;
        final url = (rawUrl == null || rawUrl.trim().isEmpty)
            ? 'http://127.0.0.1:8080'
            : rawUrl.trim();
        final rawSpeaker = appdata.settings['capcutSpeaker'] as String?;
        final speaker = (rawSpeaker == null || rawSpeaker.trim().isEmpty)
            ? 'labebe'
            : rawSpeaker.trim();
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(minutes: 2),
          validateStatus: (_) => true,
        ));
        final res = await dio.post(
          '$url/v2/synthesize',
          data: {
            'text': text,
            'speaker': speaker,
            'speed': (_speed * 10).round(),
            'volume': (_volume * 10).round(),
            'method': 'buffer',
          },
          options: Options(responseType: ResponseType.bytes),
        );
        if (res.statusCode != 200 || res.data is! List<int>) {
          throw Exception(
              'CapCut server synthesize failed: ${res.statusCode}');
        }
        return Uint8List.fromList(res.data as List<int>);
      case TtsEngine.capcutV1:
        return _v1.synthesize(
          text,
          type: (appdata.settings['capcutV1Type'] as num?)?.toInt() ?? 0,
          speed: (_speed * 10).round(),
          volume: (_volume * 10).round(),
        );
      case TtsEngine.capcutV2:
        final rawSpeaker = appdata.settings['capcutSpeaker'] as String?;
        return _v2.synthesize(
          text,
          speaker: (rawSpeaker == null || rawSpeaker.trim().isEmpty)
              ? null
              : rawSpeaker.trim(),
          type: 0,
          speed: _speed,
          volume: _volume,
        );
      case TtsEngine.off:
        throw StateError('TTS engine is off');
    }
  }
}
