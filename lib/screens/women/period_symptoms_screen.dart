import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

// =====================================================================
// FAMILYCARE+ | WOMEN'S HEALTH | PERIOD PAIN & PMS / DAILY SYMPTOMS
// =====================================================================
// Existing Backend v5 endpoint used:
//   GET /api/v1/patients/profiles/{profileId}
//     -> verifies the selected profile is a Women's Health profile.
//
// IMPORTANT: Backend v5 does NOT have period-symptoms CRUD endpoints.
// Entries below are SESSION-ONLY, held in Dart memory for the current
// app process; NO database, disk, analytics or HTTP write is performed.
// They disappear when the app is restarted. Explicit UI warnings tell
// users that "Save preview" is not a permanent save.
//
// The screen is a self-reporting diary, NOT a diagnosis, treatment
// recommendation, fertility predictor or clinical emergency detector.
// No third-party calendar/chart package is required.
// =====================================================================

class PeriodSymptomsScreen extends StatefulWidget {
  final String profileId;
  final String profileName;
  final String apiBaseUrl;

  const PeriodSymptomsScreen({
    super.key,
    required this.profileId,
    this.profileName = 'Women Profile',
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
  });

  @override
  State<PeriodSymptomsScreen> createState() =>
      _PeriodSymptomsScreenState();
}

class _PSColor {
  static const background = Color(0xFFF7F8FC);
  static const navy = Color(0xFF183C60);
  static const text = Color(0xFF2B4960);
  static const muted = Color(0xFF6B7D90);
  static const rose = Color(0xFFB95879);
  static const roseLight = Color(0xFFFFEDF3);
  static const purple = Color(0xFF8668B9);
  static const teal = Color(0xFF237F82);
  static const tealLight = Color(0xFFE7F5F3);
  static const blue = Color(0xFF3275D9);
  static const blueLight = Color(0xFFEAF2FF);
  static const red = Color(0xFFB94D58);
  static const amber = Color(0xFF9D681D);
  static const amberLight = Color(0xFFFFF4DF);
  static const border = Color(0xFFE2E9F2);
  static const white = Colors.white;
}

