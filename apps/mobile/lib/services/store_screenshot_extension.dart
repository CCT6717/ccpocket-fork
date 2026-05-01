/// Registers Marionette custom extensions for store screenshot automation.
///
/// These extensions allow the `call_custom_extension` MCP tool to navigate
/// directly to store screenshot mock scenarios without manually tapping
/// through the UI. Used by the `/update-store` skill.
///
/// Extensions registered:
/// - `ccpocket.navigateToStoreScenario` — navigate to a named store scenario
/// - `ccpocket.popToRoot` — pop all routes back to root
/// - `ccpocket.setTheme` — switch theme (light/dark/system)
/// - `ccpocket.setLocale` — switch app language (en/ja/zh/ko)
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:marionette_flutter/marionette_flutter.dart';

import '../features/claude_session/claude_session_screen.dart';
import '../features/codex_session/codex_session_screen.dart';
import '../features/explore/explore_screen.dart';
import '../features/git/git_screen.dart';
import '../features/session_list/state/session_list_cubit.dart';
import '../features/session_list/state/session_list_state.dart';
import '../features/session_list/widgets/home_content.dart';
import '../features/session_list/widgets/session_list_app_bar.dart';
import '../features/settings/state/settings_cubit.dart';
import '../mock/mock_scenarios.dart';
import '../mock/store_screenshot_data.dart';
import '../models/messages.dart';
import '../providers/bridge_cubits.dart';
import '../services/bridge_service.dart';
import '../services/draft_service.dart';
import '../services/mock_bridge_service.dart';
import '../services/notification_service.dart';
import '../widgets/new_session_sheet.dart';

/// Static holder for app-level references needed by extension callbacks.
///
/// These are set during app initialization in [main.dart] and consumed
/// by the extension callbacks which run outside the widget tree.
class StoreScreenshotState {
  StoreScreenshotState._();

  /// Navigator key from auto_route's AppRouter.
  /// Set in [_CcpocketAppState._initRouter].
  static GlobalKey<NavigatorState>? navigatorKey;

  /// DraftService instance for scenarios that need pre-populated input.
  /// Set in [main] after DraftService creation.
  static DraftService? draftService;
}

/// Registers custom Marionette extensions for store screenshot navigation.
///
/// Call this in [main] after [MarionetteBinding.ensureInitialized()].
/// The extensions use [StoreScreenshotState] to access the navigator
/// and services — these are populated later during app startup, which
/// is fine because extensions are only called after the app is running.
void registerStoreScreenshotExtensions() {
  if (!kDebugMode) return;

  registerMarionetteExtension(
    name: 'ccpocket.navigateToStoreScenario',
    description:
        'Navigate to a store screenshot scenario by name. '
        'Available scenarios: Self-Hosted Agents, Recent Sessions, '
        'Approval List, Multi-Question Approval, Project Explorer, '
        'Git Actions, Images & Screenshots, Network Resilience, '
        'Workspace Overview, Workspace Explorer, '
        'Approval In Context, Approval Queue, Dark Workspace',
    callback: (params) async {
      final scenario = params['scenario'];
      if (scenario == null || scenario.isEmpty) {
        return MarionetteExtensionResult.invalidParams(
          'Missing required parameter: scenario',
        );
      }

      final navState = StoreScreenshotState.navigatorKey?.currentState;
      if (navState == null) {
        return MarionetteExtensionResult.error(
          1,
          'Navigator not available yet. Is the app fully initialized?',
        );
      }

      try {
        final draftService = StoreScreenshotState.draftService;
        navState.push(buildStoreScenarioRoute(scenario, draftService));
        return MarionetteExtensionResult.success({
          'scenario': scenario,
          'status': 'navigated',
        });
      } catch (e) {
        return MarionetteExtensionResult.error(2, 'Navigation failed: $e');
      }
    },
  );

  registerMarionetteExtension(
    name: 'ccpocket.popToRoot',
    description: 'Pop all routes back to the root screen.',
    callback: (params) async {
      final navState = StoreScreenshotState.navigatorKey?.currentState;
      if (navState == null) {
        return MarionetteExtensionResult.error(1, 'Navigator not available.');
      }
      navState.popUntil((route) => route.isFirst);
      return MarionetteExtensionResult.success({'status': 'popped'});
    },
  );

  registerMarionetteExtension(
    name: 'ccpocket.setTheme',
    description:
        'Switch the app theme. '
        'Values: "light", "dark", "system".',
    callback: (params) async {
      final theme = params['theme'];
      if (theme == null || theme.isEmpty) {
        return MarionetteExtensionResult.invalidParams(
          'Missing required parameter: theme (light/dark/system)',
        );
      }

      final ctx = StoreScreenshotState.navigatorKey?.currentContext;
      if (ctx == null) {
        return MarionetteExtensionResult.error(1, 'Context not available.');
      }

      final mode = switch (theme.toLowerCase()) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };
      if (mode == null) {
        return MarionetteExtensionResult.invalidParams(
          'Invalid theme: $theme. Use light, dark, or system.',
        );
      }

      ctx.read<SettingsCubit>().setThemeMode(mode);
      return MarionetteExtensionResult.success({'theme': theme});
    },
  );

  registerMarionetteExtension(
    name: 'ccpocket.setLocale',
    description:
        'Switch the app language. '
        'Values: "en", "ja", "zh", "ko", "" (system default).',
    callback: (params) async {
      final locale = params['locale'];
      if (locale == null) {
        return MarionetteExtensionResult.invalidParams(
          'Missing required parameter: locale (en/ja/zh/ko/"")',
        );
      }

      final ctx = StoreScreenshotState.navigatorKey?.currentContext;
      if (ctx == null) {
        return MarionetteExtensionResult.error(1, 'Context not available.');
      }

      ctx.read<SettingsCubit>().setAppLocaleId(locale);
      return MarionetteExtensionResult.success({'locale': locale});
    },
  );

  registerMarionetteExtension(
    name: 'ccpocket.navigateToMockScenario',
    description:
        'Navigate directly to a mock scenario chat screen by name. '
        'Available scenarios: ${mockScenarios.map((s) => s.name).join(", ")}',
    callback: (params) async {
      final name = params['scenario'];
      if (name == null || name.isEmpty) {
        return MarionetteExtensionResult.invalidParams(
          'Missing required parameter: scenario',
        );
      }

      final navState = StoreScreenshotState.navigatorKey?.currentState;
      if (navState == null) {
        return MarionetteExtensionResult.error(
          1,
          'Navigator not available yet.',
        );
      }

      final scenario = mockScenarios.where((s) => s.name == name).firstOrNull;
      if (scenario == null) {
        return MarionetteExtensionResult.invalidParams(
          'Unknown scenario: $name. '
          'Available: ${mockScenarios.map((s) => s.name).join(", ")}',
        );
      }

      try {
        navState.push(
          MaterialPageRoute(
            builder: (_) => _MockScenarioChatRoute(scenario: scenario),
          ),
        );
        return MarionetteExtensionResult.success({
          'scenario': name,
          'status': 'navigated',
        });
      } catch (e) {
        return MarionetteExtensionResult.error(2, 'Navigation failed: $e');
      }
    },
  );
}

