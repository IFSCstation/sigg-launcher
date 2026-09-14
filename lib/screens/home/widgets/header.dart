import 'package:flutter/material.dart';
import 'package:sigg_launcher/screens/home/widgets/clock.dart';
import 'package:sigg_launcher/screens/home/widgets/user_widget.dart';
import 'package:sigg_launcher/screens/home/widgets/user_switcher.dart';
import 'package:sigg_launcher/services/gamepad_nav.dart';
import 'package:sigg_launcher/services/nav_controller.dart';

class GamepadIndicator extends StatelessWidget {
  const GamepadIndicator({super.key, this.status});

  final GamepadStatus? status;

  @override
  Widget build(BuildContext context) {
    final status = this.status ?? GamepadStatus.instance;
    return ListenableBuilder(
      listenable: status,
      builder: (context, child) {
        final connected = status.isConnected;
        return Tooltip(
          message: connected
              ? (status.namesLabel.isEmpty
                  ? 'Controle conectado'
                  : status.namesLabel)
              : '',
          child: Icon(
            Icons.sports_esports,
            size: 24,
            color: connected ? Colors.white : Colors.white24,
          ),
        );
      },
    );
  }
}

class Header extends StatefulWidget {
  const new({
    super.key,
    this.active = true,
    this.focusedIndex = 0,
    this.onStoreTap,
    this.onTrophiesTap,
    this.onSettingsTap,
  });

  /// Whether the header is the active navigation zone.
  final bool active;

  /// Index (0 = profile, 1 = store, 2 = trophies, 3 = settings) shown with a
  /// focus ring when [active].
  final int focusedIndex;

  final VoidCallback? onStoreTap;
  final VoidCallback? onTrophiesTap;
  final VoidCallback? onSettingsTap;

  @override
  State<Header> createState() => _HeaderState();
}

class _HeaderState extends State<Header> with WidgetsBindingObserver {
  final GlobalKey _stackKey = GlobalKey();
  final Map<int, GlobalKey> _itemKeys = {
    0: GlobalKey(),
    1: GlobalKey(),
    2: GlobalKey(),
    3: GlobalKey(),
  };

  Rect? _indicatorRect;
  bool _animateIndicator = false;

  @override
  void initState() {
    super.initState();
    _scheduleRecalc();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant Header oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusedIndex != widget.focusedIndex) {
      _scheduleRecalc();
    }
  }

  @override
  void didChangeMetrics() {
    _scheduleRecalc();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _scheduleRecalc() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recalcIndicator();
    });
  }

  void _recalcIndicator() {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null) return;
    final itemContext = _itemKeys[widget.focusedIndex]?.currentContext;
    final itemBox = itemContext?.findRenderObject() as RenderBox?;
    if (itemBox == null || !itemBox.attached) return;

    final topLeft = itemBox.localToGlobal(Offset.zero, ancestor: stackBox);
    final inflated = (topLeft & itemBox.size).inflate(4);
    final rect = Rect.fromLTRB(
      inflated.left.clamp(0.0, stackBox.size.width),
      inflated.top.clamp(0.0, stackBox.size.height),
      inflated.right.clamp(0.0, stackBox.size.width),
      inflated.bottom.clamp(0.0, stackBox.size.height),
    );
    if (rect == _indicatorRect) return;
    setState(() {
      _indicatorRect = rect;
      _animateIndicator = true;
    });
  }

  Widget _buildIndicator() {
    final rect = _indicatorRect;
    if (rect == null) {
      return const Positioned(left: 0, top: 0, child: SizedBox.shrink());
    }

    final indicator = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white, width: 2.5),
      ),
    );

    if (!_animateIndicator) {
      return Positioned(
        left: rect.left,
        top: rect.top,
        width: rect.width,
        height: rect.height,
        child: indicator,
      );
    }

    return AnimatedPositioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      child: indicator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.active ? 1.0 : 0.45,
      duration: const Duration(milliseconds: 200),
      child: RepaintBoundary(
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Stack(
          key: _stackKey,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ExcludeFocus(
                child: Row(
                  children: [
                    UserWidget(
                      avatarKey: _itemKeys[0],
                      onTap: () {
                        NavController.instance.focusHeaderItem(0);
                        showUserSwitcher(context);
                      },
                    ),
                    const Spacer(),

                    IconButton(
                      key: _itemKeys[1],
                      onPressed: widget.onStoreTap,
                      icon: const Icon(Icons.local_mall, size: 32),
                      tooltip: "IFSCstation Store",
                    ),
                    IconButton(
                      key: _itemKeys[2],
                      onPressed: widget.onTrophiesTap,
                      icon: const Icon(Icons.emoji_events, size: 32),
                      tooltip: "Troféus",
                    ),
                    IconButton(
                      key: _itemKeys[3],
                      onPressed: widget.onSettingsTap,
                      icon: const Icon(Icons.settings, size: 32),
                      tooltip: "Configurações",
                    ),

                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: GamepadIndicator(),
                    ),
                    const Clock(),
                  ],
                ),
              ),
            ),
            _buildIndicator(),
          ],
        ),
        ),
      ),
    );
  }
}
