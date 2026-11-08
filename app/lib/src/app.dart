import 'dart:async';

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'library/library_screen.dart';
import 'pairing/pairing_flow.dart';
import 'theme/tokens.dart';

class GrLabApp extends StatelessWidget {
  const GrLabApp({super.key, required this.models});

  final AppModels models;

  @override
  Widget build(BuildContext context) => AppScope(
    models: models,
    child: ListenableBuilder(
      listenable: models.settings,
      builder: (context, _) => MaterialApp(
        title: 'GR Lab',
        debugShowCheckedModeBanner: false,
        theme: grTheme(Brightness.light),
        darkTheme: grTheme(Brightness.dark),
        themeMode: models.settings.themeMode,
        home: const RootScreen(),
      ),
    ),
  );
}

/// Pairing until a camera is paired, then the Library. Connecting starts
/// automatically whenever a paired camera becomes current.
class RootScreen extends StatefulWidget {
  const RootScreen({super.key});

  @override
  State<RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<RootScreen> {
  late final AppModels _models = AppScope.of(context);
  String? _connectedSerial;

  @override
  void initState() {
    super.initState();
    _models.cameras.addListener(_autoConnect);
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoConnect());
  }

  @override
  void dispose() {
    _models.cameras.removeListener(_autoConnect);
    super.dispose();
  }

  void _autoConnect() {
    final serial = _models.cameras.current?.serial;
    if (serial == null || serial == _connectedSerial) return;
    _connectedSerial = serial;
    unawaited(_models.connection.connect());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _models.cameras,
    builder: (context, _) => _models.cameras.current == null
        ? const PairingFlow()
        : const LibraryScreen(),
  );
}
