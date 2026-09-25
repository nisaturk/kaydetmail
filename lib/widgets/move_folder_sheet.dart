import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/mail_custom_folder.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../utils/error_messages.dart';

class MoveFolderTarget {
  const MoveFolderTarget.logical(this.folder)
    : customFolder = null,
      accountId = null;
  MoveFolderTarget.custom(MailCustomFolder folder)
    : customFolder = folder,
      folder = null,
      accountId = folder.accountId;

  final MailFolder? folder;
  final MailCustomFolder? customFolder;
  final String? accountId;

  String get label => customFolder?.name ?? folder!.label;
}

List<MoveFolderTarget> buildMoveFolderTargets({
  required MailRepository repository,
  required Set<String> accountIds,
  required Set<MailFolder> currentFolders,
  String? currentCustomFolderId,
}) {
  const order = [
    MailFolder.inbox,
    MailFolder.archive,
    MailFolder.trash,
    MailFolder.spam,
  ];
  final available = accountIds.isEmpty
      ? <MailFolder>{}
      : repository.availableFolders(accountIds.first).toSet();
  for (final accountId in accountIds.skip(1)) {
    available.removeWhere(
      (folder) => !repository.availableFolders(accountId).contains(folder),
    );
  }
  final targets = <MoveFolderTarget>[
    for (final folder in order)
      if (available.contains(folder) && !currentFolders.contains(folder))
        MoveFolderTarget.logical(folder),
  ];
  if (accountIds.length == 1) {
    final accountId = accountIds.single;
    targets.addAll([
      for (final row in flattenCustomFolderTree(
        repository.getCustomFolders(accountId: accountId),
      ))
        if (row.folder.folderId != currentCustomFolderId)
          MoveFolderTarget.custom(row.folder),
    ]);
  }
  return targets;
}

Future<MoveFolderTarget?> showMoveFolderSheet(
  BuildContext context, {
  required MailRepository repository,
  required Set<String> accountIds,
  required Set<MailFolder> currentFolders,
  String? currentCustomFolderId,
}) => showModalBottomSheet<MoveFolderTarget>(
  context: context,
  isScrollControlled: true,
  builder: (context) => _MoveFolderSheet(
    repository: repository,
    accountIds: accountIds,
    currentFolders: currentFolders,
    currentCustomFolderId: currentCustomFolderId,
  ),
);

class _MoveFolderSheet extends StatefulWidget {
  const _MoveFolderSheet({
    required this.repository,
    required this.accountIds,
    required this.currentFolders,
    this.currentCustomFolderId,
  });

  final MailRepository repository;
  final Set<String> accountIds;
  final Set<MailFolder> currentFolders;
  final String? currentCustomFolderId;

  @override
  State<_MoveFolderSheet> createState() => _MoveFolderSheetState();
}

class _MoveFolderSheetState extends State<_MoveFolderSheet> {
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      for (final accountId in widget.accountIds) {
        await widget.repository.refreshCustomFolders(accountId: accountId);
      }
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final targets = buildMoveFolderTargets(
      repository: widget.repository,
      accountIds: widget.accountIds,
      currentFolders: widget.currentFolders,
      currentCustomFolderId: widget.currentCustomFolderId,
    );
    final customTargets = targets.where(
      (target) => target.customFolder != null,
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Taşı',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Kapat',
                      icon: const Icon(LucideIcons.x),
                    ),
                  ],
                ),
              ),
              if (_loading) const LinearProgressIndicator(),
              Expanded(
                child: ListView(
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        child: Column(
                          children: [
                            Text(friendlyErrorMessage(_error!)),
                            TextButton(
                              onPressed: _refresh,
                              child: const Text('Tekrar dene'),
                            ),
                          ],
                        ),
                      ),
                    for (final target in targets)
                      if (target.folder != null)
                        ListTile(
                          leading: Icon(target.folder!.icon),
                          title: Text(target.label),
                          onTap: () => Navigator.of(context).pop(target),
                        ),
                    if (customTargets.isNotEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                        child: Text(
                          'Diğer Klasörler',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    for (final target in customTargets)
                      ListTile(
                        contentPadding: EdgeInsets.only(
                          left:
                              20.0 +
                              24.0 * _depthFor(target.customFolder!, targets),
                          right: 16,
                        ),
                        leading: const Icon(LucideIcons.folder),
                        title: Text(target.customFolder!.name),
                        onTap: () => Navigator.of(context).pop(target),
                      ),
                    if (targets.isEmpty && !_loading && _error == null)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Taşınabilecek başka klasör yok.'),
                      ),
                    if (widget.accountIds.length > 1)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Farklı hesaplardan seçilen e-postalar yalnızca ortak klasörlere taşınabilir.',
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  int _depthFor(MailCustomFolder folder, List<MoveFolderTarget> targets) =>
      flattenCustomFolderTree(
        targets
            .where((target) => target.customFolder != null)
            .map((target) => target.customFolder!),
      ).firstWhere((row) => row.folder.folderId == folder.folderId).depth;
}