DateTime _psDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _psIso(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';

const _psMonthNames = <String>[
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _psReadable(DateTime value) {
  final name = _psMonthNames[value.month - 1].substring(0, 3);
  return '${value.day} $name ${value.year}';
}

bool _psSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _PSSymptom {
  final String id;
  final String label;
  final IconData icon;

  const _PSSymptom(this.id, this.label, this.icon);
}

const _psSymptoms = <_PSSymptom>[
  _PSSymptom('cramps', 'Cramps', Icons.waves_outlined),
  _PSSymptom('bloating', 'Bloating', Icons.bubble_chart_outlined),
  _PSSymptom('back_pain', 'Back pain', Icons.accessibility_new_outlined),
  _PSSymptom('headache', 'Headache', Icons.psychology_outlined),
  _PSSymptom('breast_tenderness', 'Breast tenderness', Icons.favorite_border),
  _PSSymptom('fatigue', 'Fatigue', Icons.bedtime_outlined),
  _PSSymptom('nausea', 'Nausea', Icons.sick_outlined),
  _PSSymptom('acne', 'Acne', Icons.face_outlined),
  _PSSymptom('cravings', 'Food cravings', Icons.restaurant_outlined),
  _PSSymptom('digestive', 'Digestive changes', Icons.spa_outlined),
  _PSSymptom('sleep', 'Sleep difficulty', Icons.nights_stay_outlined),
  _PSSymptom('irritability', 'Irritability', Icons.mood_bad_outlined),
  _PSSymptom('anxiety', 'Anxiety', Icons.sentiment_dissatisfied_outlined),
  _PSSymptom('low_mood', 'Low mood', Icons.cloud_outlined),
  _PSSymptom('dizziness', 'Dizziness', Icons.air_outlined),
];

String _psSymptomLabel(String id) {
  for (final item in _psSymptoms) {
    if (item.id == id) return item.label;
  }
  return id;
}

String _psSeverityName(int value) {
  switch (value) {
    case 1:
      return 'Mild';
    case 2:
      return 'Moderate';
    case 3:
      return 'Severe';
    default:
      return 'Not set';
  }
}

class _PSRecord {
  final String id;
  final DateTime date;
  final String phase;
  final int? painScore;
  final String flow;
  final String mood;
  final String energy;
  final Map<String, int> symptomLevels;
  final String notes;
  final String reliefNotes;

  const _PSRecord({
    required this.id,
    required this.date,
    required this.phase,
    required this.painScore,
    required this.flow,
    required this.mood,
    required this.energy,
    required this.symptomLevels,
    required this.notes,
    required this.reliefNotes,
  });

  bool get hasHighPain => painScore != null && painScore! >= 7;
  bool get hasHeavyFlow => flow == 'Heavy';
  bool get isPms => phase == 'Before period (PMS)';
}

// Scoped by profile. Memory only; no persistence across app restarts.
class _PSSessionDrafts {
  static final Map<String, List<_PSRecord>> _byProfile = {};

  static List<_PSRecord> get(String profileId) =>
      List<_PSRecord>.from(_byProfile[profileId] ?? const <_PSRecord>[]);

  static void put(String profileId, List<_PSRecord> records) {
    _byProfile[profileId] = List<_PSRecord>.from(records);
  }

  static void clear(String profileId) => _byProfile.remove(profileId);
}

class _PeriodSymptomsScreenState extends State<PeriodSymptomsScreen> {
  final http.Client _client = http.Client();
  final TextEditingController _search = TextEditingController();

  List<_PSRecord> _records = [];
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = _psDate(DateTime.now());
  DateTime? _profileDob;
  String? _verifiedName;
  String? _profileError;
  bool _verifying = true;
  String _historyFilter = 'all';
  int _requestVersion = 0;

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

  String get _displayName =>
      _verifiedName?.isNotEmpty == true ? _verifiedName! : widget.profileName;

  bool get _canEdit => !_verifying && _profileError == null;

  @override
  void initState() {
    super.initState();
    _records = _PSSessionDrafts.get(widget.profileId);
    _search.addListener(_refreshSearch);
    _verifyProfile();
  }

  @override
  void didUpdateWidget(covariant PeriodSymptomsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _requestVersion++;
      _records = _PSSessionDrafts.get(widget.profileId);
      _profileDob = null;
      _verifiedName = null;
      _profileError = null;
      _month = DateTime(DateTime.now().year, DateTime.now().month);
      _selectedDate = _psDate(DateTime.now());
      _historyFilter = 'all';
      _search.clear();
      _verifyProfile();
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    _search.removeListener(_refreshSearch);
    _search.dispose();
    _client.close();
    super.dispose();
  }

  void _refreshSearch() {
    if (mounted) setState(() {});
  }

  Future<void> _verifyProfile() async {
    final version = ++_requestVersion;
    final id = widget.profileId.trim();
    if (mounted) {
      setState(() {
        _verifying = true;
        _profileError = null;
      });
    }
    try {
      if (id.isEmpty) {
        throw const FormatException('Women profile ID is missing.');
      }
      final token = await FamilyCareSession.accessToken();
      if (token == null || token.trim().isEmpty) {
        throw const FormatException('Login session missing. Please sign in.');
      }
      final response = await _client.get(
        Uri.parse('$_baseUrl/api/v1/patients/profiles/'
            '${Uri.encodeComponent(id)}'),
        headers: {
          'Authorization': 'Bearer $token',
          'X-Auth-Transport': 'bearer',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401) {
          throw const FormatException('Session expired. Sign in again.');
        }
        if (response.statusCode == 403) {
          throw const FormatException('Access to this Women profile denied.');
        }
        throw FormatException('Cannot access this Women profile '
            '(HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['profile'] is! Map) {
        throw const FormatException('Invalid profile response from server.');
      }
      final data = Map<String, dynamic>.from(decoded['profile'] as Map);
      if (data['id']?.toString() != id || data['module'] != 'women') {
        throw const FormatException('Please select a Women profile.');
      }
      if (!mounted || _requestVersion != version ||
          widget.profileId.trim() != id) return;
      setState(() {
        _profileDob = DateTime.tryParse(
            (data['date_of_birth'] ?? '').toString());
        _verifiedName = (data['full_name'] ?? '').toString().trim();
        _verifying = false;
        _profileError = null;
      });
    } on TimeoutException {
      _setProfileError(version, id, 'Profile request timed out. Retry.');
    } on http.ClientException {
      _setProfileError(version, id, 'Cannot connect to FamilyCare+ backend.');
    } on FormatException catch (error) {
      _setProfileError(version, id, error.message);
    } catch (_) {
      _setProfileError(version, id,
          'Unable to verify the selected Women profile.');
    }
  }

  void _setProfileError(int version, String id, String message) {
    if (!mounted || version != _requestVersion ||
        widget.profileId.trim() != id) return;
    setState(() {
      _profileError = message;
      _verifying = false;
    });
  }

  void _snack(String message, {bool danger = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: danger ? _PSColor.red : _PSColor.navy,
        content: Text(message),
      ));
  }

  _PSRecord? _recordAt(DateTime day) {
    for (final entry in _records) {
      if (_psSameDay(entry.date, day)) return entry;
    }
    return null;
  }

  void _savePreview(_PSRecord record) {
    final updated = List<_PSRecord>.from(_records);
    final index = updated.indexWhere((value) => value.id == record.id);
    if (index >= 0) {
      updated[index] = record;
    } else {
      updated.add(record);
    }
    updated.sort((a, b) => b.date.compareTo(a.date));
    _PSSessionDrafts.put(widget.profileId, updated);
    setState(() {
      _records = updated;
      _selectedDate = _psDate(record.date);
      _month = DateTime(record.date.year, record.date.month);
    });
    _snack('Preview updated for this session only. Not saved to backend.');
  }

  Future<void> _openEditor({_PSRecord? existing, DateTime? forDate}) async {
    if (!_canEdit) {
      _snack('Verify the Women profile before adding symptoms.', danger: true);
      return;
    }
    final profileId = widget.profileId;
    final day = _psDate(forDate ?? _selectedDate);
    final current = existing ?? _recordAt(day);
    final result = await showModalBottomSheet<_PSRecord>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PSEditor(
        original: current,
        requestedDate: day,
        birthDate: _profileDob,
        usedDates: _records
            .where((e) => e.id != current?.id)
            .map((e) => _psDate(e.date))
            .toList(),
      ),
    );
    if (!mounted || result == null || profileId != widget.profileId) return;
    _savePreview(result);
  }

  Future<void> _deleteRecord(_PSRecord record) async {
    if (!_canEdit) return;
    final profileId = widget.profileId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete symptom entry?'),
        content: Text('Remove your session preview for '
            '${_psReadable(record.date)}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: _PSColor.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || profileId != widget.profileId) {
      return;
    }
    final updated = List<_PSRecord>.from(_records)
      ..removeWhere((e) => e.id == record.id);
    _PSSessionDrafts.put(profileId, updated);
    setState(() => _records = updated);
    _snack('Session preview removed.');
  }

  Future<void> _clearDrafts() async {
    if (!_canEdit || _records.isEmpty) return;
    final profileId = widget.profileId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear all preview entries?'),
        content: const Text(
          'This clears the symptom diary only for the selected Women '
              'profile in this app session. No backend records are changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: _PSColor.red),
            child: const Text('Clear preview'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || profileId != widget.profileId) return;
    _PSSessionDrafts.clear(profileId);
    setState(() => _records = []);
    _snack('All session preview entries cleared.');
  }

  List<_PSRecord> get _filteredRecords {
    final query = _search.text.trim().toLowerCase();
    final entries = _records.where((entry) {
      if (_historyFilter == 'pms' && !entry.isPms) return false;
      if (_historyFilter == 'high_pain' && !entry.hasHighPain) return false;
      if (_historyFilter == 'heavy_flow' && !entry.hasHeavyFlow) return false;
      if (query.isEmpty) return true;
      final text = [
        _psReadable(entry.date),
        entry.phase,
        entry.flow,
        entry.mood,
        entry.energy,
        entry.notes,
        entry.reliefNotes,
        for (final id in entry.symptomLevels.keys) _psSymptomLabel(id),
      ].join(' ').toLowerCase();
      return text.contains(query);
    }).toList();
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  double? get _averagePain {
    final pains = _records.map((e) => e.painScore).whereType<int>().toList();
    if (pains.isEmpty) return null;
    return pains.reduce((a, b) => a + b) / pains.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _PSColor.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _PSColor.navy,
        title: const Text('Period Pain & PMS',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            tooltip: 'Verify / refresh Women profile',
            onPressed: _verifying ? null : _verifyProfile,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
        heroTag: 'ps-create-${widget.profileId}',
        onPressed: () => _openEditor(forDate: _selectedDate),
        foregroundColor: Colors.white,
        backgroundColor: _PSColor.rose,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log Symptoms'),
      )
          : null,
      body: SafeArea(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 112),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hero(),
                    const SizedBox(height: 15),
                    _sessionNotice(),
                    const SizedBox(height: 15),
                    if (_verifying) ...[
                      const LinearProgressIndicator(color: _PSColor.rose),
                      const SizedBox(height: 12),
                    ],
                    if (_profileError != null) ...[
                      _profileErrorCard(),
                      const SizedBox(height: 15),
                    ],
                    if (_canEdit) ...[
                      _summary(),
                      const SizedBox(height: 17),
                      _calendar(),
                      const SizedBox(height: 17),
                      _selectedDaySection(),
                      const SizedBox(height: 17),
                      _history(),
                      const SizedBox(height: 17),
                      _safetyNotice(),
                    ] else if (!_verifying) ...[
                      const Text('Diary access is unavailable until the '
                          'selected Women profile is verified.'),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero() => Container(
    padding: const EdgeInsets.all(19),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [
        Color(0xFFFFEAF1), Color(0xFFF1EEFF), Color(0xFFEFF8F7),
      ]),
      borderRadius: BorderRadius.circular(19),
    ),
    child: Row(children: [
      const CircleAvatar(
        radius: 30,
        backgroundColor: Colors.white,
        child: Icon(Icons.favorite_border_rounded,
            size: 31, color: _PSColor.rose),
      ),
      const SizedBox(width: 13),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('YOUR DAILY WELLNESS DIARY',
              style: TextStyle(color: _PSColor.rose, fontSize: 10,
                  fontWeight: FontWeight.w800, letterSpacing: 1.1)),
          const SizedBox(height: 6),
          const Text('Track how you feel', style: TextStyle(
              color: _PSColor.navy, fontWeight: FontWeight.w800,
              fontSize: 22)),
          const SizedBox(height: 7),
          Text('Symptom diary for $_displayName', style: const TextStyle(
              color: _PSColor.text, fontSize: 12)),
        ],
      )),
    ]),
  );

  Widget _sessionNotice() => _notice(
    'SESSION PREVIEW ONLY: symptom entries are held in memory and '
        'are not saved to your account or any database. They disappear '
        'after restarting the app. Do not rely on this as your sole record.',
    _PSColor.blueLight,
    _PSColor.blue,
    Icons.info_outline_rounded,
  );

  Widget _profileErrorCard() => _surface(
    child: Column(children: [
      const Icon(Icons.cloud_off_outlined, color: _PSColor.red, size: 34),
      const SizedBox(height: 8),
      Text(_profileError ?? 'Unable to verify profile',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _PSColor.red)),
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _verifyProfile,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    ]),
  );

  Widget _summary() {
    final avg = _averagePain;
    final cards = <_PSStat>[
      _PSStat('Logged Days', '${_records.length}',
          Icons.event_note_outlined, _PSColor.teal),
      _PSStat('Avg. Pain', avg == null ? '—' : '${avg.toStringAsFixed(1)}/10',
          Icons.monitor_heart_outlined, _PSColor.rose),
      _PSStat('PMS Logs', '${_records.where((e) => e.isPms).length}',
          Icons.spa_outlined, _PSColor.purple),
      _PSStat('High Pain (7+)',
          '${_records.where((e) => e.hasHighPain).length}',
          Icons.warning_amber_outlined, _PSColor.amber),
    ];
    return LayoutBuilder(builder: (context, bounds) {
      final columns = bounds.maxWidth >= 740 ? 4 : 2;
      const gap = 10.0;
      final width = (bounds.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final card in cards)
            SizedBox(width: width, child: Container(
              padding: const EdgeInsets.all(14),
              constraints: const BoxConstraints(minHeight: 116),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: _PSColor.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(card.icon, color: card.color, size: 23),
                  const SizedBox(height: 10),
                  Text(card.value, style: const TextStyle(
                      color: _PSColor.navy, fontSize: 22,
                      fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text(card.title, maxLines: 2,
                      style: const TextStyle(
                          color: _PSColor.muted, fontSize: 11)),
                ],
              ),
            )),
        ],
      );
    });
  }

  void _changeMonth(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
    });
  }

  Widget _calendar() {
    final first = DateTime(_month.year, _month.month, 1);
    final before = first.weekday - 1;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = ((before + days + 6) ~/ 7) * 7;
    final today = _psDate(DateTime.now());
    return _section(
      title: 'Daily Symptom Calendar',
      subtitle: 'Tap a date to view or log how you felt',
      icon: Icons.calendar_month_outlined,
      child: Column(children: [
        Row(children: [
          IconButton(
            tooltip: 'Previous month',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _changeMonth(-1),
          ),
          Expanded(child: Text(
            '${_psMonthNames[_month.month - 1]} ${_month.year}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _PSColor.navy,
                fontWeight: FontWeight.w800, fontSize: 15),
          )),
          IconButton(
            tooltip: 'Next month',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: DateTime(_month.year, _month.month + 1)
                .isAfter(DateTime(today.year, today.month))
                ? null
                : () => _changeMonth(1),
          ),
        ]),
        const SizedBox(height: 9),
        Row(children: [
          for (final name in const ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'])
            Expanded(child: Text(name, textAlign: TextAlign.center,
                style: const TextStyle(color: _PSColor.muted,
                    fontSize: 10, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
            childAspectRatio: 1.02,
          ),
          itemCount: cells,
          itemBuilder: (context, index) {
            final number = index - before + 1;
            if (number < 1 || number > days) return const SizedBox.shrink();
            final date = DateTime(_month.year, _month.month, number);
            final selected = _psSameDay(date, _selectedDate);
            final isToday = _psSameDay(date, today);
            final disabled = date.isAfter(today) ||
                (_profileDob != null &&
                    date.isBefore(_psDate(_profileDob!)));
            final record = _recordAt(date);
            final marked = record != null;
            return Semantics(
              label: '${_psReadable(date)}; '
                  '${marked ? 'symptoms recorded' : 'no entry'}',
              button: !disabled,
              child: InkWell(
                onTap: disabled ? null : () => setState(() => _selectedDate = date),
                borderRadius: BorderRadius.circular(11),
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? _PSColor.roseLight :
                    marked ? _PSColor.tealLight : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? _PSColor.rose :
                      isToday ? _PSColor.blue : _PSColor.border,
                      width: selected ? 1.6 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$number', style: TextStyle(
                        color: disabled ? _PSColor.border : _PSColor.navy,
                        fontWeight: marked || selected ?
                        FontWeight.w800 : FontWeight.w500,
                        fontSize: 12,
                      )),
                      const SizedBox(height: 2),
                      if (marked) Container(
                        width: 5, height: 5,
                        decoration: BoxDecoration(
                          color: record.hasHighPain ? _PSColor.rose :
                          _PSColor.teal,
                          shape: BoxShape.circle,
                        ),
                      ) else const SizedBox(height: 5),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        const Row(children: [
          Icon(Icons.circle, size: 9, color: _PSColor.teal),
          SizedBox(width: 5),
          Text('Logged', style: TextStyle(fontSize: 10, color: _PSColor.muted)),
          SizedBox(width: 13),
          Icon(Icons.circle, size: 9, color: _PSColor.rose),
          SizedBox(width: 5),
          Text('High pain', style: TextStyle(fontSize: 10, color: _PSColor.muted)),
        ]),
      ]),
    );
  }

  Widget _selectedDaySection() {
    final entry = _recordAt(_selectedDate);
    return _section(
      title: _psReadable(_selectedDate),
      subtitle: entry == null ? 'No entry for this day' :
      'One daily log • session preview',
      icon: Icons.today_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (entry == null) ...[
            const Text('Record daily pain, PMS symptoms and other '
                'observations for this date.',
                style: TextStyle(fontSize: 12, color: _PSColor.muted)),
            const SizedBox(height: 12),
          ] else ...[
            _entryDetails(entry),
            const SizedBox(height: 12),
          ],
          Wrap(spacing: 9, runSpacing: 9, children: [
            FilledButton.icon(
              onPressed: () => _openEditor(
                  existing: entry, forDate: _selectedDate),
              icon: Icon(entry == null ? Icons.add_rounded : Icons.edit_outlined,
                  size: 18),
              label: Text(entry == null ? 'Log this day' : 'Edit this day'),
              style: FilledButton.styleFrom(
                  backgroundColor: _PSColor.rose,
                  foregroundColor: Colors.white),
            ),
            if (entry != null)
              OutlinedButton.icon(
                onPressed: () => _deleteRecord(entry),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: _PSColor.red),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _history() {
    final records = _filteredRecords;
    return _section(
      title: 'Symptom History',
      subtitle: 'Daily observations; newest first',
      icon: Icons.history_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'Search dates, symptoms or notes',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _search.text.isEmpty ? null : IconButton(
                onPressed: _search.clear,
                icon: const Icon(Icons.close_rounded)),
            filled: true,
            fillColor: _PSColor.background,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            _filterChip('All logs', 'all'),
            _filterChip('PMS', 'pms'),
            _filterChip('High pain (7+)', 'high_pain'),
            _filterChip('Heavy flow', 'heavy_flow'),
          ]),
        ),
        const SizedBox(height: 12),
        Text('${records.length} matching entries', style: const TextStyle(
            color: _PSColor.muted, fontSize: 11)),
        const SizedBox(height: 12),
        if (records.isEmpty)
          _notice(
            _records.isEmpty ? 'No symptom entries yet. Select a date '
                'on the calendar to start your private session preview.' :
            'No records match your search or filters.',
            _PSColor.blueLight, _PSColor.blue, Icons.menu_book_outlined,
          )
        else
          for (final entry in records) ...[
            _historyCard(entry),
            const SizedBox(height: 9),
          ],
        if (_records.isNotEmpty) ...[
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _clearDrafts,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Clear all session previews'),
              style: TextButton.styleFrom(foregroundColor: _PSColor.red),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _filterChip(String name, String id) => Padding(
    padding: const EdgeInsets.only(right: 7),
    child: ChoiceChip(
      label: Text(name),
      selected: _historyFilter == id,
      showCheckmark: false,
      selectedColor: _PSColor.roseLight,
      side: BorderSide(
          color: _historyFilter == id ? _PSColor.rose : _PSColor.border),
      onSelected: (_) => setState(() => _historyFilter = id),
    ),
  );

  Widget _historyCard(_PSRecord record) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _PSColor.background,
        border: Border.all(color: _PSColor.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_psReadable(record.date), style: const TextStyle(
                  color: _PSColor.navy, fontSize: 14,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(record.phase, style: const TextStyle(
                  color: _PSColor.muted, fontSize: 11)),
            ],
          )),
          if (record.painScore != null)
            _tag('Pain ${record.painScore}/10',
                record.hasHighPain ? _PSColor.red : _PSColor.rose),
        ]),
        const SizedBox(height: 11),
        _entryDetails(record),
        const Divider(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton.icon(
            onPressed: () => _openEditor(existing: record),
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: const Text('Edit'),
          ),
          TextButton.icon(
            onPressed: () => _deleteRecord(record),
            icon: const Icon(Icons.delete_outline, size: 17),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: _PSColor.red),
          ),
        ]),
      ]),
    );
  }

  Widget _entryDetails(_PSRecord entry) {
    final fields = <String>[
      if (entry.painScore != null) 'Pain ${entry.painScore}/10',
      if (entry.flow != 'Not recorded') 'Flow: ${entry.flow}',
      if (entry.mood != 'Not recorded') 'Mood: ${entry.mood}',
      if (entry.energy != 'Not recorded') 'Energy: ${entry.energy}',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (fields.isNotEmpty)
        Wrap(spacing: 7, runSpacing: 7,
            children: [for (final value in fields) _tag(value, _PSColor.teal)]),
      if (entry.symptomLevels.isNotEmpty) ...[
        const SizedBox(height: 9),
        Wrap(spacing: 7, runSpacing: 7, children: [
          for (final symptom in _psSymptoms)
            if (entry.symptomLevels.containsKey(symptom.id))
              _tag('${symptom.label} • '
                  '${_psSeverityName(entry.symptomLevels[symptom.id]!)}',
                  _PSColor.purple),
        ]),
      ],
      if (entry.notes.isNotEmpty) ...[
        const SizedBox(height: 9),
        Text(entry.notes, style: const TextStyle(
            fontSize: 12, color: _PSColor.text, height: 1.5)),
      ],
      if (entry.reliefNotes.isNotEmpty) ...[
        const SizedBox(height: 7),
        Text('What helped/tried: ${entry.reliefNotes}',
            style: const TextStyle(fontSize: 11, color: _PSColor.muted,
                height: 1.5)),
      ],
    ]);
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(label, style: TextStyle(
        color: color, fontSize: 11, fontWeight: FontWeight.w600)),
  );

  Widget _safetyNotice() => _notice(
    'These are self-reported observations, not a diagnosis or '
        'medical assessment. Severe or worsening pain, fainting, '
        'or unusually heavy bleeding deserves prompt medical advice. '
        'Do not use symptom logs alone to make treatment decisions.',
    _PSColor.amberLight,
    _PSColor.amber,
    Icons.health_and_safety_outlined,
  );

  Widget _surface({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: _PSColor.border),
    ),
    child: child,
  );

  Widget _section({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return _surface(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: _PSColor.roseLight,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: _PSColor.rose, size: 23),
          ),
          const SizedBox(width: 11),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                  color: _PSColor.navy, fontWeight: FontWeight.w800,
                  fontSize: 17)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(
                  color: _PSColor.muted, fontSize: 11)),
            ],
          )),
        ]),
        const SizedBox(height: 16),
        child,
      ],
    ));
  }

  Widget _notice(String message, Color background,
      Color iconColor, IconData icon) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(color: background,
        borderRadius: BorderRadius.circular(12)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 20, color: iconColor),
      const SizedBox(width: 10),
      Expanded(child: Text(message, style: const TextStyle(
          fontSize: 11, height: 1.5, color: _PSColor.text))),
    ]),
  );
}