/// Push the appropriate store scenario route.
///
/// This mirrors the logic in `mock_preview_screen.dart`'s
/// `_launchStoreScenario`, but operates with a raw [NavigatorState]
/// instead of a [BuildContext].
Route<void> buildStoreScenarioRoute(
  String scenarioName, [
  DraftService? draftService,
]) {
  switch (scenarioName) {
    case 'Self-Hosted Agents':
    case 'Session List':
    case 'Session List (Recent)':
      return MaterialPageRoute(
        builder: (_) => _StoreSessionListRoute(
          draftService: draftService,
          minimalRunning:
              scenarioName != 'Session List' && scenarioName != 'Approval List',
        ),
      );
    case 'Recent Sessions':
      return MaterialPageRoute(
        builder: (_) => _StoreSessionListRoute(
          draftService: draftService,
          minimalRunning: true,
        ),
      );
    case 'Approval List':
      return MaterialPageRoute(
        builder: (_) => _StoreSessionListRoute(draftService: draftService),
      );
    case 'New Session':
      return MaterialPageRoute(
        builder: (_) => _StoreNewSessionRoute(draftService: draftService),
      );
    case 'Multi-Question Approval':
      return MaterialPageRoute(
        builder: (_) => _StoreChatRoute(scenarioName: scenarioName),
      );
    case 'Markdown Input':
      return MaterialPageRoute(
        builder: (_) => _StoreMarkdownInputRoute(draftService: draftService),
      );
    case 'Image Attach':
      return MaterialPageRoute(
        builder: (_) => _StoreImageAttachRoute(draftService: draftService),
      );
    case 'Project Explorer':
      return MaterialPageRoute(builder: (_) => const _StoreExplorerRoute());
    case 'Git Actions':
    case 'Git Diff':
      return MaterialPageRoute(builder: (_) => const _StoreGitRoute());
    case 'Images & Screenshots':
      return MaterialPageRoute(
        builder: (_) => const _StoreVisualContextRoute(),
      );
    case 'Network Resilience':
      return MaterialPageRoute(builder: (_) => const _StoreNetworkRoute());
    case 'Workspace Overview':
      return MaterialPageRoute(
        builder: (_) => _StoreWorkspaceRoute(
          preset: _workspaceOverviewPreset,
          draftService: draftService,
        ),
      );
    case 'Workspace Explorer':
      return MaterialPageRoute(
        builder: (_) => _StoreWorkspaceRoute(
          preset: _workspaceExplorerPreset,
          draftService: draftService,
        ),
      );
    case 'Approval In Context':
      return MaterialPageRoute(
        builder: (_) => _StoreWorkspaceRoute(
          preset: _approvalInContextPreset,
          draftService: draftService,
        ),
      );
    case 'Approval Queue':
      return MaterialPageRoute(
        builder: (_) => _StoreWorkspaceRoute(
          preset: _approvalQueuePreset,
          draftService: draftService,
        ),
      );
    case 'Dark Workspace':
      return MaterialPageRoute(
        builder: (_) => _StoreThemeModeRoute(
          themeMode: ThemeMode.dark,
          child: _StoreWorkspaceRoute(
            preset: _darkWorkspacePreset,
            draftService: draftService,
          ),
        ),
      );
    default:
      throw ArgumentError.value(
        scenarioName,
        'scenarioName',
        'Unknown store scenario',
      );
  }
}

/// Phone-width Explorer route for store screenshots.
class _StoreExplorerRoute extends StatefulWidget {
  const _StoreExplorerRoute();

  @override
  State<_StoreExplorerRoute> createState() => _StoreExplorerRouteState();
}

class _StoreExplorerRouteState extends State<_StoreExplorerRoute> {
  late final MockBridgeService _mockBridge;

  @override
  void initState() {
    super.initState();
    _mockBridge = MockBridgeService();
  }

  @override
  void dispose() {
    _mockBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<BridgeService>.value(
      value: _mockBridge,
      child: const ExploreScreen(
        sessionId: 'store-explorer',
        projectPath: '/Users/dev/projects/shopify-app',
        initialFiles: storeMarkdownInputFileList,
        initialPath: 'lib/features/checkout',
        recentPeekedFiles: [
          'lib/services/stripe_service.dart',
          'lib/features/checkout/checkout_screen.dart',
        ],
      ),
    );
  }
}

