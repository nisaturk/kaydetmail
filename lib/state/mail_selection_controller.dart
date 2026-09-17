import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Selection mode state shared between the mail list and the app bar.
///
/// The list toggles ids in here; the app bar in `HomeScreen` listens to it to
/// show "N selected", "Select all" and "Cancel".
class MailSelectionController extends ChangeNotifier {
  final Set<String> _selected = {};
  List<String> _visibleIds = const [];
  bool _active = false;

  bool get isActive => _active;
  int get count => _selected.length;
  Set<String> get selectedIds => UnmodifiableSetView(_selected);

  /// Called by the list so "Select all" knows the current folder's mails.
  void syncVisibleIds(List<String> ids) => _visibleIds = ids;

  /// Enters selection mode (without selecting anything).
  void enter() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  /// Toggles one mail on/off, entering selection mode if needed.
  void toggle(String id) {
    if (!_active) enter();
    if (!_selected.add(id)) {
      _selected.remove(id);
    }
    notifyListeners();
  }

  void selectAllVisible() {
    _selected.addAll(_visibleIds);
    notifyListeners();
  }

  void exit() {
    if (!_active && _selected.isEmpty) return;
    _active = false;
    _selected.clear();
    notifyListeners();
  }
}
