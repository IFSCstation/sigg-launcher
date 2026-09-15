import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sigg_launcher/app_controller.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_users.dart';

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

class _UserSwitcherPageState extends State<_UserSwitcherPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centerCurrentProfile(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _centerCurrentProfile() {
    if (!mounted || !_scrollController.hasClients) return;
    final users = AppController.instance.users;
    final index = users.indexWhere(
      (u) => identical(u, AppController.instance.currentUser),
    );
    if (index < 0) return;
    final viewport = _scrollController.position.viewportDimension;
    final target = 8 + (index * _itemWidth) + (_itemWidth / 2) - (viewport / 2);
    _scrollController.jumpTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            radius: 1.4,
            center: const Alignment(0, -0.7),
            colors: [colorScheme.surfaceContainerHighest, colorScheme.surface],
          ),
        ),
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
              SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    for (final user in AppController.instance.users)
                      SizedBox(
                        width: _itemWidth,
                        child: _ProfileCircle(user: user),
                      ),
                    SizedBox(width: _itemWidth, child: const _AddUserCircle()),
                    const SizedBox(width: 8),
                  ],
                ),
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
  const _ProfileCircle({required this.user});

  final UserProfile user;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isCurrent = identical(user, AppController.instance.currentUser);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: isCurrent
            ? null
            : () {
                AppController.instance.switchUser(user);
                Navigator.of(context).pop();
              },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              width: 116,
              height: 116,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.55),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ]
                    : const [],
              ),
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
  const _AddUserCircle();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
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
    );
  }
}
