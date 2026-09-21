import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../repositories/apis.dart';
import '../repositories/shared_pref_repo.dart';
import '../utills/logging.dart';

class TraccarSocketPayload {
  final List<Map<String, dynamic>> devices;
  final List<Map<String, dynamic>> positions;
  final List<Map<String, dynamic>> events;

  const TraccarSocketPayload({
    this.devices = const [],
    this.positions = const [],
    this.events = const [],
  });
}

class TraccarSocketService {
  WebSocket? _socket;
  bool _isConnecting = false;
  bool _closedByClient = false;
  final _controller = StreamController<TraccarSocketPayload>.broadcast();

  Stream<TraccarSocketPayload> get stream => _controller.stream;
  bool get isConnected => _socket != null;

  Future<void> connect() async {
    if (_socket != null || _isConnecting) return;
    _closedByClient = false;
    _isConnecting = true;

    try {
      final cookie = SharedPrefsRepository().sessionCookie;
      if (cookie == null || cookie.isEmpty) {
        Logger.error('Traccar WS ✗ missing session cookie');
        return;
      }

      Logger.message('Traccar WS → connecting to ${AppUrl.socketUrl}');
      _socket = await WebSocket.connect(
        AppUrl.socketUrl,
        headers: {HttpHeaders.cookieHeader: cookie},
      );
      Logger.success('Traccar WS ✓ connected');

      _socket!.listen(
        _onMessage,
        onDone: _onDone,
        onError: (error) {
          Logger.error('Traccar WS ✗ stream error: $error');
          _onDone();
        },
        cancelOnError: true,
      );
    } catch (e) {
      Logger.error('Traccar WS ✗ connect failed: $e');
      _scheduleReconnect();
    } finally {
      _isConnecting = false;
    }
  }

  Future<void> disconnect() async {
    _closedByClient = true;
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    try {
      final decoded = jsonDecode(message);
      if (decoded is! Map) return;
      final data = Map<String, dynamic>.from(decoded);
      final payload = TraccarSocketPayload(
        devices: _asList(data['devices']),
        positions: _asList(data['positions']),
        events: _asList(data['events']),
      );
      if (!_controller.isClosed) {
        _controller.add(payload);
      }
    } catch (e) {
      Logger.error('Traccar WS ✗ parse error: $e');
    }
  }

  void _onDone() {
    _socket = null;
    if (_closedByClient) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    Timer(const Duration(seconds: 5), () {
      if (!_closedByClient) {
        connect();
      }
    });
  }

  List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  void dispose() {
    _closedByClient = true;
    _socket?.close();
    _controller.close();
  }
}
