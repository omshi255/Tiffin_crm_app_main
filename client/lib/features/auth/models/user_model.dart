class UserModel {
  const UserModel({
    required this.id,
    required this.phone,
    required this.role,
    this.name = '',
    this.businessName = '',
    this.ownerName = '',
    this.email = '',
    this.logoUrl = '',
    this.city = '',
    this.address = '',
    this.upiId = '',
    this.fcmToken = '',
    this.isActive = true,
    this.hasDashboard = false,
  });

  final String id;
  final String phone;
  final String role;
  final String name;
  final String businessName;
  final String ownerName;
  final String email;
  final String logoUrl;
  final String city;
  final String address;
  final String upiId;
  final String fcmToken;
  final bool isActive;
  /// Vendor already has customers, plans, or subscriptions saved.
  final bool hasDashboard;

  /// Open the saved vendor dashboard when profile names exist or business data is already stored.
  bool get isVendorProfileComplete =>
      hasDashboard ||
      (businessName.trim().isNotEmpty && ownerName.trim().isNotEmpty);

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      role: json['role']?.toString() ?? 'vendor',
      name: json['name']?.toString() ?? '',
      businessName: json['businessName']?.toString() ?? '',
      ownerName: json['ownerName']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      logoUrl: json['logoUrl']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      upiId: json['upiId']?.toString() ?? '',
      fcmToken: json['fcmToken']?.toString() ?? '',
      isActive: json['isActive'] as bool? ?? true,
      hasDashboard: json['hasDashboard'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (name.isNotEmpty) 'name': name,
      if (businessName.isNotEmpty) 'businessName': businessName,
      if (ownerName.isNotEmpty) 'ownerName': ownerName,
      if (email.isNotEmpty) 'email': email,
      if (logoUrl.isNotEmpty) 'logoUrl': logoUrl,
      if (city.isNotEmpty) 'city': city,
      if (address.isNotEmpty) 'address': address,
      if (upiId.isNotEmpty) 'upiId': upiId,
      'isActive': isActive,
      if (fcmToken.isNotEmpty) 'fcmToken': fcmToken,
    };
  }
}
