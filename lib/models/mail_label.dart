import 'package:flutter/material.dart';

/// A user-defined label that can be attached to emails.
class MailLabel {
  const MailLabel({required this.id, required this.name, required this.color});

  final String id;
  final String name;
  final Color color;
}