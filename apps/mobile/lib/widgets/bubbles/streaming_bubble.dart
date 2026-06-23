import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

class StreamingBubble extends StatefulWidget {
  final String text;
  const StreamingBubble({super.key, required this.text});

  @override
  State<StreamingBubble> createState() => _StreamingBubbleState();
}

class _StreamingBubbleState extends State<StreamingBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorController;

  @override
  void initState() {
    super.initState();
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _cursorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.text.isEmpty) return const SizedBox.shrink();

    // P4: RepaintBoundary isolates streaming redraws from the ListView.
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.bubbleMarginV,
          horizontal: AppSpacing.bubbleMarginH,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // P3: lightweight rendering during streaming — no full markdown
            // AST parsing, just code-block detection and plain text.
            // Full MarkdownBody is used in the final AssistantChatEntry
            // bubble after streaming completes.
            _LightweightStreamingBody(text: widget.text),
            AnimatedBuilder(
              animation: _cursorController,
              builder: (context, child) {
                return Opacity(
                  opacity: _cursorController.value,
                  child: const Text(
                    '\u258D',
                    style: TextStyle(fontSize: 16, height: 1),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lightweight streaming body — avoids full markdown AST parsing
// ---------------------------------------------------------------------------

/// Renders streaming text with minimal parsing: detects fenced code blocks
/// (``` fences) and renders them in a styled container, everything else as
/// plain [SelectableText].  This is ~10x cheaper than [MarkdownBody] for
/// high-frequency stream deltas.
class _LightweightStreamingBody extends StatelessWidget {
  final String text;
  const _LightweightStreamingBody({required this.text});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final baseStyle = Theme.of(context).textTheme.bodyMedium ??
        const TextStyle(fontSize: 14);
    final segments = _parseSegments(text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final seg in segments)
          if (seg.isCode)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: appColors.codeBackground,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: appColors.codeBorder),
              ),
              child: SelectableText(
                seg.content,
                style: baseStyle.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            )
          else
            SelectableText(seg.content, style: baseStyle),
      ],
    );
  }
}

class _Segment {
  final String content;
  final bool isCode;
  const _Segment({required this.content, required this.isCode});
}

/// Splits [text] into plain-text and fenced-code segments by detecting
/// ``` fences.  Handles incomplete fences (streaming cursor inside a code
/// block) gracefully.
List<_Segment> _parseSegments(String text) {
  final segments = <_Segment>[];
  final lines = text.split('\n');
  var inFence = false;
  var buffer = StringBuffer();

  for (final line in lines) {
    if (line.trimLeft().startsWith('```')) {
      if (inFence) {
        // Closing fence
        segments.add(_Segment(content: buffer.toString(), isCode: true));
        buffer = StringBuffer();
        inFence = false;
      } else {
        // Opening fence — flush pending plain text
        final plain = buffer.toString();
        if (plain.isNotEmpty) {
          segments.add(_Segment(content: plain, isCode: false));
        }
        buffer = StringBuffer();
        inFence = true;
      }
    } else {
      buffer.writeln(line);
    }
  }

  // Flush remaining content
  final remaining = buffer.toString().trimRight();
  if (remaining.isNotEmpty) {
    segments.add(_Segment(content: remaining, isCode: inFence));
  }

  return segments;
}
