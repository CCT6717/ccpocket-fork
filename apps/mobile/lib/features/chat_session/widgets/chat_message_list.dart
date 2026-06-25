import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../../models/messages.dart';
import '../../../providers/bridge_cubits.dart';
import '../../../services/bridge_service.dart';
import '../../../widgets/message_bubble.dart';
import '../../file_peek/file_peek_sheet.dart';
import '../../file_peek/file_path_syntax.dart';
import '../../message_images/message_images_screen.dart';
import '../state/chat_session_cubit.dart';
import '../state/streaming_state.dart';
import '../state/streaming_state_cubit.dart';

@visibleForTesting
bool shouldShowForkForAssistant(List<ChatEntry> entries, int entryIndex) {
  if (entryIndex < 0 || entryIndex >= entries.length) return false;
  final entry = entries[entryIndex];
  if (entry is! ServerChatEntry || entry.message is! AssistantServerMessage) {
    return false;
  }

  for (var i = entryIndex + 1; i < entries.length; i++) {
    final next = entries[i];
    if (next is UserChatEntry) return false;
    if (next is ServerChatEntry) {
      final message = next.message;
      if (message is AssistantServerMessage) return false;
      if (message is ResultMessage) return true;
    }
  }
  return false;
}

/// Displays the chat message list with [ListView.builder] (reverse: true).
///
/// Reads entries directly from [ChatSessionCubit] state (SSOT).
/// With reverse list, offset 0 = bottom of chat, so new messages appear
/// immediately without scroll adjustment, and history prepend does not
/// shift the viewport.
///
/// **Windowing (P1):** Only the latest [_visibleLimit] entries are rendered.
/// Scrolling to the top triggers loading more (older) entries into the
/// viewport. The underlying [ChatSessionState] always holds the full list.
class ChatMessageList extends StatefulWidget {
  final String sessionId;
  final AutoScrollController scrollController;
  final String? httpBaseUrl;
  final void Function(UserChatEntry)? onRetryMessage;
  final void Function(UserChatEntry)? onRewindMessage;
  final void Function(AssistantServerMessage)? onForkMessage;
  final ValueNotifier<int>? collapseToolResults;
  final double bottomPadding;
  final bool isCodex;
  final ValueChanged<String>? onFilePeekOpened;

  /// When true, permission request bubbles default to collapsed single-line
  /// mode to avoid duplicating information shown in the approval bar.
  final bool isApprovalBarVisible;

  /// Project path for file peek (reading files from Bridge).
  final String? projectPath;

  /// When set (non-null), the list scrolls to the given [UserChatEntry].
  /// The notifier is reset to null after scrolling.
  final ValueNotifier<UserChatEntry?>? scrollToUserEntry;

