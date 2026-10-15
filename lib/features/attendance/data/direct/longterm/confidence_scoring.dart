/// Per-record confidence scoring.
///
/// **Ported line-for-line from `src/lib/attendance/confidence-scoring.ts`**
/// (DRAIS LongTerm). Thresholds, weights, the identity/time gate and every
/// reason string are the platform's; change them there first, then here.
/// `test/features/attendance/confidence_scoring_test.dart` carries the
/// platform's own test cases.
library;

import 'package:drais/features/attendance/domain/entities/attendance_history.dart';

/// Evidence for one punch — `ConfidenceInput`.
class ConfidenceInput {
  /// Creates the input.
  const ConfidenceInput({
    required this.matched,
    required this.personId,
    required this.isProvisional,
    required this.resolutionScore,
    required this.resolutionPath,
    required this.deviceSn,
    required this.deviceKnown,
    required this.deviceOnline,
    required this.timeSource,
    required this.clockSkewSeconds,
    required this.clockConfidence,
    required this.wasCorrected,
    required this.hasVerdict,
    required this.ruleId,
    required this.derivedEvent,
  });

  /// `matched`.
  final bool matched;

  /// `person_id`.
  final int? personId;

  /// `is_provisional`.
  final bool isProvisional;

  /// Matcher score, 0–100, when set.
  final double? resolutionScore;

  /// `enrollment` | `directory` | `provisional` | …
  final String? resolutionPath;

  /// Device serial.
  final String? deviceSn;

  /// The serial exists in `devices` (or the device directory).
  final bool deviceKnown;

  /// `devices.is_online`; null when unknown.
  final bool? deviceOnline;

  /// `device` | `server` | …
  final String? timeSource;

  /// Clock error in seconds.
  final int? clockSkewSeconds;

  /// `device_clock_health.confidence` for the day, 0–100.
  final double? clockConfidence;

  /// A time correction was applied.
  final bool wasCorrected;

  /// An `attendance_records` row exists.
  final bool hasVerdict;

  /// Rule or shift resolved; negative for a staff shift.
  final int? ruleId;

  /// Engine stamp.
  final String? derivedEvent;
}

int _clamp(num n) => n.round().clamp(0, 100);

/// `bandOf()`.
ConfidenceBand bandOf(num score) => score >= 85
    ? ConfidenceBand.high
    : score >= 60
    ? ConfidenceBand.medium
    : ConfidenceBand.low;

Confidence _c(num score, String reason) =>
    Confidence(score: _clamp(score), band: bandOf(_clamp(score)), reason: reason);

/// Renders a number the way JavaScript's template literals do — `92`, not
/// `92.0` — so reason strings match the web app character for character.
String _jsNum(num n) =>
    n == n.truncate() ? n.truncate().toString() : n.toString();

Confidence _identity(ConfidenceInput i) {
  final bool matched = i.matched && i.personId != null;
  if (!matched) return _c(10, 'Unmatched — no confirmed person for this PIN');
  if (i.isProvisional) {
    return _c(55, 'Provisional identity — auto-linked, not yet confirmed');
  }
  final double? s = i.resolutionScore;
  if (s != null) {
    return _c(
      s < 60 ? 60 : s,
      'Matched via ${i.resolutionPath ?? 'matcher'} (score ${_jsNum(s)})',
    );
  }
  if (i.resolutionPath == 'enrollment' || i.resolutionPath == null) {
    return _c(97, 'Confirmed biometric enrollment');
  }
  return _c(88, 'Matched via ${i.resolutionPath}');
}

Confidence _device(ConfidenceInput i) {
  if (i.deviceSn == null || i.deviceSn!.isEmpty) {
    return _c(40, 'No device serial recorded on this punch');
  }
  if (!i.deviceKnown) return _c(50, 'Device ${i.deviceSn} is not registered');
  if (i.deviceOnline == false) {
    return _c(80, 'Known device, currently offline (backlog upload is normal)');
  }
  return _c(96, 'Known, healthy device');
}

Confidence _time(ConfidenceInput i) {
  final double? cc = i.clockConfidence;
  if (cc != null) {
    if (i.wasCorrected) {
      return _c(cc > 90 ? cc : 90, 'Timestamp corrected and re-verified');
    }
    if (cc < 60) return _c(cc, 'Device clock flagged as drifting for this day');
    if (cc < 85) return _c(cc, 'Device clock under review for this day');
    return _c(cc, 'Device clock verified for this day');
  }
  final int? skew = i.clockSkewSeconds?.abs();
  if (i.wasCorrected) return _c(90, 'Timestamp corrected');
  if (skew != null && skew > 3600) {
    return _c(30, 'Large clock skew (${(skew / 60).round()} min)');
  }
  if (skew != null && skew > 300) {
    return _c(65, 'Moderate clock skew (${(skew / 60).round()} min)');
  }
  if (i.timeSource == 'server') {
    return _c(88, 'Server-assigned time (device time not trusted)');
  }
  return _c(90, 'Device time within tolerance');
}

Confidence _policy(ConfidenceInput i) {
  if (!i.hasVerdict) return _c(45, 'No day verdict yet — not evaluated');
  final int? rule = i.ruleId;
  if (rule == null) {
    return _c(
      70,
      'Evaluated on raw presence (no specific rule/shift matched)',
    );
  }
  if (rule < 0) return _c(95, 'Evaluated against the staff shift');
  return _c(96, 'Evaluated against rule #$rule');
}

/// `scoreRecord()` — four sub-scores and a weighted, gated overall.
RecordConfidence scoreRecord(ConfidenceInput i) {
  final Confidence identity = _identity(i);
  final Confidence device = _device(i);
  final Confidence time = _time(i);
  final Confidence policy = _policy(i);

  double overallScore =
      identity.score * 0.4 +
      time.score * 0.3 +
      device.score * 0.15 +
      policy.score * 0.15;
  // Identity and time are gates, not just weights (platform comment).
  final int gate =
      (identity.score < time.score ? identity.score : time.score) + 25;
  if (overallScore > gate) overallScore = gate.toDouble();

  // The first lowest in this order — Array.prototype.sort is stable.
  Confidence weakest = identity;
  for (final Confidence candidate in <Confidence>[time, device, policy]) {
    if (candidate.score < weakest.score) weakest = candidate;
  }

  final Confidence overall = _c(
    overallScore,
    bandOf(_clamp(overallScore)) == ConfidenceBand.high
        ? 'All checks strong'
        : 'Lowered by: ${weakest.reason.toLowerCase()}',
  );
  return RecordConfidence(
    overall: overall,
    identity: identity,
    device: device,
    time: time,
    policy: policy,
  );
}