// =============================================================================
// Route Widgets (duplicated from mock_preview_screen.dart's private wrappers)
//
// These are intentionally separate from the mock preview screen to avoid
// making its private widgets public. The logic is the same but adapted
// to work without a parent BuildContext (no context.read<DraftService>()).
// =============================================================================

/// Session List route for store screenshots.
class _StoreSessionListRoute extends StatefulWidget {
  final DraftService? draftService;
  final bool minimalRunning;

  const _StoreSessionListRoute({
    this.draftService,
    this.minimalRunning = false,
  });

  @override
  State<_StoreSessionListRoute> createState() => _StoreSessionListRouteState();
}

class _StoreSessionListRouteState extends State<_StoreSessionListRoute> {
  late final MockBridgeService _mockBridge;
  late final SessionListCubit _sessionListCubit;

  @override
  void initState() {
    super.initState();
    _mockBridge = MockBridgeService();
    _sessionListCubit = SessionListCubit(bridge: _mockBridge);
  }

  @override
  void dispose() {
    _sessionListCubit.close();
    _mockBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.minimalRunning
        ? storeRunningSessionsMinimal()
        : storeRunningSessions();
    final recent = storeRecentSessions();
    final projectPaths = {
      ...running.map((s) => s.projectPath),
      ...recent.map((s) => s.projectPath),
    };

    Widget body = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('CC Pocket'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
          IconButton(icon: const Icon(Icons.collections), onPressed: () {}),
          IconButton(icon: const Icon(Icons.link_off), onPressed: () {}),
        ],
      ),
      body: HomeContent(
        connectionState: BridgeConnectionState.connected,
        sessions: running,
        recentSessions: recent,
        accumulatedProjectPaths: projectPaths,
        searchQuery: '',
        isLoadingMore: false,
        isInitialLoading: false,
        hasMoreSessions: false,
        currentProjectFilter: null,
        onNewSession: () {},
        onTapRunning:
            (
              _, {
              projectPath,
              gitBranch,
              worktreePath,
              provider,
              permissionMode,
              sandboxMode,
              approvalPolicy,
              approvalsReviewer,
            }) {},
        onStopSession: (_) {},
        onResumeSession: (_) {},
        onLongPressRecentSession: (_, _) {},
        onArchiveSession: (_) {},
        onLongPressRunningSession: (_, _) {},
        onSelectProject: (_) {},
        onLoadMore: () {},
        providerFilter: ProviderFilter.all,
        namedOnly: false,
        onToggleProvider: () {},
        onToggleNamed: () {},
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: FloatingActionButton.extended(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
      ),
    );

    if (widget.draftService != null) {
      body = RepositoryProvider<DraftService>.value(
        value: widget.draftService!,
        child: BlocProvider.value(value: _sessionListCubit, child: body),
      );
    } else {
      body = BlocProvider.value(value: _sessionListCubit, child: body);
    }

    return body;
  }
}

/// Codex chat route for store screenshots (Multi-Question Approval).
class _StoreChatRoute extends StatefulWidget {
  final String scenarioName;
  const _StoreChatRoute({required this.scenarioName});

  @override
  State<_StoreChatRoute> createState() => _StoreChatRouteState();
}

class _StoreChatRouteState extends State<_StoreChatRoute> {
  late final MockBridgeService _mockService;

  @override
  void initState() {
    super.initState();
    _mockService = MockBridgeService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final history = switch (widget.scenarioName) {
        'Multi-Question Approval' => storeChatMultiQuestion,
        _ => <ServerMessage>[],
      };
      _mockService.loadHistory(history);
    });
  }

  @override
  void dispose() {
    _mockService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionId =
        'store-${widget.scenarioName.toLowerCase().replaceAll(' ', '-')}';
    return RepositoryProvider<BridgeService>.value(
      value: _mockService,
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => ConnectionCubit(
              BridgeConnectionState.connected,
              _mockService.connectionStatus,
            ),
          ),
          BlocProvider(
            create: (_) =>
                ActiveSessionsCubit(const [], _mockService.sessionList),
          ),
          BlocProvider(
            create: (_) => FileListCubit(const [], _mockService.fileList),
          ),
        ],
        child: CodexSessionScreen(
          sessionId: sessionId,
          projectPath: '/store/preview',
        ),
      ),
    );
  }
}

/// Markdown Input route for store screenshots.
class _StoreMarkdownInputRoute extends StatefulWidget {
  final DraftService? draftService;
  const _StoreMarkdownInputRoute({this.draftService});

  @override
  State<_StoreMarkdownInputRoute> createState() =>
      _StoreMarkdownInputRouteState();
}

class _StoreMarkdownInputRouteState extends State<_StoreMarkdownInputRoute> {
  static const _sessionId = 'store-markdown-input';
  late final MockBridgeService _mockService;

  @override
  void initState() {
    super.initState();
    _mockService = MockBridgeService();
    // Pre-save the markdown draft so the input field is pre-populated
    widget.draftService?.saveDraft(_sessionId, storeMarkdownInputText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mockService.loadHistory(storeChatMarkdownInput);
    });
  }

  @override
  void dispose() {
    _mockService.dispose();
    widget.draftService?.deleteDraft(_sessionId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<BridgeService>.value(
      value: _mockService,
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => ConnectionCubit(
              BridgeConnectionState.connected,
              _mockService.connectionStatus,
            ),
          ),
          BlocProvider(
            create: (_) =>
                ActiveSessionsCubit(const [], _mockService.sessionList),
          ),
          BlocProvider(
            create: (_) => FileListCubit(
              storeMarkdownInputFileList,
              _mockService.fileList,
            ),
          ),
        ],
        child: const ClaudeSessionScreen(
          sessionId: _sessionId,
          projectPath: '/store/preview',
        ),
      ),
    );
  }
}

