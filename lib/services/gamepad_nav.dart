import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:gamepads/gamepads.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/nav_controller.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';

enum _NavDir { up, down, left, right }

/// How the `xyz.luan/gamepads` plugin behind the current binary numbers its
/// raw `key` values. `gamepads` documents `key` only as "a
/// platform-dependant identifier", and the two Linux plugins disagree:
///
/// - [evdev]: pub's GTK `gamepads_linux` reports raw `/dev/input/js*` indices,
///   which only the package's controller-database mapping can interpret
///   (including the per-VID/PID DS4 override in [registerSonyMappingOverrides]).
/// - [sdl3]: ivi-homescreen's `gamepads_linux` (v2.0) reports SDL3 controller
///   indices, already abstracted by SDL's own database, so they must NOT go
///   through the evdev-shaped mapping (README: "Consume `Gamepads.events` and
///   map the indices directly").
enum GamepadKeyLayout { evdev, sdl3 }

/// Overrides [detectGamepadKeyLayout]: `SIGG_GAMEPAD_LAYOUT=sdl3|evdev`.
const _kLayoutEnvVar = 'SIGG_GAMEPAD_LAYOUT';

/// Picks the raw key numbering used by the running embedder.
///
/// ivi-homescreen runs the app inside its `homescreen` binary, whose gamepads
/// plugin speaks SDL3; the GTK runner is `sigg_launcher` and loads pub's
/// evdev-based plugin. `SIGG_GAMEPAD_LAYOUT` wins when set, so a renamed
/// embedder can still be pointed at the right contract.
GamepadKeyLayout detectGamepadKeyLayout({
  Map<String, String>? environment,
  String? executablePath,
}) {
  final override = (environment ?? Platform.environment)[_kLayoutEnvVar]
      ?.trim()
      .toLowerCase();
  if (override == 'sdl3') return GamepadKeyLayout.sdl3;
  if (override == 'evdev') return GamepadKeyLayout.evdev;

  final executable = executablePath ?? Platform.resolvedExecutable;
  return executable.split('/').last == 'homescreen'
      ? GamepadKeyLayout.sdl3
      : GamepadKeyLayout.evdev;
}

/// SDL3 `SDL_GamepadButton` indices the launcher acts on. The d-pad is
/// 11..14 by contract, not four buttons of a hat axis.
const Map<int, GamepadButton> _sdl3Buttons = {
  0: GamepadButton.a, // SOUTH
  1: GamepadButton.b, // EAST
  6: GamepadButton.start, // START
  11: GamepadButton.dpadUp,
  12: GamepadButton.dpadDown,
  13: GamepadButton.dpadLeft,
  14: GamepadButton.dpadRight,
};

/// SDL3 `SDL_GamepadAxis` indices 0..5.
const Map<int, GamepadAxis> _sdl3Axes = {
  0: GamepadAxis.leftStickX,
  1: GamepadAxis.leftStickY,
  2: GamepadAxis.rightStickX,
  3: GamepadAxis.rightStickY,
  4: GamepadAxis.leftTrigger,
  5: GamepadAxis.rightTrigger,
};

/// Converts one raw SDL3 event into the package's normalized shape, so every
/// decision downstream (zones, activation, auto-repeat) stays in one place.
///
/// SDL hands Sint16 across unscaled: sticks are bipolar and triggers are
/// rescaled to 0..32767 by SDL before the plugin sees them. SDL reports stick
/// Y as negative-up, while [NormalizedGamepadEvent] uses positive-up.
List<NormalizedGamepadEvent> _mapSdl3Event(GamepadEvent event) {
  final index = int.tryParse(event.key);
  if (index == null) return const [];

  if (event.type == KeyType.button) {
    final button = _sdl3Buttons[index];
    if (button == null) return const [];
    return [
      NormalizedGamepadEvent(
        gamepadId: event.gamepadId,
        timestamp: event.timestamp,
        value: event.value != 0 ? 1.0 : 0.0,
        button: button,
        rawEvent: event,
      ),
    ];
  }

  final axis = _sdl3Axes[index];
  if (axis == null) return const [];
  final isTrigger =
      axis == GamepadAxis.leftTrigger || axis == GamepadAxis.rightTrigger;
  final isStickY =
      axis == GamepadAxis.leftStickY || axis == GamepadAxis.rightStickY;
  var value = event.value / 32767.0;
  if (isTrigger) {
    value = value.clamp(0.0, 1.0).toDouble();
  } else {
    value = value.clamp(-1.0, 1.0).toDouble();
    if (isStickY) value = -value;
  }
  return [
    NormalizedGamepadEvent(
      gamepadId: event.gamepadId,
      timestamp: event.timestamp,
      value: value,
      axis: axis,
      rawEvent: event,
    ),
  ];
}

