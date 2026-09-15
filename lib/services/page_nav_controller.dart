import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Axis;

import 'ui_sounds.dart';

/// D-pad focus for a list on a pushed page (trophies index / per-game trophy
/// row). Pages own one instance, push it onto [PageFocusHub] while visible,
/// and [activate] on A / Start. [axis] selects which directions move the
/// focus; moves on the other axis are no-ops so a single bridge handler can
/// feed every page. A selection tick plays whenever focus actually moves.
class PageNavController extends ChangeNotifier {
  PageNavController({this.axis = Axis.vertical});

  final Axis axis;

  int _index = 0;
  int _count = 0;

  /// Invoked by [activate] (A / Start) on the currently focused entry.
  void Function()? onActivate;

  int get index => _index;

  int get count => _count;

  void setCount(int count) {
    final clamped = count < 0 ? 0 : count;
    if (clamped == _count) return;
    _count = clamped;
    if (_index >= _count) {
      _index = _count > 0 ? _count - 1 : 0;
    }
    notifyListeners();
  }

  void moveUp() {
    if (axis != Axis.vertical || _index <= 0) return;
    _index--;
    _playTick();
    notifyListeners();
  }

  void moveDown() {
    if (axis != Axis.vertical || _count == 0 || _index >= _count - 1) return;
    _index++;
    _playTick();
    notifyListeners();
  }

  void moveLeft() {
    if (axis != Axis.horizontal || _index <= 0) return;
    _index--;
    _playTick();
    notifyListeners();
  }

  void moveRight() {
    if (axis != Axis.horizontal || _count == 0 || _index >= _count - 1) return;
    _index++;
    _playTick();
    notifyListeners();
  }

  void activate() => onActivate?.call();

  void _playTick() {
    UiSounds.instance.selectionChanged();
  }

  @visibleForTesting
  void debugReset() {
    _index = 0;
    _count = 0;
    onActivate = null;
    notifyListeners();
  }
}

/// Tracks which pushed page currently owns gamepad input. Pages push their
/// [PageNavController] in `initState` and pop it on `dispose`; because routes
/// initialize in push order, the last entry is always the topmost page.
class PageFocusHub {
  PageFocusHub._();

  static final PageFocusHub instance = PageFocusHub._();

  final List<PageNavController> _stack = [];

  PageNavController? get active => _stack.isEmpty ? null : _stack.last;

  void push(PageNavController controller) => _stack.add(controller);

  void pop(PageNavController controller) => _stack.remove(controller);

  @visibleForTesting
  void debugReset() => _stack.clear();
}
