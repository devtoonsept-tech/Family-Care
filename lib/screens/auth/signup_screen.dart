import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'otp_verification.dart';

// ============================================================
// FAMILYCARE+ SIGNUP SCREEN
// NAVY + MINT THEME
// ============================================================
//
// Patient:
// Personal Details -> Register API -> Email OTP -> Patient login
//
// Doctor:
// Personal Details -> Professional Details -> Register API -> Email OTP
// -> Doctor Profile Setup (prefilled professional fields, addresses,
//    experience, profile photo, degree certificate) -> Admin review.
//
// Backend v5 supports OPTIONAL professional details during registration.
// These values are preserved through OTP verification and returned in the
// doctor profile so the doctor does not have to type them a second time.
// Approval is NOT requested until setup-profile is submitted.
//
// Family image:
// assets/images/signup_family.png
//
// ============================================================

// ============================================================
// SIGNUP ROLE
// ============================================================

enum SignupRole {
  patient,
  doctor,
}

// ============================================================
// DOCTOR REGISTRATION TYPE
// ============================================================

enum DoctorRegistrationType {
  stateCouncil,
  nationalNmr,
}

// ============================================================
// SIGNUP STEP
// ============================================================

enum _SignupPage {
  personal,
  professional,
}

// ============================================================
// NAVY + MINT COLOR PALETTE
// ============================================================

class FCColors {
  static const navy = Color(0xFF102C4B);
  static const deepNavy = Color(0xFF081F37);

  static const primary = Color(0xFF63DDC8);
  static const accent = Color(0xFFB9F2E8);

  static const background = Color(0xFFF3FAF9);
  static const white = Colors.white;

  static const text = Color(0xFF102C4B);
  static const muted = Color(0xFF63798A);
  static const border = Color(0xFFD7E6E9);

  static const lightTeal = Color(0xFFE8F9F5);
  static const error = Color(0xFFB74250);
}

// ============================================================
// SIGNUP DATA
// ============================================================

class SignupData {
  final SignupRole role;

  final String name;
  final String mobile;
  final String email;
  final String password;
  final String confirmPassword;

  final String? qualification;
  final String? registrationNumber;
  final String? registeringCouncil;
  final String? specialization;
  final String? nmrId;

  const SignupData({
    required this.role,
    required this.name,
    required this.mobile,
    required this.email,
    required this.password,
    required this.confirmPassword,
    this.qualification,
    this.registrationNumber,
    this.registeringCouncil,
    this.specialization,
    this.nmrId,
  });

  // ==========================================================
  // FLASK REGISTRATION PAYLOAD
  // ==========================================================
  // The backend supports the optional professional fields here, and
  // carries them through OTP to the DoctorProfileSetupScreen.
  // Images, clinic address and years of experience are submitted later.

  Map<String, dynamic> toApiJson() {
    final data = <String, dynamic>{
      'full_name': name,
      'mobile_number': mobile,
      'email': email,
      'password': password,
      'confirm_password': confirmPassword,
    };

    if (role == SignupRole.doctor) {
      data['qualification'] = qualification;

      data['medical_registration_number'] =
          registrationNumber;

      data['registering_council'] =
          registeringCouncil;

      if (specialization != null &&
          specialization!.isNotEmpty) {
        data['specialization'] = specialization;
      }

      if (nmrId != null && nmrId!.isNotEmpty) {
        data['nmr_id'] = nmrId;
      }
    }

    return data;
  }
}

// ============================================================
// SIGNUP API EXCEPTION
// ============================================================

class SignupApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const SignupApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}

// ============================================================
// SIGNUP SCREEN
// ============================================================

class SignupScreen extends StatefulWidget {
  final String apiBaseUrl;
  final ValueChanged<SignupData>? onContinue;

  const SignupScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.onContinue,
  });

  @override
  State<SignupScreen> createState() =>
      _SignupScreenState();
}

// ============================================================
// SIGNUP SCREEN STATE
// ============================================================

class _SignupScreenState extends State<SignupScreen> {
  // ==========================================================
  // FAMILY IMAGE
  // ==========================================================

  static const String _heroAsset =
      'assets/images/signup_family.png';

  // ==========================================================
  // DOCTOR QUALIFICATIONS
  // ==========================================================

  static const _qualifications = <String>[
    'MBBS',
    'MD',
    'MS',
    'DNB',
    'DrNB',
    'DM',
    'MCh',
    'MBBS, MD',
    'MBBS, MS',
    'MBBS, DNB',
    'MD, DM',
    'MS, MCh',
    'BDS',
    'MDS',
    'BAMS',
    'MD (Ayurveda)',
    'BHMS',
    'MD (Homoeopathy)',
    'BUMS',
    'BSMS',
    'BNYS',
  ];

  // ==========================================================
  // SPECIALIZATIONS
  // ==========================================================

  static const _specializations = <String>[
    'General Medicine',
    'Internal Medicine',
    'Family Medicine',
    'General Surgery',
    'Pediatrics',
    'Neonatology',
    'Obstetrics and Gynecology',
    'Cardiology',
    'Neurology',
    'Neurosurgery',
    'Orthopedics',
    'Dermatology',
    'Psychiatry',
    'Ophthalmology',
    'ENT',
    'Anesthesiology',
    'Radiology',
    'Pathology',
    'Emergency Medicine',
    'Critical Care Medicine',
    'Pulmonology',
    'Nephrology',
    'Urology',
    'Gastroenterology',
    'Endocrinology',
    'Rheumatology',
    'Oncology',
    'Hematology',
    'Plastic Surgery',
    'Dentistry',
    'Orthodontics',
    'Oral and Maxillofacial Surgery',
    'Ayurveda',
    'Homoeopathy',
    'Unani Medicine',
    'Siddha Medicine',
    'Naturopathy',
  ];

