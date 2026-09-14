import 'package:flutter/material.dart';

import '../../models/email.dart';
import '../../models/mail_folder.dart';
import '../../models/mail_label.dart';

/// Default labels used by the mock repository.
class MockLabels {
  MockLabels._();

  static const work = MailLabel(
      id: 'lab-work', name: 'Work', color: Color(0xFF3E7CB1));
  static const personal = MailLabel(
      id: 'lab-personal', name: 'Personal', color: Color(0xFF8E7CC3));
  static const finance = MailLabel(
      id: 'lab-finance', name: 'Finance', color: Color(0xFF2E8B6E));
  static const travel = MailLabel(
      id: 'lab-travel', name: 'Travel', color: Color(0xFFC77D2E));
  static const important = MailLabel(
      id: 'lab-important', name: 'Important', color: Color(0xFFB02A2A));

  static const all = [work, personal, finance, travel, important];
}

/// Realistic initial dataset. Times are relative to "now" so the app always
/// looks fresh; ids are fixed so they stay stable between runs.
class MockEmails {
  MockEmails._();

  static List<Email> get seed {
    final now = DateTime.now();
    Duration h(num n) => Duration(hours: n.toInt(), minutes: ((n % 1) * 60).round());

    return [
      Email(
        id: 'seed-welcome',
        senderName: 'KAYDET Team',
        senderEmail: 'team@kaydet.app',
        recipients: ['me@kaydet.app'],
        subject: 'Welcome to KAYDET',
        bodyText:
            'Hi,\n\nWelcome to KAYDET — your mail, in one calm place. '
            'Your inbox has been set up and is ready to use.\n\n'
            'A few things to try: pin important messages with the star icon, '
            'search across everything, and use the mic button while composing '
            'to dictate.\n\n'
            'If anything feels off, reply to this mail and we will take a look.\n\n'
            'Best regards,\nThe KAYDET Team',
        timestamp: now.subtract(h(52)),
        isRead: false,
        isPinned: true,
        labelIds: [MockLabels.important.id],
      ),
      Email(
        id: 'seed-alice-onboarding',
        senderName: 'Alice Johnson',
        senderEmail: 'alice.johnson@northstar.io',
        recipients: ['me@kaydet.app'],
        subject: 'Design review: onboarding flow',
        bodyText:
            'Hey team,\n\nI pushed the new onboarding flow to the review '
            'environment. The first-run experience now has four screens '
            'instead of six and every step shows a progress bar.\n\n'
            'Could you look at the first-run wizard and the empty states '
            'before Friday? I especially want feedback on the password '
            'requirements screen.\n\n'
            'Cheers,\nAlice',
        timestamp: now.subtract(h(3)),
        isRead: false,
        labelIds: [MockLabels.work.id],
      ),
      Email(
        id: 'seed-eng-retro',
        senderName: 'Engineering Team',
        senderEmail: 'eng@northstar.io',
        recipients: ['me@kaydet.app', 'alice.johnson@northstar.io'],
        subject: 'Sprint 42 retro notes',
        bodyText:
            'Hi all,\n\nHere are the notes from this morning\'s retro:\n\n'
            '• What went well: on-call incidents down, CI green most of the week\n'
            '• What to improve: code review turnaround, flaky e2e suite\n'
            '• Actions: add a test-owners rotation, split the e2e job into two\n\n'
            'Comments welcome on the doc.\n\n'
            'Thanks,\nEngineering Team',
        timestamp: now.subtract(h(26)),
        isRead: true,
        labelIds: [MockLabels.work.id],
      ),
      Email(
        id: 'seed-finance-invoice',
        senderName: 'Finance',
        senderEmail: 'finance@northstar.io',
        recipients: ['me@kaydet.app'],
        subject: 'Invoice #4821 for March',
        bodyText:
            'Hi,\n\nInvoice #4821 for March services is attached (USD 1,240.00). '
            'Payment is due on the 25th.\n\n'
            'If you notice any discrepancy, reply to accounting@ and we will '
            'sort it out.\n\n'
            'Thanks,\nFinance',
        timestamp: now.subtract(h(5)),
        isRead: false,
        attachments: const [
          Attachment(
              name: 'invoice-4821-march.pdf', sizeBytes: 182 * 1024),
        ],
        labelIds: [MockLabels.finance.id],
      ),
      Email(
        id: 'seed-sarah-metrics',
        senderName: 'Sarah Williams',
        senderEmail: 'sarah.williams@quantica.com',
        recipients: ['me@kaydet.app'],
        cc: ['david.chen@northstar.io'],
        subject: 'Follow-up on the metrics dashboard',
        bodyText:
            'Hi,\n\nWe said we would reconvene about the metrics dashboard '
            'after the latest data migration.\n\n'
            'Numbers now look healthy — signups up 12% and the weekly active '
            'figure is back to normal. The "conversion by source" chart still '
            'shows a dip we cannot explain.\n\n'
            'Do you have time Thursday morning?\n\n'
            'Best,\nSarah',
        timestamp: now.subtract(h(30)),
        isRead: true,
        labelIds: [MockLabels.work.id],
      ),
      Email(
        id: 'seed-long-release',
        senderName: 'Elena Rodriguez',
        senderEmail: 'elena.rodriguez@fintrust.com',
        recipients: ['me@kaydet.app'],
        subject: 'Release 4.2.0 status report and the complete rollback plan for the API gateway migration across all staging environments including the load test results',
        bodyText:
            'Hello,\n\nHere is the full status report for release 4.2.0. '
            'The API gateway migration is now staged across all environments '
            'and the load tests completed without any failures.\n\n'
            'A few observations worth keeping in mind:\n\n'
            '• Average latency dropped 18% versus the previous release once '
            'caching was enabled on the edge tier.\n'
            '• The rollback plan has been exercised in staging twice, and both '
            'times we were back on the previous version in under four minutes.\n'
            '• Certificate rotation is on the critical path this month; the '
            'signing chain for the new endpoints expires before the next '
            'internal deadline, so scheduling it early would avoid a scramble.\n\n'
            'Headline numbers for the migration: 213 endpoints moved, 41 '
            'downstream services repointed, 0 unresolved incidents in the last '
            'seven days. The full spreadsheet is attached if you want the '
            'per-service breakdown.\n\n'
            'One thing I would still like covered before we call it done: a '
            'dry run of the traffic-shaping rules against production traffic '
            'mirror, since the simulated profiles never fully match real '
            'patterns — the evening peak differs noticeably from what the '
            'synthetic load produces, and we know the short-read path behaves '
            'differently under sustained concurrency.\n\n'
            'Let me know if you have questions on any of this.\n\n'
            'Best regards,\nElena',
        timestamp: now.subtract(h(40)),
        isRead: false,
        attachments: const [
          Attachment(
              name: 'release-4.2.0-status.xlsx', sizeBytes: 148 * 1024),
        ],
        labelIds: [MockLabels.work.id, MockLabels.important.id],
      ),
      Email(
        id: 'seed-marketing-campaign',
        senderName: 'Marketing',
        senderEmail: 'marketing@brightwave.co',
        recipients: ['me@kaydet.app'],
        subject: 'April campaign results are in',
        bodyText:
            'Hello,\n\nQuick summary of April: the newsletter open rate '
            'climbed to 41% and the launch email brought in the most '
            'traffic we have seen all year.\n\n'
            'Full breakdown is in the link; happy to walk through it in the '
            'next standup.\n\n'
            'Best,\nMarketing',
        timestamp: now.subtract(h(20)),
        isRead: true,
        labelIds: [MockLabels.work.id],
      ),
      Email(
        id: 'seed-john-gym',
        senderName: 'John Smith',
        senderEmail: 'john.smith@brightwave.co',
        recipients: ['me@kaydet.app'],
        subject: 'Gym membership renewal',
        bodyText:
            'Hey,\n\nOur gym membership renews at the end of the month and '
            'the auto-pay is still linked to my old card.\n\n'
            'Can you switch it to the company card, or should I sort the '
            'payment myself this month?\n\n'
            'Thanks,\nJohn',
        timestamp: now.subtract(h(7)),
        isRead: false,
        labelIds: [MockLabels.personal.id],
      ),
      Email(
        id: 'seed-hr-leave',
        senderName: 'HR Department',
        senderEmail: 'hr@northstar.io',
        recipients: ['all@northstar.io'],
        subject: 'Updated leave policy',
        bodyText:
            'Hello everyone,\n\nWe have updated the leave policy: from next '
            'month you can carry over up to 5 unused days, and the request '
            'window now opens 60 days in advance.\n\n'
            'The full document is on the intranet. Questions? Ping HR.\n\n'
            'Thanks,\nHR Department',
        timestamp: now.subtract(h(48)),
        isRead: true,
      ),
      Email(
        id: 'seed-priya-rate',
        senderName: 'Priya Patel',
        senderEmail: 'priya.patel@quantica.com',
        recipients: ['me@kaydet.app'],
        subject: 'Re: API rate limits',
        bodyText:
            'Hey,\n\nFollowing up on the rate limit discussion — I ran a '
            'simulation with the numbers we agreed on.\n\n'
            'A sliding window of 100 requests/minute per API key is enough '
            'for our current volume and leaves headroom for the mobile app '
            'sync.\n\n'
            'Shall I write the spec?\n\n'
            'Priya',
        timestamp: now.subtract(h(11)),
        isRead: false,
        isPinned: true,
        labelIds: [MockLabels.work.id, MockLabels.important.id],
      ),
      Email(
        id: 'seed-david-ci',
        senderName: 'David Chen',
        senderEmail: 'david.chen@northstar.io',
        recipients: ['me@kaydet.app'],
        subject: 'Fixing the CI pipeline',
        bodyText:
            'Hi,\n\nThe release pipeline broke again — this time the signing '
            'step expected a certificate that expires tonight.\n\n'
            'I rotated the certificate and the build went green. I also added '
            'a warning 7 days before expiry so we catch it next time.\n\n'
            'David',
        timestamp: now.subtract(h(1)),
        isRead: true,
        labelIds: [MockLabels.work.id],
      ),
      Email(
        id: 'seed-eng-postmortem',
        senderName: 'Engineering Team',
        senderEmail: 'eng@northstar.io',
        recipients: ['all@northstar.io'],
        subject: 'Incident postmortem #12',
        bodyText:
            'Hi team,\n\nPostmortem #12 (07:42–09:15 UTC): a misconfigured '
            'background job paged the database and degraded read latency for '
            'about 90 minutes.\n\n'
            'Root cause, timeline and the three follow-up actions are in the '
            'attached doc. Short version: the job runner now needs a dry-run '
            'flag for anything touching production.\n\n'
            'Thanks for the fast response.\nEngineering Team',
        timestamp: now.subtract(h(70)),
        isRead: true,
        labelIds: [MockLabels.important.id],
      ),
      Email(
        id: 'seed-sent-onboarding',
        senderName: 'Me',
        senderEmail: 'me@kaydet.app',
        recipients: ['alice.johnson@northstar.io'],
        subject: 'Re: Design review: onboarding flow',
        bodyText:
            'Alice,\n\nReviewed the new onboarding flow — the four screens '
            'feel much tighter. Two small notes:\n\n'
            '• The password screen should show its hint on first render, not '
            'after a failed attempt\n'
            '• Consider a "skip" link on the last screen\n\n'
            'Otherwise looks great. Ship it.\n\n'
            'Best,\nme',
        timestamp: now.subtract(h(2)),
        isRead: true,
        folder: MailFolder.sent,
        labelIds: [MockLabels.work.id],
      ),
      Email(
        id: 'seed-sent-roadmap',
        senderName: 'Me',
        senderEmail: 'me@kaydet.app',
        recipients: ['priya.patel@quantica.com'],
        subject: 'Questions about Q2 roadmap',
        bodyText:
            'Priya,\n\nTwo questions on the Q2 roadmap before the review '
            'call:\n\n'
            '1. Are the sync improvements in or out for the spring release?\n'
            '2. Who owns the offline-first investigation?\n\n'
            'Happy to add either to my plate.\n\n'
            'Thanks,\nme',
        timestamp: now.subtract(h(34)),
        isRead: true,
        folder: MailFolder.sent,
        labelIds: [MockLabels.work.id],
      ),
      Email(
        id: 'seed-draft-budget',
        senderName: 'Me',
        senderEmail: 'me@kaydet.app',
        recipients: ['finance@northstar.io'],
        subject: 'Draft: Budget proposal',
        bodyText:
            'Hi,\n\nHere is a first pass at the H2 budget. The main change '
            'versus last year is a separate line for developer tooling.\n\n'
            'Open questions: headcount buffer and the reserve percentage. '
            'I will fill these in once we talk.\n\n'
            'Thanks,\nme',
        timestamp: now.subtract(h(9)),
        isRead: true,
        folder: MailFolder.drafts,
        attachments: const [
          Attachment(name: 'h2-budget-draft.xlsx', sizeBytes: 64 * 1024),
        ],
        labelIds: [MockLabels.finance.id],
      ),
      Email(
        id: 'seed-draft-weekend',
        senderName: 'Me',
        senderEmail: 'me@kaydet.app',
        recipients: ['alice.johnson@northstar.io'],
        subject: 'Weekend plans',
        bodyText:
            'Hey Alice,\n\nStill on for Saturday? I was thinking the hiking '
            'trail we talked about, then lunch at that new place.\n\n'
            'Will confirm the time once the weather looks settled.',
        timestamp: now.subtract(h(4)),
        isRead: false,
        folder: MailFolder.drafts,
        labelIds: [MockLabels.personal.id],
      ),
      Email(
        id: 'seed-trash-aws',
        senderName: 'Finance',
        senderEmail: 'billing@amazon.com',
        recipients: ['me@kaydet.app'],
        subject: 'Receipt: AWS billing',
        bodyText:
            'Your monthly invoice from AWS is ready. Amount: USD 412.18.',
        timestamp: now.subtract(h(96)),
        isRead: true,
        folder: MailFolder.trash,
        labelIds: [MockLabels.finance.id],
      ),
      Email(
        id: 'seed-trash-news',
        senderName: 'John Smith',
        senderEmail: 'newsletter@brightwave.co',
        recipients: ['me@kaydet.app'],
        subject: 'Old newsletter',
        bodyText: 'Because it\'s no longer active subscriptions we removed.',
        timestamp: now.subtract(h(200)),
        isRead: true,
        folder: MailFolder.trash,
      ),
      Email(
        id: 'seed-spam-prize',
        senderName: 'Prize Team',
        senderEmail: 'prize@claim-now.xyz',
        recipients: ['me@kaydet.app'],
        subject: 'URGENT: Claim your prize',
        bodyText:
            'Congratulations! You have been selected as this week\'s winner. '
            'Send your details within 24 hours to claim your prize.',
        timestamp: now.subtract(h(6)),
        isRead: false,
        folder: MailFolder.spam,
      ),
      Email(
        id: 'seed-spam-deals',
        senderName: 'DealZone',
        senderEmail: 'offers@dealzone.example',
        recipients: ['me@kaydet.app'],
        subject: 'Unlock exclusive deals now',
        bodyText:
            'Limited time offer: up to 70% off everything. Limited quantities, '
            'act now before it is gone.',
        timestamp: now.subtract(h(15)),
        isRead: true,
        folder: MailFolder.spam,
      ),
    ];
  }
}