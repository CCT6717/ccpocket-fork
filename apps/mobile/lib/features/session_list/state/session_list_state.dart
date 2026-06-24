import 'package:collection/collection.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../models/messages.dart';

part 'session_list_state.freezed.dart';

/// Provider filter for recent sessions (toggles: All → Codex → Claude → All).
enum ProviderFilter { all, claude, codex }

/// A group of recent sessions under the same project path.
class ProjectSessionGroup {
  final String projectPath;
  final String projectName;
  final List<RecentSession> sessions;

  const ProjectSessionGroup({
    required this.projectPath,
    required this.projectName,
    required this.sessions,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ProjectSessionGroup) return false;
    return projectPath == other.projectPath &&
        projectName == other.projectName &&
        const ListEquality().equals(sessions, other.sessions);
  }

  @override
  int get hashCode =>
      Object.hash(projectPath, projectName, const ListEquality().hash(sessions));
}

/// Group [sessions] by [projectPaths], preserving the order of [projectPaths].
List<ProjectSessionGroup> groupSessionsByProject({
  required Iterable<String> projectPaths,
  required List<RecentSession> sessions,
}) {
  final grouped = <String, List<RecentSession>>{
    for (final path in projectPaths)
      if (path.isNotEmpty) path: <RecentSession>[],
  };
  for (final session in sessions) {
    grouped.putIfAbsent(session.projectPath, () => <RecentSession>[]);
    grouped[session.projectPath]!.add(session);
  }
  return [
    for (final entry in grouped.entries)
      ProjectSessionGroup(
        projectPath: entry.key,
        projectName: pathBasename(entry.key),
        sessions: entry.value,
      ),
  ];
}

/// Core state for the session list screen.
@freezed
abstract class SessionListState with _$SessionListState {
  const factory SessionListState({
    /// All sessions loaded from the server (including paginated results).
    @Default([]) List<RecentSession> sessions,

    /// Whether there are more sessions available on the server.
    @Default(false) bool hasMore,

    /// Loading more sessions (pagination).
    @Default(false) bool isLoadingMore,

    /// Initial loading (true until the first recent sessions response arrives).
    @Default(true) bool isInitialLoading,

    /// Client-side text search query (bound to the TextField, sent to server
    /// after debounce).
    @Default('') String searchQuery,

    /// Accumulated project paths from all loaded sessions + project history.
    /// Used for the "New Session" project picker.
    @Default({}) Set<String> accumulatedProjectPaths,

    /// Project paths collapsed by the user. Defaults to empty because project
    /// groups are expanded by default.
    @Default({}) Set<String> collapsedProjectPaths,

    /// Project paths currently loading an additional page.
    @Default({}) Set<String> loadingProjectPaths,

    /// Project paths known to have no more recent sessions to load.
    @Default({}) Set<String> exhaustedProjectPaths,

    /// Per-project number of recent sessions currently visible in the list.
    @Default({}) Map<String, int> projectSessionDisplayLimits,

    /// Provider filter (All / Claude / Codex). Applied server-side.
    @Default(ProviderFilter.all) ProviderFilter providerFilter,

    /// Named-only filter toggle. Applied server-side.
    @Default(false) bool namedOnly,

    /// Precomputed deduplicated recent sessions after removing running/pending
    /// sessions. Computed by [SessionListCubit.updateDerivedState].
    @Default([]) List<RecentSession> filteredRecentSessions,

    /// Precomputed project groups for the recent sessions list.
    @Default([]) List<ProjectSessionGroup> groupedRecentSessions,

    /// IDs of currently running sessions (including claudeSessionId aliases).
    @Default({}) Set<String> runningSessionIds,

    /// IDs of offline pending resume actions.
    @Default({}) Set<String> pendingResumeSessionIds,
  }) = _SessionListState;
}
