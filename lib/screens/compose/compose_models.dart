import 'package:flutter/material.dart';

import '../../services/contacts_store.dart';

/// Non-ready states for a remote attachment awaiting/needing its content —
/// see `_ComposeScreenState._attachmentIssues`.
enum AttachmentIssue { downloading, failed }

enum AttachmentSource { file, gallery, camera }

enum ComposeMenuAction { schedule, contacts, saveDraft, discard, readReceipt }

enum RecipientField { to, cc, bcc }

typedef ContactPick = ({RecipientField field, List<Contact> contacts});

/// Borderless field decoration shared by every compose input.
///
/// Every border state is explicitly [InputBorder.none]: the global theme
/// draws rounded boxes (including on focus) and compose must stay one flat
/// writing surface with only a cursor for feedback.
const flatFieldDecoration = InputDecoration(
  hintText: '',
  border: InputBorder.none,
  enabledBorder: InputBorder.none,
  focusedBorder: InputBorder.none,
  errorBorder: InputBorder.none,
  focusedErrorBorder: InputBorder.none,
  disabledBorder: InputBorder.none,
  filled: false,
  isDense: true,
  contentPadding: EdgeInsets.symmetric(vertical: 12),
);

/// Light shape check for a recipient chip: `name@domain.tld`. Not a full
/// RFC 5322 validator — just enough to flag an obviously broken address
/// (missing `@`, missing domain) before it reaches the backend.
final RegExp emailShapePattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// One recipient chip. [valid] is false for anything that fails
/// [emailShapePattern] — the chip still renders (never silently dropped)
/// but in the destructive palette so the user notices and fixes it.
@immutable
class Recipient {
  const Recipient(this.address, {required this.valid});

  final String address;
  final bool valid;
}