  // ==========================================================
  // REGISTERING COUNCILS
  // ==========================================================

  static const _councils = <String>[
    'Andhra Pradesh Medical Council',
    'Assam Council of Medical Registration',
    'Bihar Medical Council',
    'Chhattisgarh Medical Council',
    'Delhi Medical Council',
    'Goa Medical Council',
    'Gujarat Medical Council',
    'Haryana Medical Council',
    'Himachal Pradesh Medical Council',
    'Jammu and Kashmir Medical Council',
    'Jharkhand State Medical Council',
    'Karnataka Medical Council',
    'Kerala State Medical Council',
    'Madhya Pradesh Medical Council',
    'Maharashtra Medical Council',
    'Odisha Council of Medical Registration',
    'Punjab Medical Council',
    'Rajasthan Medical Council',
    'Tamil Nadu Medical Council',
    'Telangana State Medical Council',
    'Uttar Pradesh Medical Council',
    'Uttarakhand Medical Council',
    'West Bengal Medical Council',
    'Dental Council / State Dental Council',
    'State AYUSH / Indian Medicine Board',
    'State Homoeopathic Council',
  ];

  // ==========================================================
  // FORM KEYS
  // ==========================================================

  final _personalForm = GlobalKey<FormState>();

  final _professionalForm = GlobalKey<FormState>();

  // ==========================================================
  // HTTP CLIENT
  // ==========================================================

  final http.Client _client = http.Client();

  // ==========================================================
  // PERSONAL DETAILS CONTROLLERS
  // ==========================================================

  final _name = TextEditingController();

  final _mobile = TextEditingController();

  final _email = TextEditingController();

  final _password = TextEditingController();

  final _confirmation = TextEditingController();

  // ==========================================================
  // PROFESSIONAL DETAILS CONTROLLERS
  // ==========================================================

  final _qualification = TextEditingController();

  final _registration = TextEditingController();

  final _council = TextEditingController();

  final _specialization = TextEditingController();

  final _nmr = TextEditingController();

  // ==========================================================
  // FOCUS NODES
  // ==========================================================

  final _qualificationFocus = FocusNode();

  final _specializationFocus = FocusNode();

  final _councilFocus = FocusNode();

  // ==========================================================
  // CURRENT STATE
  // ==========================================================

  SignupRole _role = SignupRole.patient;

  DoctorRegistrationType _registrationType =
      DoctorRegistrationType.stateCouncil;

  _SignupPage _page = _SignupPage.personal;

  bool _busy = false;

  bool _personalSubmitted = false;

  bool _professionalSubmitted = false;

  bool _showPassword = false;

  bool _showConfirmation = false;

  String? _error;

  bool get _isDoctor =>
      _role == SignupRole.doctor;

  String get _apiRole =>
      _isDoctor ? 'doctors' : 'patients';

  // ==========================================================
  // BACKEND BASE URL
  // ==========================================================

