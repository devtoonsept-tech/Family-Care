
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'signup_screen.dart';

// ============================================================
// FAMILYCARE+ LOGIN SCREEN
// NAVY + MINT UI
// ============================================================
//
// Patient Login:
// POST /api/v1/patients/login
//
// Doctor Login:
// POST /api/v1/doctors/login
//
// Doctor Approval:
// POST /api/v1/doctors/approval-status
//
// Hero:
// assets/images/login_family.png
//
// ============================================================

class LoginColors {
  static const navy = Color(0xFF102C4B);
  static const deepNavy = Color(0xFF081F37);

  static const mint = Color(0xFF63DDC8);
  static const mintDark = Color(0xFF087E74);

  static const background = Color(0xFFF3FAF9);
  static const white = Colors.white;

  static const muted = Color(0xFF63798A);
  static const border = Color(0xFFD7E6E9);
  static const lightMint = Color(0xFFE8F9F5);

  static const error = Color(0xFFB74250);
}

// ============================================================
// LOGIN ROLES
// ============================================================

enum LoginRole {
  patient,
  doctor,
}

// ============================================================
// API EXCEPTION
// ============================================================

class LoginApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const LoginApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}

// ============================================================
// SECURE SESSION STORAGE
// ============================================================
//
// Public methods preserved for other FamilyCare+ screens.
//
// ============================================================

class FamilyCareSession {
  static const FlutterSecureStorage _storage =
  FlutterSecureStorage();

  // ==========================================================
  // SAVE SESSION
  // ==========================================================

  static Future<void> save({
    required String accessToken,
    required String refreshToken,
    required String role,
    required String userId,
    required String email,
    required int expiresIn,
  }) async {
    if (accessToken.trim().isEmpty ||
        refreshToken.trim().isEmpty ||
        userId.trim().isEmpty ||
        expiresIn <= 0) {
      throw const FormatException(
        'Invalid session data.',
      );
    }

    final expiry = DateTime.now()
        .toUtc()
        .add(Duration(seconds: expiresIn))
        .toIso8601String();

    await clear();

    try {
      await _storage.write(
        key: 'fc_role',
        value: role,
      );

      await _storage.write(
        key: 'fc_user_id',
        value: userId,
      );

      await _storage.write(
        key: 'fc_email',
        value: email,
      );

      await _storage.write(
        key: 'fc_access_expires_at',
        value: expiry,
      );

      await _storage.write(
        key: 'fc_refresh_token',
        value: refreshToken,
      );

      await _storage.write(
        key: 'fc_access_token',
        value: accessToken,
      );
    } catch (_) {
      try {
        await clear();
      } catch (_) {}

      rethrow;
    }
  }

  // ==========================================================
  // READ SESSION
  // ==========================================================

  static Future<String?> accessToken() {
    return _storage.read(
      key: 'fc_access_token',
    );
  }

  static Future<String?> refreshToken() {
    return _storage.read(
      key: 'fc_refresh_token',
    );
  }

  static Future<String?> role() {
    return _storage.read(
      key: 'fc_role',
    );
  }

  static Future<String?> userId() {
    return _storage.read(
      key: 'fc_user_id',
    );
  }

  static Future<String?> email() {
    return _storage.read(
      key: 'fc_email',
    );
  }

  static Future<DateTime?> accessTokenExpiresAt() async {
    final value = await _storage.read(
      key: 'fc_access_expires_at',
    );

    if (value == null) return null;

    return DateTime.tryParse(value);
  }

  // ==========================================================
  // CLEAR SESSION
  // ==========================================================

  static Future<void> clear() async {
    const keys = <String>[
      'fc_access_token',
      'fc_refresh_token',
      'fc_role',
      'fc_user_id',
      'fc_email',
      'fc_access_expires_at',
    ];

    for (final key in keys) {
      await _storage.delete(
        key: key,
      );
    }
  }
}

