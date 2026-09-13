import 'package:flutter/material.dart';
import 'package:sigg_launcher/screens/home/widgets/mock_users.dart';
import 'package:sigg_launcher/services/avatar_loader.dart';

class AppController extends ChangeNotifier {
  static AppController instance = AppController();

  List<UserProfile> _users = defaultMockUsers;
  UserProfile _currentUser = defaultMockUsers.first;

  List<UserProfile> get users => _users;

  UserProfile get currentUser => _currentUser;

  Future<void> loadUsers({List<String>? avatarPaths}) async {
    final paths = avatarPaths ?? await loadAvatarPaths();
    _users = buildUsersFromAvatars(paths);
    _currentUser = _users.first;
    notifyListeners();
  }

  void switchUser(UserProfile user) {
    if (identical(user, _currentUser)) return;
    _currentUser = user;
    notifyListeners();
  }
}