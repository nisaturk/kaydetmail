import '../state/app_settings_controller.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// The strings for the language currently chosen in Settings.
///
/// Looked up by locale rather than through a `BuildContext`, so widgets,
/// models, controllers and error mappers all read the same source. A language
/// switch reassembles the widget tree (see `_AuthGateState`), which makes
/// every `build` re-read this.
AppLocalizations get l10nNow =>
    lookupAppLocalizations(AppSettingsController.instance.locale);
