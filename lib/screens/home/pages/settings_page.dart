import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('Account'),
            subtitle: Text('Profile, nickname and avatar'),
            trailing: Icon(Icons.chevron_right),
          ),
          ListTile(
            leading: Icon(Icons.notifications_outlined),
            title: Text('Notifications'),
            subtitle: Text('Alerts, sounds and badges'),
            trailing: Icon(Icons.chevron_right),
          ),
          ListTile(
            leading: Icon(Icons.palette_outlined),
            title: Text('Appearance'),
            subtitle: Text('Theme and accent color'),
            trailing: Icon(Icons.chevron_right),
          ),
          ListTile(
            leading: Icon(Icons.volume_up_outlined),
            title: Text('Audio'),
            subtitle: Text('Music and sound effects'),
            trailing: Icon(Icons.chevron_right),
          ),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('About'),
            subtitle: Text('Version and licenses'),
            trailing: Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}