  String get _baseUrl {
    final configured = widget.apiBaseUrl.trim();

    if (configured.isNotEmpty) {
      return configured.replaceAll(
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
    _client.close();

    for (final controller in <TextEditingController>[
      _name,
      _mobile,
      _email,
      _password,
      _confirmation,
      _qualification,
      _registration,
      _council,
      _specialization,
      _nmr,
    ]) {
      controller.dispose();
    }

    _qualificationFocus.dispose();

    _specializationFocus.dispose();

    _councilFocus.dispose();

    super.dispose();
  }

  // ==========================================================
  // VALIDATE FULL NAME
  // ==========================================================

  String? _validateName(String? raw) {
    final text = (raw ?? '').trim();

    if (text.isEmpty) {
      return 'Enter your full name.';
    }

    if (text.length > 120) {
      return 'Maximum 120 characters.';
    }

    return null;
  }

  // ==========================================================
  // VALIDATE MOBILE NUMBER
  // ==========================================================

  String? _validateMobile(String? raw) {
    final text = (raw ?? '').trim();

    if (!RegExp(r'^\d{10}$').hasMatch(text)) {
      return 'Enter a valid 10-digit mobile number.';
    }

    return null;
  }

  // ==========================================================
  // VALIDATE EMAIL ADDRESS
  // ==========================================================

  String? _validateEmail(String? raw) {
    final text = (raw ?? '').trim();

    final pattern = RegExp(
      r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
    );

    if (!pattern.hasMatch(text)) {
      return 'Enter a valid email address.';
    }

    return null;
  }

  // ==========================================================
  // VALIDATE PASSWORD
  // ==========================================================

  String? _validatePassword(String? raw) {
    final text = raw ?? '';

    if (text.length < 8) {
      return 'Password must be at least 8 characters.';
    }

    if (text.length > 128) {
      return 'Maximum 128 characters.';
    }

    return null;
  }

  // ==========================================================
  // VALIDATE CONFIRM PASSWORD
  // ==========================================================

  String? _validateConfirmation(String? raw) {
    if ((raw ?? '').isEmpty) {
      return 'Please confirm your password.';
    }

    if (raw != _password.text) {
      return 'Passwords do not match.';
    }

    return null;
  }

  // ==========================================================
  // VALIDATE QUALIFICATION
  // ==========================================================

  String? _validateQualification(String? raw) {
    final text = (raw ?? '').trim();

    if (text.length < 2) {
      return 'Enter your medical qualification.';
    }

    if (text.length > 200) {
      return 'Maximum 200 characters.';
    }

    return null;
  }

  // ==========================================================
  // VALIDATE MEDICAL REGISTRATION NUMBER
  // ==========================================================

  String? _validateRegistration(String? raw) {
    final text = (raw ?? '').trim();

    final pattern = RegExp(
      r'^[A-Za-z0-9][A-Za-z0-9/ ._-]{1,99}$',
    );

    if (!pattern.hasMatch(text)) {
      return 'Enter a valid medical registration number.';
    }

    return null;
  }

  // ==========================================================
  // VALIDATE REGISTERING COUNCIL
  // ==========================================================

  String? _validateCouncil(String? raw) {
    final text = (raw ?? '').trim();

    if (text.length < 2) {
      return 'Registering council is required.';
    }

    if (text.length > 200) {
      return 'Maximum 200 characters.';
    }

    return null;
  }

  // ==========================================================
  // VALIDATE SPECIALIZATION
  // ==========================================================

  String? _validateSpecialization(String? raw) {
    final text = (raw ?? '').trim();

    if (text.length > 200) {
      return 'Maximum 200 characters.';
    }

    return null;
  }

  // ==========================================================
  // VALIDATE NMR ID
  // ==========================================================

  String? _validateNmr(String? raw) {
    final text = (raw ?? '').trim();

    if (_registrationType ==
        DoctorRegistrationType.nationalNmr &&
        text.isEmpty) {
      return 'NMR ID is required when National / NMR is selected.';
    }

    if (text.length > 100) {
      return 'Maximum 100 characters.';
    }

    return null;
  }

  // ==========================================================
  // FRIENDLY API ERROR MESSAGE
  // ==========================================================

  String _friendlyError(Object error) {
    if (error is SignupApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'Server timed out. Try again.';
    }

    if (error is http.ClientException) {
      return 'Cannot reach FamilyCare+. '
          'Check the API URL and CORS settings.';
    }

    if (error is FormatException) {
      return 'Invalid response from the server.';
    }

    return 'Something went wrong. Please try again.';
  }

  // ==========================================================
  // FLASK POST REQUEST
  // ==========================================================

  Future<Map<String, dynamic>> _post(
      String endpoint,
      Map<String, dynamic> payload,
      ) async {
    final response = await _client
        .post(
      Uri.parse('$_baseUrl$endpoint'),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(payload),
    )
        .timeout(
      const Duration(seconds: 35),
    );

    Map<String, dynamic>? data;

    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Non-JSON responses are handled using status codes.
    }

    // ========================================================
    // HANDLE HTTP ERROR
    // ========================================================

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final details = data?['error'];

      var code = 'request_failed';

      var message =
          'Request failed (HTTP ${response.statusCode}).';

      if (details is Map) {
        if (details['code'] is String) {
          code = details['code'] as String;
        }

        if (details['message'] is String) {
          message = details['message'] as String;
        }

        if (code == 'validation_error' &&
            details['fields'] is List) {
          final names = (details['fields'] as List)
              .whereType<Map>()
              .map((item) => item['field'])
              .whereType<String>()
              .toSet()
              .join(', ');

          if (names.isNotEmpty) {
            message = 'Please check: $names';
          }
        }
      }

      if (response.statusCode == 429) {
        message =
        'Too many attempts. Please try again later.';
      } else if (response.statusCode >= 500) {
        message =
        'FamilyCare+ server is temporarily unavailable.';
      }

      throw SignupApiException(
        statusCode: response.statusCode,
        code: code,
        message: message,
      );
    }

    if (data == null) {
      throw const SignupApiException(
        statusCode: 0,
        code: 'invalid_response',
        message:
        'The server returned invalid registration data.',
      );
    }

    return data;
  }

  // ==========================================================
  // COLLECT REGISTRATION DATA
  // ==========================================================

  SignupData _collectData() {
    return SignupData(
      role: _role,
      name: _name.text.trim(),
      mobile: '+91${_mobile.text.trim()}',
      email: _email.text.trim().toLowerCase(),
      password: _password.text,
      confirmPassword: _confirmation.text,
      qualification:
      _isDoctor ? _qualification.text.trim() : null,
      registrationNumber:
      _isDoctor ? _registration.text.trim() : null,
      registeringCouncil:
      _isDoctor ? _council.text.trim() : null,
      specialization:
      _isDoctor ? _specialization.text.trim() : null,
      nmrId:
      _isDoctor ? _nmr.text.trim() : null,
    );
  }

  // ==========================================================
  // PERSONAL DETAILS CONTINUE
  // ==========================================================

  void _nextPersonal() {
    if (_busy) return;

    setState(() {
      _personalSubmitted = true;
      _error = null;
    });

    if (!(_personalForm.currentState?.validate() ??
        false)) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    if (_isDoctor) {
      setState(() {
        _page = _SignupPage.professional;
      });
    } else {
      _register();
    }
  }

  // ==========================================================
  // PROFESSIONAL DETAILS CONTINUE
  // ==========================================================

  void _nextProfessional() {
    if (_busy) return;

    setState(() {
      _professionalSubmitted = true;
      _error = null;
    });

    if (!(_professionalForm.currentState?.validate() ??
        false)) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    _register();
  }

