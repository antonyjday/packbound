import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/deep_link_service.dart';
import 'services/notification_service.dart';
import 'services/theme_service.dart';
import 'screens/home_screen.dart';
import 'screens/sign_in_screen.dart';
import 'utils/brand_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await DeepLinkService.instance.init();
  await NotificationService.instance.init();
  await ThemeService.instance.init();
  runApp(const ConvoyApp());
}

class ConvoyApp extends StatefulWidget {
  const ConvoyApp({super.key});

  @override
  State<ConvoyApp> createState() => _ConvoyAppState();
}

class _ConvoyAppState extends State<ConvoyApp> {
  late final StreamSubscription<User?> _authSub;

  @override
  void initState() {
    super.initState();
    // A side-effect subscription separate from the StreamBuilder below,
    // which rebuilds UI on every parent rebuild (e.g. a theme toggle) using
    // its last-cached snapshot, not just on an actual new stream event -
    // doing this there would re-write lastSeen far more often than
    // intended. This fires exactly once per real auth-state emission:
    // once on cold start (whether resuming a persisted session or not
    // signed in yet) and again on every future sign-in.
    _authSub = AuthService().authStateChanges.listen((user) {
      if (user != null) AuthService().updateLastSeen();
    });
  }

  @override
  void dispose() {
    _authSub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Packbound',
          theme: _brandTheme(Brightness.light),
          darkTheme: _brandTheme(Brightness.dark),
          themeMode: mode,
          home: StreamBuilder(
            stream: AuthService().authStateChanges,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasData) {
                return const HomeScreen();
              }
              return const SignInScreen();
            },
          ),
        );
      },
    );
  }
}

/// Packbound's brand theme (see branding/packbound-brand-guide.html):
/// coral/teal/amber seeded off Material 3's dynamic scheme for a coherent
/// set of derived roles (containers, outlines, error, etc.), then the
/// visually prominent roles (primary/secondary/tertiary/surface) are pinned
/// to the brand's exact hex values via copyWith - fromSeed alone runs every
/// color through Material's tonal-palette algorithm, which noticeably
/// desaturates/darkens a bright color like coral rather than using it as-is.
/// Space Grotesk (bold) for display/headline/title styles, Inter for
/// everything else - matching the guide's "Bold shapes, bright accents"
/// pairing.
ThemeData _brandTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: BrandColors.coral,
    brightness: brightness,
  ).copyWith(
    primary: BrandColors.coral,
    onPrimary: Colors.white,
    secondary: BrandColors.teal,
    onSecondary: Colors.white,
    tertiary: BrandColors.amber,
    onTertiary: BrandColors.ink,
    surface: isDark ? BrandColors.ink : BrandColors.surface,
    onSurface: isDark ? BrandColors.surface : BrandColors.ink,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  final bodyTextTheme = GoogleFonts.interTextTheme(base.textTheme);
  final displayTextTheme = GoogleFonts.spaceGroteskTextTheme(base.textTheme);
  return base.copyWith(
    textTheme: bodyTextTheme.copyWith(
      displayLarge: displayTextTheme.displayLarge,
      displayMedium: displayTextTheme.displayMedium,
      displaySmall: displayTextTheme.displaySmall,
      headlineLarge: displayTextTheme.headlineLarge,
      headlineMedium: displayTextTheme.headlineMedium,
      headlineSmall: displayTextTheme.headlineSmall,
      titleLarge: displayTextTheme.titleLarge,
    ),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: GoogleFonts.spaceGrotesk(
        fontWeight: FontWeight.w700,
        fontSize: 20,
        color: scheme.onSurface,
      ),
    ),
  );
}
