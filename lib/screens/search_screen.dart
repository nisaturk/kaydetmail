import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../config/app_config.dart';
import '../models/email.dart';
import '../models/folder_sync_status.dart';
import '../models/mail_account.dart';
import '../models/mail_folder.dart';
import '../repositories/mail_repository.dart';
import '../theme/app_theme.dart';
import '../utils/error_messages.dart';
import '../widgets/mail_list_item.dart';
import 'compose_screen.dart';
import 'mail_detail_screen.dart';

class _AdvancedFilters {
  const _AdvancedFilters({
    this.accountId,
    this.folder,
    this.from,
    this.to,
    this.fromDate,
    this.toDate,
    this.isRead,
    this.flagged,
    this.hasAttachment,
  });

  final String? accountId;
  final MailFolder? folder;
  final String? from;
  final String? to;
  final DateTime? fromDate;
  final DateTime? toDate;
  final bool? isRead;
  final bool? flagged;
  final bool? hasAttachment;

  static const empty = _AdvancedFilters();

  bool get isEmpty =>
      accountId == null &&
      folder == null &&
      from == null &&
      to == null &&
      fromDate == null &&
      toDate == null &&
      isRead == null &&
      flagged == null &&
      hasAttachment == null;

  int get activeCount => [
    accountId,
    folder,
    from,
    to,
    fromDate,
    toDate,
    isRead,
    flagged,
    hasAttachment,
  ].where((v) => v != null).length;

  _AdvancedFilters copyWith({
    String? Function()? accountId,
    MailFolder? Function()? folder,
    String? Function()? from,
    String? Function()? to,
    DateTime? Function()? fromDate,
    DateTime? Function()? toDate,
    bool? Function()? isRead,
    bool? Function()? flagged,
    bool? Function()? hasAttachment,
  }) => _AdvancedFilters(
    accountId: accountId != null ? accountId() : this.accountId,
    folder: folder != null ? folder() : this.folder,
    from: from != null ? from() : this.from,
    to: to != null ? to() : this.to,
    fromDate: fromDate != null ? fromDate() : this.fromDate,
    toDate: toDate != null ? toDate() : this.toDate,
    isRead: isRead != null ? isRead() : this.isRead,
    flagged: flagged != null ? flagged() : this.flagged,
    hasAttachment: hasAttachment != null ? hasAttachment() : this.hasAttachment,
  );
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _labelId;
  _AdvancedFilters _filters = _AdvancedFilters.empty;
  List<Email> _results = const [];
  bool _loading = false;
  Object? _error;
  int _searchGeneration = 0;
  Map<String, List<FolderSyncStatus>> _syncStatusByAccount = const {};
  bool _remoteLoading = false;
  String? _remoteMessage;
  Object? _remoteError;

