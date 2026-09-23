import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Asks before permanently deleting [count] mails — the server expunges
/// them, so unlike moving to Trash there is no Undo afterwards.
Future<bool> confirmPermanentDelete(BuildContext context, int count) async {
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            count == 1
                ? 'E-posta kalıcı olarak silinsin mi?'
                : '$count e-posta kalıcı olarak silinsin mi?',
          ),
          content: const Text('Bu işlem geri alınamaz.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Vazgeç'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                'Kalıcı olarak sil',
                style: TextStyle(color: AppTheme.colors(ctx).destructive),
              ),
            ),
          ],
        ),
      ) ??
      false;
}
