class AppUrl {
  static const String host = 'my.cartag.co.za';
  static const String baseUrl = 'https://$host/api';
  static const String socketUrl = 'wss://$host/api/socket';

  /// Same Google Maps key used by UTrack / O2 Lite
  static const String googleAPIKey = 'AIzaSyDEck64OzLrbPNK4Bpxro1a-pbrcVN0PeE';

  static const String server = '$baseUrl/server';
  static const String session = '$baseUrl/session';
  static const String sessionToken = '$baseUrl/session/token';
  static const String devices = '$baseUrl/devices';
  static const String positions = '$baseUrl/positions';
  static const String commandsSend = '$baseUrl/commands/send';
  static const String commandsTypes = '$baseUrl/commands/types';
}
