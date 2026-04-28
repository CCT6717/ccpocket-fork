import 'package:ccpocket/models/messages.dart';
import 'package:ccpocket/services/session_runtime_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionRuntimeStore', () {
    test('keeps timeline and explorer history separated by session', () {
      final store = SessionRuntimeStore();

      store.applyServerMessage(
        's1',
        AssistantServerMessage(
          message: AssistantMessage(
            id: 'a1',
            role: 'assistant',
            content: const [TextContent(text: 'one')],
            model: 'claude',
          ),
        ),
      );
      store.setExplorerHistory(
        's1',
        currentPath: '/repo/lib',
        recentPeekedFiles: const ['lib/main.dart'],
      );

      store.applyServerMessage(
        's2',
        const StatusMessage(status: ProcessStatus.running),
      );

      expect(store.messages('s1'), hasLength(1));
      expect(store.messages('s2'), hasLength(1));
      expect(store.getExplorerHistory('s1').currentPath, '/repo/lib');
      expect(store.getExplorerHistory('s2').currentPath, isEmpty);
    });

    test('history replaces the cached timeline', () {
      final store = SessionRuntimeStore();
      store.applyServerMessage(
        's1',
        AssistantServerMessage(
          message: AssistantMessage(
            id: 'old',
            role: 'assistant',
            content: const [TextContent(text: 'old')],
            model: 'claude',
          ),
        ),
      );

      store.applyServerMessage(
        's1',
        HistoryMessage(
          messages: [
            const StatusMessage(status: ProcessStatus.idle),
            AssistantServerMessage(
              message: AssistantMessage(
                id: 'new',
                role: 'assistant',
                content: const [TextContent(text: 'new')],
                model: 'claude',
              ),
            ),
          ],
        ),
      );

      final messages = store.messages('s1');
      expect(messages, hasLength(2));
      expect(
        ((messages.last as AssistantServerMessage).message.content.single
                as TextContent)
            .text,
        'new',
      );
    });

    test('ignores transient stream deltas', () {
      final store = SessionRuntimeStore();

      store.applyServerMessage('s1', const StreamDeltaMessage(text: 'hello'));
      store.applyServerMessage('s1', const ThinkingDeltaMessage(text: 'hmm'));

      expect(store.messages('s1'), isEmpty);
    });

    test('migrates runtime state to a new session id', () {
      final store = SessionRuntimeStore();
      store.applyServerMessage(
        'pending',
        const StatusMessage(status: ProcessStatus.running),
      );
      store.setExplorerHistory(
        'pending',
        currentPath: '/repo',
        recentPeekedFiles: const ['README.md'],
      );

      store.migrateSession('pending', 'real');

      expect(store.messages('pending'), isEmpty);
      expect(store.getExplorerHistory('pending').currentPath, isEmpty);
      expect(store.messages('real'), hasLength(1));
      expect(store.getExplorerHistory('real').currentPath, '/repo');
    });

    test('trims old messages per session', () {
      final store = SessionRuntimeStore(maxMessagesPerSession: 2);

      store.applyServerMessage(
        's1',
        const StatusMessage(status: ProcessStatus.starting),
      );
      store.applyServerMessage(
        's1',
        const StatusMessage(status: ProcessStatus.running),
      );
      store.applyServerMessage(
        's1',
        const StatusMessage(status: ProcessStatus.idle),
      );

      final messages = store.messages('s1').cast<StatusMessage>();
      expect(messages, hasLength(2));
      expect(messages.first.status, ProcessStatus.running);
      expect(messages.last.status, ProcessStatus.idle);
    });
  });
}
