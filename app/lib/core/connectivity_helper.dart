import 'package:connectivity_plus/connectivity_plus.dart';

/// 检测当前是否无网络（用于失败时提示「请检查网络」）
Future<bool> isOffline() async {
  final result = await Connectivity().checkConnectivity();
  if (result.isEmpty) return true;
  return result.every((r) => r == ConnectivityResult.none);
}
