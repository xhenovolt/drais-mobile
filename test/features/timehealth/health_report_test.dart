import 'package:flutter_test/flutter_test.dart';

import 'package:drais/features/timehealth/domain/health_report.dart';

/// Tests for the Dart port of `computeOverallHealth` and `statusOf`.
///
/// These pin the numbers to `src/lib/attendance/health.ts`. If the platform
/// moves a band, one of these fails — which is the point. A silent divergence
/// here would mean mobile and web telling one school two different stories
/// about the same day.
void main() {
  group('statusOf', () {
    test('bands at 90 and 70, inclusive on the lower edge', () {
      expect(statusOf(100), HealthStatus.healthy);
      expect(statusOf(90), HealthStatus.healthy);
      expect(statusOf(89.9), HealthStatus.degraded);
      expect(statusOf(70), HealthStatus.degraded);
      expect(statusOf(69.9), HealthStatus.critical);
      expect(statusOf(0), HealthStatus.critical);
    });
  });

  group('HealthCheck.scored', () {
    test('rounds and clamps the score into 0–100', () {
      expect(_scored(score: 87.6).score, 88);
      expect(_scored(score: 140).score, 100);
      expect(_scored(score: -20).score, 0);
    });

    test('an unknown check scores zero but is not critical', () {
      final HealthCheck check = HealthCheck.unknown(
        key: 'sms',
        label: 'SMS health',
        weight: 1,
        why: 'Check failed: table missing',
      );
      expect(check.score, 0);
      expect(check.status, HealthStatus.unknown);
      expect(check.recommendation, isNull);
    });
  });

  group('computeOverallHealth', () {
    test('weights checks rather than averaging them flatly', () {
      // 100 at weight 1.5 and 40 at weight 0.5 →
      // (150 + 20) / 2 = 85. A flat mean would give 70.
      final HealthReport report = computeOverallHealth(<HealthCheck>[
        _scored(key: 'devices', score: 100, weight: 1.5),
        _scored(key: 'db', score: 40, weight: 0.5),
      ]);
      expect(report.score, 85);
      expect(report.status, HealthStatus.degraded);
    });

    test('rounds the weighted result', () {
      final HealthReport report = computeOverallHealth(<HealthCheck>[
        _scored(key: 'a', score: 80, weight: 1),
        _scored(key: 'b', score: 91, weight: 1),
      ]);
      expect(report.score, 86); // 85.5 rounds up
    });

    test('excludes unknown checks from the score', () {
      // The failing check must not be scored as a zero — a check that could
      // not run is not evidence that anything is wrong.
      final HealthReport report = computeOverallHealth(<HealthCheck>[
        _scored(key: 'devices', score: 100, weight: 1.5),
        HealthCheck.unknown(
          key: 'sms',
          label: 'SMS health',
          weight: 1,
          why: 'Check failed',
        ),
      ]);
      expect(report.score, 100);
      expect(report.status, HealthStatus.healthy);
      expect(report.usableChecks, hasLength(1));
      expect(report.failedChecks, hasLength(1));
    });

    test('survives every check being unknown', () {
      // Without the divisor guard this is 0/0, and `NaN.round()` throws —
      // a phone that briefly lost the network would crash the screen.
      final HealthReport report = computeOverallHealth(<HealthCheck>[
        HealthCheck.unknown(key: 'a', label: 'A', weight: 1, why: 'x'),
        HealthCheck.unknown(key: 'b', label: 'B', weight: 1, why: 'y'),
      ]);
      expect(report.score, 0);
      expect(report.status, HealthStatus.critical);
    });

    test('an empty list does not divide by zero', () {
      expect(computeOverallHealth(const <HealthCheck>[]).score, 0);
    });

    test('orders recommendations worst score first', () {
      final HealthReport report = computeOverallHealth(<HealthCheck>[
        _scored(key: 'a', score: 75, recommendation: 'middle'),
        _scored(key: 'b', score: 20, recommendation: 'worst'),
        _scored(key: 'c', score: 88, recommendation: 'least bad'),
      ]);
      expect(report.recommendations, <String>['worst', 'middle', 'least bad']);
    });

    test('a healthy check contributes no recommendation', () {
      // Even when one is attached — health.ts filters on status, not on
      // whether the string exists, so a 95-scoring check stays quiet.
      final HealthReport report = computeOverallHealth(<HealthCheck>[
        _scored(key: 'a', score: 95, recommendation: 'ignore me'),
        _scored(key: 'b', score: 50, recommendation: 'act on me'),
      ]);
      expect(report.recommendations, <String>['act on me']);
    });

    test('keeps every check on the report, healthy or not', () {
      final HealthReport report = computeOverallHealth(<HealthCheck>[
        _scored(key: 'a', score: 100),
        _scored(key: 'b', score: 10),
      ]);
      expect(report.checks, hasLength(2));
    });

    test('a full ten-check school scores the way the web app would', () {
      // The real weights, with every check clean: the rollup must be exactly
      // 100 rather than drifting on floating-point weights like 1.5 and 0.5.
      final HealthReport report = computeOverallHealth(<HealthCheck>[
        _scored(key: 'devices', score: 100, weight: 1.5),
        _scored(key: 'heartbeat', score: 100),
        _scored(key: 'flow', score: 100, weight: 1.5),
        _scored(key: 'time', score: 100, weight: 1.5),
        _scored(key: 'sms', score: 100),
        _scored(key: 'identity', score: 100, weight: 1.5),
        _scored(key: 'queue', score: 100, weight: 0.5),
        _scored(key: 'jobs', score: 100, weight: 0.5),
        _scored(key: 'db', score: 100, weight: 0.5),
        _scored(key: 'device_rep', score: 100),
      ]);
      expect(report.score, 100);
      expect(report.status, HealthStatus.healthy);
      expect(report.recommendations, isEmpty);
    });

    test('one failing check alone does not leave the healthy band', () {
      // Half the devices offline scores 50 at weight 1.5, against a total
      // weight of 10.5 — so the school still rolls up to 93 and reads as
      // healthy. That is deliberate on the platform's part: the overall
      // score answers "is attendance OK overall?", and a single sick check
      // is meant to surface as a *recommendation* rather than by repainting
      // the whole school red.
      //
      // Pinned because it is counter-intuitive, and because a well-meaning
      // change to make one bad check dominate would silently put mobile out
      // of step with the web app.
      final HealthReport report = computeOverallHealth(<HealthCheck>[
        _scored(
          key: 'devices',
          score: 50,
          weight: 1.5,
          recommendation: '1 device(s) offline',
        ),
        _scored(key: 'heartbeat', score: 100),
        _scored(key: 'flow', score: 100, weight: 1.5),
        _scored(key: 'time', score: 100, weight: 1.5),
        _scored(key: 'sms', score: 100),
        _scored(key: 'identity', score: 100, weight: 1.5),
        _scored(key: 'queue', score: 100, weight: 0.5),
        _scored(key: 'jobs', score: 100, weight: 0.5),
        _scored(key: 'db', score: 100, weight: 0.5),
        _scored(key: 'device_rep', score: 100),
      ]);
      expect(report.score, 93);
      expect(report.status, HealthStatus.healthy);
      // The problem is still reported — it just does not repaint the school.
      expect(report.recommendations, <String>['1 device(s) offline']);
    });
  });
}

HealthCheck _scored({
  String key = 'check',
  double weight = 1,
  required num score,
  String? recommendation,
}) => HealthCheck.scored(
  key: key,
  label: key,
  weight: weight,
  score: score,
  detail: 'detail',
  recommendation: recommendation,
);
