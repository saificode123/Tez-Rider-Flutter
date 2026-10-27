import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_motion.dart';

class _ShimmerBase extends StatelessWidget {
  final Widget child;
  const _ShimmerBase({required this.child});

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) {
      return ColorFiltered(
        colorFilter: const ColorFilter.mode(Color(0xFFE8E8E8), BlendMode.srcIn),
        child: child,
      );
    }
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8E8E8),
      highlightColor: const Color(0xFFF5F5F5),
      child: child,
    );
  }
}

Widget _box({double? width, double? height, double radius = 8}) {
  return Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

class ShimmerBanner extends StatelessWidget {
  const ShimmerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return _ShimmerBase(
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}

class ShimmerCategoryRow extends StatelessWidget {
  const ShimmerCategoryRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 6,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _ShimmerBase(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _box(width: 62, height: 62, radius: 18),
                const SizedBox(height: 6),
                _box(width: 50, height: 10, radius: 5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ShimmerCard extends StatelessWidget {
  const ShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _ShimmerBase(
        child: Row(
          children: [
            _box(width: 52, height: 52, radius: 14),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _box(height: 14, radius: 6),
                  const SizedBox(height: 8),
                  _box(width: 140, height: 11, radius: 5),
                  const SizedBox(height: 8),
                  _box(width: 90, height: 11, radius: 5),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _box(width: 64, height: 32, radius: 10),
          ],
        ),
      ),
    );
  }
}

class ShimmerTrendingCard extends StatelessWidget {
  const ShimmerTrendingCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: _ShimmerBase(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _box(height: 110, radius: 14),
            const SizedBox(height: 12),
            _box(height: 14, radius: 6),
            const SizedBox(height: 8),
            _box(width: 90, height: 11, radius: 5),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _box(width: 60, height: 13, radius: 5),
                _box(width: 36, height: 13, radius: 5),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ShimmerMetricGrid extends StatelessWidget {
  const ShimmerMetricGrid({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.55,
      ),
      itemCount: 4,
      itemBuilder: (_, __) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _ShimmerBase(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _box(width: 34, height: 34, radius: 10),
                  _box(width: 50, height: 22, radius: 8),
                ],
              ),
              const Spacer(),
              _box(width: 80, height: 20, radius: 6),
              const SizedBox(height: 6),
              _box(width: 100, height: 11, radius: 5),
            ],
          ),
        ),
      ),
    );
  }
}

class ShimmerListItems extends StatelessWidget {
  final int count;
  const ShimmerListItems({super.key, this.count = 3});

  @override
  Widget build(BuildContext context) {
    return Column(children: List.generate(count, (_) => const ShimmerCard()));
  }
}
