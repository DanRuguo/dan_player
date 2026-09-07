import 'package:dan_player/component/responsive_builder.dart';
import 'package:dan_player/component/app_entrance.dart';
import 'package:flutter/material.dart';
import 'package:dan_player/component/app_shape.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:desktop_lyric/ui_language.dart';

/// title, actions, body
///
/// 提供基本的响应式布局：
///
/// 小屏幕时，折叠第一个组件以外的其他组件。后两个放在同一行；
/// 若 action 总数大于 3，把第二个起倒数第三个为止的组件相继放在下面。
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.actions,
    this.responsiveActions,
    this.header,
    this.headerPadding = const EdgeInsets.all(16),
    required this.body,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  /// A compact, self-wrapping toolbar. Unlike the legacy actions list, it is
  /// never nested in another overflow menu and gains its own row on narrow
  /// windows or with large accessibility text.
  final Widget? responsiveActions;

  /// Optional identity layout for richer pages such as playlist artwork. Its
  /// own vertical viewport only scrolls when large text/short windows need it;
  /// the content list always retains space and an independent scroll position.
  final Widget? header;
  final EdgeInsetsGeometry headerPadding;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    UiLanguageScope.watch(context);
    final scheme = Theme.of(context).colorScheme;

    return ResponsiveBuilder(builder: (context, screenType) {
      List<Widget> rowChildren;

      if (actions.isEmpty) {
        rowChildren =
            subtitle == null ? [onlyTitle(scheme)] : [withSubtitle(scheme)];
      } else {
        switch (screenType) {
          case ScreenType.small:
            {
              final List<Widget> foldedRow1 = [];
              int count = 0;
              for (int i = actions.length - 1;
                  i > 0 && count < 2;
                  --i, ++count) {
                if (count == 1) foldedRow1.add(const SizedBox(width: 8.0));

                foldedRow1.add(actions[i]);
              }

              final List<Widget> foldedColumn = [];
              if (foldedRow1.isNotEmpty) {
                foldedColumn.add(Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: foldedRow1,
                ));
              }

              if (actions.length >= 4) {
                for (var i = actions.length - 1 - count; i > 0; --i) {
                  foldedColumn.add(actions[i]);
                }
              }

              const menuStyle = MenuStyle(
                shape: WidgetStatePropertyAll(
                  AppShape.control,
                ),
              );

              rowChildren = [
                subtitle == null ? onlyTitle(scheme) : withSubtitle(scheme),
                const SizedBox(width: 16.0),
                actions.first,
                if (foldedColumn.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 16.0),
                    child: MenuAnchor(
                      style: menuStyle,
                      menuChildren: foldedColumn,
                      builder: (_, controller, __) => IconButton.filledTonal(
                        style: IconButton.styleFrom(
                            foregroundColor: Theme.of(context)
                                .colorScheme
                                .onSecondaryContainer),
                        tooltip: ui("更多"),
                        onPressed: () {
                          controller.isOpen
                              ? controller.close()
                              : controller.open();
                        },
                        icon: const Icon(Symbols.more_vert),
                      ),
                    ),
                  ),
              ];
              break;
            }
          case ScreenType.medium:
          case ScreenType.large:
            {
              rowChildren = [
                subtitle == null ? onlyTitle(scheme) : withSubtitle(scheme),
                const SizedBox(width: 16.0),
                Wrap(spacing: 8.0, children: actions)
              ];
            }
        }
      }

      return AppEntranceScope(
        child: ColoredBox(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: LayoutBuilder(builder: (context, constraints) {
              final titleArea = Padding(
                padding: headerPadding,
                child: AppEntrance(
                  identity: ('page-header', title),
                  child: header ??
                      (responsiveActions == null
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: rowChildren,
                            )
                          : LayoutBuilder(builder: (context, constraints) {
                              final titleContent = subtitle == null
                                  ? _onlyTitleContent(scheme)
                                  : _withSubtitleContent(scheme);
                              final largeText =
                                  MediaQuery.textScalerOf(context).scale(14) >
                                      19;
                              if (constraints.maxWidth < 880 || largeText) {
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(children: [
                                      Expanded(child: titleContent)
                                    ]),
                                    const SizedBox(height: 12),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: responsiveActions,
                                    ),
                                  ],
                                );
                              }
                              return Row(
                                children: [
                                  // Localized identity text keeps its natural
                                  // width while scrolling toolbars receive the
                                  // otherwise unused middle of a wide header.
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                        maxWidth: constraints.maxWidth * .4),
                                    child: titleContent,
                                  ),
                                  const SizedBox(width: 20),
                                  Expanded(child: responsiveActions!),
                                ],
                              );
                            })),
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Keep the same viewport tree at every window width. A
                  // wrapped standard toolbar needs the same short-window
                  // budget as artwork headers, without remounting entrances
                  // or borrowing the content list's scroll controller.
                  if (constraints.hasBoundedHeight)
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxHeight: constraints.maxHeight * .6),
                      child: SingleChildScrollView(
                        key: const ValueKey('page-custom-header-scroll'),
                        primary: false,
                        child: titleArea,
                      ),
                    )
                  else
                    titleArea,
                  Expanded(child: body),
                ],
              );
            }),
          ),
        ),
      );
    });
  }

  Widget _onlyTitleContent(ColorScheme scheme) => Text(
        title,
        style: TextStyle(fontSize: 32.0, color: scheme.onSurface),
        overflow: TextOverflow.ellipsis,
      );

  Expanded onlyTitle(ColorScheme scheme) =>
      Expanded(child: _onlyTitleContent(scheme));

  Widget _withSubtitleContent(ColorScheme scheme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 28.0, color: scheme.onSurface),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 14.0, color: scheme.onSurface),
            overflow: TextOverflow.ellipsis,
          )
        ],
      );

  Expanded withSubtitle(ColorScheme scheme) =>
      Expanded(child: _withSubtitleContent(scheme));
}
