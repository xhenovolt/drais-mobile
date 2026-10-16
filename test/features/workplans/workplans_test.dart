import 'package:flutter_test/flutter_test.dart';

import 'package:drais/features/workplans/domain/workplans.dart';

void main() {
  test('statuses and priorities are the web page\'s values', () {
    expect(
      WorkPlanStatus.values.map((WorkPlanStatus s) => s.wireValue),
      <String>['pending', 'in_progress', 'completed', 'cancelled'],
    );
    expect(
      WorkPlanPriority.values.map((WorkPlanPriority p) => p.wireValue),
      <String>['low', 'medium', 'high', 'critical'],
    );
  });

  test('unknown stored values fall back to the route defaults', () {
    expect(WorkPlanStatus.fromWire('archived'), WorkPlanStatus.pending);
    expect(WorkPlanPriority.fromWire(null), WorkPlanPriority.medium);
    expect(WorkPlanStatus.fromWire('in_progress'), WorkPlanStatus.inProgress);
  });
}
