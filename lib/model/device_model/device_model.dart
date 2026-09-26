class DeviceModel {
  int? id;
  String? name;
  String? uniqueId;
  String? status;
  DateTime? lastUpdate;
  int? positionId;
  String? phone;
  String? model;
  String? contact;
  String? category;
  bool? disabled;
  int? groupId;
  Map<String, dynamic>? attributes;

  DeviceModel({
    this.id,
    this.name,
    this.uniqueId,
    this.status,
    this.lastUpdate,
    this.positionId,
    this.phone,
    this.model,
    this.contact,
    this.category,
    this.disabled,
    this.groupId,
    this.attributes,
  });

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'] as int?,
      name: json['name'] as String?,
      uniqueId: json['uniqueId'] as String?,
      status: json['status'] as String?,
      lastUpdate: _parseDate(json['lastUpdate'] as String?),
      positionId: json['positionId'] as int?,
      phone: json['phone'] as String?,
      model: json['model'] as String?,
      contact: json['contact'] as String?,
      category: json['category'] as String?,
      disabled: json['disabled'] as bool?,
      groupId: json['groupId'] as int?,
      attributes: json['attributes'] is Map
          ? Map<String, dynamic>.from(json['attributes'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'uniqueId': uniqueId,
      'status': status,
      'lastUpdate': lastUpdate?.toIso8601String(),
      'positionId': positionId,
      'phone': phone,
      'model': model,
      'contact': contact,
      'category': category,
      'disabled': disabled,
      'groupId': groupId,
      'attributes': attributes,
    };
  }

  DeviceModel copyWith({
    int? id,
    String? name,
    String? uniqueId,
    String? status,
    DateTime? lastUpdate,
    int? positionId,
    String? phone,
    String? model,
    String? contact,
    String? category,
    bool? disabled,
    int? groupId,
    Map<String, dynamic>? attributes,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      uniqueId: uniqueId ?? this.uniqueId,
      status: status ?? this.status,
      lastUpdate: lastUpdate ?? this.lastUpdate,
      positionId: positionId ?? this.positionId,
      phone: phone ?? this.phone,
      model: model ?? this.model,
      contact: contact ?? this.contact,
      category: category ?? this.category,
      disabled: disabled ?? this.disabled,
      groupId: groupId ?? this.groupId,
      attributes: attributes ?? this.attributes,
    );
  }

  /// Cartag custom flag: device supports engine Stop / Resume.
  bool get engineKillCapable {
    final v = attributes?['engineKillCapable'];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes';
    }
    return false;
  }

  /// Live immobilizer from position attrs (`true` = cut / OFF).
  static bool? blockedFrom(Map<String, dynamic>? attrs) {
    if (attrs == null || !attrs.containsKey('blocked')) return null;
    final v = attrs['blocked'];
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.toLowerCase().trim();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return null;
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
