import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

// ============================================================================
// FAMILYCARE+ | WOMEN'S HEALTH | PCOS / PCOD TRACKING
// ============================================================================
// Backend v5 (read only):
//   GET /api/v1/patients/profiles/{profileId}
//   GET /api/v1/patients/profiles/{profileId}/reports?page=1&per_page=20
//
// There are NO dedicated PCOS/PCOD diary CRUD endpoints in Backend v5.
// The symptom entries and self-reported clinical-assessment notes below are
// held in memory ONLY and disappear when the Flutter process restarts.
// A "Save preview" button NEVER claims that data reached the server.
//
// Existing uploaded medical reports are shown from the real backend, but are
// NOT automatically attached to session-only diary entries.
//
// This is a diary, NOT a PCOS diagnostic tool, treatment plan, or substitute
// for a clinician. No automatic diagnosis or fertility prediction is made.
// No calendar, chart, or storage plugins required.
// ============================================================================

class PcosHealthScreen extends StatefulWidget {
  final String profileId;
  final String profileName;
  final String apiBaseUrl;

  const PcosHealthScreen({
    super.key,
    required this.profileId,
    this.profileName = 'Women Profile',
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
  });

  @override
  State<PcosHealthScreen> createState() => _PcosHealthScreenState();
}

class _PcColor {
  static const bg = Color(0xFFF7F8FC);
  static const navy = Color(0xFF183C60);
  static const text = Color(0xFF334B63);
  static const muted = Color(0xFF6A7F92);
  static const rose = Color(0xFFB95879);
  static const roseLight = Color(0xFFFFEEF3);
  static const purple = Color(0xFF8465B9);
  static const purpleLight = Color(0xFFF1EDFA);
  static const teal = Color(0xFF287F83);
  static const tealLight = Color(0xFFE9F6F4);
  static const blue = Color(0xFF3275D9);
  static const blueLight = Color(0xFFEAF2FF);
  static const amber = Color(0xFF9F6A21);
  static const amberLight = Color(0xFFFFF4E3);
  static const red = Color(0xFFB94D58);
  static const border = Color(0xFFE3E9F2);
  static const white = Colors.white;
}

DateTime _pcDay(DateTime d) => DateTime(d.year, d.month, d.day);

String _pcApiDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

String _pcDateText(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

class _PcSymptom {
  final String code;
  final String title;
  final IconData icon;
  const _PcSymptom(this.code, this.title, this.icon);
}

const List<_PcSymptom> _pcSymptoms = [
  _PcSymptom('acne', 'Acne / oily skin', Icons.face_outlined),
  _PcSymptom('facial_hair', 'Increased facial/body hair', Icons.person_outline),
  _PcSymptom('hair_thinning', 'Scalp hair thinning', Icons.spa_outlined),
  _PcSymptom('pelvic_discomfort', 'Pelvic discomfort', Icons.favorite_border),
  _PcSymptom('bloating', 'Bloating', Icons.bubble_chart_outlined),
  _PcSymptom('fatigue', 'Fatigue', Icons.bedtime_outlined),
  _PcSymptom('sleep', 'Sleep changes', Icons.nights_stay_outlined),
  _PcSymptom('mood', 'Mood changes', Icons.mood_outlined),
  _PcSymptom('skin_changes', 'Darkened skin patches', Icons.palette_outlined),
  _PcSymptom('headache', 'Headache', Icons.psychology_outlined),
  _PcSymptom('cravings', 'Appetite / cravings', Icons.restaurant_outlined),
  _PcSymptom('other', 'Other concern', Icons.more_horiz_rounded),
];

String _pcSymptomName(String code) {
  for (final symptom in _pcSymptoms) {
    if (symptom.code == code) return symptom.title;
  }
  return code;
}

String _pcSeverityName(int level) {
  if (level == 1) return 'Mild';
  if (level == 2) return 'Moderate';
  if (level == 3) return 'Severe';
  return 'Unspecified';
}

const _cycleChoices = [
  'Not recorded',
  'Regular / expected',
  'Irregular timing',
  'Period delayed',
  'No period recently',
  'Spotting / unexpected bleeding',
  'Not sure',
];

const _assessmentChoices = [
  'Not discussed with a clinician',
  'Being assessed by a clinician',
  'Clinician told me PCOS',
  'Clinician told me PCOD',
  'Other clinician assessment',
];

class _PcEntry {
  final String id;
  final DateTime date;
  final String cyclePattern;
  final Map<String, int> symptoms;
  final int? discomfort;
  final String assessment;
  final DateTime? consultationDate;
  final String doctorNotes;
  final String personalNotes;

  const _PcEntry({
    required this.id,
    required this.date,
    required this.cyclePattern,
    required this.symptoms,
    required this.discomfort,
    required this.assessment,
    required this.consultationDate,
    required this.doctorNotes,
    required this.personalNotes,
  });

  bool get hasCycleConcern =>
      cyclePattern == 'Irregular timing' ||
          cyclePattern == 'Period delayed' ||
          cyclePattern == 'No period recently' ||
          cyclePattern == 'Spotting / unexpected bleeding';

  bool get hasClinicianAssessment =>
      assessment != _assessmentChoices.first;

  bool get isClinicianReportedDiagnosis =>
      assessment == 'Clinician told me PCOS' ||
          assessment == 'Clinician told me PCOD';
}

// Only the active Flutter process can access these entries.
class _PcSessionPreview {
  static final Map<String, List<_PcEntry>> _records = {};

  static List<_PcEntry> read(String id) =>
      List<_PcEntry>.from(_records[id] ?? const <_PcEntry>[]);

  static void write(String id, List<_PcEntry> entries) {
    _records[id] = List<_PcEntry>.from(entries);
  }

  static void clear(String id) => _records.remove(id);
}

class _PcReport {
  final String id;
  final String name;
  final String category;
  final DateTime? uploaded;

  const _PcReport({
    required this.id,
    required this.name,
    required this.category,
    required this.uploaded,
  });

  factory _PcReport.fromJson(Map<String, dynamic> json) => _PcReport(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? 'Medical report').toString(),
    category: (json['category'] ?? 'Not categorized').toString(),
    uploaded: DateTime.tryParse((json['created_at'] ?? '').toString())
        ?.toLocal(),
  );
}

