import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sigg_launcher/app_controller.dart';

class UserWidget extends StatelessWidget {
  const UserWidget({super.key, this.onTap, this.avatarKey});

  final VoidCallback? onTap;

  /// Key attached to the profile icon, used by the header focus indicator.
  final Key? avatarKey;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppController.instance,
      builder: (context, child) {
        final user = AppController.instance.currentUser;
        return Tooltip(
          message: 'Trocar de usuário',
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  key: avatarKey,
                  radius: 24,
                  backgroundColor: user.avatarColor,
                  foregroundColor: Colors.white,
                  backgroundImage: user.avatarPath != null
                      ? FileImage(File(user.avatarPath!))
                      : null,
                  child: user.avatarPath == null
                      ? Icon(user.icon, size: 32)
                      : null,
                ),
                const SizedBox(width: 12),
                Text(
                  user.nickname,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
