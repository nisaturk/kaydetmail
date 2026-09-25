class RemoteSearchResult {
  const RemoteSearchResult({
    required this.matched,
    required this.imported,
    required this.remaining,
    required this.complete,
  });

  final int matched;
  final int imported;
  final int remaining;
  final bool complete;
}
