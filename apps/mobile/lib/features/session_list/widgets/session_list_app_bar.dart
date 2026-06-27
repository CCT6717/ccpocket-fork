import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../router/app_router.dart';
import '../../../services/app_update_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/workspace_pane_chrome.dart';

/// Floating SliverAppBar for the session list screen.
///
/// Hides on scroll-down and snaps back on scroll-up (Material 3
/// enterAlways behaviour).
class SessionListSliverAppBar extends StatelessWidget {
  final VoidCallback onTitleTap;
  final VoidCallback onDisconnect;
  final bool forceElevated;
  final double? toolbarHeight;
  final String? bridgeLabel;

  /// Listenable bridge RTT in ms for connection quality display.
  final ValueListenable<int>? rttMs;

  const SessionListSliverAppBar({
    super.key,
    required this.onTitleTap,
    required this.onDisconnect,
    this.forceElevated = false,
    this.toolbarHeight,
    this.bridgeLabel,
    this.rttMs,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return SliverAppBar(
      floating: true,
      snap: true,
      forceElevated: forceElevated,
      toolbarHeight: toolbarHeight ?? kToolbarHeight,
      title: GestureDetector(
        onTap: onTitleTap,
        child: _SessionListTitle(
          title: l.appTitle,
          subtitle: bridgeLabel,
          rttMs: rttMs,
        ),
      ),
      actions: [
        IconButton(
          key: const ValueKey('settings_button'),
          icon: Badge(
            isLabelVisible: AppUpdateService.instance.cachedUpdate != null,
            smallSize: 8,
            child: const Icon(Icons.settings),
          ),
          onPressed: () => context.router.navigate(SettingsRoute()),
          tooltip: l.settings,
        ),
        IconButton(
          key: const ValueKey('gallery_button'),
          icon: const Icon(Icons.collections),
          onPressed: () => context.router.navigate(GalleryRoute()),
          tooltip: l.gallery,
        ),
        IconButton(
          key: const ValueKey('disconnect_button'),
          icon: const Icon(Icons.link_off),
          onPressed: onDisconnect,
          tooltip: l.disconnect,
        ),
      ],
    );
  }
}

class SessionListPaneHeader extends StatelessWidget {
  final VoidCallback onTitleTap;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenGallery;
  final VoidCallback? onDisconnect;
  final VoidCallback? onTogglePaneVisibility;
  final String? bridgeLabel;

  /// Listenable bridge RTT in ms for connection quality display.
  final ValueListenable<int>? rttMs;

  const SessionListPaneHeader({
    super.key,
    required this.onTitleTap,
    required this.onOpenSettings,
    this.onOpenGallery,
    this.onDisconnect,
    this.onTogglePaneVisibility,
    this.bridgeLabel,
    this.rttMs,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final openGallery = onOpenGallery;
    final disconnect = onDisconnect;
    final togglePaneVisibility = onTogglePaneVisibility;
    final chrome = resolveWorkspacePaneChrome(
      platform: Theme.of(context).platform,
      isAdaptiveWorkspace: true,
      isLeftPaneVisible: true,
      slot: WorkspacePaneSlot.left,
    );
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700);
    final actionGap = chrome.useMacOSAdaptiveChrome ? 8.0 : 0.0;

    return SizedBox(
      height: chrome.toolbarHeight,
      child: Padding(
        padding: chrome.headerPadding(),
        child: Row(
          children: [
            if (!chrome.useMacOSAdaptiveChrome)
              Expanded(
                child: GestureDetector(
                  onTap: onTitleTap,
                  child: _SessionListTitle(
                    key: const ValueKey('session_list_pane_title'),
                    title: l.appTitle,
                    subtitle: bridgeLabel,
                    rttMs: rttMs,
                    titleStyle: titleStyle,
                  ),
                ),
              )
            else
              const Expanded(
                child: MacOSWindowDragHandle(child: SizedBox.expand()),
              ),
            _PaneHeaderActionButton(
              key: const ValueKey('settings_button'),
              tooltip: l.settings,
              onPressed: onOpenSettings,
              icon: Badge(
                isLabelVisible: AppUpdateService.instance.cachedUpdate != null,
                smallSize: 8,
                child: const Icon(Icons.settings),
              ),
              compact: chrome.useMacOSAdaptiveChrome,
            ),
            if (openGallery != null ||
                disconnect != null ||
                togglePaneVisibility != null)
              SizedBox(width: actionGap),
            if (openGallery != null)
              _PaneHeaderActionButton(
                key: const ValueKey('gallery_button'),
                tooltip: l.gallery,
                onPressed: openGallery,
                icon: const Icon(Icons.collections_outlined),
                compact: chrome.useMacOSAdaptiveChrome,
              ),
            if (openGallery != null &&
                (disconnect != null || togglePaneVisibility != null))
              SizedBox(width: actionGap),
            if (disconnect != null)
              _PaneHeaderActionButton(
                key: const ValueKey('disconnect_button'),
                tooltip: l.disconnect,
                onPressed: disconnect,
                icon: const Icon(Icons.link_off),
                compact: chrome.useMacOSAdaptiveChrome,
              ),
            if (disconnect != null && togglePaneVisibility != null)
              SizedBox(width: actionGap),
            if (togglePaneVisibility != null)
              _PaneHeaderActionButton(
                key: const ValueKey('collapse_left_pane_button'),
                tooltip: l.hideSessions,
                onPressed: togglePaneVisibility,
                icon: const Icon(Icons.chevron_left),
                compact: chrome.useMacOSAdaptiveChrome,
              ),
          ],
        ),
      ),
    );
  }
}

class _SessionListTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final TextStyle? titleStyle;

  /// Listenable bridge RTT in ms (0 = no data yet).
  final ValueListenable<int>? rttMs;

  const _SessionListTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.titleStyle,
    this.rttMs,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final theme = Theme.of(context);
    final defaultTitleStyle = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final appColors = theme.extension<AppColors>();

    final rttWidget = rttMs != null
        ? ValueListenableBuilder<int>(
            valueListenable: rttMs!,
            builder: (context, rtt, _) {
              if (rtt <= 0) return const SizedBox.shrink();
              final color = rtt < 50
                  ? (appColors?.statusOnline ?? Colors.green)
                  : rtt < 150
                  ? (appColors?.statusApproval ?? Colors.orange)
                  : (appColors?.errorBubbleBorder ?? Colors.red);
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '${rtt}ms',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              );
            },
          )
        : const SizedBox.shrink();

    if (subtitle == null || subtitle.isEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle ?? defaultTitleStyle,
            ),
          ),
          rttWidget,
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle ?? defaultTitleStyle,
        ),
        const SizedBox(height: 1),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
            rttWidget,
          ],
        ),
      ],
    );
  }
}

class _PaneHeaderActionButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback onPressed;
  final Widget icon;
  final bool compact;

  const _PaneHeaderActionButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      style: compact
          ? resolveWorkspacePaneChrome(
              platform: Theme.of(context).platform,
              isAdaptiveWorkspace: true,
              isLeftPaneVisible: true,
              slot: WorkspacePaneSlot.left,
            ).compactButtonStyle()
          : null,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      tooltip: tooltip,
      icon: icon,
    );
  }
}