class _HeldDir {
  final _NavDir dir;
  final Timer timer;

  _HeldDir(this.dir, this.timer);
}

class LauncherRouteObserver extends NavigatorObserver {
  LauncherRouteObserver._();

  static final LauncherRouteObserver instance = LauncherRouteObserver._();

  Route<dynamic>? _homeRoute;
  int _aboveHome = 0;

  bool get isHomeTop => _homeRoute != null && _aboveHome == 0;

  void maybeGoBack() {
    navigator?.maybePop();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_homeRoute == null &&
        route.settings.name == Navigator.defaultRouteName) {
      _homeRoute = route;
      _aboveHome = 0;
      return;
    }
    if (route == _homeRoute) {
      _aboveHome = 0;
      return;
    }
    if (_homeRoute != null) {
      _aboveHome++;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == _homeRoute) {
      _aboveHome = 0;
      return;
    }
    if (previousRoute == _homeRoute) {
      _aboveHome = 0;
      return;
    }
    if (_homeRoute != null && _aboveHome > 0) {
      _aboveHome--;
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route == _homeRoute) {
      _aboveHome = 0;
      return;
    }
    if (previousRoute == _homeRoute) {
      _aboveHome = 0;
      return;
    }
    if (_homeRoute != null && _aboveHome > 0) {
      _aboveHome--;
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute == _homeRoute) {
      _aboveHome = 0;
      return;
    }
    if (oldRoute == _homeRoute && newRoute != _homeRoute) {
      _aboveHome = 1;
    }
  }

  @visibleForTesting
  void debugReset() {
    _homeRoute = null;
    _aboveHome = 0;
  }
}

class GamepadNavBridge {
  GamepadNavBridge({
    Stream<GamepadEvent>? events,
    GamepadKeyLayout? layout,
    NavController? controller,
    LauncherRouteObserver? routeObserver,
    PageFocusHub? focusHub,
    GameRunState? runState,
    this.initialRepeatDelay = const Duration(milliseconds: 350),
    this.repeatedRepeatDelay = const Duration(milliseconds: 120),
  }) : _controller = controller ?? NavController.instance,
       _routeObserver = routeObserver ?? LauncherRouteObserver.instance,
       _focusHub = focusHub ?? PageFocusHub.instance,
       _runState = runState ?? GameRunState.instance,
       _layout = layout ?? detectGamepadKeyLayout() {
    _subscription = _decode(events ?? Gamepads.events).listen(_onEvent);
    _runState.addListener(_onRunStateChanged);
  }

  final NavController _controller;
  final LauncherRouteObserver _routeObserver;
  final PageFocusHub _focusHub;
  final GameRunState _runState;
  final GamepadKeyLayout _layout;
  final Duration initialRepeatDelay;
  final Duration repeatedRepeatDelay;
  final Map<_NavDir, _HeldDir> _held = {};

  late final StreamSubscription<NormalizedGamepadEvent> _subscription;

  /// Turns raw platform events into normalized ones, per [GamepadKeyLayout].
  ///
  /// Raw [Gamepads.events] are the source of truth for both backends; only
  /// the evdev numbering needs the package's controller-database mapping.
  Stream<NormalizedGamepadEvent> _decode(Stream<GamepadEvent> events) {
    switch (_layout) {
      case GamepadKeyLayout.evdev:
        // Reuse the shared normalizer so a caller-supplied override (and the
        // per-VID/PID DS4 mapping loaded at startup) is honored.
        var normalizer = Gamepads.normalizer;
        if (normalizer == null) {
          normalizer = GamepadNormalizer();
          Gamepads.normalizer = normalizer;
        }
        return events.transform(normalizer.transformer);
      case GamepadKeyLayout.sdl3:
        return events.expand(_mapSdl3Event);
    }
  }

