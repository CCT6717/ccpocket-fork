import 'dart:async';

import 'package:ccpocket/features/chat_session/state/chat_session_cubit.dart';
import 'package:ccpocket/features/chat_session/state/streaming_state_cubit.dart';
import 'package:ccpocket/features/chat_session/widgets/chat_message_list.dart';
import 'package:ccpocket/l10n/app_localizations.dart';
import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/providers/bridge_cubits.dart';
import 'package:ccpocket/services/bridge_service.dart';
import 'package:ccpocket/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

class _MockBridgeService extends BridgeService {
  final _messageController = StreamController<ServerMessage>.broadcast();
  final _taggedController =
      StreamController<(ServerMessage, String?)>.broadcast();

  @override
  Stream<ServerMessage> get messages => _messageController.stream;

  @override
  Stream<ServerMessage> messagesForSession(String sessionId) {
    return _taggedController.stream
        .where((pair) => pair.$2 == null || pair.$2 == sessionId)
        .map((pair) => pair.$1);
  }

  @override
  void send(ClientMessage message) {}

  @override
  void interrupt(String sessionId) {}

  @override
  void stopSession(String sessionId) {}

  @override
  void requestFileList(String projectPath) {}

  @override
  void requestSessionList() {}

  @override
  void requestSessionHistory(String sessionId) {}

  @override
  void dispose() {
    _messageController.close();
    _taggedController.close();
    super.dispose();
  }
}

class _TestChatSessionCubit extends ChatSessionCubit {
  _TestChatSessionCubit({
    required super.sessionId,
    required super.bridge,
    required super.streamingCubit,
  });

  void setEntries(List<ChatEntry> entries) {
    emit(state.copyWith(
      entries: entries,
      entriesVersion: state.entriesVersion + 1,
    ));
  }

  void setHiddenToolUseIds(Set<String> hiddenToolUseIds) {
    emit(state.copyWith(hiddenToolUseIds: hiddenToolUseIds));
  }
}

Widget _wrapChatList({
  required _TestChatSessionCubit cubit,
  required StreamingStateCubit streamingCubit,
  required AutoScrollController scrollController,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: AppTheme.darkTheme,
    home: MultiBlocProvider(
      providers: [
        BlocProvider<ChatSessionCubit>.value(value: cubit),
        BlocProvider<StreamingStateCubit>.value(value: streamingCubit),
        BlocProvider<FileListCubit>(
          create: (_) => FileListCubit(const <String>[], Stream<List<String>>.empty()),
        ),
      ],
      child: Scaffold(
        body: ChatMessageList(
          sessionId: cubit.sessionId,
          scrollController: scrollController,
          httpBaseUrl: null,
          onRetryMessage: null,
          collapseToolResults: null,
        ),
      ),
    ),
  );
}

UserChatEntry _user(String text, String clientMessageId) => UserChatEntry(
  text,
  clientMessageId: clientMessageId,
);

Finder _entryAnimationFinder() {
  return find.byWidgetPredicate(
    (widget) => widget is TweenAnimationBuilder<double>,
    description: 'entry animation',
  );
}

void main() {
  late _MockBridgeService bridge;
  late StreamingStateCubit streamingCubit;
  late _TestChatSessionCubit cubit;
  late AutoScrollController scrollController;

  setUp(() async {
    bridge = _MockBridgeService();
    streamingCubit = StreamingStateCubit();
    cubit = _TestChatSessionCubit(
      sessionId: 'test-session',
      bridge: bridge,
      streamingCubit: streamingCubit,
    );
    scrollController = AutoScrollController();
    await Future<void>.microtask(() {});
  });

  tearDown(() async {
    scrollController.dispose();
    await cubit.close();
    await streamingCubit.close();
    bridge.dispose();
  });

  testWidgets('only newly added entries animate into view', (tester) async {
    cubit.setEntries([_user('first message', 'u1')]);

    await tester.pumpWidget(
      _wrapChatList(
        cubit: cubit,
        streamingCubit: streamingCubit,
        scrollController: scrollController,
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    cubit.setEntries([
      _user('first message', 'u1'),
      _user('second message', 'u2'),
    ]);
    await tester.pump();

    final animationFinder = _entryAnimationFinder();
    expect(animationFinder, findsOneWidget);
    expect(
      find.ancestor(of: find.text('first message'), matching: animationFinder),
      findsNothing,
    );
    expect(
      find.ancestor(of: find.text('second message'), matching: animationFinder),
      findsOneWidget,
    );
  });

  testWidgets('existing entries do not replay animation on unrelated rebuild', (
    tester,
  ) async {
    cubit.setEntries([_user('stable message', 'u1')]);

    await tester.pumpWidget(
      _wrapChatList(
        cubit: cubit,
        streamingCubit: streamingCubit,
        scrollController: scrollController,
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    cubit.setHiddenToolUseIds({'tool-1'});
    await tester.pump();

    expect(_entryAnimationFinder(), findsNothing);
  });
}
