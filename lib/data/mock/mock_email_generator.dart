import 'dart:math';

import '../../models/email.dart';
import '../../models/mail_folder.dart';
import 'mock_emails.dart';

/// Produces realistic emails on demand for infinite scrolling.
///
/// Ids are generated from a timestamp plus a monotonically increasing counter,
/// so they are unique and never collide with the seeded emails (which use the
/// `seed-` prefix) during normal use.
class MockEmailGenerator {
  MockEmailGenerator._();

  static int _counter = 0;

  static String _nextId() {
    _counter++;
    return 'gen-${DateTime.now().microsecondsSinceEpoch}-$_counter';
  }

  static const List<(String, String)> _people = [
    ('Alice Johnson', 'alice.johnson@northstar.io'),
    ('John Smith', 'john.smith@brightwave.co'),
    ('Sarah Williams', 'sarah.williams@quantica.com'),
    ('David Chen', 'david.chen@northstar.io'),
    ('Priya Patel', 'priya.patel@quantica.com'),
    ('Marcus Lee', 'marcus.lee@brightwave.co'),
    ('Elena Rodriguez', 'elena.r@fintrust.com'),
    ('Tom Becker', 't.becker@codeforge.dev'),
    ('Nina Kowalski', 'nina.kowalski@thestudio.design'),
    ('Oliver Grant', 'o.grant@northstar.io'),
  ];

  static const List<String> _subjects = [
    'Morning update and next steps',
    'Notes from the planning session',
    'Quick question about the report',
    'Budget numbers for review',
    'Meeting invite: sync on roadmap',
    'Thoughts on the new design system',
    'Customer feedback digest',
    'Reminder: timesheet due Friday',
    'Ideas for the summer intern project',
    'Review comments on the PR',
    'Proposal attached for your feedback',
    'Lunch on Thursday?',
    'Updated timeline for the launch',
    'Test plan for the next release',
    'Follow-up on yesterday\'s call',
    'Networking event next month',
    'Half-year performance snapshot',
    'A small favor, if you have a minute',
    'New partner announcement',
    'Your weekly summary',
  ];

  static const List<String> _openers = [
    'Hope your week is going well.',
    'Quick one from my side.',
    'I hope this finds you well.',
    'Wanted to touch base on something.',
    'Circling back to our last conversation.',
    'Morning!',
  ];

  static const List<String> _paragraphs = [
    'I had a look at the numbers and they mostly line up with what we '
        'discussed. There is a small variance in the second quarter that I '
        'would like to walk through when you have a moment.',
    'The team finished the first pass and left comments inline. Nothing '
        'blocking, but a few places would benefit from a quick decision '
        'before we finalize.',
    'After the last meeting I ran a few scenarios. The conservative one '
        'looks safer for now, and we can revisit once the pilot wraps up.',
    'I attached a short summary with the main points. If it looks right to '
        'you I can turn it into the full document by the end of the week.',
    'A few people have asked about this, so I wanted to get your take '
        'before sharing it more widely.',
    'The timeline slipped by a couple of days on the tools side. I updated '
        'the plan accordingly and kept the launch date unchanged.',
  ];

  static const List<String> _closers = [
    'Let me know what you think.',
    'Happy to jump on a call if that is easier.',
    'No rush — whenever you get a chance.',
    'Thanks for the quick turnaround.',
    'Speak soon.',
  ];

  static List<String> _pickLabels(Random rnd) {
    final all = MockLabels.all;
    final count = rnd.nextInt(3); // 0..2 labels
    final ids = <String>[];
    final seen = <String>{};
    for (var i = 0; i < count; i++) {
      final label = all[rnd.nextInt(all.length)];
      if (seen.add(label.id)) ids.add(label.id);
    }
    if (ids.isEmpty && rnd.nextInt(10) == 0) ids.add(MockLabels.important.id);
    return ids;
  }

  static Attachment _attachment(Random rnd, [String? name]) {
    const names = [
      'report.pdf',
      'proposal.docx',
      'screenshot.png',
      'summary.xlsx',
      'meeting-notes.md',
    ];
    return Attachment(
      name: name ?? names[rnd.nextInt(names.length)],
      sizeBytes: 48 * 1024 + rnd.nextInt(3 * 1024 * 1024),
    );
  }

  static String _buildBody(Random rnd, String sender) {
    final opener = _openers[rnd.nextInt(_openers.length)];
    final first = _paragraphs[rnd.nextInt(_paragraphs.length)];
    final second = _paragraphs[rnd.nextInt(_paragraphs.length)];
    final closer = _closers[rnd.nextInt(_closers.length)];

    return '$opener\n\n$first\n\n$second\n\n$closer\n\nBest regards,\n$sender';
  }

  /// Generates a batch of [count] new realistic emails, mostly assigned to
  /// [folder]. The [pinned] folder produces pinned emails that live in Inbox.
  static List<Email> generateMoreEmails({
    int count = 20,
    MailFolder folder = MailFolder.inbox,
    Random? random,
  }) {
    final rnd = random ?? Random();
    final now = DateTime.now();
    final out = <Email>[];
    final targetFolder = folder == MailFolder.pinned
        ? MailFolder.inbox
        : folder;

    for (var i = 0; i < count; i++) {
      final (name, email) = _people[rnd.nextInt(_people.length)];
      final minutesAgo = 3 + rnd.nextInt(60 * 24 * 30); // minutes to ~30 days

      out.add(
        Email(
          id: _nextId(),
          senderName: name,
          senderEmail: email,
          recipients: ['me@kaydet.app'],
          subject: _subjects[rnd.nextInt(_subjects.length)],
          bodyText: _buildBody(rnd, name),
          timestamp: now.subtract(Duration(minutes: minutesAgo)),
          isRead: rnd.nextInt(3) != 0, // roughly one third stay unread
          isPinned: folder == MailFolder.pinned || rnd.nextInt(20) == 0,
          isReplied: rnd.nextInt(12) == 0,
          isForwarded: rnd.nextInt(15) == 0,
          folder: targetFolder,
          labelIds: _pickLabels(rnd),
          attachments: rnd.nextInt(8) == 0 ? [_attachment(rnd)] : const [],
        ),
      );
    }
    return out;
  }
}
