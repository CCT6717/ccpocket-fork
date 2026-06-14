import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';

class GalleryEmptyState extends StatelessWidget {
  final bool isSessionMode;

  const GalleryEmptyState({super.key, required this.isSessionMode});

  @override
  Widget build(BuildContext context) {
    final appColors = Theme.of(context).extension<AppColors>()!;
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primary.withValues(alpha: 0.15),
                    colorScheme.primary.withValues(alpha: 0.04),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.collections_outlined,
                size: 44,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context).noScreenshotsYet,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isSessionMode
                  ? AppLocalizations.of(context).screenshotButtonHint
                  : AppLocalizations.of(context).screenshotsWillAppearHere,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: appColors.subtleText),
            ),
          ],
        ),
      ),
    );
  }
}
