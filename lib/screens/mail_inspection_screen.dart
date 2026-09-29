import '../utils/insets.dart';

import 'package:flutter/material.dart';

import '../models/mail_header_entry.dart';
import '../models/mail_security.dart';
import '../repositories/mail_repository.dart';
import '../utils/error_messages.dart';
import '../l10n/l10n.dart';

enum MailInspectionMode { headers, source, signature }

class MailInspectionScreen extends StatefulWidget {
  const MailInspectionScreen({
    super.key,
    required this.mailId,
    required this.mode,
    required this.repository,
  });

  final String mailId;
  final MailInspectionMode mode;
  final MailRepository repository;

  @override
  State<MailInspectionScreen> createState() => _MailInspectionScreenState();
}

class _MailInspectionScreenState extends State<MailInspectionScreen> {
  late Future<Object> _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _result = switch (widget.mode) {
      MailInspectionMode.headers => widget.repository.fetchMailHeaders(
        widget.mailId,
      ),
      MailInspectionMode.source => widget.repository.fetchMailSource(
        widget.mailId,
      ),
      MailInspectionMode.signature => widget.repository.verifyMailSignature(
        widget.mailId,
      ),
    };
  }

  String get _title => switch (widget.mode) {
    MailInspectionMode.headers => l10nNow.allHeaders,
    MailInspectionMode.source => l10nNow.rawMime,
    MailInspectionMode.signature => l10nNow.signatureVerification,
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(_title)),
    body: FutureBuilder<Object>(
      future: _result,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10nNow.couldntGetTheMessageSource(
                      friendlyErrorMessage(snapshot.error!),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(_load),
                  child: Text(l10nNow.tryAgain),
                ),
              ],
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return switch (snapshot.data!) {
          List<MailHeaderEntry> headers => ListView.separated(
            padding: withBottomInset(context, const EdgeInsets.all(16)),
            itemCount: headers.length,
            separatorBuilder: (_, _) => const Divider(height: 20),
            itemBuilder: (context, index) {
              final header = headers[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    header.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(header.value),
                ],
              );
            },
          ),
          String source => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              source,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          MailSignatureVerification signature => _signatureView(signature),
          _ => const SizedBox.shrink(),
        };
      },
    ),
  );

  Widget _signatureView(MailSignatureVerification signature) {
    final status = switch (signature.status) {
      'Valid' => l10nNow.signatureAndCertificateChainVerified,
      'Untrusted' => l10nNow.signatureMatchesCertificateIsntTrusted,
      'Invalid' => l10nNow.signatureIsInvalid,
      _ => l10nNow.signatureCouldntBeVerified,
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          signature.standard == 'SMime' ? 'S/MIME' : 'OpenPGP',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(status),
        if (signature.standard == 'OpenPgp') ...[
          const SizedBox(height: 12),
          Text(l10nNow.openpgpKeyManagementAndVerification),
        ],
        for (final signer in signature.signers) ...[
          const Divider(height: 32),
          Text(signer.name ?? signer.email ?? l10nNow.unknownSigner),
          if (signer.email != null) SelectableText(signer.email!),
          if (signer.signedAt != null)
            Text(l10nNow.signatureDate(signer.signedAt!.toLocal())),
          if (signer.certificateExpiresAt != null)
            Text(
              l10nNow.certificateExpires(
                signer.certificateExpiresAt!.toLocal(),
              ),
            ),
        ],
      ],
    );
  }
}
