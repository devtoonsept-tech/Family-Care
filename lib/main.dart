
import 'package:flutter/material.dart';

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
      // FIRST SCREEN
      // ======================================================

      home: const LoginScreen(),

      // ======================================================
      // APPLICATION ROUTES
      // ======================================================
      //
      // SignupScreen contains its own email OTP step.
      // No SignupOtpArguments class is needed here.
      //
      // ======================================================

      routes: {
        '/login': (context) => const LoginScreen(),

        '/signup': (context) => const SignupScreen(),

        '/reset-password': (context) =>
        const ResetPasswordScreen(),

        '/patient-dashboard': (context) =>
        const PatientDashboardScreen(),

        '/child-dashboard': (context) =>
        const ChildDashboardScreen(),

        '/child-care': (context) =>
        const ChildDashboardScreen(),

        '/doctor-dashboard': (context) =>
        const _DoctorDashboardPlaceholder(),

        '/doctor-approval-pending': (context) =>
        const _DoctorApprovalPendingScreen(),
      },
    );
  }
}

// ============================================================
// DOCTOR DASHBOARD PLACEHOLDER
// ============================================================

class _DoctorDashboardPlaceholder extends StatelessWidget {
  const _DoctorDashboardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Dashboard'),
      ),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              const Icon(
                Icons.medical_services_outlined,
                size: 58,
                color: FamilyCareApp.primaryColor,
              ),

              const SizedBox(height: 16),

              const Text(
                'Doctor Dashboard',

                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'The doctor dashboard is not '
                    'connected yet.',

                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              FilledButton(
                onPressed: () {
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil(
                    '/login',
                        (_) => false,
                  );
                },

                child: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// DOCTOR APPROVAL PENDING SCREEN
// ============================================================

class _DoctorApprovalPendingScreen extends StatelessWidget {
  const _DoctorApprovalPendingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Doctor Approval'),
      ),

      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),

          child: Column(
            mainAxisSize: MainAxisSize.min,

            children: [
              const Icon(
                Icons.hourglass_top_rounded,
                size: 65,
                color: FamilyCareApp.primaryColor,
              ),

              const SizedBox(height: 20),

              const Text(
                'Doctor Approval Pending',

                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Your doctor account is awaiting '
                    'admin approval. Please sign in '
                    'after your approval is confirmed.',

                textAlign: TextAlign.center,

                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF60728B),
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 20),

              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil(
                    '/login',
                        (_) => false,
                  );
                },

                icon: const Icon(
                  Icons.login_rounded,
                ),

                label: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
