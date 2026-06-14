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
  /// When [widget.data] changes, we swap this key so Flutter discards the old
  /// MarkdownBody Element tree and builds a fresh one from scratch.
  Key _childKey = UniqueKey();

  /// The data value that produced [_childKey].
  String _lastData = '';

  @override
  void initState() {
    super.initState();
    _lastData = widget.data;
    _childKey = const ValueKey<bool>(true);
  }

  @override
  void didUpdateWidget(covariant CachedMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.data != _lastData) {
      _childKey = UniqueKey();
      _lastData = widget.data;
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