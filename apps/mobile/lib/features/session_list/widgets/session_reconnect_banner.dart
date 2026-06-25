import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class SessionReconnectBanner extends StatelessWidget {
  /// Number of reconnection attempts made so far.
  final int reconnectCount;
  final VoidCallback? onRetry;

  const SessionReconnectBanner({super.key, this.reconnectCount = 0, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final l = AppLocalizations.of(context);
    final label = reconnectCount > 0
        ? '${l.reconnecting} (attempt #$reconnectCount)'
        : l.reconnecting;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: appColors.approvalBar,
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: appColors.statusApproval,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: appColors.statusApproval),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 4),
            SizedBox(
              height: 28,
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: appColors.statusApproval,
                ),
                child: Text(
                  l.retry,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