  // ==========================================================
  // REGISTER PATIENT / DOCTOR
  // ==========================================================

  Future<void> _register() async {
    if (_busy) return;

    final details = _collectData();

    if (widget.onContinue != null) {
      widget.onContinue!(details);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final response = await _post(
        '/api/v1/$_apiRole/register',
        details.toApiJson(),
      );

      final challenge =
      response['challenge_token'];

      if (challenge is! String ||
          challenge.trim().isEmpty) {
        throw const SignupApiException(
          statusCode: 0,
          code: 'missing_challenge',
          message:
          'OTP challenge was not returned. '
              'Contact support before registering again.',
        );
      }

      if (!mounted) return;

      final resend = response['resend_after'];
      final expiry = response['expires_in'];

      // ======================================================
      // OPEN SINGLE OTP SCREEN
      // ======================================================

      final destination = OtpVerificationScreen(
        email: details.email,
        challengeToken: challenge,
        isDoctor: _isDoctor,
        apiBaseUrl: _baseUrl,
        resendAfter:
        resend is num ? resend.toInt() : 60,
        expiresIn:
        expiry is num ? expiry.toInt() : 300,
      );

      _password.clear();
      _confirmation.clear();

      Navigator.of(context)
          .pushReplacement<void, void>(
        MaterialPageRoute<void>(
          builder: (_) => destination,
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  // ==========================================================
  // BACK NAVIGATION
  // ==========================================================

  void _back() {
    if (_busy) return;

    if (_page == _SignupPage.professional) {
      setState(() {
        _page = _SignupPage.personal;
        _error = null;
      });
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ==========================================================
  // LOGIN NAVIGATION
  // ==========================================================

  void _openLogin() {
    if (_busy) return;

    Navigator.of(context)
        .pushNamedAndRemoveUntil(
      '/login',
          (_) => false,
    );
  }

  // ==========================================================
  // MAIN SCREEN
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FCColors.background,

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= 800;

            return SingleChildScrollView(
              keyboardDismissBehavior:
              ScrollViewKeyboardDismissBehavior
                  .onDrag,

              padding: EdgeInsets.symmetric(
                horizontal: wide ? 26 : 14,
                vertical: wide ? 25 : 14,
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
                      // COMPACT FAMILY HERO
                      // ======================================

                      _hero(wide),

                      const SizedBox(height: 17),

                      // ======================================
                      // REGISTRATION FORM
                      // ======================================

                      Container(
                        padding: EdgeInsets.all(
                          wide ? 33 : 19,
                        ),

                        decoration: BoxDecoration(
                          color: FCColors.white,

                          borderRadius:
                          BorderRadius.circular(26),

                          border: Border.all(
                            color: FCColors.border,
                          ),

                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x10102C4B),
                              blurRadius: 28,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),

                        child:
                        _page == _SignupPage.personal
                            ? _personalPage()
                            : _professionalPage(),
                      ),

                      const SizedBox(height: 18),

                      const Text(
                        'FamilyCare+ • Families. Health. Together.',
                        textAlign: TextAlign.center,

                        style: TextStyle(
                          color: FCColors.muted,
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
  // COMPACT TWO-PANEL HERO
  // ==========================================================
  //
  // LEFT: Navy branding and short tagline.
  // RIGHT: Mother, father and infant photograph.
  //
  // No overlays on the image.
  //
  // ==========================================================

  Widget _hero(bool wide) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 360;

        final double heroHeight = wide
            ? 230
            : (compact ? 158 : 175);

        return ClipRRect(
          borderRadius:
          BorderRadius.circular(22),

          child: SizedBox(
            width: double.infinity,
            height: heroHeight,

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
                          FCColors.deepNavy,
                          FCColors.navy,
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
                          // FIRST HEADING
                          // ==================================

                          Text(
                            _page == _SignupPage.personal
                                ? 'Create Your'
                                : 'Join Our',

                            maxLines: 1,
                            overflow:
                            TextOverflow.ellipsis,

                            style: TextStyle(
                              color: Colors.white,

                              fontSize: wide
                                  ? 29
                                  : (compact ? 16 : 19),

                              fontWeight:
                              FontWeight.w900,

                              height: 1.12,
                            ),
                          ),

                          const SizedBox(height: 2),

                          // ==================================
                          // MINT HEADING
                          // ==================================

                          Text(
                            _page == _SignupPage.personal
                                ? 'Family Account'
                                : 'Care Network',

                            maxLines: 1,
                            overflow:
                            TextOverflow.ellipsis,

                            style: TextStyle(
                              color: FCColors.primary,

                              fontSize: wide
                                  ? 29
                                  : (compact ? 17 : 20),

                              fontWeight:
                              FontWeight.w900,

                              height: 1.1,
                            ),
                          ),

                          SizedBox(
                            height: wide ? 12 : 7,
                          ),

                          // ==================================
                          // SHORT TAGLINE
                          // ==================================

                          Text(
                            _page == _SignupPage.personal
                                ? 'Every little milestone matters.'
                                : 'Care that connects families.',

                            maxLines: 2,
                            overflow:
                            TextOverflow.ellipsis,

                            style: TextStyle(
                              color: const Color(
                                0xFFD7E9ED,
                              ),

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
                // RIGHT FAMILY PHOTO
                // ============================================

                Expanded(
                  flex: 11,

                  child: ColoredBox(
                    color: const Color(0xFFE6F9F4),

                    child: Image.asset(
                      _heroAsset,

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

                            size: 52,
                            color: FCColors.navy,
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
            color: FCColors.primary,

            borderRadius:
            BorderRadius.circular(9),
          ),

          child: Icon(
            Icons.favorite_rounded,

            size: large ? 21 : 16,

            color: FCColors.deepNavy,
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
  // REGISTRATION FORM HEADING
  // ==========================================================

  Widget _formHeader(
      String eyebrow,
      String title,
      ) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.center,

      children: [
        Expanded(
          child: Text(
            title,

            style: const TextStyle(
              color: FCColors.navy,

              fontSize: 23,

              fontWeight: FontWeight.w900,

              letterSpacing: -0.4,
            ),
          ),
        ),

        TextButton(
          onPressed:
          _busy ? null : _openLogin,

          child: const Text(
            'Log in',

            style: TextStyle(
              color: FCColors.navy,

              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // PATIENT / DOCTOR ROLE PICKER
  // ==========================================================

  Widget _rolePicker() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,

      children: [
        _label('Choose account type'),

        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _roleCard(
                SignupRole.patient,
                'Patient / Parent',
                Icons.people_alt_outlined,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: _roleCard(
                SignupRole.doctor,
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
      SignupRole role,
      String label,
      IconData icon,
      ) {
    final active = _role == role;

    return Material(
      color: active
          ? FCColors.lightTeal
          : const Color(0xFFFAFCFD),

      borderRadius:
      BorderRadius.circular(15),

      child: InkWell(
        borderRadius:
        BorderRadius.circular(15),

        onTap: _busy
            ? null
            : () {
          setState(() {
            _role = role;
            _personalSubmitted = false;
            _error = null;
          });
        },

        child: Container(
          height: 92,

          decoration: BoxDecoration(
            borderRadius:
            BorderRadius.circular(15),

            border: Border.all(
              color: active
                  ? FCColors.navy
                  : FCColors.border,

              width: active ? 1.8 : 1,
            ),
          ),

          child: Column(
            mainAxisAlignment:
            MainAxisAlignment.center,

            children: [
              Icon(
                icon,

                color: FCColors.navy,

                size: 25,
              ),

              const SizedBox(height: 9),

              Text(
                label,

                maxLines: 1,

                overflow:
                TextOverflow.ellipsis,

                style: const TextStyle(
                  fontSize: 13,

                  fontWeight: FontWeight.w800,

                  color: FCColors.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // REGISTRATION PROGRESS
  // ==========================================================

  Widget _progress() {
    final steps = _isDoctor
        ? const [
      'Personal Details',
      'Professional',
      'Email OTP',
      'Profile Setup',
    ]
        : const [
      'Personal Details',
      'Email OTP',
    ];

    final active =
    _page == _SignupPage.personal ? 0 : 1;

    return Row(
      children: List.generate(
        steps.length,
            (index) {
          final selected = index <= active;

          return Expanded(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 15,

                  backgroundColor: selected
                      ? FCColors.navy
                      : FCColors.border,

                  child: Text(
                    '${index + 1}',

                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : FCColors.muted,

                      fontWeight: FontWeight.w800,

                      fontSize: 12,
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                Flexible(
                  child: Text(
                    steps[index],

                    maxLines: 1,

                    overflow:
                    TextOverflow.ellipsis,

                    style: TextStyle(
                      fontSize: 10,

                      fontWeight: selected
                          ? FontWeight.w800
                          : FontWeight.w500,

                      color: selected
                          ? FCColors.navy
                          : FCColors.muted,
                    ),
                  ),
                ),

                if (index < steps.length - 1) ...[
                  const SizedBox(width: 5),

                  const Expanded(
                    child: Divider(
                      color: FCColors.border,
                      thickness: 2,
                    ),
                  ),

                  const SizedBox(width: 6),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // ==========================================================
  // PERSONAL REGISTRATION PAGE
  // ==========================================================

  Widget _personalPage() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,

      children: [
        _formHeader(
          'Join FamilyCare+ today',
          'Create an Account',
        ),

        const SizedBox(height: 14),

        _rolePicker(),

        const SizedBox(height: 15),

        _progress(),

        const SizedBox(height: 17),

        Form(
          key: _personalForm,

          autovalidateMode: _personalSubmitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,

          child: LayoutBuilder(
            builder: (context, constraints) {
              final two =
                  constraints.maxWidth >= 620;

              return Column(
                crossAxisAlignment:
                CrossAxisAlignment.stretch,

                children: [
                  // ==========================================
                  // FULL NAME AND MOBILE NUMBER
                  // ==========================================

                  _responsiveRow(
                    two,

                    _field(
                      label: 'Full Name',

                      hint: 'Enter your full name',

                      controller: _name,

                      icon:
                      Icons.person_outline_rounded,

                      validator: _validateName,

                      formatters: [
                        LengthLimitingTextInputFormatter(
                          120,
                        ),
                      ],
                    ),

                    _field(
                      label: 'Mobile Number',

                      hint: '10-digit mobile number',

                      controller: _mobile,

                      icon:
                      Icons.phone_iphone_rounded,

                      keyboardType:
                      TextInputType.phone,

                      prefixText: '+91  ',

                      validator: _validateMobile,

                      formatters: [
                        FilteringTextInputFormatter
                            .digitsOnly,

                        LengthLimitingTextInputFormatter(
                          10,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 17),

                  // ==========================================
                  // EMAIL
                  // ==========================================

                  _field(
                    label: 'Email Address',

                    hint: 'you@example.com',

                    controller: _email,

                    icon:
                    Icons.mail_outline_rounded,

                    keyboardType:
                    TextInputType.emailAddress,

                    validator: _validateEmail,
                  ),

                  const SizedBox(height: 17),

                  // ==========================================
                  // PASSWORD / CONFIRM PASSWORD
                  // ==========================================

                  _responsiveRow(
                    two,

                    _field(
                      label: 'Password',

                      hint: 'Minimum 8 characters',

                      controller: _password,

                      icon:
                      Icons.lock_outline_rounded,

                      obscure: !_showPassword,

                      validator: _validatePassword,

                      onChanged: (_) {
                        if (_personalSubmitted) {
                          _personalForm.currentState
                              ?.validate();
                        }
                      },

                      suffix: IconButton(
                        tooltip: _showPassword
                            ? 'Hide password'
                            : 'Show password',

                        onPressed: _busy
                            ? null
                            : () {
                          setState(() {
                            _showPassword =
                            !_showPassword;
                          });
                        },

                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),

                    _field(
                      label: 'Confirm Password',

                      hint: 'Repeat your password',

                      controller: _confirmation,

                      icon:
                      Icons.lock_outline_rounded,

                      obscure:
                      !_showConfirmation,

                      validator:
                      _validateConfirmation,

                      suffix: IconButton(
                        tooltip: _showConfirmation
                            ? 'Hide confirmation'
                            : 'Show confirmation',

                        onPressed: _busy
                            ? null
                            : () {
                          setState(() {
                            _showConfirmation =
                            !_showConfirmation;
                          });
                        },

                        icon: Icon(
                          _showConfirmation
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 19),

                  // ==========================================
                  // EMAIL OTP INFORMATION
                  // ==========================================

                  _info(
                    Icons.verified_user_outlined,

                    'We’ll email you a verification code. '
                        'Your +91 mobile number is for '
                        'contact purposes, not OTP.',
                  ),

                  const SizedBox(height: 17),

                  _errorBox(),

                  // ==========================================
                  // CONTINUE BUTTON
                  // ==========================================

                  _primaryButton(
                    _isDoctor
                        ? 'Next: Professional Details'
                        : 'Send Email OTP',

                    _nextPersonal,
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        _loginRow(),
      ],
    );
  }

  // ==========================================================
  // DOCTOR PROFESSIONAL REGISTRATION
  // ==========================================================

  Widget _professionalPage() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,

      children: [
        _formHeader(
          'Doctor registration',
          'Professional Details',
        ),

        const SizedBox(height: 22),

        _progress(),

        const SizedBox(height: 18),

        _info(
          Icons.person_outline_rounded,

          'Registering as ${_name.text.trim()}',
        ),

        const SizedBox(height: 19),

        Form(
          key: _professionalForm,

          autovalidateMode: _professionalSubmitted
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,

          child: LayoutBuilder(
            builder: (context, constraints) {
              final two =
                  constraints.maxWidth >= 620;

              return Column(
                crossAxisAlignment:
                CrossAxisAlignment.stretch,

                children: [
                  // ==========================================
                  // QUALIFICATION AND SPECIALIZATION
                  // ==========================================

                  _responsiveRow(
                    two,

                    _searchField(
                      'Qualification',
                      _qualification,
                      _qualificationFocus,
                      _qualifications,
                      Icons.school_outlined,
                      _validateQualification,
                    ),

                    _searchField(
                      'Specialization (Optional)',
                      _specialization,
                      _specializationFocus,
                      _specializations,
                      Icons.medical_information_outlined,
                      _validateSpecialization,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ==========================================
                  // REGISTRATION TYPE
                  // ==========================================

                  _label('Registration Type'),

                  const SizedBox(height: 9),

                  _responsiveRow(
                    two,

                    _registrationCard(
                      DoctorRegistrationType
                          .stateCouncil,

                      'State Medical Council',

                      'State registration number',

                      Icons.account_balance_outlined,
                    ),

                    _registrationCard(
                      DoctorRegistrationType
                          .nationalNmr,

                      'National / NMR',

                      'NMR ID + council details',

                      Icons.verified_user_outlined,
                    ),
                  ),

                  const SizedBox(height: 17),

                  // ==========================================
                  // MEDICAL REGISTRATION AND COUNCIL
                  // ==========================================

                  _responsiveRow(
                    two,

                    _field(
                      label:
                      'Medical Registration No.',

                      hint:
                      'Medical registration number',

                      controller: _registration,

                      icon: Icons.badge_outlined,

                      validator:
                      _validateRegistration,

                      formatters: [
                        LengthLimitingTextInputFormatter(
                          100,
                        ),
                      ],
                    ),

                    _searchField(
                      'Registering Council',
                      _council,
                      _councilFocus,
                      _councils,
                      Icons.account_balance_outlined,
                      _validateCouncil,
                    ),
                  ),

                  const SizedBox(height: 17),

                  // ==========================================
                  // NMR ID
                  // ==========================================

                  _field(
                    label: _registrationType ==
                        DoctorRegistrationType
                            .nationalNmr
                        ? 'NMR ID'
                        : 'NMR ID (Optional)',

                    hint:
                    'National Medical Register ID',

                    controller: _nmr,

                    icon: Icons.numbers_outlined,

                    validator: _validateNmr,

                    formatters: [
                      LengthLimitingTextInputFormatter(
                        100,
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // ==========================================
                  // DOCTOR APPROVAL INFORMATION
                  // ==========================================

                  _info(
                    Icons.info_outline_rounded,

                    'Medical Registration No. and Registering Council '
                        'are required by this form. After email OTP, these '
                        'professional details will be prefilled in your '
                        'Doctor Profile Setup. Upload your photo and degree '
                        'certificate, then submit your completed profile '
                        'for admin approval.',
                  ),

                  const SizedBox(height: 17),

                  _errorBox(),

                  // ==========================================
                  // BACK / CONTINUE BUTTONS
                  // ==========================================

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed:
                          _busy ? null : _back,

                          icon: const Icon(
                            Icons.arrow_back_rounded,

                            size: 18,
                          ),

                          label: const Text('Back'),

                          style:
                          OutlinedButton.styleFrom(
                            minimumSize:
                            const Size(0, 54),

                            foregroundColor:
                            FCColors.navy,

                            side: const BorderSide(
                              color: FCColors.border,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 11),

                      Expanded(
                        flex: 2,

                        child: _primaryButton(
                          'Verify Email & Continue',

                          _nextProfessional,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        _loginRow(),
      ],
    );
  }

  // ==========================================================
  // DOCTOR REGISTRATION TYPE CARD
  // ==========================================================

  Widget _registrationCard(
      DoctorRegistrationType type,
      String title,
      String subtitle,
      IconData icon,
      ) {
    final selected =
        _registrationType == type;

    return Material(
      color: selected
          ? FCColors.lightTeal
          : const Color(0xFFFAFCFD),

      borderRadius:
      BorderRadius.circular(14),

      child: InkWell(
        borderRadius:
        BorderRadius.circular(14),

        onTap: _busy
            ? null
            : () {
          setState(() {
            _registrationType = type;
            _error = null;
          });

          if (_professionalSubmitted) {
            _professionalForm.currentState
                ?.validate();
          }
        },

        child: Container(
          padding: const EdgeInsets.all(13),

          decoration: BoxDecoration(
            borderRadius:
            BorderRadius.circular(14),

            border: Border.all(
              color: selected
                  ? FCColors.navy
                  : FCColors.border,

              width: selected ? 1.8 : 1,
            ),
          ),

          child: Row(
            children: [
              Icon(
                icon,
                color: FCColors.navy,
              ),

              const SizedBox(width: 9),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Text(
                      title,

                      style: const TextStyle(
                        color: FCColors.navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,

                      style: const TextStyle(
                        color: FCColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),

              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,

                size: 18,

                color: selected
                    ? FCColors.navy
                    : FCColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // SEARCHABLE PROFESSIONAL FIELDS
  // ==========================================================

  Widget _searchField(
      String label,
      TextEditingController controller,
      FocusNode focus,
      List<String> options,
      IconData icon,
      String? Function(String?) validator,
      ) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,

      children: [
        _label(label),

        const SizedBox(height: 8),

        LayoutBuilder(
          builder: (context, constraints) {
            return RawAutocomplete<String>(
              textEditingController: controller,

              focusNode: focus,

              displayStringForOption:
                  (value) => value,

              // ==============================================
              // FILTER SEARCH OPTIONS
              // ==============================================

              optionsBuilder: (text) {
                final query =
                text.text.trim().toLowerCase();

                final matches = options
                    .where(
                      (option) => option
                      .toLowerCase()
                      .contains(query),
                )
                    .toList();

                matches.sort(
                      (a, b) {
                    final aStarts = a
                        .toLowerCase()
                        .startsWith(query);

                    final bStarts = b
                        .toLowerCase()
                        .startsWith(query);

                    if (aStarts != bStarts) {
                      return aStarts ? -1 : 1;
                    }

                    return a
                        .toLowerCase()
                        .compareTo(
                      b.toLowerCase(),
                    );
                  },
                );

                return matches;
              },

              // ==============================================
              // SEARCH INPUT
              // ==============================================

              fieldViewBuilder: (
                  context,
                  textController,
                  fieldFocus,
                  onSubmitted,
                  ) {
                return TextFormField(
                  controller: textController,

                  focusNode: fieldFocus,

                  validator: validator,

                  enabled: !_busy,

                  textInputAction:
                  TextInputAction.next,

                  decoration: _inputDecoration(
                    'Search or enter $label',
                    icon,

                    suffix: IconButton(
                      tooltip: 'Show suggestions',

                      onPressed: _busy
                          ? null
                          : fieldFocus.requestFocus,

                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                      ),
                    ),
                  ),
                );
              },

              // ==============================================
              // SUGGESTION LIST
              // ==============================================

              optionsViewBuilder: (
                  context,
                  onSelected,
                  choices,
                  ) {
                final items =
                choices.take(40).toList();

                return Align(
                  alignment: Alignment.topLeft,

                  child: Material(
                    elevation: 7,

                    color: Colors.white,

                    borderRadius:
                    BorderRadius.circular(12),

                    child: SizedBox(
                      width: constraints.maxWidth,

                      height:
                      (items.length * 46.0)
                          .clamp(0, 230)
                          .toDouble(),

                      child: ListView.builder(
                        padding:
                        const EdgeInsets.symmetric(
                          vertical: 4,
                        ),

                        itemCount: items.length,

                        itemBuilder: (
                            context,
                            index,
                            ) {
                          return ListTile(
                            dense: true,

                            title: Text(
                              items[index],

                              maxLines: 2,
                            ),

                            onTap: () {
                              onSelected(
                                items[index],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  // ==========================================================
  // REUSABLE INPUT FIELD
  // ==========================================================

  Widget _field({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,

    TextInputType keyboardType =
        TextInputType.text,

    String? prefixText,

    bool obscure = false,

    Widget? suffix,

    List<TextInputFormatter>? formatters,

    String? Function(String?)? validator,

    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.start,

      children: [
        _label(label),

        const SizedBox(height: 8),

        TextFormField(
          controller: controller,

          enabled: !_busy,

          validator: validator,

          keyboardType: keyboardType,

          inputFormatters: formatters,

          obscureText: obscure,

          autocorrect: false,

          enableSuggestions: !obscure,

          textInputAction:
          TextInputAction.next,

          onChanged: onChanged,

          decoration: _inputDecoration(
            hint,
            icon,

            suffix: suffix,

            prefixText: prefixText,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // FORM LABEL
  // ==========================================================

  Widget _label(String label) {
    return Text(
      label,

      style: const TextStyle(
        color: FCColors.navy,

        fontWeight: FontWeight.w800,

        fontSize: 12,
      ),
    );
  }

  // ==========================================================
  // INPUT DECORATION
  // ==========================================================

  InputDecoration _inputDecoration(
      String hint,
      IconData icon, {
        Widget? suffix,
        String? prefixText,
      }) {
    OutlineInputBorder outline(
        Color color, [
          double width = 1,
        ]) {
      return OutlineInputBorder(
        borderRadius:
        BorderRadius.circular(14),

        borderSide: BorderSide(
          color: color,
          width: width,
        ),
      );
    }

    return InputDecoration(
      hintText: hint,

      hintStyle: const TextStyle(
        color: Color(0xFF879DAE),

        fontSize: 12,
      ),

      prefixIcon: Icon(
        icon,

        color: FCColors.navy,

        size: 20,
      ),

      prefixText: prefixText,

      prefixStyle: const TextStyle(
        color: FCColors.navy,

        fontWeight: FontWeight.w800,
      ),

      suffixIcon: suffix,

      filled: true,

      fillColor: FCColors.white,

      contentPadding:
      const EdgeInsets.symmetric(
        horizontal: 15,

        vertical: 17,
      ),

      border: outline(
        FCColors.border,
      ),

      enabledBorder: outline(
        FCColors.border,
      ),

      focusedBorder: outline(
        FCColors.navy,
        1.8,
      ),

      errorBorder: outline(
        FCColors.error,
      ),

      focusedErrorBorder: outline(
        FCColors.error,
        1.5,
      ),

      errorMaxLines: 2,
    );
  }

  // ==========================================================
  // RESPONSIVE TWO-COLUMN ROW
  // ==========================================================

  Widget _responsiveRow(
      bool wide,
      Widget first,
      Widget second,
      ) {
    if (wide) {
      return Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Expanded(
            child: first,
          ),

          const SizedBox(width: 16),

          Expanded(
            child: second,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,

      children: [
        first,

        const SizedBox(height: 17),

        second,
      ],
    );
  }

  // ==========================================================
  // PRIMARY BUTTON
  // ==========================================================

  Widget _primaryButton(
      String label,
      VoidCallback action,
      ) {
    return SizedBox(
      height: 54,

      width: double.infinity,

      child: FilledButton(
        onPressed: _busy ? null : action,

        style: FilledButton.styleFrom(
          backgroundColor: FCColors.navy,

          disabledBackgroundColor:
          const Color(0xFF7890A3),

          foregroundColor: FCColors.white,

          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(14),
          ),
        ),

        child: _busy
            ? const SizedBox(
          width: 21,
          height: 21,

          child: CircularProgressIndicator(
            color: Colors.white,

            strokeWidth: 2,
          ),
        )
            : Row(
          mainAxisAlignment:
          MainAxisAlignment.center,

          mainAxisSize:
          MainAxisSize.min,

          children: [
            Flexible(
              child: Text(
                label,

                textAlign:
                TextAlign.center,

                maxLines: 2,

                style: const TextStyle(
                  fontSize: 14,

                  fontWeight: FontWeight.w800,
                ),
              ),
            ),

            const SizedBox(width: 9),

            const Icon(
              Icons.arrow_forward_rounded,

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

  Widget _info(
      IconData icon,
      String message,
      ) {
    return Container(
      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(
        color: FCColors.lightTeal,

        borderRadius:
        BorderRadius.circular(14),
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Icon(
            icon,

            color: FCColors.navy,

            size: 20,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              message,

              style: const TextStyle(
                color: FCColors.navy,

                fontSize: 12,

                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // INLINE ERROR BOX
  // ==========================================================

  Widget _errorBox() {
    if (_error == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(
        bottom: 15,
      ),

      padding: const EdgeInsets.all(13),

      decoration: BoxDecoration(
        color: const Color(
          0xFFFFF0F2,
        ),

        borderRadius:
        BorderRadius.circular(12),
      ),

      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          const Icon(
            Icons.error_outline,

            color: FCColors.error,

            size: 20,
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              _error!,

              style: const TextStyle(
                color: FCColors.error,

                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // LOGIN LINK
  // ==========================================================

  Widget _loginRow() {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,

        crossAxisAlignment:
        WrapCrossAlignment.center,

        children: [
          const Text(
            'Already have an account?',

            style: TextStyle(
              color: FCColors.muted,

              fontSize: 12,
            ),
          ),

          TextButton(
            onPressed:
            _busy ? null : _openLogin,

            child: const Text(
              'Log in',

              style: TextStyle(
                color: FCColors.navy,

                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}