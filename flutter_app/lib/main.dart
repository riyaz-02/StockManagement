import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/notification_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/language_provider.dart';
import 'providers/item_provider.dart';
import 'providers/container_provider.dart';
import 'providers/tally_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/analytics_provider.dart';
import 'providers/store_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'utils/app_colors.dart';
import 'utils/app_toast.dart';
import 'services/push_notification_service.dart';
import 'services/live_reactions.dart';
import 'services/presence_service.dart';

/// Global route observer — used by scanner screens to stop/start the camera
/// when navigating away and returning.
final RouteObserver<ModalRoute<void>> routeObserver =
    RouteObserver<ModalRoute<void>>();

/// Reports the top-most named screen to PresenceService, for the website's Staff & Roles > Live now.
final PresenceRouteObserver presenceRouteObserver = PresenceRouteObserver();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // No-ops quietly (returns false) if google-services.json hasn't been
  // added yet — the rest of the app must keep working regardless.
  await initializeFirebase();

  LiveReactions.attach();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => ItemProvider()),
        ChangeNotifierProvider(create: (_) => ContainerProvider()),
        ChangeNotifierProvider(create: (_) => TallyProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider()),
        ChangeNotifierProvider(create: (_) => StoreProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, child) {
          return MaterialApp(
            navigatorKey: appNavigatorKey,
            title: 'Jewellery Stock Management',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.primary,
                brightness: Brightness.light,
              ),
              // Compact, professional density app-wide (phones and tablets).
              visualDensity: VisualDensity.compact,
              // Text is shrunk app-wide via the text scaler in `builder` below
              // (not TextTheme.apply(fontSizeFactor), which asserts on styles
              // that carry no explicit fontSize).
              textTheme: GoogleFonts.poppinsTextTheme(),
              listTileTheme: const ListTileThemeData(
                dense: true,
                visualDensity: VisualDensity.compact,
                minVerticalPadding: 4,
              ),
              dividerTheme: const DividerThemeData(space: 1, thickness: 0.6),
              appBarTheme: AppBarTheme(
                elevation: 0,
                centerTitle: true,
                toolbarHeight: 48,
                // Deliberately NO titleTextStyle here: a theme-level style is not
                // tinted by each screen's foregroundColor, which made titles on
                // light app bars white. The default (Poppins titleLarge, scaled
                // down by the text scaler) follows foregroundColor correctly.
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                systemOverlayStyle: SystemUiOverlayStyle.light,
              ),
              // Every remaining AlertDialog gets the same soft, rounded look as the modern dialogs.
              dialogTheme: DialogTheme(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                titleTextStyle: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A)),
                contentTextStyle: GoogleFonts.poppins(fontSize: 13.5, height: 1.45, color: Colors.grey.shade800),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              ),
              cardTheme: CardTheme(
                elevation: 1,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              elevatedButtonTheme: ElevatedButtonThemeData(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              inputDecorationTheme: InputDecorationTheme(
                isDense: true,
                filled: true,
                fillColor: Colors.grey[100],
                labelStyle: const TextStyle(fontSize: 13),
                hintStyle: const TextStyle(fontSize: 13),
                errorStyle: const TextStyle(fontSize: 11, height: 1.1),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Colors.red,
                    width: 1.5,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
              ),
            ),
            // Keep layouts tidy: clamp OS font scaling, and stop content from
            // stretching edge-to-edge on very wide tablets/desktop.
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              // OS font size, kept within a sane range, then ~9% smaller for a
              // compact, professional look everywhere (including hard-coded sizes).
              final scale =
                  mq.textScaler.scale(1.0).clamp(0.9, 1.15).toDouble() * 0.91;
              return MediaQuery(
                data: mq.copyWith(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              );
            },
            home: const SplashScreen(),
            navigatorObservers: [routeObserver, presenceRouteObserver],
          );
        },
      ),
    );
  }
}
