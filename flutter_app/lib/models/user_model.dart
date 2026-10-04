class User {
  final String id;
  final String name;
  final String role;
  final String language;
  final String mobile;
  final String? profileImage;
  final DateTime createdAt;

  /// Shop / branch this user works at (server-assigned; 'main' = default).
  final String branchId;
  final String branchName;

  /// The billing counter this user normally works at ('' = none); it belongs to [branchId].
  final String counterId;
  final String counterName;

  User({
    required this.id,
    required this.name,
    required this.role,
    required this.language,
    required this.mobile,
    this.profileImage,
    required this.createdAt,
    this.branchId = 'main',
    this.branchName = 'Main branch',
    this.counterId = '',
    this.counterName = '',
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      role: json['role'] ?? 'staff',
      language: json['language'] ?? 'en',
      mobile: json['mobile'] ?? '',
      profileImage: json['profileImage'],
      branchId: json['branchId'] ?? 'main',
      branchName: json['branchName'] ?? 'Main branch',
      counterId: (json['counterId'] ?? '').toString(),
      counterName: (json['counterName'] ?? '').toString(),
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
      'branchId': branchId,
      'branchName': branchName,
      'counterId': counterId,
      'counterName': counterName,
      if (profileImage != null) 'profileImage': profileImage,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  bool get isAdmin => role == 'admin';
  bool get isOwner => role == 'owner';
  bool get isManager => role == 'manager';
  bool get isStaff => role == 'staff';
  bool get isViewer => role == 'viewer';

  // Admin and Owner always have full access — used throughout the app as
  // the "bypass every permission check" shortcut.
  bool get hasFullAccess => isAdmin || isOwner;
}
