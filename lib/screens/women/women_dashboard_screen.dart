import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

// ============================================================
// FAMILYCARE+ — WOMEN'S HEALTH DASHBOARD (FOUNDATION / V1)
// ============================================================
// Verified existing Flask v5 endpoints:
// GET  /api/v1/patients/profiles?module=women&page=1&per_page=100
// POST /api/v1/patients/profiles  {profile_type,module,full_name,date_of_birth}
// GET  /api/v1/patients/profiles/{profileId}
//
// Women's Health tracking endpoints (periods, symptoms, pregnancy,
// PCOS, etc.) are NOT implemented in the supplied v5 backend.
// Topic cards explicitly show an unavailable-feature message until a
// dedicated screen is wired by onOpenTopic.
//
// This is an independent dashboard screen. It does NOT change
// Child Care, the existing patient dashboard, or main.dart.
// ============================================================

class _WHColor {
  static const background = Color(0xFFF5F8FC);
  static const white = Colors.white;
  static const navy = Color(0xFF183C60);
  static const body = Color(0xFF345166);
  static const muted = Color(0xFF71869A);
  static const border = Color(0xFFE1EAF3);
  static const teal = Color(0xFF238B85);
  static const blue = Color(0xFF327DE4);
  static const rose = Color(0xFFD17993);
  static const lavender = Color(0xFF8867C7);
  static const orange = Color(0xFFC88B45);
  static const red = Color(0xFFB94D58);
  static const softTeal = Color(0xFFE8F6F4);
  static const softRose = Color(0xFFFFEFF4);
  static const softBlue = Color(0xFFECF4FF);
}

class WomenHealthTopic {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;

