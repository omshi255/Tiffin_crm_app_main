class LeaveRequestModel {
  final String id;
  final DateTime date;
  final String? customerName;
  final String mealType;

  LeaveRequestModel({
    required this.id,
    required this.date,
    this.customerName,
    required this.mealType,
  });

  factory LeaveRequestModel.fromJson(Map<String, dynamic> json) {
    return LeaveRequestModel(
      id: json['_id'] as String? ?? json['id'] as String? ?? '',
      date: json['date'] != null
          ? DateTime.parse(json['date'] as String)
          : DateTime.now(),
      customerName: json['customerName'] as String?,
      mealType: json['mealType'] as String? ?? 'lunch',
    );
  }
}