// ============================================================
// LOGIN SCREEN
// ============================================================

class LoginScreen extends StatefulWidget {
  final String apiBaseUrl;

  final void Function(
      BuildContext context,
      LoginRole role,
      )? onLoginSuccess;

  const LoginScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() =>
      _LoginScreenState();
}

// ============================================================
// LOGIN SCREEN STATE
// ============================================================

class _LoginScreenState extends State<LoginScreen> {
  // ==========================================================
  // FAMILY IMAGE
  // ==========================================================

  static const String _loginFamilyAsset =
      'assets/images/login_family.png';

  // ==========================================================
  // FORM STATE
  // ==========================================================

  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _passwordFocus = FocusNode();

  final http.Client _client = http.Client();

  LoginRole _selectedRole = LoginRole.patient;

  bool _showPassword = false;
  bool _loading = false;
  bool _submitted = false;

  String? _inlineError;

  // ==========================================================
  // API BASE URL
  // ==========================================================

  String get _baseUrl {
    final supplied = widget.apiBaseUrl.trim();

    if (supplied.isNotEmpty) {
      return supplied.replaceAll(
        RegExp(r'/+$'),
        '',
      );
    }

    if (!kIsWeb &&
        defaultTargetPlatform ==
            TargetPlatform.android) {
      return 'http://10.0.2.2:5001';
    }

    return 'http://127.0.0.1:5001';
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    _client.close();

    super.dispose();
  }

  // ==========================================================
  // VALIDATION
  // ==========================================================

  String? _validateEmail(String? input) {
    final value = (input ?? '').trim();

    if (value.isEmpty) {
      return 'Please enter your email address.';
    }

    final pattern = RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    );