  const WomenHealthTopic({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class _WomenTopicGroup {
  final String title;
  final String subtitle;
  final List<WomenHealthTopic> topics;

  const _WomenTopicGroup(this.title, this.subtitle, this.topics);
}

// All 16 requested gynecology/reproductive-health topics.
// General adult chronic diseases intentionally belong in Adult Health.
const List<_WomenTopicGroup> _womenTopicGroups = [
  _WomenTopicGroup(
    'Periods & Hormonal Health',
    'Track cycles, symptoms and hormonal concerns',
    [
      WomenHealthTopic(
        id: 'menstrual-cycle',
        title: 'Menstrual Cycle',
        description: 'Period dates, cycle history and personal tracking',
        icon: Icons.calendar_month_outlined,
        color: _WHColor.rose,
      ),
      WomenHealthTopic(
        id: 'irregular-periods',
        title: 'Irregular Periods',
        description: 'Record cycle changes and irregular bleeding',
        icon: Icons.event_repeat_rounded,
        color: _WHColor.lavender,
      ),
      WomenHealthTopic(
        id: 'period-pain-pms',
        title: 'Period Pain & PMS',
        description: 'Log cramps, discomfort and premenstrual symptoms',
        icon: Icons.monitor_heart_outlined,
        color: _WHColor.rose,
      ),
      WomenHealthTopic(
        id: 'pcos-pcod',
        title: 'PCOS / PCOD',
        description: 'Organize symptoms, reports and doctor observations',
        icon: Icons.insights_outlined,
        color: _WHColor.lavender,
      ),
    ],
  ),
  _WomenTopicGroup(
    'Gynecological Concerns',
    'Keep symptom notes and medical reports together',
    [
      WomenHealthTopic(
        id: 'vaginal-health',
        title: 'Vaginal Health & Infections',
        description: 'Private symptom and consultation records',
        icon: Icons.health_and_safety_outlined,
        color: _WHColor.teal,
      ),
      WomenHealthTopic(
        id: 'uti',
        title: 'Urinary Tract Infections',
        description: 'Record symptoms, tests and consultation history',
        icon: Icons.water_drop_outlined,
        color: _WHColor.blue,
      ),
      WomenHealthTopic(
        id: 'pelvic-pain-endometriosis',
        title: 'Pelvic Pain & Endometriosis',
        description: 'Track episodes and supporting medical documents',
        icon: Icons.favorite_border_rounded,
        color: _WHColor.rose,
      ),
      WomenHealthTopic(
        id: 'fibroids-cysts',
        title: 'Fibroids & Ovarian Cysts',
        description: 'Store scan history and follow-up notes',
        icon: Icons.document_scanner_outlined,
        color: _WHColor.lavender,
      ),
    ],
  ),
  _WomenTopicGroup(
    'Fertility & Motherhood',
    'Organize reproductive and maternity care',
    [
      WomenHealthTopic(
        id: 'contraception',
        title: 'Contraception & Family Planning',
        description: 'Personal planning notes and doctor discussions',
        icon: Icons.shield_outlined,
        color: _WHColor.teal,
      ),
      WomenHealthTopic(
        id: 'fertility-ovulation',
        title: 'Fertility & Ovulation',
        description: 'Cycle observations and fertility consultation records',
        icon: Icons.spa_outlined,
        color: _WHColor.rose,
      ),
      WomenHealthTopic(
        id: 'pregnancy',
        title: 'Pregnancy Care',
        description: 'Visits, tests, reports and prenatal timeline',
        icon: Icons.pregnant_woman_rounded,
        color: _WHColor.lavender,
      ),
      WomenHealthTopic(
        id: 'postpartum',
        title: 'Postpartum Care',
        description: 'Recovery observations and follow-up records',
        icon: Icons.volunteer_activism_outlined,
        color: _WHColor.teal,
      ),
    ],
  ),
  _WomenTopicGroup(
    'Prevention & Life Stages',
    'Screening and age-related gynecology care',
    [
      WomenHealthTopic(
        id: 'menopause',
        title: 'Menopause & Perimenopause',
        description: 'Changes, symptoms and follow-up history',
        icon: Icons.wb_sunny_outlined,
        color: _WHColor.orange,
      ),
      WomenHealthTopic(
        id: 'cervical-hpv',
        title: 'Cervical Health & HPV',
        description: 'Screening and HPV vaccination records',
        icon: Icons.verified_user_outlined,
        color: _WHColor.blue,
      ),
      WomenHealthTopic(
        id: 'breast-health',
        title: 'Breast Health',
        description: 'Breast screening and medical report history',
        icon: Icons.favorite_outline_rounded,
        color: _WHColor.rose,
      ),
      WomenHealthTopic(
        id: 'puberty-adolescent',
        title: 'Puberty & Adolescent Gynecology',
        description: 'Age-appropriate care and consultation notes',
        icon: Icons.auto_awesome_outlined,
        color: _WHColor.teal,
      ),
    ],
  ),
];

class _WomanProfile {
  final String id;
  final String fullName;
  final String profileType;
  final DateTime? dob;
  final Map<String, dynamic>? doctor;

  const _WomanProfile({
    required this.id,
    required this.fullName,
    required this.profileType,
    this.dob,
    this.doctor,
  });

  factory _WomanProfile.fromJson(Map<String, dynamic> value) {
    final rawDoctor = value['doctor'];
    return _WomanProfile(
      id: (value['id'] ?? '').toString(),
      fullName: (value['full_name'] ?? '').toString().trim(),
      profileType: (value['profile_type'] ?? '').toString(),
      dob: DateTime.tryParse((value['date_of_birth'] ?? '').toString()),
      doctor: rawDoctor is Map
          ? Map<String, dynamic>.from(rawDoctor)
          : null,
    );
  }
}

class WomenDashboardScreen extends StatefulWidget {
  final String apiBaseUrl;

  // Wire these callbacks after the individual Women's Health screens exist.
  // They receive the selected Women profile ID, not the account holder ID.
  final void Function(
      BuildContext context,
      String topicId,
      String profileId,
      )? onOpenTopic;

  final void Function(
      BuildContext context,
      String section,
      String profileId,
      )? onOpenSection;

  const WomenDashboardScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.onOpenTopic,
    this.onOpenSection,
  });

  @override
  State<WomenDashboardScreen> createState() => _WomenDashboardScreenState();
}

class _WomenDashboardScreenState extends State<WomenDashboardScreen> {
  final http.Client _client = http.Client();
  final TextEditingController _search = TextEditingController();
  final List<_WomanProfile> _profiles = [];

