import 'email.dart';
import 'mail_folder.dart';
import 'mail_label.dart';

/// The kind of check a [MailRuleCondition] performs against incoming mail.
///
/// Only [senderContains] is implemented for v1. The enum exists so a future
/// condition (subject contains, has attachment, …) slots in without
/// reshaping storage or [MailRuleCondition] itself.
enum MailRuleConditionType { senderContains }

/// One rule's trigger. [value] is matched case-insensitively.
class MailRuleCondition {
  const MailRuleCondition({required this.type, required this.value});

  factory MailRuleCondition.senderContains(String value) => MailRuleCondition(
    type: MailRuleConditionType.senderContains,
    value: value,
  );

  final MailRuleConditionType type;
  final String value;

  /// Whether [email] satisfies this condition.
  bool matches(Email email) {
    final needle = value.trim().toLowerCase();
    if (needle.isEmpty) return false;
    switch (type) {
      case MailRuleConditionType.senderContains:
        return email.senderEmail.toLowerCase().contains(needle) ||
            email.senderName.toLowerCase().contains(needle);
    }
  }

  /// Turkish one-line summary shown in the rules list.
  String get summary => switch (type) {
    MailRuleConditionType.senderContains => 'Gönderen adresi "$value" içeriyor',
  };

  Map<String, dynamic> toJson() => {'type': type.name, 'value': value};

  factory MailRuleCondition.fromJson(Map<String, dynamic> json) {
    final type = MailRuleConditionType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => MailRuleConditionType.senderContains,
    );
    return MailRuleCondition(type: type, value: json['value'] as String? ?? '');
  }
}

/// What a matching rule does to the mail.
enum MailRuleActionType { moveToFolder, addLabel }

/// One rule's effect: either [moveToFolder] (a real, non-virtual folder —
/// [MailFolder.inbox]/[MailFolder.starred]/[MailFolder.snoozed] are never
/// valid targets) or [addLabel] (a label id local to the rule's own
/// account).
class MailRuleAction {
  const MailRuleAction({required this.type, this.folder, this.labelId})
    : assert(
        type != MailRuleActionType.moveToFolder || folder != null,
        'moveToFolder actions require a folder',
      ),
      assert(
        type != MailRuleActionType.addLabel || labelId != null,
        'addLabel actions require a labelId',
      );

  factory MailRuleAction.moveToFolder(MailFolder folder) =>
      MailRuleAction(type: MailRuleActionType.moveToFolder, folder: folder);

  factory MailRuleAction.addLabel(String labelId) =>
      MailRuleAction(type: MailRuleActionType.addLabel, labelId: labelId);

  final MailRuleActionType type;
  final MailFolder? folder;
  final String? labelId;

  /// Turkish one-line summary. [labels] resolves [labelId] to a name; an
  /// unknown/deleted label falls back to a generic "Etiket".
  String summary(List<MailLabel> labels) => switch (type) {
    MailRuleActionType.moveToFolder => '${folder!.label} klasörüne taşı',
    MailRuleActionType.addLabel => '"${_labelName(labels)}" olarak etiketle',
  };

  String _labelName(List<MailLabel> labels) {
    for (final label in labels) {
      if (label.id == labelId) return label.name;
    }
    return 'Etiket';
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    if (folder != null) 'folder': folder!.name,
    if (labelId != null) 'labelId': labelId,
  };

  factory MailRuleAction.fromJson(Map<String, dynamic> json) {
    if (json['type'] == MailRuleActionType.addLabel.name) {
      return MailRuleAction.addLabel(json['labelId'] as String? ?? '');
    }
    final folderName = json['folder'] as String?;
    final folder = MailFolder.values.firstWhere(
      (f) => f.name == folderName,
      orElse: () => MailFolder.archive,
    );
    return MailRuleAction.moveToFolder(folder);
  }
}

/// A client-side filter rule: "when [condition] matches an Inbox mail, run
/// [action]". Evaluated by `MailRulesEngine`; managed by
/// `RulesSettingsScreen`. See `MailRulesStore` for persistence and account
/// scoping.
class MailRule {
  const MailRule({
    required this.id,
    required this.condition,
    required this.action,
  });

  final String id;
  final MailRuleCondition condition;
  final MailRuleAction action;

  bool matches(Email email) => condition.matches(email);

  MailRule copyWith({MailRuleCondition? condition, MailRuleAction? action}) =>
      MailRule(
        id: id,
        condition: condition ?? this.condition,
        action: action ?? this.action,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'condition': condition.toJson(),
    'action': action.toJson(),
  };

  factory MailRule.fromJson(Map<String, dynamic> json) => MailRule(
    id: json['id'] as String,
    condition: MailRuleCondition.fromJson(
      Map<String, dynamic>.from(json['condition'] as Map),
    ),
    action: MailRuleAction.fromJson(
      Map<String, dynamic>.from(json['action'] as Map),
    ),
  );

  @override
  bool operator ==(Object other) => other is MailRule && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