  const ChatMessageList({
    super.key,
    required this.sessionId,
    required this.scrollController,
    required this.httpBaseUrl,
    required this.onRetryMessage,
    this.onRewindMessage,
    this.onForkMessage,
    required this.collapseToolResults,
    this.scrollToUserEntry,
    this.bottomPadding = 8,
    this.projectPath,
    this.isCodex = false,
    this.onFilePeekOpened,
    this.isApprovalBarVisible = false,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  // ---------------------------------------------------------------------------
  // Windowing (P1): only render the latest N entries
  // ---------------------------------------------------------------------------
  static const _initialVisibleLimit = 60;
  static const _loadMoreIncrement = 40;
  int _visibleLimit = _initialVisibleLimit;
  bool _isLoadingMore = false;

  // Cache for _resolvePlanText: avoids scanning all entries on every build.
  String? _cachedPlanText;
  int _cachedPlanEntriesHash = -1;
  final Set<String> _seenEntryKeys = <String>{};

  // P5: Cached tap closures — rebuilt only when relevant widget props change.
  FilePathTapCallback? _cachedFileTap;
  ValueChanged<UserChatEntry>? _cachedImageTap;

  // P8: Skip entry animation during user scrolling to reduce jank.
  bool _isUserScrolling = false;

  @override
  void initState() {
    super.initState();
    widget.scrollToUserEntry?.addListener(_onScrollToUserEntry);
    _seedSeenEntryKeys(context.read<ChatSessionCubit>().state.entries);
    _rebuildTapClosures();
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollToUserEntry != widget.scrollToUserEntry) {
      oldWidget.scrollToUserEntry?.removeListener(_onScrollToUserEntry);
      widget.scrollToUserEntry?.addListener(_onScrollToUserEntry);
    }
    // Reset windowing limit when switching sessions so the new session
    // starts with the initial visible count (performance optimization).
    if (oldWidget.sessionId != widget.sessionId) {
      _visibleLimit = _initialVisibleLimit;
      _cachedPlanText = null;
      _cachedPlanEntriesHash = -1;
      _seenEntryKeys
        ..clear()
        ..addAll(_collectEntryKeys(context.read<ChatSessionCubit>().state.entries));
    }
    // P5: Rebuild tap closures when relevant props change.
    if (oldWidget.projectPath != widget.projectPath ||
        oldWidget.httpBaseUrl != widget.httpBaseUrl ||
        oldWidget.onFilePeekOpened != widget.onFilePeekOpened) {
      _rebuildTapClosures();
    }
  }

  @override
  void dispose() {
    widget.scrollToUserEntry?.removeListener(_onScrollToUserEntry);
    super.dispose();
  }

  void _rebuildTapClosures() {
    _cachedFileTap = _buildFileTapHandler();
    _cachedImageTap = _buildImageTapHandler();
  }

  void _onScrollToUserEntry() {
    final entry = widget.scrollToUserEntry?.value;
    if (entry == null) return;
    widget.scrollToUserEntry?.value = null;
    _scrollToUserEntry(entry);
  }

  // ---------------------------------------------------------------------------
  // Scroll to user entry
  // ---------------------------------------------------------------------------

  /// Scrolls the chat list to make the given [UserChatEntry] visible.
  void _scrollToUserEntry(UserChatEntry entry) {
    final entries = context.read<ChatSessionCubit>().state.entries;
    final idx = entries.indexOf(entry);
    if (idx < 0) return;
    // The AutoScrollTag is keyed on the real entryIndex so we pass the actual idx
    widget.scrollController.scrollToIndex(
      idx,
      preferPosition: AutoScrollPosition.middle,
      duration: const Duration(milliseconds: 300),
    );
  }

  // ---------------------------------------------------------------------------
  // Windowing helpers
  // ---------------------------------------------------------------------------

  /// How many entries from the state are hidden off-screen at the top.
  int _indexOffsetFor(List<ChatEntry> all) =>
      all.length > _visibleLimit ? all.length - _visibleLimit : 0;

  /// Whether there are entries above the visible window (pure computation).
  bool _computeHasEarlier(List<ChatEntry> all) => all.length > _visibleLimit;

  /// Clip [all] to the latest [_visibleLimit] entries.
  List<ChatEntry> _getVisibleEntries(List<ChatEntry> all) {
    if (all.length <= _visibleLimit) {
      return all;
    }
    return all.sublist(all.length - _visibleLimit);
  }

  /// Load the next batch of older entries into the visible window.
  void _loadEarlierMessages() {
    if (_isLoadingMore) return;
    _isLoadingMore = true;

    // P7: Pre-mark entry keys that will become visible so _shouldAnimateEntry
    // returns false — avoids spawning N TweenAnimationBuilders at once.
    final allEntries = context.read<ChatSessionCubit>().state.entries;
    final newLimit = _visibleLimit + _loadMoreIncrement;
    if (allEntries.length > _visibleLimit) {
      final startIndex = (allEntries.length - newLimit).clamp(0, allEntries.length);
      final endIndex = allEntries.length - _visibleLimit;
      for (var i = startIndex; i < endIndex; i++) {
        _seenEntryKeys.add(_entryKey(allEntries[i], i));
      }
    }

    setState(() {
      _visibleLimit = newLimit;
      _isLoadingMore = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Plan text resolution (cached)
  // ---------------------------------------------------------------------------

  String? _resolvePlanText(ChatEntry entry) {
    if (entry is! ServerChatEntry) return null;
    final msg = entry.message;
    if (msg is! AssistantServerMessage) return null;
    final hasExitPlan = msg.message.content.any(
      (c) => c is ToolUseContent && c.name == 'ExitPlanMode',
    );
    if (!hasExitPlan) return null;

    final entries = context.read<ChatSessionCubit>().state.entries;
    final hash = identityHashCode(entries);
    if (_cachedPlanEntriesHash != hash || _cachedPlanText == null) {
      _cachedPlanEntriesHash = hash;
      _cachedPlanText = _findPlanFromWriteTool(entries);
    }
    return _cachedPlanText;
  }

  String? _findPlanFromWriteTool(List<ChatEntry> entries) {
    for (var i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (entry is! ServerChatEntry) continue;
      final msg = entry.message;
      if (msg is! AssistantServerMessage) continue;
      for (final c in msg.message.content) {
        if (c is! ToolUseContent || c.name != 'Write') continue;
        final filePath = c.input['file_path']?.toString() ?? '';
        if (!filePath.contains('.claude/plans/')) continue;
        final content = c.input['content']?.toString();
        if (content != null && content.isNotEmpty) return content;
      }
    }
    return null;
  }

  void _seedSeenEntryKeys(List<ChatEntry> entries) {
    _seenEntryKeys
      ..clear()
      ..addAll(_collectEntryKeys(entries));
  }

  Set<String> _collectEntryKeys(List<ChatEntry> entries) {
    final keys = <String>{};
    for (var i = 0; i < entries.length; i++) {
      keys.add(_entryKey(entries[i], i));
    }
    return keys;
  }

  bool _shouldAnimateEntry(String entryKey) {
    if (_isUserScrolling) return false;
    if (_seenEntryKeys.contains(entryKey)) return false;
    _seenEntryKeys.add(entryKey);
    return true;
  }

  FilePathTapCallback _buildFileTapHandler() {
    return (filePath) {
      final projectPath = widget.projectPath;
      if (projectPath == null || projectPath.isEmpty) return;
      openFilePeek(
        context,
        bridge: context.read<BridgeService>(),
        projectPath: projectPath,
        filePath: filePath,
        projectFiles: context.read<FileListCubit>().state,
        onResolvedFilePath: widget.onFilePeekOpened,
      );
    };
  }

  ValueChanged<UserChatEntry> _buildImageTapHandler() {
    return (user) {
      final claudeSessionId = context
          .read<ChatSessionCubit>()
          .state
          .claudeSessionId;
      final httpBaseUrl = widget.httpBaseUrl;
      if (claudeSessionId == null ||
          claudeSessionId.isEmpty ||
          httpBaseUrl == null) {
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MessageImagesScreen(
            bridge: context.read<BridgeService>(),
            httpBaseUrl: httpBaseUrl,
            claudeSessionId: claudeSessionId,
            messageUuid: user.messageUuid!,
            imageCount: user.imageCount,
          ),
        ),
      );
    };
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Use entriesVersion (int comparison, O(1)) instead of list identity to
    // decide whether entries changed.  The actual list is read via context.read.
    context.select<ChatSessionCubit, int>(
      (c) => c.state.entriesVersion,
    );
    final allEntries = context.read<ChatSessionCubit>().state.entries;
    final hiddenToolUseIds = context.select<ChatSessionCubit, Set<String>>(
      (c) => c.state.hiddenToolUseIds,
    );

    // Streaming flag — scoped BlocBuilder handles text deltas locally.
    final hasStreaming = context.select<StreamingStateCubit, bool>(
      (cubit) => cubit.state.isStreaming,
    );

    // P9: Compute fileSuffixes once at the list level instead of per-bubble.
    final fileSuffixes = context.select<FileListCubit, Set<String>>(
      (c) => FilePathSyntax.buildSuffixSet(c.state),
    );

    // Windowing: only render the latest _visibleLimit entries
    final visibleEntries = _getVisibleEntries(allEntries);
    final indexOffset = _indexOffsetFor(allEntries);
    final hasEarlier = _computeHasEarlier(allEntries);

    final visibleCount = visibleEntries.length;
    final totalCount = visibleCount + (hasStreaming ? 1 : 0);

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // Track user scrolling state for P8 (skip entry animation).
        if (notification is UserScrollNotification) {
          _isUserScrolling = notification.direction != ScrollDirection.idle;
          // Unfocus on user drag (not programmatic scroll)
          if (notification.direction != ScrollDirection.idle) {
            FocusScope.of(context).unfocus();
          }
          return false;
        }
        if (notification is ScrollEndNotification) {
          _isUserScrolling = false;

          // Scroll-to-top triggers load-more (P1 windowing)
          if (hasEarlier &&
              !_isLoadingMore &&
              notification.metrics.extentAfter <= 1.0) {
            _loadEarlierMessages();
          }
        }

        return false;
      },
      child: ListView.builder(
        controller: widget.scrollController,
        reverse: true,
        padding: EdgeInsets.only(top: 36, bottom: widget.bottomPadding),
        itemCount: totalCount,
        itemBuilder: (context, index) {
          // With reverse: true, index 0 = bottom (newest visible).
          // visIndex is position within visibleEntries (0 = oldest visible).
          final visIndex = totalCount - 1 - index;
          // entryIndex maps back to the real position in allEntries
          final entryIndex = visIndex + indexOffset;

          // Streaming entry sits at the bottom of the visible list
          if (hasStreaming && visIndex == visibleCount) {
            return BlocBuilder<StreamingStateCubit, StreamingState>(
              buildWhen: (prev, curr) =>
                  prev.text != curr.text ||
                  prev.isStreaming != curr.isStreaming,
              builder: (context, streamingState) {
                if (!streamingState.isStreaming) {
                  return const SizedBox.shrink();
                }
                return ChatEntryWidget(
                  entry: StreamingChatEntry(text: streamingState.text),
                  previous: null,
                  httpBaseUrl: widget.httpBaseUrl,
                  onRetryMessage: null,
                  collapseToolResults: null,
                  hiddenToolUseIds: const {},
                  isCodex: widget.isCodex,
                  fileSuffixes: fileSuffixes,
                );
              },
            );
          }

          final entry = allEntries[entryIndex];
          final previous = entryIndex > 0 ? allEntries[entryIndex - 1] : null;
          final entryKey = _entryKey(entry, entryIndex);
          final onForkMessage =
              widget.isCodex &&
                  shouldShowForkForAssistant(allEntries, entryIndex)
              ? widget.onForkMessage
              : null;

          Widget child = ChatEntryWidget(
            entry: entry,
            previous: previous,
            httpBaseUrl: widget.httpBaseUrl,
            onRetryMessage: widget.onRetryMessage,
            onRewindMessage: widget.onRewindMessage,
            onForkMessage: onForkMessage,
            collapseToolResults: widget.collapseToolResults,
            resolvedPlanText: _resolvePlanText(entry),
            hiddenToolUseIds: hiddenToolUseIds,
            onFileTap: _cachedFileTap,
            onImageTap: _cachedImageTap,
            isCodex: widget.isCodex,
            isApprovalBarVisible: widget.isApprovalBarVisible,
            fileSuffixes: fileSuffixes,
          );
          if (_shouldAnimateEntry(entryKey)) {
            // Animate only when an entry first appears in the list.
            child = TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 16 * (1 - value)),
                    child: child,
                  ),
                );
              },
              child: child,
            );
          }
          // AutoScrollTag keyed on the real entryIndex for scroll-to-index
          child = AutoScrollTag(
            key: ValueKey(entryKey),
            controller: widget.scrollController,
            index: entryIndex,
            child: child,
          );
          return child;
        },
      ),
    );
  }

  String _entryKey(ChatEntry entry, int index) {
    return switch (entry) {
      ServerChatEntry(:final message) => switch (message) {
        ToolResultMessage(:final toolUseId) => 'tool_result:$toolUseId',
        AssistantServerMessage(:final messageUuid, :final message) =>
          messageUuid != null && messageUuid.isNotEmpty
              ? 'assistant_uuid:$messageUuid'
              : message.id.isNotEmpty
              ? 'assistant_id:${message.id}'
              : 'assistant_ts:${entry.timestamp.microsecondsSinceEpoch}:$index',
        PermissionRequestMessage(:final toolUseId) => 'permission:$toolUseId',
        ToolUseSummaryMessage() =>
          'tool_summary:${entry.timestamp.microsecondsSinceEpoch}:$index',
        _ =>
          '${message.runtimeType}:${entry.timestamp.microsecondsSinceEpoch}:$index',
      },
      UserChatEntry(:final messageUuid, :final clientMessageId, :final text) =>
        messageUuid != null && messageUuid.isNotEmpty
            ? 'user_uuid:$messageUuid'
            : clientMessageId != null && clientMessageId.isNotEmpty
            ? 'user_client:$clientMessageId'
            : 'user_ts:${entry.timestamp.microsecondsSinceEpoch}:${text.hashCode}:$index',
      StreamingChatEntry() => 'streaming',
    };
  }
}
