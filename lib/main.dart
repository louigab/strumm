import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:strumm/features/tuner/screens/tuner_screen.dart';
import 'package:strumm/core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock app to portrait up only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const StrummApp());
}

class StrummApp extends StatelessWidget {
  const StrummApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Strumm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const TunerScreen(),
    );
  }
}
