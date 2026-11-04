import 'package:flutter/material.dart';

import '../models/ai_review.dart';
import '../models/models.dart';
import '../services/journal_api.dart';
import 'theme.dart';
import 'widgets.dart';

/// AI journal review with the measured execution patterns above it.
///
/// The patterns are deterministic comparisons computed on the server; they are
/// shown first because they are the part a trader can check against their own
/// journal. The model's prose follows as the narrative, not as the evidence.
class AiCoachCard extends StatefulWidget {
  const AiCoachCard({
    super.key,
    required this.api,
    required this.summary,
  });

  final JournalApi api;
  final TradeSummary summary;

  @override
  State<AiCoachCard> createState() => _AiCoachCardState();
}

class _AiCoachCardState extends State<AiCoachCard> {
  bool _loading = false;
  String? _error;
  AiReviewResult? _review;
  int? _quota;
  int? _remaining;
  bool _allowed = true;

  @override
  void initState() {
    super.initState();
    _loadQuota();
  }

  Future<void> _loadQuota() async {
    try {
      final body = await widget.api.aiReviewQuota();
      if (!mounted) return;
      setState(() {
        _allowed = body['allowed'] != false;
        _quota = (body['quota'] as num?)?.toInt();
        _remaining = (body['remaining'] as num?)?.toInt();
      });
    } catch (_) {
      // The badge is optional; the review route still enforces the allowance.
    }
  }

  Future<void> _reviewJournal() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.aiReview(
        totalTrades: widget.summary.totalTrades,
        totalPnl: widget.summary.totalPnl,
        winRate: widget.summary.winRate,
      );
      if (!mounted) return;
      setState(() {
        _review = result;
        _loading = false;
      });
      await _loadQuota();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final exhausted = _allowed && _remaining != null && _remaining! <= 0;
    final disabled =
        _loading || widget.summary.totalTrades == 0 || !_allowed || exhausted;

    return FlatCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      borderColor: AppColors.primary.withAlpha(110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI trading review',
                  style: TextStyle(
                    color: AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Educational feedback grounded in your own journal statistics.',
            style:
                TextStyle(color: AppColors.faint, fontSize: 11.5, height: 1.45),
          ),
          if (_quota != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                !_allowed
                    ? 'AI reviews are not included in your plan'
                    : (exhausted
                        ? 'No reviews left this month'
                        : '${_remaining ?? 0} of $_quota reviews left this month'),
                style:
                    TextStyle(color: AppColors.muted, fontSize: kMinLabelSize),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: disabled ? null : _reviewJournal,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              icon: _loading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.text),
                      ),
                    )
                  : const Icon(Icons.auto_awesome, size: 15),
              label: Text(_loading ? 'Reviewing…' : 'Review my journal'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(
                    color: AppColors.danger, fontSize: 11.5, height: 1.45)),
          ],
          if (_review != null && !_review!.isEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_review!.confidence} confidence',
                    style: TextStyle(
                        color: AppColors.muted, fontSize: kMinLabelSize),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_review!.sampleSize} trades analysed',
                  style: TextStyle(
                      color: AppColors.faint, fontSize: kMinLabelSize),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _review!.headline,
              style: TextStyle(
                color: AppColors.text,
                fontSize: 12.5,
                height: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_review!.insights.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'EXECUTION PATTERNS',
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: kMinLabelSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              for (final insight in _review!.insights)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: insight.isRisk
                              ? AppColors.danger
                              : AppColors.success,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          insight.summary,
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11.5,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                'Measured from your own trades; each pattern needs at least six trades in the group.',
                style: TextStyle(
                    color: AppColors.faint,
                    fontSize: kMinLabelSize,
                    height: 1.4),
              ),
            ],
            _findings('Strengths', _review!.strengths, AppColors.success),
            _findings('Risks', _review!.risks, AppColors.danger),
            _findings('Actions', _review!.actions, AppColors.primary),
            const SizedBox(height: 6),
            Text(
              'AI feedback is educational and is not financial advice.',
              style: TextStyle(
                  color: AppColors.faint, fontSize: kMinLabelSize, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _findings(String label, List<AiFinding> items, Color color) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: kMinLabelSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11.5,
                    height: 1.5,
                  ),
                  children: [
                    TextSpan(
                      text: '${item.title} — ',
                      style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(text: item.detail),
                    if (item.evidence != null && item.evidence!.isNotEmpty)
                      TextSpan(
                        text: '\nevidence: ${item.evidence}',
                        style: TextStyle(
                            color: AppColors.faint, fontSize: kMinLabelSize),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
