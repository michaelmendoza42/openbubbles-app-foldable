import 'dart:math';

import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/app/wrappers/titlebar_wrapper.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Refreshes a [TabletModeWrapper] after its nested navigator changes routes.
class TabletPaneNavigatorObserver extends NavigatorObserver {
  void _refresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      eventDispatcher.emit('tablet-pane-navigation', null);
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _refresh();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _refresh();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _refresh();
}

class TabletModeWrapper extends StatefulWidget {
  final Widget left;
  final Widget right;
  final double initialRatio;
  final double dividerWidth;
  final double minRatio;
  final double maxRatio;
  final bool allowResize;
  final double? minWidthLeft;
  final double? maxWidthLeft;
  final double dragMargin;

  /// Chooses whether [right] should be the visible single pane outside split
  /// layout. Both panes remain mounted so nested navigation and drafts survive
  /// a landscape-to-portrait transition.
  final bool Function() showRightInSinglePane;

  /// Optional shells let widget tests exercise pane transitions without a
  /// desktop title-bar host.
  final Widget Function(Widget child)? titleBarBuilder;
  final bool Function(BuildContext context)? splitLayoutBuilder;

  const TabletModeWrapper({super.key,
    required this.left,
    required this.right,
    this.initialRatio = 0.5,
    this.allowResize = true,
    this.dividerWidth = 3.0,
    this.minRatio = 0,
    this.maxRatio = 0,
    this.minWidthLeft,
    this.maxWidthLeft,
    this.dragMargin = 5,
    this.showRightInSinglePane = _neverShowRight,
    this.titleBarBuilder,
    this.splitLayoutBuilder,
  }) : assert(initialRatio >= 0),
        assert(initialRatio <= 1);

  static bool _neverShowRight() => false;

  @override
  State<TabletModeWrapper> createState() => _TabletModeWrapperState();
}

class _TabletModeWrapperState extends OptimizedState<TabletModeWrapper> {
  //from 0-1
  late final RxDouble _ratio;
  double? _maxWidth;

  get _width1 => max(min(_ratio * _maxWidth!, widget.maxWidthLeft ?? double.infinity), widget.minWidthLeft ?? double.negativeInfinity);

  get _width2 => _maxWidth! - _width1;

  Widget _withTitleBar({required Widget child}) =>
      widget.titleBarBuilder?.call(child) ?? TitleBarWrapper(child: child);

  @override
  void initState() {
    super.initState();
    _ratio = RxDouble((ss.prefs.getDouble('splitRatio') ?? widget.initialRatio).clamp(widget.minRatio, widget.maxRatio));
    eventDispatcher.stream.listen((event) {
      if (event.item1 == 'split-refresh') {
        _ratio.value = ss.prefs.getDouble('splitRatio') ?? _ratio.value;
        setState(() {});
      } else if (event.item1 == 'override-split') {
        _ratio.value = event.item2;
        setState(() {});
      } else if ((event.item1 == 'update-highlight' || event.item1 == 'tablet-pane-navigation') && mounted) {
        setState(() {});
      }
    });
    debounce<double>(_ratio, (val) async {
      await ss.prefs.setDouble('splitRatio', val);
      eventDispatcher.emit('split-refresh', null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, BoxConstraints constraints) {
        final splitLayout = widget.splitLayoutBuilder?.call(context) ?? showAltLayout;
        final rightVisible = !splitLayout && widget.showRightInSinglePane();
        _maxWidth = constraints.maxWidth - (splitLayout ? widget.dividerWidth : 0);

        return DeferredPointerHandler(
          child: _withTitleBar(
            child: SizedBox(
              width: constraints.maxWidth,
              child: Obx(() => Stack(
                children: <Widget>[
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 0,
                    width: splitLayout ? _width1 : constraints.maxWidth,
                    child: Offstage(
                      offstage: !splitLayout && rightVisible,
                      child: ExcludeFocus(
                        excluding: !splitLayout && rightVisible,
                        child: widget.left,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: splitLayout ? _width2 : constraints.maxWidth,
                    child: Offstage(
                      offstage: !splitLayout && !rightVisible,
                      child: ExcludeFocus(
                        excluding: !splitLayout && !rightVisible,
                        child: widget.right,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: _width1,
                    width: widget.dividerWidth,
                    child: Offstage(
                      offstage: !splitLayout,
                      child: widget.allowResize ? Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            top: 0,
                            left: -widget.dragMargin,
                            right: -widget.dragMargin,
                            bottom: 0,
                            child: DeferPointer(child: MouseRegion(
                              cursor: SystemMouseCursors.resizeLeftRight,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                child: Center(
                                  child: Container(
                                    color: context.theme.colorScheme.properSurface,
                                    width: widget.dividerWidth,
                                  ),
                                ),
                                onPanUpdate: (DragUpdateDetails details) {
                                  _ratio.value = (_ratio.value + (details.delta.dx / _maxWidth!)).clamp(widget.minRatio, widget.maxRatio);
                                  ns.listener.refresh();
                                },
                              ),
                            ))
                          )
                        ],
                      ) : Container(color: context.theme.colorScheme.properSurface),
                    ),
                  ),
                ],
              )),
            ),
          ),
        );
      },
    );
  }
}