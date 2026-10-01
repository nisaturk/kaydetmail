import 'email.dart';

class SearchPage {
  SearchPage({required List<Email> items, required this.continuation})
    : items = List.unmodifiable(items);

  final List<Email> items;
  final SearchContinuation continuation;
  int get total =>
      continuation.accounts.values.fold(0, (sum, state) => sum + state.total);
  bool get hasMore =>
      continuation.accounts.values.any((state) => state.hasMore);
  Map<String, SearchAccountProgress> get accountProgress => Map.unmodifiable({
    for (final entry in continuation.accounts.entries)
      entry.key: SearchAccountProgress(
        total: entry.value.total,
        consumed: entry.value.consumed,
        offline: entry.value.offline,
      ),
  });
}

class SearchAccountProgress {
  const SearchAccountProgress({
    required this.total,
    required this.consumed,
    required this.offline,
  });
  final int total;
  final int consumed;
  final bool offline;
}

/// Immutable checkpoint: a failed request never advances the caller's cursor.
class SearchContinuation {
  SearchContinuation({
    required List<Object?> scope,
    required Map<String, SearchAccountCursor> accounts,
  }) : scope = List.unmodifiable(scope),
       accounts = Map.unmodifiable(accounts);

  final List<Object?> scope;
  final Map<String, SearchAccountCursor> accounts;
}

class SearchAccountCursor {
  SearchAccountCursor({
    required List<Email> buffered,
    required this.nextPage,
    required this.total,
    required this.consumed,
    required this.remoteHasMore,
    this.bufferOffset = 0,
    required this.offline,
  }) : buffered = List.unmodifiable(buffered);

  final List<Email> buffered;
  final int bufferOffset;
  final int nextPage;
  final int total;
  final int consumed;
  final bool remoteHasMore;
  final bool offline;
  bool get hasBuffered => bufferOffset < buffered.length;
  Email get head => buffered[bufferOffset];
  bool get hasMore => hasBuffered || remoteHasMore;

  SearchAccountCursor._advanced(SearchAccountCursor previous)
    : buffered = previous.buffered,
      bufferOffset = previous.bufferOffset + 1,
      nextPage = previous.nextPage,
      total = previous.total,
      consumed = previous.consumed + 1,
      remoteHasMore = previous.remoteHasMore,
      offline = previous.offline;

  SearchAccountCursor advance() => SearchAccountCursor._advanced(this);
}
