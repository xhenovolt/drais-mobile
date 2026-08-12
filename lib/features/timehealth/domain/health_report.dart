/// The Attendance Health Score, ported from the platform.
///
/// ## This is a transcription, not a design
///
/// Every number in this file — the 90/70 status bands, each check's weight,
/// each score ladder — is copied from `src/lib/attendance/health.ts`. They are
/// not defaults chosen here and they must not be "improved" locally. If mobile
/// scored a school 82 while the web app scored it 91, an operator looking at
/// two screens would be told two different things about one school, and would
/// have no way to know which to believe.
///
/// When the platform changes a threshold, change it here and nowhere else.
///
/// [computeOverallHealth] is pure, exactly as its TypeScript counterpart is,
/// and is unit-tested against the same cases.
library;

/// How a check came out.
enum HealthStatus {
  /// 90 and above.
  healthy('healthy', 'Healthy'),

  /// 70 to 89.
  degraded('degraded', 'Degraded'),

  /// Below 70.
  critical('critical', 'Critical'),

  /// The check itself failed, so it says nothing either way.
  ///
  /// Deliberately distinct from `critical`: a check that could not run is not
  /// evidence of a problem, and is excluded from the rollup rather than
  /// dragging the score to zero.
  unknown('unknown', 'Unknown');

  const HealthStatus(this.wireValue, this.label);

  /// The platform's string form.
  final String wireValue;

  /// Label for the UI.
  final String label;
}

/// Maps a score to a band.
///
/// `score >= 90 ? healthy : score >= 70 ? degraded : critical` — health.ts:33.
HealthStatus statusOf(num score) {
  if (score >= 90) return HealthStatus.healthy;
  if (score >= 70) return HealthStatus.degraded;
  return HealthStatus.critical;
}

/// One scored check somewhere in the attendance pipeline.
class HealthCheck {
  /// Creates a check with an explicit status.
  ///
  /// Prefer [HealthCheck.scored] — this is for [HealthCheck.unknown] and for
  /// reconstructing a check from stored data.
  const HealthCheck({
    required this.key,
    required this.label,
    required this.weight,
    required this.score,
    required this.status,
    required this.detail,
    this.recommendation,
  });

  /// Creates a check from a raw score, clamping and banding it.
  ///
  /// Mirrors the `check()` helper: the score is rounded then clamped to 0–100,
  /// but the **status is banded from the unclamped score**, as in health.ts.
  /// The distinction only shows up for out-of-range inputs, and it is kept so
  /// the two implementations cannot drift.
  factory HealthCheck.scored({
    required String key,
    required String label,
    required double weight,
    required num score,
    required String detail,
    String? recommendation,
  }) => HealthCheck(
    key: key,
    label: label,
    weight: weight,
    score: score.round().clamp(0, 100),
    status: statusOf(score),
    detail: detail,
    recommendation: recommendation,
  );

  /// Creates a check that could not be run.
  factory HealthCheck.unknown({
    required String key,
    required String label,
    required double weight,
    required String why,
  }) => HealthCheck(
    key: key,
    label: label,
    weight: weight,
    score: 0,
    status: HealthStatus.unknown,
    detail: why,
  );

  /// Stable identifier, e.g. `devices`, `heartbeat`, `identity`.
  final String key;

  /// Human label.
  final String label;

  /// How much this check counts toward the overall score.
  final double weight;

  /// 0–100.
  final int score;

  /// The band, or [HealthStatus.unknown].
  final HealthStatus status;

  /// What was measured, in words.
  final String detail;

  /// What to do about it, when there is something to do.
  final String? recommendation;
}

/// The rolled-up report.
class HealthReport {
  /// Creates a report.
  const HealthReport({
    required this.score,
    required this.status,
    required this.checks,
    required this.recommendations,
    this.generatedAt,
  });

  /// Weighted overall score, 0–100.
  final int score;

  /// The overall band.
  final HealthStatus status;

  /// Every check, in the order they were run.
  final List<HealthCheck> checks;

  /// What to do, worst score first.
  final List<String> recommendations;

  /// When this was computed.
  final DateTime? generatedAt;

  /// Checks that contributed to [score].
  List<HealthCheck> get usableChecks => checks
      .where((HealthCheck c) => c.status != HealthStatus.unknown)
      .toList(growable: false);

  /// Checks that could not be run.
  List<HealthCheck> get failedChecks => checks
      .where((HealthCheck c) => c.status == HealthStatus.unknown)
      .toList(growable: false);
}

/// Rolls checks up into a report. Pure.
///
/// Faithful to `computeOverallHealth` in health.ts:
///
/// * `unknown` checks are excluded from the average — a check that could not
///   run must not be scored as a failure.
/// * The weight total falls back to 1 when every check is unknown, so the
///   division cannot produce `NaN`. Dart would give `0/0 = NaN` here just as
///   JavaScript does, and `NaN.round()` throws, so this guard is load-bearing
///   rather than defensive decoration.
/// * Recommendations come from checks that are **not healthy** and have one,
///   sorted ascending by score so the worst problem is read first. Note this
///   includes `unknown` checks in the filter, exactly as the original does —
///   though they never carry a recommendation, so none survive in practice.
HealthReport computeOverallHealth(List<HealthCheck> checks) {
  final List<HealthCheck> usable = checks
      .where((HealthCheck c) => c.status != HealthStatus.unknown)
      .toList(growable: false);

  final double totalWeight = usable.fold<double>(
    0,
    (double sum, HealthCheck c) => sum + c.weight,
  );
  final double divisor = totalWeight == 0 ? 1 : totalWeight;

  final double weighted = usable.fold<double>(
    0,
    (double sum, HealthCheck c) => sum + c.score * c.weight,
  );
  final int score = (weighted / divisor).round();

  final List<HealthCheck> flagged =
      checks
          .where(
            (HealthCheck c) =>
                c.recommendation != null &&
                c.recommendation!.isNotEmpty &&
                c.status != HealthStatus.healthy,
          )
          .toList()
        ..sort((HealthCheck a, HealthCheck b) => a.score.compareTo(b.score));

  return HealthReport(
    score: score,
    status: statusOf(score),
    checks: checks,
    recommendations: flagged
        .map((HealthCheck c) => c.recommendation!)
        .toList(growable: false),
  );
}
