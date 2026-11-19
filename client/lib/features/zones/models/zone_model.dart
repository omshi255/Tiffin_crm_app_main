class ZoneModel {
  final String id;
  final String name;
  final String description;
  final String color;
  final bool isActive;
  final int customerCount;

  ZoneModel({
    required this.id,
    required this.name,
    this.description = '',
    this.color = '',
    this.isActive = true,
    this.customerCount = 0,
  });

  factory ZoneModel.fromJson(Map<String, dynamic> json) {
    return ZoneModel(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      color: (json['color'] ?? '').toString(),
      isActive: json['isActive'] == null ? true : json['isActive'] == true,
      customerCount: json['customerCount'] is num
          ? (json['customerCount'] as num).toInt()
          : int.tryParse('${json['customerCount']}') ?? 0,
    );
  }

  Map<String, dynamic> toCreateJson() => {
        'name': name,
        if (description.isNotEmpty) 'description': description,
        if (color.isNotEmpty) 'color': color,
        'isActive': isActive,
      };

  Map<String, dynamic> toUpdateJson() => {
        'name': name,
        'description': description,
        'color': color,
        'isActive': isActive,
      };
}

