import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/models/mail_folder_info.dart';
import 'package:kaydetmail/utils/folder_rules.dart';

MailFolderInfo _f(
  String id,
  String name, {
  FolderKind kind = FolderKind.custom,
  String? parent,
  int? total,
  FolderKind? role,
}) => MailFolderInfo(
  accountId: 'a',
  folderId: id,
  name: name,
  fullName: name,
  kind: kind,
  isSyncEnabled: false,
  parentFolderId: parent,
  totalCount: total,
  roleOverride: role,
);

void main() {
  group('permissions', () {
    test('only custom folders can be renamed, moved or deleted', () {
      final custom = _f('1', 'Projeler');
      final inbox = _f('2', 'INBOX', kind: FolderKind.inbox);
      expect(FolderRules.canRename(custom), isTrue);
      expect(FolderRules.canMove(custom), isTrue);
      expect(FolderRules.canDelete(custom), isTrue);
      expect(FolderRules.canRename(inbox), isFalse);
      expect(FolderRules.canMove(inbox), isFalse);
      expect(FolderRules.canDelete(inbox), isFalse);
    });

    test('a folder holding a user role can always be reset', () {
      final assigned = _f(
        '1',
        'Sent Items',
        kind: FolderKind.sent,
        role: FolderKind.sent,
      );
      expect(FolderRules.canAssignRole(assigned), isTrue);
      expect(FolderRules.canAssignRole(_f('2', 'X')), isTrue);
      expect(
        FolderRules.canAssignRole(_f('3', 'Sent', kind: FolderKind.sent)),
        isFalse,
      );
    });
  });

  group('deleteBlocker', () {
    test(
      'standard, non-empty and parent folders are blocked with a reason',
      () {
        final parent = _f('1', 'Parent');
        final child = _f('2', 'Child', parent: '1');
        final full = _f('3', 'Full', total: 4);
        final all = [parent, child, full];
        expect(
          FolderRules.deleteBlocker(
            _f('9', 'INBOX', kind: FolderKind.inbox),
            all,
          ),
          contains('Standart'),
        );
        expect(FolderRules.deleteBlocker(parent, all), contains('alt klasör'));
        expect(FolderRules.deleteBlocker(full, all), contains('e-posta var'));
        expect(FolderRules.deleteBlocker(child, all), isNull);
      },
    );
  });

  group('validateName', () {
    test(
      'rejects empty, control chars, wildcards, delimiter and reserved names',
      () {
        expect(FolderRules.validateName('  '), isNotNull);
        expect(FolderRules.validateName('a\nb'), isNotNull);
        expect(FolderRules.validateName('a*b'), isNotNull);
        expect(FolderRules.validateName('50%'), isNotNull);
        expect(
          FolderRules.validateName('a.b', delimiter: '.'),
          contains('"."'),
        );
        expect(FolderRules.validateName('a.b', delimiter: '/'), isNull);
        expect(FolderRules.validateName('..'), isNotNull);
        expect(FolderRules.validateName('inbox'), isNotNull);
        expect(FolderRules.validateName('x' * 201), isNotNull);
        expect(FolderRules.validateName('Projeler'), isNull);
      },
    );

    test(
      'same-level duplicates are rejected case-insensitively, except self',
      () {
        final existing = _f('1', 'Projeler');
        expect(
          FolderRules.validateName('projeler', siblings: [existing]),
          'Bu adda bir klasör zaten var.',
        );
        expect(
          FolderRules.validateName(
            'PROJELER',
            siblings: [existing],
            self: existing,
          ),
          isNull,
        );
      },
    );
  });

  test('FolderKind maps backend types', () {
    expect(FolderKind.fromBackend('Junk').logical?.name, 'spam');
    expect(FolderKind.fromBackend('Custom').isStandard, isFalse);
    expect(FolderKind.fromBackend('???'), FolderKind.unknown);
  });
}