class _PcosHealthScreenState extends State<PcosHealthScreen> {
  final http.Client _client = http.Client();
  final TextEditingController _search = TextEditingController();

  List<_PcEntry> _entries = [];
  final List<_PcReport> _reports = [];
  DateTime? _profileDob;
  String? _verifiedName;
  String? _profileError;
  String? _reportsError;
  bool _verifying = true;
  bool _reportsLoading = false;
  bool _moreLoading = false;
  int _reportsPage = 0;
  int _reportsTotal = 0;
  int _generation = 0;
  String _filter = 'all';

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

  String get _displayName => (_verifiedName?.isNotEmpty ?? false)
      ? _verifiedName!
      : widget.profileName;

  bool get _profileReady => !_verifying && _profileError == null;

  @override
  void initState() {
    super.initState();
    _entries = _PcSessionPreview.read(widget.profileId);
    _search.addListener(_searchChanged);
    _verifyAndLoad();
  }

  @override
  void didUpdateWidget(covariant PcosHealthScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _generation++;
      _entries = _PcSessionPreview.read(widget.profileId);
      _reports.clear();
      _reportsPage = 0;
      _reportsTotal = 0;
      _reportsLoading = false;
      _moreLoading = false;
      _verifiedName = null;
      _profileDob = null;
      _profileError = null;
      _reportsError = null;
      _filter = 'all';
      _search.clear();
      _verifyAndLoad();
    }
  }

  @override
  void dispose() {
    _generation++;
    _search.removeListener(_searchChanged);
    _search.dispose();
    _client.close();
    super.dispose();
  }

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  bool _isCurrent(int generation, String profileId) =>
      mounted && generation == _generation &&
          widget.profileId.trim() == profileId;

  String _friendlyError(Object error) {
    if (error is TimeoutException) return 'Request timed out. Please retry.';
    if (error is http.ClientException) {
      return 'Unable to connect to FamilyCare+ backend.';
    }
    if (error is FormatException) return error.message;
    return 'Unable to load data. Please try again.';
  }

  Future<Map<String, dynamic>> _getJson(String path) async {
    final token = await FamilyCareSession.accessToken();
    if (token == null || token.trim().isEmpty) {
      throw const FormatException('Login session missing. Sign in again.');
    }
    final response = await _client.get(
      Uri.parse('$_baseUrl$path'),
      headers: {
        'Authorization': 'Bearer $token',
        'X-Auth-Transport': 'bearer',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 35));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401) {
        throw const FormatException('Login expired. Please sign in again.');
      }
      if (response.statusCode == 403) {
        throw const FormatException('Access to Women profile denied.');
      }
      if (response.statusCode == 404) {
        throw const FormatException('Women profile not found.');
      }
      throw FormatException('Request failed (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('Invalid JSON response.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  String _profilePath(String id) =>
      '/api/v1/patients/profiles/${Uri.encodeComponent(id)}';

  Future<void> _verifyAndLoad() async {
    final generation = ++_generation;
    final id = widget.profileId.trim();
    setState(() {
      _verifying = true;
      _profileError = null;
      _reportsError = null;
      _reportsLoading = false;
      _moreLoading = false;
    });
    try {
      if (id.isEmpty) {
        throw const FormatException('Women profile ID is required.');
      }
      final result = await _getJson(_profilePath(id));
      final raw = result['profile'];
      if (raw is! Map) {
        throw const FormatException('Profile details are incomplete.');
      }
      final profile = Map<String, dynamic>.from(raw);
      if (profile['module'] != 'women' ||
          profile['id']?.toString() != id) {
        throw const FormatException('Select a valid Women profile.');
      }
      if (!_isCurrent(generation, id)) return;
      setState(() {
        _verifiedName = (profile['full_name'] ?? '').toString().trim();
        _profileDob = DateTime.tryParse(
            (profile['date_of_birth'] ?? '').toString());
        _verifying = false;
      });
      await _loadReports(reset: true);
    } catch (error) {
      if (!_isCurrent(generation, id)) return;
      setState(() {
        _verifying = false;
        _profileError = _friendlyError(error);
        _reports.clear();
        _reportsPage = 0;
        _reportsTotal = 0;
      });
    }
  }

  Future<void> _loadReports({bool reset = false}) async {
    if (!_profileReady || _moreLoading || _reportsLoading) return;
    final generation = _generation;
    final id = widget.profileId.trim();
    final nextPage = reset ? 1 : _reportsPage + 1;
    setState(() {
      if (reset) {
        _reportsLoading = true;
      } else {
        _moreLoading = true;
      }
      _reportsError = null;
    });

    try {
      final data = await _getJson(
        '${_profilePath(id)}/reports?page=$nextPage&per_page=20',
      );
      if (data['items'] is! List) {
        throw const FormatException('Invalid medical report list.');
      }
      final rows = <_PcReport>[];
      for (final raw in data['items'] as List) {
        if (raw is! Map) continue;
        final report = Map<String, dynamic>.from(raw);
        if (report['profile_id']?.toString() != id) continue;
        final parsed = _PcReport.fromJson(report);
        if (parsed.id.isNotEmpty) rows.add(parsed);
      }
      if (!_isCurrent(generation, id)) return;
      setState(() {
        if (reset) {
          _reports.clear();
        }
        final ids = _reports.map((r) => r.id).toSet();
        for (final row in rows) {
          if (ids.add(row.id)) _reports.add(row);
        }
        _reportsPage = nextPage;
        final total = data['total'];
        _reportsTotal = total is num ? total.toInt() : _reports.length;
      });
    } catch (error) {
      if (_isCurrent(generation, id)) {
        setState(() => _reportsError = _friendlyError(error));
      }
    } finally {
      if (_isCurrent(generation, id)) {
        setState(() {
          _reportsLoading = false;
          _moreLoading = false;
        });
      }
    }
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? _PcColor.red : _PcColor.navy,
        behavior: SnackBarBehavior.floating,
      ));
  }

  List<_PcEntry> get _visibleEntries {
    final query = _search.text.trim().toLowerCase();
    final found = _entries.where((entry) {
      if (_filter == 'cycle' && !entry.hasCycleConcern) return false;
      if (_filter == 'symptoms' && entry.symptoms.isEmpty) return false;
      if (_filter == 'review' && !entry.hasClinicianAssessment) return false;
      if (query.isEmpty) return true;
      final searchable = [
        _pcDateText(entry.date),
        entry.cyclePattern,
        entry.assessment,
        entry.personalNotes,
        entry.doctorNotes,
        ...entry.symptoms.keys.map(_pcSymptomName),
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();
    found.sort((a, b) => b.date.compareTo(a.date));
    return found;
  }

  _PcEntry? _entryOn(DateTime date) {
    for (final entry in _entries) {
      if (_pcDay(entry.date) == _pcDay(date)) return entry;
    }
    return null;
  }

  Future<void> _openEditor({_PcEntry? existing, DateTime? initialDate}) async {
    if (!_profileReady) {
      _snack('Verify the Women profile before adding entries.', error: true);
      return;
    }
    final profileId = widget.profileId;
    final date = _pcDay(initialDate ?? DateTime.now());
    final entry = existing ?? _entryOn(date);
    final result = await showModalBottomSheet<_PcEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PcEditor(
        original: entry,
        initialDate: date,
        birthDate: _profileDob,
        occupiedDates: _entries
            .where((e) => e.id != entry?.id)
            .map((e) => _pcDay(e.date))
            .toList(),
      ),
    );
    if (!mounted || result == null || profileId != widget.profileId) return;
    final revised = List<_PcEntry>.from(_entries);
    final index = revised.indexWhere((e) => e.id == result.id);
    if (index >= 0) {
      revised[index] = result;
    } else {
      revised.add(result);
    }
    revised.sort((a, b) => b.date.compareTo(a.date));
    _PcSessionPreview.write(profileId, revised);
    setState(() => _entries = revised);
    _snack('Preview updated for this app session only. Not saved to backend.');
  }

  Future<void> _delete(_PcEntry entry) async {
    if (!_profileReady) return;
    final profileId = widget.profileId;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this preview entry?'),
        content: Text('Remove the entry for ${_pcDateText(entry.date)}? '
            'Only this session-only draft will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _PcColor.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete preview'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true || profileId != widget.profileId) return;
    final revised = _entries.where((e) => e.id != entry.id).toList();
    _PcSessionPreview.write(profileId, revised);
    setState(() => _entries = revised);
    _snack('Preview entry deleted. No backend record was changed.');
  }

  Future<void> _clearPreviews() async {
    if (_entries.isEmpty) return;
    final id = widget.profileId;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all preview entries?'),
        content: const Text('This clears only temporary PCOS diary entries '
            'for this Women profile. Existing uploaded reports remain untouched.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _PcColor.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear previews'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true || id != widget.profileId) return;
    _PcSessionPreview.clear(id);
    setState(() => _entries = []);
    _snack('Temporary preview entries cleared.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _PcColor.bg,
      appBar: AppBar(
        title: const Text('PCOS / PCOD Health',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: _PcColor.navy,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh profile and reports',
            onPressed: _verifying ? null : _verifyAndLoad,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _profileReady
          ? FloatingActionButton.extended(
        onPressed: _openEditor,
        backgroundColor: _PcColor.rose,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add observation'),
      )
          : null,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _verifyAndLoad,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 105),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _hero(),
                      const SizedBox(height: 16),
                      _notice(
                        'Session-only preview: symptom observations and '
                            'clinician-assessment notes are NOT saved to the server. '
                            'They disappear when the app restarts. Uploaded medical '
                            'reports below are fetched separately from the backend.',
                        background: _PcColor.amberLight,
                        icon: Icons.info_outline_rounded,
                        color: _PcColor.amber,
                      ),
                      const SizedBox(height: 15),
                      if (_verifying) ...[
                        const Center(child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        )),
                      ] else if (_profileError != null) ...[
                        _errorCard(_profileError!, _verifyAndLoad),
                      ] else ...[
                        _summary(),
                        const SizedBox(height: 17),
                        _quickStart(),
                        const SizedBox(height: 17),
                        _historySection(),
                        const SizedBox(height: 17),
                        _reportsSection(),
                        const SizedBox(height: 17),
                        _notice(
                          'Symptoms and menstrual irregularity can have many '
                              'causes. This diary does not diagnose PCOS/PCOD. '
                              'For severe or sudden pelvic pain, fainting, or '
                              'very heavy bleeding, seek urgent medical care.',
                          background: _PcColor.blueLight,
                          icon: Icons.health_and_safety_outlined,
                          color: _PcColor.blue,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFEDF3), Color(0xFFF0EEFC), Color(0xFFEAF6F3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        const CircleAvatar(
          radius: 30,
          backgroundColor: Colors.white,
          child: Icon(Icons.insights_rounded, size: 32, color: _PcColor.rose),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('WOMEN\'S HEALTH',
                style: TextStyle(fontSize: 10, letterSpacing: 1.5,
                    color: _PcColor.purple, fontWeight: FontWeight.w800)),
            const SizedBox(height: 7),
            const Text('PCOS / PCOD', style: TextStyle(
              fontSize: 25, fontWeight: FontWeight.w900, color: _PcColor.navy,
            )),
            const SizedBox(height: 5),
            Text('Track symptoms and clinical discussions for $_displayName.',
                style: const TextStyle(fontSize: 12, color: _PcColor.text)),
          ],
        )),
      ]),
    );
  }

  Widget _summary() {
    final symptomDays = _entries.where((e) => e.symptoms.isNotEmpty).length;
    final cycleDays = _entries.where((e) => e.hasCycleConcern).length;
    final reviewed = _entries.where((e) => e.hasClinicianAssessment).length;
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 750 ? 4 : 2;
      const spacing = 10.0;
      final width = (constraints.maxWidth - (cols - 1) * spacing) / cols;
      return Wrap(spacing: spacing, runSpacing: spacing, children: [
        _metric(width, 'Diary entries', _entries.length,
            Icons.edit_calendar_rounded, _PcColor.rose),
        _metric(width, 'Symptom days', symptomDays,
            Icons.monitor_heart_outlined, _PcColor.purple),
        _metric(width, 'Cycle concerns', cycleDays,
            Icons.event_repeat_rounded, _PcColor.teal),
        _metric(width, 'Clinical notes', reviewed,
            Icons.medical_information_outlined, _PcColor.blue),
      ]);
    });
  }

  Widget _metric(double width, String label, int number,
      IconData icon, Color color) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _PcColor.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 23, color: color),
        const SizedBox(height: 10),
        Text('$number', style: const TextStyle(fontSize: 24,
            fontWeight: FontWeight.w900, color: _PcColor.navy)),
        Text(label, style: const TextStyle(fontSize: 11, color: _PcColor.muted)),
      ]),
    );
  }

  Widget _quickStart() {
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Daily observations', Icons.fact_check_outlined),
      const SizedBox(height: 7),
      const Text('Log observed symptoms, changes in period timing, '
          'or what your clinician discussed. No diagnosis is generated.',
          style: TextStyle(fontSize: 12, color: _PcColor.muted, height: 1.5)),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, child: FilledButton.icon(
        onPressed: _openEditor,
        style: FilledButton.styleFrom(
          backgroundColor: _PcColor.rose,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 47),
        ),
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Record a daily observation (preview)'),
      )),
      const SizedBox(height: 9),
      const Text('You can log one entry per date and edit it later.',
          style: TextStyle(fontSize: 11, color: _PcColor.muted)),
    ]));
  }

  Widget _historySection() {
    final entries = _visibleEntries;
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _heading('PCOS health diary', Icons.history_rounded)),
        if (_entries.isNotEmpty)
          TextButton.icon(
            onPressed: _clearPreviews,
            icon: const Icon(Icons.delete_sweep_outlined, size: 17),
            label: const Text('Clear previews'),
            style: TextButton.styleFrom(foregroundColor: _PcColor.red),
          ),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        decoration: InputDecoration(
          hintText: 'Search dates, symptoms or notes',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _search.text.isEmpty ? null : IconButton(
            tooltip: 'Clear search',
            onPressed: _search.clear,
            icon: const Icon(Icons.close_rounded),
          ),
          filled: true,
          fillColor: _PcColor.bg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
        ),
      ),
      const SizedBox(height: 12),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(
        children: [
          _filterChip('All', 'all'),
          _filterChip('Cycle concerns', 'cycle'),
          _filterChip('Symptoms', 'symptoms'),
          _filterChip('Clinical notes', 'review'),
        ],
      )),
      const SizedBox(height: 13),
      Text('${entries.length} matching preview entries', style: const TextStyle(
        fontSize: 11, color: _PcColor.muted,
      )),
      const SizedBox(height: 11),
      if (entries.isEmpty) _emptyHistory()
      else for (final entry in entries) ...[
        _historyCard(entry),
        const SizedBox(height: 10),
      ],
    ]));
  }

  Widget _filterChip(String title, String filter) {
    final selected = _filter == filter;
    return Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(
      label: Text(title),
      selected: selected,
      showCheckmark: false,
      selectedColor: _PcColor.purpleLight,
      labelStyle: TextStyle(color: selected ? _PcColor.purple : _PcColor.text,
          fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w500),
      onSelected: (_) => setState(() => _filter = filter),
    ));
  }

  Widget _emptyHistory() {
    return Container(width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 35, horizontal: 14),
      decoration: BoxDecoration(color: _PcColor.bg,
          borderRadius: BorderRadius.circular(13)),
      child: Column(children: [
        const Icon(Icons.event_note_rounded, size: 41, color: _PcColor.purple),
        const SizedBox(height: 10),
        Text(_entries.isEmpty ? 'No observations yet' : 'No matching entries',
            style: const TextStyle(color: _PcColor.navy,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text(_entries.isEmpty
            ? 'Add an observation to start a temporary diary.'
            : 'Try another search or filter.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: _PcColor.muted)),
      ]),
    );
  }

  Widget _historyCard(_PcEntry entry) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _PcColor.bg,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _PcColor.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.calendar_today_outlined, size: 19,
              color: _PcColor.rose),
          const SizedBox(width: 9),
          Expanded(child: Text(_pcDateText(entry.date), style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800, color: _PcColor.navy,
          ))),
          const Icon(Icons.edit_note_rounded, color: _PcColor.muted, size: 17),
        ]),
        const SizedBox(height: 10),
        if (entry.cyclePattern != 'Not recorded') ...[
          _detail('Cycle observation', entry.cyclePattern),
        ],
        if (entry.discomfort != null)
          _detail('Discomfort', '${entry.discomfort}/10'),
        if (entry.symptoms.isNotEmpty) ...[
          const SizedBox(height: 7),
          Wrap(spacing: 7, runSpacing: 7, children: [
            for (final item in entry.symptoms.entries)
              _pill('${_pcSymptomName(item.key)} · ${_pcSeverityName(item.value)}',
                  _PcColor.roseLight, _PcColor.rose),
          ]),
        ],
        if (entry.hasClinicianAssessment) ...[
          const SizedBox(height: 9),
          _detail('Clinician discussion (self-reported)', entry.assessment),
          if (entry.consultationDate != null)
            _detail('Consultation date', _pcDateText(entry.consultationDate!)),
          if (entry.doctorNotes.trim().isNotEmpty)
            _detail('Clinician notes (your entry)', entry.doctorNotes),
        ],
        if (entry.personalNotes.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(entry.personalNotes, style: const TextStyle(
            fontSize: 12, color: _PcColor.text, height: 1.45,
          )),
        ],
        const Divider(height: 25),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(
            onPressed: () => _openEditor(existing: entry),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
          TextButton.icon(
            onPressed: () => _delete(entry),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: _PcColor.red),
          ),
        ]),
      ]),
    );
  }

  Widget _reportsSection() {
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Existing medical reports', Icons.folder_copy_outlined),
      const SizedBox(height: 7),
      const Text('Read-only list from this Women profile. Reports are not '
          'attached to temporary diary entries. Upload/manage reports from '
          'your Health Reports screen when it is connected.',
          style: TextStyle(fontSize: 12, color: _PcColor.muted, height: 1.5)),
      const SizedBox(height: 12),
      if (_reportsLoading) const LinearProgressIndicator(),
      if (_reportsError != null) ...[
        _notice(_reportsError!, background: _PcColor.amberLight,
            color: _PcColor.amber, icon: Icons.error_outline_rounded),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _loadReports(reset: true),
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Retry reports'),
        ),
      ] else if (!_reportsLoading && _reports.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Text('No uploaded reports found for this profile.',
              style: TextStyle(fontSize: 12, color: _PcColor.muted)),
        ),
      if (_reports.isNotEmpty) ...[
        Text('${_reports.length} loaded · $_reportsTotal total',
            style: const TextStyle(fontSize: 11, color: _PcColor.muted)),
        const SizedBox(height: 10),
        for (final report in _reports) ...[
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: _PcColor.bg,
                borderRadius: BorderRadius.circular(11)),
            child: Row(children: [
              const Icon(Icons.description_outlined, color: _PcColor.blue),
              const SizedBox(width: 10),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report.name, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _PcColor.navy,
                          fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text('${report.category} · Uploaded ${report.uploaded == null ? 'date unavailable' : _pcDateText(report.uploaded!)}',
                      style: const TextStyle(fontSize: 11, color: _PcColor.muted)),
                ],
              )),
            ]),
          ),
          const SizedBox(height: 7),
        ],
        if (_reports.length < _reportsTotal) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _moreLoading ? null : () => _loadReports(),
            icon: _moreLoading
                ? const SizedBox(width: 15, height: 15,
                child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.expand_more_rounded),
            label: Text(_moreLoading ? 'Loading...' : 'Load more reports'),
          ),
        ],
      ],
    ]));
  }

  Widget _heading(String text, IconData icon) {
    return Row(children: [
      Icon(icon, color: _PcColor.purple, size: 21),
      const SizedBox(width: 9),
      Expanded(child: Text(text, style: const TextStyle(
        color: _PcColor.navy, fontWeight: FontWeight.w900, fontSize: 17,
      ))),
    ]);
  }

  Widget _detail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 125, child: Text(label, style: const TextStyle(
          color: _PcColor.muted, fontSize: 11,
        ))),
        const SizedBox(width: 8),
        Expanded(child: Text(value, style: const TextStyle(
          color: _PcColor.text, fontSize: 11, fontWeight: FontWeight.w600,
        ))),
      ]),
    );
  }

  Widget _pill(String label, Color background, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: background,
          borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 10,
          color: textColor, fontWeight: FontWeight.w700)),
    );
  }

  Widget _card(Widget child) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: _PcColor.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _PcColor.border)),
      child: child,
    );
  }

  Widget _notice(String message, {
    required Color background,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: background,
          borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 9),
        Expanded(child: Text(message, style: const TextStyle(
          color: _PcColor.text, fontSize: 11, height: 1.5,
        ))),
      ]),
    );
  }

  Widget _errorCard(String message, Future<void> Function() onRetry) {
    return _card(Column(children: [
      const Icon(Icons.cloud_off_outlined, size: 42, color: _PcColor.amber),
      const SizedBox(height: 10),
      const Text('Unable to verify Women profile', style: TextStyle(
          fontWeight: FontWeight.w800, color: _PcColor.navy)),
      const SizedBox(height: 7),
      Text(message, textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: _PcColor.red)),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Retry'),
      ),
    ]));
  }
}

