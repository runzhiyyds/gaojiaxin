class MallGoodModel {
  MallGoodModel({
    required this.id,
    required this.coupleSpaceId,
    required this.ownerId,
    required this.name,
    this.description,
    required this.pointsRequired,
    this.stock,
    this.imageUrl,
    required this.sortOrder,
    this.category,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String coupleSpaceId;
  /// 商品归属用户（谁添加的），情侣空间内双方均可管理
  final String ownerId;
  final String name;
  final String? description;
  final int pointsRequired;
  final int? stock;
  final String? imageUrl;
  final int sortOrder;
  /// 品类，如：知识付费、科技赋能、虚拟类、书籍类、礼物
  final String? category;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isUnlimited => stock == null;

  factory MallGoodModel.fromJson(Map<String, dynamic> json) {
    return MallGoodModel(
      id: json['id'] as String,
      coupleSpaceId: json['couple_space_id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      pointsRequired: (json['points_required'] as num).toInt(),
      stock: json['stock'] != null ? (json['stock'] as num).toInt() : null,
      imageUrl: json['image_url'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      category: json['category'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'couple_space_id': coupleSpaceId,
        'owner_id': ownerId,
        'name': name,
        'description': description,
        'points_required': pointsRequired,
        'stock': stock,
        'image_url': imageUrl,
        'sort_order': sortOrder,
        'category': category,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