/// Image Attachment route for store screenshots.
class _StoreImageAttachRoute extends StatefulWidget {
  final DraftService? draftService;
  const _StoreImageAttachRoute({this.draftService});

  @override
  State<_StoreImageAttachRoute> createState() => _StoreImageAttachRouteState();
}

class _StoreImageAttachRouteState extends State<_StoreImageAttachRoute> {
  static const _sessionId = 'store-image-attach';
  late final MockBridgeService _mockService;

  @override
  void initState() {
    super.initState();
    _mockService = MockBridgeService();
    // Pre-save mock images
    final mockImages = _generateMockImages();
    widget.draftService?.saveImageDraft(_sessionId, mockImages);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mockService.loadHistory(storeChatImageAttach);
    });
  }

  static List<({Uint8List bytes, String mimeType})> _generateMockImages() {
    return [
      (bytes: _createMiniPng(0xFF4A90D9), mimeType: 'image/png'),
      (bytes: _createMiniPng(0xFFE8913A), mimeType: 'image/png'),
    ];
  }

  static Uint8List _createMiniPng(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final header = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    final ihdr = _pngChunk('IHDR', [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0]);
    final rawData = [0, r, g, b];
    final idat = _pngChunk('IDAT', _zlibCompress(rawData));
    final iend = _pngChunk('IEND', []);
    return Uint8List.fromList([...header, ...ihdr, ...idat, ...iend]);
  }

  static List<int> _pngChunk(String type, List<int> data) {
    final typeBytes = type.codeUnits;
    final length = data.length;
    final chunk = <int>[
      (length >> 24) & 0xFF,
      (length >> 16) & 0xFF,
      (length >> 8) & 0xFF,
      length & 0xFF,
      ...typeBytes,
      ...data,
    ];
    final crc = _crc32([...typeBytes, ...data]);
    chunk.addAll([
      (crc >> 24) & 0xFF,
      (crc >> 16) & 0xFF,
      (crc >> 8) & 0xFF,
      crc & 0xFF,
    ]);
    return chunk;
  }

  static List<int> _zlibCompress(List<int> data) {
    final stored = <int>[
      0x78,
      0x01,
      0x01,
      data.length & 0xFF,
      (data.length >> 8) & 0xFF,
      (~data.length) & 0xFF,
      ((~data.length) >> 8) & 0xFF,
      ...data,
    ];
    int a = 1, b2 = 0;
    for (final byte in data) {
      a = (a + byte) % 65521;
      b2 = (b2 + a) % 65521;
    }
    final adler = (b2 << 16) | a;
    stored.addAll([
      (adler >> 24) & 0xFF,
      (adler >> 16) & 0xFF,
      (adler >> 8) & 0xFF,
      adler & 0xFF,
    ]);
    return stored;
  }

  static int _crc32(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  @override
  void dispose() {
    _mockService.dispose();
    widget.draftService?.deleteImageDraft(_sessionId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<BridgeService>.value(
      value: _mockService,
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => ConnectionCubit(
              BridgeConnectionState.connected,
              _mockService.connectionStatus,
            ),
          ),
          BlocProvider(
            create: (_) =>
                ActiveSessionsCubit(const [], _mockService.sessionList),
          ),
          BlocProvider(
            create: (_) => FileListCubit(const [], _mockService.fileList),
          ),
        ],
        child: const ClaudeSessionScreen(
          sessionId: _sessionId,
          projectPath: '/store/preview',
        ),
      ),
    );
  }
}

/// Diff route for store screenshots.
class _StoreGitRoute extends StatefulWidget {
  const _StoreGitRoute();

  @override
  State<_StoreGitRoute> createState() => _StoreGitRouteState();
}

class _StoreGitRouteState extends State<_StoreGitRoute> {
  late final MockBridgeService _mockBridge;

  @override
  void initState() {
    super.initState();
    _mockBridge = MockBridgeService()..mockDiff = storeMockDiff;
  }

  @override
  void dispose() {
    _mockBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<BridgeService>.value(
      value: _mockBridge,
      child: const GitScreen(projectPath: '/mock/shopify-app'),
    );
  }
}

