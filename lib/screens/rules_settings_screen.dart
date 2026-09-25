import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/account_sync_scope.dart';
import '../models/mail_label.dart';
import '../models/server_mail_rule.dart';
import '../repositories/mail_repository.dart';
import '../utils/error_messages.dart';

const _conditionNames = {
  'senderContains': 'Gönderen içerir',
  'senderEquals': 'Gönderen eşittir',
  'senderDomain': 'Gönderen alan adı',
  'subjectContains': 'Konu içerir',
  'recipientContains': 'Alıcı içerir',
  'hasAttachment': 'Ek içerir',
  'folder': 'Klasör',
};

const _actionNames = {
  'markRead': 'Okundu işaretle',
  'markUnread': 'Okunmadı işaretle',
  'star': 'Yıldızla',
  'archive': 'Arşivle',
  'move': 'Klasöre taşı',
  'trash': 'Çöpe taşı',
  'spam': 'Spam olarak işaretle',
  'addLabel': 'Etiket ekle',
  'stopProcessing': 'Sonraki kuralları durdur',
};

class RulesSettingsScreen extends StatefulWidget {
  const RulesSettingsScreen({super.key});

  @override
  State<RulesSettingsScreen> createState() => _RulesSettingsScreenState();
}

class _RulesSettingsScreenState extends State<RulesSettingsScreen> {
  MailRepository get _repo => AppConfig.mailRepository;
  late String _accountId;
  List<ServerMailRule> _rules = const [];
  AccountSyncScope? _scope;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _accountId = _repo.activeAccountId ?? _repo.accounts.first.id;
    _load();
  }

  Future<void> _load() async {
    final accountId = _accountId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final scope = await _repo.getSyncScope(accountId);
      final rules = await _repo.listRules(accountId);
      if (!mounted || accountId != _accountId) return;
      setState(() {
        _scope = scope;
        _rules = rules;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || accountId != _accountId) return;
      setState(() {
        _error = error is StateError
            ? error.message
            : friendlyErrorMessage(error);
        _loading = false;
      });
    }
  }

  Future<void> _edit([ServerMailRule? rule]) async {
    if (_scope == null) return;
    final accountId = _accountId;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RuleEditor(
        accountId: accountId,
        repo: _repo,
        rule: rule,
        folders: _scope!.folders
            .where((folder) => folder.type != 'Unknown')
            .toList(),
        labels: _repo.getLabelsForAccount(accountId),
      ),
    );
    if (saved == true && accountId == _accountId) await _load();
  }

  Future<void> _delete(ServerMailRule rule) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Kuralı sil?'),
        content: const Text(
          'Bu kuralın daha önce işlediği e-postalar etkilenmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repo.deleteRule(_accountId, rule.id);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  Future<void> _toggle(ServerMailRule rule, bool enabled) async {
    try {
      await _repo.updateRule(_accountId, rule.copyWith(enabled: enabled));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Kurallar'),
      actions: [
        if (_repo.accounts.length > 1)
          PopupMenuButton<String>(
            key: const Key('rules-account-menu'),
            tooltip: 'Hesap seç',
            icon: const Icon(LucideIcons.chevronDown),
            onSelected: (id) {
              if (id == _accountId) return;
              setState(() => _accountId = id);
              _load();
            },
            itemBuilder: (_) => [
              for (final account in _repo.accounts)
                PopupMenuItem(value: account.id, child: Text(account.label)),
            ],
          ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, textAlign: TextAlign.center),
                ),
                TextButton(onPressed: _load, child: const Text('Tekrar dene')),
              ],
            ),
          )
        : _rules.isEmpty
        ? const Center(child: Text('Henüz kural yok'))
        : ListView.builder(
            itemCount: _rules.length,
            itemBuilder: (context, index) {
              final rule = _rules[index];
              return ListTile(
                key: ValueKey('rule-${rule.id}'),
                title: Text(rule.name),
                subtitle: Text(
                  'Öncelik ${rule.priority} · ${rule.logic == 'And' ? 'VE' : 'VEYA'} · ${rule.actions.map((action) => _actionNames[action.type]).join(', ')}',
                ),
                leading: Switch(
                  value: rule.enabled,
                  onChanged: (value) => _toggle(rule, value),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Düzenle',
                      icon: const Icon(LucideIcons.pencil),
                      onPressed: () => _edit(rule),
                    ),
                    IconButton(
                      tooltip: 'Sil',
                      icon: const Icon(LucideIcons.trash2),
                      onPressed: () => _delete(rule),
                    ),
                  ],
                ),
              );
            },
          ),
    floatingActionButton: _loading || _error != null
        ? null
        : FloatingActionButton(
            key: const Key('add-rule-fab'),
            tooltip: 'Yeni kural',
            onPressed: () => _edit(),
            child: const Icon(LucideIcons.plus),
          ),
  );
}

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({
    required this.accountId,
    required this.repo,
    required this.folders,
    required this.labels,
    this.rule,
  });

  final String accountId;
  final MailRepository repo;
  final ServerMailRule? rule;
  final List<SyncScopeFolder> folders;
  final List<MailLabel> labels;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late final TextEditingController _name;
  late final TextEditingController _priority;
  late bool _enabled;
  late String _logic;
  late List<RuleCondition> _conditions;
  late List<RuleAction> _actions;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.rule?.name ?? '');
    _priority = TextEditingController(text: '${widget.rule?.priority ?? 0}');
    _enabled = widget.rule?.enabled ?? true;
    _logic = widget.rule?.logic ?? 'And';
    _conditions = List.of(
      widget.rule?.conditions ?? [const RuleCondition('senderContains', '')],
    );
    _actions = List.of(widget.rule?.actions ?? [const RuleAction('archive')]);
  }

  @override
  void dispose() {
    _name.dispose();
    _priority.dispose();
    super.dispose();
  }

  void _condition(int index, RuleCondition value) =>
      setState(() => _conditions[index] = value);
  void _action(int index, RuleAction value) =>
      setState(() => _actions[index] = value);

  Future<void> _save() async {
    if (_saving) return;
    final priority = int.tryParse(_priority.text.trim());
    if (_name.text.trim().isEmpty ||
        _name.text.trim().length > 100 ||
        priority == null ||
        priority < 0 ||
        priority > 99999 ||
        _conditions.isEmpty ||
        _actions.isEmpty ||
        _conditions.any(
          (condition) =>
              condition.type != 'hasAttachment' &&
              (condition.value?.trim().isEmpty ?? true),
        ) ||
        _actions.any(
          (action) =>
              action.type == 'move' && action.folderId == null ||
              action.type == 'addLabel' && action.labelId == null,
        )) {
      setState(
        () => _error = 'Ad, öncelik, koşul ve işlem alanlarını kontrol edin.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final rule = ServerMailRule(
      id: widget.rule?.id ?? '',
      name: _name.text.trim(),
      enabled: _enabled,
      priority: priority,
      logic: _logic,
      conditions: _conditions,
      actions: _actions,
    );
    try {
      if (widget.rule == null) {
        await widget.repo.createRule(widget.accountId, rule);
      } else {
        await widget.repo.updateRule(widget.accountId, rule);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: ListView(
          children: [
            Text(
              widget.rule == null ? 'Yeni kural' : 'Kuralı düzenle',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('rule-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Kural adı'),
            ),
            TextField(
              key: const Key('rule-priority'),
              controller: _priority,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Öncelik (küçük sayı önce)',
              ),
            ),
            SwitchListTile(
              title: const Text('Etkin'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            DropdownButtonFormField<String>(
              initialValue: _logic,
              decoration: const InputDecoration(labelText: 'Koşul mantığı'),
              items: const [
                DropdownMenuItem(
                  value: 'And',
                  child: Text('Tüm koşullar (VE)'),
                ),
                DropdownMenuItem(
                  value: 'Or',
                  child: Text('Herhangi biri (VEYA)'),
                ),
              ],
              onChanged: (value) => setState(() => _logic = value!),
            ),
            const SizedBox(height: 16),
            Text('Koşullar', style: Theme.of(context).textTheme.titleMedium),
            for (var i = 0; i < _conditions.length; i++) _conditionEditor(i),
            TextButton.icon(
              onPressed: _conditions.length >= 16
                  ? null
                  : () => setState(
                      () => _conditions.add(
                        const RuleCondition('senderContains', ''),
                      ),
                    ),
              icon: const Icon(LucideIcons.plus),
              label: const Text('Koşul ekle'),
            ),
            const SizedBox(height: 12),
            Text(
              'İşlemler (sırayla uygulanır)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (var i = 0; i < _actions.length; i++) _actionEditor(i),
            TextButton.icon(
              onPressed: _actions.length >= 16
                  ? null
                  : () => setState(
                      () => _actions.add(const RuleAction('markRead')),
                    ),
              icon: const Icon(LucideIcons.plus),
              label: const Text('İşlem ekle'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              key: const Key('rule-save-button'),
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _conditionEditor(int index) {
    final condition = _conditions[index];
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('condition-type-$index'),
                initialValue: condition.type,
                items: [
                  for (final entry in _conditionNames.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (type) => _condition(
                  index,
                  RuleCondition(
                    type!,
                    type == 'hasAttachment'
                        ? null
                        : type == 'folder'
                        ? widget.folders.firstOrNull?.id
                        : '',
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Koşulu kaldır',
              onPressed: _conditions.length == 1
                  ? null
                  : () => setState(() => _conditions.removeAt(index)),
              icon: const Icon(LucideIcons.x),
            ),
          ],
        ),
        if (condition.type == 'folder')
          DropdownButtonFormField<String>(
            key: ValueKey('condition-folder-$index'),
            initialValue: widget.folders.any((f) => f.id == condition.value)
                ? condition.value
                : null,
            decoration: const InputDecoration(labelText: 'Klasör'),
            items: [
              for (final folder in widget.folders)
                DropdownMenuItem(
                  value: folder.id,
                  child: Text(folder.displayName),
                ),
            ],
            onChanged: (id) =>
                _condition(index, RuleCondition(condition.type, id)),
          )
        else if (condition.type != 'hasAttachment')
          TextFormField(
            key: ValueKey('condition-value-$index'),
            initialValue: condition.value,
            decoration: const InputDecoration(labelText: 'Değer'),
            onChanged: (value) =>
                _conditions[index] = RuleCondition(condition.type, value),
          ),
      ],
    );
  }

  Widget _actionEditor(int index) {
    final action = _actions[index];
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('action-type-$index'),
                initialValue: action.type,
                items: [
                  for (final entry in _actionNames.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (type) => _action(
                  index,
                  RuleAction(
                    type!,
                    folderId: type == 'move'
                        ? widget.folders.firstOrNull?.id
                        : null,
                    labelId: type == 'addLabel'
                        ? widget.labels.firstOrNull?.id
                        : null,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'İşlemi kaldır',
              onPressed: _actions.length == 1
                  ? null
                  : () => setState(() => _actions.removeAt(index)),
              icon: const Icon(LucideIcons.x),
            ),
          ],
        ),
        if (action.type == 'move')
          DropdownButtonFormField<String>(
            key: ValueKey('action-folder-$index'),
            initialValue: widget.folders.any((f) => f.id == action.folderId)
                ? action.folderId
                : null,
            decoration: const InputDecoration(labelText: 'Hedef klasör'),
            items: [
              for (final folder in widget.folders)
                DropdownMenuItem(
                  value: folder.id,
                  child: Text(folder.displayName),
                ),
            ],
            onChanged: (id) => _action(index, RuleAction('move', folderId: id)),
          )
        else if (action.type == 'addLabel')
          DropdownButtonFormField<String>(
            key: ValueKey('action-label-$index'),
            initialValue: widget.labels.any((l) => l.id == action.labelId)
                ? action.labelId
                : null,
            decoration: const InputDecoration(labelText: 'Etiket'),
            items: [
              for (final label in widget.labels)
                DropdownMenuItem(value: label.id, child: Text(label.name)),
            ],
            onChanged: (id) =>
                _action(index, RuleAction('addLabel', labelId: id)),
          ),
      ],
    );
  }
}
