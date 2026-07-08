class PointDepositModel {
  PointDepositModel({
    required this.id,
    required this.coupleSpaceId,
    required this.userId,
    required this.productType,
    required this.principal,
    required this.interestRate,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String coupleSpaceId;
  final String userId;
  final String productType;
  final int principal;
  final double interestRate;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final DateTime createdAt;

  bool get isActive => status == 'active';
  bool get isRedeemed => status == 'redeemed';
  bool get isRedeemedEarly => status == 'redeemed_early';
  bool get isMatured => DateTime.now().isAfter(endAt) || !endAt.isAfter(DateTime.now());

  factory PointDepositModel.fromJson(Map<String, dynamic> json) {
    return PointDepositModel(
      id: json['id'] as String,
      coupleSpaceId: json['couple_space_id'] as String,
      userId: json['user_id'] as String,
      productType: json['product_type'] as String,
      principal: (json['principal'] as num).toInt(),
      interestRate: (json['interest_rate'] as num).toDouble(),
      startAt: DateTime.parse(json['start_at'] as String),
      endAt: DateTime.parse(json['end_at'] as String),
      status: json['status'] as String? ?? 'active',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// 定期产品类型与展示
enum DepositProductType {
  quarter('quarter', '一季度', 0.10),
  halfYear('half_year', '半年', 0.15),
  oneYear('one_year', '一年', 0.20),
  twoYears('two_years', '两年', 0.30);

  const DepositProductType(this.value, this.label, this.rate);
  final String value;
  final String label;
  final double rate;

  static DepositProductType? fromString(String? v) {
    for (final e in DepositProductType.values) {
      if (e.value == v) return e;
    }
    return null;
  }

  /// 期限对应的月数（用于计算 end_at）
  int get months {
    switch (this) {
      case DepositProductType.quarter:
        return 3;
      case DepositProductType.halfYear:
        return 6;
      case DepositProductType.oneYear:
        return 12;
      case DepositProductType.twoYears:
        return 24;
    }
  }
}
