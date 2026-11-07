
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'login_screen.dart';

// ============================================================
// FAMILY CARE - RESET PASSWORD SCREEN
// ============================================================
//
// Backend: Python Flask
//
// POST /api/v1/auth/forgot-password
// POST /api/v1/auth/resend-otp
// POST /api/v1/auth/reset-password
//
// FLOW:
//
// Login Screen
//      |
// Forgot Password
//      |
// Enter Email Address
//      |
// Request Email OTP
//      |
// Enter 6-Digit OTP
//      |
// Enter New Password
//      |
// Confirm New Password
//      |
// Reset Password
//      |
// Back to Login
//
// This screen supports both Patient and Doctor accounts.
//
// No separate forgot_password_screen.dart is required.
//
// ============================================================

// ============================================================
// COLORS
// ============================================================

class ResetColors {
  static const Color primary = Color(0xFF078F81);
  static const Color accent = Color(0xFF13AA9C);
  static const Color navy = Color(0xFF103E51);

  static const Color background = Color(0xFFF1F7F9);
  static const Color white = Colors.white;

  static const Color text = Color(0xFF173D4D);
  static const Color muted = Color(0xFF6A8290);

  static const Color border = Color(0xFFDCE7EC);
  static const Color lightTeal = Color(0xFFEAF8F5);

  static const Color error = Color(0xFFB7434E);
}

// ============================================================
// PASSWORD RESET STEPS
// ============================================================

enum ResetPasswordStep {
  enterEmail,
  verifyOtp,
  completed,
}

// ============================================================
// API EXCEPTION
// ============================================================

class ResetPasswordApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const ResetPasswordApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() {
    return message;
  }
}

// ============================================================
// RESET PASSWORD SCREEN
// ============================================================

class ResetPasswordScreen extends StatefulWidget {
  final String? initialEmail;

  final String apiBaseUrl;

  const ResetPasswordScreen({
    super.key,
    this.initialEmail,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
  });

  @override
  State<ResetPasswordScreen> createState() {
    return _ResetPasswordScreenState();
  }
}

// ============================================================
// RESET PASSWORD SCREEN STATE
// ============================================================

