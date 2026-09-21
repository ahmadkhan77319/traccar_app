class PositionModel {
  int? id;
  int? deviceId;
  String? protocol;
  DateTime? deviceTime;
  DateTime? fixTime;
  DateTime? serverTime;
  bool? valid;
  double? latitude;
  double? longitude;
  double? altitude;
  double? speed;
  double? course;
  String? address;
  double? accuracy;
  Map<String, dynamic>? attributes;

  PositionModel({
    this.id,
    this.deviceId,
    this.protocol,
    this.deviceTime,
    this.fixTime,
    this.serverTime,
    this.valid,
    this.latitude,
    this.longitude,
    this.altitude,
    this.speed,
    this.course,
    this.address,
    this.accuracy,
    this.attributes,
  });

  factory PositionModel.fromJson(Map<String, dynamic> json) {
    return PositionModel(
      id: json['id'] as int?,
      deviceId: json['deviceId'] as int?,
      protocol: json['protocol'] as String?,
      deviceTime: _parseDate(json['deviceTime'] as String?),
      fixTime: _parseDate(json['fixTime'] as String?),
      serverTime: _parseDate(json['serverTime'] as String?),
      valid: json['valid'] as bool?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      altitude: (json['altitude'] as num?)?.toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      course: (json['course'] as num?)?.toDouble(),
      address: json['address'] as String?,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      attributes: json['attributes'] is Map
          ? Map<String, dynamic>.from(json['attributes'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'protocol': protocol,
      'deviceTime': deviceTime?.toIso8601String(),
      'fixTime': fixTime?.toIso8601String(),
      'serverTime': serverTime?.toIso8601String(),
      'valid': valid,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'speed': speed,
      'course': course,
      'address': address,
      'accuracy': accuracy,
      'attributes': attributes,
    };
  }

  /// Traccar speed is in knots.
  double get speedKph => (speed ?? 0) * 1.852;

  /// Raw ignition from device attributes when the tracker supports it.
  bool? get ignition {
    final value = attributes?['ignition'];
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.toLowerCase().trim();
      if (lower == 'true' || lower == '1' || lower == 'on') return true;
      if (lower == 'false' || lower == '0' || lower == 'off') return false;
    }
    return null;
  }

  bool get motion {
    final value = attributes?['motion'];
    if (value is bool) return value;
    if (value is num) return value != 0;
    return speedKph > 3;
  }

  /// True when ignition attribute key exists and parses to a bool.
  bool get hasIgnitionReport => ignition != null;

  /// Engine on/off from ignition only (null when device does not report it).
  bool? get engineOn => ignition;

  bool get hasLocation =>
      latitude != null &&
      longitude != null &&
      !(latitude == 0 && longitude == 0);

  PositionModel copyWith({
    int? id,
    int? deviceId,
    String? protocol,
    DateTime? deviceTime,
    DateTime? fixTime,
    DateTime? serverTime,
    bool? valid,
    double? latitude,
    double? longitude,
    double? altitude,
    double? speed,
    double? course,
    String? address,
    double? accuracy,
    Map<String, dynamic>? attributes,
  }) {
    return PositionModel(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      protocol: protocol ?? this.protocol,
      deviceTime: deviceTime ?? this.deviceTime,
      fixTime: fixTime ?? this.fixTime,
      serverTime: serverTime ?? this.serverTime,
      valid: valid ?? this.valid,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      course: course ?? this.course,
      address: address ?? this.address,
      accuracy: accuracy ?? this.accuracy,
      attributes: attributes ?? this.attributes,
    );
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
