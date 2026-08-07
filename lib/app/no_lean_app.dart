import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'shell.dart';

class NoLeanApp extends StatelessWidget {
  const NoLeanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NO LEAN',
      debugShowCheckedModeBanner: false,
      theme: buildNoLeanTheme(),
      home: const Shell(),
    );
  }
}
