import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

// ================================================================
// FAMILYCARE+ | WOMEN'S HEALTH | MENSTRUAL CYCLE
// ================================================================
// Backend v5 supports GET /api/v1/patients/profiles/{profileId}
// to verify the selected Women profile and its ownership.
// No menstrual-cycle CRUD endpoints exist in Backend v5.
// Therefore cycle entries below are IN-MEMORY PREVIEWS ONLY.
// They survive screen navigation during this app process, but are
// lost when the app closes/restarts. They are NOT saved to Flask,
// a device database, or analytics; no fake API success is shown.
// Calendar predictions are approximate, not fertility guidance.
// No external chart/calendar packages required.
// ================================================================

class MenstrualCycleScreen extends StatefulWidget {
  final String profileId;
  final String profileName;
  final String apiBaseUrl;

  const MenstrualCycleScreen({
    super.key,
    required this.profileId,
    this.profileName = 'Women Profile',
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL', defaultValue: '',
    ),
  });

  @override
  State<MenstrualCycleScreen> createState() => _MenstrualCycleScreenState();
}

class _CyclePalette {
  static const bg = Color(0xFFF7F8FC);
  static const ink = Color(0xFF183C60);
  static const muted = Color(0xFF6A7F92);
  static const rose = Color(0xFFB95879);
  static const roseLight = Color(0xFFFFEDF3);
  static const teal = Color(0xFF237F82);
  static const tealLight = Color(0xFFE7F4F3);
  static const blue = Color(0xFF3175D6);
  static const border = Color(0xFFE5E9F1);
  static const amber = Color(0xFF9D691D);
  static const amberLight = Color(0xFFFFF5DF);
}

DateTime _onlyDate(DateTime value) => DateTime(value.year, value.month, value.day);

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

String _friendlyDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

String _monthName(DateTime date) {
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${months[date.month - 1]} ${date.year}';
}

class _PeriodEntry {
  final String id;
  final DateTime start;
  final DateTime? end;
  final String flow;
  final List<String> symptoms;
  final String notes;

  const _PeriodEntry({
    required this.id,
    required this.start,
    required this.end,
    required this.flow,
    required this.symptoms,
    required this.notes,
  });

  bool contains(DateTime day) {
    final date = _onlyDate(day);
    if (date.isBefore(_onlyDate(start))) return false;
    // An open period is marked up to today, never infinitely into future.
    final last = end == null ? _onlyDate(DateTime.now()) : _onlyDate(end!);
    return !date.isAfter(last);
  }

  int? get duration => end == null ? null :
  _onlyDate(end!).difference(_onlyDate(start)).inDays + 1;
}

// Session memory only: deliberately no SharedPreferences/SQLite/network write.
class _PeriodSessionDrafts {
  static final Map<String, List<_PeriodEntry>> _drafts = {};

  static List<_PeriodEntry> forProfile(String id) =>
      List<_PeriodEntry>.from(_drafts[id] ?? const <_PeriodEntry>[]);

  static void set(String id, List<_PeriodEntry> entries) {
    _drafts[id] = List<_PeriodEntry>.from(entries);
  }

  static void clear(String id) => _drafts.remove(id);
}

class _CycleStats {
  final int? averageLength;
  final int? averageDuration;
  final DateTime? nextStart;
  final bool irregular;

  const _CycleStats({
    this.averageLength,
    this.averageDuration,
    this.nextStart,
    this.irregular = false,
  });

