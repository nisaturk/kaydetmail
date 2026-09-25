import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/mail_folder.dart';
import '../models/mail_label.dart';
import '../models/mail_rule.dart';
import '../repositories/mail_repository.dart';
import '../services/mail_rules_store.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';

/// Real, non-virtual folders a rule can move mail into. [MailFolder.inbox]
/// (mail is already there), [MailFolder.starred] and [MailFolder.snoozed]
/// are virtual groupings, not storage folders — `MailRepository.moveToFolder`
/// throws for them.
const List<MailFolder> _ruleTargetFolders = [
  MailFolder.archive,
  MailFolder.trash,
  MailFolder.spam,
];

/// CRUD for client-side mail rules ("gönderen X -> klasöre taşı / etiketle")
/// evaluated by `MailRulesEngine`. Purely client-side, same rationale as
/// labels — no backend endpoint exists for this.
///
/// Rules are scoped per account (an `addLabel` action's label id only means
/// something within its own account, per
/// `MailRepository.getLabelsForAccount`), so a mailbox switcher lets the
/// user pick which connected account's rules they are viewing/editing.
class RulesSettingsScreen extends StatefulWidget {
  const RulesSettingsScreen({super.key});

  @override
  State<RulesSettingsScreen> createState() => _RulesSettingsScreenState();
}

