import 'package:flutter/material.dart';

class StorePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("IFSCstation Store"),
        // Convention: submenus have no back button (B-back / Escape).
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200,
          mainAxisExtent: 180,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {},
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      color: item.color.withValues(alpha: 0.25),
                      child: Icon(item.icon, size: 48, color: item.color),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          item.price,
                          style: TextStyle(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StoreItem {
  const _StoreItem(this.title, this.price, this.icon, this.color);

  final String title;
  final String price;
  final IconData icon;
  final Color color;
}

const _items = <_StoreItem>[
  _StoreItem(
    'Neon Racer',
    'R\$ 49,90',
    Icons.directions_car,
    Color(0xFFE91E63),
  ),
  _StoreItem('Mystic Grove', 'R\$ 79,90', Icons.forest, Color(0xFF4CAF50)),
  _StoreItem('Dungeon Crawl', 'R\$ 39,90', Icons.gavel, Color(0xFF8D6E63)),
  _StoreItem(
    'Stellar Drift',
    'R\$ 59,90',
    Icons.rocket_launch,
    Color(0xFF7C4DFF),
  ),
  _StoreItem('Gem Pack', 'R\$ 9,90', Icons.diamond, Color(0xFF00BCD4)),
  _StoreItem('Sky Bound', 'R\$ 69,90', Icons.air, Color(0xFF2196F3)),
  _StoreItem('Arcade Pass', 'R\$ 29,90', Icons.attractions, Color(0xFF9C27B0)),
  _StoreItem('Cosmic Clash', 'R\$ 89,90', Icons.bolt, Color(0xFFF44336)),
];
