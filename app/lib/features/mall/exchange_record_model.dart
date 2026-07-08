class ExchangeRecordModel {
  ExchangeRecordModel({
    required this.id,
    required this.coupleSpaceId,
    required this.userId,
    required this.mallGoodId,
    required this.pointsSpent,
    required this.createdAt,
    this.goodName,
    this.fulfilledAt,
    this.fulfilledBy,
  });

  final String id;
  final String coupleSpaceId;
  final String userId;
  final String mallGoodId;
  final int pointsSpent;
  final DateTime createdAt;
  final String? goodName;
  /// 对方点击「满足TA」的时间
  final DateTime? fulfilledAt;
  /// 点击「满足TA」的用户 id
  final String? fulfilledBy;

  factory ExchangeRecordModel.fromJson(Map<String, dynamic> json) {
    return ExchangeRecordModel(
      id: json['id'] as String,
      coupleSpaceId: json['couple_space_id'] as String,
      userId: json['user_id'] as String,
      mallGoodId: json['mall_good_id'] as String,
      pointsSpent: (json['points_spent'] as num).toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      goodName: json['good_name'] as String?,
      fulfilledAt: json['fulfilled_at'] != null
          ? DateTime.parse(json['fulfilled_at'] as String)
          : null,
      fulfilledBy: json['fulfilled_by'] as String?,
    );
  }
}
