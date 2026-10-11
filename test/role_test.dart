import 'package:attendance_and_event_management/core/constants/role.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RoleX.fromString', () {
    test('maps database staff role to the organizer role', () {
      expect(RoleX.fromString('Cán bộ'), Role.organizer);
      expect(RoleX.fromString('cán bộ'), Role.organizer);
      expect(RoleX.fromString('Nhân viên'), Role.organizer);
      expect(RoleX.fromString('Công nhân viên'), Role.organizer);
      expect(RoleX.fromString('công nhân viên'), Role.organizer);
      expect(RoleX.fromString('Ban tổ chức'), Role.organizer);
    });

    test('admin, event organizers, and assigned staff can manage events', () {
      expect(RoleX.canManageEvents('Cán bộ'), isTrue);
      expect(RoleX.canManageEvents('Nhân viên'), isTrue);
      expect(RoleX.canManageEvents('Công nhân viên'), isTrue);
      expect(RoleX.canManageEvents('organizer'), isFalse);
      expect(RoleX.canManageEvents('Ban tổ chức'), isTrue);
      expect(RoleX.canManageEvents('admin'), isTrue);
      expect(RoleX.canManageEvents('Admin'), isTrue);
    });

    test('uses the database staff label in the interface', () {
      expect(Role.organizer.label, 'Công nhân viên');
      expect(Role.organizer.shortCode, 'NV');
    });
  });
}
