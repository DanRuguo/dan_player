import 'package:dan_player/component/app_action_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  test('repeated actions have one Material Symbols mapping', () {
    expect(AppActionGlyph.reorder.icon, Symbols.drag_handle);
    expect(AppActionGlyph.play.icon, Symbols.play_circle);
    expect(AppActionGlyph.moreVertical.icon, Symbols.more_vert);
    expect(AppActionGlyph.moreHorizontal.icon, Symbols.more_horiz);
    expect(
      AppActionGlyph.values.map((glyph) => glyph.icon).toSet(),
      hasLength(AppActionGlyph.values.length),
    );
  });

  testWidgets('shared icon action is themed, animated and a 44px target',
      (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: AppIconActionButton(
            tooltip: '更多',
            glyph: AppActionGlyph.moreVertical,
            onPressed: () {},
          ),
        ),
      ),
    ));

    final finder = find.byType(AppIconActionButton);
    expect(tester.getSize(finder), const Size.square(44));
    expect(find.byTooltip('更多'), findsOneWidget);
    expect(find.byIcon(Symbols.more_vert), findsOneWidget);
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.constraints,
        const BoxConstraints.tightFor(width: 44, height: 44));
    expect(button.style!.tapTargetSize, MaterialTapTargetSize.shrinkWrap);
    expect(button.style!.foregroundColor!.resolve(<WidgetState>{}),
        scheme.primary);
    expect(
      button.style!.backgroundColor!
          .resolve(<WidgetState>{WidgetState.hovered}),
      scheme.surfaceContainerHighest.withValues(alpha: .48),
    );
    expect(button.style!.animationDuration, isNot(Duration.zero));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selected play action keeps a paired filled symbol',
      (tester) async {
    final scheme = ColorScheme.fromSeed(seedColor: Colors.orange);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: Scaffold(
        body: AppIconActionButton(
          tooltip: '播放歌单',
          glyph: AppActionGlyph.play,
          selected: true,
          onPressed: () {},
        ),
      ),
    ));
    final button = tester.widget<IconButton>(find.byType(IconButton));
    final icon = tester.widget<Icon>(find.byIcon(Symbols.play_circle));
    expect(icon.fill, 1);
    expect(button.style!.foregroundColor!.resolve(<WidgetState>{}),
        scheme.onSecondaryContainer);
    expect(button.style!.backgroundColor!.resolve(<WidgetState>{}),
        scheme.secondaryContainer);
  });
}
