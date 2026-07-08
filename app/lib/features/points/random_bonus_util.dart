import 'dart:math';

/// 心意值内部单位：1 单位 = 0.1 心意值，便于支持一位小数。
const int kHeartValueScale = 10;

/// 普通模式三档：小额 1~2、中额 3~5、大额 5~10（展示值）；内部存为 [10,20]、[30,50]、[50,100]。
enum HeartAmountTier {
  small,
  medium,
  large,
}

extension HeartAmountTierExt on HeartAmountTier {
  String get label {
    switch (this) {
      case HeartAmountTier.small:
        return '小额';
      case HeartAmountTier.medium:
        return '中额';
      case HeartAmountTier.large:
        return '大额';
    }
  }

  (int minTenths, int maxTenths) get rangeTenths {
    switch (this) {
      case HeartAmountTier.small:
        return (10, 20); // 1.0 ~ 2.0
      case HeartAmountTier.medium:
        return (30, 50); // 3.0 ~ 5.0
      case HeartAmountTier.large:
        return (50, 100); // 5.0 ~ 10.0
    }
  }
}

/// 在指定档位内随机生成心意值（内部单位，十分之一）。
int sampleHeartValue(HeartAmountTier tier, {Random? random}) {
  final rnd = random ?? Random();
  final (minTenths, maxTenths) = tier.rangeTenths;
  return minTenths + rnd.nextInt(maxTenths - minTenths + 1);
}

/// 将内部单位转为展示用一位小数字符串。
String formatHeartValueDisplay(int tenths) {
  return (tenths / kHeartValueScale).toStringAsFixed(1);
}

/// 记一笔时给记分者的随机奖励：0.5X ~ 10X，截断指数分布（金额越大概率越小），
/// 并缩放使长期 E(随机奖励) ≈ 1.05X，弱化“薅羊毛”感。
/// [x] 为本笔给对方的积分（内部单位，十分之一）。
int sampleRandomBonus(int x, {double lambda = 0.4, Random? random}) {
  if (x < 1) return 0;
  final rnd = random ?? Random();
  final a = 0.5 * x;
  final b = 10.0 * x;
  if (b <= a) return a.ceil().clamp(0, 10 * x);
  final span = b - a;
  final expTerm = 1.0 - exp(-lambda * span);
  if (expTerm <= 0) return a.ceil();
  final u = rnd.nextDouble();
  final v = a - log(1.0 - u * expTerm) / lambda;
  final expL = exp(-lambda * span);
  final eV = a + 1 / lambda - span * expL / (1 - expL);
  final targetMean = 1.05 * x;
  final scaled = (eV > 0) ? v * targetMean / eV : targetMean;
  final low = a.ceil();
  final high = (10 * x).floor();
  return scaled.round().clamp(low, high);
}
