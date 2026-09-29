import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../state/app_settings_controller.dart';
import '../utils/link_safety.dart';
import '../utils/query_parameter_cleaner.dart';
import '../l10n/l10n.dart';

typedef MailLinkLauncher = Future<bool> Function(Uri uri);

class MailLinkOpener {
  MailLinkOpener._();

  static MailLinkLauncher _launcher = _launchWithPlatform;

  @visibleForTesting
  static void launcherForTest(MailLinkLauncher? launcher) {
    _launcher = launcher ?? _launchWithPlatform;
  }

  static Future<bool> _launchWithPlatform(Uri uri) => launchUrl(
    uri,
    mode: uri.scheme == 'http' || uri.scheme == 'https'
        ? LaunchMode.externalApplication
        : LaunchMode.platformDefault,
  );

  static Future<void> open(
    BuildContext context,
    String href, {
    String displayText = '',
  }) async {
    final assessment = assessMailLink(href, displayText: displayText);
    if (assessment.isBlocked) {
      _showMessage(context, _blockedMessage(assessment));
      return;
    }
    if (assessment.isSuspicious) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => SuspiciousLinkDialog(assessment: assessment),
      );
      if (proceed != true || !context.mounted) return;
    }
    var opened = false;
    try {
      final target = AppSettingsController.instance.cleanTrackingQueries
          ? cleanTrackingQueryParameters(assessment.uri!)
          : assessment.uri!;
      opened = await _launcher(target);
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      _showMessage(context, l10nNow.theLinkCouldntBeOpened);
    }
  }

  static String _blockedMessage(LinkAssessment assessment) {
    if (assessment.blockReason == LinkBlockReason.unsupportedScheme) {
      return l10nNow.theLinkWasntOpenedBecause(assessment.scheme);
    }
    return l10nNow.theLinkWasntOpenedBecauseItsAddressIs;
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }
}

class SuspiciousLinkDialog extends StatelessWidget {
  const SuspiciousLinkDialog({super.key, required this.assessment});

  final LinkAssessment assessment;

  static String warningText(LinkAssessment assessment, LinkWarning warning) {
    switch (warning) {
      case LinkWarning.displayMismatch:
        return l10nNow.theLinkTextShowsBut(assessment.displayedDomain!);
      case LinkWarning.punycodeHost:
        return l10nNow.theDomainContainsInternationalPunycode;
      case LinkWarning.mixedScripts:
        return l10nNow.theDomainMixesCharactersFrom;
      case LinkWarning.confusableCharacters:
        return l10nNow.theDomainContainsMisleadingCharacters;
      case LinkWarning.embeddedCredentials:
        return l10nNow.theAddressContainsUserInformation;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors(context);
    final unicodeHost = assessment.unicodeHost ?? '';
    final asciiHost = assessment.asciiHost ?? '';
    final labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: colors.secondaryText,
    );
    final valueStyle = TextStyle(fontSize: 15, color: colors.bodyText);
    return AlertDialog(
      title: Text(l10nNow.thisLinkLooksSuspicious),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final warning in LinkWarning.values)
              if (assessment.warnings.contains(warning))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppTheme.space2),
                  child: Text(warningText(assessment, warning)),
                ),
            const SizedBox(height: AppTheme.space2),
            Text(l10nNow.actualDestination, style: labelStyle),
            SelectableText(unicodeHost, style: valueStyle),
            if (asciiHost.isNotEmpty && asciiHost != unicodeHost) ...[
              const SizedBox(height: AppTheme.space2),
              Text(l10nNow.rawAddressPunycode, style: labelStyle),
              SelectableText(asciiHost, style: valueStyle),
            ],
            const SizedBox(height: AppTheme.space2),
            Text(l10nNow.fullLink, style: labelStyle),
            SelectableText(
              assessment.uri.toString(),
              style: TextStyle(fontSize: 13, color: colors.secondaryText),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            l10nNow.openAnyway,
            style: TextStyle(color: colors.destructive),
          ),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10nNow.cancel),
        ),
      ],
    );
  }
}

class MailLinkWidgetFactory extends WidgetFactory {
  MailLinkWidgetFactory({required this.onLinkTap});

  final void Function(String href, String displayText) onLinkTap;

  @override
  void parse(BuildTree tree) {
    final element = tree.element;
    if (element.localName == 'a' && !element.attributes.containsKey('href')) {
      final remoteHref = element.attributes['data-remote-href'];
      if (remoteHref != null && remoteHref.trim().isNotEmpty) {
        element.attributes['href'] = remoteHref;
      }
    }
    super.parse(tree);
  }

  @override
  GestureRecognizer? buildGestureRecognizer(
    BuildTree tree, {
    GestureTapCallback? onTap,
  }) {
    final element = tree.element;
    final href = element.attributes['href'];
    if (element.localName != 'a' || href == null || href.startsWith('#')) {
      return super.buildGestureRecognizer(tree, onTap: onTap);
    }
    final target = urlFull(href) ?? href;
    return super.buildGestureRecognizer(
      tree,
      onTap: () => onLinkTap(target, element.text),
    );
  }
}
