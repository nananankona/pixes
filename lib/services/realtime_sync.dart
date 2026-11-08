import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pixes/foundation/log.dart';

/// Minimal Supabase Realtime (Phoenix channels v1) client.
///
/// Joins a single topic with postgres_changes bindings and invokes
/// [onEvent] for every INSERT / UPDATE / DELETE. No extra dependencies;
/// works with the anon key while RLS is disabled on the tables.
class RealtimeSync {
  WebSocket? _ws;
  Timer? _heartbeat;
  Timer? _watchdog;
  Timer? _reconnectTimer;
  int _ref = 0;
  int _reconnectAttempt = 0;
  bool _started = false;
  bool _joined = false;
  DateTime? _lastMessageAt;
  String _joinRef = '';

  void Function(String table, String type, Map<String, dynamic> record,
      Map<String, dynamic>? oldRecord)? onEvent;

  final ValueNotifier<bool> connected = ValueNotifier(false);

  static const _topic = 'realtime:pixes-sync';
  static const _tables = [
    'sync_search_history',
    'sync_browsing_history',
    'sync_settings',
    'sync_devices',
  ];

  bool get isActive => _started;

  Future<void> start({
    required String supabaseUrl,
    required String apiKey,
    required void Function(String table, String type,
            Map<String, dynamic> record, Map<String, dynamic>? oldRecord)
        onEvent,
  }) async {
    if (_started) return;
    this.onEvent = onEvent;
    _started = true;
    _reconnectAttempt = 0;
    _socketUrl = '${supabaseUrl.replaceAll(RegExp(r'/+$'), '')}'
        '/realtime/v1/websocket?apikey=$apiKey&vsn=1.0.0';
    _apiKey = apiKey;
    await _connect();
  }

  String _socketUrl = '';
  String _apiKey = '';

  void stop() {
    _started = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _cleanupSocket();
    if (connected.value) connected.value = false;
  }

  void _cleanupSocket() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _watchdog?.cancel();
    _watchdog = null;
    _joined = false;
    try {
      _ws?.close();
    } catch (_) {}
    _ws = null;
  }

  Future<void> _connect() async {
    if (!_started) return;
    try {
      final ws = await WebSocket.connect(
        _socketUrl,
        headers: {'apikey': _apiKey, 'Authorization': 'Bearer $_apiKey'},
      ).timeout(const Duration(seconds: 15));
      if (!_started) {
        try {
          await ws.close();
        } catch (_) {}
        return;
      }
      _ws = ws;
      _reconnectAttempt = 0;
      _lastMessageAt = DateTime.now();
      ws.listen(_onMessage,
          onError: (_) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true);
      _sendJoin();
      _heartbeat?.cancel();
      _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
        _send({'topic': 'phoenix', 'event': 'heartbeat', 'payload': {}});
      });
      _watchdog?.cancel();
      _watchdog = Timer.periodic(const Duration(seconds: 30), (_) {
        final last = _lastMessageAt;
        if (last != null &&
            DateTime.now().difference(last) > const Duration(seconds: 65)) {
          Log.info("Realtime", "No traffic for a while, reconnecting");
          _scheduleReconnect();
        }
      });
    } catch (e) {
      Log.info("Realtime", "Connect failed: $e");
      _scheduleReconnect();
    }
  }

  void _send(Map<String, dynamic> message) {
    final ws = _ws;
    if (ws == null) return;
    message['ref'] = '${++_ref}';
    try {
      ws.add(jsonEncode(message));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _sendJoin() {
    _joinRef = '${++_ref}';
    final bindings = _tables
        .map((t) => {
              'event': '*',
              'schema': 'public',
              'table': t,
            })
        .toList();
    try {
      _ws?.add(jsonEncode({
        'topic': _topic,
        'event': 'phx_join',
        'ref': _joinRef,
        'join_ref': _joinRef,
        'payload': {
          'config': {
            'broadcast': {'ack': false, 'self': false},
            'presence': {'key': ''},
            'postgres_changes': bindings,
          },
          'access_token': _apiKey,
        },
      }));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    _lastMessageAt = DateTime.now();
    Map<String, dynamic>? m;
    try {
      final decoded = raw is String ? jsonDecode(raw) : null;
      if (decoded is Map<String, dynamic>) m = decoded;
    } catch (_) {
      return;
    }
    if (m == null) return;
    final event = m['event']?.toString() ?? '';
    if (event == 'phx_reply') {
      final ref = m['ref']?.toString();
      final status = (m['payload'] as Map?)?['status']?.toString();
      if (ref == _joinRef && status == 'ok') {
        _joined = true;
        if (!connected.value) connected.value = true;
        Log.info("Realtime", "Joined live channel");
      }
      return;
    }
    if (event != 'postgres_changes') return;
    if (!_joined) return;
    try {
      final payload = m['payload'] as Map? ?? {};
      final data = payload['data'] as Map? ?? {};
      final type = (data['type'] ?? '').toString().toUpperCase();
      final table = (data['table'] ?? '').toString();
      if (type.isEmpty || table.isEmpty) return;
      final record = data['record'];
      final oldRecord = data['old_record'];
      onEvent?.call(
        table,
        type,
        record is Map ? Map<String, dynamic>.from(record) : {},
        oldRecord is Map ? Map<String, dynamic>.from(oldRecord) : null,
      );
    } catch (e) {
      Log.info("Realtime", "Bad event payload: $e");
    }
  }

  void _scheduleReconnect() {
    if (!_started) return;
    if (_reconnectTimer != null) return;
    if (connected.value) connected.value = false;
    _cleanupSocket();
    final delay = _reconnectAttempt == 0
        ? 2
        : _reconnectAttempt == 1
            ? 5
            : _reconnectAttempt == 2
                ? 15
                : 30;
    _reconnectAttempt++;
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _reconnectTimer = null;
      _connect();
    });
  }
}

final realtimeSync = RealtimeSync();
