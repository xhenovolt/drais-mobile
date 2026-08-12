/// An attendance device, and whether it is behaving.
class AttendanceDevice {
  /// Creates a device.
  const AttendanceDevice({
    required this.id,
    required this.serialNumber,
    this.name,
    this.location,
    this.isOnline = false,
    this.status,
    this.lastSeen,
    this.lastActivity,
    this.ipAddress,
    this.punchesToday = 0,
    this.baseline,
    this.medianSkewSeconds,
  });

  /// `devices.id`.
  final int id;

  /// `devices.sn` — the serial the device reports, and the key everything
  /// else about it is filed under.
  final String serialNumber;

  /// Friendly name.
  final String? name;

  /// Where it is mounted.
  final String? location;

  /// Whether DRAIS believes it is connected.
  final bool isOnline;

  /// `devices.status`.
  final String? status;

  /// Last contact of any kind.
  final DateTime? lastSeen;

  /// Last punch or command.
  final DateTime? lastActivity;

  /// Last known address.
  final String? ipAddress;

  /// Punches recorded from it today.
  final int punchesToday;

  /// What a normal day looks like for this device.
  final DeviceBaseline? baseline;

  /// Typical clock offset today, in seconds. Positive is fast.
  final int? medianSkewSeconds;

  /// How long since anything was heard from it.
  Duration? get silence {
    final DateTime? last = lastActivity ?? lastSeen;
    return last == null ? null : DateTime.now().difference(last);
  }

  /// Whether it has gone quiet for long enough to matter.
  ///
  /// Four hours spans a morning: a device that reported at 07:00 and nothing
  /// since has missed the entire arrival window, which is the one period that
  /// cannot be reconstructed later.
  bool get isSilent {
    final Duration? quiet = silence;
    return quiet != null && quiet.inHours >= 4;
  }

  /// Whether the clock is off by more than a minute.
  bool get hasClockDrift =>
      medianSkewSeconds != null && medianSkewSeconds!.abs() >= 60;

  /// Today's punch count against this device's own normal.
  ///
  /// Compared to *its* baseline rather than a fixed number, because a gate
  /// reader and a staff-room reader have completely different normals.
  double? get punchRatio {
    final int? typical = baseline?.medianDailyPunches;
    if (typical == null || typical == 0) return null;
    return punchesToday / typical;
  }

  /// Whether today's volume is far enough below normal to investigate.
  bool get isUnderReporting {
    final double? ratio = punchRatio;
    return ratio != null && ratio < 0.5;
  }

  /// Everything currently wrong with this device, worst first.
  List<String> get concerns => <String>[
    if (!isOnline) 'Offline',
    if (isSilent) 'No activity for ${_describe(silence!)}',
    if (hasClockDrift) 'Clock ${_skewLabel(medianSkewSeconds!)}',
    if (isUnderReporting)
      'Only ${(punchRatio! * 100).round()}% of its usual punches today',
  ];

  /// Whether anything needs looking at.
  bool get isHealthy => concerns.isEmpty;

  static String _describe(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 48) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  static String _skewLabel(int seconds) {
    final int magnitude = seconds.abs();
    final String direction = seconds > 0 ? 'fast' : 'slow';
    if (magnitude < 60) return '${magnitude}s $direction';
    if (magnitude < 3600) return '${magnitude ~/ 60}m $direction';
    return '${(magnitude / 3600).toStringAsFixed(1)}h $direction';
  }
}

/// What a normal day looks like for one device.
///
/// Computed by the platform over a rolling window and stored in
/// `attendance_time_baselines`. It is what makes "is today odd?" answerable —
/// without it, 239 punches is just a number.
class DeviceBaseline {
  /// Creates a baseline.
  const DeviceBaseline({
    this.medianFirstMinute,
    this.madMinutes,
    this.p10FirstMinute,
    this.p90FirstMinute,
    this.medianDailyPunches,
    this.sampleDays,
    this.windowDays,
    this.computedAt,
  });

  /// Typical first arrival, in minutes past midnight.
  final int? medianFirstMinute;

  /// Median absolute deviation of that, in minutes — how consistent the school
  /// is, and therefore how much variation is worth remarking on.
  final int? madMinutes;

  /// Early edge of normal arrivals.
  final int? p10FirstMinute;

  /// Late edge of normal arrivals.
  final int? p90FirstMinute;

  /// Typical punches in a day.
  final int? medianDailyPunches;

  /// Days that contributed.
  final int? sampleDays;

  /// Window the baseline was computed over.
  final int? windowDays;

  /// When it was last recomputed.
  final DateTime? computedAt;

  /// Typical first arrival as `HH:MM`.
  String? get medianFirstArrival => _clock(medianFirstMinute);

  /// Early edge as `HH:MM`.
  String? get earlyEdge => _clock(p10FirstMinute);

  /// Late edge as `HH:MM`.
  String? get lateEdge => _clock(p90FirstMinute);

  /// Whether there is enough history to trust this.
  ///
  /// Two weeks of school days. Below that a single unusual week distorts the
  /// median, and comparing today against it would raise false alarms.
  bool get isReliable => (sampleDays ?? 0) >= 10;

  static String? _clock(int? minutesPastMidnight) {
    if (minutesPastMidnight == null) return null;
    final int hour = minutesPastMidnight ~/ 60;
    final int minute = minutesPastMidnight % 60;
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }
}

/// The school's device-time settings.
class TimePolicy {
  /// Creates a policy.
  const TimePolicy({
    this.timezone = 'Africa/Kampala',
    this.utcOffsetMinutes = 180,
    this.devicePolicy,
    this.autoSync = false,
    this.maxDriftSeconds,
    this.isConfigured = false,
  });

  /// School timezone.
  final String timezone;

  /// Offset used to resolve device wall-clock times.
  final int utcOffsetMinutes;

  /// Which of the platform's device-time policies is in force.
  final String? devicePolicy;

  /// Whether DRAIS pushes time corrections to devices.
  final bool autoSync;

  /// Drift beyond which a device's times stop being trusted.
  final int? maxDriftSeconds;

  /// Whether the school has a row, as opposed to running on defaults.
  final bool isConfigured;
}
