import 'package:flutter/material.dart';

import 'package:drais/app/theme/app_colors.dart';
import 'package:drais/core/datetime/local_date.dart';
import 'package:drais/features/attendance/domain/entities/attendance_history.dart';
import 'package:drais/shared/widgets/drais_app_bar.dart';

/// One punch, as a card — the mobile shape of a row on the web logs page.
///
/// Shows who, when (in **school** time), what the engine made of it, which
/// device, and whether the record can be trusted. Tapping a matched punch
/// opens that person.
class HistoryRowTile extends StatelessWidget {
  /// Creates a row tile.
  const HistoryRowTile({
    required this.row,
    required this.offsetMinutes,
    this.showDate = false,
    this.onTap,
    super.key,
  });

  /// The punch.
  final AttendanceHistoryRow row;

  /// The school's UTC offset.
  final int offsetMinutes;

  /// Whether to show the date under the time — for multi-day ranges.
  final bool showDate;

  /// Opens the person, when there is one.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final DateTime wall = schoolWallTime(
      row.checkTime,
      offsetMinutes: offsetMinutes,
    );
    final Color muted = theme.colorScheme.onSurfaceVariant;
    final Color warn = DraisColors.forAttendanceStatus(
      'half_day',
      isDark: isDark,
    );

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PersonAvatar(
                initials: row.matched ? row.initials : '?',
                photoUrl: row.photoUrl,
                muted: !row.matched,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      row.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (row.subtitle != null)
                      Text(
                        row.subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        if (row.derivedLabel != null)
                          DraisPill(
                            label: row.derivedDetail ?? row.derivedLabel!,
                            color: DraisColors.forAttendanceStatus(
                              row.derivedStatusKey,
                              isDark: isDark,
                            ),
                          ),
                        if (!row.matched)
                          DraisPill(
                            label: 'Unmatched',
                            color: warn,
                            icon: Icons.person_search_outlined,
                          )
                        else if (row.isProvisional)
                          DraisPill(
                            label: 'Provisional',
                            color: warn,
                            icon: Icons.hourglass_empty,
                          ),
                        if (row.deviceName != null)
                          DraisPill(
                            label: row.deviceName!,
                            color: muted,
                            icon: Icons.sensors,
                          ),
                        ConfidencePill(confidence: row.confidence.overall),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    formatClockTime(wall),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  if (showDate)
                    Text(
                      describeLocalDate(toLocalDateStr(wall)),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                      ),
                    ),
                  if (row.ioMode != null)
                    Text(
                      row.ioMode == 0 ? 'in' : 'out',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: muted,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A person's photo, or their initials.
///
/// `people.photo_url` is often a path relative to the web app. In direct mode
/// there is no web origin to resolve it against, so only absolute URLs are
/// loaded and everything else falls back to initials.
class PersonAvatar extends StatelessWidget {
  /// Creates an avatar.
  const PersonAvatar({
    required this.initials,
    this.photoUrl,
    this.muted = false,
    this.radius = 20,
    super.key,
  });

  /// Fallback text.
  final String initials;

  /// `people.photo_url`.
  final String? photoUrl;

  /// Grey rather than brand-tinted, for unmatched punches.
  final bool muted;

  /// Radius.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String? url = photoUrl;
    final bool loadable =
        url != null && (url.startsWith('http://') || url.startsWith('https://'));

    return CircleAvatar(
      radius: radius,
      backgroundColor: muted
          ? scheme.surfaceContainerHighest
          : scheme.primaryContainer,
      foregroundImage: loadable ? NetworkImage(url) : null,
      onForegroundImageError: loadable ? (Object _, StackTrace? _) {} : null,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w600,
          color: muted ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// The record's overall confidence, shown only when it is not high — a
/// trusted row needs no badge, and badges on every row would be noise.
class ConfidencePill extends StatelessWidget {
  /// Creates a confidence pill.
  const ConfidencePill({required this.confidence, super.key});

  /// The overall confidence.
  final Confidence confidence;

  @override
  Widget build(BuildContext context) {
    if (confidence.band == ConfidenceBand.high) return const SizedBox.shrink();
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool low = confidence.band == ConfidenceBand.low;

    return Tooltip(
      message: confidence.reason,
      triggerMode: TooltipTriggerMode.tap,
      child: DraisPill(
        label: '${low ? 'Low' : 'Medium'} trust · ${confidence.score}',
        color: DraisColors.forAttendanceStatus(
          low ? 'absent' : 'late',
          isDark: isDark,
        ),
        icon: Icons.verified_user_outlined,
      ),
    );
  }
}