  @override
  void initState() {
    super.initState();
    _loadSyncStatus();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadSyncStatus() async {
    final byAccount = <String, List<FolderSyncStatus>>{};
    for (final account in _repo.accounts) {
      try {
        byAccount[account.id] = await _repo.getSyncStatus(account.id);
      } catch (_) {
        // Best-effort advisory banner only; a failed fetch just omits that
        // account from the incompleteness check instead of blocking search.
      }
    }
    if (!mounted) return;
    setState(() => _syncStatusByAccount = byAccount);
  }

  bool get _hasActiveSearch =>
      _query.trim().isNotEmpty || _labelId != null || !_filters.isEmpty;
  bool get _canSearchRemote =>
      _labelId == null &&
      (_query.trim().isNotEmpty ||
          (_filters.from?.trim().isNotEmpty ?? false) ||
          (_filters.to?.trim().isNotEmpty ?? false));

  bool get _mailboxIncomplete {
    final scoped = _filters.accountId == null
        ? _syncStatusByAccount.values.expand((v) => v)
        : _syncStatusByAccount[_filters.accountId] ?? const [];
    return scoped.any((status) => !status.backfillComplete);
  }

  void _queryChanged(String value) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    setState(() {
      _query = value;
      _remoteMessage = null;
      _remoteError = null;
      _remoteLoading = false;
      _error = null;
    });
    if (!_hasActiveSearch) {
      setState(() {
        _loading = false;
        _results = const [];
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _search(generation),
    );
  }

  Future<void> _search(int generation) async {
    try {
      final results = await _repo.searchEmailsOnServer(
        query: _query.trim(),
        accountId: _filters.accountId,
        folder: _filters.folder,
        from: _filters.from,
        to: _filters.to,
        fromDate: _filters.fromDate,
        toDate: _filters.toDate,
        isRead: _filters.isRead,
        flagged: _filters.flagged,
        hasAttachment: _filters.hasAttachment,
        labelId: _labelId,
      );
      if (!mounted || generation != _searchGeneration) return;
      final byId = {for (final email in results) email.id: email};
      final sorted = byId.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      setState(() {
        _results = List.unmodifiable(sorted);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _searchOnServer() async {
    if (!_canSearchRemote || _remoteLoading) return;
    final generation = _searchGeneration;
    setState(() {
      _remoteLoading = true;
      _remoteError = null;
      _remoteMessage = null;
    });
    try {
      final result = await _repo.searchRemote(
        query: _query.trim(),
        accountId: _filters.accountId,
        folder: _filters.folder,
        from: _filters.from,
        to: _filters.to,
        fromDate: _filters.fromDate,
        toDate: _filters.toDate,
        isRead: _filters.isRead,
        flagged: _filters.flagged,
        hasAttachment: _filters.hasAttachment,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _remoteLoading = false;
        _remoteMessage = result.complete
            ? 'Sunucu taraması tamamlandı. ${result.imported} yeni e-posta eklendi.'
            : 'Sunucu taraması kısmen tamamlandı. ${result.imported} yeni e-posta eklendi; ${result.remaining} eşleşme kaldı. Yeniden deneyin.';
      });
      _runSearchNow();
      _loadSyncStatus();
    } catch (error) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _remoteLoading = false;
        _remoteError = error;
      });
    }
  }

  void _runSearchNow() {
    final generation = ++_searchGeneration;
    if (!_hasActiveSearch) {
      setState(() {
        _loading = false;
        _error = null;
        _results = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    _search(generation);
  }

  void _selectLabel(String? id) {
    setState(() {
      _labelId = id;
      _remoteLoading = false;
      _remoteMessage = null;
      _remoteError = null;
    });
    _runSearchNow();
  }

  void _applyFilters(_AdvancedFilters filters) {
    setState(() {
      _filters = filters;
      _remoteLoading = false;
      _remoteMessage = null;
      _remoteError = null;
    });
    _runSearchNow();
  }

  void _clearOneFilter(_AdvancedFilters cleared) => _applyFilters(cleared);

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<_AdvancedFilters>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _FilterSheet(initial: _filters, accounts: _repo.accounts),
    );
    if (result != null) _applyFilters(result);
  }

  void _retry() => _runSearchNow();

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final colors = AppTheme.colors(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _queryChanged,
          decoration: InputDecoration(
            hintText: 'E-posta ara',
            border: InputBorder.none,
            filled: false,
            hintStyle: TextStyle(color: colors.tertiaryText, fontSize: 16),
          ),
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: 'Temizle',
              onPressed: () {
                _controller.clear();
                _queryChanged('');
              },
              icon: const Icon(LucideIcons.x),
            ),
          IconButton(
            tooltip: 'Filtreler',
            onPressed: _openFilterSheet,
            icon: Badge(
              isLabelVisible: _filters.activeCount > 0,
              label: Text('${_filters.activeCount}'),
              child: const Icon(LucideIcons.slidersHorizontal),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _LabelFilter(selected: _labelId, onSelected: _selectLabel),
          if (!_filters.isEmpty)
            _ActiveFilterChips(
              filters: _filters,
              accounts: _repo.accounts,
              onClear: _clearOneFilter,
              onClearAll: () => _applyFilters(_AdvancedFilters.empty),
            ),
          if (_hasActiveSearch && _mailboxIncomplete)
            const _CompletenessBanner(),
          if (_hasActiveSearch && _canSearchRemote)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('search-remote'),
                  onPressed: _remoteLoading ? null : _searchOnServer,
                  icon: _remoteLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.search, size: 18),
                  label: Text(
                    _remoteLoading ? 'Sunucuda aranıyor…' : 'Sunucuda da ara',
                  ),
                ),
              ),
            ),
          if (_remoteMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_remoteMessage!),
              ),
            ),
          if (_remoteError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(friendlyErrorMessage(_remoteError!)),
            ),
          _SearchScopeStatus(
            serverSearch: _hasActiveSearch,
            loading: _loading,
            accountEmail: _filters.accountId == null
                ? null
                : _repo.accounts
                      .where((a) => a.id == _filters.accountId)
                      .map((a) => a.email)
                      .firstOrNull,
          ),
          Expanded(child: _buildResults(results)),
        ],
      ),
    );
  }

  void _onMailTap(Email email) {
    if (email.folder == MailFolder.drafts) {
      openDraftEditor(context, email);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MailDetailScreen(emailId: email.id)),
      );
    }
  }

  Widget _buildResults(List<Email> results) {
    if (_loading && results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && results.isEmpty) {
      return _SearchError(error: _error!, onRetry: _retry);
    }
    if (!_hasActiveSearch) {
      return const _Hint(message: 'Aramak için yazmaya başlayın.');
    }
    if (results.isEmpty) {
      return _Hint(
        message: _query.trim().isEmpty
            ? 'Seçili filtrelerle eşleşen sonuç yok.'
            : '“${_query.trim()}” için sonuç yok.',
      );
    }
    final showAccount = _repo.accounts.length > 1;
    final accountEmail = showAccount
        ? {for (final account in _repo.accounts) account.id: account.email}
        : const <String, String>{};
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(indent: 64, endIndent: 16),
      itemBuilder: (context, index) {
        final email = results[index];
        final labelsById = {
          for (final label in _repo.getLabelsForAccount(email.accountId))
            label.id: label,
        };
        return MailListItem(
          key: ValueKey(email.id),
          email: email,
          accountLabel: showAccount ? accountEmail[email.accountId] : null,
          folderLabel: email.folder.label,
          labels: [
            for (final id in email.labelIds)
              if (labelsById[id] != null) labelsById[id]!,
          ],
          onTap: () => _onMailTap(email),
        );
      },
    );
  }
}

