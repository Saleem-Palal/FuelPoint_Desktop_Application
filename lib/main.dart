import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide ChangeNotifierProvider;
import 'package:provider/provider.dart';

import 'Screens/login_screen.dart';
import 'Screens/onboarding_screen.dart';
import 'Shell/shell.dart';
import 'Shell/shell_navigation.dart';
import 'core/constants.dart';
import 'core/theme/dispensr_theme.dart';
import 'features/dashboard/dashboard_controller.dart';
import 'features/esp32_bridge/presentation/esp32_bridge_controller.dart';
import 'providers/auth_provider.dart';
import 'providers/onboarding_provider.dart';
import 'services/database_helper.dart';
import 'services/window_lifecycle_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await WindowLifecycleService.configureDesktopWindow();
  final bool onboarded = await OnboardingPrefs.isCompleted();
  if (onboarded) {
    try {
      await DatabaseHelper.instance.database;
    } catch (error, stack) {
      debugPrint('Failed to initialize fuel_point_system.db: $error\n$stack');
    }
  } else {
    debugPrint(
      'FuelPoint: onboarding required — deferring SQLite until setup completes',
    );
  }
  runApp(
    ProviderScope(
      child: FdxApp(initialRoute: resolveLaunchRoute(onboarded: onboarded)),
    ),
  );
}

class FdxApp extends StatefulWidget {
  const FdxApp({super.key, required this.initialRoute});

  final String initialRoute;

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
    DatabaseHelper.instance.close();
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
        navigatorKey: appNavigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildDispensrTheme(),
        home: screenForRoute(widget.initialRoute),
        onGenerateRoute: (RouteSettings settings) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (BuildContext context) {
              return screenForRoute(settings.name ?? '/');
            },
          );
        },
      ),
    );
  }
}

/// Maps named routes without stacking `/` under `/login` or `/dashboard`.
Widget screenForRoute(String route) {
  switch (route) {
    case '/onboarding':
      return const OnboardingScreen();
    case '/login':
      return const LoginScreen();
    case '/sale':
      return appShellAt(ShellDestinations.sale);
    case '/dashboard':
      return appShellAt(ShellDestinations.dashboard);
    case '/managers':
      return appShellAt(ShellDestinations.managers);
    default:
      return const AppShell();
  }
}

/// Overrides destination before [AppShell] builds so login does not mutate
/// providers during the route's build/initState phase.
Widget appShellAt(int destination) {
  return ProviderScope(
    overrides: <Override>[
      shellDestinationProvider.overrideWith((Ref ref) => destination),
    ],
    child: const AppShell(),
  );
}
