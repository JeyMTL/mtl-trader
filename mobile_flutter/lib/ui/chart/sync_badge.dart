import 'package:flutter/material.dart';

import '../theme.dart';

/// What the account copy of a chart's objects is doing.
///
/// `saved` and `failed` are the two a trader can read without opening anything:
/// the levels are on the account, or they are not and only live on this device.
enum ChartSyncState { idle, syncing, saved, failed }

/// One small badge for the shared copy of the chart's objects.
///
/// Nothing while idle, a spinner while reconciling, a tick for a moment after a
/// save, and a cloud with a line through it when the share failed — tapping that
/// one says why.
///
/// It lives outside the chart screen because it is drawn twice: in the app bar
/// with the app palette, and in fullscreen over the trader's own chart theme.
/// Both cases pass their own colours, and the widget on its own is what the
/// widget test pins at the narrowest phone size.
class ChartSyncBadge extends StatelessWidget {
  const ChartSyncBadge({
    super.key,
    required this.state,
    required this.onExplain,
    this.muted,
    this.savedInk,
    this.failedInk,
  });

  final ChartSyncState state;

  /// Called when the failed badge is tapped, to say what went wrong.
  final VoidCallback onExplain;

  /// Colours for the fullscreen chart, which carries its own theme. Null means
  /// the app palette.
  final Color? muted;
  final Color? savedInk;
  final Color? failedInk;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case ChartSyncState.idle:
        return const SizedBox.shrink();
      case ChartSyncState.syncing:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            child: SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: muted ?? AppColors.muted,
              ),
            ),
          ),
        );
      case ChartSyncState.saved:
        return Tooltip(
          message: 'Levels saved to your account',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(
              Icons.cloud_done_outlined,
              size: 18,
              color: savedInk ?? AppColors.primaryLight,
            ),
          ),
        );
      case ChartSyncState.failed:
        return IconButton(
          tooltip: 'Levels could not be shared',
          onPressed: onExplain,
          icon: Icon(
            Icons.cloud_off_outlined,
            size: 18,
            color: failedInk ?? AppColors.danger,
          ),
        );
    }
  }
}
