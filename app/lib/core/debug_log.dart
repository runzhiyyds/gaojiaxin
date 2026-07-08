import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const _kEndpoint =
    'http://127.0.0.1:7243/ingest/65999639-609c-442e-8260-7118848961b1';

/// 调试用：将一条 NDJSON 日志 POST 到调试服务，并 debugPrint 以便真机时从控制台采集
void debugLog({
  required String location,
  required String message,
  Map<String, dynamic>? data,
  String? hypothesisId,
  String? runId,
}) {
  final payload = <String, dynamic>{
    'location': location,
    'message': message,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  if (data != null) payload['data'] = data;
  if (hypothesisId != null) payload['hypothesisId'] = hypothesisId;
  if (runId != null) payload['runId'] = runId;

  final body = jsonEncode(payload);
  if (kDebugMode) {
    debugPrint('DEBUG_LOG $body');
  }
  http
      .post(
        Uri.parse(_kEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: body,
      )
      .timeout(const Duration(seconds: 2))
      .catchError((_) => Future<http.Response>.value(http.Response('', 500)));
}
