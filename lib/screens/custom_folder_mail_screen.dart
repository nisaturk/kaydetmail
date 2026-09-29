import 'package:flutter/material.dart';

import '../models/mail_custom_folder.dart';
import 'home_screen.dart';

/// A scoped mailbox using the same list, selection toolbar and actions as
/// standard folders, with its own folder-specific paging and refresh.
class CustomFolderMailScreen extends StatelessWidget {
  const CustomFolderMailScreen({
    super.key,
    required this.accountId,
    required this.folderId,
    required this.name,
  });

  final String accountId;
  final String folderId;
  final String name;

  @override
  Widget build(BuildContext context) => HomeScreen(
    customFolder: MailCustomFolder(
      accountId: accountId,
      folderId: folderId,
      name: name,
      fullName: name,
      isSyncEnabled: false,
    ),
  );
}
