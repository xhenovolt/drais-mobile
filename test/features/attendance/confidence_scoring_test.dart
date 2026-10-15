import 'package:flutter_test/flutter_test.dart';

import 'package:drais/features/attendance/data/direct/longterm/confidence_scoring.dart';
import 'package:drais/features/attendance/domain/entities/attendance_history.dart';

/// Pins the Dart port of `scoreRecord()` to the platform.
///
/// Every case here is transcribed from LongTerm's
/// `src/lib/attendance/__tests__/confidence-scoring.test.mjs`. If one fails,
/// the port has drifted from the web app — fix the port, not the test.
void main() {
  RecordConfidence rec({
    bool matched = true,
    int? personId = 720001,
    bool keepPerson = true,
    bool isProvisional = false,
    double? resolutionScore,
    String? resolutionPath = 'enrollment',
    String? deviceSn = 'GED7254601154',
    bool keepSn = true,
    bool deviceKnown = true,
    bool? deviceOnline = true,
    String? timeSource = 'device',
    int? clockSkewSeconds = 0,
    double? clockConfidence = 99,
    bool keepClock = true,
    bool wasCorrected = false,
    bool hasVerdict = true,
    int? ruleId = 300002,
    bool keepRule = true,
  }) => scoreRecord(
    ConfidenceInput(
      matched: matched,
      personId: keepPerson ? personId : null,
      isProvisional: isProvisional,
      resolutionScore: resolutionScore,
      resolutionPath: resolutionPath,
      deviceSn: keepSn ? deviceSn : null,
      deviceKnown: deviceKnown,
      deviceOnline: deviceOnline,
      timeSource: timeSource,
      clockSkewSeconds: clockSkewSeconds,
      clockConfidence: keepClock ? clockConfidence : null,
      wasCorrected: wasCorrected,
      hasVerdict: hasVerdict,
      ruleId: keepRule ? ruleId : null,
      derivedEvent: 'ARRIVED',
    ),
  );

  test('band thresholds', () {
    expect(bandOf(90), ConfidenceBand.high);
    expect(bandOf(85), ConfidenceBand.high);
    expect(bandOf(70), ConfidenceBand.medium);
    expect(bandOf(60), ConfidenceBand.medium);
    expect(bandOf(40), ConfidenceBand.low);
  });

  test('a clean record scores high across the board', () {
    final RecordConfidence r = rec();
    expect(r.overall.band, ConfidenceBand.high);
    expect(r.overall.score, greaterThanOrEqualTo(90));
    for (final Confidence c in <Confidence>[
      r.identity,
      r.device,
      r.time,
      r.policy,
    ]) {
      expect(c.band, ConfidenceBand.high);
    }
  });

  group('identity failures dominate', () {
    test('an unmatched punch drags the overall down', () {
      final RecordConfidence r = rec(matched: false, keepPerson: false);
      expect(r.identity.band, ConfidenceBand.low);
      expect(r.overall.band, ConfidenceBand.low);
      expect(r.overall.reason.toLowerCase(), contains('unmatched'));
    });

    test('a provisional identity is 55, which is the low band', () {
      final RecordConfidence r = rec(isProvisional: true);
      expect(r.identity.band, ConfidenceBand.low);
      expect(r.overall.score, lessThan(90));
    });

    test('a matcher score maps through', () {
      expect(
        rec(resolutionScore: 92, resolutionPath: 'directory').identity.band,
        ConfidenceBand.high,
      );
      expect(
        rec(resolutionScore: 70, resolutionPath: 'directory').identity.band,
        ConfidenceBand.medium,
      );
    });

    test('reason strings render numbers as JavaScript does', () {
      // `score 92`, not `score 92.0` — the web app shows the same sentence.
      expect(
        rec(resolutionScore: 92, resolutionPath: 'directory').identity.reason,
        'Matched via directory (score 92)',
      );
    });
  });

  group('time confidence', () {
    test('a drifting clock for the day is low', () {
      final RecordConfidence r = rec(clockConfidence: 5);
      expect(r.time.band, ConfidenceBand.low);
      expect(r.time.reason.toLowerCase(), contains('drift'));
    });

    test('a corrected timestamp recovers to high', () {
      final RecordConfidence r = rec(clockConfidence: 5, wasCorrected: true);
      expect(r.time.band, ConfidenceBand.high);
      expect(r.time.reason.toLowerCase(), contains('corrected'));
    });

    test('large skew without clock-health data is low', () {
      expect(
        rec(keepClock: false, clockSkewSeconds: 18000).time.band,
        ConfidenceBand.low,
      );
    });

    test('server-assigned time is trusted', () {
      expect(
        rec(
          keepClock: false,
          timeSource: 'server',
          clockSkewSeconds: null,
        ).time.band,
        ConfidenceBand.high,
      );
    });
  });

  group('device and policy', () {
    test('an unregistered device scores 60 or less', () {
      expect(rec(deviceKnown: false).device.score, lessThanOrEqualTo(60));
    });
    test('an offline known device is only mildly penalised', () {
      expect(rec(deviceOnline: false).device.score, greaterThanOrEqualTo(75));
    });
    test('no serial is low', () {
      expect(rec(keepSn: false).device.band, ConfidenceBand.low);
    });
    test('a staff-shift verdict is high policy', () {
      expect(rec(ruleId: -5).policy.band, ConfidenceBand.high);
    });
    test('no verdict yet scores exactly 45', () {
      expect(rec(hasVerdict: false, keepRule: false).policy.score, 45);
    });
    test('the raw-presence fallback is medium', () {
      expect(rec(keepRule: false).policy.band, ConfidenceBand.medium);
    });
  });

  test('the overall reason names the weakest link', () {
    final String reason = rec(clockConfidence: 20).overall.reason.toLowerCase();
    expect(reason.contains('clock') || reason.contains('drift'), isTrue);
  });
}