  void _onEvent(NormalizedGamepadEvent event) {
    if (_runState.running) return;
    if (_routeObserver.isHomeTop) {
      _handleHomeEvent(event);
      return;
    }
    // A pushed page owns input while it has a controller registered (trophy
    // lists); everything else only reacts to B so back always works.
    final page = _focusHub.active;
    if (page != null) {
      _handlePageEvent(event, page);
    } else if (event.button == GamepadButton.b && event.value != 0) {
      _routeObserver.maybeGoBack();
    }
  }

  void _handlePageEvent(NormalizedGamepadEvent event, PageNavController page) {
    final button = event.button;
    if (button != null) {
      switch (button) {
        case GamepadButton.dpadUp:
          _setHeld(_NavDir.up, event.value != 0);
          break;
        case GamepadButton.dpadDown:
          _setHeld(_NavDir.down, event.value != 0);
          break;
        case GamepadButton.dpadLeft:
          _setHeld(_NavDir.left, event.value != 0);
          break;
        case GamepadButton.dpadRight:
          _setHeld(_NavDir.right, event.value != 0);
          break;
        case GamepadButton.a:
        case GamepadButton.start:
          if (event.value != 0) {
            // Cancel held repeats so opening a page can't auto-scroll it.
            _cancelHeld();
            page.activate();
          }
          break;
        case GamepadButton.b:
          if (event.value != 0) {
            _cancelHeld();
            _routeObserver.maybeGoBack();
          }
          break;
        default:
          break;
      }
      return;
    }
    switch (event.axis) {
      case GamepadAxis.leftStickX:
        if (event.value > 0.5) {
          _setHeld(_NavDir.left, false);
          _setHeld(_NavDir.right, true);
        } else if (event.value < -0.5) {
          _setHeld(_NavDir.right, false);
          _setHeld(_NavDir.left, true);
        } else {
          _setHeld(_NavDir.left, false);
          _setHeld(_NavDir.right, false);
        }
        break;
      case GamepadAxis.leftStickY:
        if (event.value < -0.5) {
          _setHeld(_NavDir.up, false);
          _setHeld(_NavDir.down, true);
        } else if (event.value > 0.5) {
          _setHeld(_NavDir.down, false);
          _setHeld(_NavDir.up, true);
        } else {
          _setHeld(_NavDir.up, false);
          _setHeld(_NavDir.down, false);
        }
        break;
      default:
        break;
    }
  }

  void _handleHomeEvent(NormalizedGamepadEvent event) {
    final button = event.button;
    if (button != null) {
      switch (button) {
        case GamepadButton.dpadUp:
          _setHeld(_NavDir.up, event.value != 0);
          break;
        case GamepadButton.dpadDown:
          _setHeld(_NavDir.down, event.value != 0);
          break;
        case GamepadButton.dpadLeft:
          _setHeld(_NavDir.left, event.value != 0);
          break;
        case GamepadButton.dpadRight:
          _setHeld(_NavDir.right, event.value != 0);
          break;
        case GamepadButton.a:
        case GamepadButton.start:
          if (event.value != 0) {
            _controller.activate();
          }
          break;
        default:
          break;
      }
      return;
    }
    switch (event.axis) {
      case GamepadAxis.leftStickX:
        if (event.value > 0.5) {
          _setHeld(_NavDir.left, false);
          _setHeld(_NavDir.right, true);
        } else if (event.value < -0.5) {
          _setHeld(_NavDir.right, false);
          _setHeld(_NavDir.left, true);
        } else {
          _setHeld(_NavDir.left, false);
          _setHeld(_NavDir.right, false);
        }
        break;
      case GamepadAxis.leftStickY:
        if (event.value < -0.5) {
          _setHeld(_NavDir.up, false);
          _setHeld(_NavDir.down, true);
        } else if (event.value > 0.5) {
          _setHeld(_NavDir.down, false);
          _setHeld(_NavDir.up, true);
        } else {
          _setHeld(_NavDir.up, false);
          _setHeld(_NavDir.down, false);
        }
        break;
      default:
        break;
    }
  }

