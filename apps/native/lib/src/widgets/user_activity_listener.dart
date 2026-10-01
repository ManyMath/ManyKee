import 'package:flutter/widgets.dart';

/// Reports pointer and keyboard input anywhere below it via [onActivity].
///
/// Install it through `MaterialApp.builder`, above the Navigator, so input
/// inside dialogs and pushed routes counts too, not just the home route.
class UserActivityListener extends StatelessWidget {
  const UserActivityListener({
    super.key,
    required this.onActivity,
    required this.child,
  });

  final VoidCallback onActivity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onActivity(),
      onPointerMove: (_) => onActivity(),
      onPointerSignal: (_) => onActivity(),
      child: Focus(
        // Observes key events bubbling up from the focused widget; never
        // takes focus or joins traversal itself.
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, __) {
          onActivity();
          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }
}
