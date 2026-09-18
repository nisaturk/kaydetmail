/// A single device's login session on the account, as listed by
/// `GET /api/account/sessions`. One session per device — closing it forces
/// that device to sign in again on its next request.
class MailSession {
  const MailSession({
    required this.id,
    required this.deviceIdentifier,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
    this.isCurrentDevice = false,
  });

  final String id;
  final String deviceIdentifier;
  final DateTime createdAt;
  final DateTime lastUsedAt;
  final DateTime expiresAt;

  /// Whether this session belongs to the device the app is running on —
  /// determined locally by comparing [deviceIdentifier] against the
  /// persisted device id, the server does not flag this itself.
  final bool isCurrentDevice;

  MailSession copyWith({bool? isCurrentDevice}) => MailSession(
    id: id,
    deviceIdentifier: deviceIdentifier,
    createdAt: createdAt,
    lastUsedAt: lastUsedAt,
    expiresAt: expiresAt,
    isCurrentDevice: isCurrentDevice ?? this.isCurrentDevice,
  );
}
