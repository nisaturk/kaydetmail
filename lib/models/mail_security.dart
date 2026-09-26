class MailContentSecurity {
  const MailContentSecurity({this.signed, this.encrypted});

  final String? signed;
  final String? encrypted;
}

class MailSignatureVerification {
  const MailSignatureVerification({
    required this.standard,
    required this.status,
    required this.signers,
  });

  final String standard;
  final String status;
  final List<MailSigner> signers;
}

class MailSigner {
  const MailSigner({
    this.name,
    this.email,
    this.signedAt,
    this.certificateExpiresAt,
  });

  final String? name;
  final String? email;
  final DateTime? signedAt;
  final DateTime? certificateExpiresAt;
}
