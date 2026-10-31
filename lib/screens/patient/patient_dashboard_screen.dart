
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';
import '../child/child_dashboard_screen.dart';

// ============================================================
// FAMILYCARE+ PATIENT DASHBOARD
// NAVY + MINT DESIGN
// ============================================================
//
// SCREENS:
// 1. Home
// 2. Services
// 3. My Family
// 4. Support
//
// FEATURES:
// - Responsive Navbar
// - Navy + Mint Family Hero
// - Child, Women and Adult Cards
// - English / Hindi
// - Flask Patient Profile API
// - Child Care Navigation
// - Family Profile Pagination
// - Pricing Information
// - Ambulance Information
// - Secure Logout
//
// IMAGE ASSETS:
// assets/images/dashboard_family.png
// assets/images/dashboard_child.png
// assets/images/dashboard_women.png
// assets/images/dashboard_adult.png
//
// ============================================================

// ============================================================
// COLORS
// ============================================================

class _PatientColors {
  static const navy = Color(0xFF102C4B);

  static const deepNavy = Color(0xFF081F37);

  static const mint = Color(0xFF63DDC8);

  static const mintDark = Color(0xFF079E8E);

  static const blue = Color(0xFF287DDA);

  static const pink = Color(0xFFE43988);

  static const purple = Color(0xFFA23FE4);

  static const green = Color(0xFF079E8E);

  static const muted = Color(0xFF62788A);

  static const border = Color(0xFFD7E6E9);

  static const background = Color(0xFFF3FAF9);

  static const lightMint = Color(0xFFE8F9F5);

  static const white = Colors.white;
}

// ============================================================
// FAMILY MEMBER MODEL
// ============================================================

class _FamilyMember {
  final String id;

  final String fullName;

  final String module;

  final DateTime? dateOfBirth;

  const _FamilyMember({
    required this.id,
    required this.fullName,
    required this.module,
    required this.dateOfBirth,
  });

  factory _FamilyMember.fromJson(
      Map<String, dynamic> json,
      ) {
    return _FamilyMember(
      id: (json['id'] ?? '').toString().trim(),

      fullName: (json['full_name'] ?? '')
          .toString()
          .trim(),

      module: (json['module'] ?? '')
          .toString()
          .trim()
          .toLowerCase(),

      dateOfBirth: DateTime.tryParse(
        (json['date_of_birth'] ?? '').toString(),
      ),
    );
  }
}

// ============================================================
// PATIENT API EXCEPTION
// ============================================================

class _PatientApiException implements Exception {
  final String message;

  final int statusCode;

  const _PatientApiException(
      this.message, {
        this.statusCode = 0,
      });

  @override
  String toString() => message;
}

// ============================================================
// PATIENT DASHBOARD SCREEN
// ============================================================

class PatientDashboardScreen extends StatefulWidget {
  final String apiBaseUrl;

  const PatientDashboardScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
  });

  @override
  State<PatientDashboardScreen> createState() =>
      _PatientDashboardScreenState();
}

// ============================================================
// DASHBOARD STATE
// ============================================================

