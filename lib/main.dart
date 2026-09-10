import 'package:flutter/material.dart';

import 'ui/home_shell.dart';

void main() {
  runApp(const PixelMapperApp());
}

class PixelMapperApp extends StatelessWidget {
  const PixelMapperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'xModel Tools - Pixel Mapper',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
        ).copyWith(secondary: Colors.orange, tertiary: Colors.deepOrange),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ).copyWith(secondary: Colors.orange, tertiary: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}
