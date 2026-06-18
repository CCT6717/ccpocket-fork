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
/// This widget solves it with a **Key-swapping strategy**:
/// - The inner `MarkdownBody` gets a stable key derived from whether the text
///   has changed since the last build.
/// - When `data` stays the same, the key also stays the same → Flutter walks
///   into the existing subtree and **does nothing**.
/// - When `data` changes, the key changes → Flutter discards the old Element
///   tree and creates a fresh one.
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
  /// Counter-based key: incremented whenever any render-affecting prop changes,
  /// causing Flutter to discard the old MarkdownBody Element tree.
  int _keyCounter = 0;
  Key _childKey = const ValueKey(0);

  /// Cached prop values from the last build that produced [_childKey].
  String _lastData = '';
  bool _lastSelectable = true;
  Set<String> _lastSuffixes = const {};
  // Note: onFileTap is a closure — we track identity via hashCode as a
  // best-effort signal. If the parent recreates the closure on every build the
  // key will change every time, which is still correct (just less cached).
  int _lastTapHash = 0;

  @override
  void initState() {
    super.initState();
    _lastData = widget.data;
    _lastSelectable = widget.selectable;
    _lastSuffixes = widget.knownFileSuffixes;
    _lastTapHash = widget.onFileTap.hashCode;
  }

  @override
  void didUpdateWidget(covariant CachedMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tapHash = widget.onFileTap.hashCode;
    if (widget.data != _lastData ||
        widget.selectable != _lastSelectable ||
        widget.knownFileSuffixes != _lastSuffixes ||
        tapHash != _lastTapHash) {
      _childKey = ValueKey(++_keyCounter);
      _lastData = widget.data;
      _lastSelectable = widget.selectable;
      _lastSuffixes = widget.knownFileSuffixes;
      _lastTapHash = tapHash;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onFileTap = widget.onFileTap;
    final fileSuffixes = widget.knownFileSuffixes;

    return RepaintBoundary(
      child: MarkdownBody(
        key: _childKey,
        data: widget.data,
        selectable: widget.selectable,
        styleSheet: buildMarkdownStyle(context),
        onTapLink: handleMarkdownLink,
        inlineSyntaxes: [
          if (onFileTap != null) ...[
            FilePathSyntax(knownPathSuffixes: fileSuffixes),
            BareFilePathSyntax(knownPathSuffixes: fileSuffixes),
          ],
          ...colorCodeInlineSyntaxes,
        ],
        builders: {
          if (onFileTap != null)
            'filePath': FilePathBuilder(onTap: onFileTap),
          ...markdownBuilders,
        },
      ),
    );
  }
}