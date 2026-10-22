import 'package:flutter/material.dart';
import '../presentation/screens/epcr_editor_screen.dart';

class PCRApp extends StatelessWidget {
  const PCRApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PVFD ePCR',
      theme: ThemeData(useMaterial3: true),
      home: const PCRFormPage(),
    );
  }
}
