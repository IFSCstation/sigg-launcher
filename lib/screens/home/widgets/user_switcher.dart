import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:sigg_launcher/app_controller.dart';
import 'package:sigg_launcher/app_widget.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_users.dart';
import 'package:sigg_launcher/services/page_nav_controller.dart';

void showUserSwitcher(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder(
      opaque: true,
      pageBuilder: (context, animation, secondaryAnimation) =>
          const _UserSwitcherPage(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    ),
  );
}

const double _itemWidth = 140;

class _UserSwitcherPage extends StatefulWidget {
  const _UserSwitcherPage();

  @override
  State<_UserSwitcherPage> createState() => _UserSwitcherPageState();
}

class _UserSwitcherPageState extends State<_UserSwitcherPage>
    with WidgetsBindingObserver {
  static const double _itemPadding = 12;
  static const double _avatarSize = 116;

  final ScrollController _scrollController = ScrollController();

  /// Horizontal D-pad focus: one entry per profile plus the "Novo perfil"
  /// circle at the end.
  final PageNavController _nav = PageNavController(axis: Axis.horizontal);

  late final List<GlobalKey> _itemKeys = List.generate(
    AppController.instance.users.length + 1,
    (_) => GlobalKey(),
  );

  /// Shared highlight ring, measured like the home header indicator so it
  /// slides between entries instead of fading each one in/out.
  final GlobalKey _stackKey = GlobalKey();
  Rect? _ringRect;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PageFocusHub.instance.push(_nav);
    _nav
      ..onActivate = _activateFocused
      ..addListener(_onNavChanged);
    _nav.setCount(_itemKeys.length);
    // Park the cursor on the profile in use, like the initial centering below
    // (focus() is a silent no-op at index 0, so that path still runs).
    final currentIndex = AppController.instance.users.indexWhere(
      (u) => identical(u, AppController.instance.currentUser),
    );
    _nav.focus(currentIndex < 0 ? 0 : currentIndex);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centerCurrentProfile(),
    );
    _scheduleRingRecalc();
  }

  @override
  void didChangeMetrics() {
    _scheduleRingRecalc();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PageFocusHub.instance.pop(_nav);
    _nav
      ..removeListener(_onNavChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleRingRecalc() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recalcRing();
    });
  }

  /// Measures the focused entry relative to the scrolling content (not the
  /// viewport), so the ring travels with the row while it auto-centers.
  void _recalcRing() {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;
    final index = _nav.index;
    if (index < 0 || index >= _itemKeys.length) return;
    final itemBox =
        _itemKeys[index].currentContext?.findRenderObject() as RenderBox?;
    if (itemBox == null || !itemBox.attached) return;

    final topLeft = itemBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final rect = Rect.fromLTWH(
      topLeft.dx + _itemPadding,
      topLeft.dy,
      _avatarSize,
      _avatarSize,
    );
    if (rect == _ringRect) return;
    setState(() => _ringRect = rect);
  }

  Widget _buildRing() {
    final rect = _ringRect;
    if (rect == null) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }
    return AnimatedPositioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2.5),
        ),
      ),
    );
  }

  void _onNavChanged() {
    if (!mounted) return;
    setState(() {});
    _scheduleRingRecalc();
    final index = _nav.index;
    if (index < 0 || index >= _itemKeys.length) return;
    // Defer until the rebuilt row has laid out the focused circle; calling
    // ensureVisible synchronously can hit an unlaid-out RenderBox.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _itemKeys[index].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  void _activateFocused() {
    final users = AppController.instance.users;
    final index = _nav.index;
    if (index >= 0 && index < users.length) {
      _selectProfile(users[index]);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('A criação de perfis chega em breve.'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  void _selectProfile(UserProfile user) {
    AppController.instance.switchUser(user);
    Navigator.of(context).pop();
  }

  /// Mouse taps move the D-pad cursor too, so clicking and navigating share
  /// the same focus (matching the other D-pad-navigable pages). Tapping the
  /// profile already in use stays a no-op, as before.
  void _onProfileTap(int index) {
    _nav.focus(index);
    final user = AppController.instance.users[index];
    if (!identical(user, AppController.instance.currentUser)) {
      _selectProfile(user);
    }
  }

  void _centerCurrentProfile() {
    if (!mounted || !_scrollController.hasClients) return;
    final users = AppController.instance.users;
    final index = users.indexWhere(
      (u) => identical(u, AppController.instance.currentUser),
    );
    if (index < 0) return;
    // The row is padded by (viewport - item) / 2 on both sides, so every
    // entry's centered offset is simply `index * _itemWidth` — including the
    // first and last ones.
    _scrollController.jumpTo(
      (index * _itemWidth).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final users = AppController.instance.users;

    return Scaffold(
      // Submenus share the home shell's neutral backdrop (theme
      // scaffoldBackgroundColor), not the green-tinted surface colors.
      backgroundColor: kScreenBackground,
      // Hardware focus is inert on this route: PageFocusHub owns the keyboard
      // (arrows/Enter) and the gamepad bridge the D-pad, and leaving the
      // profile InkWells focusable would let Enter natively activate one on
      // top of the hub confirm — switching twice and popping Home as well.
      body: ExcludeFocus(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: 'Back',
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Icon(Icons.sports_esports, size: 56, color: colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Quem está jogando?',
                textAlign: TextAlign.center,
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Selecione um perfil para continuar',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              // Side padding of half a viewport minus one item lets the first
              // and last entries reach the exact screen center instead of
              // stopping at the scroll edges; every offset then equals
              // `index * _itemWidth`.
              LayoutBuilder(
                builder: (context, constraints) {
                  final side = math.max(
                    0.0,
                    (constraints.maxWidth - _itemWidth) / 2,
                  );
                  return SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: Stack(
                      key: _stackKey,
                      clipBehavior: Clip.none,
                      children: [
                        Row(
                          children: [
                            SizedBox(width: side),
                            for (var i = 0; i < users.length; i++)
                              SizedBox(
                                key: _itemKeys[i],
                                width: _itemWidth,
                                child: _ProfileCircle(
                                  user: users[i],
                                  onTap: () => _onProfileTap(i),
                                ),
                              ),
                            SizedBox(
                              key: _itemKeys[users.length],
                              width: _itemWidth,
                              child: _AddUserCircle(
                                onTap: () {
                                  _nav.focus(users.length);
                                  _activateFocused();
                                },
                              ),
                            ),
                            SizedBox(width: side),
                          ],
                        ),
                        _buildRing(),
                      ],
                    ),
                  );
                },
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileCircle extends StatelessWidget {
  const _ProfileCircle({required this.user, required this.onTap});

  final UserProfile user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isCurrent = identical(user, AppController.instance.currentUser);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 116,
              height: 116,
              padding: const EdgeInsets.all(4),
              child: CircleAvatar(
                radius: 54,
                backgroundColor: user.avatarColor,
                backgroundImage: user.avatarPath != null
                    ? FileImage(File(user.avatarPath!))
                    : null,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (user.avatarPath == null)
                      Icon(user.icon, size: 48, color: Colors.white),
                    if (isCurrent)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primary,
                            border: Border.all(
                              color: colorScheme.surface,
                              width: 3,
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              user.nickname,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isCurrent ? 'Perfil atual' : 'Jogador',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: isCurrent
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w400,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddUserCircle extends StatelessWidget {
  const _AddUserCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colorScheme.surfaceContainerHighest,
                border: Border.all(color: colorScheme.outlineVariant, width: 2),
              ),
              child: Icon(
                Icons.add,
                size: 44,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Novo perfil',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Criar',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
