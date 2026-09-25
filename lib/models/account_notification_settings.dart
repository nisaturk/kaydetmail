enum NotificationPrivacy {
  full('Full', 'Tam', 'Gönderen, konu ve kısa önizleme'),
  limited('Limited', 'Sınırlı', 'Gönderen ve konu'),
  private('Private', 'Gizli', 'Yalnızca "Yeni e-posta"');

  const NotificationPrivacy(this.backendValue, this.label, this.description);

  final String backendValue;
  final String label;
  final String description;

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
