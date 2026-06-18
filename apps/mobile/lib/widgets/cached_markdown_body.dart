import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/markdown_style.dart';
import '../features/file_peek/file_path_syntax.dart';

/// A [MarkdownBody] wrapper that uses Key-based subtree reuse to avoid
/// re-parsing the markdown AST when the text hasn't changed.
///
/// ## Why this works
///
/// In Flutter, Widgets are ephemeral configuration objects created anew each
/// build.  Creating a new `MarkdownBody(data: text)` on every build is cheap;
/// the problem is that the framework still calls `update()` → `build()` on
/// every Element in the existing subtree, causing `MarkdownBody` to re-parse
/// the AST and regenerate its internal widget tree (dozens of RichText/TextSpan
/// allocations).
///
/// This widget solves it with a **render-keyed cached child**:
/// - The inner `MarkdownBody` widget instance is cached and reused while all
///   render-affecting inputs stay the same.
/// - When those inputs change, a new cached child is created with a new key.
///
/// A `RepaintBoundary` wraps the whole thing so repaints are also isolated
/// from the parent layer.
class CachedMarkdownBody extends StatefulWidget {
  final String data;
  final FilePathTapCallback? onFileTap;
  final Set<String> knownFileSuffixes;
  final bool selectable;

  const CachedMarkdownBody({
    super.key,
    required this.data,
    this.onFileTap,
    this.knownFileSuffixes = const {},
    this.selectable = true,
  });

  @override
  State<CachedMarkdownBody> createState() => _CachedMarkdownBodyState();
}

class _CachedMarkdownBodyState extends State<CachedMarkdownBody> {
  _CachedMarkdownRenderKey? _cachedRenderKey;
  Widget? _cachedMarkdownBody;

  @override
  Widget build(BuildContext context) {
    final onFileTap = widget.onFileTap;
    final fileSuffixes = widget.knownFileSuffixes;
    final styleSheet = buildMarkdownStyle(context);
    final renderKey = _CachedMarkdownRenderKey(
      data: widget.data,
      selectable: widget.selectable,
      hasFileTapHandler: onFileTap != null,
      sortedSuffixes: _sortedSuffixes(fileSuffixes),
      themeSignature: _themeSignature(context),
    );
    if (_cachedRenderKey != renderKey || _cachedMarkdownBody == null) {
      _cachedRenderKey = renderKey;
      _cachedMarkdownBody = MarkdownBody(
        key: ValueKey(renderKey),
        data: widget.data,
        selectable: widget.selectable,
        styleSheet: styleSheet,
        onTapLink: handleMarkdownLink,
        inlineSyntaxes: [
          if (onFileTap != null) ...[
            FilePathSyntax(knownPathSuffixes: fileSuffixes),
            BareFilePathSyntax(knownPathSuffixes: fileSuffixes),
          ],
          ...colorCodeInlineSyntaxes,
        ],
        builders: {
          if (onFileTap != null) 'filePath': FilePathBuilder(onTap: onFileTap),
          ...markdownBuilders,
        },
      );
    }

    return RepaintBoundary(child: _cachedMarkdownBody!);
  }
}

List<String> _sortedSuffixes(Set<String> suffixes) {
  if (suffixes.isEmpty) return const [];
  final sorted = suffixes.toList()..sort();
  return sorted;
}

String _themeSignature(BuildContext context) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;
  final textTheme = theme.textTheme;
  return [
    theme.brightness.name,
    theme.useMaterial3,
    colorScheme.primary.toARGB32(),
    colorScheme.onSurface.toARGB32(),
    colorScheme.secondary.toARGB32(),
    colorScheme.surface.toARGB32(),
    textTheme.bodyMedium?.fontFamily,
    textTheme.bodyMedium?.fontSize,
    textTheme.bodyMedium?.fontWeight?.value,
    textTheme.bodyMedium?.height,
    textTheme.bodyLarge?.fontFamily,
    textTheme.bodyLarge?.fontSize,
    textTheme.bodyLarge?.fontWeight?.value,
    textTheme.bodyLarge?.height,
  ].join('|');
}

@immutable
class _CachedMarkdownRenderKey {
  final String data;
  final bool selectable;
  final bool hasFileTapHandler;
  final List<String> sortedSuffixes;
  final String themeSignature;

  const _CachedMarkdownRenderKey({
    required this.data,
    required this.selectable,
    required this.hasFileTapHandler,
    required this.sortedSuffixes,
    required this.themeSignature,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _CachedMarkdownRenderKey &&
            data == other.data &&
            selectable == other.selectable &&
            hasFileTapHandler == other.hasFileTapHandler &&
            themeSignature == other.themeSignature &&
            _listEquals(sortedSuffixes, other.sortedSuffixes);
  }

  @override
  int get hashCode => Object.hash(
    data,
    selectable,
    hasFileTapHandler,
    themeSignature,
    Object.hashAll(sortedSuffixes),
  );
}

bool _listEquals(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
