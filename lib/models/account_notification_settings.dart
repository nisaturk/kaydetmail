import '../l10n/l10n.dart';

enum NotificationPrivacy {
  full('Full'),
  limited('Limited'),
  private('Private');

  const NotificationPrivacy(this.backendValue);

  final String backendValue;

  String get label => switch (this) {
    NotificationPrivacy.full => l10nNow.full,
    NotificationPrivacy.limited => l10nNow.limited,
    NotificationPrivacy.private => l10nNow.private,
  };

  String get description => switch (this) {
    NotificationPrivacy.full => l10nNow.senderSubjectAndAShort,
    NotificationPrivacy.limited => l10nNow.senderAndSubject,
    NotificationPrivacy.private => l10nNow.onlyNewEmail,
  };

  static NotificationPrivacy fromBackend(String? value) =>
      NotificationPrivacy.values.firstWhere(
        (privacy) => privacy.backendValue.toLowerCase() == value?.toLowerCase(),
        orElse: () => NotificationPrivacy.private,
      );
}

class AccountNotificationSettings {
  const AccountNotificationSettings({
    required this.enabled,
    required this.inboxOnly,
    required this.privacy,
    this.previewsAllowedByServer = true,
  });

  factory AccountNotificationSettings.fromJson(Map<String, dynamic> json) =>
      AccountNotificationSettings(
        enabled: json['enabled'] as bool,
        inboxOnly: json['inboxOnly'] as bool,
        privacy: NotificationPrivacy.fromBackend(json['privacy'] as String?),
        previewsAllowedByServer: json['previewsAllowedByServer'] as bool,
      );

  final bool enabled;
  final bool inboxOnly;
  final NotificationPrivacy privacy;
  final bool previewsAllowedByServer;

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'inboxOnly': inboxOnly,
    'privacy': privacy.backendValue,
  };

  AccountNotificationSettings copyWith({
    bool? enabled,
    bool? inboxOnly,
    NotificationPrivacy? privacy,
  }) => AccountNotificationSettings(
    enabled: enabled ?? this.enabled,
    inboxOnly: inboxOnly ?? this.inboxOnly,
    privacy: privacy ?? this.privacy,
    previewsAllowedByServer: previewsAllowedByServer,
  );
}
