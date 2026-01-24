class User {
  final String id;
  final String name;
  final String role;
  final String language;
  final String mobile;
  final String? profileImage;
  final DateTime createdAt;

  User({
    required this.id,
    required this.name,
    required this.role,
    required this.language,
    required this.mobile,
    this.profileImage,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      role: json['role'] ?? 'staff',
      language: json['language'] ?? 'en',
      mobile: json['mobile'] ?? '',
      profileImage: json['profileImage'],
      createdAt: json['createdAt'] != null 
          ? DateTime.parse(json['createdAt']) 
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'role': role,
      'language': language,
      'mobile': mobile,
      if (profileImage != null) 'profileImage': profileImage,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  bool get isAdmin => role == 'admin';
  bool get isStaff => role == 'staff';
  bool get isViewer => role == 'viewer';
}
