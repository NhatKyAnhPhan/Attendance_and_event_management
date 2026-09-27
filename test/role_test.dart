import 'package:attendance_and_event_management/core/constants/role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoleX.fromString', () {
    test('maps database staff role to the organizer role', () {
      expect(RoleX.fromString('Cán bộ'), Role.organizer);
      expect(RoleX.fromString('cán bộ'), Role.organizer);
      expect(RoleX.fromString('Nhân viên'), Role.organizer);
      expect(RoleX.fromString('Ban tổ chức'), Role.organizer);
    });

    test('only admin and event organizers can manage events', () {
      expect(RoleX.canManageEvents('Cán bộ'), isFalse);
      expect(RoleX.canManageEvents('Nhân viên'), isFalse);
      expect(RoleX.canManageEvents('organizer'), isFalse);
      expect(RoleX.canManageEvents('Ban tổ chức'), isTrue);
      expect(RoleX.canManageEvents('admin'), isTrue);
      expect(RoleX.canManageEvents('Admin'), isTrue);
    });

    test('uses the database staff label in the interface', () {
      expect(Role.organizer.label, 'Cán bộ');
      expect(Role.organizer.shortCode, 'CB');
    });
  });
}
