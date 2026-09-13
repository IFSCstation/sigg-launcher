import 'dart:io';
import 'dart:math';

import 'package:sigg_launcher/screens/home/widgets/mock_users.dart';

const String kAvatarsFolder = String.fromEnvironment(
  'AVATARS_FOLDER',
  defaultValue: 'avatars',
);

const _avatarExtensions = <String>['png', 'webp', 'jpg', 'jpeg', 'gif'];

Future<List<String>> loadAvatarPaths({String folder = kAvatarsFolder}) async {
  final dir = Directory(folder);
  if (!await dir.exists()) return const [];

  final paths = <String>[];
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! File) continue;
    final ext = entity.path.split('.').last.toLowerCase();
    if (_avatarExtensions.contains(ext)) {
      paths.add(File(entity.path).absolute.path);
    }
  }
  paths.sort();
  return paths;
}

List<UserProfile> buildUsersFromAvatars(
  List<String> avatarPaths, {
  List<UserProfile> fallback = defaultMockUsers,
}) {
  if (avatarPaths.isEmpty) return List.of(fallback);

  final rng = Random();
  return [
    for (final user in fallback)
      UserProfile(
        user.nickname,
        user.avatarColor,
        user.icon,
        avatarPath: avatarPaths[rng.nextInt(avatarPaths.length)],
      ),
  ];
}