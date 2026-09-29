import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../l10n/l10n.dart';

/// Asks before permanently deleting [count] mails — the server expunges
/// them, so unlike moving to Trash there is no Undo afterwards.
Future<bool> confirmPermanentDelete(BuildContext context, int count) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          // Large text on a short viewport can exceed the dialog height.
          scrollable: true,
          title: Text(
            count == 1
                ? l10nNow.permanentlyDeleteThisEmail
                : l10nNow.permanentlyDeleteEmails(count),
          ),
          content: Text(l10nNow.thisActionCantBeUndone),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10nNow.cancel2),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                l10nNow.deletePermanently,
                style: TextStyle(color: AppTheme.colors(ctx).destructive),
              ),
            ),
          ],
        ),
      ) ??
      false;
}
