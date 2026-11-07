
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../doctor/doctor_dashboard_screen.dart';
import '../doctor/doctor_profile_setup_screen.dart';

// ============================================================
// FAMILYCARE+ EMAIL OTP VERIFICATION
// ============================================================
// Compatible with the updated SignupScreen constructor.
// Patient: POST /api/v1/patients/verify-email, /resend-otp
// Doctor:  POST /api/v1/doctors/verify-email, /resend-otp
// Patient OTP -> login (or existing caller callback).
// Doctor OTP -> complete professional profile (not admin approval yet).
// After submission -> limited doctor dashboard; clinical routes locked.
// ============================================================

class OTPColors {
  static const primary = Color(0xFF078F81);
  static const accent = Color(0xFF13AA9C);
  static const navy = Color(0xFF103E51);
  static const background = Color(0xFFF1F7F9);
  static const white = Colors.white;
  static const text = Color(0xFF173D4D);
  static const muted = Color(0xFF6A8290);
  static const border = Color(0xFFDCE7EC);
  static const lightTeal = Color(0xFFEAF8F5);
  static const error = Color(0xFFB7434E);
}

class OTPApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const OTPApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}

class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final String challengeToken;
  final String apiBaseUrl;
  final bool? isDoctor;
  final String? accountType;
  final int resendAfter;
  final int expiresIn;

  // Optional PATIENT integration hook: patient callers can preserve their
  // existing navigation. Doctor verification always opens profile setup
  // so legacy callbacks cannot skip the required onboarding step.
  final void Function(
      BuildContext context,
      bool isDoctor,
      Map<String, dynamic> response,
      )? onVerified;

  const OtpVerificationScreen({
    super.key,
    required this.email,
    required this.challengeToken,
    required this.apiBaseUrl,
    this.isDoctor,
    this.accountType,
    this.resendAfter = 60,
    this.expiresIn = 300,
    this.onVerified,
  });

  @override
  State<OtpVerificationScreen> createState() =>
      _OtpVerificationScreenState();
}