  static _CycleStats calculate(List<_PeriodEntry> records) {
    if (records.isEmpty) return const _CycleStats();
    final sorted = List<_PeriodEntry>.from(records)
      ..sort((a, b) => a.start.compareTo(b.start));
    final durations = sorted
        .map((r) => r.duration)
        .whereType<int>()
        .where((n) => n >= 1 && n <= 14)
        .toList();
    final averageDuration = durations.isEmpty ? null :
    (durations.reduce((a, b) => a + b) / durations.length).round();

    // Require three separate starts (two intervals) for an estimate.
    if (sorted.length < 3) {
      return _CycleStats(averageDuration: averageDuration);
    }
    final intervals = <int>[];
    for (var i = 1; i < sorted.length; i++) {
      final days = _onlyDate(sorted[i].start)
          .difference(_onlyDate(sorted[i - 1].start)).inDays;
      if (days >= 18 && days <= 60) intervals.add(days);
    }
    if (intervals.length < 2) {
      return _CycleStats(averageDuration: averageDuration);
    }
    final recent = intervals.length > 6
        ? intervals.sublist(intervals.length - 6)
        : intervals;
    final average = (recent.reduce((a, b) => a + b) / recent.length).round();
    final smallest = recent.reduce((a, b) => a < b ? a : b);
    final largest = recent.reduce((a, b) => a > b ? a : b);
    final irregular = largest - smallest > 7;
    DateTime next = _onlyDate(sorted.last.start).add(Duration(days: average));
    final today = _onlyDate(DateTime.now());
    while (next.isBefore(today)) {
      next = next.add(Duration(days: average));
    }
    return _CycleStats(
      averageLength: average,
      averageDuration: averageDuration,
      nextStart: next,
      irregular: irregular,
    );
  }
}

class _MenstrualCycleScreenState extends State<MenstrualCycleScreen> {
  final http.Client _client = http.Client();
  List<_PeriodEntry> _entries = [];
  DateTime _displayMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selectedDate = _onlyDate(DateTime.now());
  DateTime? _profileDob;
  String? _verifiedName;
  String? _profileError;
  bool _checkingProfile = true;
  int _requestVersion = 0;