class _PatientDashboardScreenState
    extends State<PatientDashboardScreen> {
  // ==========================================================
  // HTTP CLIENT
  // ==========================================================

  final http.Client _client = http.Client();

  // ==========================================================
  // DASHBOARD IMAGES
  // ==========================================================

  static const String _familyImage =
      'assets/images/dashboard_family.png';

  static const String _childImage =
      'assets/images/dashboard_child.png';

  static const String _womenImage =
      'assets/images/dashboard_women.png';

  static const String _adultImage =
      'assets/images/dashboard_adult.png';

  // ==========================================================
  // DASHBOARD NAVIGATION
  // ==========================================================

  int _selectedTab = 0;

  // ==========================================================
  // LANGUAGE
  // ==========================================================

  bool _hindi = false;

  // ==========================================================
  // SIGN OUT
  // ==========================================================

  bool _signingOut = false;

  // ==========================================================
  // CHILD CARE NAVIGATION
  // ==========================================================

  bool _openingChildCare = false;

  // ==========================================================
  // FAMILY PROFILES
  // ==========================================================

  final List<_FamilyMember> _familyMembers = [];

  int _familyRequestVersion = 0;

  bool _loadingFamily = false;

  bool _familyLoaded = false;

  String? _familyError;

  // ==========================================================
  // LANGUAGE HELPER
  // ==========================================================

  String _t(
      String english,
      String hindi,
      ) {
    return _hindi ? hindi : english;
  }

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
  // UPDATE API BASE URL
  // ==========================================================

  @override
  void didUpdateWidget(
      covariant PatientDashboardScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _familyRequestVersion++;

      _familyMembers.clear();

      _familyLoaded = false;

      _loadingFamily = false;

      _familyError = null;

      if (_selectedTab == 2) {
        _loadFamily();
      }
    }
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _familyRequestVersion++;

    _client.close();

    super.dispose();
  }

  // ==========================================================
  // SWITCH DASHBOARD TAB
  // ==========================================================

  void _switchTab(int index) {
    if (_selectedTab == index) {
      return;
    }

    setState(() {
      _selectedTab = index;
    });

    if (index == 2 &&
        !_familyLoaded &&
        !_loadingFamily) {
      _loadFamily();
    }
  }

  // ==========================================================
  // OPEN CHILD CARE
  // ==========================================================

  Future<void> _openChildCare() async {
    if (_openingChildCare || !mounted) {
      return;
    }

    setState(() {
      _openingChildCare = true;
    });

    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChildDashboardScreen(
            apiBaseUrl: _baseUrl,
          ),
        ),
      );

      if (!mounted) {
        return;
      }

      // Family data may change inside Child Care.
      _familyLoaded = false;

      if (_selectedTab == 2) {
        await _loadFamily();
      }
    } finally {
      if (mounted) {
        setState(() {
          _openingChildCare = false;
        });
      }
    }
  }

  // ==========================================================
  // WOMEN / ADULT MODULE NAVIGATION
  // ==========================================================

  void _openUpcomingModule({
    required bool women,
  }) {
    final title = women
        ? _t(
      "Women's Health",
      'महिला स्वास्थ्य',
    )
        : _t(
      'Adult Health',
      'वयस्क स्वास्थ्य',
    );

    final description = women
        ? _t(
      'Menstrual care, PCOS, reproductive health, '
          'fertility, pregnancy, postpartum care and '
          'menopause will be available when this '
          'module is completed.',
      'मासिक धर्म, PCOS, प्रजनन स्वास्थ्य, '
          'गर्भावस्था और महिला देखभाल की '
          'सुविधाएं जल्द जोड़ी जाएंगी।',
    )
        : _t(
      'Adult healthcare for diabetes, blood '
          'pressure, cholesterol, asthma and other '
          'chronic conditions will be available '
          'when this module is completed.',
      'शुगर, बीपी, कोलेस्ट्रॉल और अन्य '
          'स्वास्थ्य सुविधाएं जल्द जोड़ी जाएंगी।',
    );

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _DashboardPreviewScreen(
          title: title,
          description: description,
          icon: women
              ? Icons.favorite_outline_rounded
              : Icons.monitor_heart_outlined,
        ),
      ),
    );
  }

  // ==========================================================
  // AMBULANCE INFORMATION
  // ==========================================================

  void _showAmbulanceInfo() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _t(
              'Ambulance Assistance',
              'एम्बुलेंस सहायता',
            ),
          ),

          content: Text(
            _t(
              'Ambulance dispatch is not currently '
                  'connected to FamilyCare+. This button '
                  'does not book or request an ambulance.\n\n'
                  'In an emergency, contact local emergency '
                  'services immediately.',
              'FamilyCare+ से अभी एम्बुलेंस बुकिंग '
                  'नहीं होती है। यह बटन एम्बुलेंस '
                  'नहीं बुलाता।\n\n'
                  'आपातकाल में स्थानीय आपातकालीन '
                  'सेवा से तुरंत संपर्क करें।',
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },

              child: Text(
                _t(
                  'Close',
                  'बंद करें',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // FRIENDLY ERROR MESSAGES
  // ==========================================================

  String _friendlyError(Object error) {
    if (error is _PatientApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'The server took too long to respond.';
    }

    if (error is http.ClientException) {
      return 'Unable to connect to FamilyCare+. '
          'Check your API URL and CORS settings.';
    }

    if (error is FormatException) {
      return 'Invalid family profile data received.';
    }

    return 'Something went wrong. Please try again.';
  }

  // ==========================================================
  // AUTHENTICATED FLASK GET REQUEST
  // ==========================================================

  Future<Map<String, dynamic>> _getJson(
      String path, {
        required String baseUrl,
        required String token,
      }) async {
    final response = await _client
        .get(
      Uri.parse('$baseUrl$path'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
        'X-Auth-Transport': 'bearer',
      },
    )
        .timeout(
      const Duration(seconds: 35),
    );

    Map<String, dynamic>? decoded;

    try {
      final raw = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (raw is Map) {
        decoded = Map<String, dynamic>.from(raw);
      }
    } catch (_) {
      // HTTP error pages may return non-JSON data.
    }

    // ========================================================
    // HTTP ERROR HANDLING
    // ========================================================

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      var message =
          'Unable to load family profiles '
          '(HTTP ${response.statusCode}).';

      final error = decoded?['error'];

      if (error is Map &&
          error['message'] is String) {
        message = error['message'] as String;
      }

      if (response.statusCode == 401) {
        message =
        'Your login session has expired. '
            'Please sign in again.';
      }

      if (response.statusCode == 403) {
        message =
        'You do not have access to these profiles.';
      }

      throw _PatientApiException(
        message,
        statusCode: response.statusCode,
      );
    }

    // ========================================================
    // INVALID JSON RESPONSE
    // ========================================================

    if (decoded == null) {
      throw const FormatException(
        'The server returned invalid JSON.',
      );
    }

    return decoded;
  }

  // ==========================================================
  // LOAD FAMILY PROFILES
  // ==========================================================

  Future<void> _loadFamily() async {
    if (_loadingFamily || !mounted) {
      return;
    }

    final requestVersion = ++_familyRequestVersion;

    final baseUrl = _baseUrl;

    setState(() {
      _loadingFamily = true;
      _familyError = null;
    });

    try {
      // ======================================================
      // ACCESS TOKEN
      // ======================================================

      final token =
      await FamilyCareSession.accessToken();

      if (token == null || token.trim().isEmpty) {
        throw const _PatientApiException(
          'Please sign in to view family profiles.',
          statusCode: 401,
        );
      }

      // ======================================================
      // FAMILY MEMBERS
      // ======================================================

      final members = <_FamilyMember>[];

      final seenIds = <String>{};

      // ======================================================
      // PAGINATED BACKEND REQUEST
      // ======================================================

      for (int page = 1; page <= 100; page++) {
        final payload = await _getJson(
          '/api/v1/patients/profiles'
              '?page=$page&per_page=100',
          baseUrl: baseUrl,
          token: token,
        );

        if (!mounted ||
            requestVersion != _familyRequestVersion) {
          return;
        }

        final items = payload['items'];

        if (items is! List) {
          throw const FormatException(
            'Missing family profile list.',
          );
        }

        // ====================================================
        // READ FAMILY PROFILES
        // ====================================================

        for (final raw in items) {
          if (raw is! Map) {
            continue;
          }

          final item =
          Map<String, dynamic>.from(raw);

          final member =
          _FamilyMember.fromJson(item);

          if (member.id.isEmpty ||
              member.fullName.isEmpty) {
            continue;
          }

          if (!const {
            'child',
            'women',
            'adult',
          }.contains(member.module)) {
            continue;
          }

          if (seenIds.add(member.id)) {
            members.add(member);
          }
        }

        // ====================================================
        // CHECK PAGINATION
        // ====================================================

        final total = payload['total'];

        if (items.isEmpty ||
            items.length < 100 ||
            (total is num &&
                page * 100 >= total.toInt())) {
          break;
        }
      }

      if (!mounted ||
          requestVersion != _familyRequestVersion) {
        return;
      }

      // ======================================================
      // SUCCESS
      // ======================================================

      setState(() {
        _familyMembers
          ..clear()
          ..addAll(members);

        _familyLoaded = true;

        _familyError = null;
      });
    } catch (error) {
      if (!mounted ||
          requestVersion != _familyRequestVersion) {
        return;
      }

      // ======================================================
      // ERROR
      // ======================================================

      setState(() {
        _familyError = _friendlyError(error);
        _familyLoaded = false;
      });
    } finally {
      if (mounted &&
          requestVersion == _familyRequestVersion) {
        setState(() {
          _loadingFamily = false;
        });
      }
    }
  }

  // ==========================================================
  // SIGN OUT
  // ==========================================================

  Future<void> _signOut() async {
    if (_signingOut || !mounted) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _t(
              'Sign out?',
              'साइन आउट करें?',
            ),
          ),

          content: Text(
            _t(
              'You will be signed out on this device.',
              'आप इस डिवाइस से साइन आउट हो जाएंगे।',
            ),
          ),

          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },

              child: Text(
                _t(
                  'Cancel',
                  'रद्द करें',
                ),
              ),
            ),

            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },

              child: Text(
                _t(
                  'Sign Out',
                  'साइन आउट',
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _signingOut = true;
    });

    try {
      await FamilyCareSession.clear();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/login',
            (_) => false,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'Unable to sign out. Please try again.',
              'साइन आउट नहीं हो पाया। फिर कोशिश करें।',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _signingOut = false;
        });
      }
    }
  }

  // ==========================================================
  // MAIN DASHBOARD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    final screenWidth =
        MediaQuery.sizeOf(context).width;

    final isWide = screenWidth >= 1100;

    return Scaffold(
      backgroundColor: _PatientColors.background,

      // ======================================================
      // MOBILE BOTTOM NAVIGATION
      // ======================================================

      bottomNavigationBar: isWide
          ? null
          : NavigationBar(
        selectedIndex: _selectedTab,

        onDestinationSelected: _switchTab,

        backgroundColor: Colors.white,

        indicatorColor: _PatientColors.lightMint,

        labelBehavior:
        NavigationDestinationLabelBehavior
            .alwaysShow,

        destinations: [
          NavigationDestination(
            icon: const Icon(
              Icons.home_outlined,
            ),

            selectedIcon: const Icon(
              Icons.home_rounded,
            ),

            label: _t(
              'Home',
              'होम',
            ),
          ),

          NavigationDestination(
            icon: const Icon(
              Icons.grid_view_outlined,
            ),

            selectedIcon: const Icon(
              Icons.grid_view_rounded,
            ),

            label: _t(
              'Services',
              'सेवाएं',
            ),
          ),

          NavigationDestination(
            icon: const Icon(
              Icons.family_restroom_outlined,
            ),

            selectedIcon: const Icon(
              Icons.family_restroom_rounded,
            ),

            label: _t(
              'My Family',
              'परिवार',
            ),
          ),

          NavigationDestination(
            icon: const Icon(
              Icons.support_agent_outlined,
            ),

            selectedIcon: const Icon(
              Icons.support_agent_rounded,
            ),

            label: _t(
              'Support',
              'सहायता',
            ),
          ),
        ],
      ),

      // ======================================================
      // BODY
      // ======================================================

      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior:
          ScrollViewKeyboardDismissBehavior.onDrag,

          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 1240,
              ),

              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 28 : 15,
                  vertical: isWide ? 18 : 12,
                ),

                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.stretch,

                  children: [
                    // ========================================
                    // HEADER
                    // ========================================

                    _buildHeader(isWide),

                    const SizedBox(height: 18),

                    // ========================================
                    // PAGE CONTENT
                    // ========================================

                    if (_selectedTab == 0)
                      _buildHome(isWide)
                    else if (_selectedTab == 1)
                      _buildServices(isWide)
                    else if (_selectedTab == 2)
                        _buildFamily()
                      else
                        _buildSupport(),

                    const SizedBox(height: 28),

                    // ========================================
                    // FOOTER
                    // ========================================

                    Text(
                      _t(
                        'FamilyCare+ • Healthier Families. '
                            'Brighter Tomorrows.',
                        'FamilyCare+ • स्वस्थ परिवार, '
                            'उज्ज्वल कल।',
                      ),

                      textAlign: TextAlign.center,

                      style: const TextStyle(
                        color: _PatientColors.muted,
                        fontSize: 11,
                      ),
                    ),

                    const SizedBox(height: 12),
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
  // RESPONSIVE HEADER
  // ==========================================================
  //
  // Prevents the RenderFlex overflow on narrow screens.
  //
  // ==========================================================

  Widget _buildHeader(bool isWide) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny = constraints.maxWidth < 275;

        final logoSize =
        isWide ? 47.0 : (tiny ? 30.0 : 38.0);

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? 20 : (tiny ? 8 : 11),
            vertical: isWide ? 14 : 9,
          ),

          decoration: BoxDecoration(
            color: Colors.white,

            borderRadius: BorderRadius.circular(20),

            border: Border.all(
              color: _PatientColors.border,
            ),
          ),

          child: Row(
            children: [
              // ============================================
              // FAMILYCARE+ LOGO
              // ============================================

              Container(
                width: logoSize,
                height: logoSize,

                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      _PatientColors.navy,
                      _PatientColors.mint,
                    ],
                  ),

                  borderRadius:
                  BorderRadius.circular(12),
                ),

                child: Icon(
                  Icons.favorite_rounded,

                  color: Colors.white,

                  size: tiny ? 17 : 23,
                ),
              ),

              SizedBox(
                width: tiny ? 5 : 9,
              ),

              // ============================================
              // BRAND
              // ============================================

              if (isWide)
                const Column(
                  mainAxisSize: MainAxisSize.min,

                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Text(
                      'FamilyCare+',

                      style: TextStyle(
                        fontSize: 20,

                        fontWeight: FontWeight.w800,

                        color: _PatientColors.navy,
                      ),
                    ),

                    Text(
                      'Healthier Families. Brighter Tomorrows.',

                      style: TextStyle(
                        fontSize: 10,

                        color: _PatientColors.muted,
                      ),
                    ),
                  ],
                )
              else
                Expanded(
                  child: Text(
                    tiny ? 'FC+' : 'FamilyCare+',

                    maxLines: 1,

                    overflow: TextOverflow.ellipsis,

                    style: TextStyle(
                      color: _PatientColors.navy,

                      fontSize: tiny ? 12 : 16,

                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),

              // ============================================
              // DESKTOP NAVIGATION
              // ============================================

              if (isWide)
                Expanded(
                  child: Row(
                    mainAxisAlignment:
                    MainAxisAlignment.center,

                    children: [
                      _headerTab(
                        _t('Home', 'होम'),
                        0,
                      ),

                      _headerTab(
                        _t('Services', 'सेवाएं'),
                        1,
                      ),

                      _headerTab(
                        _t('My Family', 'मेरा परिवार'),
                        2,
                      ),

                      _headerTab(
                        _t('Support', 'सहायता'),
                        3,
                      ),
                    ],
                  ),
                ),

              // ============================================
              // LANGUAGE SELECTOR
              // ============================================

              PopupMenuButton<bool>(
                tooltip: _t(
                  'Change language',
                  'भाषा बदलें',
                ),

                onSelected: (value) {
                  setState(() {
                    _hindi = value;
                  });
                },

                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: false,
                    child: Text('English'),
                  ),

                  PopupMenuItem(
                    value: true,
                    child: Text('हिन्दी'),
                  ),
                ],

                child: Container(
                  constraints: BoxConstraints(
                    minWidth: tiny ? 30 : 38,
                    minHeight: 36,
                  ),

                  padding: EdgeInsets.symmetric(
                    horizontal: tiny ? 5 : 8,
                    vertical: 8,
                  ),

                  decoration: BoxDecoration(
                    color: _PatientColors.lightMint,

                    borderRadius:
                    BorderRadius.circular(10),
                  ),

                  child: Row(
                    mainAxisSize: MainAxisSize.min,

                    mainAxisAlignment:
                    MainAxisAlignment.center,

                    children: [
                      const Icon(
                        Icons.language_rounded,

                        size: 17,

                        color: _PatientColors.navy,
                      ),

                      if (!tiny) ...[
                        const SizedBox(width: 4),

                        Text(
                          _hindi ? 'हिं' : 'EN',

                          style: const TextStyle(
                            color: _PatientColors.navy,

                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              SizedBox(
                width: tiny ? 2 : 6,
              ),

              // ============================================
              // SIGN OUT
              // ============================================

              if (isWide)
                TextButton.icon(
                  onPressed:
                  _signingOut ? null : _signOut,

                  icon: const Icon(
                    Icons.logout_rounded,
                    size: 18,
                  ),

                  label: Text(
                    _t(
                      'Sign Out',
                      'साइन आउट',
                    ),
                  ),

                  style: TextButton.styleFrom(
                    foregroundColor:
                    _PatientColors.navy,
                  ),
                )
              else
                SizedBox(
                  width: tiny ? 30 : 36,
                  height: 36,

                  child: IconButton(
                    tooltip: _t(
                      'Sign Out',
                      'साइन आउट',
                    ),

                    onPressed:
                    _signingOut ? null : _signOut,

                    padding: EdgeInsets.zero,

                    iconSize: 19,

                    icon: const Icon(
                      Icons.logout_rounded,

                      color: _PatientColors.navy,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================
  // DESKTOP HEADER TAB
  // ==========================================================

  Widget _headerTab(
      String label,
      int index,
      ) {
    final selected = _selectedTab == index;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 2,
      ),

      child: TextButton(
        onPressed: () => _switchTab(index),

        child: Text(
          label,

          style: TextStyle(
            color: selected
                ? _PatientColors.mintDark
                : _PatientColors.muted,

            fontWeight: selected
                ? FontWeight.w800
                : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // HOME PAGE
  // ==========================================================

  Widget _buildHome(bool isWide) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,

      children: [
        // ====================================================
        // FAMILY HERO
        // ====================================================

        _buildHero(isWide),

        SizedBox(
          height: isWide ? 22 : 16,
        ),

        // ====================================================
        // SERVICES
        // ====================================================

        _sectionHeading(
          _t(
            'Our Services',
            'हमारी सेवाएं',
          ),

          _t(
            'Care for every member of your family.',
            'आपके परिवार के हर सदस्य की देखभाल।',
          ),
        ),

        const SizedBox(height: 12),

        _buildCareCards(isWide),

        const SizedBox(height: 28),

        // ====================================================
        // ADDITIONAL INFORMATION
        // ====================================================

        Text(
          _t(
            'A little care. A lot of peace of mind.',
            'थोड़ी सी देखभाल, ढेर सारा सुकून।',
          ),

          textAlign: TextAlign.center,

          style: TextStyle(
            fontSize: isWide ? 26 : 21,

            fontWeight: FontWeight.w800,

            color: _PatientColors.navy,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          _t(
            "Your family's wellbeing, together in one place.",
            'आपके परिवार की सेहत, एक ही जगह।',
          ),

          textAlign: TextAlign.center,

          style: const TextStyle(
            color: _PatientColors.muted,
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 26),

        _buildHowItWorks(isWide),

        const SizedBox(height: 20),

        _buildPricingSection(),

        const SizedBox(height: 20),

        _buildAmbulanceSection(),
      ],
    );
  }

  // ==========================================================
  // UPDATED HERO - NAVY + MINT
  // ==========================================================
  //
  // LEFT SIDE:
  // FAMILY FIRST
  // Healthcare for Every Stage of Life
  // Little moments. Lifelong care.
  //
  // RIGHT SIDE:
  // Indian family image
  //
  // BoxFit.cover fills the panel without side gaps.
  // No text overlays the photo.
  //
  // ==========================================================

  Widget _buildHero(bool isWide) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final verySmall = width < 330;

        final heroHeight = isWide
            ? 290.0
            : (verySmall ? 165.0 : 184.0);

        final headingFontSize = isWide
            ? 37.0
            : (verySmall
            ? 15.4
            : (width < 390 ? 17.0 : 19.0));

        return Container(
          width: double.infinity,
          height: heroHeight,

          clipBehavior: Clip.antiAlias,

          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),

            border: Border.all(
              color: _PatientColors.border,
            ),

            boxShadow: const [
              BoxShadow(
                color: Color(0x10102C4B),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),

          child: Row(
            crossAxisAlignment:
            CrossAxisAlignment.stretch,

            children: [
              // ============================================
              // LEFT NAVY PANEL
              // ============================================

              Expanded(
                flex: isWide ? 11 : 10,

                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                    isWide ? 28 : (verySmall ? 9 : 12),

                    vertical: isWide ? 28 : 11,
                  ),

                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,

                      end: Alignment.bottomRight,

                      colors: [
                        Color(0xFF081F37),
                        Color(0xFF153B5A),
                      ],
                    ),
                  ),

                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,

                    mainAxisAlignment:
                    MainAxisAlignment.spaceEvenly,

                    children: [
                      // ======================================
                      // FAMILY FIRST LABEL
                      // ======================================

                      Row(
                        mainAxisSize: MainAxisSize.min,

                        children: [
                          const Icon(
                            Icons.favorite_rounded,

                            color: _PatientColors.mint,

                            size: 13,
                          ),

                          const SizedBox(width: 5),

                          Flexible(
                            child: Text(
                              _t(
                                'FAMILY FIRST',
                                'परिवार पहले',
                              ),

                              maxLines: 1,

                              overflow:
                              TextOverflow.ellipsis,

                              style: TextStyle(
                                color: const Color(
                                  0xFFB9F2E8,
                                ),

                                fontSize:
                                isWide ? 12 : 8.5,

                                letterSpacing:
                                isWide ? 1.4 : 0.55,

                                fontWeight:
                                FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),

                      // ======================================
                      // HERO HEADING
                      // ======================================

                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _t(
                                'Healthcare\n',
                                'स्वास्थ्य सेवा\n',
                              ),

                              style: const TextStyle(
                                color: Colors.white,
                              ),
                            ),

                            TextSpan(
                              text: _t(
                                'for Every\n',
                                'हर उम्र के\n',
                              ),

                              style: const TextStyle(
                                color: _PatientColors.mint,
                              ),
                            ),

                            TextSpan(
                              text: _t(
                                'Stage of Life',
                                'हर पड़ाव पर',
                              ),

                              style: const TextStyle(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),

                        maxLines: 5,

                        overflow:
                        TextOverflow.ellipsis,

                        textAlign: TextAlign.left,

                        style: TextStyle(
                          height: 1.11,

                          fontSize: headingFontSize,

                          letterSpacing: -0.45,

                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      // ======================================
                      // SHORT TAGLINE
                      // ======================================

                      Text(
                        _t(
                          'Little moments. Lifelong care.',
                          'हर पल अपनों का साथ।',
                        ),

                        maxLines: 2,

                        overflow:
                        TextOverflow.ellipsis,

                        style: TextStyle(
                          fontSize: isWide ? 13 : 9.1,

                          height: 1.28,

                          color: const Color(
                            0xFFD2E8EC,
                          ),

                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ============================================
              // RIGHT FAMILY IMAGE
              // ============================================

              Expanded(
                flex: isWide ? 10 : 11,

                child: ClipRect(
                  child: Image.asset(
                    _familyImage,

                    width: double.infinity,

                    height: double.infinity,

                    fit: BoxFit.cover,

                    alignment: const Alignment(
                      0,
                      -0.2,
                    ),

                    errorBuilder: (
                        context,
                        error,
                        stackTrace,
                        ) {
                      return const ColoredBox(
                        color: Color(0xFFE6F9F4),

                        child: Center(
                          child: Icon(
                            Icons.family_restroom_rounded,

                            color: _PatientColors.navy,

                            size: 45,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================================
  // CHILD / WOMEN / ADULT CARE CARDS
  // ==========================================================

  Widget _buildCareCards(bool isWide) {
    // ========================================================
    // CHILD CARE
    // ========================================================

    final child = _careCard(
      title: _t(
        'Child Care',
        'चाइल्ड केयर',
      ),

      subtitle: _t(
        '0–12 Years',
        '0–12 वर्ष',
      ),

      image: _childImage,

      color: _PatientColors.blue,

      background: const Color(0xFFEAF5FF),

      icon: Icons.child_care_rounded,

      onTap: _openChildCare,
    );

    // ========================================================
    // WOMEN'S HEALTH
    // ========================================================

    final women = _careCard(
      title: _t(
        "Women's Health",
        'महिला स्वास्थ्य',
      ),

      subtitle: _t(
        'Gynecology, reproductive health & wellness',
        'महिला स्वास्थ्य और देखभाल',
      ),

      image: _womenImage,

      color: _PatientColors.pink,

      background: const Color(0xFFFFF0F7),

      icon: Icons.favorite_rounded,

      onTap: () {
        _openUpcomingModule(women: true);
      },
    );

    // ========================================================
    // ADULT HEALTH
    // ========================================================

    final adult = _careCard(
      title: _t(
        'Adult Health',
        'वयस्क स्वास्थ्य',
      ),

      subtitle: _t(
        'BP, diabetes & chronic health records',
        'बीपी, शुगर और स्वास्थ्य रिकॉर्ड',
      ),

      image: _adultImage,

      color: _PatientColors.green,

      background: const Color(0xFFEAF9F4),

      icon: Icons.monitor_heart_rounded,

      onTap: () {
        _openUpcomingModule(women: false);
      },
    );

    // ========================================================
    // DESKTOP THREE-COLUMN LAYOUT
    // ========================================================

    if (isWide) {
      return Row(
        children: [
          Expanded(child: child),

          const SizedBox(width: 14),

          Expanded(child: women),

          const SizedBox(width: 14),

          Expanded(child: adult),
        ],
      );
    }

    // ========================================================
    // MOBILE STACKED LAYOUT
    // ========================================================

    return Column(
      children: [
        child,

        const SizedBox(height: 12),

        women,

        const SizedBox(height: 12),

        adult,
      ],
    );
  }

  // ==========================================================
  // SINGLE HEALTHCARE CARD
  // ==========================================================

  Widget _careCard({
    required String title,
    required String subtitle,
    required String image,
    required Color color,
    required Color background,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 285;

        final photoWidth = tight ? 70.0 : 94.0;

        return Material(
          color: background,

          borderRadius: BorderRadius.circular(19),

          child: InkWell(
            onTap: onTap,

            borderRadius: BorderRadius.circular(19),

            child: Container(
              height: tight ? 120 : 132,

              padding: const EdgeInsets.all(10),

              decoration: BoxDecoration(
                borderRadius:
                BorderRadius.circular(19),

                border: Border.all(
                  color: color.withValues(
                    alpha: 0.18,
                  ),
                ),
              ),

              child: Row(
                children: [
                  // ========================================
                  // IMAGE
                  // ========================================

                  SizedBox(
                    width: photoWidth,

                    height: double.infinity,

                    child: ClipRRect(
                      borderRadius:
                      BorderRadius.circular(13),

                      child: _DashboardAssetPhoto(
                        path: image,

                        fallback: icon,

                        fallbackColor:
                        color.withValues(
                          alpha: 0.12,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // ========================================
                  // CARD CONTENT
                  // ========================================

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment.start,

                      mainAxisAlignment:
                      MainAxisAlignment.center,

                      children: [
                        Icon(
                          icon,

                          color: color,

                          size: tight ? 16 : 20,
                        ),

                        const SizedBox(height: 6),

                        Text(
                          title,

                          maxLines: 2,

                          overflow:
                          TextOverflow.ellipsis,

                          style: TextStyle(
                            color: _PatientColors.navy,

                            fontSize: tight ? 12 : 14,

                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          subtitle,

                          maxLines: tight ? 2 : 3,

                          overflow:
                          TextOverflow.ellipsis,

                          style: TextStyle(
                            color:
                            _PatientColors.muted,

                            fontSize: tight ? 9 : 10,

                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 3),

                  // ========================================
                  // ARROW
                  // ========================================

                  CircleAvatar(
                    radius: tight ? 12 : 15,

                    backgroundColor: color,

                    child: Icon(
                      Icons.arrow_forward_rounded,

                      size: tight ? 14 : 17,

                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================================
  // SERVICES TAB
  // ==========================================================

  Widget _buildServices(bool isWide) {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,

      children: [
        _sectionHeading(
          _t(
            'Our Healthcare Services',
            'हमारी स्वास्थ्य सेवाएं',
          ),

          _t(
            'Choose the care that fits your family.',
            'अपने परिवार के लिए सही देखभाल चुनें।',
          ),
        ),

        const SizedBox(height: 18),

        _buildCareCards(isWide),

        const SizedBox(height: 22),

        _buildHowItWorks(isWide),

        const SizedBox(height: 20),

        _buildPricingSection(),

        const SizedBox(height: 20),

        _buildAmbulanceSection(),
      ],
    );
  }

  // ==========================================================
  // HOW IT WORKS
  // ==========================================================

  Widget _buildHowItWorks(bool isWide) {
    return _panel(
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Text(
            _t(
              'Care That Stays Connected',
              'एक साथ जुड़ी देखभाल',
            ),

            style: const TextStyle(
              color: _PatientColors.navy,

              fontSize: 20,

              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 18),

          LayoutBuilder(
            builder: (context, constraints) {
              final horizontal =
                  constraints.maxWidth >= 700;

              final features = [
                _featureItem(
                  icon:
                  Icons.family_restroom_outlined,

                  title: _t(
                    'One Family Account',
                    'एक परिवार का खाता',
                  ),

                  detail: _t(
                    'Access the right healthcare module '
                        'for each member of your family.',
                    'परिवार के प्रत्येक सदस्य की '
                        'स्वास्थ्य जानकारी रखें।',
                  ),

                  color: _PatientColors.blue,
                ),

                _featureItem(
                  icon: Icons.folder_copy_outlined,

                  title: _t(
                    'Organized Health Records',
                    'संगठित स्वास्थ्य रिकॉर्ड',
                  ),

                  detail: _t(
                    'Keep medical reports linked '
                        'to the correct family profile.',
                    'हर सदस्य की रिपोर्ट '
                        'उनकी प्रोफाइल से जोड़ें।',
                  ),

                  color: _PatientColors.pink,
                ),

                _featureItem(
                  icon:
                  Icons.medical_services_outlined,

                  title: _t(
                    'Doctor Connection',
                    'डॉक्टर कनेक्शन',
                  ),

                  detail: _t(
                    'Connect with an approved doctor '
                        'using a referral ID.',
                    'रेफरल आईडी से स्वीकृत '
                        'डॉक्टर जोड़ें।',
                  ),

                  color: _PatientColors.green,
                ),
              ];

              // ==============================================
              // DESKTOP FEATURES
              // ==============================================

              if (horizontal) {
                return Row(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Expanded(
                      child: features[0],
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: features[1],
                    ),

                    const SizedBox(width: 14),

                    Expanded(
                      child: features[2],
                    ),
                  ],
                );
              }

              // ==============================================
              // MOBILE FEATURES
              // ==============================================

              return Column(
                children: [
                  features[0],

                  const SizedBox(height: 18),

                  features[1],

                  const SizedBox(height: 18),

                  features[2],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SINGLE FEATURE ITEM
  // ==========================================================

  Widget _featureItem({
    required IconData icon,
    required String title,
    required String detail,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment:
      CrossAxisAlignment.start,

      children: [
        Container(
          padding: const EdgeInsets.all(10),

          decoration: BoxDecoration(
            color: color.withValues(
              alpha: 0.10,
            ),

            borderRadius:
            BorderRadius.circular(12),
          ),

          child: Icon(
            icon,

            color: color,

            size: 22,
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,

            children: [
              Text(
                title,

                style: const TextStyle(
                  color: _PatientColors.navy,

                  fontSize: 12,

                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 5),

              Text(
                detail,

                style: const TextStyle(
                  color: _PatientColors.muted,

                  fontSize: 11,

                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // PRICING SECTION
  // ==========================================================

  Widget _buildPricingSection() {
    return _panel(
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          const CircleAvatar(
            radius: 27,

            backgroundColor: Color(0xFFF3ECFF),

            child: Icon(
              Icons.sell_outlined,

              color: _PatientColors.purple,

              size: 26,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  _t(
                    'Plans & Pricing',
                    'प्लान और कीमत',
                  ),

                  style: const TextStyle(
                    color: _PatientColors.navy,

                    fontSize: 18,

                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 7),

                Text(
                  _t(
                    'Subscription plans and prices '
                        'have not been published yet. '
                        'Verified options will appear '
                        'here when available.',
                    'प्लान और कीमतें तय होने के '
                        'बाद यहां दिखाई जाएंगी।',
                  ),

                  style: const TextStyle(
                    color: _PatientColors.muted,

                    fontSize: 12,

                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // AMBULANCE SECTION
  // ==========================================================

  Widget _buildAmbulanceSection() {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(19),

      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFF0F1),

            Color(0xFFF9F5FF),
          ],
        ),

        border: Border.all(
          color: const Color(0xFFF3DEE5),
        ),

        borderRadius:
        BorderRadius.circular(19),
      ),

      child: Row(
        children: [
          const CircleAvatar(
            radius: 29,

            backgroundColor: Colors.white,

            child: Icon(
              Icons.emergency_outlined,

              color: Color(0xFFBB4059),

              size: 31,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,

              children: [
                Text(
                  _t(
                    'Ambulance Assistance',
                    'एम्बुलेंस सहायता',
                  ),

                  style: const TextStyle(
                    color: _PatientColors.navy,

                    fontSize: 17,

                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  _t(
                    'Ambulance dispatch is not currently '
                        'connected. This feature does not '
                        'book an ambulance.',
                    'अभी ऐप से एम्बुलेंस '
                        'बुक नहीं होती।',
                  ),

                  style: const TextStyle(
                    color: _PatientColors.muted,

                    fontSize: 11,

                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 11),

                OutlinedButton.icon(
                  onPressed: _showAmbulanceInfo,

                  icon: const Icon(
                    Icons.info_outline_rounded,

                    size: 17,
                  ),

                  label: Text(
                    _t(
                      'Learn More',
                      'जानकारी देखें',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // MY FAMILY TAB
  // ==========================================================

  Widget _buildFamily() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,

      children: [
        _sectionHeading(
          _t(
            'My Family',
            'मेरा परिवार',
          ),

          _t(
            'Profiles connected to your '
                'FamilyCare+ account.',
            'आपके खाते से जुड़ी हुई प्रोफाइल।',
          ),
        ),

        const SizedBox(height: 10),

        // ====================================================
        // FAMILY HEADER AND REFRESH
        // ====================================================

        Row(
          children: [
            Expanded(
              child: Text(
                _t(
                  'Family Profiles',
                  'परिवार की प्रोफाइल',
                ),

                style: const TextStyle(
                  color: _PatientColors.navy,

                  fontSize: 13,

                  fontWeight: FontWeight.w700,
                ),
              ),
            ),

            IconButton(
              tooltip: _t(
                'Refresh Family',
                'परिवार रिफ्रेश करें',
              ),

              onPressed:
              _loadingFamily ? null : _loadFamily,

              icon: const Icon(
                Icons.refresh_rounded,

                color: _PatientColors.blue,
              ),
            ),
          ],
        ),

        const SizedBox(height: 11),

        // ====================================================
        // LOADING
        // ====================================================

        if (_loadingFamily)
          _panel(
            child: const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 30,
              ),

              child: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          )

        // ====================================================
        // ERROR
        // ====================================================

        else if (_familyError != null)
          _emptyPanel(
            icon: Icons.cloud_off_rounded,

            title: _t(
              'Could Not Load Profiles',
              'प्रोफाइल नहीं खुल सकीं',
            ),

            message: _familyError!,

            button: _t(
              'Try Again',
              'फिर कोशिश करें',
            ),

            onPressed: _loadFamily,
          )

        // ====================================================
        // EMPTY FAMILY
        // ====================================================

        else if (_familyMembers.isEmpty)
            _emptyPanel(
              icon: Icons.family_restroom_rounded,

              title: _t(
                'Start Your Family Health Journey',
                'परिवार की शुरुआत करें',
              ),

              message: _t(
                'No family profiles exist yet. '
                    'Open Child Care to add your child.',
                'अभी कोई प्रोफाइल नहीं है। '
                    'बच्चा जोड़ने के लिए चाइल्ड केयर खोलें।',
              ),

              button: _t(
                'Open Child Care',
                'चाइल्ड केयर खोलें',
              ),

              onPressed: _openChildCare,
            )

          // ====================================================
          // FAMILY MEMBER LIST
          // ====================================================

          else
            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns =
                    constraints.maxWidth >= 720;

                final cardWidth = twoColumns
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,

                  runSpacing: 12,

                  children: [
                    for (final member in _familyMembers)
                      SizedBox(
                        width: cardWidth,

                        child: _familyMemberCard(
                          member,
                        ),
                      ),
                  ],
                );
              },
            ),

        const SizedBox(height: 20),

        // ====================================================
        // CHILD CARE SHORTCUT
        // ====================================================

        _panel(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,

            children: [
              Text(
                _t(
                  'Child Care',
                  'चाइल्ड केयर',
                ),

                style: const TextStyle(
                  color: _PatientColors.navy,

                  fontSize: 17,

                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 7),

              Text(
                _t(
                  'Add a child, track vaccinations, '
                      'view health reports and monitor growth.',
                  'बच्चे की प्रोफाइल, टीके, '
                      'रिपोर्ट और विकास की जानकारी देखें।',
                ),

                style: const TextStyle(
                  color: _PatientColors.muted,

                  fontSize: 12,

                  height: 1.5,
                ),
              ),

              const SizedBox(height: 14),

              FilledButton.icon(
                onPressed: _openChildCare,

                icon: const Icon(
                  Icons.child_care_rounded,
                ),

                label: Text(
                  _t(
                    'Open Child Care',
                    'चाइल्ड केयर खोलें',
                  ),
                ),

                style: FilledButton.styleFrom(
                  backgroundColor:
                  _PatientColors.navy,

                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // FAMILY MEMBER CARD
  // ==========================================================

  Widget _familyMemberCard(
      _FamilyMember member,
      ) {
    final isChild = member.module == 'child';

    final isWomen = member.module == 'women';

    final color = isChild
        ? _PatientColors.blue
        : isWomen
        ? _PatientColors.pink
        : _PatientColors.green;

    final icon = isChild
        ? Icons.child_care_rounded
        : isWomen
        ? Icons.favorite_outline_rounded
        : Icons.monitor_heart_outlined;

    final label = isChild
        ? _t(
      'Child Care',
      'चाइल्ड केयर',
    )
        : isWomen
        ? _t(
      "Women's Health",
      'महिला स्वास्थ्य',
    )
        : _t(
      'Adult Health',
      'वयस्क स्वास्थ्य',
    );

    return Material(
      color: Colors.white,

      borderRadius: BorderRadius.circular(17),

      child: InkWell(
        borderRadius: BorderRadius.circular(17),

        onTap: isChild
            ? _openChildCare
            : () {
          _openUpcomingModule(
            women: isWomen,
          );
        },

        child: Container(
          padding: const EdgeInsets.all(16),

          decoration: BoxDecoration(
            borderRadius:
            BorderRadius.circular(17),

            border: Border.all(
              color: _PatientColors.border,
            ),
          ),

          child: Row(
            children: [
              // ========================================
              // MODULE ICON
              // ========================================

              CircleAvatar(
                radius: 25,

                backgroundColor:
                color.withValues(alpha: 0.10),

                child: Icon(
                  icon,

                  color: color,

                  size: 26,
                ),
              ),

              const SizedBox(width: 12),

              // ========================================
              // MEMBER DETAILS
              // ========================================

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,

                  children: [
                    Text(
                      member.fullName,

                      maxLines: 2,

                      overflow:
                      TextOverflow.ellipsis,

                      style: const TextStyle(
                        color: _PatientColors.navy,

                        fontSize: 14,

                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      label,

                      style: const TextStyle(
                        color: _PatientColors.muted,

                        fontSize: 11,
                      ),
                    ),

                    if (member.dateOfBirth != null) ...[
                      const SizedBox(height: 4),

                      Text(
                        'DOB: ${_formatDate(member.dateOfBirth!)}',

                        style: const TextStyle(
                          color: _PatientColors.muted,

                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ========================================
              // OPEN PROFILE ICON
              // ========================================

              const Icon(
                Icons.chevron_right_rounded,

                color: _PatientColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================================
  // FORMAT DATE
  // ==========================================================

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  // ==========================================================
  // SUPPORT TAB
  // ==========================================================

  Widget _buildSupport() {
    return Column(
      crossAxisAlignment:
      CrossAxisAlignment.stretch,

      children: [
        _sectionHeading(
          _t(
            'How Can We Help?',
            'हम कैसे मदद करें?',
          ),

          _t(
            'Support for your FamilyCare+ account.',
            'आपके FamilyCare+ खाते के लिए सहायता।',
          ),
        ),

        const SizedBox(height: 17),

        _emptyPanel(
          icon: Icons.support_agent_rounded,

          title: _t(
            'Support Center',
            'सहायता केंद्र',
          ),

          message: _t(
            'Verified customer support contact '
                'options will appear when configured.',
            'सहायता संपर्क उपलब्ध होने '
                'पर यहां दिखेंगे।',
          ),
        ),

        const SizedBox(height: 16),

        _buildAmbulanceSection(),
      ],
    );
  }

  // ==========================================================
  // SECTION HEADING
  // ==========================================================

  Widget _sectionHeading(
      String title,
      String description,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 12,
      ),

      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,

        children: [
          Text(
            title,

            style: const TextStyle(
              color: _PatientColors.navy,

              fontSize: 25,

              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            description,

            style: const TextStyle(
              color: _PatientColors.muted,

              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // REUSABLE PANEL
  // ==========================================================

  Widget _panel({
    required Widget child,
  }) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.all(19),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(
          color: _PatientColors.border,
        ),
      ),

      child: child,
    );
  }

  // ==========================================================
  // EMPTY / ERROR PANEL
  // ==========================================================

  Widget _emptyPanel({
    required IconData icon,
    required String title,
    required String message,
    String? button,
    VoidCallback? onPressed,
  }) {
    return Container(
      width: double.infinity,

      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 42,
      ),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius: BorderRadius.circular(24),

        border: Border.all(
          color: _PatientColors.border,
        ),
      ),

      child: Column(
        children: [
          const SizedBox(height: 4),

          CircleAvatar(
            radius: 38,

            backgroundColor: _PatientColors.lightMint,

            child: Icon(
              icon,

              color: _PatientColors.navy,

              size: 34,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            title,

            textAlign: TextAlign.center,

            style: const TextStyle(
              color: _PatientColors.navy,

              fontSize: 20,

              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 9),

          Text(
            message,

            textAlign: TextAlign.center,

            style: const TextStyle(
              color: _PatientColors.muted,

              fontSize: 13,

              height: 1.5,
            ),
          ),

          if (button != null &&
              onPressed != null) ...[
            const SizedBox(height: 22),

            FilledButton.icon(
              onPressed: onPressed,

              icon: const Icon(
                Icons.arrow_forward_rounded,
              ),

              label: Text(button),

              style: FilledButton.styleFrom(
                backgroundColor:
                _PatientColors.navy,

                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================
// DASHBOARD LOCAL IMAGE
// ============================================================

class _DashboardAssetPhoto extends StatelessWidget {
  final String path;

  final IconData fallback;

  final Color fallbackColor;

  const _DashboardAssetPhoto({
    required this.path,
    required this.fallback,
    required this.fallbackColor,
  });

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      path,

      width: double.infinity,

      height: double.infinity,

      fit: BoxFit.cover,

      errorBuilder: (
          context,
          error,
          stackTrace,
          ) {
        return ColoredBox(
          color: fallbackColor,

          child: Center(
            child: Icon(
              fallback,

              size: 53,

              color: _PatientColors.navy,
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// WOMEN / ADULT PREVIEW SCREEN
// ============================================================

class _DashboardPreviewScreen extends StatelessWidget {
  final String title;

  final String description;

  final IconData icon;

  const _DashboardPreviewScreen({
    required this.title,
    required this.description,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _PatientColors.background,

      appBar: AppBar(
        backgroundColor: Colors.white,

        foregroundColor: _PatientColors.navy,

        title: Text(title),
      ),

      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),

            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 490,
              ),

              child: Column(
                mainAxisSize: MainAxisSize.min,

                children: [
                  // ========================================
                  // ICON
                  // ========================================

                  CircleAvatar(
                    radius: 48,

                    backgroundColor:
                    _PatientColors.lightMint,

                    child: Icon(
                      icon,

                      size: 50,

                      color: _PatientColors.navy,
                    ),
                  ),

                  const SizedBox(height: 19),

                  // ========================================
                  // TITLE
                  // ========================================

                  Text(
                    title,

                    textAlign: TextAlign.center,

                    style: const TextStyle(
                      color: _PatientColors.navy,

                      fontSize: 24,

                      fontWeight: FontWeight.w800,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ========================================
                  // DESCRIPTION
                  // ========================================

                  Text(
                    description,

                    textAlign: TextAlign.center,

                    style: const TextStyle(
                      color: _PatientColors.muted,

                      fontSize: 13,

                      height: 1.6,
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    'Screen under development',

                    style: TextStyle(
                      color: _PatientColors.muted,

                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(height: 17),

                  // ========================================
                  // BACK BUTTON
                  // ========================================

                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },

                    icon: const Icon(
                      Icons.arrow_back_rounded,
                    ),

                    label: const Text(
                      'Back to Family Dashboard',
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
}
