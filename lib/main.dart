import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide ChangeNotifierProvider;
import 'package:provider/provider.dart';

import 'Shell/shell.dart';
import 'core/constants.dart';
import 'core/theme/dispensr_theme.dart';
import 'features/dashboard/dashboard_controller.dart';
import 'features/esp32_bridge/presentation/esp32_bridge_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FdxApp()));
}

class FdxApp extends StatefulWidget {
  const FdxApp({super.key});

  @override
  State<FdxApp> createState() => _FdxAppState();
}

class _FdxAppState extends State<FdxApp> {
  late final DashboardController _controller;
  late final Esp32BridgeController _bridgeController;

  @override
  void initState() {
    super.initState();
    _controller = DashboardController();
    _controller.start();
    _bridgeController = Esp32BridgeController();
  }

  @override
  void dispose() {
    _controller.dispose();
    _bridgeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<DashboardController>.value(value: _controller),
        ChangeNotifierProvider<Esp32BridgeController>.value(
          value: _bridgeController,
        ),
      ],
      child: MaterialApp(
        title: AppBrand.name,
        debugShowCheckedModeBanner: false,
        theme: buildDispensrTheme(),
        home: const AppShell(),
      ),
    );
  }
}
