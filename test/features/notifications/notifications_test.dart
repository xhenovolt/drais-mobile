import 'package:flutter_test/flutter_test.dart';

import 'package:drais/features/notifications/data/notifications_direct_repository.dart';
import 'package:drais/features/notifications/domain/notifications.dart';

void main() {
  group('metadata', () {
    test('JSON text is decoded, as the service does', () {
      expect(
        NotificationsDirectRepository.parseMetadata('{"link":"/students/12"}'),
        <String, Object?>{'link': '/students/12'},
      );
    });

    test('an already-decoded map passes through', () {
      expect(
        NotificationsDirectRepository.parseMetadata(<String, Object?>{'a': 1}),
        <String, Object?>{'a': 1},
      );
    });

    test('bad JSON is an empty map, not a failed inbox', () {
      expect(NotificationsDirectRepository.parseMetadata('{nope'), isEmpty);
      expect(NotificationsDirectRepository.parseMetadata(null), isEmpty);
      expect(NotificationsDirectRepository.parseMetadata(''), isEmpty);
    });
  });

  test('link is read only when it is a non-empty string', () {
    NotificationItem n(Map<String, Object?> m) =>
        NotificationItem(id: 1, title: 't', createdAtRaw: '', metadata: m);
    expect(n(<String, Object?>{'link': '/attendance'}).link, '/attendance');
    expect(n(<String, Object?>{'link': ''}).link, isNull);
    expect(n(<String, Object?>{'link': 5}).link, isNull);
    expect(n(const <String, Object?>{}).link, isNull);
  });
}