/// Store-only visual context preview for MCP images and Mac screenshots.
class _StoreVisualContextRoute extends StatelessWidget {
  const _StoreVisualContextRoute();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Visual context'),
        actions: [
          IconButton(
            icon: const Icon(Icons.screenshot_monitor),
            tooltip: 'Screenshot',
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StoreStatusBanner(
            icon: Icons.image_search_outlined,
            title: 'MCP images and Mac screenshots',
            subtitle: 'Keep visual context beside the coding session.',
            color: cs.primaryContainer,
            foreground: cs.onPrimaryContainer,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StoreImagePreviewCard(
                  title: 'Checkout mockup',
                  subtitle: 'Attached from Photos',
                  color: const Color(0xFF6EA8FE),
                  icon: Icons.photo_library_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StoreImagePreviewCard(
                  title: 'Desktop screenshot',
                  subtitle: 'Captured from Mac',
                  color: const Color(0xFFFFB86B),
                  icon: Icons.desktop_mac_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _StoreChatPreviewCard(
            label: 'Codex',
            text:
                'I can use these screenshots to match the layout, spacing, and visual states.',
            icon: Icons.auto_awesome,
          ),
          const SizedBox(height: 12),
          _StoreChatPreviewCard(
            label: 'Claude supported',
            text:
                'Claude Code sessions appear in the same app when you need them.',
            icon: Icons.code,
          ),
          const SizedBox(height: 12),
          _StoreToolPreviewCard(
            title: 'Screenshot saved',
            subtitle: 'MacBook Pro - Safari window',
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(height: 12),
          _StoreToolPreviewCard(
            title: 'Image available in gallery',
            subtitle: '2 images linked to this session',
            icon: Icons.collections_outlined,
          ),
        ],
      ),
    );
  }
}

/// Store-only network resilience preview for offline pending messages.
class _StoreNetworkRoute extends StatelessWidget {
  const _StoreNetworkRoute();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Checkout Refactor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync',
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          _StoreStatusBanner(
            icon: Icons.wifi_off_outlined,
            title: 'Offline message pending',
            subtitle: 'It will resend automatically after reconnecting.',
            color: cs.errorContainer,
            foreground: cs.onErrorContainer,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _StoreChatPreviewCard(
                  label: 'Codex',
                  text:
                      'I finished the checkout refactor and prepared a diff for review.',
                  icon: Icons.smart_toy_outlined,
                ),
                const SizedBox(height: 12),
                _StorePendingMessageCard(
                  text:
                      'Looks good. Stage the checkout files and generate a commit message.',
                ),
                const SizedBox(height: 16),
                _StoreTimelineStep(
                  icon: Icons.download_done,
                  title: 'Recovered missed deltas',
                  subtitle: 'The latest assistant output is back in sync.',
                ),
                _StoreTimelineStep(
                  icon: Icons.schedule_send_outlined,
                  title: 'Pending message queued',
                  subtitle: 'Your reply is preserved while offline.',
                ),
                _StoreTimelineStep(
                  icon: Icons.cloud_done_outlined,
                  title: 'Ready to resend',
                  subtitle: 'CC Pocket retries when the connection returns.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreStatusBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final Color foreground;

  const _StoreStatusBanner({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.78),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreImagePreviewCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;

  const _StoreImagePreviewCard({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 176,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withValues(alpha: 0.55)],
                ),
              ),
              child: Icon(icon, size: 54, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreChatPreviewCard extends StatelessWidget {
  final String label;
  final String text;
  final IconData icon;

  const _StoreChatPreviewCard({
    required this.label,
    required this.text,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: cs.primaryContainer,
            foregroundColor: cs.onPrimaryContainer,
            child: Icon(icon, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(text, style: const TextStyle(fontSize: 13, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoreToolPreviewCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _StoreToolPreviewCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorePendingMessageCard extends StatelessWidget {
  final String text;

  const _StorePendingMessageCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text,
              style: TextStyle(color: cs.onPrimaryContainer, height: 1.35),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule, size: 13, color: cs.onPrimaryContainer),
                const SizedBox(width: 4),
                Text(
                  'Pending',
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreTimelineStep extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _StoreTimelineStep({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(icon, size: 18, color: cs.onSecondaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// New Session route for store screenshots (with bottom sheet auto-open).
class _StoreNewSessionRoute extends StatefulWidget {
  final DraftService? draftService;
  const _StoreNewSessionRoute({this.draftService});

  @override
  State<_StoreNewSessionRoute> createState() => _StoreNewSessionRouteState();
}

class _StoreNewSessionRouteState extends State<_StoreNewSessionRoute> {
  late final MockBridgeService _mockBridge;
  late final SessionListCubit _sessionListCubit;

  @override
  void initState() {
    super.initState();
    _mockBridge = MockBridgeService();
    _sessionListCubit = SessionListCubit(bridge: _mockBridge);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showNewSessionSheet();
    });
  }

  void _showNewSessionSheet() {
    if (!mounted) return;
    showNewSessionSheet(
      context: context,
      recentProjects: const [
        (path: '/Users/dev/projects/shopify-app', name: 'shopify-app'),
        (path: '/Users/dev/projects/rust-cli', name: 'rust-cli'),
        (path: '/Users/dev/projects/my-portfolio', name: 'my-portfolio'),
      ],
      projectHistory: const [],
      bridge: _mockBridge,
    );
  }

  @override
  void dispose() {
    _sessionListCubit.close();
    _mockBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = storeRunningSessionsMinimal();
    final recent = storeRecentSessions();
    final projectPaths = {
      ...running.map((s) => s.projectPath),
      ...recent.map((s) => s.projectPath),
    };

    Widget body = Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('CC Pocket'),
        actions: [
          IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
          IconButton(icon: const Icon(Icons.collections), onPressed: () {}),
          IconButton(icon: const Icon(Icons.link_off), onPressed: () {}),
        ],
      ),
      body: HomeContent(
        connectionState: BridgeConnectionState.connected,
        sessions: running,
        recentSessions: recent,
        accumulatedProjectPaths: projectPaths,
        searchQuery: '',
        isLoadingMore: false,
        isInitialLoading: false,
        hasMoreSessions: false,
        currentProjectFilter: null,
        onNewSession: () {},
        onTapRunning:
            (
              _, {
              projectPath,
              gitBranch,
              worktreePath,
              provider,
              permissionMode,
              sandboxMode,
              approvalPolicy,
              approvalsReviewer,
            }) {},
        onStopSession: (_) {},
        onResumeSession: (_) {},
        onLongPressRecentSession: (_, _) {},
        onArchiveSession: (_) {},
        onLongPressRunningSession: (_, _) {},
        onSelectProject: (_) {},
        onLoadMore: () {},
        providerFilter: ProviderFilter.all,
        namedOnly: false,
        onToggleProvider: () {},
        onToggleNamed: () {},
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: FloatingActionButton.extended(
          onPressed: _showNewSessionSheet,
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
      ),
    );

    if (widget.draftService != null) {
      body = RepositoryProvider<DraftService>.value(
        value: widget.draftService!,
        child: BlocProvider.value(value: _sessionListCubit, child: body),
      );
    } else {
      body = BlocProvider.value(value: _sessionListCubit, child: body);
    }

    return body;
  }
}

// =============================================================================
// iPad Workspace Store Screenshots
// =============================================================================

enum _StoreWorkspacePaneKind { none, git, explore }

enum _StoreWorkspaceCenterKind { markdown, approval }

enum _StoreWorkspaceRunningKind { compact, approvalFocus, approvalQueue }

class _StoreWorkspacePreset {
  final String sessionId;
  final String projectPath;
  final String sessionName;
  final String sessionSummary;
  final _StoreWorkspaceCenterKind centerKind;
  final _StoreWorkspacePaneKind rightPaneKind;
  final _StoreWorkspaceRunningKind runningKind;

  const _StoreWorkspacePreset({
    required this.sessionId,
    required this.projectPath,
    required this.sessionName,
    required this.sessionSummary,
    required this.centerKind,
    required this.rightPaneKind,
    this.runningKind = _StoreWorkspaceRunningKind.compact,
  });
}

const _storeWorkspaceProjectPath = '/Users/dev/projects/shopify-app';
const _storeWorkspaceSessionId = 'store-chat-md';
const _storeWorkspaceApprovalSessionId = 'store-chat-mq';

final Map<String, dynamic> _storeWorkspaceApprovalInput =
    _extractStoreWorkspaceApprovalInput();

Map<String, dynamic> _extractStoreWorkspaceApprovalInput() {
  for (final message in storeChatMultiQuestion) {
    if (message is! AssistantServerMessage) continue;
    for (final content in message.message.content) {
      if (content is ToolUseContent && content.name == 'AskUserQuestion') {
        return Map<String, dynamic>.from(content.input);
      }
    }
  }
  return {'questions': const []};
}

const _workspaceOverviewPreset = _StoreWorkspacePreset(
  sessionId: _storeWorkspaceSessionId,
  projectPath: _storeWorkspaceProjectPath,
  sessionName: 'Checkout Refactor',
  sessionSummary: 'Refactor the checkout module and review the resulting diff',
  centerKind: _StoreWorkspaceCenterKind.markdown,
  rightPaneKind: _StoreWorkspacePaneKind.git,
);

const _workspaceExplorerPreset = _StoreWorkspacePreset(
  sessionId: _storeWorkspaceSessionId,
  projectPath: _storeWorkspaceProjectPath,
  sessionName: 'Checkout Refactor',
  sessionSummary: 'Inspect project files while updating the checkout flow',
  centerKind: _StoreWorkspaceCenterKind.markdown,
  rightPaneKind: _StoreWorkspacePaneKind.explore,
);

const _approvalInContextPreset = _StoreWorkspacePreset(
  sessionId: _storeWorkspaceApprovalSessionId,
  projectPath: _storeWorkspaceProjectPath,
  sessionName: 'Checkout Decisions',
  sessionSummary: 'Decide how Codex should stage and verify the checkout diff',
  centerKind: _StoreWorkspaceCenterKind.approval,
  rightPaneKind: _StoreWorkspacePaneKind.none,
  runningKind: _StoreWorkspaceRunningKind.approvalFocus,
);

const _approvalQueuePreset = _StoreWorkspacePreset(
  sessionId: _storeWorkspaceApprovalSessionId,
  projectPath: _storeWorkspaceProjectPath,
  sessionName: 'Checkout Decisions',
  sessionSummary: 'Review Codex decisions before staging the checkout changes',
  centerKind: _StoreWorkspaceCenterKind.approval,
  rightPaneKind: _StoreWorkspacePaneKind.none,
  runningKind: _StoreWorkspaceRunningKind.approvalQueue,
);

const _darkWorkspacePreset = _StoreWorkspacePreset(
  sessionId: _storeWorkspaceSessionId,
  projectPath: _storeWorkspaceProjectPath,
  sessionName: 'Checkout Refactor',
  sessionSummary: 'Review the workspace layout in a focused dark theme',
  centerKind: _StoreWorkspaceCenterKind.markdown,
  rightPaneKind: _StoreWorkspacePaneKind.git,
);

class _StoreThemeModeRoute extends StatefulWidget {
  final ThemeMode themeMode;
  final Widget child;

  const _StoreThemeModeRoute({required this.themeMode, required this.child});

  @override
  State<_StoreThemeModeRoute> createState() => _StoreThemeModeRouteState();
}

class _StoreThemeModeRouteState extends State<_StoreThemeModeRoute> {
  ThemeMode? _previousMode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_previousMode != null) return;
    final settingsCubit = context.read<SettingsCubit>();
    _previousMode = settingsCubit.state.themeMode;
    if (_previousMode != widget.themeMode) {
      settingsCubit.setThemeMode(widget.themeMode);
    }
  }

  @override
  void dispose() {
    final previousMode = _previousMode;
    if (previousMode != null) {
      context.read<SettingsCubit>().setThemeMode(previousMode);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _StoreWorkspaceRoute extends StatefulWidget {
  final _StoreWorkspacePreset preset;
  final DraftService? draftService;

  const _StoreWorkspaceRoute({required this.preset, this.draftService});

  @override
  State<_StoreWorkspaceRoute> createState() => _StoreWorkspaceRouteState();
}

class _StoreWorkspaceRouteState extends State<_StoreWorkspaceRoute> {
  late final MockBridgeService _mockBridge;
  late final SessionListCubit _sessionListCubit;

  @override
  void initState() {
    super.initState();
    _mockBridge = MockBridgeService();
    _sessionListCubit = SessionListCubit(bridge: _mockBridge);
    _mockBridge.mockDiff = storeMockDiff;
    switch (widget.preset.centerKind) {
      case _StoreWorkspaceCenterKind.markdown:
        widget.draftService?.saveDraft(
          widget.preset.sessionId,
          storeMarkdownInputText,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mockBridge.loadHistory(storeChatMarkdownInput);
        });
      case _StoreWorkspaceCenterKind.approval:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _mockBridge.loadHistory(storeChatMultiQuestion);
        });
    }
    NotificationService.instance.setActiveSession(
      sessionId: widget.preset.sessionId,
      provider: 'codex',
    );
  }

  @override
  void dispose() {
    widget.draftService?.deleteDraft(widget.preset.sessionId);
    NotificationService.instance.clearActiveSession(
      sessionId: widget.preset.sessionId,
      provider: 'codex',
    );
    _sessionListCubit.close();
    _mockBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recent = _workspaceRecentSessions(widget.preset);
    final running = _workspaceRunningSessions(widget.preset);
    final projectPaths = {
      ...running.map((s) => s.projectPath),
      ...recent.map((s) => s.projectPath),
    };
    final rightPane = _buildRightPane();

    return RepositoryProvider<BridgeService>.value(
      value: _mockBridge,
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => ConnectionCubit(
              BridgeConnectionState.connected,
              _mockBridge.connectionStatus,
            ),
          ),
          BlocProvider(
            create: (_) =>
                ActiveSessionsCubit(const [], _mockBridge.sessionList),
          ),
          BlocProvider(
            create: (_) =>
                FileListCubit(storeMarkdownInputFileList, _mockBridge.fileList),
          ),
          BlocProvider.value(value: _sessionListCubit),
        ],
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: Row(
            children: [
              SizedBox(
                width: 320,
                child: _StoreWorkspaceListPane(
                  recentSessions: recent,
                  runningSessions: running,
                  projectPaths: projectPaths,
                ),
              ),
              _storePaneDivider(context),
              Expanded(child: _buildCenterPane()),
              if (rightPane != null) ...[
                _storePaneDivider(context),
                SizedBox(width: 360, child: rightPane),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterPane() {
    return switch (widget.preset.centerKind) {
      _StoreWorkspaceCenterKind.approval => CodexSessionScreen(
        sessionId: widget.preset.sessionId,
        projectPath: widget.preset.projectPath,
        hideSessionBackButton: true,
      ),
      _StoreWorkspaceCenterKind.markdown => CodexSessionScreen(
        sessionId: widget.preset.sessionId,
        projectPath: widget.preset.projectPath,
        hideSessionBackButton: true,
      ),
    };
  }

  Widget? _buildRightPane() {
    return switch (widget.preset.rightPaneKind) {
      _StoreWorkspacePaneKind.none => null,
      _StoreWorkspacePaneKind.git => GitScreen(
        projectPath: widget.preset.projectPath,
        sessionId: widget.preset.sessionId,
        embedded: true,
      ),
      _StoreWorkspacePaneKind.explore => ExploreScreen(
        sessionId: widget.preset.sessionId,
        projectPath: widget.preset.projectPath,
        initialFiles: storeMarkdownInputFileList,
        initialPath: 'lib/features/checkout',
        recentPeekedFiles: const ['lib/services/stripe_service.dart'],
        embedded: true,
      ),
    };
  }
}

class _StoreWorkspaceListPane extends StatelessWidget {
  final List<RecentSession> recentSessions;
  final List<SessionInfo> runningSessions;
  final Set<String> projectPaths;

  const _StoreWorkspaceListPane({
    required this.recentSessions,
    required this.runningSessions,
    required this.projectPaths,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            SessionListPaneHeader(
              onTitleTap: () {},
              onOpenSettings: () {},
              onOpenGallery: () {},
              onDisconnect: () {},
              onTogglePaneVisibility: () {},
            ),
            Expanded(
              child: HomeContent(
                connectionState: BridgeConnectionState.connected,
                sessions: runningSessions,
                recentSessions: recentSessions,
                accumulatedProjectPaths: projectPaths,
                searchQuery: '',
                isLoadingMore: false,
                isInitialLoading: false,
                hasMoreSessions: false,
                currentProjectFilter: null,
                onNewSession: () {},
                onTapRunning:
                    (
                      _, {
                      projectPath,
                      gitBranch,
                      worktreePath,
                      provider,
                      permissionMode,
                      sandboxMode,
                      approvalPolicy,
                      approvalsReviewer,
                    }) {},
                onStopSession: (_) {},
                onResumeSession: (_) {},
                onLongPressRecentSession: (_, _) {},
                onArchiveSession: (_) {},
                onLongPressRunningSession: (_, _) {},
                onSelectProject: (_) {},
                onLoadMore: () {},
                providerFilter: ProviderFilter.all,
                namedOnly: false,
                onToggleProvider: () {},
                onToggleNamed: () {},
                showInlineStopButtonOverride: true,
              ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: FloatingActionButton.extended(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('New'),
        ),
      ),
    );
  }
}

Widget _storePaneDivider(BuildContext context) {
  return Container(
    width: 1,
    color: Theme.of(context).dividerColor.withValues(alpha: 0.18),
  );
}

List<RecentSession> _workspaceRecentSessions(_StoreWorkspacePreset preset) => [
  ...storeRecentSessions(),
];

List<SessionInfo> _workspaceRunningSessions(_StoreWorkspacePreset preset) {
  switch (preset.runningKind) {
    case _StoreWorkspaceRunningKind.compact:
      return [
        SessionInfo(
          id: preset.sessionId,
          provider: 'codex',
          name: preset.sessionName,
          projectPath: preset.projectPath,
          status: 'running',
          createdAt: DateTime.now()
              .subtract(const Duration(minutes: 12))
              .toIso8601String(),
          lastActivityAt: DateTime.now()
              .subtract(const Duration(minutes: 1))
              .toIso8601String(),
          gitBranch: 'feat/checkout-workspace',
          lastMessage: preset.sessionSummary,
        ),
      ];
    case _StoreWorkspaceRunningKind.approvalFocus:
      return [
        _buildWorkspaceApprovalSession(
          id: preset.sessionId,
          name: preset.sessionName,
          projectPath: preset.projectPath,
          gitBranch: 'feat/checkout-redesign',
          lastMessage: 'Waiting for your decisions on the checkout refactor.',
          createdOffset: const Duration(minutes: 9),
          lastActivityOffset: const Duration(seconds: 20),
        ),
        ...storeRunningSessionsMinimal(),
      ];
    case _StoreWorkspaceRunningKind.approvalQueue:
      return [
        _buildWorkspaceApprovalSession(
          id: preset.sessionId,
          name: preset.sessionName,
          projectPath: preset.projectPath,
          gitBranch: 'feat/checkout-redesign',
          lastMessage:
              'Waiting for your decisions on migration, checks, and staging.',
          createdOffset: const Duration(minutes: 6),
          lastActivityOffset: const Duration(seconds: 15),
        ),
        SessionInfo(
          id: 'store-queue-2',
          provider: 'codex',
          name: 'Parser Benchmark',
          projectPath: '/Users/dev/projects/rust-cli',
          status: 'waiting_approval',
          createdAt: DateTime.now()
              .subtract(const Duration(minutes: 14))
              .toIso8601String(),
          lastActivityAt: DateTime.now()
              .subtract(const Duration(seconds: 40))
              .toIso8601String(),
          gitBranch: 'feat/parser',
          lastMessage: 'Ready to run the parser benchmark before merging.',
          pendingPermission: const PermissionRequestMessage(
            toolUseId: 'store-queue-bash-1',
            toolName: 'Bash',
            input: {'command': 'cargo bench parser'},
          ),
        ),
        SessionInfo(
          id: 'store-queue-3',
          provider: 'claude',
          name: 'Claude Code Plan',
          projectPath: '/Users/dev/projects/my-portfolio',
          status: 'waiting_approval',
          createdAt: DateTime.now()
              .subtract(const Duration(minutes: 18))
              .toIso8601String(),
          lastActivityAt: DateTime.now()
              .subtract(const Duration(minutes: 2))
              .toIso8601String(),
          gitBranch: 'feat/dark-mode',
          lastMessage: 'Claude Code support appears alongside Codex sessions.',
          pendingPermission: const PermissionRequestMessage(
            toolUseId: 'store-queue-plan-1',
            toolName: 'ExitPlanMode',
            input: {'plan': 'Dark mode rollout plan'},
          ),
        ),
      ];
  }
}

SessionInfo _buildWorkspaceApprovalSession({
  required String id,
  required String name,
  required String projectPath,
  required String gitBranch,
  required String lastMessage,
  required Duration createdOffset,
  required Duration lastActivityOffset,
}) {
  return SessionInfo(
    id: id,
    provider: 'codex',
    name: name,
    projectPath: projectPath,
    status: 'waiting_approval',
    createdAt: DateTime.now().subtract(createdOffset).toIso8601String(),
    lastActivityAt: DateTime.now()
        .subtract(lastActivityOffset)
        .toIso8601String(),
    gitBranch: gitBranch,
    lastMessage: lastMessage,
    pendingPermission: PermissionRequestMessage(
      toolUseId: 'store-mq-ask-1',
      toolName: 'AskUserQuestion',
      input: _storeWorkspaceApprovalInput,
    ),
  );
}

// =============================================================================
// Mock Scenario Route (for call_custom_extension navigation)
// =============================================================================

/// Chat route for mock scenario navigation via custom extension.
///
/// Mirrors `_MockChatWrapper` in mock_preview_screen.dart but works
/// without a parent BuildContext (used by call_custom_extension).
class _MockScenarioChatRoute extends StatefulWidget {
  final MockScenario scenario;
  const _MockScenarioChatRoute({required this.scenario});

  @override
  State<_MockScenarioChatRoute> createState() => _MockScenarioChatRouteState();
}

class _MockScenarioChatRouteState extends State<_MockScenarioChatRoute> {
  late final MockBridgeService _mockService;

  @override
  void initState() {
    super.initState();
    _mockService = MockBridgeService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mockService.playScenario(widget.scenario);
    });
  }

  @override
  void dispose() {
    _mockService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionId =
        'mock-${widget.scenario.name.toLowerCase().replaceAll(' ', '-')}';
    return RepositoryProvider<BridgeService>.value(
      value: _mockService,
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (_) => ConnectionCubit(
              BridgeConnectionState.connected,
              _mockService.connectionStatus,
            ),
          ),
          BlocProvider(
            create: (_) =>
                ActiveSessionsCubit(const [], _mockService.sessionList),
          ),
          BlocProvider(
            create: (_) => FileListCubit(const [], _mockService.fileList),
          ),
        ],
        child: switch (widget.scenario.provider) {
          MockScenarioProvider.codex => CodexSessionScreen(
            sessionId: sessionId,
            projectPath: '/mock/preview',
          ),
          MockScenarioProvider.claude => ClaudeSessionScreen(
            sessionId: sessionId,
            projectPath: '/mock/preview',
          ),
        },
      ),
    );
  }
}
