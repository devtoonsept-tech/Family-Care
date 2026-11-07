
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ============================================================
// FAMILYCARE+ - AUTHENTICATION SCREENS
// ============================================================

import 'screens/auth/login_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/reset_password_screen.dart';

// ============================================================
// FAMILYCARE+ - DASHBOARDS
// ============================================================

import 'screens/patient/patient_dashboard_screen.dart';
import 'screens/child/child_dashboard_screen.dart';
import 'screens/doctor/doctor_dashboard_screen.dart';
import 'screens/doctor/doctor_profile_setup_screen.dart';

// ============================================================
// APPLICATION ENTRY POINT
// ============================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FamilyCareApp());
}

// ============================================================
// FAMILYCARE+ MAIN APPLICATION
// ============================================================

class FamilyCareApp extends StatelessWidget {
  const FamilyCareApp({super.key});

  static const Color primaryColor = Color(0xFF078F81);
  static const Color backgroundColor = Color(0xFFF1F7F9);
  static const Color primaryTextColor = Color(0xFF173D4D);
  static const Color borderColor = Color(0xFFDCE7EC);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamilyCare+',
      debugShowCheckedModeBanner: false,

      // ======================================================
      // APP THEME
      // ======================================================

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          brightness: Brightness.light,
        ),

        scaffoldBackgroundColor: backgroundColor,

        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,

          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),

          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
          ),

          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: borderColor,
            ),
          ),

          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: primaryColor,
              width: 1.8,
            ),
          ),

          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Colors.redAccent,
            ),
          ),

          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
              color: Colors.redAccent,
              width: 1.8,
            ),
          ),
        ),

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 52),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryColor,
            minimumSize: const Size(0, 48),

            side: const BorderSide(
              color: borderColor,
            ),

            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: backgroundColor,
          foregroundColor: primaryTextColor,
          centerTitle: false,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),

        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),

            side: const BorderSide(
              color: borderColor,
            ),
          ),
        ),

        dividerTheme: const DividerThemeData(
          color: borderColor,
          thickness: 1,
        ),

        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: primaryTextColor,

          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13,
          ),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),

        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,

          indicatorColor: primaryColor.withValues(
            alpha: 0.12,
          ),

          elevation: 0,
          height: 74,
        ),
      ),

      // ======================================================
      // FIRST SCREEN — ALWAYS LOGIN
      // ======================================================
      home: const LoginScreen(),

      // ======================================================
      // APPLICATION ROUTES
      // ======================================================
      // Updated LoginScreen and OtpVerificationScreen open the
      // Doctor onboarding workspace DIRECTLY, passing the real
      // backend setup token and doctor data in memory.
      //
      // A standalone '/doctor-dashboard' route is therefore
      // exclusively for an already approved doctor session.
      // Never trust route arguments such as "approved=true".
      // ======================================================
      routes: {
        '/login': (_) => const LoginScreen(),
        '/signup': (_) => const SignupScreen(),
        '/reset-password': (_) => const ResetPasswordScreen(),

        // Existing patient and child routes stay unchanged.
        '/patient-dashboard': (_) => const PatientDashboardScreen(),
        '/child-dashboard': (_) => const ChildDashboardScreen(),
        '/child-care': (_) => const ChildDashboardScreen(),

        // Protected route: verifies role, expiry and backend /me.
        '/doctor-dashboard': (_) => const _ApprovedDoctorGateway(),

        // Legacy names: require login rather than creating a fake
        // pending doctor session without a backend response.
        '/doctor-approval-pending': (_) =>
        const _DoctorLoginRequiredScreen(
          title: 'Doctor Approval',
          message: 'Please sign in as Doctor to check approval status. '
              'Pending doctors can access Dashboard and Set My Profile '
              'through the doctor login flow.',
        ),
        '/doctor-profile-setup': (_) =>
        const _DoctorLoginRequiredScreen(
          title: 'Doctor Profile Setup',
          message: 'Please verify your doctor email or sign in as Doctor '
              'to get a valid profile setup token.',
        ),
      },
    );
  }
}

// ============================================================
// APPROVED DOCTOR ROUTE GATEWAY
// ============================================================
// Only used when navigating to '/doctor-dashboard' directly.
// A valid stored doctor token is verified against the Flask
// backend BEFORE the approved doctor dashboard is rendered.
//
// Pending / rejected / profile-required doctors do NOT have
// clinical access tokens. Their login and OTP screens already
// open an in-memory limited dashboard/profile workspace.
// ============================================================

class _ApprovedDoctorGateway extends StatefulWidget {
  const _ApprovedDoctorGateway();

  @override
  State<_ApprovedDoctorGateway> createState() =>
      _ApprovedDoctorGatewayState();
}

