part of '../compose_screen.dart';

mixin _RecipientsMixin on _ComposeStateBase {
  void _refreshContacts() {
    final manual = [
      for (final c in _repo.getManualContacts())
        Contact(
          email: c.email,
          displayName: c.label,
          lastSeen: _manualContactRank,
        ),
    ];
    _contacts = ContactsStore.merge(
      ContactsStore.merge(
        ContactsStore.merge(
          DeviceContacts.cached,
          ContactsStore.cachedPersisted,
        ),
        manual,
      ),
      ContactsStore.fromEmails(_repo.getAllEmails()),
    );
  }

  List<String> _addressStrings(List<Recipient> recipients) => [
    for (final recipient in recipients) recipient.address,
  ];

  /// Turns whatever is left in [input] into a chip in [recipients] (used on
  /// submit/Enter and right before send/save so an address the user typed
  /// but never delimited isn't silently lost). Caller wraps this in
  /// `setState` when a rebuild is needed.
  void _commitPendingRecipient(
    List<Recipient> recipients,
    TextEditingController input,
  ) {
    final address = input.text.trim();
    if (address.isEmpty) return;
    recipients.add(
      Recipient(address, valid: emailShapePattern.hasMatch(address)),
    );
    input.clear();
  }

  /// Splits typed text on comma/whitespace, turning every completed token
  /// into a chip and leaving the trailing partial token as pending text —
  /// so a comma or space commits a chip without waiting for submit.
  void _onRecipientChanged(
    List<Recipient> recipients,
    TextEditingController input,
    String value,
  ) {
    if (!value.contains(',') && !value.contains(' ')) return;
    final parts = value.split(RegExp(r'[,\s]+'));
    final pending = parts.removeLast();
    if (parts.every((p) => p.isEmpty)) {
      input.value = TextEditingValue(
        text: pending,
        selection: TextSelection.collapsed(offset: pending.length),
      );
      return;
    }
    setState(() {
      for (final part in parts) {
        if (part.isEmpty) continue;
        recipients.add(
          Recipient(part, valid: emailShapePattern.hasMatch(part)),
        );
      }
      input.value = TextEditingValue(
        text: pending,
        selection: TextSelection.collapsed(offset: pending.length),
      );
    });
  }

  void _onRecipientSubmitted(
    List<Recipient> recipients,
    TextEditingController input,
  ) {
    setState(() => _commitPendingRecipient(recipients, input));
  }

  void _removeRecipient(List<Recipient> recipients, Recipient recipient) {
    setState(() => recipients.remove(recipient));
  }

  // --- Contact autocomplete ------------------------------------------

  void _handleFieldFocusChange(FocusNode node) {
    if (node.hasFocus) return;
    // A tap on a suggestion briefly steals focus before committing it —
    // give that tap a chance to land before tearing the overlay down.
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted && !node.hasFocus) _removeSuggestionOverlay();
    });
  }

  void _removeSuggestionOverlay() {
    _suggestionOverlay?.remove();
    _suggestionOverlay = null;
  }

  /// Shows/updates the suggestion overlay anchored to [link] for the
  /// current [query], excluding addresses already chipped in
  /// [currentRecipients]. [onSelected] adds the tapped contact as a chip.
  void _updateSuggestions(
    LayerLink link,
    String query,
    List<Recipient> currentRecipients,
    void Function(Contact) onSelected,
  ) {
    _removeSuggestionOverlay();
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    final existing = {
      for (final r in currentRecipients) r.address.toLowerCase(),
    };
    final matches = ContactsStore.search(
      _contacts,
      trimmed,
    ).where((c) => !existing.contains(c.email.toLowerCase())).take(5).toList();
    if (matches.isEmpty) return;
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        width: 280,
        child: CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          offset: const Offset(0, 4),
          child: ContactSuggestionList(
            contacts: matches,
            onSelected: onSelected,
          ),
        ),
      ),
    );
    _suggestionOverlay = entry;
    Overlay.of(context).insert(entry);
  }

  void _commitSuggestion(
    List<Recipient> recipients,
    TextEditingController input,
    Contact contact,
  ) {
    setState(() {
      recipients.add(
        Recipient(
          contact.email,
          valid: emailShapePattern.hasMatch(contact.email),
        ),
      );
      input.clear();
    });
    _removeSuggestionOverlay();
  }
}
