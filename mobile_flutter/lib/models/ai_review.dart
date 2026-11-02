/// Shapes returned by `POST /api/ai/review`.
///
/// `insights` is the execution-coach payload: deterministic comparisons computed
/// on the server from the trader's own trades. It is displayed verbatim because
/// the sentence already carries the measured number — paraphrasing it on the
/// device would be the one place a number could drift.
class CoachInsight {
  const CoachInsight({
    required this.label,
    required this.summary,
    required this.tone,
    required this.trades,
  });

  final String label;
  final String summary;

  /// `risk` or `strength`.
  final String tone;

  final int trades;

  bool get isRisk => tone == 'risk';

  factory CoachInsight.fromMap(Map<String, dynamic> map) => CoachInsight(
        label: map['label']?.toString() ?? '—',
        summary: map['summary']?.toString() ?? '',
        tone: map['tone']?.toString() ?? 'risk',
        trades: (map['trades'] as num?)?.toInt() ?? 0,
      );
}

class AiFinding {
  const AiFinding({required this.title, required this.detail, this.evidence});

  final String title;
  final String detail;
  final String? evidence;

  factory AiFinding.fromMap(Map<String, dynamic> map) => AiFinding(
        title: map['title']?.toString() ?? '',
        detail: map['detail']?.toString() ?? '',
        evidence: map['evidence']?.toString(),
      );
}

class AiReviewResult {
  const AiReviewResult({
    required this.headline,
    required this.confidence,
    required this.sampleSize,
    required this.strengths,
    required this.risks,
    required this.actions,
    required this.insights,
  });

  final String headline;
  final String confidence;
  final int sampleSize;
  final List<AiFinding> strengths;
  final List<AiFinding> risks;
  final List<AiFinding> actions;
  final List<CoachInsight> insights;

  bool get isEmpty => headline.isEmpty;

  static List<AiFinding> _findings(dynamic value) {
    if (value is! List) return const <AiFinding>[];
    return value
        .whereType<Map>()
        .map((row) => AiFinding.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  factory AiReviewResult.fromBody(Map<String, dynamic> body) {
    final review = body['review'];
    final map = review is Map ? Map<String, dynamic>.from(review) : const <String, dynamic>{};
    final rawInsights = body['insights'];
    return AiReviewResult(
      headline: map['headline']?.toString() ?? '',
      confidence: map['confidence']?.toString() ?? 'low',
      sampleSize: (map['sampleSize'] as num?)?.toInt() ?? 0,
      strengths: _findings(map['strengths']),
      risks: _findings(map['risks']),
      actions: _findings(map['actions']),
      insights: rawInsights is List
          ? rawInsights
              .whereType<Map>()
              .map((row) => CoachInsight.fromMap(Map<String, dynamic>.from(row)))
              .toList()
          : const <CoachInsight>[],
    );
  }
}