class _PSStat {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _PSStat(this.title, this.value, this.icon, this.color);
}

// =====================================================================
// DAILY LOG EDITOR — EXPANDS FROM THE SYMPTOM SCREEN (NO NEW ROUTE)
// =====================================================================
class _PSEditor extends StatefulWidget {
  final _PSRecord? original;
  final DateTime requestedDate;
  final DateTime? birthDate;
  final List<DateTime> usedDates;

  const _PSEditor({
    required this.original,
    required this.requestedDate,
    required this.birthDate,
    required this.usedDates,
  });

  @override
  State<_PSEditor> createState() => _PSEditorState();
}

class _PSEditorState extends State<_PSEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _notes;
  late final TextEditingController _reliefNotes;

  late DateTime _date;
  late String _phase;
  late String _flow;
  late String _mood;
  late String _energy;
  late bool _painRecorded;
  late int _painScore;
  late Map<String, int> _levels;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final old = widget.original;
    _date = _psDate(old?.date ?? widget.requestedDate);
    _phase = old?.phase ?? 'Not sure';
    _flow = old?.flow ?? 'Not recorded';
    _mood = old?.mood ?? 'Not recorded';
    _energy = old?.energy ?? 'Not recorded';
    _painRecorded = old?.painScore != null;
    _painScore = old?.painScore ?? 0;
    _levels = Map<String, int>.from(old?.symptomLevels ?? const {});
    _notes = TextEditingController(text: old?.notes ?? '');
    _reliefNotes = TextEditingController(text: old?.reliefNotes ?? '');
  }

  @override
  void dispose() {
    _notes.dispose();
    _reliefNotes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = _psDate(DateTime.now());
    var first = widget.birthDate == null ? DateTime(1900) :
    _psDate(widget.birthDate!);
    if (first.isAfter(today)) first = today;
    var initial = _date;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(today)) initial = today;
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: today,
      helpText: 'SYMPTOM OBSERVATION DATE',
    );
    if (selected == null || !mounted) return;
    setState(() => _date = _psDate(selected));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: _PSColor.red,
      ));
  }

  void _submit() {
    setState(() => _submitted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final today = _psDate(DateTime.now());
    if (_date.isAfter(today) ||
        (widget.birthDate != null &&
            _date.isBefore(_psDate(widget.birthDate!)))) {
      _showError('Choose a date between birth and today.');
      return;
    }
    if (widget.usedDates.any((day) => _psSameDay(day, _date))) {
      _showError('A log already exists for this date. Edit that entry instead.');
      return;
    }
    if (!_painRecorded && _levels.isEmpty &&
        _flow == 'Not recorded' &&
        _mood == 'Not recorded' &&
        _energy == 'Not recorded' &&
        _notes.text.trim().isEmpty &&
        _reliefNotes.text.trim().isEmpty &&
        _phase == 'Not sure') {
      _showError('Record at least one symptom, pain score or observation.');
      return;
    }
    FocusScope.of(context).unfocus();
    Navigator.pop(context, _PSRecord(
      id: widget.original?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      date: _date,
      phase: _phase,
      painScore: _painRecorded ? _painScore : null,
      flow: _flow,
      mood: _mood,
      energy: _energy,
      symptomLevels: Map<String, int>.from(_levels),
      notes: _notes.text.trim(),
      reliefNotes: _reliefNotes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .93,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(23)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(19, 21, 19, 30),
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Form(
                key: _formKey,
                autovalidateMode: _submitted ?
                AutovalidateMode.onUserInteraction :
                AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text(widget.original == null
                          ? 'Log Daily Symptoms' : 'Edit Daily Symptoms',
                        style: const TextStyle(color: _PSColor.navy,
                            fontWeight: FontWeight.w800, fontSize: 21),
                      )),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    const Text('Personal observations only • not a medical diagnosis',
                        style: TextStyle(fontSize: 11, color: _PSColor.muted)),
                    const SizedBox(height: 18),
                    _label('Observation Date'),
                    const SizedBox(height: 7),
                    OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: Text(_psReadable(_date)),
                    ),
                    const SizedBox(height: 18),
                    _label('Cycle Phase (self-reported)'),
                    const SizedBox(height: 7),
                    _choices(
                      const ['Not sure', 'Before period (PMS)',
                        'During period', 'After period'],
                      _phase,
                          (value) => setState(() => _phase = value),
                    ),
                    const SizedBox(height: 19),
                    _painSection(),
                    const SizedBox(height: 18),
                    _label('Bleeding / Flow (Optional)'),
                    const SizedBox(height: 7),
                    _choices(const ['Not recorded', 'None', 'Spotting',
                      'Light', 'Medium', 'Heavy'],
                        _flow, (value) => setState(() => _flow = value)),
                    const SizedBox(height: 18),
                    _label('Mood (Optional)'),
                    const SizedBox(height: 7),
                    _choices(const ['Not recorded', 'Calm', 'Happy',
                      'Low', 'Irritable', 'Anxious'],
                        _mood, (value) => setState(() => _mood = value)),
                    const SizedBox(height: 18),
                    _label('Energy (Optional)'),
                    const SizedBox(height: 7),
                    _choices(const ['Not recorded', 'Low', 'Moderate', 'Good'],
                        _energy, (value) => setState(() => _energy = value)),
                    const SizedBox(height: 20),
                    _symptomSection(),
                    const SizedBox(height: 19),
                    _label('Personal Notes (Optional)'),
                    const SizedBox(height: 7),
                    TextFormField(
                      controller: _notes,
                      maxLines: 4,
                      maxLength: 1200,
                      inputFormatters: [LengthLimitingTextInputFormatter(1200)],
                      decoration: _decoration(
                          'What did you experience today?'),
                    ),
                    const SizedBox(height: 14),
                    _label('What You Tried / What Helped (Optional)'),
                    const SizedBox(height: 7),
                    TextFormField(
                      controller: _reliefNotes,
                      maxLines: 3,
                      maxLength: 500,
                      inputFormatters: [LengthLimitingTextInputFormatter(500)],
                      decoration: _decoration('Rest, comfort measures, '
                          'or any other personal notes'),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _PSColor.blueLight,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, color: _PSColor.blue, size: 19),
                          SizedBox(width: 9),
                          Expanded(child: Text(
                            'Save preview stores this entry only in app memory. '
                                'There is no Women symptom API or permanent save yet.',
                            style: TextStyle(fontSize: 11,
                                color: _PSColor.text, height: 1.5),
                          )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 19),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(widget.original == null ?
                        'Save Session Preview' : 'Update Session Preview'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          backgroundColor: _PSColor.rose,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    )),
                  ],
                ),
              ),
            )),
          ),
        ),
      ),
    );
  }

  Widget _painSection() => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: _PSColor.roseLight,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: _painRecorded,
        activeThumbColor: _PSColor.rose,
        onChanged: (value) => setState(() => _painRecorded = value),
        title: const Text('Record Pain Intensity',
            style: TextStyle(fontWeight: FontWeight.w800,
                fontSize: 13, color: _PSColor.navy)),
        subtitle: const Text('Optional self-reported scale from 0 to 10',
            style: TextStyle(fontSize: 11)),
      ),
      if (_painRecorded) ...[
        Row(children: [
          const Text('No pain • 0', style: TextStyle(fontSize: 10)),
          const Spacer(),
          Text('$_painScore / 10', style: const TextStyle(
              fontSize: 17, color: _PSColor.rose,
              fontWeight: FontWeight.w800)),
        ]),
        Slider(
          min: 0,
          max: 10,
          divisions: 10,
          value: _painScore.toDouble(),
          activeColor: _PSColor.rose,
          label: '$_painScore / 10',
          onChanged: (value) =>
              setState(() => _painScore = value.round()),
        ),
        const Text('10 = worst pain imaginable',
            style: TextStyle(color: _PSColor.muted, fontSize: 10)),
      ],
    ]),
  );

  Widget _symptomSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label('Symptoms Experienced (Optional)'),
      const SizedBox(height: 7),
      const Text('Tap a symptom to select it. Then set its severity.',
          style: TextStyle(color: _PSColor.muted, fontSize: 11)),
      const SizedBox(height: 10),
      Wrap(spacing: 7, runSpacing: 7, children: [
        for (final symptom in _psSymptoms)
          FilterChip(
            label: Text(symptom.label,
                style: const TextStyle(fontSize: 11)),
            avatar: Icon(symptom.icon, size: 17,
                color: _levels.containsKey(symptom.id) ?
                _PSColor.purple : _PSColor.muted),
            selected: _levels.containsKey(symptom.id),
            selectedColor: const Color(0xFFF0EAF9),
            checkmarkColor: _PSColor.purple,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  _levels[symptom.id] = 1;
                } else {
                  _levels.remove(symptom.id);
                }
              });
            },
          ),
      ]),
      if (_levels.isNotEmpty) ...[
        const SizedBox(height: 13),
        const Text('Selected symptom severity', style: TextStyle(
            color: _PSColor.navy, fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(height: 8),
        for (final symptom in _psSymptoms)
          if (_levels.containsKey(symptom.id))
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _PSColor.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _PSColor.border),
                ),
                child: Row(children: [
                  Expanded(child: Text(symptom.label, style: const TextStyle(
                      color: _PSColor.text, fontSize: 12,
                      fontWeight: FontWeight.w700))),
                  DropdownButton<int>(
                    value: _levels[symptom.id],
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Mild')),
                      DropdownMenuItem(value: 2, child: Text('Moderate')),
                      DropdownMenuItem(value: 3, child: Text('Severe')),
                    ],
                    onChanged: (level) {
                      if (level != null) {
                        setState(() => _levels[symptom.id] = level);
                      }
                    },
                  ),
                ]),
              ),
            ),
      ],
    ]);
  }

  Widget _choices(List<String> values, String current,
      ValueChanged<String> onChanged) => Wrap(
    spacing: 7,
    runSpacing: 7,
    children: [
      for (final choice in values)
        ChoiceChip(
          label: Text(choice, style: const TextStyle(fontSize: 11)),
          selected: current == choice,
          showCheckmark: false,
          selectedColor: _PSColor.roseLight,
          side: BorderSide(color: current == choice ?
          _PSColor.rose : _PSColor.border),
          onSelected: (_) => onChanged(choice),
        ),
    ],
  );

  Widget _label(String label) => Text(label,
      style: const TextStyle(color: _PSColor.navy,
          fontWeight: FontWeight.w800, fontSize: 13));

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: _PSColor.muted, fontSize: 12),
    filled: true,
    fillColor: _PSColor.background,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _PSColor.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _PSColor.border),
    ),
  );
}
