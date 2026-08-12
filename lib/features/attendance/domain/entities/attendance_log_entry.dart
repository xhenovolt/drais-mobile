/// Where a punch came from.
///
/// Mirrors the `attendance_raw_events.source` enum exactly. DRAIS funnels
/// every source through one path (`recordRawEvent`), which is why this is a
/// property of the event rather than a separate table per device type.
enum PunchSource {
  /// A ZKTeco device pushed it to DRAIS.
  zktecoPush('zkteco_push', 'ZKTeco'),

  /// DRAIS pulled it from a Dahua device.
  dahuaPull('dahua_pull', 'Dahua'),

  /// Entered by a person rather than captured by a device.
  manual('manual', 'Manual'),

  /// Arrived via a relay.
  relay('relay', 'Relay'),

  /// Pulled over TCP from a device.
  tcpPull('tcp_pull', 'TCP pull'),

  /// Imported from a USB dump.
  usbImport('usb_import', 'USB import'),

  /// Imported from a CSV.
  csvImport('csv_import', 'CSV import'),

  /// A value this build does not recognise — the backend may add sources
  /// faster than the app ships, and an unknown one must display, not crash.
  unknown('', 'Unknown');

  const PunchSource(this.wireValue, this.label);

  /// The exact enum value in the database.
  final String wireValue;

  /// Short label for the log row.
  final String label;

  /// Resolves a stored value.
  static PunchSource fromWire(String? raw) {
    for (final PunchSource source in PunchSource.values) {
      if (source.wireValue == raw) return source;
    }
    return PunchSource.unknown;
  }

  /// Whether a device produced this, as opposed to a person or a file.
  ///
  /// Device punches carry a clock that can drift; manual and imported ones
  /// carry whatever time a human supplied. The distinction is why
  /// `clock_skew_seconds` is meaningful for some rows and not others.
  bool get isFromDevice => switch (this) {
    PunchSource.zktecoPush ||
    PunchSource.dahuaPull ||
    PunchSource.tcpPull ||
    PunchSource.relay => true,
    _ => false,
  };
}

/// How much the recorded time can be trusted.
///
/// DRAIS treats device clocks as unreliable by default — five distinct time
/// policies exist because five distinct hardware behaviours were observed in
/// production (ADR-0003). A log screen that showed only the timestamp would be
/// hiding the most operationally important thing about it.
enum TimeConfidence {
  /// The clock is trusted.
  high('high', 'Clock trusted'),

  /// Drift detected but within tolerance, or corrected.
  medium('medium', 'Clock corrected'),

  /// The device clock is materially wrong.
  low('low', 'Clock suspect'),

  /// Nothing recorded — older rows, or a source with no clock.
  unknown('', 'Unverified');

  const TimeConfidence(this.wireValue, this.label);

  /// The stored value.
  final String wireValue;

  /// Short label.
  final String label;

  /// Resolves a stored value.
  static TimeConfidence fromWire(String? raw) {
    if (raw == null || raw.isEmpty) return TimeConfidence.unknown;
    for (final TimeConfidence c in TimeConfidence.values) {
      if (c.wireValue == raw.toLowerCase()) return c;
    }
    return TimeConfidence.unknown;
  }

  /// Whether this warrants drawing the operator's attention.
  bool get needsAttention => this == TimeConfidence.low;
}

/// One punch, as it was recorded.
///
/// A row of `attendance_raw_events` — the **append-only record of what
/// happened**, as distinct from `attendance_records`, which is the derived
/// verdict about a whole day (ADR-0001). A log entry is never edited; a
/// correction produces a new event and the verdict is recomputed.
///
/// This is what the logs screen shows: who came, when, from where, whether
/// DRAIS is sure it was them, and whether the clock can be believed.
class AttendanceLogEntry {
  /// Creates a log entry.
  const AttendanceLogEntry({
    required this.id,
    required this.punchAt,
    required this.source,
    required this.roleType,
    required this.matched,
    this.personId,
    this.displayName,
    this.deviceReportedTime,
    this.clockSkewSeconds,
    this.timeConfidence = TimeConfidence.unknown,
    this.resolutionPath,
    this.resolutionScore,
    this.ioMode,
    this.derivedEvent,
    this.isProvisional = false,
    this.provisionalReason,
  });

  /// `attendance_raw_events.id`.
  final int id;

  /// When the punch happened, after DRAIS resolved it to a real instant.
  final DateTime punchAt;

  /// Which device or process produced it.
  final PunchSource source;

  /// `student` | `staff` | `visitor`.
  final String roleType;

  /// Whether DRAIS resolved this punch to a known person.
  ///
  /// An unmatched punch is not a failure to record — the event is kept
  /// regardless, which is what lets a late identity claim attach it to
  /// someone afterwards and recompute their day.
  final bool matched;

  /// The resolved person, when matched.
  final int? personId;

  /// The name to show. May be the device's own label for an unmatched punch,
  /// which is exactly the string an operator needs in order to claim it.
  final String? displayName;

  /// The wall-clock time the device reported, before correction.
  final DateTime? deviceReportedTime;

  /// How far the device clock was off, in seconds.
  final int? clockSkewSeconds;

  /// How much the time can be trusted.
  final TimeConfidence timeConfidence;

  /// How the identity was resolved — `pin`, `fuzzy`, `claim`, and so on.
  final String? resolutionPath;

  /// Confidence of a fuzzy match, 0–1.
  final double? resolutionScore;

  /// Direction, when the device reported one. 0 is typically in, 1 out.
  final int? ioMode;

  /// A short label the engine derived, e.g. `first_in`.
  final String? derivedEvent;

  /// Whether the resulting verdict is still provisional.
  final bool isProvisional;

  /// Why it is provisional.
  final String? provisionalReason;

  /// Best available name for display.
  String get personLabel {
    final String? name = displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return matched ? 'Person #$personId' : 'Unidentified';
  }

  /// Whether the device clock was off by more than a minute.
  ///
  /// A minute is the threshold at which skew starts changing a *late* verdict,
  /// which is when an operator needs to know about it.
  bool get hasMeaningfulSkew =>
      clockSkewSeconds != null && clockSkewSeconds!.abs() >= 60;

  /// Human description of the skew, e.g. `2m fast`.
  String? get skewLabel {
    final int? seconds = clockSkewSeconds;
    if (seconds == null || seconds == 0) return null;

    final int magnitude = seconds.abs();
    final String direction = seconds > 0 ? 'fast' : 'slow';

    if (magnitude < 60) return '${magnitude}s $direction';
    if (magnitude < 3600) return '${magnitude ~/ 60}m $direction';
    return '${(magnitude / 3600).toStringAsFixed(1)}h $direction';
  }

  /// Whether this row should be surfaced for operator attention.
  ///
  /// Three things qualify: DRAIS could not identify the person, the clock is
  /// suspect, or the verdict is provisional. Each is recoverable, and each
  /// stays wrong until somebody looks.
  bool get needsAttention =>
      !matched || timeConfidence.needsAttention || isProvisional;

  @override
  String toString() =>
      'AttendanceLogEntry($id, $personLabel, ${source.label}, $punchAt)';
}
