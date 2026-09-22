import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/user_model/user_model.dart';
import '../utills/logging.dart';

const String _authEmailKey = 'AUTH_EMAIL';
const String _authPasswordKey = 'AUTH_PASSWORD';
const String _sessionCookieKey = 'SESSION_COOKIE';
const String _sessionTokenKey = 'SESSION_TOKEN';
const String _userModelKey = 'USER_MODEL';
const String _engineCommandPrefix = 'ENGINE_COMMAND_';
const String _engineStatePrefix = 'ENGINE_STATE_';
const String _engineStateIdsKey = 'ENGINE_STATE_IDS';

class SharedPrefsRepository {
  static final SharedPrefsRepository _instance =
      SharedPrefsRepository._internal();

  factory SharedPrefsRepository() => _instance;

  SharedPrefsRepository._internal();

  late final SharedPreferences _prefs;

  static Future<void> initialize() async {
    _instance._prefs = await SharedPreferences.getInstance();
    Logger.success('SharedPrefsRepository initialized');
  }

  String? get email => _prefs.getString(_authEmailKey);
  String? get password => _prefs.getString(_authPasswordKey);
  String? get sessionCookie => _prefs.getString(_sessionCookieKey);
  String? get sessionToken => _prefs.getString(_sessionTokenKey);

  bool get isLoggedIn {
    final cookie = sessionCookie;
    final mail = email;
    final pass = password;
    return (cookie != null && cookie.isNotEmpty) ||
        (mail != null &&
            mail.isNotEmpty &&
            pass != null &&
            pass.isNotEmpty);
  }

  Future<void> saveAuth({
    required String email,
    required String password,
    required String sessionCookie,
    required UserModel user,
    String? sessionToken,
  }) async {
    await _prefs.setString(_authEmailKey, email);
    await _prefs.setString(_authPasswordKey, password);
    await _prefs.setString(_sessionCookieKey, sessionCookie);
    await _prefs.setString(_userModelKey, jsonEncode(user.toJson()));
    if (sessionToken != null && sessionToken.isNotEmpty) {
      await _prefs.setString(_sessionTokenKey, sessionToken);
    }
  }

  Future<void> setSessionCookie(String cookie) async {
    await _prefs.setString(_sessionCookieKey, cookie);
  }

  Future<void> setSessionToken(String token) async {
    await _prefs.setString(_sessionTokenKey, token);
  }

  UserModel? getUser() {
    final raw = _prefs.getString(_userModelKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return UserModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearUserData() async {
    await _prefs.remove(_authEmailKey);
    await _prefs.remove(_authPasswordKey);
    await _prefs.remove(_sessionCookieKey);
    await _prefs.remove(_sessionTokenKey);
    await _prefs.remove(_userModelKey);
  }

  /// Last engine command sent for a device: `engineStop` or `engineResume`.
  String? getEngineCommand(int deviceId) =>
      _prefs.getString('$_engineCommandPrefix$deviceId');

  Future<void> setEngineCommand(int deviceId, String type) async {
    await _prefs.setString('$_engineCommandPrefix$deviceId', type);
  }

  /// Confirmed engine immobilizer state: `on` or `off` only.
  String? getConfirmedEngineState(int deviceId) =>
      _prefs.getString('$_engineStatePrefix$deviceId');

  Future<void> setConfirmedEngineState(int deviceId, String state) async {
    if (state != 'on' && state != 'off') return;
    await _prefs.setString('$_engineStatePrefix$deviceId', state);
    final ids = _prefs.getStringList(_engineStateIdsKey) ?? <String>[];
    final idStr = deviceId.toString();
    if (!ids.contains(idStr)) {
      ids.add(idStr);
      await _prefs.setStringList(_engineStateIdsKey, ids);
    }
  }

  Map<int, String> allConfirmedEngineStates() {
    final ids = _prefs.getStringList(_engineStateIdsKey) ?? const <String>[];
    final out = <int, String>{};
    for (final idStr in ids) {
      final id = int.tryParse(idStr);
      if (id == null) continue;
      final value = getConfirmedEngineState(id);
      if (value == 'on' || value == 'off') {
        out[id] = value!;
      }
    }
    return out;
  }
}
