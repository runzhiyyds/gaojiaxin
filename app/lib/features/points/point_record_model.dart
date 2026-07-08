import 'package:love_story/features/points/love_dimension.dart';
class PointRecordModel {
  PointRecordModel({
    required this.id,
    required this.coupleSpaceId,
    required this.userId,
    required this.pointItemId,
    required this.points,
    required this.recordAt,
    this.note,
    this.loveDimension,
    DateTime? createdAt,
    this.editUsedAt,
    this.recipientComment,
    this.recipientCommentAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String coupleSpaceId;
  final String userId;
  final String pointItemId;
  final int points;
  final DateTime recordAt;
  final String? note;
  final DateTime createdAt;
  /// 非空表示已使用「一次编辑/删除」机会，不可再改
  final DateTime? editUsedAt;
  final LoveDimension? loveDimension;
  /// 收件人（user_id）对这条心意的回应正文
  final String? recipientComment;
  /// 收件人写下/更新回应的时间
  final DateTime? recipientCommentAt;

  bool get canEditOnce => editUsedAt == null;

  bool get hasRecipientComment =>
      recipientComment != null && recipientComment!.trim().isNotEmpty;

  factory PointRecordModel.fromJson(Map<String, dynamic> json) {
    return PointRecordModel(
      id: json['id'] as String,
      coupleSpaceId: json['couple_space_id'] as String,
      userId: json['user_id'] as String,
      pointItemId: json['point_item_id'] as String,
      points: (json['points'] as num).toInt(),
      recordAt: DateTime.parse(json['record_at'] as String),
      note: json['note'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      editUsedAt: json['edit_used_at'] != null
          ? DateTime.parse(json['edit_used_at'] as String)
          : null,
      loveDimension: LoveDimension.fromDb(json['love_dimension'] as String?),
      recipientComment: json['recipient_comment'] as String?,
      recipientCommentAt: json['recipient_comment_at'] != null
          ? DateTime.parse(json['recipient_comment_at'] as String)
          : null,
    );
  }
}
