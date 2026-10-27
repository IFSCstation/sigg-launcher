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

  /// Moves focus to an entry programmatically without the selection tick
  /// (mouse taps stay silent, matching `NavController.focusHeaderItem`).
  void focus(int index) {
    if (index == _index) return;
    _index = _count == 0 ? 0 : index.clamp(0, _count - 1);
    notifyListeners();
  }

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
  int _suspendDepth = 0;

  /// Null while suspended ([suspend]) so dialogs with real text input steal
  /// arrows/Enter back from the launcher's global keyboard handler (which
  /// consumes keys whenever a controller is active) and from the gamepad
  /// bridge (which would otherwise keep driving the page behind the dialog).
  PageNavController? get active =>
      _suspendDepth > 0 || _stack.isEmpty ? null : _stack.last;

  void push(PageNavController controller) => _stack.add(controller);

  void pop(PageNavController controller) => _stack.remove(controller);

  /// Suspends input routing (ref-counted for nesting). Pair with [resume]
  /// around `showDialog` calls on navigable pages.
  void suspend() => _suspendDepth++;

  void resume() {
    if (_suspendDepth > 0) _suspendDepth--;
  }

  @visibleForTesting
  void debugReset() {
    _stack.clear();
    _suspendDepth = 0;
  }
}

/// 2D focus grid for pages laid out as rows of cards (the store): each row
/// holds a variable number of columns. Up/Down move across rows (column
/// clamped to the target row), Left/Right move within a row — XMB-style, no
/// wrap. [activate] (A / Start / Enter) fires the focused item's action.
/// [focusCell] moves the position programmatically (mouse taps), silently.
class GridPageNavController extends PageNavController {
  GridPageNavController() : super(axis: Axis.vertical);

  List<int> _rowLengths = const [];
  int _row = 0;
  int _col = 0;

  int get row => _row;

  int get col => _col;

  /// True when no rows are navigable (loading/empty/error states).
  bool get isEmpty => _rowLengths.every((length) => length == 0);

  /// Replaces the grid dimensions, clamping the current position into the
  /// new grid (used when the catalog reloads).
  void setRows(List<int> lengths) {
    _rowLengths = [for (final length in lengths) length < 0 ? 0 : length];
    if (_row >= _rowLengths.length) {
      _row = _rowLengths.isEmpty ? 0 : _rowLengths.length - 1;
    }
    _clampCol();
    notifyListeners();
  }

  /// Moves focus to a card programmatically without the selection tick
  /// (mouse-only paths stay silent, matching `NavController.focusHeaderItem`
  /// on the home shell). Named [focusCell] (not [focus]) to avoid clashing
  /// with the 1D base-class method it can't override.
  void focusCell(int row, int col) {
    if (row < 0 || row >= _rowLengths.length) return;
    final clampedCol = _rowLengths[row] == 0
        ? 0
        : col.clamp(0, _rowLengths[row] - 1);
    if (row == _row && clampedCol == _col) return;
    _row = row;
    _col = clampedCol;
    notifyListeners();
  }

  @override
  void moveUp() {
    if (_row <= 0) return;
    _row--;
    _clampCol();
    _playTick();
    notifyListeners();
  }

  @override
  void moveDown() {
    if (_row >= _rowLengths.length - 1) return;
    _row++;
    _clampCol();
    _playTick();
    notifyListeners();
  }

  @override
  void moveLeft() {
    if (_col <= 0) return;
    _col--;
    _playTick();
    notifyListeners();
  }

  @override
  void moveRight() {
    if (_row >= _rowLengths.length || _col >= _rowLengths[_row] - 1) return;
    _col++;
    _playTick();
    notifyListeners();
  }

  void _clampCol() {
    final length = _row >= 0 && _row < _rowLengths.length
        ? _rowLengths[_row]
        : 0;
    _col = length == 0 ? 0 : _col.clamp(0, length - 1);
  }

  @override
  @visibleForTesting
  void debugReset() {
    super.debugReset();
    _rowLengths = const [];
    _row = 0;
    _col = 0;
  }
}
