import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../services/session_store.dart';
import '../state/mail_selection_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/app_drawer.dart';
import 'compose_screen.dart';
import 'inbox_screen.dart';
import 'login_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// The main mail interface: a drawer to switch folders plus the mail list.
///
/// When selection mode is active the app bar switches to a selection toolbar
/// and a bottom action bar appears. A FAB opens the compose screen when
/// selection mode is off.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  MailFolder _folder = MailFolder.inbox;
  final MailSelectionController _selection = MailSelectionController();

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  MailRepository get _repo => AppConfig.mailRepository;

  void _selectFolder(MailFolder folder) {
    _selection.exit();
    setState(() => _folder = folder);
    Navigator.of(context).pop();
  }

  Future<void> _logout() async {
    Navigator.of(context).pop();
    await _repo.logout();
    await SessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _openSearch() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  void _openSettings() {
    Navigator.of(context).pop(); // close the drawer
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  void _openCompose() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ComposeScreen()));
  }

  // ── Bulk actions ──────────────────────────────────────────────────────

  List<Email> get _selectedEmails => _repo
      .getEmailsInFolder(_folder)
      .where((e) => _selection.selectedIds.contains(e.id))
      .toList();

  Future<void> _actionDelete() async {
    await _repo.moveToTrash(_selection.selectedIds.toList());
    _selection.exit();
  }

  Future<void> _actionReadUnread() async {
    final emails = _selectedEmails;
    final allRead = emails.every((e) => e.isRead);
    if (allRead) {
      await _repo.markAsUnread(_selection.selectedIds.toList());
    } else {
      await _repo.markAsRead(_selection.selectedIds.toList());
    }
    _selection.exit();
  }

  Future<void> _actionPinUnpin() async {
    final emails = _selectedEmails;
    final allPinned = emails.every((e) => e.isPinned);
    if (!allPinned) {
      final newPins = emails.where((e) => !e.isPinned).length;
      final pinnedCount = _repo.getEmailsInFolder(MailFolder.pinned).length;
      if (pinnedCount + newPins > MailRepository.maxPinnedMails) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('En fazla 3 mail sabitlenebilir.')),
        );
        return;
      }
    }
    await _repo.setPinned(_selection.selectedIds.toList(), !allPinned);
    _selection.exit();
  }

  Future<void> _actionArchive() async {
    await _repo.moveToFolder(
      _selection.selectedIds.toList(),
      MailFolder.archive,
    );
    _selection.exit();
  }

  void _actionMove() {
    final ids = _selection.selectedIds.toList();
    final targets = MailFolder.values
        .where(
          (f) =>
              f != MailFolder.pinned &&
              f != _folder &&
              f != MailFolder.sent &&
              f != MailFolder.archive,
        )
        .toList();

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Klasöre Taşı',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final folder in targets)
              ListTile(
                leading: Icon(folder.icon, size: 20),
                title: Text(folder.label),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await _repo.moveToFolder(ids, folder);
                  _selection.exit();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _actionLabel() async {
    final ids = _selection.selectedIds.toList();
    final labels = _repo.getLabels();
    if (labels.isEmpty) return;

    final selectedEmails = _selectedEmails;
    final applied = <String>{for (final e in selectedEmails) ...e.labelIds};

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Etiketler',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  for (final label in labels)
                    CheckboxListTile(
                      value: applied.contains(label.id),
                      onChanged: (checked) async {
                        if (checked == true) {
                          await _repo.addLabelsToEmails(ids, [label.id]);
                          applied.add(label.id);
                        } else {
                          await _repo.removeLabelsFromEmails(ids, [label.id]);
                          applied.remove(label.id);
                        }
                        setSheetState(() {});
                      },
                      secondary: CircleAvatar(
                        backgroundColor: label.color,
                        radius: 8,
                      ),
                      title: Text(label.name),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
    _selection.exit();
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_repo, _selection]),
      builder: (context, _) {
        return Scaffold(
          appBar: _selection.isActive
              ? _buildSelectionAppBar()
              : _buildNormalAppBar(),
          drawer: AppDrawer(
            selectedFolder: _folder,
            onSelectFolder: _selectFolder,
            onLogout: _logout,
            onOpenSettings: _openSettings,
          ),
          floatingActionButton: _selection.isActive
              ? null
              : FloatingActionButton(
                  onPressed: _openCompose,
                  tooltip: 'Yeni E-posta',
                  child: const Icon(LucideIcons.mailPlus),
                ),
          bottomNavigationBar: _selection.isActive
              ? _buildBulkActionBar()
              : null,
          body: KeyedSubtree(
            key: ValueKey(_folder),
            child: InboxScreen(folder: _folder, selection: _selection),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      title: Text(_folder.label),
      actions: [
        IconButton(
          onPressed: _openSearch,
          icon: const Icon(LucideIcons.search),
          tooltip: 'Ara',
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    return AppBar(
      leading: IconButton(
        onPressed: _selection.exit,
        tooltip: 'Seçimi iptal et',
        icon: const Icon(LucideIcons.x),
      ),
      title: Text(
        _selection.count == 1 ? '1 seçili' : '${_selection.count} seçili',
      ),
      actions: [
        TextButton(
          onPressed: _selection.selectAllVisible,
          child: const Text('Tümünü seç'),
        ),
      ],
    );
  }

  Widget _buildBulkActionBar() {
    final allRead = _selectedEmails.every((e) => e.isRead);
    final allPinned = _selectedEmails.every((e) => e.isPinned);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              _ActionBtn(
                icon: LucideIcons.trash2,
                label: 'Sil',
                onTap: _actionDelete,
              ),
              _ActionBtn(
                icon: allRead ? LucideIcons.eyeOff : LucideIcons.eye,
                label: allRead ? 'Okunmadı' : 'Okundu',
                onTap: _actionReadUnread,
              ),
              _ActionBtn(
                icon: allPinned ? LucideIcons.star : LucideIcons.pin,
                label: allPinned ? 'Yıldızdan Çıkar' : 'Yıldızla',
                onTap: _actionPinUnpin,
              ),
              _ActionBtn(
                icon: LucideIcons.archive,
                label: 'Arşivle',
                onTap: _actionArchive,
              ),
              _ActionBtn(
                icon: LucideIcons.move,
                label: 'Taşı',
                onTap: _actionMove,
              ),
              _ActionBtn(
                icon: LucideIcons.tag,
                label: 'Etiket',
                onTap: _actionLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: Colors.black),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}