  _WomanProfile? _selected;
  bool _loading = true;
  bool _creating = false;
  String? _error;
  int _revision = 0;

  String get _baseUrl {
    final configured = widget.apiBaseUrl.trim();
    if (configured.isNotEmpty) {
      return configured.replaceAll(RegExp(r'/+$'), '');
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5001';
    }
    return 'http://127.0.0.1:5001';
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_onSearch);
    _loadProfiles();
  }

  @override
  void didUpdateWidget(covariant WomenDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _revision++;
      _profiles.clear();
      _selected = null;
      _loadProfiles();
    }
  }

  @override
  void dispose() {
    _revision++;
    _client.close();
    _search.removeListener(_onSearch);
    _search.dispose();
    super.dispose();
  }

  void _onSearch() {
    if (mounted) setState(() {});
  }

  Future<Map<String, String>> _headers() async {
    final token = await FamilyCareSession.accessToken();
    if (token == null || token.trim().isEmpty) {
      throw const _WomenApiException(
        'Login session missing. Please sign in again.',
      );
    }
    return {
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> _request(
      String method,
      String path, {
        Map<String, dynamic>? payload,
      }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final headers = await _headers();
    late http.Response response;
    if (method == 'GET') {
      response = await _client.get(uri, headers: headers)
          .timeout(const Duration(seconds: 35));
    } else if (method == 'POST') {
      response = await _client.post(
        uri,
        headers: headers,
        body: jsonEncode(payload ?? {}),
      ).timeout(const Duration(seconds: 35));
    } else {
      throw const _WomenApiException('Unsupported request method.');
    }

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException();
      data = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const _WomenApiException('Invalid server response.');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String message = 'Request failed (HTTP ${response.statusCode}).';
      final error = data['error'];
      if (error is Map && error['message'] is String) {
        message = error['message'] as String;
      } else if (error is String && error.isNotEmpty) {
        message = error;
      }
      if (response.statusCode == 401) {
        message = 'Session expired. Please sign in again.';
      }
      if (response.statusCode == 409 && method == 'POST') {
        message = '$message You can add a member profile instead.';
      }
      throw _WomenApiException(message);
    }
    return data;
  }

  String _friendlyError(Object error) {
    if (error is _WomenApiException) return error.message;
    if (error is TimeoutException) return 'Server timed out. Try again.';
    if (error is http.ClientException) {
      return 'Cannot reach FamilyCare+ backend. Check your API URL.';
    }
    if (error is PlatformException) return 'Cannot read your login session.';
    return 'Something went wrong. Please retry.';
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? _WHColor.red : _WHColor.navy,
        content: Text(message),
      ));
  }

  Future<void> _loadProfiles({String? preferredId}) async {
    final revision = ++_revision;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = <_WomanProfile>[];
      for (var page = 1; page <= 100; page++) {
        final response = await _request(
          'GET',
          '/api/v1/patients/profiles?module=women&page=$page&per_page=100',
        );
        final items = response['items'];
        if (items is! List) {
          throw const _WomenApiException('Invalid women profile list.');
        }
        for (final item in items) {
          if (item is! Map) continue;
          final map = Map<String, dynamic>.from(item);
          if (map['module'] != 'women') continue;
          final profile = _WomanProfile.fromJson(map);
          if (profile.id.isNotEmpty) result.add(profile);
        }
        final total = response['total'];
        if (items.length < 100 ||
            (total is num && result.length >= total.toInt())) {
          break;
        }
      }
      if (!mounted || revision != _revision) return;
      final wanted = preferredId ?? _selected?.id;
      _WomanProfile? selected;
      for (final profile in result) {
        if (profile.id == wanted) {
          selected = profile;
          break;
        }
      }
      setState(() {
        _profiles
          ..clear()
          ..addAll(result);
        _selected = selected ?? (result.isNotEmpty ? result.first : null);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _createProfile() async {
    if (_creating || _loading) return;
    final draft = await showModalBottomSheet<_WomenProfileDraft>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _CreateWomenProfileSheet(),
    );
    if (draft == null || !mounted) return;
    final revision = _revision;
    setState(() => _creating = true);
    try {
      final result = await _request(
        'POST',
        '/api/v1/patients/profiles',
        payload: {
          'profile_type': draft.profileType,
          'module': 'women',
          'full_name': draft.fullName,
          'date_of_birth': draft.birthDate,
        },
      );
      if (!mounted || revision != _revision) return;
      final raw = result['profile'];
      if (raw is! Map || raw['module'] != 'women') {
        throw const _WomenApiException(
          'Profile was submitted, but the response was incomplete. Refresh.',
        );
      }
      final id = (raw['id'] ?? '').toString();
      await _loadProfiles(preferredId: id);
      if (mounted) _showMessage('Women profile created successfully.');
    } catch (error) {
      if (mounted && revision == _revision) {
        _showMessage(_friendlyError(error), isError: true);
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _openTopic(WomenHealthTopic topic) {
    final profile = _selected;
    if (profile == null) {
      _showMessage('Create or select a Women profile first.', isError: true);
      return;
    }
    final callback = widget.onOpenTopic;
    if (callback != null) {
      callback(context, topic.id, profile.id);
      return;
    }
    _showMessage(
      '${topic.title} tracking is not connected yet. '
          'This screen and its API will be built next.',
    );
  }

  void _openSection(String section) {
    final profile = _selected;
    if (profile == null) {
      _showMessage('Select a Women profile first.', isError: true);
      return;
    }
    final callback = widget.onOpenSection;
    if (callback == null) {
      _showMessage('The $section screen has not been connected yet.');
      return;
    }
    callback(context, section, profile.id);
  }

  List<WomenHealthTopic> _filteredTopics(List<WomenHealthTopic> topics) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return topics;
    return topics.where((item) =>
    item.title.toLowerCase().contains(query) ||
        item.description.toLowerCase().contains(query)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _WHColor.background,
      appBar: AppBar(
        backgroundColor: _WHColor.white,
        foregroundColor: _WHColor.navy,
        surfaceTintColor: Colors.white,
        title: const Text(
          "Women's Health",
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh Women profiles',
            onPressed: _creating || _loading ? null : _loadProfiles,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (!_creating) await _loadProfiles();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 44),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hero(),
                    const SizedBox(height: 18),
                    _profileSection(),
                    const SizedBox(height: 19),
                    if (_selected != null) ...[
                      _quickActions(),
                      const SizedBox(height: 21),
                    ],
                    _topicsHeader(),
                    const SizedBox(height: 18),
                    for (final group in _womenTopicGroups) ...[
                      _topicSection(group),
                      const SizedBox(height: 19),
                    ],
                    _privacyNotice(),
                    const SizedBox(height: 24),
                    const Center(
                      child: Text(
                        'FamilyCare+ • Private, respectful care for every stage',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _WHColor.muted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(21),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFEBF2), Color(0xFFEDF4FF), Color(0xFFEAF8F4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "WOMEN'S WELLNESS",
                  style: TextStyle(
                    color: _WHColor.teal,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your health, your space.',
                  style: TextStyle(
                    color: _WHColor.navy,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'One place for reproductive health, reports, '
                      'personal observations and care across life stages.',
                  style: TextStyle(color: _WHColor.body, fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const CircleAvatar(
            radius: 34,
            backgroundColor: Colors.white,
            child: Icon(Icons.favorite_border_rounded,
                color: _WHColor.rose, size: 35),
          ),
        ],
      ),
    );
  }

  Widget _surface({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: _WHColor.border),
      ),
      child: child,
    );
  }

  Widget _profileSection() {
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_outline_rounded,
                  color: _WHColor.teal, size: 25),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Women Profiles',
                  style: TextStyle(color: _WHColor.navy,
                      fontWeight: FontWeight.w800, fontSize: 17),
                ),
              ),
              FilledButton.icon(
                onPressed: _creating || _loading ? null : _createProfile,
                style: FilledButton.styleFrom(
                  backgroundColor: _WHColor.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(_creating ? 'Saving...' : 'Add Profile'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose whose information to view. Each profile has separate records.',
            style: TextStyle(color: _WHColor.muted, fontSize: 12),
          ),
          const SizedBox(height: 15),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Column(
              children: [
                Text(_error!,
                    style: const TextStyle(color: _WHColor.red, fontSize: 12)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loadProfiles,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            )
          else if (_profiles.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _WHColor.softRose,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.person_add_alt_1_outlined,
                        color: _WHColor.rose, size: 28),
                    SizedBox(height: 8),
                    Text('No Women profile yet',
                        style: TextStyle(color: _WHColor.navy,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 5),
                    Text('Tap Add Profile to create the first one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _WHColor.body, fontSize: 12)),
                  ],
                ),
              )
            else ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _profiles.map((profile) {
                      final active = _selected?.id == profile.id;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          selected: active,
                          showCheckmark: false,
                          selectedColor: _WHColor.softTeal,
                          side: BorderSide(color: active
                              ? _WHColor.teal : _WHColor.border),
                          avatar: const Icon(Icons.person_outline_rounded,
                              size: 19, color: _WHColor.teal),
                          label: Text(profile.fullName.isEmpty
                              ? 'Profile' : profile.fullName),
                          onSelected: (_) => setState(() => _selected = profile),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 15),
                if (_selected != null) _selectedProfileCard(_selected!),
              ],
        ],
      ),
    );
  }

  Widget _selectedProfileCard(_WomanProfile profile) {
    final doctor = profile.doctor;
    final doctorName = doctor?['full_name']?.toString().trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _WHColor.softBlue,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(profile.fullName,
              style: const TextStyle(fontWeight: FontWeight.w800,
                  color: _WHColor.navy, fontSize: 15)),
          const SizedBox(height: 5),
          Text(
            '${profile.profileType == 'self' ? 'Self' : 'Family member'} profile'
                '${profile.dob == null ? '' : ' • DOB ${_date(profile.dob!)}'}',
            style: const TextStyle(color: _WHColor.body, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            doctorName != null && doctorName.isNotEmpty
                ? 'Linked doctor: $doctorName'
                : 'No linked doctor',
            style: const TextStyle(color: _WHColor.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _quickActions() {
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Profile & Records',
              style: TextStyle(color: _WHColor.navy,
                  fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 7),
          const Text(
            'These actions use shared profile/report APIs when their screens are connected.',
            style: TextStyle(color: _WHColor.muted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              _actionButton('Health Reports', Icons.folder_copy_outlined,
                      () => _openSection('health-reports')),
              _actionButton('Doctor Connection', Icons.medical_services_outlined,
                      () => _openSection('doctor')),
              _actionButton('Profile Settings', Icons.settings_outlined,
                      () => _openSection('settings')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _WHColor.navy,
        side: const BorderSide(color: _WHColor.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      icon: Icon(icon, size: 18, color: _WHColor.teal),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Widget _topicsHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Explore Women’s Health',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800,
                color: _WHColor.navy)),
        const SizedBox(height: 6),
        const Text(
          '16 dedicated gynecology topics. Tracking screens and APIs '
              'will be connected step by step.',
          style: TextStyle(fontSize: 12, color: _WHColor.muted),
        ),
        const SizedBox(height: 13),
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'Search women’s health topics...',
            prefixIcon: const Icon(Icons.search_rounded,
                color: _WHColor.teal),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
              tooltip: 'Clear search',
              onPressed: _search.clear,
              icon: const Icon(Icons.close_rounded),
            ),
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(color: _WHColor.border),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        ),
      ],
    );
  }

  Widget _topicSection(_WomenTopicGroup group) {
    final topics = _filteredTopics(group.topics);
    if (topics.isEmpty) return const SizedBox.shrink();
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(group.title, style: const TextStyle(
              color: _WHColor.navy, fontWeight: FontWeight.w800,
              fontSize: 17)),
          const SizedBox(height: 5),
          Text(group.subtitle, style: const TextStyle(
              color: _WHColor.muted, fontSize: 11)),
          const SizedBox(height: 15),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 660;
            final gap = 10.0;
            final width = wide
                ? (constraints.maxWidth - gap) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: topics.map((topic) => SizedBox(
                width: width,
                child: _topicTile(topic),
              )).toList(),
            );
          }),
        ],
      ),
    );
  }

  Widget _topicTile(WomenHealthTopic topic) {
    return Material(
      color: _WHColor.background,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: () => _openTopic(topic),
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: topic.color.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(topic.icon, size: 23, color: topic.color),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(topic.title,
                        style: const TextStyle(color: _WHColor.navy,
                            fontSize: 13, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(topic.description,
                        style: const TextStyle(color: _WHColor.muted,
                            fontSize: 10.5, height: 1.4)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded,
                  color: _WHColor.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _privacyNotice() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _WHColor.softTeal,
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, color: _WHColor.teal, size: 20),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'Personal health records can be sensitive. Only the shared '
                  'profile functions are connected today. Topic trackers '
                  'need dedicated backend storage and access controls before '
                  'they can save personal observations. This screen does not '
                  'provide medical diagnoses.',
              style: TextStyle(color: _WHColor.body,
                  fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
}

class _WomenApiException implements Exception {
  final String message;
  const _WomenApiException(this.message);
  @override
  String toString() => message;
}

class _WomenProfileDraft {
  final String fullName;
  final String profileType;
  final String birthDate;
  const _WomenProfileDraft(this.fullName, this.profileType, this.birthDate);
}

class _CreateWomenProfileSheet extends StatefulWidget {
  const _CreateWomenProfileSheet();

  @override
  State<_CreateWomenProfileSheet> createState() =>
      _CreateWomenProfileSheetState();
}

class _CreateWomenProfileSheetState extends State<_CreateWomenProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  DateTime? _dob;
  String _profileType = 'member';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final chosen = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(today.year - 25, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'DATE OF BIRTH',
    );
    if (chosen != null && mounted) setState(() => _dob = chosen);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_dob == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select date of birth.')),
      );
      return;
    }
    final date = _dob!;
    final apiDate = '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    Navigator.pop(context,
        _WomenProfileDraft(_name.text.trim(), _profileType, apiDate));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.90,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text('Add Women Profile',
                                style: TextStyle(fontSize: 22,
                                    color: _WHColor.navy,
                                    fontWeight: FontWeight.w800)),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            tooltip: 'Close',
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Create a profile using the existing FamilyCare+ backend.',
                        style: TextStyle(color: _WHColor.muted, fontSize: 12),
                      ),
                      const SizedBox(height: 21),
                      const Text('Profile for',
                          style: TextStyle(color: _WHColor.navy,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'self', label: Text('Myself'),
                              icon: Icon(Icons.person_outline_rounded)),
                          ButtonSegment(value: 'member', label: Text('Family member'),
                              icon: Icon(Icons.people_outline_rounded)),
                        ],
                        selected: {_profileType},
                        onSelectionChanged: (selection) =>
                            setState(() => _profileType = selection.first),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'Only one Self profile is allowed per account across all modules.',
                        style: TextStyle(color: _WHColor.muted, fontSize: 11),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _name,
                        maxLength: 120,
                        textCapitalization: TextCapitalization.words,
                        inputFormatters: [LengthLimitingTextInputFormatter(120)],
                        decoration: InputDecoration(
                          labelText: 'Full name',
                          prefixIcon: const Icon(Icons.person_outline,
                              color: _WHColor.teal),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Enter the full name.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 7),
                      OutlinedButton.icon(
                        onPressed: _chooseDate,
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(_dob == null
                            ? 'Choose date of birth'
                            : 'DOB: ${_dob!.day}/${_dob!.month}/${_dob!.year}'),
                      ),
                      const SizedBox(height: 21),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: _WHColor.teal,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(52),
                          ),
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Create Profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
