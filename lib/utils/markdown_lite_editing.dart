import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'markdown_lite_to_html.dart';

TextEditingValue toggleBulletList(TextEditingValue value) =>
    _editLines(value, (lines, first, last) {
      _toggleList(lines, first, last, numbered: false);
    });

TextEditingValue toggleNumberedList(TextEditingValue value) =>
    _editLines(value, (lines, first, last) {
      _toggleList(lines, first, last, numbered: true);
    });

TextEditingValue toggleQuote(TextEditingValue value) =>
    _editLines(value, (lines, first, last) {
      final targets = [for (var i = first; i <= last; i++) i];
      final filled = targets.where((i) => lines[i].toString().isNotEmpty);
      final remove =
          filled.isNotEmpty && filled.every((i) => lines[i].quote.isNotEmpty);
      for (final i in targets) {
        final line = lines[i];
        if (remove) {
          lines[i] = line.copyWith(quote: _dropQuoteLevel(line.quote));
        } else if (line.quote.isEmpty) {
          lines[i] = line.copyWith(quote: line.toString().isEmpty ? '>' : '> ');
        }
      }
    });

TextEditingValue increaseIndent(TextEditingValue value) =>
    _editLines(value, (lines, first, last) {
      for (final i in _targetIndexes(lines, first, last)) {
        final line = lines[i];
        if (line.isListItem) {
          lines[i] = line.copyWith(indent: '${_spaces(line.indent)}  ');
        } else if (line.quote.isNotEmpty) {
          lines[i] = line.copyWith(quote: '> ${line.quote}');
        }
      }
    });

TextEditingValue decreaseIndent(TextEditingValue value) =>
    _editLines(value, (lines, first, last) {
      for (final i in _targetIndexes(lines, first, last)) {
        final line = lines[i];
        final indent = _spaces(line.indent);
        if (line.isListItem && indent.isNotEmpty) {
          lines[i] = line.copyWith(
            indent: indent.substring(math.min(2, indent.length)),
          );
        } else if (line.quote.isNotEmpty) {
          lines[i] = line.copyWith(quote: _dropQuoteLevel(line.quote));
        } else if (line.isListItem) {
          lines[i] = line.copyWith(clearMarker: true, indent: '');
        }
      }
    });

TextEditingValue clearFormatting(TextEditingValue value) {
  final text = value.text;
  final (start, end) = _range(value);
  final first = _lineIndexAt(text, start);
  final last = _lineIndexAt(text, end);
  final starts = _lineStarts(text);
  final blockStart = starts[first];
  final lastLineEnd = last + 1 < starts.length
      ? starts[last + 1] - 1
      : text.length;
  final firstLineEnd = first + 1 < starts.length
      ? starts[first + 1] - 1
      : text.length;
  final editor = _OffsetEditor(text, [
    if (start == end) blockStart else start,
    if (start == end) firstLineEnd else end,
    lastLineEnd,
    start,
    end,
  ]);

  for (final (pattern, openLength) in markdownLiteInlineMarkers) {
    while (true) {
      final rangeStart = editor.positions[0];
      final rangeEnd = editor.positions[1];
      final blockEnd = editor.positions[2];
      final block = editor.text.substring(blockStart, blockEnd);
      final match = pattern
          .allMatches(block)
          .map(
            (m) => (
              start: blockStart + m.start,
              end: blockStart + m.end,
              inner: m.group(1)!,
            ),
          )
          .where((m) => m.start < rangeEnd && m.end > rangeStart)
          .firstOrNull;
      if (match == null) break;
      final innerEnd = match.start + openLength + match.inner.length;
      editor.delete(innerEnd, match.end);
      editor.delete(match.start, match.start + openLength);
    }
  }

  for (var i = last; i >= first; i--) {
    final lineStart = _lineStarts(editor.text)[i];
    final lineEnd = editor.text.indexOf('\n', lineStart);
    final line = MarkdownLiteLine.parse(
      editor.text.substring(lineStart, lineEnd == -1 ? null : lineEnd),
    );
    editor.delete(lineStart, lineStart + line.prefixLength);
  }

  final selectionStart = editor.positions[3];
  final selectionEnd = editor.positions[4];
  return TextEditingValue(
    text: editor.text,
    selection: start == end
        ? TextSelection.collapsed(offset: selectionEnd)
        : TextSelection(baseOffset: selectionStart, extentOffset: selectionEnd),
  );
}

String normalizePastedStructure(
  String pasted, {
  required bool startsAtLineStart,
}) {
  final lines = pasted
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (i == 0 && !startsAtLineStart) continue;
    lines[i] = _normalizePastedLine(lines[i]);
  }
  return lines.join('\n');
}

class MarkdownLitePasteFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final old = oldValue.text;
    final (start, end) = _range(oldValue);
    final prefix = old.substring(0, start);
    final suffix = old.substring(end);
    final text = newValue.text;
    if (text.length < prefix.length + suffix.length + 2 ||
        !text.startsWith(prefix) ||
        !text.endsWith(suffix)) {
      return newValue;
    }
    final inserted = text.substring(prefix.length, text.length - suffix.length);
    final normalized = normalizePastedStructure(
      inserted,
      startsAtLineStart: prefix.isEmpty || prefix.endsWith('\n'),
    );
    if (normalized == inserted) return newValue;
    return TextEditingValue(
      text: '$prefix$normalized$suffix',
      selection: TextSelection.collapsed(
        offset: prefix.length + normalized.length,
      ),
    );
  }
}

