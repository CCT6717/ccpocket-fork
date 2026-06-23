import 'package:ccpocket/theme/app_theme.dart';
import 'package:ccpocket/theme/markdown_style.dart';
import 'package:ccpocket/widgets/cached_markdown_body.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

const _markdownWithCodeBlock = 'Intro\n\n```dart\nfinal value = 42;\n```';

Widget _wrapWithTheme({
  required ThemeData theme,
  required int parentTick,
  required Set<String> suffixes,
  required bool selectable,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Theme(
      data: theme,
      child: Material(
        child: CachedMarkdownBody(
          data: _markdownWithCodeBlock,
          knownFileSuffixes: suffixes,
          selectable: selectable,
        ),
      ),
    ),
  );
}

ThemeData _baseTheme() => AppTheme.darkTheme;

ThemeData _themeWithBodyLargeFontSize(double fontSize) {
  final theme = _baseTheme();
  return theme.copyWith(
    textTheme: theme.textTheme.copyWith(
      bodyLarge: theme.textTheme.bodyLarge?.copyWith(fontSize: fontSize),
    ),
  );
}

ThemeData _themeWithCodeBorder(Color color) {
  final theme = _baseTheme();
  final appColors = theme.extension<AppColors>()!;
  return theme.copyWith(
    extensions: <ThemeExtension<dynamic>>[
      appColors.copyWith(codeBorder: color),
    ],
  );
}

void main() {
  group('CachedMarkdownBody subtree caching', () {
    tearDown(markdownPerformanceProbe.reset);

    testWidgets('reuses cached markdown subtree for identical render input', (
      tester,
    ) async {
      markdownPerformanceProbe.reset();

      // Reuse the same ThemeData instance so Theme.InheritedWidget does not
      // notify dependents between pumps — isolates cache behaviour from
      // inherited-widget rebuild noise.
      final theme = _baseTheme();

      await tester.pumpWidget(
        _wrapWithTheme(
          theme: theme,
          parentTick: 0,
          suffixes: const {'lib/main.dart'},
          selectable: true,
        ),
      );

      expect(markdownPerformanceProbe.codeBlockBuilds, 1);

      await tester.pumpWidget(
        _wrapWithTheme(
          theme: theme,
          parentTick: 1,
          suffixes: const {'lib/main.dart'},
          selectable: true,
        ),
      );

      expect(markdownPerformanceProbe.codeBlockBuilds, 1);
    });

    testWidgets(
      'does not change render key for non-render-affecting theme changes',
      (tester) async {
        markdownPerformanceProbe.reset();

        await tester.pumpWidget(
          _wrapWithTheme(
            theme: _themeWithBodyLargeFontSize(18),
            parentTick: 0,
            suffixes: const {'lib/main.dart'},
            selectable: true,
          ),
        );

        expect(markdownPerformanceProbe.codeBlockBuilds, 1);
        final initialKey = tester
            .widget<MarkdownBody>(find.byType(MarkdownBody))
            .key;

        await tester.pumpWidget(
          _wrapWithTheme(
            theme: _themeWithBodyLargeFontSize(26),
            parentTick: 1,
            suffixes: const {'lib/main.dart'},
            selectable: true,
          ),
        );

        // Render key (MarkdownBody key) should be unchanged because
        // bodyLarge.fontSize is not part of _themeSignature.
        // codeBlockBuilds may increase because Theme notifies dependents
        // on identity change — that's expected inherited-widget behaviour.
        final updatedKey = tester
            .widget<MarkdownBody>(find.byType(MarkdownBody))
            .key;
        expect(updatedKey, equals(initialKey));
      },
    );

    testWidgets('rebuilds markdown subtree when render-affecting input changes', (
      tester,
    ) async {
      markdownPerformanceProbe.reset();

      await tester.pumpWidget(
        _wrapWithTheme(
          theme: _themeWithCodeBorder(const Color(0xFF3D3D3D)),
          parentTick: 0,
          suffixes: const {'lib/main.dart'},
          selectable: true,
        ),
      );

      expect(markdownPerformanceProbe.codeBlockBuilds, 1);
      final initialKey = tester
          .widget<MarkdownBody>(find.byType(MarkdownBody))
          .key;

      await tester.pumpWidget(
        _wrapWithTheme(
          theme: _themeWithCodeBorder(const Color(0xFF00BCD4)),
          parentTick: 1,
          suffixes: const {'lib/main.dart'},
          selectable: true,
        ),
      );

      final updatedKey = tester
          .widget<MarkdownBody>(find.byType(MarkdownBody))
          .key;
      expect(updatedKey, isNot(equals(initialKey)));
    });
  });
}
