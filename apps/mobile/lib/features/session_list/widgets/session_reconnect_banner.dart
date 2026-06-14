import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class SessionReconnectBanner extends StatelessWidget {
  /// Number of reconnection attempts made so far.
  final int reconnectCount;

  const SessionReconnectBanner({super.key, this.reconnectCount = 0});

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
          Text(
            label,
            style: TextStyle(fontSize: 13, color: appColors.statusApproval),
          ),
        ],
      ),
    );
  }
}
