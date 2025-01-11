import 'package:flutter/material.dart';

import 'src/theme/app_theme.dart';

void main() {
  runApp(const ManyKeeApp());
}

/// Root widget for the ManyKee Flutter Web vault browser.
class ManyKeeApp extends StatelessWidget {
  const ManyKeeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ManyKee',
      theme: appTheme(),
      debugShowCheckedModeBanner: false,
      home: const Scaffold(
        body: Center(
          child: Text('ManyKee'),
        ),
      ),
    );
  }
}
