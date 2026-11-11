import 'package:flutter/material.dart';

import '../services/journal_api.dart';
import '../ui/prop_compliance.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// The prop-firm evaluation, on its own screen.
///
/// It used to be a card on the desk, between the equity curve and the journal
/// feed, where a rule about to break was one scroll away from being missed. A
/// dedicated screen gives the headroom the whole width — and a place for the
/// extra rules (consistency, payout targets) that a monitor card could not hold.
class PropFirmScreen extends StatelessWidget {
  const PropFirmScreen({super.key, required this.api});

  final JournalApi api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Prop firm simulation')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
        children: [
          FlatCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Evaluation',
                        style: TextStyle(
                          color: AppColors.text,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Set the rules your firm gave you. Every number below is '
                  'computed from the trades in this journal, so a breach shows '
                  'up here before the firm emails you about it.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          PropComplianceCard(api: api),
        ],
      ),
    );
  }
}
