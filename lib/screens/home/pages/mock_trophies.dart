import 'package:flutter/material.dart';

class Trophy {
  const Trophy(
    this.title,
    this.description,
    this.icon,
    this.color, {
    this.isEarned = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool isEarned;
}

class GameEntry {
  const GameEntry(this.title, this.icon, this.color, this.trophies);

  final String title;
  final IconData icon;
  final Color color;
  final List<Trophy> trophies;

  int get earnedCount => trophies.where((t) => t.isEarned).length;
}

const mockGames = <GameEntry>[
  GameEntry('Stellar Drift', Icons.rocket_launch, Color(0xFF7C4DFF), [
    Trophy('Lift Off', 'Complete your first race', Icons.rocket_launch, Color(0xFF7C4DFF), isEarned: true),
    Trophy('Top Speed', 'Reach max velocity', Icons.speed, Color(0xFF7C4DFF), isEarned: true),
    Trophy('Galaxy Explorer', 'Visit every track', Icons.travel_explore, Color(0xFF7C4DFF)),
    Trophy('World Record', 'Beat every time trial', Icons.emoji_events, Color(0xFF7C4DFF)),
  ]),
  GameEntry('Mystic Grove', Icons.forest, Color(0xFF4CAF50), [
    Trophy('Seedling', 'Enter the grove', Icons.park, Color(0xFF4CAF50), isEarned: true),
    Trophy('Forest Guide', 'Clear 20 puzzles', Icons.psychology, Color(0xFF4CAF50)),
    Trophy('Grove Keeper', 'Complete the story', Icons.emoji_events, Color(0xFF4CAF50)),
  ]),
  GameEntry('Neon Racer', Icons.directions_car, Color(0xFFE91E63), [
    Trophy('First Lap', 'Finish a lap', Icons.directions_run, Color(0xFFE91E63), isEarned: true),
    Trophy('Night Owl', 'Win at night', Icons.dark_mode, Color(0xFFE91E63)),
    Trophy('Undefeated', 'Win every race', Icons.military_tech, Color(0xFFE91E63)),
  ]),
];