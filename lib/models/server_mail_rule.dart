class RuleCondition {
  const RuleCondition(this.type, [this.value]);

  final String type;
  final String? value;

  factory RuleCondition.fromJson(Map<String, dynamic> json) =>
      RuleCondition(json['type'] as String, json['value'] as String?);

  Map<String, dynamic> toJson() => {'type': type, 'value': value};
}

class RuleAction {
  const RuleAction(this.type, {this.folderId, this.labelId});

  final String type;
  final String? folderId;
  final String? labelId;

  factory RuleAction.fromJson(Map<String, dynamic> json) => RuleAction(
    json['type'] as String,
    folderId: json['folderId'] as String?,
    labelId: json['labelId'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'type': type,
    if (folderId != null) 'folderId': folderId,
    if (labelId != null) 'labelId': labelId,
  };
}

class ServerMailRule {
  const ServerMailRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.priority,
    required this.logic,
    required this.conditions,
    required this.actions,
  });

  final String id;
  final String name;
  final bool enabled;
  final int priority;
  final String logic;
  final List<RuleCondition> conditions;
  final List<RuleAction> actions;

  factory ServerMailRule.fromJson(Map<String, dynamic> json) => ServerMailRule(
    id: json['id'] as String,
    name: json['name'] as String,
    enabled: json['enabled'] as bool,
    priority: json['priority'] as int,
    logic: json['logic'] as String,
    conditions: (json['conditions'] as List<dynamic>)
        .map(
          (item) =>
              RuleCondition.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
    actions: (json['actions'] as List<dynamic>)
        .map(
          (item) => RuleAction.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .toList(),
  );

  ServerMailRule copyWith({
    String? name,
    bool? enabled,
    int? priority,
    String? logic,
    List<RuleCondition>? conditions,
    List<RuleAction>? actions,
  }) => ServerMailRule(
    id: id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    priority: priority ?? this.priority,
    logic: logic ?? this.logic,
    conditions: conditions ?? this.conditions,
    actions: actions ?? this.actions,
  );

  Map<String, dynamic> toJson({String? legacyId}) => {
    'name': name,
    'enabled': enabled,
    'priority': priority,
    'logic': logic,
    'conditions': conditions.map((c) => c.toJson()).toList(),
    'actions': actions.map((a) => a.toJson()).toList(),
    'legacyId': legacyId,
  };
}
