import 'package:flutter/material.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final PageNavController _nav = PageNavController(axis: Axis.vertical);
  final List<GlobalKey> _itemKeys = List.generate(
    _settings.length,
    (_) => GlobalKey(),
  );

  @override
  void initState() {
    super.initState();
    PageFocusHub.instance.push(_nav);
    _nav.setCount(_settings.length);
    _nav
      ..onActivate = _activateFocused
      ..addListener(_onNavChanged);
  }

  @override
  void dispose() {
    PageFocusHub.instance.pop(_nav);
    _nav
      ..removeListener(_onNavChanged)
      ..dispose();
    super.dispose();
  }

  void _onNavChanged() {
    if (!mounted) return;
    setState(() {});
    final index = _nav.index;
    if (index < 0 || index >= _itemKeys.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _itemKeys[index].currentContext;
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
    if (_nav.index < 0 || _nav.index >= _settings.length) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Esta opção estará disponível em breve.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: kScreenBackground,
      // Submenus keep their transparent, no-back header (B/Escape exits).
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Settings'),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.only(
          top: kToolbarHeight,
          left: 16,
          right: 16,
          bottom: 24,
        ),
        children: [
          for (var i = 0; i < _settings.length; i++)
            Padding(
              key: _itemKeys[i],
              padding: const EdgeInsets.only(bottom: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                decoration: BoxDecoration(
                  color: _nav.index == i
                      ? colorScheme.primary.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _nav.index == i
                        ? colorScheme.primary.withValues(alpha: 0.85)
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    selected: _nav.index == i,
                    selectedColor: colorScheme.primary,
                    leading: Icon(_settings[i].icon),
                    title: Text(_settings[i].title),
                    subtitle: Text(_settings[i].subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onTap: () {
                      _nav.focus(i);
                      _activateFocused();
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

const _settings = <_SettingsEntry>[
  _SettingsEntry(
    icon: Icons.person_outline,
    title: 'Account',
    subtitle: 'Profile, nickname and avatar',
  ),
  _SettingsEntry(
    icon: Icons.notifications_outlined,
    title: 'Notifications',
    subtitle: 'Alerts, sounds and badges',
  ),
  _SettingsEntry(
    icon: Icons.palette_outlined,
    title: 'Appearance',
    subtitle: 'Theme and accent color',
  ),
  _SettingsEntry(
    icon: Icons.volume_up_outlined,
    title: 'Audio',
    subtitle: 'Music and sound effects',
  ),
  _SettingsEntry(
    icon: Icons.info_outline,
    title: 'About',
    subtitle: 'Version and licenses',
  ),
];

class _SettingsEntry {
  const _SettingsEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}
