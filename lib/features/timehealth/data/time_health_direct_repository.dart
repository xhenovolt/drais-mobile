import 'package:drais/core/database/drais_database.dart';
import 'package:drais/core/error/failure.dart';
import 'package:drais/core/error/result.dart';
import 'package:drais/features/timehealth/domain/health_report.dart';
import 'package:drais/features/timehealth/domain/time_health.dart';

/// Reads device and clock health straight from TiDB, for direct mode.
///
/// ## Why this screen exists
///
/// DRAIS records attendance from biometric devices. If a device stops
/// reporting, or its clock drifts, the register is quietly wrong — everyone
/// looks present-and-late, or absent, and nothing on an attendance screen says
/// why. This is the screen that says why.
class TimeHealthDirectRepository {
  /// Creates the repository.
  TimeHealthDirectRepository({
    required DraisDatabase database,
    required int schoolId,
  }) : _db = database,
       _schoolId = schoolId;

  final DraisDatabase _db;
  final int _schoolId;

  /// Devices, with today's volume and clock behaviour attached.
  Future<Result<List<AttendanceDevice>>> devices({required String date}) async {
    try {
      final List<Row> rows = await _db.query(
        '''
        SELECT d.id, d.sn, d.device_name, d.location, d.is_online, d.status,
               d.last_seen, d.last_activity, d.ip_address,
               b.median_first_minute, b.mad_minutes, b.p10_first_minute,
               b.p90_first_minute, b.median_daily_punches, b.sample_days,
               b.window_days, b.computed_at
          FROM devices d
          LEFT JOIN attendance_time_baselines b
                 ON b.device_sn = d.sn AND b.school_id = d.school_id
         WHERE d.school_id = ? AND d.deleted_at IS NULL
         ORDER BY d.device_name
        ''',
        <Object?>[_schoolId],
      );

      // Punch volume and clock offset come from the records themselves, keyed
      // by the device that produced the first punch of each day. Raw events
      // carry no device column, so this is the only honest per-device count.
      final List<Row> activity = await _db.query(
        '''
        SELECT r.first_in_device AS device, COUNT(*) AS punches
          FROM attendance_records r
         WHERE r.school_id = ? AND r.attendance_date = ?
           AND r.first_in_device IS NOT NULL
         GROUP BY r.first_in_device
        ''',
        <Object?>[_schoolId, date],
      );

      final Map<String, int> punchesByDevice = <String, int>{
        for (final Row row in activity)
          (SqlValue.asString(row['device']) ?? ''):
              SqlValue.asInt(row['punches']) ?? 0,
      };

      // One representative skew for the day. The median would be better than
      // the average, but MySQL has no median and sorting every row on a phone
      // to find one is not worth the accuracy here.
      final Row? skew = await _db.queryOne(
        '''
        SELECT AVG(e.clock_skew_seconds) AS avg_skew
          FROM attendance_raw_events e
         WHERE DATE(e.punch_at) = ?
           AND e.clock_skew_seconds IS NOT NULL
           AND e.person_id IN (
                 SELECT person_id FROM students
                  WHERE school_id = ? AND deleted_at IS NULL
                 UNION SELECT person_id FROM staff
                  WHERE school_id = ? AND deleted_at IS NULL
               )
        ''',
        <Object?>[date, _schoolId, _schoolId],
      );

      final double? avgSkew = double.tryParse(
        SqlValue.asString(skew?['avg_skew']) ?? '',
      );

      return Ok<List<AttendanceDevice>>(
        rows
            .map((Row row) {
              final String sn = SqlValue.asString(row['sn']) ?? '';
              return AttendanceDevice(
                id: SqlValue.asInt(row['id']) ?? 0,
                serialNumber: sn,
                name: SqlValue.asString(row['device_name'])?.trim(),
                location: SqlValue.asString(row['location']),
                isOnline: SqlValue.asBool(row['is_online']),
                status: SqlValue.asString(row['status']),
                lastSeen: SqlValue.asDate(row['last_seen']),
                lastActivity: SqlValue.asDate(row['last_activity']),
                ipAddress: SqlValue.asString(row['ip_address']),
                punchesToday: punchesByDevice[sn] ?? 0,
                medianSkewSeconds: avgSkew?.round(),
                baseline: row['median_first_minute'] == null
                    ? null
                    : DeviceBaseline(
                        medianFirstMinute: SqlValue.asInt(
                          row['median_first_minute'],
                        ),
                        madMinutes: SqlValue.asInt(row['mad_minutes']),
                        p10FirstMinute: SqlValue.asInt(row['p10_first_minute']),
                        p90FirstMinute: SqlValue.asInt(row['p90_first_minute']),
                        medianDailyPunches: SqlValue.asInt(
                          row['median_daily_punches'],
                        ),
                        sampleDays: SqlValue.asInt(row['sample_days']),
                        windowDays: SqlValue.asInt(row['window_days']),
                        computedAt: SqlValue.asDate(row['computed_at']),
                      ),
              );
            })
            .toList(growable: false),
      );
    } on Failure catch (failure) {
      return Err<List<AttendanceDevice>>(failure);
    }
  }