class _OtpVerificationScreenState
    extends State<OtpVerificationScreen> {
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();
  final _client = http.Client();

  late String _challengeToken;
  late DateTime _expiresAt;
  late DateTime _resendAt;

  Timer? _ticker;
  bool _loading = false;
  bool _verified = false;
  bool _navigating = false;
  Map<String, dynamic>? _doctorVerification;
  String? _inlineError;

  bool get _doctor =>
      widget.isDoctor ??
          (widget.accountType?.trim().toLowerCase() == 'doctor');

  String get _apiRole => _doctor ? 'doctors' : 'patients';

  String get _baseUrl => widget.apiBaseUrl
      .trim()
      .replaceAll(RegExp(r'/+$'), '');

  int _secondsUntil(DateTime target) {
    final milliseconds = target.difference(DateTime.now()).inMilliseconds;
    return milliseconds <= 0 ? 0 : (milliseconds + 999) ~/ 1000;
  }

  int get _expirySeconds => _secondsUntil(_expiresAt);
  int get _resendSeconds => _secondsUntil(_resendAt);

  @override
  void initState() {
    super.initState();
    _challengeToken = widget.challengeToken.trim();
    _setDeadlines(
      resendAfter: widget.resendAfter,
      expiresIn: widget.expiresIn,
    );
    _otpController.addListener(_onOtpChanged);
    _startTicker();
  }

  void _onOtpChanged() {
    if (mounted && !_verified) {
      setState(() {
        _inlineError = null;
      });
    }
  }

  void _setDeadlines({
    required int resendAfter,
    required int expiresIn,
  }) {
    final now = DateTime.now();
    _resendAt = now.add(
      Duration(seconds: resendAfter.clamp(0, 3600).toInt()),
    );
    _expiresAt = now.add(
      Duration(seconds: expiresIn.clamp(0, 3600).toInt()),
    );
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _verified) {
        timer.cancel();
        return;
      }
      setState(() {});
      if (_resendSeconds == 0 && _expirySeconds == 0) {
        timer.cancel();
      }
    });
  }

  int _readSeconds(dynamic value, int fallback) {
    if (value is num && value >= 0) {
      return value.toInt().clamp(0, 3600).toInt();
    }
    return fallback;
  }

  String _formatTime(int seconds) {
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder';
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _otpController.removeListener(_onOtpChanged);
    _otpController.dispose();
    _otpFocusNode.dispose();
    _client.close();
    super.dispose();
  }

  // ==========================================================
  // API REQUEST AND ERROR HANDLING
  // ==========================================================

  Future<Map<String, dynamic>> _post(
      String action,
      Map<String, dynamic> payload,
      ) async {
    if (_baseUrl.isEmpty) {
      throw const OTPApiException(
        statusCode: 0,
        code: 'missing_base_url',
        message: 'Backend URL is not configured.',
      );
    }

    final uri = Uri.parse('$_baseUrl/api/v1/$_apiRole/$action');
    final response = await _client
        .post(
      uri,
      headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Auth-Transport': 'bearer',
      },
      body: jsonEncode(payload),
    )
        .timeout(const Duration(seconds: 30));

    Map<String, dynamic>? decoded;
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map) {
        decoded = Map<String, dynamic>.from(value);
      }
    } catch (_) {
      // An upstream proxy may return HTML instead of JSON.
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var code = 'request_failed';
      var message = 'Request failed (HTTP ${response.statusCode}).';
      final details = decoded?['error'];

      if (details is Map) {
        if (details['code'] is String) {
          code = details['code'] as String;
        }
        if (details['message'] is String &&
            (details['message'] as String).trim().isNotEmpty) {
          message = details['message'] as String;
        }
      } else if (details is String && details.trim().isNotEmpty) {
        message = details;
      }

      if (response.statusCode == 429 && details == null) {
        message = 'Too many attempts. Please try again later.';
      } else if (response.statusCode >= 500 && details == null) {
        message = 'The FamilyCare+ server is temporarily unavailable.';
      }

      throw OTPApiException(
        statusCode: response.statusCode,
        code: code,
        message: message,
      );
    }

    if (decoded == null) {
      throw const OTPApiException(
        statusCode: 0,
        code: 'invalid_response',
        message: 'Invalid response received from the server.',
      );
    }
    return decoded;
  }

  String _friendlyError(Object error) {
    if (error is OTPApiException) return error.message;
    if (error is TimeoutException) {
      return 'Server response timed out. Please try again.';
    }
    if (error is http.ClientException) {
      return 'Unable to connect to the server. Check your connection.';
    }
    if (error is FormatException) {
      return 'The server sent an unexpected response.';
    }
    return 'Something went wrong. Please try again.';
  }

  void _showError(Object error) {
    if (!mounted) return;
    setState(() => _inlineError = _friendlyError(error));
  }

  // ==========================================================
  // VERIFY OTP
  // ==========================================================

  Future<void> _verifyOtp() async {
    if (_loading || _verified || _navigating) return;

    final otp = _otpController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      _showError(const OTPApiException(
        statusCode: 0,
        code: 'invalid_otp_format',
        message: 'Enter the complete 6-digit email OTP.',
      ));
      return;
    }
    if (_expirySeconds <= 0) {
      _showError(const OTPApiException(
        statusCode: 0,
        code: 'expired_otp',
        message: 'OTP expired. Please request a new code.',
      ));
      return;
    }
    if (_challengeToken.isEmpty) {
      _showError(const OTPApiException(
        statusCode: 0,
        code: 'missing_challenge',
        message: 'Verification session is unavailable.',
      ));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _inlineError = null;
    });

    try {
      final response = await _post('verify-email', {
        'challenge_token': _challengeToken,
        'otp': otp,
      });

      if (!mounted) return;

      if (_doctor) {
        // The doctor has NOT been submitted for approval yet. The backend
        // returns a short-lived onboarding token for profile completion.
        final setupToken = (response['setup_token'] ?? '').toString().trim();
        final user = _asMap(response['user']);
        final status = (user['approval_status'] ?? '').toString().toUpperCase();
        if (setupToken.isEmpty ||
            user['role'] != 'DOCTOR' ||
            status != 'PROFILE_REQUIRED' ||
            response['requires_profile_setup'] != true) {
          throw const OTPApiException(
            statusCode: 0,
            code: 'missing_setup_response',
            message: 'Email verification succeeded, but profile setup data '
                'was incomplete. Sign in again as Doctor to resume setup.',
          );
        }
      }

      _ticker?.cancel();
      setState(() {
        _verified = true;
        _doctorVerification = _doctor ? response : null;
        _challengeToken = '';
        _otpController.clear();
      });

      // The doctor's setup page must not be skipped by an old callback
      // that routes directly to an approval-pending page.
      if (!_doctor && widget.onVerified != null) {
        widget.onVerified!(context, false, response);
        return;
      }

      // Briefly show the success state before switching screens.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) _goToDestination();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ==========================================================
  // RESEND OTP
  // ==========================================================

  Future<void> _resendOtp() async {
    if (_loading || _verified || _resendSeconds > 0) return;
    if (_challengeToken.isEmpty) {
      _showError(const OTPApiException(
        statusCode: 0,
        code: 'missing_challenge',
        message: 'Verification session is unavailable.',
      ));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _inlineError = null;
    });

    try {
      final response = await _post('resend-otp', {
        'challenge_token': _challengeToken,
      });
      final newToken = response['challenge_token'];
      if (newToken is! String || newToken.trim().isEmpty) {
        throw const OTPApiException(
          statusCode: 0,
          code: 'missing_challenge',
          message: 'New OTP challenge was not returned.',
        );
      }
      if (!mounted) return;

      _setDeadlines(
        resendAfter: _readSeconds(response['resend_after'], 60),
        expiresIn: _readSeconds(response['expires_in'], 300),
      );
      setState(() {
        _challengeToken = newToken;
        _otpController.clear();
      });
      _startTicker();
      _otpFocusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A new verification code was sent to your email.'),
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ==========================================================
  // NAVIGATION
  // ==========================================================

  static Map<String, dynamic> _asMap(dynamic raw) {
    return raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
  }

  void _goToDestination() {
    if (!mounted || _navigating || !_verified) return;

    if (_doctor) {
      final payload = _doctorVerification;
      final setupToken = (payload?['setup_token'] ?? '').toString().trim();
      if (payload == null || setupToken.isEmpty) {
        setState(() {
          _inlineError = 'The doctor setup session is unavailable. '
              'Sign in again as Doctor to resume onboarding.';
        });
        return;
      }
      _navigating = true;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => _DoctorOnboardingFlow(
            verification: payload,
            apiBaseUrl: _baseUrl,
          ),
        ),
            (route) => false,
      );
      return;
    }

    _navigating = true;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
          (route) => false,
    );
  }

  Future<void> _confirmLeave() async {
    if (_loading || _navigating) return;
    if (_verified) {
      _goToDestination();
      return;
    }

    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave verification?'),
        content: const Text(
          'Your registration is not complete until your email is verified. '
              'If you leave, your verification challenge may expire.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep verifying'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );

    if (leave == true && mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
            (route) => false,
      );
    }
  }

  // ==========================================================
  // UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: OTPColors.background,
        appBar: AppBar(
          title: const Text(
            'Email Verification',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          leading: IconButton(
            tooltip: 'Back to Login',
            onPressed: _loading ? null : _confirmLeave,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 17,
                vertical: 22,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        color: OTPColors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: OTPColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: OTPColors.navy.withValues(alpha: 0.05),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: _verified ? _successContent() : _otpContent(),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'FamilyCare+ • Healthier Families. Brighter Tomorrows.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: OTPColors.muted, fontSize: 11),
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

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [OTPColors.navy, OTPColors.primary, OTPColors.accent],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_rounded, color: Colors.white, size: 30),
              SizedBox(width: 11),
              Expanded(
                child: Text(
                  'FamilyCare+',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 21,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            _verified ? 'Email verified!' : 'Verify your email',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 26,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _verified
                ? (_doctor ? 'Email verification is complete. Profile setup is next.' : 'Your registration is complete.')
                : 'One last step to secure your account.',
            style: const TextStyle(color: Color(0xFFE4F5F3), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _otpContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: CircleAvatar(
            radius: 39,
            backgroundColor: OTPColors.lightTeal,
            child: Icon(
              Icons.mark_email_read_outlined,
              color: OTPColors.primary,
              size: 43,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Email Verification',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: OTPColors.text,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Enter the 6-digit code sent to',
          textAlign: TextAlign.center,
          style: TextStyle(color: OTPColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 6),
        SelectableText(
          widget.email,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: OTPColors.primary,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 25),
        TextField(
          controller: _otpController,
          focusNode: _otpFocusNode,
          enabled: !_loading,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(
            fontSize: 25,
            letterSpacing: 8,
            fontWeight: FontWeight.w800,
            color: OTPColors.navy,
          ),
          decoration: InputDecoration(
            hintText: '000000',
            hintStyle: const TextStyle(
              color: Color(0xFFB3C5CC),
              letterSpacing: 8,
            ),
            filled: true,
            fillColor: const Color(0xFFF8FBFC),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 19),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: OTPColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide:
              const BorderSide(color: OTPColors.primary, width: 1.8),
            ),
          ),
          onSubmitted: (_) => _verifyOtp(),
        ),
        const SizedBox(height: 17),
        Text(
          _expirySeconds > 0
              ? 'OTP expires in ${_formatTime(_expirySeconds)}'
              : 'OTP expired. Please request a new code.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _expirySeconds > 0 ? OTPColors.primary : OTPColors.error,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_inlineError != null) ...[
          const SizedBox(height: 14),
          _errorPanel(_inlineError!),
        ],
        const SizedBox(height: 23),
        _primaryButton(
          label: 'Verify Email OTP',
          icon: Icons.verified_outlined,
          onPressed: _otpController.text.length == 6 &&
              _expirySeconds > 0 &&
              !_loading
              ? _verifyOtp
              : null,
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _loading || _resendSeconds > 0 ? null : _resendOtp,
          child: Text(
            _resendSeconds > 0
                ? 'Resend OTP in ${_formatTime(_resendSeconds)}'
                : 'Resend OTP',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 5),
        TextButton.icon(
          onPressed: _loading ? null : _confirmLeave,
          icon: const Icon(Icons.arrow_back_rounded, size: 17),
          label: const Text('Back to Login'),
        ),
        if (_doctor) ...[
          const SizedBox(height: 14),
          _infoPanel(
            'After email verification, complete your doctor profile '
                'and upload documents. Admin review starts after submission.',
          ),
        ],
      ],
    );
  }

  Widget _successContent() {
    return Column(
      children: [
        const CircleAvatar(
          radius: 48,
          backgroundColor: OTPColors.lightTeal,
          child: Icon(
            Icons.check_circle_rounded,
            color: OTPColors.primary,
            size: 66,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          _doctor ? 'Email Verified Successfully!' : 'Registration Successful!',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: OTPColors.text,
            fontSize: 23,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _doctor
              ? 'Email verified. Complete your professional profile and upload documents before admin review.'
              : 'Your patient account is verified. Sign in to continue.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: OTPColors.muted,
            fontSize: 14,
            height: 1.6,
          ),
        ),
        if (_doctor) ...[
          const SizedBox(height: 19),
          _infoPanel('Next step: Complete your doctor profile'),
        ],
        const SizedBox(height: 23),
        _primaryButton(
          label: _doctor ? 'Complete Doctor Profile' : 'Continue to Login',
          icon: Icons.arrow_forward_rounded,
          onPressed: _goToDestination,
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: _loading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: OTPColors.primary,
          foregroundColor: OTPColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
        child: _loading
            ? const SizedBox(
          height: 21,
          width: 21,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: OTPColors.white,
          ),
        )
            : Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Icon(icon, size: 19),
          ],
        ),
      ),
    );
  }

  Widget _errorPanel(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: OTPColors.error, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: OTPColors.error,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPanel(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OTPColors.lightTeal,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD5EEEA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: OTPColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: OTPColors.text,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// DOCTOR ONBOARDING FLOW AFTER OTP
// ============================================================
// This route keeps the setup screen mounted when the doctor switches between
// Dashboard and Set My Profile. The setup token remains in memory only.
// No setup token is used as a clinical token. The doctor dashboard independently
// verifies an approved session before enabling clinical navigation.
// ============================================================

class _DoctorOnboardingFlow extends StatefulWidget {
  final Map<String, dynamic> verification;
  final String apiBaseUrl;

  const _DoctorOnboardingFlow({
    required this.verification,
    required this.apiBaseUrl,
  });

  @override
  State<_DoctorOnboardingFlow> createState() => _DoctorOnboardingFlowState();
}

class _DoctorOnboardingFlowState extends State<_DoctorOnboardingFlow> {
  late final Map<String, dynamic> _initialUser;
  late final Map<String, dynamic> _initialDoctor;
  late String _setupToken;
  late String _approvalStatus;
  bool _showProfile = true;

  @override
  void initState() {
    super.initState();
    _initialUser = _map(widget.verification['user']);
    _initialDoctor = _map(widget.verification['doctor']);
    _setupToken = (widget.verification['setup_token'] ?? '').toString().trim();
    _approvalStatus =
        (_initialUser['approval_status'] ?? 'PROFILE_REQUIRED')
            .toString()
            .toUpperCase();
  }

  static Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  void _showDashboard() {
    if (mounted) setState(() => _showProfile = false);
  }

  void _showSetup() {
    if (mounted) setState(() => _showProfile = true);
  }

  void _submitted(Map<String, dynamic> result) {
    final user = _map(result['user']);
    if (!mounted) return;
    setState(() {
      // Keep both the limited dashboard AND the profile's read-only
      // state in sync after the server confirms submission.
      _initialUser.addAll(user);
      _approvalStatus =
          (user['approval_status'] ?? 'PENDING_APPROVAL')
              .toString()
              .toUpperCase();
      _initialUser['approval_status'] = _approvalStatus;
      // Setup tokens are one-time onboarding credentials. They are
      // no longer needed after successful profile submission.
      _setupToken = '';
      _showProfile = false;
    });
  }

  void _goToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      '/login',
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack preserves uploaded-image/form state when switching tabs.
    // The approved-only dashboard does not unlock clinical routes here.
    return IndexedStack(
      index: _showProfile ? 1 : 0,
      children: [
        DoctorDashboardScreen(
          doctorName: (_initialUser['full_name'] ?? '').toString(),
          email: (_initialUser['email'] ?? '').toString(),
          approvalStatus: _approvalStatus,
          doctorDetails: _initialDoctor,
          apiBaseUrl: widget.apiBaseUrl,
          onOpenProfile: _showSetup,
          onGoToLogin: _goToLogin,
        ),
        DoctorProfileSetupScreen(
          setupToken: _setupToken,
          initialUser: _initialUser,
          initialDoctor: _initialDoctor,
          approvalStatus: (_initialUser['approval_status'] ?? 'PROFILE_REQUIRED')
              .toString(),
          rejectionReason: widget.verification['rejection_reason']?.toString(),
          apiBaseUrl: widget.apiBaseUrl,
          onSubmitted: _submitted,
          onBackToDashboard: _showDashboard,
        ),
      ],
    );
  }
}
