import 'package:flutter/material.dart';

import 'package:drais/app/router/routes.dart';

/// Whether a module is usable on mobile yet.
enum ModuleAvailability {
  /// Built and working.
  live,

  /// Planned for a named phase. Shown, disabled, with the phase on it — so
  /// the drawer doubles as a roadmap and nobody has to ask what is coming.
  planned,

  /// Deliberately web-only, and expected to stay that way.
  ///
  /// Bulk import, report-card design, template kitchens, financial
  /// reconciliation: long, wide, file-heavy work that a phone makes worse
  /// rather than better. Listing them with an honest reason beats pretending
  /// they were forgotten.
  webOnly,
}

/// One destination in the drawer.
class ModuleItem {
  /// Creates a module item.
  const ModuleItem({
    required this.label,
    required this.icon,
    this.route,
    this.availability = ModuleAvailability.planned,
    this.phase,
    this.permission,
    this.superAdminOnly = false,
    this.note,
  });

  /// Label, matching the web app's wording so the two read as one product.
  final String label;

  /// Leading icon.
  final IconData icon;

  /// Where it goes. Null unless [availability] is live.
  final String? route;

  /// Whether it works yet.
  final ModuleAvailability availability;

  /// Which phase delivers it, for planned items.
  final int? phase;

  /// Permission code the server gates this on.
  ///
  /// Used to *hide* what a user cannot reach, so the drawer reflects their
  /// actual access rather than the full catalogue. Presentation only — the
  /// server re-checks every request regardless.
  final String? permission;

  /// Restrict to super-admins.
  final bool superAdminOnly;

  /// Why a web-only item is web-only.
  final String? note;

  /// Whether tapping it does anything.
  bool get isEnabled =>
      availability == ModuleAvailability.live && route != null;
}

/// A drawer section.
class ModuleSection {
  /// Creates a section.
  const ModuleSection({
    required this.label,
    required this.icon,
    required this.items,
    this.initiallyExpanded = false,
  });

  /// Section heading, mirroring the web app's grouping.
  final String label;

  /// Section icon.
  final IconData icon;

  /// Items within.
  final List<ModuleItem> items;

  /// Whether it starts open.
  final bool initiallyExpanded;

  /// How many items are usable today — drives the "3 of 11" counter.
  int get liveCount => items
      .where((ModuleItem i) => i.availability == ModuleAvailability.live)
      .length;
}

