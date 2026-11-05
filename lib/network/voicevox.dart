import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:pixes/network/capcut.dart' show CapCutApiException;

/// Minimal client for VOICEVOX ENGINE (default http://127.0.0.1:50021).
class VoicevoxService {
  final Dio _dio;

  VoicevoxService({String? baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? 'http://127.0.0.1:50021',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 60),
            ));

  String get baseUrl => _dio.options.baseUrl;

  set baseUrl(String url) => _dio.options.baseUrl = url;

  Future<String> version() async {
    try {
      final res = await _dio.get('/version');
      return res.data?.toString() ?? 'unknown';
    } on DioException catch (e) {
      throw CapCutApiException(
          'VOICEVOX connection failed: ${e.message ?? e.type}');
    }
  }

  /// Returns [{name, uuid, styles:[{name, id}]}].
  Future<List<Map<String, dynamic>>> speakers() async {
    try {
      final res = await _dio.get('/speakers');
      final list = res.data as List;
      return list.map((e) {
        final m = e as Map;
        final styles = (m['styles'] as List? ?? [])
            .map((s) => {
                  'name': (s as Map)['name']?.toString() ?? '',
                  'id': (s['id'] as num?)?.toInt() ?? 0,
                })
            .toList();
        return {
          'name': m['name']?.toString() ?? '',
          'uuid': m['speaker_uuid']?.toString() ?? '',
          'styles': styles,
        };
      }).toList();
    } on DioException catch (e) {
      throw CapCutApiException(
          'VOICEVOX speakers failed: ${e.message ?? e.type}');
    }
  }

  Future<Uint8List> synthesize(
    String text, {
    required int speaker,
    double speedScale = 1.0,
  }) async {
    try {
      final query = await _dio.post('/audio_query',
          queryParameters: {'text': text, 'speaker': speaker});
      final queryJson = Map<String, dynamic>.from(query.data as Map);
      queryJson['speedScale'] = speedScale;
      final res = await _dio.post(
        '/synthesis',
        queryParameters: {
          'speaker': speaker,
          'enable_interrogative_upspeak': true,
        },
        data: queryJson,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data is List<int>) return Uint8List.fromList(data);
      throw CapCutApiException('VOICEVOX synthesis returned no audio');
    } on DioException catch (e) {
      throw CapCutApiException(
          'VOICEVOX synthesis failed: ${e.message ?? e.type}');
    }
  }
}
