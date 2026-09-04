import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'services/storage_service.dart';
import 'services/notification_service.dart';
import 'services/firebase_messaging_service.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await StorageService.init();

  if (!Platform.isWindows) {
    await Firebase.initializeApp();

    await NotificationService.instance.initialize();

    await FirebaseMessagingService.instance.initialize();
  }

  runApp(const SpartanChatApp());
}

class SpartanChatApp extends StatelessWidget {
  const SpartanChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SPARTAN CHAT',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD4AF37),
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}