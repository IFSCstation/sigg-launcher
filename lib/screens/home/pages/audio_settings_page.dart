import 'package:flutter/material.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/services/audio_preferences.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';

/// Audio preferences that directly control the launcher's BGM and UI tick.
/// Up/Down focuses a control, Left/Right adjusts it, and A/Enter toggles
/// switches. Mouse interaction remains available through the native controls.
class AudioSettingsPage extends StatefulWidget {
  const AudioSettingsPage({super.key});

  @override
  State<AudioSettingsPage> createState() => _AudioSettingsPageState();
}

class _AudioSettingsPageState extends State<AudioSettingsPage> {
  final AudioPreferences _preferences = AudioPreferences.instance;
  final _AudioPageNavController _nav = _AudioPageNavController();
  final List<GlobalKey> _rowKeys = List.generate(4, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    PageFocusHub.instance.push(_nav);
    _nav
      ..setCount(_rowKeys.length)
      ..onActivate = _activateFocused
      ..onAdjust = _adjustFocused
      ..addListener(_onNavChanged);
    _preferences.addListener(_onPreferencesChanged);
  }

  @override
  void dispose() {
    PageFocusHub.instance.pop(_nav);
    _nav
      ..removeListener(_onNavChanged)
      ..onActivate = null
      ..onAdjust = null
      ..dispose();
    _preferences.removeListener(_onPreferencesChanged);
    super.dispose();
  }

  void _onPreferencesChanged() {
    if (mounted) setState(() {});
  }

  void _onNavChanged() {
    if (!mounted) return;
    setState(() {});
    final index = _nav.index;
    if (index < 0 || index >= _rowKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _rowKeys[index].currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        alignment: 0.1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _activateFocused() {
    final focusedIndex = _nav.index;
    // Volume rows deliberately have no confirm action. Only the switch rows
    // respond to A/Enter; otherwise Slider's semantics could be mistaken for
    // the adjacent toggle during keyboard/gamepad activation.
    if (focusedIndex == 0) {
      _preferences.setMusicEnabled(!_preferences.musicEnabled);
    } else if (focusedIndex == 2) {
      _preferences.setUiSoundsEnabled(!_preferences.uiSoundsEnabled);
    }
  }

  void _adjustFocused(int direction) {
    switch (_nav.index) {
      case 0:
        _preferences.setMusicEnabled(!_preferences.musicEnabled);
        break;
      case 1:
        _preferences.setMusicVolume(
          _stepVolume(_preferences.musicVolume, direction),
        );
        break;
      case 2:
        _preferences.setUiSoundsEnabled(!_preferences.uiSoundsEnabled);
        break;
      case 3:
        _preferences.setUiSoundsVolume(
          _stepVolume(_preferences.uiSoundsVolume, direction),
        );
        break;
    }
  }

  double _stepVolume(double value, int direction) =>
      ((value * 100).round() + direction).clamp(0, 100) / 100;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: kScreenBackground,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Audio'),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, kToolbarHeight + 8, 16, 24),
        children: [
          _panel(
            0,
            ExcludeFocus(
              child: SwitchListTile(
                value: _preferences.musicEnabled,
                selected: _nav.index == 0,
                title: const Text('Background music'),
                subtitle: const Text('Play the selected game’s music track'),
                secondary: const Icon(Icons.music_note),
                onChanged: (enabled) {
                  _nav.focus(0);
                  _preferences.setMusicEnabled(enabled);
                },
              ),
            ),
          ),
          _panel(
            1,
            _VolumeControl(
              label: 'Music volume',
              icon: Icons.volume_down,
              value: _preferences.musicVolume,
              onFocus: () => _nav.focus(1),
              onChanged: _preferences.setMusicVolume,
              textTheme: textTheme,
            ),
          ),
          _panel(
            2,
            ExcludeFocus(
              child: SwitchListTile(
                value: _preferences.uiSoundsEnabled,
                selected: _nav.index == 2,
                title: const Text('Interface sounds'),
                subtitle: const Text('Play the selection movement sound'),
                secondary: const Icon(Icons.graphic_eq),
                onChanged: (enabled) {
                  _nav.focus(2);
                  _preferences.setUiSoundsEnabled(enabled);
                },
              ),
            ),
          ),
          _panel(
            3,
            _VolumeControl(
              label: 'Interface sound volume',
              icon: Icons.volume_up,
              value: _preferences.uiSoundsVolume,
              onFocus: () => _nav.focus(3),
              onChanged: _preferences.setUiSoundsVolume,
              textTheme: textTheme,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Use Up/Down to focus controls, Left/Right to adjust values, '
              'and A/Enter to toggle switches. Changes last for this session.',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(int index, Widget child) {
    final colorScheme = Theme.of(context).colorScheme;
    final focused = _nav.index == index;
    return Padding(
      key: _rowKeys[index],
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: focused
              ? colorScheme.primary.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: focused
                ? colorScheme.primary.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.08),
            width: focused ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    required this.label,
    required this.icon,
    required this.value,
    required this.onFocus,
    required this.onChanged,
    required this.textTheme,
  });

  final String label;
  final IconData icon;
  final double value;
  final VoidCallback onFocus;
  final ValueChanged<double> onChanged;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text('${(value * 100).round()}%'),
            ],
          ),
          ExcludeFocus(
            // The page controller owns arrow keys for a focused slider row;
            // excluding Slider's own focus prevents competing keyboard input.
            child: Slider(
              value: value,
              min: 0,
              max: 1,
              divisions: 100,
              label: '${(value * 100).round()}%',
              onChangeStart: (_) => onFocus(),
              onChanged: (next) {
                onFocus();
                onChanged(next);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioPageNavController extends PageNavController {
  _AudioPageNavController() : super(axis: Axis.vertical);

  void Function(int direction)? onAdjust;

  @override
  void moveLeft() => onAdjust?.call(-1);

  @override
  void moveRight() => onAdjust?.call(1);
}
