import 'package:bluebubbles/app/wrappers/titlebar_wrapper.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/helpers/ui/tablet_layout_policy.dart';
import 'package:bluebubbles/helpers/types/helpers/misc_helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

NavigatorService ns = Get.isRegistered<NavigatorService>() ? Get.find<NavigatorService>() : Get.put(NavigatorService());

/// Handles navigation for the app
class NavigatorService extends GetxService {
  final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
  final Rxn listener = Rxn();
  /// width of left side of split screen view
  double? _widthChatListLeft;
  /// width of right side of split screen view
  double? _widthChatListRight;
  /// width of settings right side split screen
  double? _widthSettings;

  set maxWidthLeft(double w) => _widthChatListLeft = w;
  set maxWidthRight(double w) => _widthChatListRight = w;
  set maxWidthSettings(double w) => _widthSettings = w;

  /// Returns widthChatListLeft if in tablet mode, and 0 otherwise
  double widthChatListLeft(BuildContext context) => isTabletMode(context) ? _widthChatListLeft ?? 0 : 0;

  bool isTabletMode(BuildContext context) => usesTabletSplitLayout(
        tabletMode: ss.settings.tabletMode.value,
        isPhone: context.isPhone,
        width: context.width,
        height: context.height,
        isBubble: ls.isBubble,
        isDesktop: kIsDesktop,
        isWeb: kIsWeb,
      );

  /// grab the available screen width, returning the split screen width if applicable
  /// this should *always* be used in place of context.width or similar
  double width(BuildContext context) {
    if (Navigator.of(context).widget.key?.toString().contains("Getx nested key: 1") ?? false) {
      return _widthChatListLeft ?? context.width;
    } else if (Navigator.of(context).widget.key?.toString().contains("Getx nested key: 2") ?? false) {
      return _widthChatListRight ?? context.width;
    } else if (Navigator.of(context).widget.key?.toString().contains("Getx nested key: 3") ?? false) {
      return _widthSettings ?? context.width;
    }
    return context.width;
  }

  double ratio(BuildContext context) => (_widthChatListLeft ?? context.width) / context.width;
  
  bool isAvatarOnly(BuildContext context) => (kIsDesktop || kIsWeb) && isTabletMode(context) && (_widthChatListLeft ?? context.width) < 300;

  /// Nested panes stay mounted in portrait so route ownership remains stable
  /// while the visual presentation switches between one and two panes.
  bool _hasPane(int id) => Get.keys[id]?.currentState != null;

  /// Push a new route onto the chat list right side navigator
  void push(BuildContext context, Widget widget) {
    if (_hasPane(2)) {
      Get.to(() => widget, transition: Transition.rightToLeft, id: 2);
    } else {
      Navigator.of(context).push(ThemeSwitcher.buildPageRoute(
        builder: (BuildContext context) => TitleBarWrapper(child: widget),
      ));
    }
  }

  /// Push a new route onto the chat list left side navigator
  Future<void> pushLeft(BuildContext context, Widget widget) async {
    if (_hasPane(1)) {
      await Get.to(() => widget, transition: Transition.leftToRight, id: 1);
    } else {
      await Navigator.of(context).push(ThemeSwitcher.buildPageRoute(
        builder: (BuildContext context) => TitleBarWrapper(child: widget),
      ));
    }
  }

  /// Push a new route onto the settings navigator
  Future<dynamic> pushSettings(BuildContext context, Widget widget, {Bindings? binding}) async {
    if (_hasPane(3)) {
      return await Get.to(() => widget, transition: Transition.rightToLeft, id: 3, binding: binding);
    } else {
      binding?.dependencies();
      return await Navigator.of(context).push(ThemeSwitcher.buildPageRoute(
        builder: (BuildContext context) => TitleBarWrapper(child: widget),
      ));
    }
  }

  /// Push a new route, popping all previous routes, on the chat list right side navigator
  Future<void> pushAndRemoveUntil(BuildContext context, Widget widget, bool Function(Route) predicate,
      {bool closeActiveChat = true, PageRoute? customRoute}) async {
    if (_hasPane(2)) {
      if (closeActiveChat && cm.activeChat != null) {
        Logger.debug("Closing active chat: ${cm.activeChat!.chat.guid}", tag: "NavigatorService");
        cvc(cm.activeChat!.chat).close();
      }

      await Get.offUntil(
          GetPageRoute(
            page: () => widget,
            transition: Transition.noTransition,
            transitionDuration: Duration.zero,
          ),
          predicate,
          id: 2);
    } else {
      await Navigator.of(context).pushAndRemoveUntil(customRoute ?? ThemeSwitcher.buildPageRoute(
        builder: (BuildContext context) => TitleBarWrapper(child: widget),
      ), predicate);
    }
  }

  /// Push a new route, popping all previous routes, on the settings navigator
  void pushAndRemoveSettingsUntil(BuildContext context, Widget widget, bool Function(Route) predicate,
      {Bindings? binding}) {
    if (_hasPane(3)) {
      // The right pane owns settings routes in both orientations.
      Get.offUntil(GetPageRoute(
        page: () => widget,
        binding: binding,
        transition: Transition.noTransition,
        transitionDuration: Duration.zero,
      ), predicate, id: 3);
    } else {
      binding?.dependencies();
      // only push here because we don't want to remove underlying routes when in portrait
      Navigator.of(context).push(ThemeSwitcher.buildPageRoute(
        builder: (BuildContext context) => TitleBarWrapper(child: widget),
      ));
    }
  }

  /// Pops the currently active nested pane, regardless of whether it is
  /// presented as a split pane or the single portrait pane.
  ///
  /// Returns whether a route was handled so production [PopScope]s can fall
  /// back to the root navigator or system Back exactly once.
  Future<bool> backConversationView(BuildContext context, {bool allowRootFallback = true}) async {
    for (final id in [3, 2, 1]) {
      final pane = Get.keys[id]?.currentState;
      // Global pane keys can remain mounted beneath a newer root route.
      if (pane == null || !(ModalRoute.of(pane.context)?.isCurrent ?? false)) continue;
      final hadRoute = pane.canPop();
      // maybePop also gives an initial route's PopScope a chance to dismiss
      // selection/attachment UI. Direct pop bypasses that local Back contract.
      if (await pane.maybePop()) {
        if (id == 2 && hadRoute && pane.mounted && !pane.canPop()) {
          if (cm.activeChat != null) cvc(cm.activeChat!.chat).close();
          eventDispatcher.emit('update-highlight', null);
        }
        return true;
      }
    }
    // A root PopScope calls this with fallback disabled to avoid recursively
    // dispatching the same rejected system Back to itself.
    if (allowRootFallback && context.mounted) {
      return Navigator.of(context, rootNavigator: true).maybePop();
    }
    return false;
  }

  void closeSettings(BuildContext context) {
    if (_hasPane(3)) {
      Get.until((route) => route.isFirst, id: 3);
      Get.back(closeOverlays: true);
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// Remember to call `await cm.setAllInactive()` after calling this function
  void closeAllConversationView(BuildContext context) {
    if (_hasPane(2)) {
      Get.until((route) {
        return route.settings.name == "initial";
      }, id: 2);
    }
    eventDispatcher.emit("update-highlight", null);
  }

  void backSettings(BuildContext context, {dynamic result, bool closeOverlays = false}) {
    if (_hasPane(3)) {
      Get.back(result: result, closeOverlays: closeOverlays, id: 3);
    } else {
      Get.back(result: result, closeOverlays: closeOverlays);
    }
  }
}
