import 'package:flutter/material.dart';
import 'welcome_screen.dart';

void main() {
  runApp(const BrainLagApp());
}

class BrainLagApp extends StatelessWidget {
  const BrainLagApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BrainLag',
      theme: ThemeData(
        fontFamily: 'Roboto',
      ),
      home: const WelcomeScreen(),
    );
  }
}