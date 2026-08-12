# Table Dictionary

Every base table in the DRAIS schema, grouped by domain.

**Generated from `information_schema` against the live database.** Regenerate it rather than editing by hand — see "Regenerating" at the end.

## How to read this

- **Scope — `school`**: the table has a `school_id` column and is tenant-owned. Per-school operations (backup, export, hard-delete) discover these automatically.
- **Scope — `global`**: no `school_id`. Either genuinely global reference data (districts, nationalities, Qur'an structure), platform-level tables (`schools`, `schema_migrations`, platform API keys), **or** a table that is tenant-owned but reached through a foreign key rather than a direct column — e.g. `class_subjects` → `classes.school_id`, `biometric_templates` → `biometric_enrollments.school_id`.

  > **Do not read `global` as "safe to expose across tenants".** Roughly a third of these are school data one join away. The backup engine resolves this properly by walking FK paths (`src/lib/backup/discovery.ts`); anything else touching tenant data must do the same.

- **Soft-delete**: has a `deleted_at` column. See [`../PHASE_1_CRUD_TRASH_ARCHITECTURE.md`](../PHASE_1_CRUD_TRASH_ARCHITECTURE.md).
- **Approx rows**: `information_schema.TABLE_ROWS` — a TiDB **estimate**, sometimes badly wrong right after writes. Useful for relative scale only. Never use it where an exact count matters.

## Summary

| | Count |
|---|---|
| Base tables | 292 |
| With `school_id` (directly tenant-scoped) | 209 |
| Without `school_id` (global, platform, or FK-scoped) | 83 |
| With `deleted_at` (soft-delete) | 45 |

### Attendance (33 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `attendance_acquisition_records` | global | — | 546 |
| `attendance_acquisitions` | school | — | 3 |
| `attendance_audit_logs` | school | — | 0 |
| `attendance_daily_aggregates` | school | — | 0 |
| `attendance_first_arrival_anchors` | school | — | 106 |
| `attendance_first_arrival_health` | school | — | 3 |
| `attendance_live_ui_settings` | school | — | 4 |
| `attendance_logs` | school | — | 0 |
| `attendance_processing_queue` | school | — | 0 |
| `attendance_raw_events` | school | — | 10,342 |
| `attendance_reconciliation` | school | — | 0 |
| `attendance_records` | school | — | 11,456 |
| `attendance_reports` | school | — | 0 |
| `attendance_rule_day_overrides` | global | — | 2 |
| `attendance_rules` | school | — | 25 |
| `attendance_sessions` | school | yes | 0 |
| `attendance_time_baselines` | school | — | 5 |
| `attendance_time_corrections` | school | — | 12 |
| `attendance_time_policy` | school | — | 1 |
| `attendance_users` | school | — | 0 |
| `daily_attendance` | school | — | 0 |
| `device_user_directory` | school | — | 1,404 |
| `device_user_mappings` | school | — | 1 |
| `device_users` | school | — | 0 |
| `shift_assignments` | school | — | 0 |
| `shifts` | school | — | 0 |
| `zk_attendance_logs` | school | — | 11,171 |
| `zk_device_commands` | school | — | 3,062 |
| `zk_device_logs` | school | — | 139,028 |
| `zk_devices` | school | — | 5 |
| `zk_parsed_logs` | school | — | 256,420 |
| `zk_raw_logs` | school | — | 53,182 |
| `zk_user_mapping` | school | — | 2,160 |

### Biometrics (8 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `biometric_devices` | school | yes | 0 |
| `biometric_enrollments` | school | — | 2,379 |
| `biometric_enrollments_legacy` | school | — | 424 |
| `biometric_mapping_history` | school | — | 407 |
| `biometric_match_suggestions` | school | — | 36 |
| `biometric_templates` | global | — | 450 |
| `fingerprint_orphans` | school | — | 86 |
| `fingerprints` | school | — | 0 |

### Devices (23 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `dahua_attendance_logs` | global | — | 0 |
| `dahua_devices` | school | — | 0 |
| `dahua_raw_logs` | global | — | 0 |
| `dahua_sync_history` | global | — | 0 |
| `device_access_logs` | global | — | 0 |
| `device_alerts` | school | — | 0 |
| `device_clock_health` | school | — | 17 |
| `device_configs` | school | yes | 0 |
| `device_connection_history` | global | — | 0 |
| `device_directory_audit` | school | — | 62 |
| `device_heartbeats` | global | — | 43,896 |
| `device_inventory_runs` | school | — | 14 |
| `device_log_sync_runs` | school | — | 1 |
| `device_reconciliation_items` | school | — | 156 |
| `device_reconciliation_runs` | school | — | 5 |
| `device_school_hidden` | school | — | 0 |
| `device_sync_checkpoints` | school | — | 0 |
| `device_sync_logs` | school | — | 0 |
| `device_sync_state` | school | — | 3 |
| `device_transfers` | global | — | 3 |
| `devices` | school | yes | 3 |
| `relay_agents` | global | — | 1 |
| `relay_commands` | global | — | 12 |

### Students & enrollment (35 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `admission_audit` | school | — | 5 |
| `admission_documents` | school | — | 0 |
| `admissions` | school | yes | 2 |
| `enrollment_history` | school | — | 686 |
| `enrollment_programs` | global | — | 784 |
| `enrollment_sessions` | school | — | 483 |
| `enrollments` | school | yes | 7,378 |
| `passout_events` | school | — | 452 |
| `passout_requests` | school | yes | 1 |
| `promotion_audit_log` | school | — | 0 |
| `promotion_criteria` | school | — | 0 |
| `promotions` | school | yes | 334 |
| `student_additional_info` | global | — | 0 |
| `student_attendance` | school | — | 0 |
| `student_component_results` | school | — | 0 |
| `student_contacts` | global | — | 8 |
| `student_curriculums` | global | — | 632 |
| `student_custom_values` | global | — | 0 |
| `student_documents` | school | — | 0 |
| `student_education_levels` | global | — | 0 |
| `student_family_status` | global | — | 0 |
| `student_fee_items` | global | — | 16,722 |
| `student_fingerprints` | school | — | 0 |
| `student_generic_skills` | school | — | 0 |
| `student_hafz_progress_summary` | global | — | 0 |
| `student_history` | school | — | 0 |
| `student_ledger` | school | — | 16,613 |
| `student_next_of_kin` | global | — | 0 |
| `student_parents` | global | — | 0 |
| `student_profiles` | global | — | 0 |
| `student_projects` | school | — | 0 |
| `student_requirements` | global | — | 0 |
| `students` | school | yes | 6,124 |
| `visitation_cards` | school | — | 0 |
| `visitation_events` | school | — | 0 |

### Academics (16 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `academic_programs` | school | — | 3 |
| `academic_years` | school | yes | 11 |
| `class_results` | global | yes | 19,003 |
| `class_subjects` | global | — | 218 |
| `class_teachers` | school | — | 0 |
| `classes` | school | yes | 76 |
| `curriculums` | global | yes | 1 |
| `exams` | school | yes | 175 |
| `result_submission_deadlines` | school | — | 0 |
| `result_types` | school | yes | 11 |
| `results` | school | — | 16,579 |
| `streams` | school | yes | 34 |
| `subject_groups` | school | — | 0 |
| `subject_report_order` | school | — | 0 |
| `subjects` | school | yes | 68 |
| `terms` | school | yes | 17 |

### Reports & templates (13 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `drce_blocks` | school | — | 0 |
| `drce_document_versions` | global | — | 26 |
| `drce_starters` | school | — | 2 |
| `dvcf_active_documents` | school | — | 4 |
| `dvcf_documents` | school | — | 21 |
| `report_card_metrics` | global | — | 0 |
| `report_card_overrides` | global | — | 2 |
| `report_card_subjects` | global | — | 0 |
| `report_cards` | global | — | 0 |
| `report_comment_rules` | school | — | 1 |
| `report_overall_comment_rules` | school | — | 0 |
| `report_snapshots` | school | — | 21 |
| `report_templates` | school | — | 6 |

### Finance (23 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `budgets` | school | — | 0 |
| `fee_assignment_log` | school | — | 0 |
| `fee_clearance_exceptions` | school | — | 0 |
| `fee_eligibility_rules` | school | — | 28 |
| `fee_invoices` | school | — | 0 |
| `fee_items` | school | — | 30 |
| `fee_payment_allocations` | global | — | 0 |
| `fee_payments` | global | — | 0 |
| `fee_structures` | school | — | 0 |
| `finance_account_transfers` | school | — | 0 |
| `finance_accounts` | school | — | 2 |
| `finance_actions` | school | — | 4 |
| `finance_categories` | school | — | 0 |
| `finance_fee_items` | school | — | 0 |
| `finance_import_batches` | school | — | 0 |
| `finance_import_rows` | school | — | 0 |
| `finance_payments` | school | — | 4 |
| `learner_fee_adjustments` | school | yes | 1 |
| `payment_reconciliations` | school | — | 4 |
| `pocket_money_accounts` | school | — | 0 |
| `pocket_money_transactions` | school | — | 0 |
| `receipts` | school | — | 4 |
| `wallets` | school | — | 1 |

### Tahfiz (20 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `tahfiz_attendance` | school | — | 0 |
| `tahfiz_books` | school | — | 0 |
| `tahfiz_custom_book_units` | school | — | 0 |
| `tahfiz_custom_books` | school | yes | 0 |
| `tahfiz_enrollments` | school | yes | 1 |
| `tahfiz_evaluations` | school | — | 0 |
| `tahfiz_global_books` | global | — | 1 |
| `tahfiz_group_members` | school | — | 0 |
| `tahfiz_groups` | school | — | 1 |
| `tahfiz_plans` | school | — | 0 |
| `tahfiz_portions` | school | — | 0 |
| `tahfiz_quran_hizb` | global | — | 60 |
| `tahfiz_quran_juz` | global | — | 30 |
| `tahfiz_quran_pages` | global | — | 604 |
| `tahfiz_quran_quarters` | global | — | 240 |
| `tahfiz_quran_surahs` | global | — | 114 |
| `tahfiz_records` | school | — | 0 |
| `tahfiz_results` | school | yes | 0 |
| `tahfiz_school_books` | school | — | 3 |
| `tahfiz_seven_metrics` | school | — | 0 |

### Parent portal (4 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `parent_accounts` | global | — | 1 |
| `parent_otp_codes` | global | — | 5 |
| `parent_sessions` | global | — | 1 |
| `parent_student_links` | school | — | 3 |

### People, auth & access (16 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `auth_codes` | global | — | 0 |
| `password_resets` | global | — | 0 |
| `permissions` | global | — | 190 |
| `role_permissions` | global | — | 371 |
| `roles` | school | yes | 62 |
| `sessions` | school | — | 471 |
| `staff` | school | yes | 278 |
| `staff_attendance` | global | — | 0 |
| `staff_employment` | school | — | 37 |
| `staff_qualifications` | school | — | 0 |
| `staff_salaries` | school | — | 0 |
| `staff_subject_specializations` | school | — | 0 |
| `user_notifications` | school | — | 1,300 |
| `user_roles` | school | — | 33 |
| `user_sessions` | global | — | 0 |
| `users` | school | yes | 38 |

### Notifications & SMS (12 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `comm_dispatch_log` | school | — | 18 |
| `comm_rules` | school | — | 0 |
| `comm_settings` | school | — | 5 |
| `comm_templates` | school | — | 18 |
| `notification_deliveries` | school | — | 29 |
| `notification_outbox` | school | — | 36 |
| `notification_policies` | school | — | 5 |
| `notification_preferences` | school | — | 0 |
| `notification_queue` | global | — | 0 |
| `notification_templates` | school | — | 5 |
| `notifications` | school | yes | 1,722 |
| `sms_allocations` | school | — | 2 |

### Control Center & platform (18 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `control_audit_logs` | global | — | 327 |
| `control_login_attempts` | global | — | 5 |
| `control_sessions` | global | — | 6 |
| `control_users` | global | — | 1 |
| `platform_alerts` | school | — | 0 |
| `platform_api_audit` | school | — | 1,194 |
| `platform_api_keys` | global | — | 3 |
| `platform_events` | school | — | 2 |
| `platform_health_snapshots` | school | — | 0 |
| `platform_idempotency_keys` | global | — | 2 |
| `platform_invoices` | school | — | 2 |
| `platform_jobs` | global | — | 2 |
| `platform_payments` | school | — | 1 |
| `platform_rate_limits` | global | — | 138 |
| `platform_settings` | global | — | 2 |
| `subscription_plans` | global | — | 4 |
| `webhook_deliveries` | global | — | 0 |
| `webhook_subscriptions` | global | — | 0 |

### Backup (3 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `backup_chunks` | global | — | 0 |
| `backup_parts` | global | — | 0 |
| `backup_records` | school | — | 0 |

### Audit & system (5 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `audit_log` | school | — | 560 |
| `audit_logs` | school | — | 8,107 |
| `migration_runs` | global | — | 2 |
| `schema_migrations` | global | — | 44 |
| `system_logs` | global | — | 53,276 |

### Other modules (9 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `document_types` | global | — | 0 |
| `documents` | school | yes | 0 |
| `inventory_items` | school | yes | 0 |
| `inventory_transactions` | school | yes | 0 |
| `issuance_audit_log` | global | — | 3 |
| `issuance_batches` | school | — | 3 |
| `issuance_dedupe_keys` | school | — | 0 |
| `issuance_items` | global | — | 0 |
| `workplans` | school | yes | 2 |

### Reference & uncategorized (54 tables)

| Table | Scope | Soft-delete | Approx rows |
|---|---|---|---|
| `balance_reminders` | school | — | 0 |
| `branches` | school | yes | 0 |
| `contacts` | school | yes | 9 |
| `counties` | global | — | 0 |
| `custom_fields` | school | — | 2 |
| `deadline_reminder_log` | school | — | 0 |
| `department_workplans` | global | — | 0 |
| `departments` | school | yes | 53 |
| `districts` | global | — | 0 |
| `events` | school | — | 0 |
| `expenditures` | school | yes | 0 |
| `feature_flags` | school | yes | 0 |
| `financial_reports` | school | — | 0 |
| `holidays` | school | — | 0 |
| `import_errors` | global | — | 0 |
| `import_sessions` | school | — | 8 |
| `initials_edit_history` | school | — | 0 |
| `ledger` | school | — | 0 |
| `ledger_accounts` | school | — | 0 |
| `ledger_entries` | school | — | 0 |
| `ledger_transactions` | school | — | 0 |
| `living_statuses` | global | — | 3 |
| `manual_attendance_entries` | school | yes | 0 |
| `marks_migration_log` | school | — | 0 |
| `marks_migration_policies` | school | yes | 0 |
| `mobile_money_transactions` | school | — | 0 |
| `name_repair_changes` | school | — | 0 |
| `name_repair_sessions` | school | — | 0 |
| `nationalities` | global | — | 0 |
| `orphan_statuses` | global | — | 5 |
| `parents` | school | — | 0 |
| `parishes` | global | — | 0 |
| `payroll_definitions` | school | yes | 0 |
| `pending_device_users` | school | — | 297 |
| `people` | school | yes | 7,129 |
| `positions` | school | — | 41 |
| `programs` | school | — | 11 |
| `reminders` | school | — | 0 |
| `requirements_master` | school | — | 0 |
| `salary_payments` | school | yes | 0 |
| `school_info` | school | yes | 1 |
| `school_modules` | school | — | 188 |
| `school_settings` | school | — | 25 |
| `school_theme_settings` | school | — | 0 |
| `schools` | global | yes | 22 |
| `security_settings` | school | — | 0 |
| `settings` | school | — | 0 |
| `stores` | school | yes | 0 |
| `study_modes` | school | — | 3 |
| `subcounties` | global | — | 0 |
| `system_errors` | school | — | 17 |
| `template_distributions` | global | — | 450 |
| `villages` | global | yes | 0 |
| `waivers_discounts` | school | yes | 0 |

## Regenerating

This file is generated. To refresh it after schema changes, query `information_schema.TABLES` and `information_schema.COLUMNS` for `school_id` / `deleted_at` presence and regroup by the domain prefixes above. Grouping is heuristic (by table-name prefix), so a genuinely new domain may land in "Reference & uncategorized" until the rules are extended.

## Related

- [`MIGRATIONS.md`](MIGRATIONS.md) — the three schema-evolution mechanisms
- [`../adr/0008-two-auth-systems.md`](../adr/0008-two-auth-systems.md) — why `control_*` tables are separate
- `src/lib/backup/discovery.ts` — the authoritative FK-path resolution for tenant ownership
