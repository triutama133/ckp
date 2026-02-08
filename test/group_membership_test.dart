import 'package:flutter_test/flutter_test.dart';
import 'package:catatan_keuangan_pintar/services/db_service.dart';
import 'package:catatan_keuangan_pintar/services/group_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  test('create invite and accept invite (local DB)', () async {
    final uuid = Uuid();
    final gId = 'test_group_${uuid.v4()}';
    final group = Group(id: gId, name: 'Test Group', description: 'for tests', icon: null, createdAt: DateTime.now(), createdBy: 'test_user');
    await DBService.instance.insertGroup(group);

    final invite = await GroupService.instance.generateInvite(gId, 'test_user');
    expect(invite.groupId, gId);
    expect(invite.token.isNotEmpty, true);

    final member = await GroupService.instance.acceptInvite(invite.token, 'new_user');
    expect(member, isNotNull);
    expect(member!.groupId, gId);

    // cleanup
    await DBService.instance.deleteInvite(invite.id);
    await DBService.instance.deleteGroup(gId);
  });
}