class _CompletenessBanner extends StatelessWidget {
  const _CompletenessBanner();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.warningBackground,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 16, color: colors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Posta kutusu hâlâ senkronize ediliyor. Arama sonuçları eksik olabilir.',
              style: TextStyle(fontSize: 12.5, color: colors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({
    required this.filters,
    required this.accounts,
    required this.onClear,
    required this.onClearAll,
  });

  final _AdvancedFilters filters;
  final List<MailAccount> accounts;
  final ValueChanged<_AdvancedFilters> onClear;
  final VoidCallback onClearAll;

  String? _accountEmail(String id) =>
      accounts.where((a) => a.id == id).map((a) => a.email).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, VoidCallback)>[
      if (filters.accountId case final id?)
        (
          'Hesap: ${_accountEmail(id) ?? id}',
          () => onClear(filters.copyWith(accountId: () => null)),
        ),
      if (filters.folder case final folder?)
        (
          'Klasör: ${folder.label}',
          () => onClear(filters.copyWith(folder: () => null)),
        ),
      if (filters.from case final from?)
        ('Kimden: $from', () => onClear(filters.copyWith(from: () => null))),
      if (filters.to case final to?)
        ('Kime: $to', () => onClear(filters.copyWith(to: () => null))),
      if (filters.fromDate case final date?)
        (
          'Başlangıç: ${_formatDate(date)}',
          () => onClear(filters.copyWith(fromDate: () => null)),
        ),
      if (filters.toDate case final date?)
        (
          'Bitiş: ${_formatDate(date)}',
          () => onClear(filters.copyWith(toDate: () => null)),
        ),
      if (filters.isRead == true)
        ('Okundu', () => onClear(filters.copyWith(isRead: () => null))),
      if (filters.isRead == false)
        ('Okunmadı', () => onClear(filters.copyWith(isRead: () => null))),
      if (filters.flagged == true)
        ('Yıldızlı', () => onClear(filters.copyWith(flagged: () => null))),
      if (filters.hasAttachment == true)
        ('Ek var', () => onClear(filters.copyWith(hasAttachment: () => null))),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (label, clear) in entries)
            InputChip(label: Text(label), onDeleted: clear),
          if (entries.length > 1)
            TextButton(
              onPressed: onClearAll,
              child: const Text('Filtreleri Temizle'),
            ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.accounts});

  final _AdvancedFilters initial;
  final List<MailAccount> accounts;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _AdvancedFilters _draft = widget.initial;
  late final TextEditingController _from = TextEditingController(
    text: widget.initial.from ?? '',
  );
  late final TextEditingController _to = TextEditingController(
    text: widget.initial.to ?? '',
  );

  static const _folders = [
    MailFolder.inbox,
    MailFolder.sent,
    MailFolder.drafts,
    MailFolder.archive,
    MailFolder.trash,
    MailFolder.spam,
  ];

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? _draft.fromDate : _draft.toDate) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _draft = isStart
          ? _draft.copyWith(fromDate: () => picked)
          : _draft.copyWith(toDate: () => picked);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Gelişmiş Filtreler',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _draft = _AdvancedFilters.empty),
                    child: const Text('Temizle'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.accounts.length > 1) ...[
                _SheetLabel('Hesap'),
                Wrap(
                  spacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Tüm hesaplar'),
                      selected: _draft.accountId == null,
                      onSelected: (_) => setState(
                        () => _draft = _draft.copyWith(accountId: () => null),
                      ),
                    ),
                    for (final account in widget.accounts)
                      ChoiceChip(
                        label: Text(account.email),
                        selected: _draft.accountId == account.id,
                        onSelected: (_) => setState(
                          () => _draft = _draft.copyWith(
                            accountId: () => account.id,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              _SheetLabel('Klasör'),
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Tümü'),
                    selected: _draft.folder == null,
                    onSelected: (_) => setState(
                      () => _draft = _draft.copyWith(folder: () => null),
                    ),
                  ),
                  for (final folder in _folders)
                    ChoiceChip(
                      label: Text(folder.label),
                      selected: _draft.folder == folder,
                      onSelected: (_) => setState(
                        () => _draft = _draft.copyWith(folder: () => folder),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _SheetLabel('Kimden'),
              TextField(
                controller: _from,
                decoration: const InputDecoration(
                  hintText: 'ör. ad@sirket.com',
                ),
                onChanged: (v) => _draft = _draft.copyWith(
                  from: () => v.trim().isEmpty ? null : v.trim(),
                ),
              ),
              const SizedBox(height: 12),
              _SheetLabel('Kime'),
              TextField(
                controller: _to,
                decoration: const InputDecoration(
                  hintText: 'ör. ad@sirket.com',
                ),
                onChanged: (v) => _draft = _draft.copyWith(
                  to: () => v.trim().isEmpty ? null : v.trim(),
                ),
              ),
              const SizedBox(height: 12),
              _SheetLabel('Tarih Aralığı'),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(isStart: true),
                      child: Text(
                        _draft.fromDate == null
                            ? 'Başlangıç'
                            : _ActiveFilterChips._formatDate(_draft.fromDate!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _pickDate(isStart: false),
                      child: Text(
                        _draft.toDate == null
                            ? 'Bitiş'
                            : _ActiveFilterChips._formatDate(_draft.toDate!),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SheetLabel('Durum'),
              Wrap(
                spacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Herhangi'),
                    selected: _draft.isRead == null,
                    onSelected: (_) => setState(
                      () => _draft = _draft.copyWith(isRead: () => null),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Okundu'),
                    selected: _draft.isRead == true,
                    onSelected: (_) => setState(
                      () => _draft = _draft.copyWith(isRead: () => true),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Okunmadı'),
                    selected: _draft.isRead == false,
                    onSelected: (_) => setState(
                      () => _draft = _draft.copyWith(isRead: () => false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  FilterChip(
                    label: const Text('Yıldızlı'),
                    selected: _draft.flagged == true,
                    onSelected: (v) => setState(
                      () => _draft = _draft.copyWith(
                        flagged: () => v ? true : null,
                      ),
                    ),
                  ),
                  FilterChip(
                    label: const Text('Ek var'),
                    selected: _draft.hasAttachment == true,
                    onSelected: (v) => setState(
                      () => _draft = _draft.copyWith(
                        hasAttachment: () => v ? true : null,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_draft),
                  child: const Text('Uygula'),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Filtreler VE ile birleştirilir.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: colors.tertiaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: AppTheme.colors(context).secondaryText,
      ),
    ),
  );
}

class _SearchScopeStatus extends StatelessWidget {
  const _SearchScopeStatus({
    required this.serverSearch,
    required this.loading,
    this.accountEmail,
  });

  final bool serverSearch;
  final bool loading;
  final String? accountEmail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          if (loading) ...[
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              !serverSearch
                  ? 'Aramak veya filtrelemek için yazmaya başlayın'
                  : accountEmail == null
                  ? 'Tüm hesaplarda sunucuda aranıyor'
                  : '$accountEmail hesabında aranıyor',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.colors(context).secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            friendlyErrorMessage(error),
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.colors(context).secondaryText),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            label: const Text('Tekrar dene'),
          ),
        ],
      ),
    );
  }
}

class _LabelFilter extends StatelessWidget {
  const _LabelFilter({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final repo = AppConfig.mailRepository;
    return SizedBox(
      height: 48,
      child: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: ChoiceChip(
                  label: const Text('Tümü'),
                  selected: selected == null,
                  onSelected: (_) => onSelected(null),
                ),
              ),
              for (final label in repo.getLabels())
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: ChoiceChip(
                    label: Text(label.name),
                    selected: selected == label.id,
                    selectedColor: label.color,
                    labelStyle: selected == label.id
                        ? const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                    onSelected: (_) => onSelected(label.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(
          fontSize: 14,
          color: AppTheme.colors(context).secondaryText,
        ),
      ),
    );
  }
}
