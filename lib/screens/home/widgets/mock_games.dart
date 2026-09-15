import 'package:flutter/material.dart';

class GameEntry {
  const GameEntry(
    this.title,
    this.tagline,
    this.genre,
    this.icon,
    this.color, {
    this.id,
    this.description,
    this.imageUrl,
    this.imageAsset,
    this.heroPath,
    this.coverPath,
    this.iconPath,
    this.bgmPath,
    this.executable,
  });

  /// Registry game id (slug), e.g. "half-life".
  final String? id;

  final String title;
  final String tagline;
  final String genre;
  final IconData icon;
  final Color color;

  /// Longer game description, shown in place of [tagline] when available.
  final String? description;

  /// Cover art from a network source. Flutter animates GIF/WebP natively.
  final String? imageUrl;

  /// Cover art bundled as an asset. Flutter animates GIF/WebP natively.
  final String? imageAsset;

  /// Path to a local hero.png for the featured banner.
  final String? heroPath;

  /// Path to a local cover.png for the game cover.
  final String? coverPath;

  /// Path to a local square icon.png (~512×512) for Discord RPC / trophy lists.
  final String? iconPath;

  /// Path to a selection BGM track (XMB-style jingle), e.g. bgm.ogg.
  final String? bgmPath;

  /// Command used to launch the game executable (from game.json).
  final String? executable;
}

const mockGames = <GameEntry>[
  GameEntry(
    'Stellar Drift',
    'Race across the cosmos in a hyper-fueled hover racer.',
    'Racing',
    Icons.rocket_launch,
    Color(0xFF7C4DFF),
  ),
  GameEntry(
    'Mystic Grove',
    'Solve ancient puzzles deep inside a glowing forest.',
    'Puzzle',
    Icons.forest,
    Color(0xFF4CAF50),
  ),
  GameEntry(
    'Neon Racer',
    'Street racing under the city lights at full throttle.',
    'Racing',
    Icons.directions_car,
    Color(0xFFE91E63),
  ),
  GameEntry(
    'Dungeon Crawl',
    'Delve into dark dungeons and reclaim lost treasures.',
    'RPG',
    Icons.gavel,
    Color(0xFF8D6E63),
  ),
  GameEntry(
    'Sky Bound',
    'Soar through floating islands in a chill open sky.',
    'Adventure',
    Icons.air,
    Color(0xFF2196F3),
  ),
  GameEntry(
    'Cosmic Clash',
    'Brawl across planetoids in explosive zero-G arenas.',
    'Action',
    Icons.bolt,
    Color(0xFFF44336),
  ),
  GameEntry(
    'Arcade Pass',
    'A jam-packed compendium of retro arcade classics.',
    'Arcade',
    Icons.attractions,
    Color(0xFF9C27B0),
  ),
];

const double coverAspectRatio = 600 / 900;
const double heroAspectRatio = 1900 / 620;
