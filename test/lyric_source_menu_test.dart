import 'package:dan_player/page/now_playing_page/component/lyric_source_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

void main() {
  testWidgets('lyric source menu uses aligned semantic icons and a tooltip',
      (tester) async {
    var choseDefault = false;
    var choseOnline = false;
    var choseLocal = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: LyricSourceMenuButton(
              enabled: true,
              showLocal: true,
              isLocal: true,
              onChooseDefault: () => choseDefault = true,
              onOnline: () => choseOnline = true,
              onLocal: () => choseLocal = true,
            ),
          ),
        ),
      ),
    );

    final trigger = tester.widget<IconButton>(
      find.byKey(const ValueKey('lyric-source-menu-button')),
    );
    expect(trigger.tooltip, '选择歌词来源');
    await tester.tap(find.byKey(const ValueKey('lyric-source-menu-button')));
    await tester.pumpAndSettle();

    final defaultItem = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('lyric-source-choose-default')),
    );
    final onlineItem = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('lyric-source-online')),
    );
    final localItem = tester.widget<MenuItemButton>(
      find.byKey(const ValueKey('lyric-source-local-menu-item')),
    );
    expect((defaultItem.leadingIcon! as Icon).icon, Symbols.search);
    expect((onlineItem.leadingIcon! as Icon).icon, Symbols.cloud);
    expect((localItem.leadingIcon! as Icon).icon, Symbols.folder);
    expect(defaultItem.trailingIcon, isNull);
    expect(onlineItem.trailingIcon, isNull);
    expect((localItem.trailingIcon! as Icon).icon, Symbols.check);

    await tester.tap(find.byKey(const ValueKey('lyric-source-online')));
    await tester.pumpAndSettle();
    expect(choseOnline, isTrue);
    expect(choseDefault, isFalse);
    expect(choseLocal, isFalse);
    expect(tester.takeException(), isNull);
  });
}