  String get _baseUrl {
    final url = widget.apiBaseUrl.trim();
    if (url.isNotEmpty) return url.replaceAll(RegExp(r'/+$'), '');
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5001';
    }
    return 'http://127.0.0.1:5001';
  }

  @override
  void initState() {
    super.initState();
    _entries = _PeriodSessionDrafts.forProfile(widget.profileId);
    _verifyProfile();
  }

  @override
  void didUpdateWidget(covariant MenstrualCycleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _requestVersion++;
      _entries = _PeriodSessionDrafts.forProfile(widget.profileId);
      _profileDob = null;
      _verifiedName = null;
      _profileError = null;
      _verifyProfile();
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    _client.close();
    super.dispose();
  }

  Future<void> _verifyProfile() async {
    final version = ++_requestVersion;
    final profileId = widget.profileId;
    if (mounted) setState(() => _checkingProfile = true);
    try {
      if (profileId.trim().isEmpty) {
        throw const FormatException('Women profile ID is missing.');
      }
      final token = await FamilyCareSession.accessToken();
      if (token == null || token.isEmpty) {
        throw const FormatException('Please sign in again.');
      }
      final url = Uri.parse(
        '$_baseUrl/api/v1/patients/profiles/${Uri.encodeComponent(profileId)}',
      );
      final response = await _client.get(url, headers: {
        'Authorization': 'Bearer $token',
        'X-Auth-Transport': 'bearer',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401) {
          throw const FormatException('Session expired. Sign in again.');
        }
        throw FormatException(
          'Cannot access this Women profile (HTTP ${response.statusCode}).',
        );
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map || json['profile'] is! Map) {
        throw const FormatException('Invalid profile response from server.');
      }
      final profile = Map<String, dynamic>.from(json['profile'] as Map);
      if (profile['module'] != 'women' ||
          profile['id']?.toString() != profileId) {
        throw const FormatException('Please select a valid Women profile.');
      }
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _verifiedName = (profile['full_name'] ?? '').toString().trim();
        _profileDob = DateTime.tryParse(
          (profile['date_of_birth'] ?? '').toString(),
        );
        _profileError = null;
        _checkingProfile = false;
      });
    } on TimeoutException {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _profileError = 'Profile request timed out. Check the backend.';
        _checkingProfile = false;
      });
    } on http.ClientException {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _profileError = 'Cannot reach the FamilyCare+ backend.';
        _checkingProfile = false;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _profileError = error is FormatException
            ? error.message : 'Unable to verify the Women profile.';
        _checkingProfile = false;
      });
    }
  }

  bool get _canEdit => !_checkingProfile && _profileError == null;
  _CycleStats get _stats => _CycleStats.calculate(_entries);
  String get _name => (_verifiedName?.isNotEmpty ?? false)
      ? _verifiedName! : widget.profileName;

  void _saveDraft(_PeriodEntry entry) {
    final values = List<_PeriodEntry>.from(_entries);
    final index = values.indexWhere((value) => value.id == entry.id);
    if (index >= 0) {
      values[index] = entry;
    } else {
      values.add(entry);
    }
    values.sort((a, b) => b.start.compareTo(a.start));
    _PeriodSessionDrafts.set(widget.profileId, values);
    setState(() {
      _entries = values;
      _selectedDate = entry.start;
      _displayMonth = DateTime(entry.start.year, entry.start.month);
    });
    _snack('Preview updated for this session only. Not saved to backend.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _CyclePalette.ink,
        content: Text(message),
      ));
  }

  Future<void> _openEditor({_PeriodEntry? existing, DateTime? onDate}) async {
    if (!_canEdit) {
      _snack('Verify the selected Women profile before entering data.');
      return;
    }
    final profileId = widget.profileId;
    final draft = await showModalBottomSheet<_PeriodEntry>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PeriodEditorSheet(
        existing: existing,
        selectedDay: onDate ?? _selectedDate,
        birthDate: _profileDob,
        otherRecords: _entries.where((e) => e.id != existing?.id).toList(),
      ),
    );
    if (draft == null || !mounted || profileId != widget.profileId) return;
    _saveDraft(draft);
  }

  Future<void> _deleteEntry(_PeriodEntry entry) async {
    if (!_canEdit) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove period log?'),
        content: const Text(
          'This removes the in-memory preview entry. Nothing is deleted '
              'from the FamilyCare+ backend, because it was never uploaded.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final values = _entries.where((e) => e.id != entry.id).toList();
    _PeriodSessionDrafts.set(widget.profileId, values);
    setState(() => _entries = values);
    _snack('Period preview removed.');
  }

  Future<void> _clearDrafts() async {
    if (_entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear all preview entries?'),
        content: const Text(
          'All menstrual records entered during this app session for this '
              'profile will be cleared. This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear preview')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    _PeriodSessionDrafts.clear(widget.profileId);
    setState(() => _entries = []);
    _snack('All in-memory preview entries cleared.');
  }

  void _changeMonth(int offset) {
    setState(() => _displayMonth = DateTime(
      _displayMonth.year, _displayMonth.month + offset,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _CyclePalette.bg,
      appBar: AppBar(
        title: const Text('Menstrual Cycle',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        backgroundColor: Colors.white,
        foregroundColor: _CyclePalette.ink,
        actions: [
          IconButton(
            tooltip: 'Clear session preview',
            onPressed: _entries.isEmpty ? null : _clearDrafts,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
          IconButton(
            tooltip: 'Reload Women profile',
            onPressed: _checkingProfile ? null : _verifyProfile,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _canEdit ? FloatingActionButton.extended(
        backgroundColor: _CyclePalette.rose,
        foregroundColor: Colors.white,
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log Period'),
      ) : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 108),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1060),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hero(),
                    const SizedBox(height: 14),
                    _sessionNotice(),
                    if (_checkingProfile) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(color: _CyclePalette.rose),
                    ],
                    if (_profileError != null) ...[
                      const SizedBox(height: 12),
                      _errorCard(),
                    ],
                    const SizedBox(height: 17),
                    _summaryCards(),
                    const SizedBox(height: 18),
                    LayoutBuilder(builder: (context, constraints) {
                      if (constraints.maxWidth >= 760) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: _calendarCard()),
                            const SizedBox(width: 16),
                            Expanded(flex: 4, child: _insightCard()),
                          ],
                        );
                      }
                      return Column(children: [
                        _calendarCard(),
                        const SizedBox(height: 16),
                        _insightCard(),
                      ]);
                    }),
                    const SizedBox(height: 18),
                    _historyCard(),
                    const SizedBox(height: 18),
                    _healthNotice(),
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
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [
          Color(0xFFFFECF3), Color(0xFFEAF5F5), Color(0xFFF5F0FF),
        ]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        const CircleAvatar(
          radius: 27,
          backgroundColor: Colors.white,
          child: Icon(Icons.calendar_month_outlined,
              color: _CyclePalette.rose, size: 30),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PERIODS & HORMONAL HEALTH',
                style: TextStyle(color: _CyclePalette.teal,
                    fontSize: 10, letterSpacing: 1.2,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Cycle diary for $_name',
                style: const TextStyle(color: _CyclePalette.ink,
                    fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('A private, simple way to note your period days and symptoms.',
                style: TextStyle(color: _CyclePalette.muted, fontSize: 12)),
          ],
        )),
      ]),
    );
  }

  Widget _sessionNotice() => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: _CyclePalette.amberLight,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.info_outline_rounded, color: _CyclePalette.amber, size: 20),
      SizedBox(width: 10),
      Expanded(child: Text(
        'Preview mode: Period entries are kept in app memory only. '
            'They are not saved to the backend or device storage and will '
            'disappear when the app closes or restarts. No reminders are sent.',
        style: TextStyle(fontSize: 11, height: 1.45, color: _CyclePalette.ink),
      )),
    ]),
  );

  Widget _errorCard() => _panel(
    child: Column(children: [
      const Icon(Icons.cloud_off_rounded, color: _CyclePalette.amber, size: 28),
      const SizedBox(height: 7),
      Text(_profileError!, textAlign: TextAlign.center,
          style: const TextStyle(color: _CyclePalette.ink)),
      const SizedBox(height: 8),
      TextButton.icon(onPressed: _verifyProfile,
          icon: const Icon(Icons.refresh), label: const Text('Retry profile check')),
    ]),
  );

  Widget _summaryCards() {
    final stats = _stats;
    final latest = _entries.isEmpty ? null : _entries.first;
    final data = <(String, String, IconData, Color)>[
      ('Logged periods', '${_entries.length}', Icons.history_rounded, _CyclePalette.rose),
      ('Last started', latest == null ? '—' : _friendlyDate(latest.start),
      Icons.water_drop_outlined, _CyclePalette.teal),
      ('Avg. cycle', stats.averageLength == null ? 'Not enough data' :
      '${stats.averageLength} days', Icons.timeline_outlined, _CyclePalette.blue),
      ('Next estimate', stats.nextStart == null ? 'Not available' :
      _friendlyDate(stats.nextStart!), Icons.event_note_outlined, _CyclePalette.rose),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth >= 820 ? 4 : 2;
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap,
        children: [for (final item in data) SizedBox(
          width: width,
          child: _panel(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.$3, color: item.$4, size: 22),
              const SizedBox(height: 12),
              Text(item.$2, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800,
                      fontSize: 16, color: _CyclePalette.ink)),
              const SizedBox(height: 5),
              Text(item.$1, style: const TextStyle(
                  fontSize: 11, color: _CyclePalette.muted)),
            ],
          )),
        )],
      );
    });
  }

  Widget _panel({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: _CyclePalette.border),
    ),
    child: child,
  );

  Widget _calendarCard() {
    final daysInMonth = DateUtils.getDaysInMonth(
      _displayMonth.year, _displayMonth.month,
    );
    final first = DateTime(_displayMonth.year, _displayMonth.month, 1);
    final firstOffset = (first.weekday + 6) % 7; // Monday first.
    final totalCells = ((firstOffset + daysInMonth + 6) ~/ 7) * 7;
    final today = _onlyDate(DateTime.now());
    final estimate = _stats.nextStart;

    return _panel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(child: Text('Period Calendar',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                  color: _CyclePalette.ink))),
          IconButton(tooltip: 'Previous month',
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left_rounded)),
          Text(_monthName(_displayMonth),
              style: const TextStyle(fontSize: 12,
                  fontWeight: FontWeight.w800, color: _CyclePalette.ink)),
          IconButton(tooltip: 'Next month', onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right_rounded)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          for (final label in const ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
            Expanded(child: Center(child: Text(label,
                style: const TextStyle(color: _CyclePalette.muted,
                    fontSize: 11, fontWeight: FontWeight.w700)))),
        ]),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: totalCells,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, mainAxisSpacing: 5,
            crossAxisSpacing: 5, childAspectRatio: 1.05,
          ),
          itemBuilder: (context, index) {
            final dayNumber = index - firstOffset + 1;
            if (dayNumber < 1 || dayNumber > daysInMonth) {
              return const SizedBox.shrink();
            }
            final day = DateTime(
              _displayMonth.year, _displayMonth.month, dayNumber,
            );
            final logged = _entries.any((entry) => entry.contains(day));
            final predicted = estimate != null &&
                _onlyDate(estimate) == _onlyDate(day);
            final selected = _onlyDate(day) == _selectedDate;
            final current = _onlyDate(day) == today;
            return InkWell(
              key: ValueKey(_isoDate(day)),
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => _selectedDate = _onlyDate(day)),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: logged ? _CyclePalette.rose :
                  (predicted ? _CyclePalette.roseLight :
                  (selected ? _CyclePalette.tealLight : Colors.white)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    width: selected ? 2 : 1,
                    color: selected ? _CyclePalette.teal :
                    (current ? _CyclePalette.blue :
                    (predicted ? _CyclePalette.rose :
                    _CyclePalette.border)),
                  ),
                ),
                child: Text('$dayNumber',
                    style: TextStyle(
                      color: logged ? Colors.white : _CyclePalette.ink,
                      fontWeight: selected || logged
                          ? FontWeight.w800 : FontWeight.w500,
                      fontSize: 12,
                    )),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 14, runSpacing: 8, children: [
          _legend(_CyclePalette.rose, 'Logged days'),
          _legend(_CyclePalette.roseLight, 'Estimated start'),
          _legend(_CyclePalette.tealLight, 'Selected date'),
        ]),
        const SizedBox(height: 13),
        Text('Selected: ${_friendlyDate(_selectedDate)}',
            style: const TextStyle(fontSize: 12, color: _CyclePalette.muted)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: !_canEdit || _selectedDate.isAfter(today)
              ? null : () => _openEditor(onDate: _selectedDate),
          icon: const Icon(Icons.edit_calendar_outlined),
          label: const Text('Log period for selected date'),
        ),
      ],
    ));
  }

  Widget _legend(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 11, height: 11,
          decoration: BoxDecoration(color: color,
              borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: _CyclePalette.muted, fontSize: 10)),
    ],
  );

  Widget _insightCard() {
    final stats = _stats;
    final recent = _entries.isEmpty ? null : _entries.first;
    return _panel(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Icon(Icons.insights_outlined, color: _CyclePalette.teal),
          SizedBox(width: 9),
          Text('Cycle Overview', style: TextStyle(fontSize: 17,
              fontWeight: FontWeight.w800, color: _CyclePalette.ink)),
        ]),
        const SizedBox(height: 15),
        _insight('Latest period', recent == null ? 'Not logged yet' :
        '${_friendlyDate(recent.start)}${recent.end == null ? ' • Ongoing' : ''}'),
        const Divider(height: 20),
        _insight('Average bleed duration', stats.averageDuration == null ?
        'Not enough data' : '${stats.averageDuration} days'),
        const Divider(height: 20),
        _insight('Cycle length', stats.averageLength == null ?
        'Log 3 cycle starts for an estimate' : '${stats.averageLength} days'),
        const Divider(height: 20),
        _insight('Approximate next start', stats.nextStart == null ?
        'Not calculated' : _friendlyDate(stats.nextStart!)),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _CyclePalette.roseLight,
              borderRadius: BorderRadius.circular(10)),
          child: Text(
            stats.irregular
                ? 'Recorded intervals vary considerably. Prediction may be unreliable.'
                : 'Estimates use logged dates only. They cannot confirm ovulation, '
                'fertile days or pregnancy and should not guide contraception.',
            style: const TextStyle(fontSize: 11, height: 1.5,
                color: _CyclePalette.ink),
          ),
        ),
      ],
    ));
  }

  Widget _insight(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(
          color: _CyclePalette.muted, fontSize: 11)),
      const SizedBox(height: 4),
      Text(value, style: const TextStyle(color: _CyclePalette.ink,
          fontSize: 13, fontWeight: FontWeight.w800)),
    ],
  );

  Widget _historyCard() => _panel(child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        const Expanded(child: Text('Cycle History',
            style: TextStyle(color: _CyclePalette.ink,
                fontSize: 17, fontWeight: FontWeight.w800))),
        Text('${_entries.length} preview logs',
            style: const TextStyle(fontSize: 11, color: _CyclePalette.muted)),
      ]),
      const SizedBox(height: 6),
      const Text('Entries are not stored in your FamilyCare+ account.',
          style: TextStyle(color: _CyclePalette.muted, fontSize: 11)),
      const SizedBox(height: 15),
      if (_entries.isEmpty)
        Center(child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 23),
          child: Column(children: [
            const Icon(Icons.event_note_outlined, size: 43,
                color: _CyclePalette.rose),
            const SizedBox(height: 10),
            const Text('No period entries in this session',
                style: TextStyle(color: _CyclePalette.ink,
                    fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _canEdit ? () => _openEditor() : null,
              style: FilledButton.styleFrom(backgroundColor: _CyclePalette.rose,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.add), label: const Text('Log First Period'),
            ),
          ]),
        )),
      for (final entry in _entries) ...[
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: _CyclePalette.bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.water_drop_outlined,
                    color: _CyclePalette.rose, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  '${_friendlyDate(entry.start)} – '
                      '${entry.end == null ? 'Ongoing' : _friendlyDate(entry.end!)}',
                  style: const TextStyle(color: _CyclePalette.ink,
                      fontWeight: FontWeight.w800, fontSize: 13),
                )),
                IconButton(tooltip: 'Edit period log',
                    onPressed: _canEdit ? () => _openEditor(existing: entry) : null,
                    icon: const Icon(Icons.edit_outlined, color: _CyclePalette.blue)),
                IconButton(tooltip: 'Remove period log',
                    onPressed: _canEdit ? () => _deleteEntry(entry) : null,
                    icon: const Icon(Icons.delete_outline, color: _CyclePalette.rose)),
              ]),
              const SizedBox(height: 7),
              Text('Flow: ${entry.flow}'
                  '${entry.duration == null ? '' : '   •   ${entry.duration} days'}',
                  style: const TextStyle(color: _CyclePalette.muted, fontSize: 11)),
              if (entry.symptoms.isNotEmpty) ...[
                const SizedBox(height: 9),
                Wrap(spacing: 6, runSpacing: 6,
                  children: [for (final symptom in entry.symptoms)
                    Chip(label: Text(symptom, style: const TextStyle(fontSize: 10)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: _CyclePalette.roseLight,
                      side: BorderSide.none,
                    )],
                ),
              ],
              if (entry.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(entry.notes, style: const TextStyle(
                    color: _CyclePalette.ink, fontSize: 12)),
              ],
            ],
          ),
        ),
      ],
    ],
  ));

  Widget _healthNotice() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _CyclePalette.tealLight,
      borderRadius: BorderRadius.circular(13),
    ),
    child: const Row(crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.health_and_safety_outlined, color: _CyclePalette.teal),
        SizedBox(width: 10),
        Expanded(child: Text(
          'This diary records self-reported observations, not a diagnosis. '
              'Seek medical advice for unusual bleeding, severe pain or persistent '
              'cycle changes. Very heavy bleeding, fainting or severe sudden pain '
              'may need urgent medical care. Never rely on cycle predictions to '
              'prevent pregnancy.',
          style: TextStyle(color: _CyclePalette.ink, fontSize: 11, height: 1.5),
        )),
      ],
    ),
  );
}