// ============================================================================
// OBSERVATION EDITOR (IN-MEMORY PREVIEW ONLY)
// ============================================================================

class _PcEditor extends StatefulWidget {
  final _PcEntry? original;
  final DateTime initialDate;
  final DateTime? birthDate;
  final List<DateTime> occupiedDates;

  const _PcEditor({
    required this.original,
    required this.initialDate,
    required this.birthDate,
    required this.occupiedDates,
  });

  @override
  State<_PcEditor> createState() => _PcEditorState();
}

class _PcEditorState extends State<_PcEditor> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _notes = TextEditingController();
  final TextEditingController _doctorNotes = TextEditingController();
  late DateTime _date;
  DateTime? _consultationDate;
  late String _cycle;
  late String _assessment;
  late Map<String, int> _symptomLevels;
  int? _discomfort;

  @override
  void initState() {
    super.initState();
    final old = widget.original;
    _date = _pcDay(old?.date ?? widget.initialDate);
    _cycle = old?.cyclePattern ?? _cycleChoices.first;
    _assessment = old?.assessment ?? _assessmentChoices.first;
    _symptomLevels = Map<String, int>.from(old?.symptoms ?? {});
    _discomfort = old?.discomfort;
    _consultationDate = old?.consultationDate;
    _notes.text = old?.personalNotes ?? '';
    _doctorNotes.text = old?.doctorNotes ?? '';
  }

  @override
  void dispose() {
    _notes.dispose();
    _doctorNotes.dispose();
    super.dispose();
  }

  DateTime get _firstDate {
    final today = _pcDay(DateTime.now());
    final fallback = DateTime(today.year - 20, today.month, today.day);
    final birth = widget.birthDate;
    if (birth == null) return fallback;
    final dob = _pcDay(birth);
    return dob.isAfter(fallback) ? dob : fallback;
  }

  Future<void> _chooseDate({bool consultation = false}) async {
    final now = _pcDay(DateTime.now());
    final first = _firstDate;
    if (first.isAfter(now)) return;
    final current = consultation ? (_consultationDate ?? _date) : _date;
    final safe = current.isBefore(first)
        ? first
        : current.isAfter(now) ? now : current;
    final selected = await showDatePicker(
      context: context,
      initialDate: safe,
      firstDate: first,
      lastDate: now,
      helpText: consultation ? 'CLINICIAN VISIT DATE' : 'OBSERVATION DATE',
    );
    if (selected == null || !mounted) return;
    final date = _pcDay(selected);
    if (!consultation && widget.occupiedDates.contains(date)) {
      _message('An observation already exists for this date. Edit that entry.');
      return;
    }
    setState(() {
      if (consultation) {
        _consultationDate = date;
      } else {
        _date = date;
      }
    });
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _save() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final today = _pcDay(DateTime.now());
    if (_date.isAfter(today) || _date.isBefore(_firstDate)) {
      _message('Observation date must be between date of birth and today.');
      return;
    }
    if (widget.occupiedDates.contains(_date)) {
      _message('An entry already exists on this date.');
      return;
    }
    if (_consultationDate != null && _consultationDate!.isAfter(today)) {
      _message('A past consultation cannot have a future date.');
      return;
    }
    final hasContent = _cycle != _cycleChoices.first ||
        _symptomLevels.isNotEmpty ||
        _discomfort != null ||
        _assessment != _assessmentChoices.first ||
        _notes.text.trim().isNotEmpty ||
        _doctorNotes.text.trim().isNotEmpty;
    if (!hasContent) {
      _message('Enter at least one observation or note.');
      return;
    }
    Navigator.of(context).pop(_PcEntry(
      id: widget.original?.id ??
          '${DateTime.now().microsecondsSinceEpoch}-${_pcApiDate(_date)}',
      date: _date,
      cyclePattern: _cycle,
      symptoms: Map<String, int>.from(_symptomLevels),
      discomfort: _discomfort,
      assessment: _assessment,
      consultationDate: _assessment == _assessmentChoices.first
          ? null : _consultationDate,
      doctorNotes: _assessment == _assessmentChoices.first
          ? '' : _doctorNotes.text.trim(),
      personalNotes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight:
        MediaQuery.sizeOf(context).height * 0.94),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 690),
              child: Form(key: _form, child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  const SizedBox(height: 12),
                  _info('Preview only — not saved to FamilyCare+ backend.'),
                  const SizedBox(height: 16),
                  _sectionTitle('Observation date'),
                  const SizedBox(height: 7),
                  OutlinedButton.icon(
                    onPressed: _chooseDate,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_pcDateText(_date)),
                  ),
                  const SizedBox(height: 18),
                  _sectionTitle('Period pattern (your observation)'),
                  const SizedBox(height: 7),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_cycle),
                    initialValue: _cycle,
                    decoration: _inputDecoration('Choose a pattern'),
                    isExpanded: true,
                    items: _cycleChoices.map((value) =>
                        DropdownMenuItem(value: value, child: Text(value,
                            overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _cycle = value);
                    },
                  ),
                  const SizedBox(height: 17),
                  _sectionTitle('Symptoms noticed'),
                  const SizedBox(height: 5),
                  const Text('Select a symptom, then Mild / Moderate / Severe. '
                      'These are self-reported observations, not diagnoses.',
                      style: TextStyle(fontSize: 11, color: _PcColor.muted)),
                  const SizedBox(height: 10),
                  for (final symptom in _pcSymptoms) ...[
                    _symptomTile(symptom),
                    const SizedBox(height: 7),
                  ],
                  const SizedBox(height: 10),
                  _sectionTitle('Pelvic discomfort (optional)'),
                  const SizedBox(height: 7),
                  Row(children: [
                    Expanded(child: Text(_discomfort == null
                        ? 'Not recorded' : 'Self-rated: $_discomfort / 10',
                        style: const TextStyle(fontSize: 12,
                            color: _PcColor.text))),
                    if (_discomfort != null)
                      TextButton(onPressed: () => setState(() => _discomfort = null),
                          child: const Text('Clear')),
                  ]),
                  Slider(
                    value: (_discomfort ?? 0).toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: _discomfort?.toString() ?? '0',
                    activeColor: _PcColor.rose,
                    onChanged: (value) => setState(() => _discomfort = value.round()),
                  ),
                  const SizedBox(height: 17),
                  _sectionTitle('Clinician discussion (optional)'),
                  const SizedBox(height: 6),
                  const Text('Only choose a diagnosis option if a qualified '
                      'clinician actually told you. This is your own record '
                      'of that discussion, not verification by the app.',
                      style: TextStyle(fontSize: 11, color: _PcColor.muted,
                          height: 1.45)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    key: ValueKey(_assessment),
                    initialValue: _assessment,
                    isExpanded: true,
                    decoration: _inputDecoration('Clinician assessment status'),
                    items: _assessmentChoices.map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(value, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() {
                        _assessment = value;
                        if (value == _assessmentChoices.first) {
                          _consultationDate = null;
                          _doctorNotes.clear();
                        }
                      });
                    },
                  ),
                  if (_assessment != _assessmentChoices.first) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _chooseDate(consultation: true),
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text(_consultationDate == null
                          ? 'Add consultation date (optional)'
                          : _pcDateText(_consultationDate!)),
                    ),
                    if (_consultationDate != null)
                      TextButton(onPressed: () => setState(
                              () => _consultationDate = null),
                          child: const Text('Remove consultation date')),
                    const SizedBox(height: 9),
                    TextFormField(
                      controller: _doctorNotes,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 1200,
                      decoration: _inputDecoration('What your clinician said'),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _sectionTitle('Personal notes'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _notes,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 1800,
                    decoration: _inputDecoration('Anything else to remember?'),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton.icon(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                          backgroundColor: _PcColor.rose,
                          foregroundColor: Colors.white),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Save preview'),
                    )),
                  ]),
                ],
              )),
            )),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(children: [
      const Icon(Icons.edit_calendar_rounded, color: _PcColor.rose, size: 29),
      const SizedBox(width: 10),
      Expanded(child: Text(widget.original == null
          ? 'Add PCOS observation' : 'Edit observation',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
              color: _PcColor.navy))),
      IconButton(
        tooltip: 'Close',
        onPressed: () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded),
      ),
    ]);
  }

  Widget _info(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _PcColor.amberLight,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded, size: 18, color: _PcColor.amber),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(
            fontSize: 11, color: _PcColor.text))),
      ]),
    );
  }

  Widget _sectionTitle(String value) => Text(value,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
          color: _PcColor.navy));

  InputDecoration _inputDecoration(String label) => InputDecoration(
    labelText: label,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
  );

  Widget _symptomTile(_PcSymptom symptom) {
    final level = _symptomLevels[symptom.code];
    return Container(
      decoration: BoxDecoration(
        color: level == null ? _PcColor.bg : _PcColor.roseLight,
        border: Border.all(color: _PcColor.border),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() {
            if (level == null) {
              _symptomLevels[symptom.code] = 1;
            } else {
              _symptomLevels.remove(symptom.code);
            }
          }),
          child: Row(children: [
            Icon(symptom.icon, color: _PcColor.rose, size: 20),
            const SizedBox(width: 9),
            Expanded(child: Text(symptom.title, style: const TextStyle(
              fontWeight: FontWeight.w700, color: _PcColor.text, fontSize: 12,
            ))),
            Checkbox(
              value: level != null,
              activeColor: _PcColor.rose,
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  _symptomLevels[symptom.code] = 1;
                } else {
                  _symptomLevels.remove(symptom.code);
                }
              }),
            ),
          ]),
        ),
        if (level != null) ...[
          const SizedBox(height: 5),
          Wrap(spacing: 8, children: [
            for (final value in [1, 2, 3])
              ChoiceChip(
                label: Text(_pcSeverityName(value),
                    style: const TextStyle(fontSize: 11)),
                selected: level == value,
                selectedColor: _PcColor.roseLight,
                onSelected: (_) => setState(() =>
                _symptomLevels[symptom.code] = value),
              ),
          ]),
        ],
      ]),
    );
  }
}