class _ApprovedDoctorGatewayState extends State<_ApprovedDoctorGateway> {
  final http.Client _client = http.Client();

  bool _loading = true;
  bool _showProfile = false;
  String? _error;
  Map<String, dynamic> _user = <String, dynamic>{};
  Map<String, dynamic> _doctor = <String, dynamic>{};

  static const String _configuredApiUrl = String.fromEnvironment(
    'FAMILY_CARE_API_URL',
    defaultValue: '',
  );

  String get _apiBaseUrl {
    if (_configuredApiUrl.trim().isNotEmpty) {
      return _configuredApiUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Android emulator -> host development server.
      return 'http://10.0.2.2:5001';
    }
    // Desktop and Flutter Web local development.
    return 'http://127.0.0.1:5001';
  }

  @override
  void initState() {
    super.initState();
    _verifyDoctorSession();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  Future<void> _verifyDoctorSession() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _showProfile = false;
    });

    try {
      final role = await FamilyCareSession.role();
      final token = await FamilyCareSession.accessToken();
      final expiry = await FamilyCareSession.accessTokenExpiresAt();

      if (role?.toUpperCase() != 'DOCTOR' ||
          token == null ||
          token.trim().isEmpty) {
        throw StateError('Sign in as an approved Doctor to continue.');
      }
      if (expiry == null || !expiry.isAfter(DateTime.now().toUtc())) {
        throw StateError('Your doctor session has expired. Sign in again.');
      }

      final response = await _client.get(
        Uri.parse('$_apiBaseUrl/api/v1/doctors/me'),
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'X-Auth-Transport': 'bearer',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw StateError(
          'Doctor access is unavailable. Please sign in again.',
        );
      }
      if (response.statusCode != 200) {
        throw StateError(
          'Unable to verify Doctor (HTTP ${response.statusCode}).',
        );
      }

      final responseJson = jsonDecode(utf8.decode(response.bodyBytes));
      final body = _asMap(responseJson);
      final user = _asMap(body['user']);

      if ((user['role'] ?? '').toString().toUpperCase() != 'DOCTOR' ||
          (user['approval_status'] ?? '').toString().toUpperCase() !=
              'APPROVED' ||
          (user['account_status'] ?? '').toString().toUpperCase() !=
              'ACTIVE') {
        throw StateError(
          'Only admin-approved, active doctors can open this dashboard.',
        );
      }

      if (!mounted) return;
      setState(() {
        _user = user;
        _doctor = _asMap(user['doctor']);
        _loading = false;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Doctor verification timed out. Try again.';
      });
    } on FormatException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Invalid response from the server. Try again.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is StateError
            ? error.message.toString()
            : 'Could not verify your doctor session. Check your connection.';
      });
    }
  }

  Future<void> _goToLogin() async {
    // Explicit exit clears any previous clinical session.
    try {
      await FamilyCareSession.clear();
    } catch (_) {
      // The login screen still opens if device storage is unavailable.
    }
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Verifying doctor access...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Doctor Verification')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.gpp_bad_outlined,
                    size: 52,
                    color: FamilyCareApp.primaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _verifyDoctorSession,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),
                  TextButton(
                    onPressed: _goToLogin,
                    child: const Text('Back to Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // An IndexedStack keeps the real approved doctor's dashboard and
    // profile screen mounted when switching between the two.
    return IndexedStack(
      index: _showProfile ? 1 : 0,
      children: <Widget>[
        DoctorDashboardScreen(
          doctorName: (_user['full_name'] ?? '').toString(),
          email: (_user['email'] ?? '').toString(),
          approvalStatus: 'APPROVED',
          doctorDetails: _doctor,
          apiBaseUrl: _apiBaseUrl,
          onOpenProfile: () {
            setState(() => _showProfile = true);
          },
          onGoToLogin: _goToLogin,
          // Do not connect clinical routes until their individual
          // Flutter screens are complete and permission-aware.
        ),
        DoctorProfileSetupScreen(
          initialUser: _user,
          initialDoctor: _doctor,
          approvalStatus: 'APPROVED',
          apiBaseUrl: _apiBaseUrl,
          onBackToDashboard: () {
            setState(() => _showProfile = false);
          },
        ),
      ],
    );
  }
}

// ============================================================
// LEGACY DOCTOR ROUTES — SAFE SIGN-IN PROMPT
// ============================================================
// Setup and approval status cannot be recovered from route names
// alone. OTP/login provide those states with backend response data.
// ============================================================

class _DoctorLoginRequiredScreen extends StatelessWidget {
  final String title;
  final String message;

  const _DoctorLoginRequiredScreen({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.verified_user_outlined,
                  color: FamilyCareApp.primaryColor,
                  size: 58,
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 23,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.5),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/login',
                          (route) => false,
                    );
                  },
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Continue to Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
