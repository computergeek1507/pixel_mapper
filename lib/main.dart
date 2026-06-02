import 'package:flutter/material.dart';

import 'ui/target_setup_page.dart';

void main() {
  runApp(const PixelMapperApp());
}

class PixelMapperApp extends StatelessWidget {
  const PixelMapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pixel Mapper',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const TargetSetupPage(),
    );
  }
}