class _ResetPasswordScreenState
    extends State<ResetPasswordScreen> {

  // ----------------------------------------------------------
  // FORM KEYS
  // ----------------------------------------------------------

  final GlobalKey<FormState> _emailFormKey =
  GlobalKey<FormState>();

  final GlobalKey<FormState> _passwordFormKey =
  GlobalKey<FormState>();

  // ----------------------------------------------------------
  // TEXT CONTROLLERS
  // ----------------------------------------------------------

  final TextEditingController _emailController =
  TextEditingController();

  final TextEditingController _otpController =
  TextEditingController();

  final TextEditingController _newPasswordController =
  TextEditingController();

  final TextEditingController _confirmPasswordController =
  TextEditingController();

  // ----------------------------------------------------------
  // HTTP CLIENT
  // ----------------------------------------------------------

  final http.Client _httpClient = http.Client();

  // ----------------------------------------------------------
  // SCREEN STATE
  // ----------------------------------------------------------

  ResetPasswordStep _currentStep =
      ResetPasswordStep.enterEmail;

  bool _isLoading = false;

  bool _emailSubmitted = false;

  bool _passwordSubmitted = false;

  bool _showNewPassword = false;

  bool _showConfirmPassword = false;

  bool _routeInitialized = false;

  String? _routeApiBaseUrl;

  // ----------------------------------------------------------
  // OTP STATE
  // ----------------------------------------------------------

  String? _challengeToken;

  Timer? _otpTimer;

  late DateTime _otpExpiresAt;

  late DateTime _resendAvailableAt;

  // ==========================================================
  // INITIALIZATION
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _emailController.text = widget.initialEmail ?? '';

    final now = DateTime.now();

    _otpExpiresAt = now;

    _resendAvailableAt = now;
  }

  // ==========================================================
  // RECEIVE LOGIN SCREEN ARGUMENTS
  // ==========================================================

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_routeInitialized) {
      return;
    }

    _routeInitialized = true;

    // LoginScreen passes:
    //
    // Navigator.pushNamed(
    //   '/reset-password',
    //   arguments: {
    //     'email': email,
    //     'apiBaseUrl': baseUrl,
    //   },
    // );

    final arguments =
        ModalRoute.of(context)?.settings.arguments;

    if (arguments is Map) {
      final email = arguments['email'];

      final apiUrl = arguments['apiBaseUrl'];

      if (email is String &&
          email.trim().isNotEmpty &&
          _emailController.text.trim().isEmpty) {
        _emailController.text = email.trim();
      }

      if (apiUrl is String &&
          apiUrl.trim().isNotEmpty) {
        _routeApiBaseUrl = apiUrl.trim();
      }
    }
  }

  // ==========================================================
  // API BASE URL
  // ==========================================================

  String get _baseUrl {
    final configured = widget.apiBaseUrl.trim();

    if (configured.isNotEmpty) {
      return configured.replaceAll(
        RegExp(r'/+$'),
        '',
      );
    }

    final routeUrl = _routeApiBaseUrl?.trim() ?? '';

    if (routeUrl.isNotEmpty) {
      return routeUrl.replaceAll(
        RegExp(r'/+$'),
        '',
      );
    }

    // Android Emulator

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5001';
    }

    // Desktop / Web

    return 'http://127.0.0.1:5001';
  }

  // ==========================================================
  // OTP TIMER HELPERS
  // ==========================================================

  int _remainingSeconds(DateTime target) {
    final difference =
        target.difference(DateTime.now()).inMilliseconds;

    if (difference <= 0) {
      return 0;
    }

    return (difference + 999) ~/ 1000;
  }

  int get _otpExpirySeconds {
    return _remainingSeconds(_otpExpiresAt);
  }

  int get _resendSeconds {
    return _remainingSeconds(_resendAvailableAt);
  }

  int _readSeconds(
      dynamic value,
      int fallback,
      ) {
    if (value is num && value >= 0) {
      return value.toInt();
    }

    return fallback;
  }

  String _formatSeconds(int seconds) {
    final minutes = seconds ~/ 60;

    final remaining = seconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${remaining.toString().padLeft(2, '0')}';
  }

  // ==========================================================
  // START OTP COUNTDOWN
  // ==========================================================

  void _startOtpCountdown({
    required int resendAfter,
    required int expiresIn,
  }) {
    _otpTimer?.cancel();

    final now = DateTime.now();

    _otpExpiresAt = now.add(
      Duration(
        seconds: expiresIn >= 0 ? expiresIn : 300,
      ),
    );

    _resendAvailableAt = now.add(
      Duration(
        seconds: resendAfter >= 0 ? resendAfter : 60,
      ),
    );

    _otpTimer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {});

        if (_otpExpirySeconds == 0 &&
            _resendSeconds == 0) {
          timer.cancel();
        }
      },
    );
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _otpTimer?.cancel();

    _httpClient.close();

    _emailController.dispose();

    _otpController.dispose();

    _newPasswordController.dispose();

    _confirmPasswordController.dispose();

    super.dispose();
  }

  // ==========================================================
  // EMAIL VALIDATION
  // ==========================================================

  String? _validateEmail(String? value) {
    final email = (value ?? '').trim();

    if (email.isEmpty) {
      return 'Email address is required';
    }

    final pattern = RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    );

    if (!pattern.hasMatch(email)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  // ==========================================================
  // OTP VALIDATION
  // ==========================================================

  String? _validateOtp(String? value) {
    final otp = (value ?? '').trim();

    if (otp.isEmpty) {
      return 'Please enter your OTP';
    }

    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      return 'Enter a valid 6-digit OTP';
    }

    return null;
  }

  // ==========================================================
  // NEW PASSWORD VALIDATION
  // ==========================================================

  String? _validateNewPassword(String? value) {
    final password = value ?? '';

    if (password.isEmpty) {
      return 'New password is required';
    }

    if (password.length < 8) {
      return 'Password must contain at least 8 characters';
    }

    if (password.length > 128) {
      return 'Maximum 128 characters allowed';
    }

    return null;
  }

  // ==========================================================
  // CONFIRM PASSWORD VALIDATION
  // ==========================================================

  String? _validateConfirmPassword(String? value) {
    final confirmPassword = value ?? '';

    if (confirmPassword.isEmpty) {
      return 'Please confirm your password';
    }

    if (confirmPassword !=
        _newPasswordController.text) {
      return 'Passwords do not match';
    }

    return null;
  }

  // ==========================================================
  // NOTIFICATION
  // ==========================================================

  void _showMessage(
      String message, {
        bool error = false,
      }) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error
              ? ResetColors.error
              : ResetColors.navy,
          content: Text(message),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ==========================================================
  // HTTP POST REQUEST
  // ==========================================================

  Future<Map<String, dynamic>> _postRequest(
      String endpoint,
      Map<String, dynamic> body,
      ) async {
    final uri = Uri.parse(
      '$_baseUrl$endpoint',
    );

    final response = await _httpClient
        .post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Auth-Transport': 'bearer',
      },
      body: jsonEncode(body),
    )
        .timeout(
      const Duration(seconds: 30),
    );

    Map<String, dynamic> result;

    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (decoded is! Map) {
        throw const FormatException(
          'Invalid server response',
        );
      }

      result = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const ResetPasswordApiException(
        statusCode: 0,
        code: 'invalid_response',
        message:
        'Invalid response received from the server.',
      );
    } on TypeError {
      throw const ResetPasswordApiException(
        statusCode: 0,
        code: 'invalid_response',
        message:
        'Invalid response received from the server.',
      );
    }

    // --------------------------------------------------------
    // HANDLE HTTP ERRORS
    // --------------------------------------------------------

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final errorData = result['error'];

      String errorCode = 'request_failed';

      String errorMessage =
          'Request failed. Please try again.';

      if (errorData is Map) {
        final code = errorData['code'];
        final message = errorData['message'];

        if (code is String) {
          errorCode = code;
        }

        if (message is String &&
            message.isNotEmpty) {
          errorMessage = message;
        }

        if (errorCode == 'validation_error') {
          final fields = errorData['fields'];

          if (fields is List && fields.isNotEmpty) {
            final names = fields
                .whereType<Map>()
                .map((item) => item['field'])
                .whereType<String>()
                .toSet()
                .join(', ');

            if (names.isNotEmpty) {
              errorMessage =
              'Check these fields: $names';
            }
          }
        }
      }

      throw ResetPasswordApiException(
        statusCode: response.statusCode,
        code: errorCode,
        message: errorMessage,
      );
    }

    return result;
  }

  // ==========================================================
  // HANDLE API ERRORS
  // ==========================================================

  void _handleError(Object error) {
    if (!mounted) {
      return;
    }

    if (error is ResetPasswordApiException) {
      _showMessage(
        error.message,
        error: true,
      );
      return;
    }

    if (error is TimeoutException) {
      _showMessage(
        'Server response timed out. Please try again.',
        error: true,
      );
      return;
    }

    if (error is http.ClientException) {
      _showMessage(
        'Could not connect to the server. '
            'Check your internet connection.',
        error: true,
      );
      return;
    }

    _showMessage(
      'Something went wrong. Please try again.',
      error: true,
    );
  }

  // ==========================================================
  // STEP 1 - REQUEST PASSWORD RESET
  // ==========================================================

  Future<void> _requestPasswordReset() async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _emailSubmitted = true;
    });

    final valid =
        _emailFormKey.currentState?.validate() ?? false;

    if (!valid) {
      return;
    }

    FocusScope.of(context).unfocus();

    final email =
    _emailController.text.trim().toLowerCase();

    setState(() {
      _isLoading = true;
    });

    try {
      // ------------------------------------------------------
      // POST /api/v1/auth/forgot-password
      // ------------------------------------------------------

      final response = await _postRequest(
        '/api/v1/auth/forgot-password',
        {
          'email': email,
        },
      );

      final challenge = response['challenge_token'];

      if (challenge is! String ||
          challenge.isEmpty) {
        throw const ResetPasswordApiException(
          statusCode: 0,
          code: 'missing_challenge',
          message:
          'Password reset session could not be started.',
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _challengeToken = challenge;

        _otpController.clear();

        _newPasswordController.clear();

        _confirmPasswordController.clear();

        _passwordSubmitted = false;

        _currentStep = ResetPasswordStep.verifyOtp;
      });

      _startOtpCountdown(
        resendAfter: _readSeconds(
          response['resend_after'],
          60,
        ),
        expiresIn: _readSeconds(
          response['expires_in'],
          300,
        ),
      );

      // The backend intentionally does not confirm
      // whether a registered email exists.

      _showMessage(
        'If an eligible account exists, '
            'reset instructions will be sent to your email.',
      );
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ==========================================================
  // STEP 2 - RESEND OTP
  // ==========================================================

  Future<void> _resendOtp() async {
    if (_isLoading ||
        _resendSeconds > 0 ||
        _currentStep != ResetPasswordStep.verifyOtp) {
      return;
    }

    final challenge = _challengeToken;

    if (challenge == null || challenge.isEmpty) {
      _showMessage(
        'OTP session unavailable. Please start again.',
        error: true,
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // ------------------------------------------------------
      // POST /api/v1/auth/resend-otp
      // ------------------------------------------------------

      final response = await _postRequest(
        '/api/v1/auth/resend-otp',
        {
          'challenge_token': challenge,
        },
      );

      final newChallenge = response['challenge_token'];

      if (newChallenge is! String ||
          newChallenge.isEmpty) {
        throw const ResetPasswordApiException(
          statusCode: 0,
          code: 'missing_challenge',
          message:
          'New verification challenge was not received.',
        );
      }

      if (!mounted) {
        return;
      }

      // The backend replaces the previous challenge.

      setState(() {
        _challengeToken = newChallenge;

        _otpController.clear();
      });

      _startOtpCountdown(
        resendAfter: _readSeconds(
          response['resend_after'],
          60,
        ),
        expiresIn: _readSeconds(
          response['expires_in'],
          300,
        ),
      );

      _showMessage(
        'If your account is eligible, '
            'a new OTP will be sent to your email.',
      );
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ==========================================================
  // STEP 3 - RESET PASSWORD
  // ==========================================================

  Future<void> _resetPassword() async {
    if (_isLoading ||
        _currentStep != ResetPasswordStep.verifyOtp) {
      return;
    }

    setState(() {
      _passwordSubmitted = true;
    });

    final valid =
        _passwordFormKey.currentState?.validate() ?? false;

    if (!valid) {
      return;
    }

    if (_otpExpirySeconds <= 0) {
      _showMessage(
        'Your OTP has expired. Request a new OTP.',
        error: true,
      );
      return;
    }

    final challenge = _challengeToken;

    if (challenge == null || challenge.isEmpty) {
      _showMessage(
        'OTP session unavailable. Please start again.',
        error: true,
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
    });

    try {
      // ------------------------------------------------------
      // POST /api/v1/auth/reset-password
      // ------------------------------------------------------
      //
      // REQUEST BODY:
      //
      // {
      //   "challenge_token": "...",
      //   "otp": "123456",
      //   "new_password": "...",
      //   "confirm_password": "..."
      // }
      //
      // The backend verifies the OTP, changes the
      // password and revokes previous sessions.

      await _postRequest(
        '/api/v1/auth/reset-password',
        {
          'challenge_token': challenge,
          'otp': _otpController.text.trim(),
          'new_password':
          _newPasswordController.text,
          'confirm_password':
          _confirmPasswordController.text,
        },
      );

      if (!mounted) {
        return;
      }

      _otpTimer?.cancel();

      // ------------------------------------------------------
      // CLEAR SENSITIVE INPUTS
      // ------------------------------------------------------

      _otpController.clear();

      _newPasswordController.clear();

      _confirmPasswordController.clear();

      // ------------------------------------------------------
      // CLEAR PREVIOUS LOCAL LOGIN SESSION
      // ------------------------------------------------------

      try {
        await FamilyCareSession.clear();
      } catch (error) {
        debugPrint(
          'Local session cleanup could not be completed.',
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _challengeToken = null;

        _currentStep = ResetPasswordStep.completed;
      });

      _showMessage(
        'Password reset successfully.',
      );
    } catch (error) {
      _handleError(error);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ==========================================================
  // EDIT EMAIL ADDRESS
  // ==========================================================

  void _editEmail() {
    if (_isLoading) {
      return;
    }

    FocusScope.of(context).unfocus();

    _otpTimer?.cancel();

    _otpController.clear();

    _newPasswordController.clear();

    _confirmPasswordController.clear();

    setState(() {
      _challengeToken = null;

      _emailSubmitted = false;

      _passwordSubmitted = false;

      _currentStep = ResetPasswordStep.enterEmail;
    });
  }

  // ==========================================================
  // RETURN TO LOGIN
  // ==========================================================

  void _backToLogin() {
    if (_isLoading) {
      return;
    }

    FocusScope.of(context).unfocus();

    final navigator = Navigator.of(context);

    // Normal navigation:
    // Login -> Reset Password -> Login

    if (navigator.canPop()) {
      navigator.pop(
        _currentStep == ResetPasswordStep.completed,
      );
      return;
    }

    // Fallback if reset screen was launched directly.

    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(
          apiBaseUrl: _baseUrl,
        ),
      ),
    );
  }

  // ==========================================================
  // APP BAR BACK BUTTON
  // ==========================================================

  void _handleBack() {
    if (_isLoading) {
      return;
    }

    if (_currentStep == ResetPasswordStep.verifyOtp) {
      _editEmail();
      return;
    }

    _backToLogin();
  }

  // ==========================================================
  // MAIN BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isLoading,

      child: Scaffold(
        backgroundColor: ResetColors.background,

        appBar: AppBar(
          backgroundColor: ResetColors.background,
          foregroundColor: ResetColors.navy,
          elevation: 0,

          leading: IconButton(
            tooltip: 'Go back',
            onPressed: _isLoading ? null : _handleBack,
            icon: const Icon(
              Icons.arrow_back_rounded,
            ),
          ),

          title: Text(
            _currentStep == ResetPasswordStep.completed
                ? 'Password Updated'
                : 'Reset Password',

            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),

              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 540,
                ),

                child: Column(
                  children: [
                    // ----------------------------------------
                    // HEADER
                    // ----------------------------------------

                    _buildHeader(),

                    const SizedBox(height: 20),

                    // ----------------------------------------
                    // MAIN CARD
                    // ----------------------------------------

                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 28,
                      ),

                      decoration: BoxDecoration(
                        color: ResetColors.white,

                        borderRadius:
                        BorderRadius.circular(22),

                        border: Border.all(
                          color: ResetColors.border,
                        ),

                        boxShadow: [
                          BoxShadow(
                            color: ResetColors.navy.withValues(
                              alpha: 0.05,
                            ),

                            blurRadius: 24,

                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),

                      child: _buildCurrentStep(),
                    ),

                    const SizedBox(height: 20),

                    const Text(
                      'Family Care  •  Your health, our priority',

                      textAlign: TextAlign.center,

                      style: TextStyle(
                        color: ResetColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // BUILD CURRENT STEP
  // ==========================================================

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case ResetPasswordStep.enterEmail:
        return _buildEmailStep();

      case ResetPasswordStep.verifyOtp:
        return _buildVerificationStep();

      case ResetPasswordStep.completed:
        return _buildCompletedStep();
    }
  }

  // ==========================================================
  // HEADER
  // ==========================================================

  Widget _buildHeader() {
    String heading;

    String description;

    switch (_currentStep) {
      case ResetPasswordStep.enterEmail:
        heading = 'Forgot your password?';
        description =
        'Secure access to your Family Care account.';
        break;

      case ResetPasswordStep.verifyOtp:
        heading = 'Verify & reset password';
        description =
        'Enter your verification code and new password.';
        break;

      case ResetPasswordStep.completed:
        heading = 'Password reset successful';
        description =
        'Your account is ready for secure sign in.';
        break;
    }

    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(26),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,

          colors: [
            ResetColors.navy,
            ResetColors.primary,
            ResetColors.accent,
          ],
        ),

        borderRadius: BorderRadius.circular(22),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Row(
            children: [
              Icon(
                Icons.monitor_heart_rounded,
                color: Colors.white,
                size: 31,
              ),

              SizedBox(width: 12),

              Text(
                'FAMILY CARE',

                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          Text(
            heading,

            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            description,

            style: const TextStyle(
              color: Color(0xFFE4F5F3),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // STEP 1 - ENTER EMAIL
  // ==========================================================

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,

      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),

            decoration: const BoxDecoration(
              color: ResetColors.lightTeal,
              shape: BoxShape.circle,
            ),

            child: const Icon(
              Icons.lock_reset_rounded,
              color: ResetColors.primary,
              size: 46,
            ),
          ),
        ),

        const SizedBox(height: 20),

        const Center(
          child: Text(
            'Reset Your Password',

            textAlign: TextAlign.center,

            style: TextStyle(
              color: ResetColors.text,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),

        const SizedBox(height: 11),

        const Text(
          'Enter your registered email address to '
              'request a password reset OTP.',

          textAlign: TextAlign.center,

          style: TextStyle(
            color: ResetColors.muted,
            fontSize: 13,
            height: 1.6,
          ),
        ),

        const SizedBox(height: 27),

        Form(
          key: _emailFormKey,

          autovalidateMode: _emailSubmitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,

          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,

            children: [
              const Text(
                'Email Address',

                style: TextStyle(
                  color: ResetColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 9),

              TextFormField(
                controller: _emailController,

                enabled: !_isLoading,

                keyboardType:
                TextInputType.emailAddress,

                textCapitalization:
                TextCapitalization.none,

                autocorrect: false,

                autofillHints: const [
                  AutofillHints.email,
                ],

                textInputAction:
                TextInputAction.done,

                validator: _validateEmail,

                onFieldSubmitted: (_) {
                  _requestPasswordReset();
                },

                decoration: _fieldDecoration(
                  hint: 'Enter your registered email',
                  icon: Icons.email_outlined,
                ),
              ),

              const SizedBox(height: 25),

              _buildPrimaryButton(
                title: 'Send Reset OTP',
                icon: Icons.arrow_forward_rounded,
                onPressed: _requestPasswordReset,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        Center(
          child: TextButton.icon(
            onPressed: _isLoading
                ? null
                : _backToLogin,

            icon: const Icon(
              Icons.arrow_back_rounded,
              size: 17,
            ),

            label: const Text(
              'Back to Login',
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // STEP 2 - VERIFY OTP AND RESET PASSWORD
  // ==========================================================

  Widget _buildVerificationStep() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,

      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),

            decoration: const BoxDecoration(
              color: ResetColors.lightTeal,
              shape: BoxShape.circle,
            ),

            child: const Icon(
              Icons.mark_email_read_outlined,
              color: ResetColors.primary,
              size: 45,
            ),
          ),
        ),

        const SizedBox(height: 19),

        const Center(
          child: Text(
            'Verify Your Email',

            textAlign: TextAlign.center,

            style: TextStyle(
              color: ResetColors.text,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),

        const SizedBox(height: 10),

        const Center(
          child: Text(
            'If your account is eligible, a 6-digit '
                'verification code has been requested for',

            textAlign: TextAlign.center,

            style: TextStyle(
              color: ResetColors.muted,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),

        const SizedBox(height: 6),

        Center(
          child: SelectableText(
            _emailController.text.trim(),

            textAlign: TextAlign.center,

            style: const TextStyle(
              color: ResetColors.primary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),

        const SizedBox(height: 25),

        Form(
          key: _passwordFormKey,

          autovalidateMode: _passwordSubmitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,

          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,

            children: [
              // ----------------------------------------------
              // OTP INPUT
              // ----------------------------------------------

              const Text(
                'Verification OTP',

                style: TextStyle(
                  color: ResetColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 9),

              TextFormField(
                controller: _otpController,

                enabled: !_isLoading,

                keyboardType: TextInputType.number,

                textAlign: TextAlign.center,

                textInputAction:
                TextInputAction.next,

                autofillHints: const [
                  AutofillHints.oneTimeCode,
                ],

                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],

                validator: _validateOtp,

                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 8,
                  color: ResetColors.navy,
                ),

                decoration: _fieldDecoration(
                  hint: '000000',
                  icon: Icons.password_outlined,
                ).copyWith(
                  hintStyle: const TextStyle(
                    color: Color(0xFFB3C5CC),
                    letterSpacing: 8,
                  ),
                ),
              ),

              const SizedBox(height: 13),

              // ----------------------------------------------
              // OTP EXPIRY
              // ----------------------------------------------

              Center(
                child: Text(
                  _otpExpirySeconds > 0
                      ? 'OTP expires in ${_formatSeconds(_otpExpirySeconds)}'
                      : 'OTP expired. Request a new code.',

                  textAlign: TextAlign.center,

                  style: TextStyle(
                    color: _otpExpirySeconds > 0
                        ? ResetColors.primary
                        : ResetColors.error,

                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // ----------------------------------------------
              // RESEND OTP
              // ----------------------------------------------

              Center(
                child: TextButton(
                  onPressed: _isLoading ||
                      _resendSeconds > 0
                      ? null
                      : _resendOtp,

                  child: Text(
                    _resendSeconds > 0
                        ? 'Resend OTP in $_resendSeconds seconds'
                        : 'Resend OTP',

                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ----------------------------------------------
              // NEW PASSWORD
              // ----------------------------------------------

              const Text(
                'New Password',

                style: TextStyle(
                  color: ResetColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 9),

              TextFormField(
                controller: _newPasswordController,

                enabled: !_isLoading,

                obscureText: !_showNewPassword,

                enableSuggestions: false,
                autocorrect: false,

                textInputAction:
                TextInputAction.next,

                autofillHints: const [
                  AutofillHints.newPassword,
                ],

                inputFormatters: [
                  LengthLimitingTextInputFormatter(128),
                ],

                validator: _validateNewPassword,

                onChanged: (_) {
                  if (_passwordSubmitted) {
                    _passwordFormKey.currentState
                        ?.validate();
                  }
                },

                decoration: _fieldDecoration(
                  hint: 'Enter your new password',
                  icon: Icons.lock_outline,

                  suffix: IconButton(
                    tooltip: _showNewPassword
                        ? 'Hide password'
                        : 'Show password',

                    onPressed: () {
                      setState(() {
                        _showNewPassword =
                        !_showNewPassword;
                      });
                    },

                    icon: Icon(
                      _showNewPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,

                      color: ResetColors.muted,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Password must contain 8 to 128 characters.',

                style: TextStyle(
                  color: ResetColors.muted,
                  fontSize: 11,
                ),
              ),

              const SizedBox(height: 19),

              // ----------------------------------------------
              // CONFIRM NEW PASSWORD
              // ----------------------------------------------

              const Text(
                'Confirm New Password',

                style: TextStyle(
                  color: ResetColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 9),

              TextFormField(
                controller:
                _confirmPasswordController,

                enabled: !_isLoading,

                obscureText: !_showConfirmPassword,

                enableSuggestions: false,
                autocorrect: false,

                textInputAction:
                TextInputAction.done,

                autofillHints: const [
                  AutofillHints.newPassword,
                ],

                inputFormatters: [
                  LengthLimitingTextInputFormatter(128),
                ],

                validator:
                _validateConfirmPassword,

                onFieldSubmitted: (_) {
                  _resetPassword();
                },

                decoration: _fieldDecoration(
                  hint: 'Re-enter your new password',
                  icon: Icons.lock_reset_outlined,

                  suffix: IconButton(
                    tooltip: _showConfirmPassword
                        ? 'Hide password'
                        : 'Show password',

                    onPressed: () {
                      setState(() {
                        _showConfirmPassword =
                        !_showConfirmPassword;
                      });
                    },

                    icon: Icon(
                      _showConfirmPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,

                      color: ResetColors.muted,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 26),

              // ----------------------------------------------
              // RESET BUTTON
              // ----------------------------------------------

              _buildPrimaryButton(
                title: 'Reset Password',
                icon: Icons.verified_outlined,
                onPressed: _resetPassword,
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        Center(
          child: TextButton.icon(
            onPressed: _isLoading
                ? null
                : _editEmail,

            icon: const Icon(
              Icons.edit_outlined,
              size: 17,
            ),

            label: const Text(
              'Change Email Address',
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // STEP 3 - PASSWORD RESET SUCCESS
  // ==========================================================

  Widget _buildCompletedStep() {
    return Column(
      children: [
        const SizedBox(height: 12),

        Container(
          padding: const EdgeInsets.all(20),

          decoration: const BoxDecoration(
            color: ResetColors.lightTeal,
            shape: BoxShape.circle,
          ),

          child: const Icon(
            Icons.check_circle_rounded,
            color: ResetColors.primary,
            size: 65,
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'Password Reset Successful!',

          textAlign: TextAlign.center,

          style: TextStyle(
            color: ResetColors.text,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),

        const SizedBox(height: 15),

        const Text(
          'Your password has been updated successfully.\n'
              'You can now sign in using your new password.',

          textAlign: TextAlign.center,

          style: TextStyle(
            color: ResetColors.muted,
            fontSize: 14,
            height: 1.7,
          ),
        ),

        const SizedBox(height: 22),

        _buildInfoBox(
          'For your security, previous login sessions '
              'have been revoked. Please sign in again.',
        ),

        const SizedBox(height: 28),

        _buildPrimaryButton(
          title: 'Back to Login',
          icon: Icons.login_rounded,
          onPressed: _backToLogin,
        ),
      ],
    );
  }

  // ==========================================================
  // SHARED TEXT FIELD DECORATION
  // ==========================================================

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    OutlineInputBorder outline(
        Color color,
        double width,
        ) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),

        borderSide: BorderSide(
          color: color,
          width: width,
        ),
      );
    }

    return InputDecoration(
      hintText: hint,

      hintStyle: const TextStyle(
        color: Color(0xFF9DAFB8),
        fontSize: 13,
      ),

      prefixIcon: Icon(
        icon,
        color: ResetColors.primary,
        size: 21,
      ),

      suffixIcon: suffix,

      filled: true,

      fillColor: const Color(0xFFF8FBFC),

      contentPadding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 17,
      ),

      border: outline(
        ResetColors.border,
        1,
      ),

      enabledBorder: outline(
        ResetColors.border,
        1,
      ),

      focusedBorder: outline(
        ResetColors.primary,
        1.7,
      ),

      errorBorder: outline(
        ResetColors.error,
        1,
      ),

      focusedErrorBorder: outline(
        ResetColors.error,
        1.5,
      ),

      errorMaxLines: 2,
    );
  }

  // ==========================================================
  // PRIMARY BUTTON
  // ==========================================================

  Widget _buildPrimaryButton({
    required String title,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,

      child: FilledButton(
        onPressed: _isLoading ? null : onPressed,

        style: FilledButton.styleFrom(
          backgroundColor: ResetColors.primary,

          foregroundColor: Colors.white,

          disabledBackgroundColor:
          ResetColors.primary.withValues(
            alpha: 0.65,
          ),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),

        child: _isLoading
            ? const SizedBox(
          height: 22,
          width: 22,

          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white,
          ),
        )
            : Row(
          mainAxisAlignment:
          MainAxisAlignment.center,

          mainAxisSize: MainAxisSize.min,

          children: [
            Flexible(
              child: Text(
                title,

                textAlign: TextAlign.center,

                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),

            const SizedBox(width: 9),

            Icon(
              icon,
              size: 19,
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // INFORMATION BOX
  // ==========================================================

  Widget _buildInfoBox(String message) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(15),

      decoration: BoxDecoration(
        color: ResetColors.lightTeal,

        borderRadius: BorderRadius.circular(13),

        border: Border.all(
          color: const Color(0xFFD5EEEA),
        ),
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: ResetColors.primary,
            size: 21,
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Text(
              message,

              style: const TextStyle(
                color: ResetColors.text,
                fontSize: 12.5,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}