// ================================================================
// ADD / EDIT PERIOD SHEET
// ================================================================
class _PeriodEditorSheet extends StatefulWidget {
  final _PeriodEntry? existing;
  final DateTime selectedDay;
  final DateTime? birthDate;
  final List<_PeriodEntry> otherRecords;

  const _PeriodEditorSheet({
    this.existing,
    required this.selectedDay,
    required this.birthDate,
    required this.otherRecords,
  });

  @override
  State<_PeriodEditorSheet> createState() => _PeriodEditorSheetState();
}

class _PeriodEditorSheetState extends State<_PeriodEditorSheet> {
  static const _symptomOptions = [
    'Cramps', 'Bloating', 'Headache', 'Fatigue',
    'Back pain', 'Mood changes', 'Breast tenderness',
    'Nausea', 'Acne', 'Other',
  ];
  final TextEditingController _notes = TextEditingController();
  late DateTime _start;
  DateTime? _end;
  late bool _ongoing;
  late String _flow;
  final Set<String> _symptoms = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final today = _onlyDate(DateTime.now());
    _start = _onlyDate(existing?.start ?? widget.selectedDay);
    if (_start.isAfter(today)) _start = today;
    _end = existing?.end;
    _ongoing = existing == null ? true : existing.end == null;
    _flow = existing?.flow ?? 'Not sure';
    _symptoms.addAll(existing?.symptoms ?? []);
    _notes.text = existing?.notes ?? '';
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickStart() async {
    final today = _onlyDate(DateTime.now());
    final birth = widget.birthDate == null ? null :
    _onlyDate(widget.birthDate!);
    final first = birth != null && !birth.isAfter(today)
        ? birth : DateTime(1900);
    final value = await showDatePicker(
      context: context, initialDate: _start,
      firstDate: first, lastDate: today,
      helpText: 'PERIOD START DATE',
    );
    if (!mounted || value == null) return;
    setState(() {
      _start = _onlyDate(value);
      if (_end != null && _end!.isBefore(_start)) _end = null;
      _error = null;
    });
  }

