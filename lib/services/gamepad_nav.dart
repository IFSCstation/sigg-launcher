import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gamepads/gamepads.dart';
import 'package:sigg_launcher/services/game_run_state.dart';
import 'package:sigg_launcher/services/nav_controller.dart';

enum _NavDir { up, down, left, right }

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
    if (_homeRoute == null && route.settings.name == Navigator.defaultRouteName) {
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
    Stream<NormalizedGamepadEvent>? events,
    NavController? controller,
    LauncherRouteObserver? routeObserver,
    GameRunState? runState,
    this.initialRepeatDelay = const Duration(milliseconds: 350),
    this.repeatedRepeatDelay = const Duration(milliseconds: 120),
  })  : _controller = controller ?? NavController.instance,
        _routeObserver = routeObserver ?? LauncherRouteObserver.instance,
        _runState = runState ?? GameRunState.instance {
    _subscription = (events ?? Gamepads.normalizedEvents).listen(_onEvent);
    _runState.addListener(_onRunStateChanged);
  }

  final NavController _controller;
  final LauncherRouteObserver _routeObserver;
  final GameRunState _runState;
  final Duration initialRepeatDelay;
  final Duration repeatedRepeatDelay;
  final Map<_NavDir, _HeldDir> _held = {};

  late final StreamSubscription<NormalizedGamepadEvent> _subscription;

  void _onEvent(NormalizedGamepadEvent event) {
    if (_runState.running) return;
    if (_routeObserver.isHomeTop) {
      _handleHomeEvent(event);
    } else {
      if (event.button == GamepadButton.b && event.value != 0) {
        _routeObserver.maybeGoBack();
      }
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
      _held[dir] = _HeldDir(
        dir,
        Timer(initialRepeatDelay, () => _repeat(dir)),
      );
    } else if (existing != null) {
      existing.timer.cancel();
      _held.remove(dir);
    }
  }

  void _repeat(_NavDir dir) {
    if (!_held.containsKey(dir)) return;
    _move(dir);
    _held[dir] = _HeldDir(
      dir,
      Timer(repeatedRepeatDelay, () => _repeat(dir)),
    );
  }

  void _move(_NavDir dir) {
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
  GamepadStatus({
    Future<List<String>> Function()? namesLoader,
    this.events,
  }) : _namesLoader = namesLoader ?? _loadNames;

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