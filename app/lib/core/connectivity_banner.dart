import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// 在无网络时于子组件顶部显示「当前无网络」条
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key, required this.child});

  final Widget child;

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _check();
    Connectivity().onConnectivityChanged.listen((_) => _check());
  }

  Future<void> _check() async {
    final result = await Connectivity().checkConnectivity();
    final offline = result.isEmpty ||
        result.every((r) => r == ConnectivityResult.none);
    if (mounted && _offline != offline) {
      setState(() => _offline = offline);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_offline)
          Material(
            color: Colors.orange.shade700,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      '当前无网络',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