  /// The school's device-time policy, or the platform defaults.
  ///
  /// An absent row is normal, not an error: the platform falls back to EAT and
  /// its default policy, and most schools never touch it.
  Future<Result<TimePolicy>> policy() async {
    try {
      final Row? row = await _db.queryOne(
        'SELECT school_timezone, utc_offset_minutes, device_time_policy, '
        'auto_sync_device_time, max_allowed_drift_seconds '
        'FROM attendance_time_policy WHERE school_id = ? LIMIT 1',
        <Object?>[_schoolId],
      );

      if (row == null) return const Ok<TimePolicy>(TimePolicy());

      return Ok<TimePolicy>(
        TimePolicy(
          timezone:
              SqlValue.asString(row['school_timezone']) ?? 'Africa/Kampala',
          utcOffsetMinutes: SqlValue.asInt(row['utc_offset_minutes']) ?? 180,
          devicePolicy: SqlValue.asString(row['device_time_policy']),
          autoSync: SqlValue.asBool(row['auto_sync_device_time']),
          maxDriftSeconds: SqlValue.asInt(row['max_allowed_drift_seconds']),
          isConfigured: true,
        ),
      );
    } on Failure catch (failure) {
      return Err<TimePolicy>(failure);
    }
  }

  /// Runs the ten Attendance Health Score checks.
  ///
  /// ## A transcription of `runHealthChecks` in `src/lib/attendance/health.ts`
  ///
  /// Same ten checks, same SQL, same weights, same score ladders, same wording
  /// of the details and recommendations. Where the original catches and returns
  /// a fallback row, so does this. Where it guards a check so one failure cannot
  /// take down the report, so does this.
  ///
  /// The only intentional departure is check 9, the database latency probe: the
  /// original measures a `SELECT 1` round-trip from a Vercel function to TiDB,
  /// while here it measures one from the handset. That is a different distance
  /// over a different network, and it is measured anyway because on a phone it
  /// is the more honest number — a school on a bad mobile connection genuinely
  /// does have a slow database, and the score should say so.
  Future<Result<HealthReport>> runHealthChecks() async {
    final List<HealthCheck> checks = <HealthCheck>[];

    // Each check is individually guarded. One failing check reports itself as
    // `unknown` and is excluded from the rollup, rather than failing the
    // whole report — a phone on a flaky connection should still show the nine
    // checks that did answer.
    Future<void> guard(
      Future<HealthCheck> Function() run, {
      required String key,
      required String label,
      required double weight,
    }) async {
      try {
        checks.add(await run());
      } on Object catch (error) {
        checks.add(
          HealthCheck.unknown(
            key: key,
            label: label,
            weight: weight,
            why: 'Check failed: ${_reason(error)}',
          ),
        );
      }
    }

    final TimePolicy timePolicy = await policy().then(
      (Result<TimePolicy> r) => r.fold(
        onOk: (TimePolicy p) => p,
        // health.ts falls back to a bare `{ offsetMinutes: 180 }` when the
        // policy cannot be resolved. Same fallback, same 180.
        onErr: (Failure _) => const TimePolicy(),
      ),
    );
    final int offsetMinutes = timePolicy.utcOffsetMinutes;
    final DateTime localNow = DateTime.now().toUtc().add(
      Duration(minutes: offsetMinutes),
    );
    // `localNow` has already been shifted, so this is a plain slice of it —
    // not `toLocalDateStr`, which would apply the offset a second time. This
    // is exactly the `.toISOString().slice(0, 10)` the original does on its
    // own pre-shifted value.
    final String localDate =
        '${localNow.year.toString().padLeft(4, '0')}-'
        '${localNow.month.toString().padLeft(2, '0')}-'
        '${localNow.day.toString().padLeft(2, '0')}';
    // The UTC instant at which the school's local day began — what the raw
    // event timestamps must be compared against.
    final DateTime utcDayStart = DateTime.parse(
      '${localDate}T00:00:00Z',
    ).subtract(Duration(minutes: offsetMinutes));

    // 1 · Device connectivity (weight 1.5)
    await guard(
      key: 'devices',
      label: 'Device connectivity',
      weight: 1.5,
      () async {
        final Row? row = await _db.queryOne(
          'SELECT COUNT(*) AS total, SUM(is_online = 1) AS online '
          'FROM devices WHERE school_id = ?',
          <Object?>[_schoolId],
        );
        final int total = SqlValue.asInt(row?['total']) ?? 0;
        final int online = SqlValue.asInt(row?['online']) ?? 0;
        if (total == 0) {
          return HealthCheck.scored(
            key: 'devices',
            label: 'Device connectivity',
            weight: 1.5,
            score: 100,
            detail: 'No devices registered — nothing to monitor.',
          );
        }
        return HealthCheck.scored(
          key: 'devices',
          label: 'Device connectivity',
          weight: 1.5,
          score: (online / total) * 100,
          detail: '$online/$total devices online.',
          recommendation: online < total
              ? '${total - online} device(s) offline — check power/network '
                    'at the school.'
              : null,
        );
      },
    );

    // 2 · Heartbeats (weight 1) — freshness of the stalest last_seen.
    await guard(
      key: 'heartbeat',
      label: 'Device heartbeats',
      weight: 1,
      () async {
        final List<Row> rows = await _db.query(
          'SELECT device_name, sn, TIMESTAMPDIFF(MINUTE, last_seen, NOW()) '
          'AS age_min FROM devices '
          'WHERE school_id = ? AND last_seen IS NOT NULL '
          'ORDER BY age_min DESC',
          <Object?>[_schoolId],
        );
        if (rows.isEmpty) {
          return HealthCheck.scored(
            key: 'heartbeat',
            label: 'Device heartbeats',
            weight: 1,
            score: 100,
            detail: 'No heartbeat history yet.',
          );
        }
        final Row worst = rows.first;
        final int age = SqlValue.asInt(worst['age_min']) ?? 0;
        final int score = age <= 15
            ? 100
            : age <= 60
            ? 85
            : age <= 24 * 60
            ? 55
            : 20;
        final String name =
            SqlValue.asString(worst['device_name'])?.trim() ??
            SqlValue.asString(worst['sn']) ??
            'device';
        final String ago = age < 60 ? '$age min' : '${(age / 60).round()}h';
        return HealthCheck.scored(
          key: 'heartbeat',
          label: 'Device heartbeats',
          weight: 1,
          score: score,
          detail:
              'Stalest heartbeat: '
              '${name.isEmpty ? SqlValue.asString(worst['sn']) : name} — '
              '$ago ago.',
          recommendation: score < 90
              ? 'A device has not reported recently — verify its '
                    'internet/ADMS settings.'
              : null,
        );
      },
    );

    // 3 · Attendance flow (weight 1.5) — today's volume against what this
    // school normally does by this hour.
    await guard(key: 'flow', label: 'Attendance flow', weight: 1.5, () async {
      final Row? todayRow = await _db.queryOne(
        'SELECT COUNT(*) AS n FROM attendance_raw_events '
        'WHERE school_id = ? AND punch_at >= ?',
        <Object?>[_schoolId, utcDayStart],
      );
      int expected = 0;
      try {
        final Row? blRow = await _db.queryOne(
          'SELECT SUM(median_daily_punches) AS expected '
          'FROM attendance_time_baselines WHERE school_id = ?',
          <Object?>[_schoolId],
        );
        expected = SqlValue.asInt(blRow?['expected']) ?? 0;
      } on Object {
        // The original `.catch(() => [{ expected: null }])`s this: a school
        // with no baselines table yet must not fail the whole check.
        expected = 0;
      }
      final int today = SqlValue.asInt(todayRow?['n']) ?? 0;
      final int hour = localNow.hour;

      if (expected == 0) {
        return HealthCheck.scored(
          key: 'flow',
          label: 'Attendance flow',
          weight: 1.5,
          score: today > 0 ? 100 : 70,
          detail: '$today punches today (no learned volume yet).',
        );
      }
      if (hour < 8) {
        return HealthCheck.scored(
          key: 'flow',
          label: 'Attendance flow',
          weight: 1.5,
          score: 100,
          detail: '$today punches so far — too early to judge volume.',
        );
      }
      // Scale the expectation by how far through the day it is, capped at
      // the full day, so a 10:00 reading is not compared against a 17:00
      // total.
      final double frac = _min(1, today / (expected * _min(1, hour / 17)));
      final int score = frac >= 0.6
          ? 100
          : frac >= 0.3
          ? 70
          : 25;
      return HealthCheck.scored(
        key: 'flow',
        label: 'Attendance flow',
        weight: 1.5,
        score: score,
        detail: '$today punches today vs ~$expected on a normal day.',
        recommendation: score < 90
            ? 'Punch volume is far below normal — device may be offline or '
                  'storing without uploading. Open the Recovery/device pages.'
            : null,
      );
    });

    // 4 · Time synchronization (weight 1.5) — today's worst clock confidence.
    await guard(
      key: 'time',
      label: 'Time synchronization',
      weight: 1.5,
      () async {
        final List<Row> rows = await _db.query(
          'SELECT device_sn, confidence, status, likely_cause '
          'FROM device_clock_health '
          'WHERE school_id = ? AND local_date = ? ORDER BY confidence ASC',
          <Object?>[_schoolId, localDate],
        );
        if (rows.isEmpty) {
          return HealthCheck.scored(
            key: 'time',
            label: 'Time synchronization',
            weight: 1.5,
            score: 95,
            detail: 'No batches assessed yet today.',
          );
        }
        final Row worst = rows.first;
        final int confidence = SqlValue.asInt(worst['confidence']) ?? 0;
        return HealthCheck.scored(
          key: 'time',
          label: 'Time synchronization',
          weight: 1.5,
          score: confidence,
          detail:
              'Lowest device time confidence today: '
              '${SqlValue.asString(worst['device_sn'])} at $confidence% '
              '(${SqlValue.asString(worst['likely_cause']) ?? 'unknown'}).',
          recommendation: confidence < 80
              ? 'Open Time Health to review and correct the batch, and fix '
                    'the device clock.'
              : null,
        );
      },
    );

    // 5 · SMS health (weight 1) — delivery success over 48h.
    await guard(key: 'sms', label: 'SMS health', weight: 1, () async {
      final List<Row> rows = await _db.query(
        'SELECT status, COUNT(*) AS n FROM notification_outbox '
        'WHERE school_id = ? '
        'AND created_at >= DATE_SUB(NOW(), INTERVAL 48 HOUR) '
        'GROUP BY status',
        <Object?>[_schoolId],
      );
      final Map<String, int> by = <String, int>{};
      for (final Row row in rows) {
        final String? status = SqlValue.asString(row['status']);
        if (status != null) by[status] = SqlValue.asInt(row['n']) ?? 0;
      }
      final int sent = (by['delivered'] ?? 0) + (by['sent'] ?? 0);
      final int failed = by['failed'] ?? 0;
      final int total = sent + failed;
      if (total == 0) {
        return HealthCheck.scored(
          key: 'sms',
          label: 'SMS health',
          weight: 1,
          score: 100,
          detail: 'No SMS attempted in the last 48h.',
        );
      }
      return HealthCheck.scored(
        key: 'sms',
        label: 'SMS health',
        weight: 1,
        score: (sent / total) * 100,
        detail: '$sent/$total SMS delivered in 48h ($failed failed).',
        recommendation: failed > 0
            ? 'SMS failures present — check provider balance/credentials '
                  'in notification settings.'
            : null,
      );
    });

    // 6 · Identity mapping (weight 1.5) — 7-day matched ratio.
    await guard(
      key: 'identity',
      label: 'Identity mapping',
      weight: 1.5,
      () async {
        final Row? row = await _db.queryOne(
          'SELECT COUNT(*) AS total, SUM(matched = 1) AS matched '
          'FROM attendance_raw_events '
          'WHERE school_id = ? '
          'AND punch_at >= DATE_SUB(NOW(), INTERVAL 7 DAY)',
          <Object?>[_schoolId],
        );
        final int total = SqlValue.asInt(row?['total']) ?? 0;
        final int matched = SqlValue.asInt(row?['matched']) ?? 0;
        if (total == 0) {
          return HealthCheck.scored(
            key: 'identity',
            label: 'Identity mapping',
            weight: 1.5,
            score: 100,
            detail: 'No punches in the last 7 days.',
          );
        }
        final double score = (matched / total) * 100;
        return HealthCheck.scored(
          key: 'identity',
          label: 'Identity mapping',
          weight: 1.5,
          score: score,
          detail: '$matched/$total punches matched to people (7 days).',
          recommendation: score < 95
              ? '${total - matched} unmatched punches — use "Detect & map" '
                    'on the Unmatched tab.'
              : null,
        );
      },
    );

    // 7 · Notification queue (weight 0.5) — outbox items stuck > 15 min.
    await guard(
      key: 'queue',
      label: 'Notification queue',
      weight: 0.5,
      () async {
        final Row? row = await _db.queryOne(
          'SELECT COUNT(*) AS n FROM notification_outbox '
          "WHERE school_id = ? AND status = 'queued' "
          'AND created_at < DATE_SUB(NOW(), INTERVAL 15 MINUTE)',
          <Object?>[_schoolId],
        );
        final int stuck = SqlValue.asInt(row?['n']) ?? 0;
        final int score = stuck == 0
            ? 100
            : stuck < 10
            ? 70
            : 30;
        return HealthCheck.scored(
          key: 'queue',
          label: 'Notification queue',
          weight: 0.5,
          score: score,
          detail: stuck > 0
              ? '$stuck messages stuck in queue > 15 min.'
              : 'Queue is draining normally.',
          recommendation: stuck > 0
              ? 'Outbox drainer may be idle — any page load nudges it; '
                    'persistent backlog means provider errors.'
              : null,
        );
      },
    );

    // 8 · Background jobs (weight 0.5) — device pulls stuck mid-flight.
    await guard(key: 'jobs', label: 'Background jobs', weight: 0.5, () async {
      int stuck = 0;
      try {
        final Row? row = await _db.queryOne(
          'SELECT COUNT(*) AS n FROM attendance_acquisitions '
          "WHERE school_id = ? AND status IN ('pulling','staged','validated') "
          'AND created_at < DATE_SUB(NOW(), INTERVAL 2 HOUR)',
          <Object?>[_schoolId],
        );
        stuck = SqlValue.asInt(row?['n']) ?? 0;
      } on Object {
        // Original catches to `[{ n: 0 }]` — a school without the
        // acquisitions table scores clean rather than unknown.
        stuck = 0;
      }
      return HealthCheck.scored(
        key: 'jobs',
        label: 'Background jobs',
        weight: 0.5,
        score: stuck > 0 ? 60 : 100,
        detail: stuck > 0
            ? '$stuck device pull(s) stuck mid-flight > 2h.'
            : 'No stuck pulls or jobs.',
        recommendation: stuck > 0
            ? 'Open Device Control and discard or re-run the stalled '
                  'acquisition.'
            : null,
      );
    });

    // 9 · Database (weight 0.5) — round-trip latency probe.
    //
    // On a handset this measures the phone's own path to TiDB rather than a
    // server's. That is the number that actually governs whether these
    // screens feel usable here, so it is the right one to score.
    await guard(key: 'db', label: 'Database', weight: 0.5, () async {
      final Stopwatch watch = Stopwatch()..start();
      await _db.query('SELECT 1 AS ok');
      watch.stop();
      final int ms = watch.elapsedMilliseconds;
      final int score = ms < 250
          ? 100
          : ms < 1000
          ? 80
          : 40;
      return HealthCheck.scored(
        key: 'db',
        label: 'Database',
        weight: 0.5,
        score: score,
        detail: 'Query round-trip $ms ms.',
        recommendation: score < 90
            ? 'Database latency is elevated — TiDB region or network issue.'
            : null,
      );
    });

    // 10 · Device clock reputation (weight 1) — anomalous device-days over 30d.
    await guard(
      key: 'device_rep',
      label: 'Device clock reputation',
      weight: 1,
      () async {
        final Row? row = await _db.queryOne(
          "SELECT COUNT(*) AS days, SUM(status = 'anomaly') AS bad "
          'FROM device_clock_health WHERE school_id = ? '
          'AND local_date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)',
          <Object?>[_schoolId],
        );
        final int days = SqlValue.asInt(row?['days']) ?? 0;
        final int bad = SqlValue.asInt(row?['bad']) ?? 0;
        if (days == 0) {
          return HealthCheck.scored(
            key: 'device_rep',
            label: 'Device clock reputation',
            weight: 1,
            score: 95,
            detail: 'No clock history yet.',
          );
        }
        return HealthCheck.scored(
          key: 'device_rep',
          label: 'Device clock reputation',
          weight: 1,
          score: 100 - (bad / days) * 100,
          detail: '$bad/$days tracked device-days had clock anomalies (30d).',
          recommendation: bad > 2
              ? 'A device drifts repeatedly — its RTC coin-cell battery '
                    'likely needs replacement.'
              : null,
        );
      },
    );

    final HealthReport rollup = computeOverallHealth(checks);
    return Ok<HealthReport>(
      HealthReport(
        score: rollup.score,
        status: rollup.status,
        checks: rollup.checks,
        recommendations: rollup.recommendations,
        generatedAt: DateTime.now(),
      ),
    );
  }

  static double _min(double a, double b) => a < b ? a : b;

  static String _reason(Object error) =>
      error is Failure ? error.message : error.toString();
}