  void _setHeld(_NavDir dir, bool held) {
    final existing = _held[dir];
    if (held) {
      if (existing != null) return;
      _move(dir);
      _held[dir] = _HeldDir(dir, Timer(initialRepeatDelay, () => _repeat(dir)));
    } else if (existing != null) {
      existing.timer.cancel();
      _held.remove(dir);
    }
  }

  void _repeat(_NavDir dir) {
    if (!_held.containsKey(dir)) return;
    _move(dir);
    _held[dir] = _HeldDir(dir, Timer(repeatedRepeatDelay, () => _repeat(dir)));
  }

  void _move(_NavDir dir) {
    // Re-routed on every tick so a held repeat keeps following the active
    // target across page pushes/pops.
    if (_routeObserver.isHomeTop) {
      _moveHome(dir);
      return;
    }
    final page = _focusHub.active;
    if (page != null) _movePage(dir, page);
  }

  void _moveHome(_NavDir dir) {
    switch (dir) {
      case _NavDir.up:
        _controller.moveUp();
        break;
      case _NavDir.down:
        _controller.moveDown();
        break;
      case _NavDir.left:
        _controller.moveLeft();
        break;
      case _NavDir.right:
        _controller.moveRight();
        break;
    }
  }

  void _movePage(_NavDir dir, PageNavController page) {
    switch (dir) {
      case _NavDir.up:
        page.moveUp();
        break;
      case _NavDir.down:
        page.moveDown();
        break;
      case _NavDir.left:
        page.moveLeft();
        break;
      case _NavDir.right:
        page.moveRight();
        break;
    }
  }

  void _onRunStateChanged() {
    if (_runState.running) {
      _cancelHeld();
    }
  }

  void _cancelHeld() {
    for (final held in _held.values) {
      held.timer.cancel();
    }
    _held.clear();
  }

  void dispose() {
    _subscription.cancel();
    _runState.removeListener(_onRunStateChanged);
    _cancelHeld();
  }
}

class GamepadStatus extends ChangeNotifier {
  GamepadStatus({Future<List<String>> Function()? namesLoader, this.events})
    : _namesLoader = namesLoader ?? _loadNames;

  static final GamepadStatus instance = GamepadStatus();

  static Future<List<String>> _loadNames() async {
    final gamepads = await Gamepads.list();
    return [for (final gamepad in gamepads) gamepad.name];
  }

  final Future<List<String>> Function() _namesLoader;
  final Stream<GamepadEvent>? events;
  final Set<String> _knownIds = {};

  List<String> _names = const [];
  StreamSubscription<GamepadEvent>? _eventSub;
  Timer? _pollTimer;
  bool _started = false;

  List<String> get names => _names;

  bool get isConnected => _names.isNotEmpty;

  String get namesLabel => _names.join(', ');

  void start() {
    if (_started) return;
    _started = true;
    _eventSub = (events ?? Gamepads.events).listen(_onEvent);
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    refresh();
  }

  Future<void> _onEvent(GamepadEvent event) async {
    if (_knownIds.add(event.gamepadId)) {
      await refresh();
    }
  }

  Future<void> refresh() async {
    final updated = await _namesLoader();
    _names = updated;
    notifyListeners();
  }

  void stop() {
    _eventSub?.cancel();
    _eventSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _started = false;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  @visibleForTesting
  void debugReset() {
    _names = const [];
    _knownIds.clear();
    stop();
  }
}

void registerSonyMappingOverrides() {
  ControllerDatabase.loadSdlMappings(
    '050000004c050000cc09000000810000,PS4 Controller,'
    'a:b0,b:b1,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,'
    'guide:b10,leftshoulder:b4,leftstick:b11,lefttrigger:a2,leftx:a0,lefty:a1,'
    'rightshoulder:b5,rightstick:b12,righttrigger:a5,rightx:a3,righty:a4,'
    'start:b9,x:b3,y:b2,platform:Linux,',
    platform: GamepadPlatform.linux,
  );
}
