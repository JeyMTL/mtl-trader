import 'package:flutter/material.dart';

import 'theme.dart';

/// Sweeps a highlight across its child. Put plain [SkeletonBox]es inside so the
/// gradient paints only where the skeleton exists.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final travel = rect.width * 2;
            return LinearGradient(
              colors: [
                AppColors.surfaceAlt,
                AppColors.borderStrong,
                AppColors.surfaceAlt,
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(
              Rect.fromLTWH(
                rect.left - travel + travel * 2 * _controller.value,
                rect.top,
                rect.width + travel,
                rect.height,
              ),
            );
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// One grey block in a loading skeleton.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 12,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A card-shaped skeleton with a title line and a couple of body lines.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 92, this.padding = 14});

  final double height;
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBox(width: 90, height: 9),
          SizedBox(height: 12),
          SkeletonBox(width: 150, height: 18),
          SizedBox(height: 10),
          SkeletonBox(width: double.infinity, height: 9),
          SizedBox(height: 6),
          SkeletonBox(width: 180, height: 9),
        ],
      ),
    );
  }
}