    if (!pattern.hasMatch(value)) {
      return 'Enter a valid email address.';
    }

    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password.';
    }

    if (value.length > 128) {
      return 'Password is too long.';
    }

    return null;
  }

  // ==========================================================
  // ERROR HANDLING
  // ==========================================================

  String _errorMessage(Object error) {
    if (error is LoginApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'The server took too long. '
          'Check your connection and retry.';
    }

    if (error is http.ClientException) {
      return 'Cannot reach FamilyCare+. '
          'Check your internet, API URL and CORS settings.';
    }

    if (error is PlatformException) {
      return 'Secure storage is unavailable '
          'on this device.';
    }

    if (error is FormatException) {
      return 'Unexpected response from the server. '
          'Please try again.';
    }

    return 'Something went wrong. Please try again.';
  }

  void _showError(String message) {
    if (!mounted) return;

    setState(() {
      _inlineError = message;
    });
  }

  // ==========================================================
  // FLASK POST REQUEST
  // ==========================================================

  Future<Map<String, dynamic>> _post(
      String path,
      Map<String, dynamic> data,
      ) async {
    final uri = Uri.parse(
      '$_baseUrl$path',
    );

    final response = await _client
        .post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Auth-Transport': 'bearer',
      },
      body: jsonEncode(data),
    )
        .timeout(
      const Duration(seconds: 30),
    );

    Map<String, dynamic>? body;

    try {
      final raw = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (raw is Map) {
        body = Map<String, dynamic>.from(raw);
      }
    } catch (_) {
      // Handle non-JSON HTTP errors below.
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final error = body?['error'];

      var code = 'request_failed';

      var message =
          'Request failed (HTTP ${response.statusCode}).';

      if (error is Map) {
        if (error['code'] is String) {
          code = error['code'] as String;
        }

        if (error['message'] is String) {
          message = error['message'] as String;
        }

        if (code == 'validation_error' &&
            error['fields'] is List) {
          final names = (error['fields'] as List)
              .whereType<Map>()
              .map((item) => item['field'])
              .whereType<String>()
              .toSet()
              .join(', ');

          if (names.isNotEmpty) {
            message = 'Check: $names';
          }
        }
      } else if (error is String &&
          error.trim().isNotEmpty) {
        message = error;
      }

      if (response.statusCode == 429) {
        message = 'Too many attempts. '
            'Please try again later.';
      } else if (response.statusCode >= 500) {
        message =
        'FamilyCare+ server is temporarily unavailable.';
      }

      throw LoginApiException(
        statusCode: response.statusCode,
        code: code,
        message: message,
      );
    }

    if (body == null) {
      throw const LoginApiException(
        statusCode: 0,
        code: 'invalid_response',
        message:
        'The server returned invalid login data.',
      );
    }

    return body;
  }

  // ==========================================================
  // LOGIN API
  // ==========================================================

  Future<void> _login() async {
    if (_loading) return;

    setState(() {
      _submitted = true;
      _inlineError = null;
    });

    final valid =
        _formKey.currentState?.validate() ?? false;

    if (!valid) return;

    FocusManager.instance.primaryFocus?.unfocus();

    final role = _selectedRole;

    final email =
    _emailController.text.trim().toLowerCase();

    final password = _passwordController.text;

    setState(() {
      _loading = true;
    });

    try {
      // ======================================================
      // PATIENT / DOCTOR LOGIN ENDPOINT
      // ======================================================

      final path = role == LoginRole.doctor
          ? '/api/v1/doctors/login'
          : '/api/v1/patients/login';

      final data = await _post(
        path,
        {
          'email': email,
          'password': password,
        },
      );

      // ======================================================
      // EXTRACT BACKEND SESSION
      // ======================================================

      final access = data['access_token'];
      final refresh = data['refresh_token'];
      final user = data['user'];
      final expiresIn = data['expires_in'];

      final expectedRole = role == LoginRole.doctor
          ? 'DOCTOR'
          : 'PATIENT';

      // ======================================================
      // VALIDATE SESSION
      // ======================================================

      if (access is! String ||
          access.trim().isEmpty ||
          refresh is! String ||
          refresh.trim().isEmpty ||
          user is! Map ||
          user['id'] is! String ||
          (user['id'] as String).trim().isEmpty ||
          expiresIn is! num ||
          expiresIn <= 0) {
        throw const LoginApiException(
          statusCode: 0,
          code: 'invalid_session',
          message:
          'The server did not return a valid login session.',
        );
      }

      // ======================================================
      // VERIFY ACCOUNT ROLE
      // ======================================================

      final backendRole = (user['role'] ?? '')
          .toString()
          .toUpperCase();

      if (backendRole != expectedRole) {
        throw const LoginApiException(
          statusCode: 0,
          code: 'role_mismatch',
          message:
          'Account type does not match your selected role.',
        );
      }

      // ======================================================
      // SECURE SESSION STORAGE
      // ======================================================

      await FamilyCareSession.save(
        accessToken: access,
        refreshToken: refresh,
        role: expectedRole,
        userId: user['id'] as String,
        email: email,
        expiresIn: expiresIn.toInt(),
      );

      if (!mounted) return;

      _passwordController.clear();

      TextInput.finishAutofillContext();

      // ======================================================
      // SUCCESS NAVIGATION
      // ======================================================

      if (widget.onLoginSuccess != null) {
        widget.onLoginSuccess!(
          context,
          role,
        );
      } else {
        final route = role == LoginRole.doctor
            ? '/doctor-dashboard'
            : '/patient-dashboard';

        Navigator.of(context).pushNamedAndRemoveUntil(
          route,
              (_) => false,
        );
      }
    } on LoginApiException catch (error) {
      // ======================================================
      // DOCTOR RESTRICTED ACCOUNT
      // ======================================================

      if (role == LoginRole.doctor &&
          error.statusCode == 403 &&
          error.code == 'account_restricted') {
        await _checkDoctorApproval(
          email,
          password,
        );
      } else {
        _showError(error.message);
      }
    } catch (error) {
      _showError(
        _errorMessage(error),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ==========================================================
  // DOCTOR APPROVAL STATUS
  // ==========================================================

  Future<void> _checkDoctorApproval(
      String email,
      String password,
      ) async {
    try {
      final response = await _post(
        '/api/v1/doctors/approval-status',
        {
          'email': email,
          'password': password,
        },
      );

      if (!mounted) return;

      final approval =
      (response['approval_status'] ?? '')
          .toString()
          .toUpperCase();

      final account =
      (response['account_status'] ?? '')
          .toString()
          .toUpperCase();

      final verified =
          response['email_verified'] == true;

      // ======================================================
      // EMAIL NOT VERIFIED
      // ======================================================

      if (!verified) {
        _showError(
          'Your email is not verified. '
              'Complete email verification '
              'before signing in.',
        );

        return;
      }

      // ======================================================
      // ACCOUNT NOT ACTIVE
      // ======================================================

      if (account != 'ACTIVE') {
        _showError(
          'Your doctor account is not active. '
              'Contact FamilyCare+ support.',
        );

        return;
      }

      // ======================================================
      // PENDING APPROVAL
      // ======================================================

      if (approval == 'PENDING_APPROVAL') {
        Navigator.of(context).pushNamed(
          '/doctor-approval-pending',
          arguments: {
            'email': email,
            'approval_status': approval,
          },
        );

        return;
      }

      // ======================================================
      // REJECTED
      // ======================================================

      if (approval == 'REJECTED') {
        final reason =
        (response['rejection_reason'] ?? '')
            .toString()
            .trim();

        _showError(
          reason.isEmpty
              ? 'Your doctor registration was rejected. '
              'Contact support.'
              : 'Doctor registration rejected: $reason',
        );

        return;
      }

      // ======================================================
      // OTHER RESTRICTIONS
      // ======================================================

      _showError(
        approval == 'APPROVED'
            ? 'Your account could not sign in. '
            'Please contact support.'
            : 'Doctor account is not approved '
            'for sign in.',
      );
    } catch (error) {
      _showError(
        _errorMessage(error),
      );
    }
  }

  // ==========================================================
  // SIGNUP NAVIGATION
  // ==========================================================

  void _openSignup() {
    if (_loading) return;

    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => SignupScreen(
          apiBaseUrl: _baseUrl,
        ),
      ),
    );
  }

  // ==========================================================
  // RESET PASSWORD NAVIGATION
  // ==========================================================

  void _openResetPassword() {
    if (_loading) return;

    Navigator.of(context).pushNamed(
      '/reset-password',
      arguments: {
        'email':
        _emailController.text.trim().toLowerCase(),
        'apiBaseUrl': _baseUrl,
      },
    );
  }

  // ==========================================================
  // RESPONSIVE LOGIN PAGE
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LoginColors.background,

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 800;

            return SingleChildScrollView(
              keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior.onDrag,

              padding: EdgeInsets.fromLTRB(
                wide ? 26 : 14,
                wide ? 25 : 14,
                wide ? 26 : 14,
                28,
              ),

              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 980,
                  ),

                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.stretch,

                    children: [
                      // ======================================
                      // NAVY + MINT FAMILY HERO
                      // ======================================

                      _familyHero(wide),

                      const SizedBox(height: 17),

                      // ======================================
                      // WHITE LOGIN CARD
                      // ======================================

                      _loginCard(wide),

                      const SizedBox(height: 19),

                      const Text(
                        'FamilyCare+ • Families. Health. Together.',

                        textAlign: TextAlign.center,

                        style: TextStyle(
                          color: LoginColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ==========================================================
  // COMPACT HERO CARD
  // ==========================================================
  //
  // LEFT: NAVY TEXT
  // RIGHT: FAMILY PHOTO
  //
  // No text overlay on image.
  //
  // ==========================================================

  Widget _familyHero(bool wide) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;

        final height = wide
            ? 230.0
            : (compact ? 158.0 : 175.0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(22),

          child: SizedBox(
            width: double.infinity,
            height: height,

            child: Row(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,

              children: [
                // ============================================
                // LEFT NAVY SECTION
                // ============================================

                Expanded(
                  flex: 11,

                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,

                        colors: [
                          LoginColors.deepNavy,
                          LoginColors.navy,
                        ],
                      ),
                    ),

                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 24 : 12,
                        vertical: wide ? 22 : 12,
                      ),

                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,

                        mainAxisAlignment:
                        MainAxisAlignment.center,

                        children: [
                          // ==================================
                          // BRAND
                          // ==================================

                          _brandRow(large: wide),

                          SizedBox(
                            height: wide ? 25 : 16,
                          ),

                          // ==================================
                          // HEADING
                          // ==================================

                          Text(
                            'Your Family',

                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,

                            style: TextStyle(
                              color: Colors.white,

                              fontSize: wide
                                  ? 29
                                  : (compact ? 16 : 19),

                              fontWeight: FontWeight.w900,
                              height: 1.12,
                            ),
                          ),

                          const SizedBox(height: 2),

                          Text(
                            'Our Priority',

                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,

                            style: TextStyle(
                              color: LoginColors.mint,

                              fontSize: wide
                                  ? 29
                                  : (compact ? 17 : 20),

                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),

                          SizedBox(
                            height: wide ? 12 : 7,
                          ),

                          Text(
                            'Care starts here.',

                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,

                            style: TextStyle(
                              color: const Color(0xFFD7E9ED),

                              fontSize: wide ? 13 : 9,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ============================================
                // RIGHT FAMILY + DOCTOR PHOTO
                // ============================================

                Expanded(
                  flex: 11,

                  child: ColoredBox(
                    color: const Color(0xFFE6F9F4),

                    child: Image.asset(
                      _loginFamilyAsset,

                      width: double.infinity,
                      height: double.infinity,

                      fit: BoxFit.cover,
                      alignment: Alignment.center,

                      errorBuilder: (
                          context,
                          error,
                          stackTrace,
                          ) {
                        return const Center(
                          child: Icon(
                            Icons.family_restroom_rounded,
                            color: LoginColors.navy,
                            size: 54,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // BRAND ROW
  // ==========================================================

  Widget _brandRow({
    required bool large,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,

      children: [
        Container(
          width: large ? 38 : 28,
          height: large ? 38 : 28,

          decoration: BoxDecoration(
            color: LoginColors.mint,
            borderRadius: BorderRadius.circular(9),
          ),

          child: Icon(
            Icons.favorite_rounded,
            color: LoginColors.deepNavy,
            size: large ? 21 : 16,
          ),
        ),

        SizedBox(
          width: large ? 9 : 6,
        ),

        Flexible(
          child: Text(
            'FamilyCare+',

            maxLines: 1,
            overflow: TextOverflow.ellipsis,

            style: TextStyle(
              color: Colors.white,

              fontWeight: FontWeight.w900,

              fontSize: large ? 20 : 12,
              letterSpacing: -0.3,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // WHITE LOGIN CARD
  // ==========================================================

  Widget _loginCard(bool wide) {
    return Container(
      width: double.infinity,

      padding: EdgeInsets.all(
        wide ? 32 : 19,
      ),

      decoration: BoxDecoration(
        color: LoginColors.white,

        borderRadius: BorderRadius.circular(26),

        border: Border.all(
          color: LoginColors.border,
        ),

        boxShadow: const [
          BoxShadow(
            color: Color(0x10102C4B),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),

      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 720,
          ),

          child: AutofillGroup(
            child: Form(
              key: _formKey,

              autovalidateMode: _submitted
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,

              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.stretch,

                mainAxisSize: MainAxisSize.min,

                children: [
                  _formHeader(),

                  const SizedBox(height: 20),

                  _roleSelector(),

                  const SizedBox(height: 22),

                  // ========================================
                  // EMAIL ADDRESS
                  // ========================================

                  _labeledField('Email Address'),

                  const SizedBox(height: 8),

                  _emailField(),

                  const SizedBox(height: 17),

                  // ========================================
                  // PASSWORD
                  // ========================================

                  _labeledField('Password'),

                  const SizedBox(height: 8),

                  _passwordField(),

                  // ========================================
                  // FORGOT PASSWORD
                  // ========================================

                  Align(
                    alignment: Alignment.centerRight,

                    child: TextButton(
                      onPressed: _loading
                          ? null
                          : _openResetPassword,

                      child: const Text(
                        'Forgot password?',

                        style: TextStyle(
                          color: LoginColors.navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),

                  // ========================================
                  // INLINE ERROR
                  // ========================================

                  if (_inlineError != null) ...[
                    const SizedBox(height: 5),

                    _errorBox(_inlineError!),

                    const SizedBox(height: 14),
                  ] else
                    const SizedBox(height: 9),

                  // ========================================
                  // LOGIN BUTTON
                  // ========================================

                  _loginButton(),

                  const SizedBox(height: 15),

                  // ========================================
                  // SIGNUP NAVIGATION
                  // ========================================

                  _signupLink(),

                  const SizedBox(height: 9),

                  const Text(
                    'Your password is never stored in the app.',

                    textAlign: TextAlign.center,

                    style: TextStyle(
                      color: LoginColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // FORM HEADER
  // ==========================================================

  Widget _formHeader() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,

      children: [
        const Text(
          'WELCOME TO FAMILYCARE+',

          style: TextStyle(
            color: LoginColors.mintDark,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),

        const SizedBox(height: 7),

        const Text(
          'Welcome Back!',

          style: TextStyle(
            color: LoginColors.navy,
            fontSize: 25,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),

        const SizedBox(height: 7),

        const Text(
          'Sign in to securely manage your family’s health journey.',

          style: TextStyle(
            color: LoginColors.muted,
            fontSize: 12,
            height: 1.45,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // FIELD LABEL
  // ==========================================================

  Widget _labeledField(String label) {
    return Text(
      label,

      style: const TextStyle(
        color: LoginColors.navy,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    );
  }

  // ==========================================================
  // PATIENT / DOCTOR ROLE SELECTOR
  // ==========================================================

  Widget _roleSelector() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,

      children: [
        _labeledField('Sign in as'),

        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _roleCard(
                LoginRole.patient,
                'Patient / Parent',
                Icons.people_alt_outlined,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: _roleCard(
                LoginRole.doctor,
                'Doctor',
                Icons.medical_services_outlined,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================================
  // ROLE CARD
  // ==========================================================

  Widget _roleCard(
      LoginRole role,
      String label,
      IconData icon,
      ) {
    final active = _selectedRole == role;

    return Material(
      color: active
          ? LoginColors.lightMint
          : const Color(0xFFFAFCFD),

      borderRadius: BorderRadius.circular(15),

      child: InkWell(
        borderRadius: BorderRadius.circular(15),

        onTap: _loading
            ? null
            : () {
          setState(() {
            _selectedRole = role;
            _inlineError = null;
          });
        },

        child: Container(
          height: 92,

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),

            border: Border.all(
              color: active
                  ? LoginColors.navy
                  : LoginColors.border,

              width: active ? 1.8 : 1,
            ),
          ),

          child: Column(
            mainAxisAlignment:
            MainAxisAlignment.center,

            children: [
              Icon(
                icon,
                color: LoginColors.navy,
                size: 25,
              ),

              const SizedBox(height: 9),

              Text(
                label,

                maxLines: 1,
                overflow: TextOverflow.ellipsis,

                style: const TextStyle(
                  color: LoginColors.navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // INPUT DECORATION
  // ==========================================================

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder outline(
        Color color, [
          double width = 1,
        ]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),

        borderSide: BorderSide(
          color: color,
          width: width,
        ),
      );
    }

    return InputDecoration(
      hintText: hint,

      hintStyle: const TextStyle(
        fontSize: 12,
        color: Color(0xFF879DAE),
      ),

      prefixIcon: Icon(
        icon,
        color: LoginColors.navy,
        size: 20,
      ),

      suffixIcon: suffix,

      filled: true,
      fillColor: LoginColors.white,

      contentPadding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 17,
      ),

      border: outline(
        LoginColors.border,
      ),

      enabledBorder: outline(
        LoginColors.border,
      ),

      focusedBorder: outline(
        LoginColors.navy,
        1.8,
      ),

      errorBorder: outline(
        LoginColors.error,
      ),

      focusedErrorBorder: outline(
        LoginColors.error,
        1.5,
      ),

      errorMaxLines: 2,
    );
  }

  // ==========================================================
  // EMAIL FIELD
  // ==========================================================

  Widget _emailField() {
    return TextFormField(
      controller: _emailController,

      enabled: !_loading,

      keyboardType: TextInputType.emailAddress,

      autofillHints: const [
        AutofillHints.username,
        AutofillHints.email,
      ],

      textCapitalization:
      TextCapitalization.none,

      autocorrect: false,

      textInputAction: TextInputAction.next,

      onFieldSubmitted: (_) {
        _passwordFocus.requestFocus();
      },

      validator: _validateEmail,

      decoration: _decoration(
        hint: 'you@example.com',
        icon: Icons.alternate_email_rounded,
      ),
    );
  }

  // ==========================================================
  // PASSWORD FIELD
  // ==========================================================

  Widget _passwordField() {
    return TextFormField(
      controller: _passwordController,
      focusNode: _passwordFocus,

      enabled: !_loading,

      obscureText: !_showPassword,

      enableSuggestions: false,
      autocorrect: false,

      autofillHints: const [
        AutofillHints.password,
      ],

      textInputAction: TextInputAction.done,

      onFieldSubmitted: (_) {
        _login();
      },

      validator: _validatePassword,

      decoration: _decoration(
        hint: 'Enter your password',
        icon: Icons.lock_outline_rounded,

        suffix: IconButton(
          tooltip: _showPassword
              ? 'Hide password'
              : 'Show password',

          onPressed: _loading
              ? null
              : () {
            setState(() {
              _showPassword = !_showPassword;
            });
          },

          icon: Icon(
            _showPassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,

            color: LoginColors.navy,
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // INLINE ERROR BOX
  // ==========================================================

  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(13),

      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F2),

        borderRadius: BorderRadius.circular(12),
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: LoginColors.error,
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              message,

              style: const TextStyle(
                color: LoginColors.error,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // LOGIN BUTTON
  // ==========================================================

  Widget _loginButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,

      child: FilledButton(
        onPressed: _loading ? null : _login,

        style: FilledButton.styleFrom(
          backgroundColor: LoginColors.navy,

          disabledBackgroundColor:
          const Color(0xFF7890A3),

          foregroundColor: LoginColors.white,

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),

        child: _loading
            ? const SizedBox(
          width: 21,
          height: 21,

          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
        )
            : const Row(
          mainAxisSize: MainAxisSize.min,

          mainAxisAlignment:
          MainAxisAlignment.center,

          children: [
            Text(
              'Sign In',

              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),

            SizedBox(width: 9),

            Icon(
              Icons.arrow_forward_rounded,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // SIGNUP LINK
  // ==========================================================

  Widget _signupLink() {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,

        crossAxisAlignment:
        WrapCrossAlignment.center,

        children: [
          const Text(
            "Don't have an account?",

            style: TextStyle(
              color: LoginColors.muted,
              fontSize: 12,
            ),
          ),

          TextButton(
            onPressed: _loading
                ? null
                : _openSignup,

            child: const Text(
              'Sign up',

              style: TextStyle(
                color: LoginColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
