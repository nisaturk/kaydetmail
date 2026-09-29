part of '../mail_detail_screen.dart';

/// Fields shared by the logic mixins of [_MailDetailScreenState].
abstract class _MailDetailStateBase extends State<MailDetailScreen> {
  MailRepository get _repo => AppConfig.mailRepository;

  Email? _email;

  List<Email> _thread = const [];

  /// Last server conversation fetch. Kept apart from [_thread] so a reload
  /// rebuilds from server + current cache: a local send echo the cache has
  /// since replaced with the real Sent copy must not linger as a duplicate.
  List<Email> _fetchedThread = const [];

  final _scroll = ScrollController();

  /// Enrichment adds history below the opened mail; never reset scroll.
  bool _loading = true;

  bool _opened = false;

  /// Set while a reply/reply-all/forward compose context request is in
  /// flight — disables the triggering action so a slow/offline fetch
  /// can't be tapped twice or race a second mode's response into the
  /// wrong `ComposeScreen`.
  bool _composeActionBusy = false;

  /// Why the main mail load failed, when it did and nothing is shown yet.
  /// Null means "not found" rather than a transport error.
  Object? _loadError;

  /// Guards thread enrichment: `<mailId>@<threadId>` currently loading vs.
  /// already loaded, so listener re-runs never stack or repeat fetches.
  String? _enrichingKey;

  String? _enrichedKey;

  /// Labels apply to the whole conversation, the same unit a list row and
  /// the bulk "Etiketle" act on — labeling only the opened message would
  /// leave the row's representative (often another message) unchanged.
  List<String> get _conversationIds {
    final ids = expandThreadIds(_repo, [widget.emailId]);
    return ids.isEmpty ? [widget.emailId] : ids;
  }
}

bool _sameIds(List<Email> a, List<Email> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id) return false;
  }
  return true;
}
