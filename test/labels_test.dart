import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:kaydetmail/repositories/mock_mail_repository.dart';

void main() {
  setUp(() => MockMailRepository().resetMockData());

  group('label management', () {
    test('create label adds a trimmed label', () async {
      final repo = MockMailRepository();
      final before = repo.getLabels().length;
      final label = await repo.createLabel(
        name: '  new  ',
        color: const Color(0xFF112233),
      );
      expect(repo.getLabels().length, before + 1);
      expect(label.name, 'new');
    });

    test('rename label preserves the id', () async {
      final repo = MockMailRepository();
      final label = repo.getLabels().first;
      final originalId = label.id;

      await repo.updateLabel(id: label.id, name: 'Updated', color: label.color);

      final updated = repo.getLabels().firstWhere((l) => l.id == originalId);
      expect(updated.id, originalId);
      expect(updated.name, 'Updated');
    });

    test('recolor label preserves the id and updates color', () async {
      final repo = MockMailRepository();
      final label = repo.getLabels().first;
      final originalId = label.id;
      const newColor = Color(0xFF998877);

      await repo.updateLabel(id: label.id, name: label.name, color: newColor);

      final updated = repo.getLabels().firstWhere((l) => l.id == originalId);
      expect(updated.id, originalId);
      expect(updated.color, newColor);
    });

    test('update keeps an unchanged name without error', () async {
      final repo = MockMailRepository();
      final label = repo.getLabels().first;

      // Should not throw.
      await repo.updateLabel(
        id: label.id,
        name: label.name,
        color: label.color,
      );

      expect(repo.getLabels().any((l) => l.id == label.id), isTrue);
    });

    test('duplicate label names are rejected (case-insensitive)', () async {
      final repo = MockMailRepository();
      // Existing: 'İş' (lab-work). Try ASCII duplicate.
      await repo.createLabel(name: 'Unique', color: const Color(0xFFAABBCC));
      await expectLater(
        repo.createLabel(name: 'UNIQUE', color: const Color(0xFFDDEEFF)),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repo.createLabel(name: '  unique  ', color: const Color(0xFFDDEEFF)),
        throwsA(isA<ArgumentError>()),
      );
      // Turkish İ folding: 'İŞ' canonicalises to 'iş' same as 'İş'.
      await expectLater(
        repo.createLabel(name: 'İŞ', color: const Color(0xFF111111)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('renaming to a name held by another label is rejected', () async {
      final repo = MockMailRepository();
      final second = repo.getLabels()[1];
      await expectLater(
        repo.updateLabel(
          id: second.id,
          name: repo.getLabels()[0].name, // already used
          color: second.color,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('empty label name is rejected', () async {
      final repo = MockMailRepository();
      await expectLater(
        repo.createLabel(name: '', color: const Color(0xFF000000)),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repo.createLabel(name: '   ', color: const Color(0xFF000000)),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('delete label removes it from getLabels()', () async {
      final repo = MockMailRepository();
      final target = repo.getLabels().first;
      final beforeCount = repo.getLabels().length;

      await repo.deleteLabel(target.id);

      expect(repo.getLabels().length, beforeCount - 1);
      expect(repo.getLabels().any((l) => l.id == target.id), isFalse);
    });

    test(
      'deleting a label strips its id from mails but keeps the mails',
      () async {
        final repo = MockMailRepository();
        final target = repo.getLabels().first; // İş (lab-work)
        final mailCountBefore = repo.getAllEmails().length;
        final workMailIds = repo
            .getAllEmails()
            .where((e) => e.labelIds.contains(target.id))
            .map((e) => e.id)
            .toList();
        expect(workMailIds, isNotEmpty);

        await repo.deleteLabel(target.id);

        // No email deleted.
        expect(repo.getAllEmails().length, mailCountBefore);
        // The label id is gone from every mail.
        final remaining = repo.getAllEmails();
        expect(remaining.any((e) => e.labelIds.contains(target.id)), isFalse);
        // Each previously-tagged mail still exists (same ids present).
        for (final id in workMailIds) {
          expect(remaining.any((e) => e.id == id), isTrue);
        }
      },
    );

    test('deleting unknown label id is a safe no-op', () async {
      final repo = MockMailRepository();
      final before = repo.getLabels().length;
      await repo.deleteLabel('nonexistent-label');
      expect(repo.getLabels().length, before);
    });
  });

  group('search', () {
    test('text search still works', () {
      final repo = MockMailRepository();
      final results = repo.searchEmails(query: 'invoice');
      expect(results.map((e) => e.id), contains('seed-finance-invoice'));
    });

    test('label-only filter returns only mails carrying that label', () {
      final repo = MockMailRepository();
      final results = repo.searchEmails(labelId: 'lab-work');
      expect(results, isNotEmpty);
      expect(results.every((e) => e.labelIds.contains('lab-work')), isTrue);
    });

    test('text + label uses AND semantics', () {
      final repo = MockMailRepository();
      final withBoth = repo.searchEmails(
        query: 'invoice',
        labelId: 'lab-finance',
      );
      expect(withBoth.map((e) => e.id), contains('seed-finance-invoice'));
      // The same text without the matching label: still matches by text but
      // the mail carries only finance, not work, so the row vanishes.
      final withWrongLabel = repo.searchEmails(
        query: 'invoice',
        labelId: 'lab-work',
      );
      expect(
        withWrongLabel.any((e) => e.id == 'seed-finance-invoice'),
        isFalse,
      );
    });

    test('clearing the text query does not reset the label filter', () {
      final repo = MockMailRepository();
      final labelOnly = repo.searchEmails(labelId: 'lab-work');
      final emptyQuery = repo.searchEmails(query: '', labelId: 'lab-work');
      expect(emptyQuery.length, labelOnly.length);
    });

    test('Tümü (null labelId) removes the label restriction', () {
      final repo = MockMailRepository();
      final withLabel = repo.searchEmails(labelId: 'lab-travel');
      final withoutLabel = repo.searchEmails();
      expect(withoutLabel.length, greaterThan(withLabel.length));
    });

    test('threads are not duplicated', () {
      final repo = MockMailRepository();
      final results = repo.searchEmails(labelId: 'lab-work');
      final threadIds = results
          .where((e) => e.threadId.isNotEmpty)
          .map((e) => e.threadId)
          .toSet();
      final threadRows = results.where((e) => e.threadId.isNotEmpty).toList();
      expect(threadRows.length, threadIds.length);
    });

    test(
      'a thread is included when another member carries the label',
      () async {
        final repo = MockMailRepository();
        // Remove work label from the newest member (alice-onboarding-reply).
        await repo.removeLabelsFromEmails(
          ['seed-alice-onboarding-reply'],
          ['lab-work'],
        );
        final results = repo.searchEmails(query: 'design', labelId: 'lab-work');
        final rows = results
            .where((e) => e.threadId == 'thread-onboarding')
            .toList();
        expect(rows, hasLength(1));
        // The representative is the newest still-matching message.
        expect(rows.single.id, 'seed-sent-onboarding');
        expect(rows.single.labelIds, contains('lab-work'));
      },
    );
  });
}