  Future<void> _pickEnd() async {
    final today = _onlyDate(DateTime.now());
    if (_start.isAfter(today)) return;
    final value = await showDatePicker(
      context: context,
      initialDate: _end != null && !_end!.isBefore(_start)
          ? _end! : _start,
      firstDate: _start, lastDate: today,
      helpText: 'PERIOD END DATE',
    );
    if (!mounted || value == null) return;
    setState(() {
      _end = _onlyDate(value);
      _error = null;
    });
  }

  void _submit() {
    final today = _onlyDate(DateTime.now());
    final end = _ongoing ? null : _end;
    if (_start.isAfter(today)) {
      setState(() => _error = 'Period start cannot be in the future.');
      return;
    }
    if (widget.birthDate != null &&
        _start.isBefore(_onlyDate(widget.birthDate!))) {
      setState(() => _error = 'Period start cannot be before date of birth.');
      return;
    }
    if (!_ongoing && end == null) {
      setState(() => _error = 'Select the period end date or mark ongoing.');
      return;
    }
    if (end != null && (end.isBefore(_start) || end.isAfter(today))) {
      setState(() => _error = 'End date must be between start and today.');
      return;
    }
    final checkEnd = end ?? today;
    for (final old in widget.otherRecords) {
      final oldEnd = old.end ?? today;
      final overlaps = !_start.isAfter(oldEnd) && !checkEnd.isBefore(old.start);
      if (overlaps) {
        setState(() => _error = 'This period overlaps another entry. '
            'Edit the existing period or choose different dates.');
        return;
      }
    }
    Navigator.pop(context, _PeriodEntry(
      id: widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      start: _start,
      end: end,
      flow: _flow,
      symptoms: _symptoms.toList()..sort(),
      notes: _notes.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: height * 0.92),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(top: false, child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: Text(
                    widget.existing == null ? 'Log a Period' : 'Edit Period Log',
                    style: const TextStyle(fontSize: 21,
                        color: _CyclePalette.ink, fontWeight: FontWeight.w800),
                  )),
                  IconButton(tooltip: 'Close', icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context)),
                ]),
                const SizedBox(height: 6),
                const Text('Session preview only • not saved to the server',
                    style: TextStyle(color: _CyclePalette.amber, fontSize: 11)),
                const SizedBox(height: 20),
                _label('Period start date *'),
                const SizedBox(height: 8),
                _dateButton(_friendlyDate(_start), _pickStart),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: _CyclePalette.rose,
                  title: const Text('Period is ongoing',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Turn off when bleeding has ended.'),
                  value: _ongoing,
                  onChanged: (value) => setState(() {
                    _ongoing = value;
                    _error = null;
                  }),
                ),
                if (!_ongoing) ...[
                  const SizedBox(height: 8),
                  _label('Period end date *'),
                  const SizedBox(height: 8),
                  _dateButton(_end == null ? 'Choose end date' :
                  _friendlyDate(_end!), _pickEnd),
                ],
                const SizedBox(height: 20),
                _label('Flow (optional)'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8,
                  children: [for (final flow in const [
                    'Not sure', 'Light', 'Medium', 'Heavy',
                  ]) ChoiceChip(
                    label: Text(flow),
                    selected: _flow == flow,
                    selectedColor: _CyclePalette.roseLight,
                    onSelected: (_) => setState(() => _flow = flow),
                  )],
                ),
                const SizedBox(height: 20),
                _label('Symptoms (optional)'),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8,
                  children: [for (final symptom in _symptomOptions)
                    FilterChip(
                      label: Text(symptom),
                      selected: _symptoms.contains(symptom),
                      selectedColor: _CyclePalette.roseLight,
                      onSelected: (checked) => setState(() {
                        checked ? _symptoms.add(symptom) : _symptoms.remove(symptom);
                      }),
                    )],
                ),
                const SizedBox(height: 20),
                _label('Personal notes (optional)'),
                const SizedBox(height: 8),
                TextField(
                  controller: _notes,
                  maxLines: 4,
                  maxLength: 700,
                  decoration: InputDecoration(
                    hintText: 'Any observations you want to remember…',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(
                      color: Colors.redAccent, fontSize: 12)),
                ],
                const SizedBox(height: 17),
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(widget.existing == null
                      ? 'Add to Session Preview' : 'Update Session Preview'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    backgroundColor: _CyclePalette.rose,
                    foregroundColor: Colors.white,
                  ),
                )),
                const SizedBox(height: 8),
                Center(child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                )),
              ],
            ),
          )),
        )),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: _CyclePalette.ink,
          fontSize: 13, fontWeight: FontWeight.w800));

  Widget _dateButton(String text, VoidCallback onTap) =>
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(text),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 49),
            alignment: Alignment.centerLeft,
            foregroundColor: _CyclePalette.ink,
          ),
        ),
      );
}