class _RulesSettingsScreenState extends State<RulesSettingsScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  late String _accountId;
  List<MailRule> _rules = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _accountId = _repo.activeAccountId ?? _repo.accounts.first.id;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rules = await MailRulesStore.readRules(_accountId);
    if (!mounted) return;
    setState(() {
      _rules = rules;
      _loading = false;
    });
  }

  void _switchAccount(String accountId) {
    if (accountId == _accountId) return;
    setState(() => _accountId = accountId);
    _load();
  }

  Future<void> _addOrEdit({MailRule? rule}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RuleEditorSheet(accountId: _accountId, rule: rule),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(MailRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kuralı sil?'),
        content: const Text(
          'Bu kural silinecek; daha önce taşınmış veya etiketlenmiş '
          'e-postalar etkilenmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Evet, sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await MailRulesStore.deleteRule(_accountId, rule.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _repo.accounts;
    final colors = AppTheme.colors(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurallar'),
        actions: [
          if (accounts.length > 1)
            PopupMenuButton<String>(
              key: const Key('rules-account-menu'),
              tooltip: 'Hesap seç',
              icon: const Icon(LucideIcons.chevronDown),
              onSelected: _switchAccount,
              itemBuilder: (context) => [
                for (final account in accounts)
                  PopupMenuItem(
                    value: account.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Text(
                            account.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (account.id == _accountId)
                          const Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: Icon(LucideIcons.check, size: 18),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          if (accounts.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _repo.getAccount(_accountId)?.label ?? '',
                  style: TextStyle(fontSize: 13, color: colors.secondaryText),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListenableBuilder(
                    listenable: _repo,
                    builder: (context, _) {
                      if (_rules.isEmpty) return const _EmptyState();
                      final labels = _repo.getLabelsForAccount(_accountId);
                      return ListView.separated(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _rules.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final rule = _rules[i];
                          final isMove =
                              rule.action.type ==
                              MailRuleActionType.moveToFolder;
                          return ListTile(
                            key: ValueKey('rule-${rule.id}'),
                            leading: Icon(
                              isMove
                                  ? LucideIcons.folderInput
                                  : LucideIcons.tag,
                              color: colors.secondaryText,
                            ),
                            title: Text(rule.condition.summary),
                            subtitle: Text(rule.action.summary(labels)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Düzenle',
                                  icon: const Icon(
                                    LucideIcons.pencil,
                                    size: 18,
                                  ),
                                  onPressed: () => _addOrEdit(rule: rule),
                                ),
                                IconButton(
                                  tooltip: 'Sil',
                                  icon: const Icon(
                                    LucideIcons.trash2,
                                    size: 18,
                                  ),
                                  onPressed: () => _delete(rule),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('add-rule-fab'),
        tooltip: 'Yeni kural',
        onPressed: () => _addOrEdit(),
        child: const Icon(LucideIcons.plus),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.filter,
                      size: 48,
                      color: colors.secondaryText,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Henüz kural yok',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gelen postayı otomatik taşımak veya etiketlemek '
                      'için sağ alttaki + ile bir kural ekleyin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet that creates a new rule, or edits/deletes [rule] when given.
/// Pops `true` when a save/delete mutated storage, so the caller reloads.
class _RuleEditorSheet extends StatefulWidget {
  const _RuleEditorSheet({required this.accountId, this.rule});

  final String accountId;
  final MailRule? rule;

  @override
  State<_RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends State<_RuleEditorSheet> {
  late final TextEditingController _senderController;
  late MailRuleActionType _actionType;
  late MailFolder _folder;
  String? _labelId;
  String? _error;
  bool _submitting = false;

  bool get _isEdit => widget.rule != null;

  @override
  void initState() {
    super.initState();
    final rule = widget.rule;
    _senderController = TextEditingController(
      text: rule?.condition.value ?? '',
    );
    _actionType = rule?.action.type ?? MailRuleActionType.moveToFolder;
    _folder = rule?.action.folder ?? _ruleTargetFolders.first;
    _labelId = rule?.action.labelId;
  }

  @override
  void dispose() {
    _senderController.dispose();
    super.dispose();
  }

  List<MailLabel> get _labels =>
      AppConfig.mailRepository.getLabelsForAccount(widget.accountId);

  Future<void> _save() async {
    if (_submitting) return;
    final value = _senderController.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Gönderen adresi/adı boş olamaz.');
      return;
    }
    if (_actionType == MailRuleActionType.addLabel && _labelId == null) {
      setState(() => _error = 'Bir etiket seçin.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final condition = MailRuleCondition.senderContains(value);
    final action = _actionType == MailRuleActionType.moveToFolder
        ? MailRuleAction.moveToFolder(_folder)
        : MailRuleAction.addLabel(_labelId!);
    try {
      if (_isEdit) {
        await MailRulesStore.updateRule(
          widget.accountId,
          widget.rule!.copyWith(condition: condition, action: action),
        );
      } else {
        await MailRulesStore.addRule(
          accountId: widget.accountId,
          condition: condition,
          action: action,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = friendlyErrorMessage(e);
        });
      }
    }
  }

  Future<void> _pickFolder() async {
    final picked = await showModalBottomSheet<MailFolder>(
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
                  'Klasör seç',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final folder in _ruleTargetFolders)
              ListTile(
                key: ValueKey('rule-folder-${folder.name}'),
                leading: Icon(
                  folder == _folder
                      ? LucideIcons.circleCheckBig
                      : LucideIcons.circle,
                  size: 20,
                  color: folder == _folder
                      ? Theme.of(ctx).colorScheme.onSurface
                      : AppTheme.colors(ctx).tertiaryText,
                ),
                title: Text(folder.label),
                selected: folder == _folder,
                onTap: () => Navigator.of(ctx).pop(folder),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _folder = picked);
  }

  Future<void> _pickLabel() async {
    final labels = _labels;
    final picked = await showModalBottomSheet<String>(
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
                  'Etiket seç',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            for (final label in labels)
              ListTile(
                key: ValueKey('rule-label-${label.id}'),
                leading: CircleAvatar(backgroundColor: label.color, radius: 8),
                title: Text(label.name),
                trailing: label.id == _labelId
                    ? Icon(
                        LucideIcons.check,
                        color: Theme.of(ctx).colorScheme.onSurface,
                      )
                    : null,
                selected: label.id == _labelId,
                onTap: () => Navigator.of(ctx).pop(label.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _labelId = picked);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final labels = _labels;
    final selectedLabelName = labels
        .where((label) => label.id == _labelId)
        .map((label) => label.name)
        .firstOrNull;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEdit ? 'Kuralı Düzenle' : 'Yeni Kural',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('rule-sender-field'),
              controller: _senderController,
              autofocus: !_isEdit,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Gönderen adresi/adı şunu içerir',
                hintText: 'ör. bildirim@ornek.com',
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Eylem',
              style: TextStyle(fontSize: 13, color: colors.secondaryText),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const Key('rule-action-move'),
                  label: const Text('Klasöre taşı'),
                  selected: _actionType == MailRuleActionType.moveToFolder,
                  onSelected: (_) => setState(
                    () => _actionType = MailRuleActionType.moveToFolder,
                  ),
                ),
                ChoiceChip(
                  key: const Key('rule-action-label'),
                  label: const Text('Etiketle'),
                  selected: _actionType == MailRuleActionType.addLabel,
                  onSelected: (_) =>
                      setState(() => _actionType = MailRuleActionType.addLabel),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_actionType == MailRuleActionType.moveToFolder)
              ListTile(
                key: const Key('rule-folder-picker'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.folder),
                title: const Text('Hedef klasör'),
                subtitle: Text(_folder.label),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: _pickFolder,
              )
            else if (labels.isEmpty)
              Text(
                'Bu hesapta henüz etiket yok. Önce Etiketler bölümünden bir '
                'etiket oluşturun.',
                style: TextStyle(fontSize: 13, color: colors.secondaryText),
              )
            else
              ListTile(
                key: const Key('rule-label-picker'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(LucideIcons.tag),
                title: const Text('Etiket'),
                subtitle: Text(selectedLabelName ?? 'Seçilmedi'),
                trailing: const Icon(LucideIcons.chevronRight, size: 18),
                onTap: _pickLabel,
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: colors.destructive, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                if (_isEdit)
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Vazgeç'),
                  ),
                const Spacer(),
                FilledButton(
                  key: const Key('rule-save-button'),
                  onPressed: _submitting ? null : _save,
                  child: Text(_isEdit ? 'Kaydet' : 'Ekle'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
