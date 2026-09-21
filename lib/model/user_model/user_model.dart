class UserModel {
  int? id;
  String? name;
  String? email;
  String? phone;
  bool? administrator;
  bool? readonly;
  bool? disabled;
  Map<String, dynamic>? attributes;

  UserModel({
    this.id,
    this.name,
    this.email,
    this.phone,
    this.administrator,
    this.readonly,
    this.disabled,
    this.attributes,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int?,
      name: json['name'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      administrator: json['administrator'] as bool?,
      readonly: json['readonly'] as bool?,
      disabled: json['disabled'] as bool?,
      attributes: json['attributes'] is Map
          ? Map<String, dynamic>.from(json['attributes'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'administrator': administrator,
      'readonly': readonly,
      'disabled': disabled,
      'attributes': attributes,
    };
  }
}