/// The DRAIS module catalogue, mirroring `src/lib/navigationConfig.tsx`.
///
/// ## Why mirror the web app's structure
///
/// A bursar who knows where Fee Rules live on the web should find them in the
/// same group here. Reorganising the hierarchy for mobile would mean two
/// mental models of one product, and the reorganisation would drift.
///
/// Labels, grouping and order follow the web navigation. What differs is the
/// **availability** marking: mobile does not have all 100-odd destinations,
/// and pretending otherwise by hiding them would leave a user wondering
/// whether DRAIS mobile is a different, smaller product. It is the same
/// product, partly delivered — so the catalogue is complete and each entry
/// says where it stands.
abstract final class DraisModules {
  /// Every section, in web-navigation order.
  static List<ModuleSection> sections = <ModuleSection>[
    // ── Students — phase 1 ────────────────────────────────────────────────
    ModuleSection(
      label: 'Students',
      icon: Icons.groups_outlined,
      initiallyExpanded: true,
      items: <ModuleItem>[
        ModuleItem(
          label: 'Student List',
          icon: Icons.list_alt_outlined,
          route: AppRoutes.students,
          availability: ModuleAvailability.live,
          permission: 'students.view',
        ),
        ModuleItem(
          label: 'Admit Student',
          icon: Icons.person_add_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'A long validated form, done once per learner at a desk.',
        ),
        ModuleItem(
          label: 'Admissions Pipeline',
          icon: Icons.account_tree_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'Multi-stage review across many applicants.',
        ),
        ModuleItem(
          label: 'Enroll Student',
          icon: Icons.school_outlined,
          availability: ModuleAvailability.planned,
          phase: 2,
        ),
        ModuleItem(
          label: 'Requirements',
          icon: Icons.checklist_outlined,
          availability: ModuleAvailability.planned,
          phase: 2,
        ),
        ModuleItem(
          label: 'Contacts',
          icon: Icons.phone_outlined,
          availability: ModuleAvailability.planned,
          phase: 1,
        ),
        ModuleItem(
          label: 'Documents',
          icon: Icons.description_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'File upload and review.',
        ),
        ModuleItem(
          label: 'Duplicates',
          icon: Icons.warning_amber_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'Side-by-side comparison of many records.',
        ),
        ModuleItem(
          label: 'History',
          icon: Icons.history_outlined,
          availability: ModuleAvailability.planned,
          phase: 2,
        ),
        ModuleItem(
          label: 'ID Cards',
          icon: Icons.badge_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'Layout and printing.',
        ),
      ],
    ),

    // ── Attendance — the spine, mostly delivered ──────────────────────────
    ModuleSection(
      label: 'Attendance',
      icon: Icons.fact_check_outlined,
      initiallyExpanded: true,
      items: <ModuleItem>[
        ModuleItem(
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
          route: AppRoutes.home,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'Attendance Logs',
          icon: Icons.receipt_long_outlined,
          route: AppRoutes.attendanceLog,
          availability: ModuleAvailability.live,
          permission: 'attendance.view',
        ),
        ModuleItem(
          label: 'Time Health',
          icon: Icons.schedule_outlined,
          route: AppRoutes.timeHealth,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'Shifts',
          icon: Icons.swap_horiz_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
        ),
        ModuleItem(
          label: 'Holidays',
          icon: Icons.beach_access_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
        ),
        ModuleItem(
          label: 'Health Center',
          icon: Icons.monitor_heart_outlined,
          route: AppRoutes.timeHealth,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'Recovery Center',
          icon: Icons.restore_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
        ),
        ModuleItem(
          label: 'Trends',
          icon: Icons.show_chart_outlined,
          route: AppRoutes.attendanceTrends,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'Event Explorer',
          icon: Icons.travel_explore_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
        ),
      ],
    ),

    // ── Devices & Biometrics ──────────────────────────────────────────────
    ModuleSection(
      label: 'Devices & Biometrics',
      icon: Icons.sensors_outlined,
      items: <ModuleItem>[
        ModuleItem(
          label: 'Devices',
          icon: Icons.devices_other_outlined,
          route: AppRoutes.timeHealth,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'Device Intelligence',
          icon: Icons.memory_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
        ),
        ModuleItem(
          label: 'Identity Matching',
          icon: Icons.person_search_outlined,
          route: AppRoutes.unmatchedPunches,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'Enrollment Station',
          icon: Icons.fingerprint_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'Fingerprint capture needs the device on a LAN.',
        ),
        ModuleItem(
          label: 'Device Logs',
          icon: Icons.article_outlined,
          route: AppRoutes.attendanceLog,
          availability: ModuleAvailability.live,
        ),
      ],
    ),

    // ── Gate & Movement ───────────────────────────────────────────────────
    ModuleSection(
      label: 'Gate & Movement',
      icon: Icons.door_front_door_outlined,
      items: <ModuleItem>[
        ModuleItem(
          label: 'Pass-outs',
          icon: Icons.logout_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
        ),
        ModuleItem(
          label: 'Gate Mode',
          icon: Icons.sensor_door_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
        ),
        ModuleItem(
          label: 'Visitation Cards',
          icon: Icons.badge_outlined,
          availability: ModuleAvailability.planned,
          phase: 4,
        ),
      ],
    ),

    // ── Staff & Roles ─────────────────────────────────────────────────────
    ModuleSection(
      label: 'Staff & Roles',
      icon: Icons.badge_outlined,
      items: <ModuleItem>[
        ModuleItem(
          label: 'View Staff',
          icon: Icons.work_outline,
          availability: ModuleAvailability.planned,
          phase: 2,
        ),
        ModuleItem(
          label: 'User Management',
          icon: Icons.manage_accounts_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
          superAdminOnly: true,
        ),
        ModuleItem(
          label: 'Roles & Permissions',
          icon: Icons.shield_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'Permission matrices need width.',
          superAdminOnly: true,
        ),
        ModuleItem(
          label: 'Departments',
          icon: Icons.apartment_outlined,
          availability: ModuleAvailability.planned,
          phase: 4,
          superAdminOnly: true,
        ),
        ModuleItem(
          label: 'Audit Trail',
          icon: Icons.plagiarism_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
          superAdminOnly: true,
        ),
      ],
    ),

    // ── Academics ─────────────────────────────────────────────────────────
    ModuleSection(
      label: 'Academics',
      icon: Icons.menu_book_outlined,
      items: <ModuleItem>[
        ModuleItem(
          label: 'Classes',
          icon: Icons.class_outlined,
          availability: ModuleAvailability.planned,
          phase: 2,
        ),
        ModuleItem(
          label: 'Streams',
          icon: Icons.alt_route_outlined,
          availability: ModuleAvailability.planned,
          phase: 2,
        ),
        ModuleItem(
          label: 'Subjects',
          icon: Icons.subject_outlined,
          availability: ModuleAvailability.planned,
          phase: 2,
        ),
        ModuleItem(
          label: 'Timetable',
          icon: Icons.calendar_view_week_outlined,
          availability: ModuleAvailability.planned,
          phase: 2,
        ),
        ModuleItem(
          label: 'Academic Years',
          icon: Icons.calendar_today_outlined,
          route: AppRoutes.schoolSetup,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'Terms',
          icon: Icons.event_note_outlined,
          route: AppRoutes.schoolSetup,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'Results',
          icon: Icons.grading_outlined,
          availability: ModuleAvailability.planned,
          phase: 4,
        ),
        ModuleItem(
          label: 'Report Cards',
          icon: Icons.description_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'DRCE is a canvas layout engine — it needs a large screen.',
        ),
        ModuleItem(
          label: 'Promotions',
          icon: Icons.trending_up_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'Bulk operation across a whole cohort.',
        ),
      ],
    ),

    // ── Finance ───────────────────────────────────────────────────────────
    ModuleSection(
      label: 'Finance',
      icon: Icons.payments_outlined,
      items: <ModuleItem>[
        ModuleItem(
          label: 'Overview',
          icon: Icons.account_balance_wallet_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
        ),
        ModuleItem(
          label: 'Learner Fees',
          icon: Icons.receipt_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
        ),
        ModuleItem(
          label: 'Payments',
          icon: Icons.point_of_sale_outlined,
          availability: ModuleAvailability.planned,
          phase: 4,
          note: 'Needs server-side idempotency before it can be written to.',
        ),
        ModuleItem(
          label: 'Fee Rules',
          icon: Icons.rule_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'Rule authoring is spreadsheet-shaped work.',
        ),
        ModuleItem(
          label: 'Ledger',
          icon: Icons.menu_book_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'Reconciliation needs width.',
        ),
        ModuleItem(
          label: 'Pocket Money',
          icon: Icons.savings_outlined,
          availability: ModuleAvailability.planned,
          phase: 4,
        ),
      ],
    ),

    // ── Tahfiz ────────────────────────────────────────────────────────────
    ModuleSection(
      label: 'Tahfiz',
      icon: Icons.auto_stories_outlined,
      items: <ModuleItem>[
        ModuleItem(
          label: 'Overview',
          icon: Icons.dashboard_outlined,
          availability: ModuleAvailability.planned,
          phase: 4,
        ),
        ModuleItem(
          label: 'Participants',
          icon: Icons.groups_outlined,
          availability: ModuleAvailability.planned,
          phase: 4,
        ),
        ModuleItem(
          label: 'Attendance',
          icon: Icons.fact_check_outlined,
          availability: ModuleAvailability.planned,
          phase: 4,
        ),
        ModuleItem(
          label: 'Records',
          icon: Icons.history_edu_outlined,
          availability: ModuleAvailability.planned,
          phase: 4,
        ),
      ],
    ),

    // ── Reports ───────────────────────────────────────────────────────────
    ModuleSection(
      label: 'Reports',
      icon: Icons.insights_outlined,
      items: <ModuleItem>[
        ModuleItem(
          label: 'Students',
          icon: Icons.groups_outlined,
          availability: ModuleAvailability.planned,
          phase: 2,
        ),
        ModuleItem(
          label: 'Staff',
          icon: Icons.badge_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
        ),
        ModuleItem(
          label: 'Finance',
          icon: Icons.payments_outlined,
          availability: ModuleAvailability.planned,
          phase: 3,
        ),
        ModuleItem(
          label: 'Custom Reports',
          icon: Icons.tune_outlined,
          availability: ModuleAvailability.webOnly,
          note: 'Report building is desk work.',
        ),
      ],
    ),

    // ── Settings ──────────────────────────────────────────────────────────
    ModuleSection(
      label: 'Settings',
      icon: Icons.settings_outlined,
      items: <ModuleItem>[
        ModuleItem(
          label: 'Appearance',
          icon: Icons.palette_outlined,
          route: AppRoutes.appearance,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'School Setup',
          icon: Icons.tune_outlined,
          route: AppRoutes.schoolSetup,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'Profile',
          icon: Icons.person_outline,
          route: AppRoutes.profile,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'Diagnostics',
          icon: Icons.bug_report_outlined,
          route: AppRoutes.diagnostics,
          availability: ModuleAvailability.live,
        ),
        ModuleItem(
          label: 'About DRAIS',
          icon: Icons.info_outline,
          route: AppRoutes.about,
          availability: ModuleAvailability.live,
        ),
      ],
    ),
  ];

  /// How many destinations work today, across every section.
  static int get liveCount =>
      sections.fold(0, (int total, ModuleSection s) => total + s.liveCount);

  /// How many exist in the catalogue at all.
  static int get totalCount =>
      sections.fold(0, (int total, ModuleSection s) => total + s.items.length);
}
