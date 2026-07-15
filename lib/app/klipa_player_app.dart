import 'package:flutter/material.dart';

import '../features/library/library_screen.dart';
import 'app_theme.dart';

class KlipaPlayerApp extends StatelessWidget {
  const KlipaPlayerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Klipa Player',
    debugShowCheckedModeBanner: false,
    theme: buildKlipaTheme(),
    home: const LibraryScreen(),
  );
}
