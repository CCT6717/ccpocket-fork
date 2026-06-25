import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

/// Cross-session scroll offset persistence.
final Map<String, double> _scrollOffsets = {};

/// Minimum change in maxScrollExtent (in logical pixels) to be considered a
/// layout-driven shift rather than floating-point rounding noise.
const _kExtentChangeTolerance = 1.0;

/// Result record returned by [useScrollTracking].
typedef ScrollTrackingResult = ({
  AutoScrollController controller,
  bool isScrolledUp,
  void Function() scrollToBottom,
  /// Locks the scroll position at the current offset while streaming,
  /// preventing the list from jumping back when new content arrives.
  /// Returns true if the lock was saved (user was scrolled up).
  bool Function() lockScrollDuringStreaming,
  /// Releases the scroll lock so the list can scroll naturally again.
  void Function() unlockScroll,
});

/// Manages scroll position tracking with three responsibilities:
///
/// 1. **Scrolled-up detection**: Returns `isScrolledUp` when the user scrolls
///    more than 100px from the bottom.
/// 2. **Cross-session offset persistence**: Saves/restores scroll offset keyed
///    by [sessionId] so switching sessions preserves position.
/// 3. **Scroll-to-bottom**: Provides a [scrollToBottom] callback that smoothly
///    animates to the bottom (skipped when the user has scrolled up).
ScrollTrackingResult useScrollTracking(String sessionId) {
  final controller = useMemoized(AutoScrollController.new);
  // Dispose the controller when the hook is disposed.
  useEffect(() => controller.dispose, const []);

  final isScrolledUp = useState(false);

  // Ref to track isScrolledUp without rebuilds (for scrollToBottom closure).
  final isScrolledUpRef = useRef(false);

  // Streaming scroll lock — saves offset while user is scrolled up during
  // streaming to prevent the list from jumping back to the bottom.
  final savedScrollOffset = useRef<double?>(null);

  // Track previous maxScrollExtent to detect layout-driven changes
  // (e.g. Android notification shade toggling safe-area padding).
  final prevMaxExtent = useRef<double?>(null);

  useEffect(() {
    void onScroll() {
      if (!controller.hasClients) return;
      final pos = controller.position;

      final prevMax = prevMaxExtent.value;
      prevMaxExtent.value = pos.maxScrollExtent;

      // When maxScrollExtent shifts (viewport/layout change) while we were
      // already at the bottom, ignore this event — don't flip isScrolledUp.
      // The framework will settle the scroll position on the next frame.
      // This prevents the FAB from flashing when the Android notification
      // shade is pulled down/up.
      // Note: when isScrolledUp is already true (user scrolled up), we don't
      // guard — the user's intent takes priority over layout shifts.
      if (prevMax != null && !isScrolledUpRef.value) {
        final extentDelta = (pos.maxScrollExtent - prevMax).abs();
        if (extentDelta > _kExtentChangeTolerance) return;
      }

      // Reverse list: offset 0 = bottom, higher offset = scrolled up.
      final scrolled = pos.pixels > 100;
      isScrolledUpRef.value = scrolled;
      if (scrolled != isScrolledUp.value) {
        isScrolledUp.value = scrolled;
        // When user scrolls back to bottom, clear any streaming lock.
        if (!scrolled) {
          savedScrollOffset.value = null;
        }
      }
    }

    controller.addListener(onScroll);

    // Restore saved offset after first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final saved = _scrollOffsets[sessionId];
      if (saved != null && controller.hasClients) {
        controller.jumpTo(saved);
      }
    });

    return () {
      // Persist offset before disposal.
      if (controller.hasClients) {
        _scrollOffsets[sessionId] = controller.offset;
      }
      controller.removeListener(onScroll);
      prevMaxExtent.value = null;
    };
  }, [sessionId]);

  void scrollToBottom() {
    // Clear any streaming scroll lock when user explicitly scrolls to bottom.
    savedScrollOffset.value = null;
    if (isScrolledUpRef.value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.animateTo(
          0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Saves the current scroll offset while the user is scrolled up during
  /// streaming. Returns true if the lock was saved (user was scrolled up).
  bool lockScrollDuringStreaming() {
    if (!isScrolledUpRef.value) return false;
    if (!controller.hasClients) return false;
    savedScrollOffset.value = controller.offset;
    // Schedule a post-frame check to restore offset if the list was rebuilt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      final locked = savedScrollOffset.value;
      if (locked == null) return; // lock was released
      if (controller.offset != locked) {
        controller.jumpTo(locked);
      }
    });
    return true;
  }

  /// Releases the scroll lock and clears the saved offset.
  void unlockScroll() {
    savedScrollOffset.value = null;
  }

  return (
    controller: controller,
    isScrolledUp: isScrolledUp.value,
    scrollToBottom: scrollToBottom,
    lockScrollDuringStreaming: lockScrollDuringStreaming,
    unlockScroll: unlockScroll,
  );
}
