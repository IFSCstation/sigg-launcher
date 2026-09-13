import 'package:flutter/material.dart';

class UserProfile {
  const UserProfile(
    this.nickname,
    this.avatarColor,
    this.icon, {
    this.avatarPath,
  });

  final String nickname;
  final Color avatarColor;
  final IconData icon;

  /// Path to the user's profile image inside the avatars folder.
  final String? avatarPath;
}

const defaultMockUsers = <UserProfile>[
  UserProfile('TripleT', Color(0xFF2E7D32), Icons.person),
  UserProfile('Luna', Color(0xFF7C4DFF), Icons.auto_awesome),
  UserProfile('Neko', Color(0xFFE91E63), Icons.pets),
  UserProfile('Rex', Color(0xFF2196F3), Icons.rocket_launch),
];
