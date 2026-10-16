import 'package:drais/core/error/result.dart';

/// `workplans.status` — the web page's four values.
enum WorkPlanStatus {
  /// Not started.
  pending('pending', 'Pending'),

  /// Under way.
  inProgress('in_progress', 'In progress'),

  /// Done.
  completed('completed', 'Completed'),

  /// Dropped.
  cancelled('cancelled', 'Cancelled');

  const WorkPlanStatus(this.wireValue, this.label);

  /// Stored value.
  final String wireValue;

  /// Label.
  final String label;

  /// Resolves a stored value; unknown values read as pending.
  static WorkPlanStatus fromWire(String? v) => WorkPlanStatus.values.firstWhere(
    (WorkPlanStatus s) => s.wireValue == v,
    orElse: () => WorkPlanStatus.pending,
  );
}

/// `workplans.priority`.
enum WorkPlanPriority {
  /// Low.
  low('low', 'Low'),

  /// Medium — the default.
  medium('medium', 'Medium'),

  /// High.
  high('high', 'High'),

  /// Critical.
  critical('critical', 'Critical');

  const WorkPlanPriority(this.wireValue, this.label);

  /// Stored value.
  final String wireValue;

  /// Label.
  final String label;

  /// Resolves a stored value; unknown values read as medium.
  static WorkPlanPriority fromWire(String? v) =>
      WorkPlanPriority.values.firstWhere(
        (WorkPlanPriority p) => p.wireValue == v,
        orElse: () => WorkPlanPriority.medium,
      );
}

/// One work plan — a row of `GET /api/work-plans`.
class WorkPlan {
  /// Creates a plan.
  const WorkPlan({
    required this.id,
    required this.title,
    required this.status,
    required this.priority,
    this.description,
    this.ownerType,
    this.startDatetime,
    this.endDatetime,
    this.progress = 0,
    this.assignedTo,
    this.assigneeName,
    this.departmentName,
    this.createdAt,
  });

  /// Row id.
  final int id;

  /// Title.
  final String title;

  /// Description.
  final String? description;

  /// `school` | `department` | …
  final String? ownerType;

  /// Start, as stored — wall-clock time from the web's `datetime-local`.
  final String? startDatetime;

  /// End, as stored.
  final String? endDatetime;

  /// Status.
  final WorkPlanStatus status;

  /// Priority.
  final WorkPlanPriority priority;

  /// 0–100.
  final int progress;

  /// `staff.id`.
  final int? assignedTo;

  /// Assignee's name.
  final String? assigneeName;

  /// Department, for department-owned plans.
  final String? departmentName;

  /// When created.
  final String? createdAt;
}

/// Work plans.
///
/// | Method | LongTerm source |
/// |---|---|
/// | [list] | `GET /api/work-plans` (`work_plans` module) |
/// | [create] | `POST /api/work-plans` |
/// | [update] | `PATCH /api/work-plans`, **school-scoped here** (see PARITY §4.7) |
abstract interface class WorkPlansRepository {
  /// Plans, newest first.
  Future<Result<List<WorkPlan>>> list({
    WorkPlanStatus? status,
    WorkPlanPriority? priority,
  });

  /// Creates a school-level plan; returns its id.
  Future<Result<int>> create({
    required String title,
    String? description,
    WorkPlanPriority priority = WorkPlanPriority.medium,
    String? startDatetime,
    String? endDatetime,
  });

  /// Writes every field of [plan], as the route does.
  Future<Result<void>> update(WorkPlan plan);
}
