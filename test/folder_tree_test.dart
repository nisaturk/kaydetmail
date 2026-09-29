import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/mail_folder_info.dart';
import 'package:kaydetmail/utils/folder_tree.dart';

MailFolderInfo _f(
  String id,
  String name, {
  FolderKind kind = FolderKind.custom,
  String? parent,
}) => MailFolderInfo(
  accountId: 'a',
  folderId: id,
  name: name,
  fullName: name,
  kind: kind,
  isSyncEnabled: false,
  parentFolderId: parent,
);

void main() {
  test(
    'standard folders lead in fixed order; custom nest under INBOX by parentId',
    () {
      final rows = buildFolderRows([
        _f('trash', 'Trash', kind: FolderKind.trash),
        _f('z', 'Zeta', parent: 'inbox'),
        _f('a', 'alpha', parent: 'inbox'),
        _f('inbox', 'INBOX', kind: FolderKind.inbox),
        _f('sent', 'Sent', kind: FolderKind.sent),
        _f('deep', 'Deep', parent: 'a'),
      ]);
      expect(
        [for (final r in rows) '${r.depth}:${r.folder.name}'],
        ['0:INBOX', '1:alpha', '2:Deep', '1:Zeta', '0:Sent', '0:Trash'],
      );
    },
  );

  test('a missing parent or a parent cycle never hides a folder', () {
    final rows = buildFolderRows([
      _f('orphan', 'Orphan', parent: 'gone'),
      _f('x', 'X', parent: 'y'),
      _f('y', 'Y', parent: 'x'),
      _f('self', 'Self', parent: 'self'),
    ]);
    expect(rows.map((r) => r.folder.folderId).toSet(), {
      'orphan',
      'x',
      'y',
      'self',
    });
    expect(rows, hasLength(4));
  });

  test('subtreeIds includes the folder and all descendants only', () {
    final all = [
      _f('a', 'A'),
      _f('b', 'B', parent: 'a'),
      _f('c', 'C', parent: 'b'),
      _f('d', 'D'),
    ];
    expect(subtreeIds(all, 'a'), {'a', 'b', 'c'});
    expect(subtreeIds(all, 'd'), {'d'});
  });
}