final RegExp _pastedLeading = RegExp(r'^([ \t\u00a0]*)(.*)$');
final RegExp _pastedBullet = RegExp(r'^[•◦▪▫‣⁃●○■□–—·*][ \t\u00a0]+');
final RegExp _pastedNumber = RegExp(r'^(\d{1,9})[.)][ \t\u00a0]+');

String _normalizePastedLine(String line) {
  final match = _pastedLeading.firstMatch(line)!;
  final indent = match
      .group(1)!
      .replaceAll('\t', '  ')
      .replaceAll('\u00a0', ' ');
  final rest = match
      .group(2)!
      .replaceFirst(_pastedBullet, '- ')
      .replaceFirstMapped(_pastedNumber, (m) => '${m.group(1)}. ');
  return '$indent$rest';
}

void _toggleList(
  List<MarkdownLiteLine> lines,
  int first,
  int last, {
  required bool numbered,
}) {
  final targets = _targetIndexes(lines, first, last);
  bool hasKind(MarkdownLiteLine line) =>
      numbered ? line.isNumbered : line.isBullet;
  final remove = targets.every((i) => hasKind(lines[i]));
  for (final i in targets) {
    final line = lines[i];
    lines[i] = remove
        ? line.copyWith(clearMarker: true, indent: '')
        : line.copyWith(
            marker: numbered ? '1.' : '-',
            markerGap: line.isListItem ? line.markerGap : ' ',
          );
  }
}

List<int> _targetIndexes(List<MarkdownLiteLine> lines, int first, int last) {
  final all = [for (var i = first; i <= last; i++) i];
  if (all.length == 1) return all;
  final filled = all
      .where((i) => lines[i].isListItem || lines[i].content.trim().isNotEmpty)
      .toList();
  return filled.isEmpty ? all : filled;
}

void _renumber(List<MarkdownLiteLine> lines, int first, int last) {
  var i = first;
  while (i <= last) {
    if (!lines[i].isListItem) {
      i++;
      continue;
    }
    final depth = lines[i].quoteDepth;
    bool inRun(int index) =>
        lines[index].isListItem && lines[index].quoteDepth == depth;
    var runStart = i;
    while (runStart > 0 && inRun(runStart - 1)) {
      runStart--;
    }
    var runEnd = i;
    while (runEnd + 1 < lines.length && inRun(runEnd + 1)) {
      runEnd++;
    }
    final counters = <int>[];
    for (var index = runStart; index <= runEnd; index++) {
      final line = lines[index];
      final level = math.min(line.indentLevel, counters.length);
      while (counters.length <= level) {
        counters.add(0);
      }
      counters.length = level + 1;
      counters[level] = line.isNumbered ? counters[level] + 1 : 0;
      if (line.isNumbered) {
        lines[index] = line.copyWith(marker: '${counters[level]}.');
      }
    }
    i = runEnd + 1;
  }
}

String _dropQuoteLevel(String quote) => quote.replaceFirst(RegExp(r'^> ?'), '');

String _spaces(String indent) => indent.replaceAll('\t', '  ');

TextEditingValue _editLines(
  TextEditingValue value,
  void Function(List<MarkdownLiteLine> lines, int first, int last) edit,
) {
  final text = value.text;
  final (start, end) = _range(value);
  final first = _lineIndexAt(text, start);
  final last = _lineIndexAt(text, end);
  final lines = [
    for (final line in text.split('\n')) MarkdownLiteLine.parse(line),
  ];
  final oldPrefixes = [for (final line in lines) line.prefixLength];
  final oldStarts = _lineStarts(text);
  edit(lines, first, last);
  _renumber(
    lines,
    math.max(0, first - 1),
    math.min(lines.length - 1, last + 1),
  );
  final newText = lines.join('\n');
  final newStarts = _lineStarts(newText);

  int map(int offset) {
    final index = _lineIndexAt(text, offset);
    final column = offset - oldStarts[index];
    final oldPrefix = oldPrefixes[index];
    final newPrefix = lines[index].prefixLength;
    final newColumn = column >= oldPrefix
        ? newPrefix + column - oldPrefix
        : math.min(column, newPrefix);
    return newStarts[index] + newColumn;
  }

  return TextEditingValue(
    text: newText,
    selection: start == end
        ? TextSelection.collapsed(offset: map(end))
        : TextSelection(baseOffset: map(start), extentOffset: map(end)),
  );
}

(int, int) _range(TextEditingValue value) {
  final selection = value.selection;
  if (!selection.isValid) return (value.text.length, value.text.length);
  return (selection.start, selection.end);
}

int _lineIndexAt(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length;

List<int> _lineStarts(String text) {
  final starts = [0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) starts.add(i + 1);
  }
  return starts;
}

class _OffsetEditor {
  _OffsetEditor(this.text, this.positions);

  String text;
  final List<int> positions;

  void delete(int start, int end) {
    if (end <= start) return;
    text = text.replaceRange(start, end, '');
    final removed = end - start;
    for (var i = 0; i < positions.length; i++) {
      final position = positions[i];
      if (position >= end) {
        positions[i] = position - removed;
      } else if (position > start) {
        positions[i] = start;
      }
    }
  }
}
