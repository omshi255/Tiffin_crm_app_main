class LeaveRequestModel {
  final String id;
  final String requestedBy;
  final String? customerId;
  final String? customerName;
  final String? vendorId;
  final String? subscriptionId;
  final String mealType;
  final DateTime date;
  final String? reason;
  final String? notes;
  final String status;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;

  LeaveRequestModel({
    required this.id,
    required this.requestedBy,
    this.customerId,
    this.customerName,
    this.vendorId,
    this.subscriptionId,
    required this.mealType,
    required this.date,
    this.reason,
    this.notes,
    required this.status,
    this.approvedBy,
    this.approvedAt,
    this.rejectedAt,
  });

  factory LeaveRequestModel.fromJson(Map<String, dynamic> json) {
    String? custName = json['customerName']?.toString();
    String? custId;
    if (json['customerId'] != null) {
      if (json['customerId'] is Map) {
        custName = (json['customerId'] as Map)['name']?.toString() ?? custName;
        custId = (json['customerId'] as Map)['_id']?.toString();
      } else {
        custId = json['customerId']?.toString();
      }
    }

    String? vId;
    if (json['vendorId'] != null) {
      if (json['vendorId'] is Map) {
        vId = (json['vendorId'] as Map)['_id']?.toString();
      } else {
        vId = json['vendorId']?.toString();
      }
    }

    String? subId;
    if (json['subscriptionId'] != null) {
      if (json['subscriptionId'] is Map) {
        subId = (json['subscriptionId'] as Map)['_id']?.toString();
      } else {
        subId = json['subscriptionId']?.toString();
      }
    }

    String? appBy;
    if (json['approvedBy'] != null) {
      if (json['approvedBy'] is Map) {
        appBy = (json['approvedBy'] as Map)['_id']?.toString();
      } else {
        appBy = json['approvedBy']?.toString();
      }
    }

    DateTime parsedDate = DateTime.now();
    try {
      final rawDate = json['leaveDate'] ?? json['date'];
      if (rawDate != null) {
        parsedDate = DateTime.parse(rawDate.toString());
      }
    } catch (_) {}

    DateTime? appAt;
    try {
      if (json['approvedAt'] != null) {
        appAt = DateTime.parse(json['approvedAt'].toString());
      }
    } catch (_) {}

    DateTime? rejAt;
    try {
      if (json['rejectedAt'] != null) {
        rejAt = DateTime.parse(json['rejectedAt'].toString());
      }
    } catch (_) {}

    return LeaveRequestModel(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      requestedBy: json['requestedBy']?.toString() ?? 'Customer',
      customerId: custId,
      customerName: custName,
      vendorId: vId,
      subscriptionId: subId,
      mealType: json['mealType']?.toString() ?? 'lunch',
      date: parsedDate,
      reason: json['reason']?.toString(),
      notes: json['notes']?.toString(),
      status: json['status']?.toString() ?? 'Pending',
      approvedBy: appBy,
      approvedAt: appAt,
      rejectedAt: rejAt,
    );
  }
}
