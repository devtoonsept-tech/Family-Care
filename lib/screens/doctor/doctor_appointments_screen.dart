import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

// FamilyCare+ Backend v10: scheduled capacity bookings and legacy consultations
// are independent workflows and are intentionally displayed separately.
class DoctorAppointmentsScreen extends StatefulWidget {
  const DoctorAppointmentsScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.initialProfile,
    this.onBack,
  });

  final String apiBaseUrl;
  final Map<String, dynamic>? initialProfile;
  final VoidCallback? onBack;

  @override
  State<DoctorAppointmentsScreen> createState() =>
      _DoctorAppointmentsScreenState();
}

class _A {
  static const bg = Color(0xFFF4FAF8);
  static const white = Colors.white;
  static const ink = Color(0xFF204A50);
  static const muted = Color(0xFF71898A);
  static const green = Color(0xFF257B6B);
  static const teal = Color(0xFF128C86);
  static const blue = Color(0xFF4683AE);
  static const purple = Color(0xFF776EB3);
  static const amber = Color(0xFFAA792D);
  static const red = Color(0xFFB65359);
  static const border = Color(0xFFDCEBE7);
  static const mint = Color(0xFFE6F5EE);
  static const ice = Color(0xFFEEF6FB);
}

class _ApiError implements Exception {
  const _ApiError(this.message, [this.status = 0]);
  final String message;
  final int status;
  @override
  String toString() => message;
}

class _TimeChoice {
  const _TimeChoice(this.start, this.duration);
  final DateTime start;
  final int duration;
}

String _txt(dynamic v) => (v ?? '').toString().trim();
Map<String, dynamic> _obj(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> _list(dynamic v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : <Map<String, dynamic>>[];
int? _integer(dynamic v) => v is num ? v.toInt() : int.tryParse(_txt(v));
DateTime? _localTime(dynamic v) => DateTime.tryParse(_txt(v))?.toLocal();

// Booking dates and weekly window clocks are ALWAYS Asia/Kolkata,
// independent of the doctor's device timezone.
DateTime _indiaToday() {
  final now = DateTime.now().toUtc().add(
    const Duration(hours: 5, minutes: 30),
  );
  return DateTime(now.year, now.month, now.day);
}

String _ymd(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];
const _weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String _dayLabel(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]}, ${d.day} ${_monthNames[d.month - 1]} ${d.year}';
String _clock(DateTime d) =>
    '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour >= 12 ? 'PM' : 'AM'}';
String _dateTimeLabel(DateTime? d) =>
    d == null ? 'Not provided' : '${_dayLabel(d)} • ${_clock(d)}';
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _newUuid() {
  final random = Random.secure();
  final b = List<int>.generate(16, (_) => random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
      '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

// Parses an Indian appointment wall-clock time into an actual instant.
DateTime? _bookingStart(Map<String, dynamic> booking) {
  final date = _txt(booking['appointment_date']);
  final start = _txt(booking['start']);
  if (date.isEmpty || !RegExp(r'^\d\d:\d\d$').hasMatch(start)) {
    return null;
  }
  return DateTime.tryParse('${date}T$start:00+05:30')?.toLocal();
}

TimeOfDay _parseClock(String? value, TimeOfDay fallback) {
  final parts = (value ?? '').split(':');
  if (parts.length != 2) return fallback;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null || hour < 0 || hour > 23 ||
      minute < 0 || minute > 59) {
    return fallback;
  }
  return TimeOfDay(hour: hour, minute: minute);
}

String _hhmm(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
String _prettyClock(String v) {
  if (!RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(v)) {
    return 'Time unavailable';
  }
  final t = _parseClock(v, const TimeOfDay(hour: 9, minute: 0));
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour >= 12 ? 'PM' : 'AM'}';
}

class _DoctorAppointmentsScreenState extends State<DoctorAppointmentsScreen> {
  final _client = http.Client();
  final _search = TextEditingController();

  bool _verifying = true;
  bool _authorized = false;
  bool _loadingBookings = false;
  bool _loadingSchedule = false;
  bool _loadingVisits = false;
  bool _loadingSlots = false;
  bool _scheduleDirty = false;
  String? _authError;
  String? _bookingError;
  String? _scheduleError;
  String? _visitsError;
  String? _slotsError;
  String? _savingAction;

  String _tab = 'bookings';
  String _visitView = 'requests';
  String _statusFilter = 'ALL';
  DateTime _bookingDay = _indiaToday();
  DateTime? _visitDay;

  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _schedule = [];
  List<Map<String, dynamic>> _visits = [];
  List<Map<String, dynamic>> _slots = [];
  int? _scheduleVersion;

  int _authEpoch = 0;
  int _bookingsEpoch = 0;
  int _scheduleEpoch = 0;
  int _visitsEpoch = 0;
  int _slotsEpoch = 0;

  String get _profileId => _txt(widget.initialProfile?['id']);
  bool get _saving => _savingAction != null;

  String get _doctorBase {
    var base = widget.apiBaseUrl.trim();
    if (base.isEmpty) {
      base = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:5001'
          : 'http://127.0.0.1:5001';
    }
    base = base.replaceFirst(RegExp(r'/+$'), '');
    if (base.endsWith('/api/v1/doctors')) return base;
    if (base.endsWith('/api/v1')) return '$base/doctors';
    return '$base/api/v1/doctors';
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(_searchChanged);
    unawaited(_verify());
  }

  @override
  void didUpdateWidget(covariant DoctorAppointmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      unawaited(_verify());
    } else if (_txt(oldWidget.initialProfile?['id']) != _profileId) {
      _search.clear();
      setState(() {
        _visitView = 'requests';
        _visitDay = null;
        _statusFilter = 'ALL';
      });
    }
  }

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _authEpoch++;
    _bookingsEpoch++;
    _scheduleEpoch++;
    _visitsEpoch++;
    _slotsEpoch++;
    _search.removeListener(_searchChanged);
    _search.dispose();
    _client.close();
    super.dispose();
  }

  String _friendly(Object e) {
    if (e is _ApiError) return e.message;
    if (e is TimeoutException) return 'Request timed out. Please retry.';
    if (e is FormatException) return 'Invalid response from the server.';
    if (e is http.ClientException) {
      return 'Cannot reach FamilyCare+. Check the backend address and network.';
    }
    return 'Unable to complete the request. Please try again.';
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? _A.red : _A.ink,
      ));
  }

  Future<Map<String, dynamic>> _api(
      String method,
      String path, {
        Map<String, dynamic>? body,
        Map<String, String>? query,
      }) async {
    final role = await FamilyCareSession.role();
    final access = await FamilyCareSession.accessToken();
    final expiry = await FamilyCareSession.accessTokenExpiresAt();
    if (_txt(role).toUpperCase() != 'DOCTOR' ||
        access == null || access.trim().isEmpty || expiry == null ||
        !expiry.isAfter(DateTime.now().toUtc())) {
      throw const _ApiError('Doctor session expired. Please sign in again.', 401);
    }
    final uri = Uri.parse('$_doctorBase$path').replace(queryParameters: query);
    final headers = <String, String>{
      'Authorization': 'Bearer $access',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final http.Response response;
    switch (method) {
      case 'PUT':
        response = await _client.put(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
      case 'PATCH':
        response = await _client.patch(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 30));
      case 'POST':
        response = await _client.post(uri, headers: headers, body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 30));
      case 'DELETE':
        response = await _client.delete(uri, headers: headers).timeout(const Duration(seconds: 30));
      default:
        response = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 30));
    }
    Map<String, dynamic> data = {};
    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        } else if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const FormatException('Expected a JSON object.');
        }
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final issue = data['error'];
      final message = issue is Map ? _txt(issue['message']) : _txt(issue);
      final fallback = switch (response.statusCode) {
        401 => 'Doctor session expired. Sign in again.',
        403 => 'Doctor permission denied.',
        404 => 'Requested appointment was not found.',
        409 => 'This record changed. Refresh it and try again.',
        422 => 'Check the selected date, times, capacity or status.',
        429 => 'Too many requests. Please retry later.',
        _ => 'Request failed (HTTP ${response.statusCode}).',
      };
      throw _ApiError(message.isEmpty ? fallback : message, response.statusCode);
    }
    return data;
  }

  void _accessLost(String message) {
    _authEpoch++;
    _bookingsEpoch++;
    _scheduleEpoch++;
    _visitsEpoch++;
    _slotsEpoch++;
    if (!mounted) return;
    setState(() {
      _authorized = false;
      _verifying = false;
      _authError = message;
      _loadingBookings = false;
      _loadingSchedule = false;
      _loadingVisits = false;
      _loadingSlots = false;
      _bookings = [];
      _visits = [];
      _slots = [];
      _schedule = [];
      _scheduleVersion = null;
      _scheduleDirty = false;
    });
  }

  Future<void> _verify() async {
    final version = ++_authEpoch;
    _bookingsEpoch++;
    _scheduleEpoch++;
    _visitsEpoch++;
    _slotsEpoch++;
    setState(() {
      _verifying = true;
      _authorized = false;
      _authError = null;
    });
    try {
      final result = await _api('GET', '/me');
      final user = _obj(result['user']);
      if (_txt(user['role']).toUpperCase() != 'DOCTOR' ||
          _txt(user['approval_status']).toUpperCase() != 'APPROVED' ||
          _txt(user['account_status']).toUpperCase() != 'ACTIVE') {
        throw const _ApiError('Only an active, approved doctor can manage appointments.', 403);
      }
      if (!mounted || version != _authEpoch) return;
      setState(() {
        _authorized = true;
        _verifying = false;
      });
      await Future.wait([_loadBookings(), _loadSchedule(), _loadVisits(), _loadSlots()]);
    } catch (e) {
      if (mounted && version == _authEpoch) _accessLost(_friendly(e));
    }
  }

  Future<void> _loadBookings() async {
    if (!_authorized) return;
    final version = ++_bookingsEpoch;
    final date = _ymd(_bookingDay);
    setState(() {
      _loadingBookings = true;
      _bookingError = null;
    });
    try {
      final result = await _api('GET', '/booked-appointments', query: {'date': date});
      if (result['items'] is! List || _txt(result['date']) != date) {
        throw const FormatException('Incomplete booked appointments response.');
      }
      if (!mounted || version != _bookingsEpoch) return;
      setState(() => _bookings = _list(result['items']));
    } catch (e) {
      if (!mounted || version != _bookingsEpoch) return;
      if (e is _ApiError && e.status == 401) {
        _accessLost(_friendly(e));
        return;
      }
      setState(() {
        _bookings = [];
        _bookingError = _friendly(e);
      });
    } finally {
      if (mounted && version == _bookingsEpoch) {
        setState(() => _loadingBookings = false);
      }
    }
  }

  Future<void> _loadSchedule({bool discardDraft = false}) async {
    if (!_authorized) return;
    if (_scheduleDirty && !discardDraft) return;
    final version = ++_scheduleEpoch;
    setState(() {
      _loadingSchedule = true;
      _scheduleError = null;
    });
    try {
      final data = await _api('GET', '/appointment-schedule');
      final v = _integer(data['version']);
      if (v == null || v < 0 || data['windows'] is! List ||
          _txt(data['timezone']) != 'Asia/Kolkata') {
        throw const FormatException('Invalid weekly schedule response.');
      }
      if (!mounted || version != _scheduleEpoch) return;
      setState(() {
        _schedule = _list(data['windows']);
        _scheduleVersion = v;
        _scheduleDirty = false;
      });
    } catch (e) {
      if (!mounted || version != _scheduleEpoch) return;
      if (e is _ApiError && e.status == 401) {
        _accessLost(_friendly(e));
        return;
      }
      setState(() => _scheduleError = _friendly(e));
    } finally {
      if (mounted && version == _scheduleEpoch) {
        setState(() => _loadingSchedule = false);
      }
    }
  }

  Future<void> _loadVisits() async {
    if (!_authorized) return;
    final version = ++_visitsEpoch;
    setState(() {
      _loadingVisits = true;
      _visitsError = null;
    });
    try {
      final data = await _api('GET', '/consultation-visits');
      if (data['items'] is! List) throw const FormatException('Invalid consultation response.');
      if (!mounted || version != _visitsEpoch) return;
      setState(() => _visits = _list(data['items']));
    } catch (e) {
      if (!mounted || version != _visitsEpoch) return;
      if (e is _ApiError && e.status == 401) {
        _accessLost(_friendly(e));
        return;
      }
      setState(() => _visitsError = _friendly(e));
    } finally {
      if (mounted && version == _visitsEpoch) {
        setState(() => _loadingVisits = false);
      }
    }
  }

  Future<void> _loadSlots() async {
    if (!_authorized) return;
    final version = ++_slotsEpoch;
    setState(() {
      _loadingSlots = true;
      _slotsError = null;
    });
    try {
      final data = await _api('GET', '/appointment-slots');
      if (data['items'] is! List) throw const FormatException('Invalid slot response.');
      if (!mounted || version != _slotsEpoch) return;
      setState(() => _slots = _list(data['items']));
    } catch (e) {
      if (!mounted || version != _slotsEpoch) return;
      if (e is _ApiError && e.status == 401) {
        _accessLost(_friendly(e));
        return;
      }
      setState(() => _slotsError = _friendly(e));
    } finally {
      if (mounted && version == _slotsEpoch) {
        setState(() => _loadingSlots = false);
      }
    }
  }

  Future<void> _refresh() async {
    if (!_authorized || _saving) return;
    switch (_tab) {
      case 'bookings':
        await _loadBookings();
        return;
      case 'schedule':
        if (_scheduleDirty) {
          final discard = await _confirm(
            'Discard unsaved schedule?',
            'Reloading will replace your unsaved weekly schedule changes.',
            action: 'Discard & Reload',
            destructive: true,
          );
          if (discard != true || !mounted) return;
        }
        await _loadSchedule(discardDraft: true);
        return;
      case 'requests':
        await Future.wait([_loadVisits(), _loadSlots()]);
        return;
      case 'slots':
        await _loadSlots();
        return;
    }
  }

  Future<bool?> _confirm(
      String heading,
      String message, {
        String action = 'Confirm',
        bool destructive = false,
      }) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(heading),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go Back')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: destructive ? _A.red : _A.green),
          child: Text(action),
        ),
      ],
    ),
  );

  // ============================================================
  // V10: DATE-SCOPED CAPACITY BOOKINGS
  // ============================================================

  Future<void> _chooseBookingDay() async {
    final today = _indiaToday();
    final selected = await showDatePicker(
      context: context,
      initialDate: _bookingDay,
      firstDate: today,
      lastDate: DateTime(today.year, today.month, today.day + 90),
      helpText: 'Choose booking date (India time)',
    );
    if (!mounted || selected == null || _sameDay(selected, _bookingDay)) return;
    setState(() => _bookingDay = selected);
    await _loadBookings();
  }

  List<Map<String, dynamic>> get _visibleBookings {
    final filtered = _bookings.where((b) =>
    _profileId.isEmpty || _txt(b['profile_id']) == _profileId).toList();
    filtered.sort((a, b) => _txt(a['start']).compareTo(_txt(b['start'])));
    return filtered;
  }

  Future<void> _changeBooking(Map<String, dynamic> booking, String next) async {
    if (_saving || !_authorized) return;
    final id = _txt(booking['id']);
    if (id.isEmpty || _txt(booking['status']) != 'BOOKED') return;
    final confirm = await _confirm(
      next == 'COMPLETED' ? 'Complete appointment?' : 'Cancel appointment?',
      next == 'COMPLETED'
          ? 'Only mark the visit completed after its scheduled window has started and the visit has happened.'
          : 'This booking will be cancelled, releasing capacity for another patient.',
      action: next == 'COMPLETED' ? 'Complete' : 'Cancel Booking',
      destructive: next == 'CANCELLED',
    );
    if (confirm != true || !mounted) return;
    setState(() => _savingAction = 'booking:$id');
    try {
      final result = await _api(
        'PATCH',
        '/booked-appointments/${Uri.encodeComponent(id)}/status',
        body: {'status': next},
      );
      final saved = _obj(result['appointment']);
      if (_txt(saved['id']) != id || _txt(saved['status']) != next) {
        throw const FormatException('Backend did not confirm the booking change.');
      }
      _toast(next == 'COMPLETED' ? 'Appointment completed.' : 'Appointment cancelled.');
    } catch (e) {
      if (e is _ApiError && e.status == 401) {
        _accessLost(_friendly(e));
      } else {
        _toast(_friendly(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _savingAction = null);
      if (mounted && _authorized) await _loadBookings();
    }
  }

  Widget _bookingCard(Map<String, dynamic> b) {
    final status = _txt(b['status']).toUpperCase();
    final at = _bookingStart(b);
    final canComplete = status == 'BOOKED' && at != null &&
        !at.isAfter(DateTime.now());
    final id = _txt(b['id']);
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: _A.ice,
              child: Icon(Icons.person_outline, color: _A.blue),
            ),
            const SizedBox(width: 11),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _txt(b['patient_name']).isEmpty ? 'Patient' : _txt(b['patient_name']),
                  style: const TextStyle(color: _A.ink, fontSize: 14, fontWeight: FontWeight.w800),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text('${_prettyClock(_txt(b['start']))} – ${_prettyClock(_txt(b['end']))} IST',
                    style: const TextStyle(color: _A.teal, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            )),
            _statusBadge(status),
          ]),
          const SizedBox(height: 10),
          const Divider(height: 1, color: _A.border),
          const SizedBox(height: 9),
          Wrap(spacing: 12, runSpacing: 6, children: [
            _smallInfo(Icons.calendar_today_outlined, _txt(b['appointment_date'])),
            _smallInfo(Icons.schedule_outlined, 'Asia/Kolkata'),
            if (_txt(b['email_status']).isNotEmpty)
              _smallInfo(Icons.mail_outline, 'Email: ${_txt(b['email_status'])}'),
          ]),
          if (status == 'BOOKED') ...[
            const SizedBox(height: 11),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (canComplete)
                FilledButton.icon(
                  onPressed: _saving ? null : () => _changeBooking(b, 'COMPLETED'),
                  icon: const Icon(Icons.task_alt, size: 17),
                  label: const Text('Complete'),
                  style: FilledButton.styleFrom(backgroundColor: _A.green),
                ),
              OutlinedButton.icon(
                onPressed: _saving ? null : () => _changeBooking(b, 'CANCELLED'),
                icon: const Icon(Icons.event_busy_outlined, size: 17),
                label: const Text('Cancel'),
                style: OutlinedButton.styleFrom(foregroundColor: _A.red),
              ),
              if (_savingAction == 'booking:$id')
                const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _bookingsView() {
    final rows = _visibleBookings;
    final bookedCount = rows.where((b) => _txt(b['status']) == 'BOOKED').length;
    final completedCount = rows.where((b) => _txt(b['status']) == 'COMPLETED').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionTitle('Patient Bookings', 'Capacity-based appointments • Backend v10'),
      const SizedBox(height: 11),
      _notice('Bookings are loaded for one selected date (Asia/Kolkata), not all future days.'),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _loadingBookings ? null : _chooseBookingDay,
        icon: const Icon(Icons.date_range_outlined),
        label: Text(_dayLabel(_bookingDay)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _A.green,
          backgroundColor: Colors.white,
          side: const BorderSide(color: _A.border),
          minimumSize: const Size.fromHeight(46),
        ),
      ),
      const SizedBox(height: 12),
      Wrap(spacing: 9, runSpacing: 9, children: [
        _miniCount('Booked', _bookingError == null && !_loadingBookings ? bookedCount : null, Icons.event_available_outlined, _A.green),
        _miniCount('Completed', _bookingError == null && !_loadingBookings ? completedCount : null, Icons.task_alt_outlined, _A.blue),
        _miniCount('All statuses', _bookingError == null && !_loadingBookings ? rows.length : null, Icons.calendar_view_day_outlined, _A.purple),
      ]),
      const SizedBox(height: 13),
      if (_profileId.isNotEmpty)
        _notice('Showing only bookings for the selected care profile.'),
      if (_bookingError != null) _errorPanel(_bookingError!, _loadBookings),
      if (_loadingBookings)
        _spinner()
      else if (_bookingError == null && rows.isEmpty)
        _empty('No bookings for this date', 'Choose another date to check confirmed, cancelled or completed bookings.')
      else if (_bookingError == null)
          for (final booking in rows) Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _bookingCard(booking),
          ),
    ]);
  }

  // ============================================================
  // V10: WEEKLY CAPACITY SCHEDULE
  // ============================================================

  List<int> _days(Map<String, dynamic> w) {
    if (w['days'] is! List) return [];
    final result = (w['days'] as List).map(_integer).whereType<int>().toList();
    result.sort();
    return result;
  }

  String? _validateSchedule(List<Map<String, dynamic>> windows) {
    if (windows.length > 20) return 'Maximum 20 weekly windows are allowed.';
    final ids = <String>{};
    for (final w in windows) {
      final id = _txt(w['id']);
      final start = _txt(w['start']);
      final end = _txt(w['end']);
      final capacity = _integer(w['capacity']);
      final days = _days(w);
      if (id.isEmpty || !ids.add(id)) return 'Every window needs a unique ID.';
      if (start.compareTo(end) >= 0) return 'End time must be after start time.';
      if (capacity == null || capacity < 1 || capacity > 500) {
        return 'Capacity must be between 1 and 500.';
      }
      if (days.isEmpty || days.toSet().length != days.length ||
          days.any((d) => d < 0 || d > 6)) {
        return 'Select valid, unique weekdays.';
      }
    }
    for (var i = 0; i < windows.length; i++) {
      for (var j = i + 1; j < windows.length; j++) {
        final a = windows[i];
        final b = windows[j];
        if (_days(a).toSet().intersection(_days(b).toSet()).isNotEmpty &&
            _txt(a['start']).compareTo(_txt(b['end'])) < 0 &&
            _txt(b['start']).compareTo(_txt(a['end'])) < 0) {
          return 'Weekly windows cannot overlap on the same weekday.';
        }
      }
    }
    return null;
  }

  Future<void> _editWindow([Map<String, dynamic>? original]) async {
    if (_scheduleVersion == null || _saving || _loadingSchedule) return;
    if (original == null && _schedule.length >= 20) {
      _toast('The backend allows at most 20 weekly windows.', error: true);
      return;
    }
    final startDefault = const TimeOfDay(hour: 10, minute: 0);
    final endDefault = const TimeOfDay(hour: 11, minute: 0);
    var start = _parseClock(_txt(original?['start']), startDefault);
    var end = _parseClock(_txt(original?['end']), endDefault);
    final chosen = original == null ? <int>{0, 1, 2, 3, 4} : _days(original).toSet();
    final capacity = TextEditingController(text: '${_integer(original?['capacity']) ?? 5}');
    String? error;
    final edited = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: _A.bg,
      builder: (sheet) => StatefulBuilder(builder: (context, redraw) {
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 6, 18, MediaQuery.viewInsetsOf(context).bottom + 20),
          child: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(original == null ? 'Add Weekly Window' : 'Edit Weekly Window',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _A.ink)),
              const SizedBox(height: 6),
              const Text('Times and weekdays use India Standard Time (IST).',
                  style: TextStyle(fontSize: 12, color: _A.muted)),
              const SizedBox(height: 17),
              const Text('Repeat on', style: TextStyle(fontWeight: FontWeight.w700, color: _A.ink)),
              const SizedBox(height: 7),
              Wrap(spacing: 7, runSpacing: 7, children: [
                for (var d = 0; d < 7; d++)
                  FilterChip(
                    label: Text(_weekdayNames[d]),
                    selected: chosen.contains(d),
                    selectedColor: _A.mint,
                    onSelected: (yes) => redraw(() {
                      yes ? chosen.add(d) : chosen.remove(d);
                      error = null;
                    }),
                  ),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule, size: 17),
                  label: Text('From ${_hhmm(start)}'),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: start);
                    if (t != null) redraw(() { start = t; error = null; });
                  },
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  icon: const Icon(Icons.schedule, size: 17),
                  label: Text('To ${_hhmm(end)}'),
                  onPressed: () async {
                    final t = await showTimePicker(context: context, initialTime: end);
                    if (t != null) redraw(() { end = t; error = null; });
                  },
                )),
              ]),
              const SizedBox(height: 13),
              TextField(
                controller: capacity,
                keyboardType: TextInputType.number,
                maxLength: 3,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Capacity per window per day (1–500)',
                  counterText: '', filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(),
                ),
              ),
              if (error != null) Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text(error!, style: const TextStyle(color: _A.red, fontSize: 12)),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  final n = int.tryParse(capacity.text.trim());
                  if (chosen.isEmpty) {
                    redraw(() => error = 'Choose at least one weekday.');
                  } else if (_hhmm(start).compareTo(_hhmm(end)) >= 0) {
                    redraw(() => error = 'End time must be later than start time.');
                  } else if (n == null || n < 1 || n > 500) {
                    redraw(() => error = 'Capacity must be 1 to 500.');
                  } else {
                    Navigator.pop(sheet, <String, dynamic>{
                      'id': _txt(original?['id']).isEmpty ? _newUuid() : _txt(original?['id']),
                      'start': _hhmm(start),
                      'end': _hhmm(end),
                      'capacity': n,
                      'days': chosen.toList()..sort(),
                    });
                  }
                },
                icon: const Icon(Icons.check),
                label: const Text('Use This Window'),
                style: FilledButton.styleFrom(backgroundColor: _A.green, minimumSize: const Size.fromHeight(48)),
              ),
            ],
          )),
        );
      }),
    );
    capacity.dispose();
    if (!mounted || edited == null) return;
    final next = [
      for (final w in _schedule)
        if (_txt(w['id']) == _txt(edited['id'])) edited else w,
      if (original == null) edited,
    ];
    final issue = _validateSchedule(next);
    if (issue != null) {
      _toast(issue, error: true);
      return;
    }
    setState(() {
      _schedule = next;
      _scheduleDirty = true;
      _scheduleError = null;
    });
  }

  Future<void> _removeWindow(Map<String, dynamic> window) async {
    final confirmed = await _confirm(
      'Remove weekly window?',
      'This removes it from your unsaved draft. Press Save Schedule to apply the change. The backend may reject removal if future bookings depend on it.',
      action: 'Remove From Draft',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _schedule = _schedule.where((w) => _txt(w['id']) != _txt(window['id'])).toList();
      _scheduleDirty = true;
    });
  }

  Future<void> _saveSchedule() async {
    if (!_authorized || _saving || !_scheduleDirty || _scheduleVersion == null) return;
    final issue = _validateSchedule(_schedule);
    if (issue != null) {
      _toast(issue, error: true);
      return;
    }
    setState(() => _savingAction = 'schedule');
    try {
      final result = await _api(
        'PUT',
        '/appointment-schedule',
        body: {
          'version': _scheduleVersion,
          'windows': [
            for (final w in _schedule) {
              'id': _txt(w['id']),
              'start': _txt(w['start']),
              'end': _txt(w['end']),
              'capacity': _integer(w['capacity']),
              'days': _days(w),
            },
          ],
        },
      );
      final version = _integer(result['version']);
      if (version == null || result['windows'] is! List) {
        throw const FormatException('Backend did not confirm the saved schedule.');
      }
      if (!mounted) return;
      setState(() {
        _scheduleVersion = version;
        _schedule = _list(result['windows']);
        _scheduleDirty = false;
        _scheduleError = null;
      });
      _toast('Weekly appointment schedule saved.');
    } catch (e) {
      if (e is _ApiError && e.status == 401) {
        _accessLost(_friendly(e));
      } else {
        _toast(_friendly(e), error: true);
        if (mounted) setState(() => _scheduleError = _friendly(e));
      }
    } finally {
      if (mounted) setState(() => _savingAction = null);
    }
  }

  Widget _windowCard(Map<String, dynamic> window) {
    final days = _days(window);
    return _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const CircleAvatar(
          backgroundColor: _A.mint,
          child: Icon(Icons.access_time, color: _A.green),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${_prettyClock(_txt(window['start']))} – ${_prettyClock(_txt(window['end']))}',
              style: const TextStyle(color: _A.ink, fontWeight: FontWeight.w800, fontSize: 14)),
          Text('Capacity: ${_integer(window['capacity']) ?? '—'} per day',
              style: const TextStyle(color: _A.muted, fontSize: 11)),
        ])),
        IconButton(
          onPressed: _saving ? null : () => _editWindow(window),
          tooltip: 'Edit window',
          icon: const Icon(Icons.edit_outlined, color: _A.green),
        ),
        IconButton(
          onPressed: _saving ? null : () => _removeWindow(window),
          tooltip: 'Remove window from draft',
          icon: const Icon(Icons.delete_outline, color: _A.red),
        ),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 5, runSpacing: 5, children: [
        for (final d in days)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(color: _A.mint, borderRadius: BorderRadius.circular(18)),
            child: Text(_weekdayNames[d], style: const TextStyle(fontSize: 10, color: _A.green, fontWeight: FontWeight.w700)),
          ),
      ]),
    ]));
  }

  Widget _scheduleView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionTitle('Weekly Schedule', 'Repeatable appointment windows • Asia/Kolkata'),
      const SizedBox(height: 11),
      _notice('Each window has its own weekdays, start/end times and per-day capacity. These are not one-time slots. Save to publish all changes.'),
      const SizedBox(height: 12),
      if (_scheduleDirty)
        _notice('Unsaved changes. The backend schedule has not been updated yet.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: _saving || _loadingSchedule || _scheduleVersion == null || _schedule.length >= 20
              ? null : () => _editWindow(),
          icon: const Icon(Icons.add), label: const Text('Add Window'),
          style: FilledButton.styleFrom(backgroundColor: _A.green),
        ),
        FilledButton.icon(
          onPressed: _saving || !_scheduleDirty ? null : _saveSchedule,
          icon: const Icon(Icons.save_outlined),
          label: Text(_savingAction == 'schedule' ? 'Saving...' : 'Save Schedule'),
          style: FilledButton.styleFrom(backgroundColor: _A.blue),
        ),
        OutlinedButton.icon(
          onPressed: _saving || _loadingSchedule ? null : () => _refresh(),
          icon: const Icon(Icons.refresh), label: const Text('Reload'),
        ),
      ]),
      const SizedBox(height: 12),
      Text(
        _scheduleVersion == null ? 'Schedule version unavailable' :
        '${_schedule.length} of 20 windows • Version $_scheduleVersion',
        style: const TextStyle(color: _A.muted, fontSize: 11),
      ),
      const SizedBox(height: 12),
      if (_scheduleError != null) _errorPanel(_scheduleError!, () => _loadSchedule(discardDraft: !_scheduleDirty)),
      if (_loadingSchedule)
        _spinner()
      else if (_scheduleError == null && _schedule.isEmpty)
        _empty('No weekly schedule', 'Add a repeatable window, choose days and capacity, then save.')
      else
        for (final w in _schedule) Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: _windowCard(w),
        ),
    ]);
  }

  // ============================================================
  // LEGACY CONSULTATION REQUESTS
  // ============================================================

  String _visitStatus(Map<String, dynamic> v) => _txt(v['status']).toUpperCase();
  DateTime? _visitTime(Map<String, dynamic> v) =>
      _localTime(v['confirmed_at']) ?? _localTime(v['requested_at']);

  List<Map<String, dynamic>> get _visibleVisits {
    final term = _search.text.trim().toLowerCase();
    final now = DateTime.now();
    final rows = _visits.where((v) {
      if (_profileId.isNotEmpty && _txt(v['profile_id']) != _profileId) return false;
      final status = _visitStatus(v);
      if (_statusFilter != 'ALL' && _statusFilter != status) return false;
      final at = _visitTime(v);
      if (_visitDay != null && (at == null || !_sameDay(at, _visitDay!))) return false;
      if (_visitDay == null) {
        if (_visitView == 'requests' && status != 'REQUESTED') return false;
        if (_visitView == 'upcoming' &&
            (status != 'CONFIRMED' || at == null || !at.isAfter(now))) return false;
        if (_visitView == 'today' && (at == null || !_sameDay(at, now))) return false;
        if (_visitView == 'past' && (at == null || !at.isBefore(now))) return false;
      }
      return term.isEmpty || [v['patient_name'], v['concern'], v['notes'], status]
          .any((x) => _txt(x).toLowerCase().contains(term));
    }).toList();
    rows.sort((a, b) {
      final first = _visitTime(a);
      final second = _visitTime(b);
      if (first == null) return second == null ? 0 : 1;
      if (second == null) return -1;
      final compare = first.compareTo(second);
      return _visitView == 'requests' || _visitView == 'upcoming' ||
          _visitView == 'today' || _visitDay != null ? compare : -compare;
    });
    return rows;
  }

  Future<void> _chooseVisitDay() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _visitDay ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Filter consultation requests by date',
    );
    if (!mounted || selected == null) return;
    setState(() {
      _visitDay = selected;
      _visitView = 'all';
    });
  }

  Future<void> _changeVisit(Map<String, dynamic> visit, String next,
      {_TimeChoice? chosen}) async {
    if (!_authorized || _saving) return;
    final id = _txt(visit['id']);
    final version = _integer(visit['version']);
    if (id.isEmpty || version == null || version < 1) {
      _toast('Consultation version unavailable. Refresh first.', error: true);
      await _loadVisits();
      return;
    }
    setState(() => _savingAction = 'visit:$id');
    try {
      final body = <String, dynamic>{
        'status': next,
        'version': version,
        if (next == 'CONFIRMED' && chosen != null) ...{
          'confirmed_at': chosen.start.toUtc().toIso8601String(),
          'duration_minutes': chosen.duration,
        },
      };
      final result = await _api(
        'PATCH', '/consultation-visits/${Uri.encodeComponent(id)}/status', body: body,
      );
      final updated = _obj(result['consultation']);
      if (_txt(updated['id']) != id || _visitStatus(updated) != next) {
        throw const FormatException('Backend did not confirm the consultation change.');
      }
      _toast(next == 'CONFIRMED' ? 'Consultation time confirmed.' :
      'Consultation updated to ${next.toLowerCase()}.');
    } catch (e) {
      if (e is _ApiError && e.status == 401) {
        _accessLost(_friendly(e));
      } else {
        _toast(_friendly(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _savingAction = null);
      if (mounted && _authorized) await Future.wait([_loadVisits(), _loadSlots()]);
    }
  }

  Future<void> _confirmVisit(Map<String, dynamic> visit) async {
    if (_saving || !_authorized) return;
    final editing = _visitStatus(visit) == 'CONFIRMED';
    final choice = await showModalBottomSheet<_TimeChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: _A.bg,
      builder: (_) => _LegacyTimeSheet(
        heading: editing ? 'Reschedule Consultation' : 'Confirm Consultation',
        initial: _localTime(visit['confirmed_at']) ?? _localTime(visit['requested_at']),
        initialDuration: _integer(visit['duration_minutes']) ?? 30,
        requireSelection: !editing &&
            !(_localTime(visit['requested_at'])?.isAfter(DateTime.now()) ?? false),
        availableSlots: _slots,
      ),
    );
    if (!mounted || choice == null) return;
    await _changeVisit(visit, 'CONFIRMED', chosen: choice);
  }

  Future<void> _simpleVisitAction(Map<String, dynamic> visit, String next) async {
    if (_saving || !_authorized) return;
    final confirmed = await _confirm(
      '${next[0]}${next.substring(1).toLowerCase()} consultation?',
      switch (next) {
        'COMPLETED' => 'Mark completed only after the consultation has actually happened.',
        'CANCELLED' => 'Cancel this consultation? The current API cannot undo it.',
        _ => 'Decline this consultation? The current API cannot undo it.',
      },
      action: next == 'COMPLETED' ? 'Complete' : next == 'CANCELLED' ? 'Cancel' : 'Decline',
      destructive: next != 'COMPLETED',
    );
    if (confirmed != true || !mounted) return;
    await _changeVisit(visit, next);
  }

  Widget _visitCard(Map<String, dynamic> v) {
    final status = _visitStatus(v);
    final confirmed = _localTime(v['confirmed_at']);
    final requested = _localTime(v['requested_at']);
    final completeAllowed = status == 'CONFIRMED' && confirmed != null &&
        !confirmed.isAfter(DateTime.now());
    return _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const CircleAvatar(backgroundColor: _A.ice,
            child: Icon(Icons.medical_services_outlined, color: _A.blue)),
        const SizedBox(width: 9),
        Expanded(child: Text(_txt(v['patient_name']).isEmpty
            ? 'Patient consultation' : _txt(v['patient_name']),
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: _A.ink, fontWeight: FontWeight.w800, fontSize: 13))),
        _statusBadge(status),
      ]),
      const SizedBox(height: 8),
      Text(_txt(v['concern']).isEmpty ? 'Concern not specified' : _txt(v['concern']),
          style: const TextStyle(color: _A.ink, fontSize: 12)),
      const SizedBox(height: 8),
      _smallInfo(Icons.schedule_outlined, 'Requested: ${_dateTimeLabel(requested)}'),
      if (confirmed != null) ...[
        const SizedBox(height: 5),
        _smallInfo(Icons.event_available_outlined,
            'Confirmed: ${_dateTimeLabel(confirmed)} • ${_integer(v['duration_minutes']) ?? 30} min'),
      ],
      const SizedBox(height: 11),
      Wrap(spacing: 7, runSpacing: 6, children: [
        OutlinedButton.icon(
          onPressed: () => _visitDetails(v),
          icon: const Icon(Icons.visibility_outlined, size: 16),
          label: const Text('Details'),
        ),
        if (status == 'REQUESTED') ...[
          FilledButton(
            onPressed: _saving ? null : () => _confirmVisit(v),
            style: FilledButton.styleFrom(backgroundColor: _A.green),
            child: const Text('Confirm Time'),
          ),
          OutlinedButton(
            onPressed: _saving ? null : () => _simpleVisitAction(v, 'DECLINED'),
            child: const Text('Decline'),
          ),
          TextButton(
            onPressed: _saving ? null : () => _simpleVisitAction(v, 'CANCELLED'),
            child: const Text('Cancel'),
          ),
        ],
        if (status == 'CONFIRMED') ...[
          OutlinedButton(
            onPressed: _saving ? null : () => _confirmVisit(v),
            child: const Text('Reschedule'),
          ),
          if (completeAllowed)
            FilledButton(
              onPressed: _saving ? null : () => _simpleVisitAction(v, 'COMPLETED'),
              style: FilledButton.styleFrom(backgroundColor: _A.green),
              child: const Text('Complete'),
            ),
          TextButton(
            onPressed: _saving ? null : () => _simpleVisitAction(v, 'CANCELLED'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: _saving ? null : () => _simpleVisitAction(v, 'DECLINED'),
            child: const Text('Decline'),
          ),
        ],
      ]),
    ]));
  }

  void _visitDetails(Map<String, dynamic> v) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .78),
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(19), children: [
          const Text('Consultation Details', style: TextStyle(fontSize: 19,
              color: _A.ink, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          _detail('Patient', v['patient_name']),
          _detail('Status', v['status']),
          _detail('Concern', v['concern']),
          _detail('Notes', v['notes']),
          _detail('Requested time', _dateTimeLabel(_localTime(v['requested_at']))),
          if (_localTime(v['confirmed_at']) != null)
            _detail('Confirmed time', _dateTimeLabel(_localTime(v['confirmed_at']))),
          if (v['duration_minutes'] != null)
            _detail('Duration', '${v['duration_minutes']} minutes'),
          _detail('Record version', v['version']),
          const Divider(color: _A.border),
          const Text('Legacy consultation requests and v10 capacity bookings are different records. Confirming a consultation does not create a capacity booking or video link.',
              style: TextStyle(fontSize: 12, color: _A.muted, height: 1.5)),
        ]),
      ),
    );
  }

  Widget _requestsView() {
    final visible = _visibleVisits;
    final requests = _visits.where((v) => _visitStatus(v) == 'REQUESTED').length;
    final confirmed = _visits.where((v) => _visitStatus(v) == 'CONFIRMED').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionTitle('Consultation Requests', 'Legacy consultation workflow • latest 100 records'),
      const SizedBox(height: 11),
      _notice('These patient consultation requests are separate from v10 Bookings. Confirming a request requires choosing a time and checks overlapping consultations.'),
      const SizedBox(height: 12),
      Wrap(spacing: 9, runSpacing: 9, children: [
        _miniCount('Requests', _visitsError == null && !_loadingVisits ? requests : null,
            Icons.pending_actions_outlined, _A.amber),
        _miniCount('Confirmed', _visitsError == null && !_loadingVisits ? confirmed : null,
            Icons.event_available_outlined, _A.blue),
      ]),
      const SizedBox(height: 12),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final e in const [
          ('requests', 'Requests'), ('upcoming', 'Upcoming'),
          ('today', 'Today'), ('past', 'Past'), ('all', 'All'),
        ])
          Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(
            selected: _visitDay == null && _visitView == e.$1,
            label: Text(e.$2),
            selectedColor: _A.mint,
            onSelected: (_) => setState(() {
              _visitView = e.$1;
              _visitDay = null;
              _statusFilter = 'ALL';
            }),
          )),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 16, color: _A.blue),
          label: Text(_visitDay == null ? 'Date' : _dayLabel(_visitDay!)),
          onPressed: _chooseVisitDay,
        ),
        if (_visitDay != null)
          IconButton(onPressed: () => setState(() => _visitDay = null),
              icon: const Icon(Icons.close, color: _A.red)),
      ])),
      const SizedBox(height: 10),
      TextField(
        controller: _search,
        decoration: InputDecoration(
          hintText: 'Search patient, concern or notes',
          prefixIcon: const Icon(Icons.search, color: _A.green),
          suffixIcon: _search.text.isEmpty ? null : IconButton(
              onPressed: _search.clear, icon: const Icon(Icons.close)),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 9),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final s in const ['ALL', 'REQUESTED', 'CONFIRMED', 'COMPLETED', 'DECLINED', 'CANCELLED'])
          Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
            label: Text(s == 'ALL' ? 'All statuses' : s),
            selected: _statusFilter == s,
            selectedColor: _A.mint,
            onSelected: (_) => setState(() => _statusFilter = s),
          )),
      ])),
      const SizedBox(height: 10),
      Text('Showing ${visible.length} of ${_visits.length} loaded visits',
          style: const TextStyle(color: _A.muted, fontSize: 11)),
      const SizedBox(height: 12),
      if (_visitsError != null) _errorPanel(_visitsError!, _loadVisits),
      if (_loadingVisits)
        _spinner()
      else if (_visitsError == null && visible.isEmpty)
        _empty('No matching consultations', 'Choose another filter or date.')
      else if (_visitsError == null)
          for (final v in visible) Padding(padding: const EdgeInsets.only(bottom: 9), child: _visitCard(v)),
    ]);
  }

  // ============================================================
  // LEGACY ONE-TIME AVAILABILITY SLOTS
  // ============================================================

  Future<void> _addSlot() async {
    if (_saving || !_authorized) return;
    final choice = await showModalBottomSheet<_TimeChoice>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: _A.bg,
      builder: (_) => const _LegacyTimeSheet(heading: 'Add Single Slot', requireSelection: true),
    );
    if (!mounted || choice == null) return;
    setState(() => _savingAction = 'add-slot');
    try {
      final response = await _api('POST', '/appointment-slots', body: {
        'starts_at': choice.start.toUtc().toIso8601String(),
        'duration_minutes': choice.duration,
      });
      if (_obj(response['slot']).isEmpty) {
        throw const FormatException('Backend did not confirm the availability slot.');
      }
      _toast('One-time availability added. This is not a booking.');
    } catch (e) {
      if (e is _ApiError && e.status == 401) {
        _accessLost(_friendly(e));
      } else {
        _toast(_friendly(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _savingAction = null);
      if (mounted && _authorized) await _loadSlots();
    }
  }

  Future<void> _deleteSlot(Map<String, dynamic> slot) async {
    if (_saving || !_authorized) return;
    final id = _txt(slot['id']);
    if (id.isEmpty) return;
    final ok = await _confirm(
      'Remove one-time slot?',
      'Only this one-time available slot will be removed. The backend prevents removal when it conflicts with a confirmed consultation.',
      action: 'Remove Slot',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _savingAction = 'slot:$id');
    try {
      await _api('DELETE', '/appointment-slots/${Uri.encodeComponent(id)}');
      _toast('Availability slot removed.');
    } catch (e) {
      if (e is _ApiError && e.status == 401) {
        _accessLost(_friendly(e));
      } else {
        _toast(_friendly(e), error: true);
      }
    } finally {
      if (mounted) setState(() => _savingAction = null);
      if (mounted && _authorized) await _loadSlots();
    }
  }

  Widget _slotsView() {
    final ordered = [..._slots]..sort((a, b) {
      final aa = _localTime(a['starts_at']);
      final bb = _localTime(b['starts_at']);
      if (aa == null) return bb == null ? 0 : 1;
      if (bb == null) return -1;
      return aa.compareTo(bb);
    });
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _sectionTitle('Single Slots', 'Legacy one-time consultation availability'),
      const SizedBox(height: 11),
      _notice('These are individual available times for the legacy consultation flow. They do not create capacity bookings. Weekly windows are managed in Weekly Schedule.'),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: _saving ? null : _addSlot,
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Add One-Time Slot'),
        style: FilledButton.styleFrom(backgroundColor: _A.green, minimumSize: const Size.fromHeight(44)),
      ),
      const SizedBox(height: 13),
      Text('${ordered.length} future available slots loaded (max 200)',
          style: const TextStyle(color: _A.muted, fontSize: 11)),
      const SizedBox(height: 10),
      if (_slotsError != null) _errorPanel(_slotsError!, _loadSlots),
      if (_loadingSlots)
        _spinner()
      else if (_slotsError == null && ordered.isEmpty)
        _empty('No available single slots', 'Add one-time availability for consultation requests.')
      else if (_slotsError == null)
          for (final s in ordered) Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: _panel(Row(children: [
              const CircleAvatar(backgroundColor: _A.ice, child: Icon(Icons.schedule, color: _A.blue)),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_dateTimeLabel(_localTime(s['starts_at'])),
                    style: const TextStyle(color: _A.ink, fontWeight: FontWeight.w800, fontSize: 12)),
                const SizedBox(height: 4),
                Text('${_integer(s['duration_minutes']) ?? '—'} minutes • Available',
                    style: const TextStyle(color: _A.green, fontSize: 11)),
              ])),
              IconButton(
                tooltip: 'Remove one-time slot',
                onPressed: _saving ? null : () => _deleteSlot(s),
                icon: const Icon(Icons.delete_outline, color: _A.red),
              ),
            ])),
          ),
    ]);
  }

  // ============================================================
  // SHARED UI
  // ============================================================

  Color _statusColor(String status) => switch (status) {
    'BOOKED' || 'CONFIRMED' => _A.blue,
    'REQUESTED' => _A.amber,
    'COMPLETED' => _A.green,
    'CANCELLED' || 'DECLINED' => _A.red,
    _ => _A.muted,
  };

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: color.withAlpha(23), borderRadius: BorderRadius.circular(22)),
      child: Text(status.isEmpty ? 'UNKNOWN' : status,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }

  Widget _smallInfo(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: _A.teal),
      const SizedBox(width: 5),
      Text(text, style: const TextStyle(color: _A.muted, fontSize: 11)),
    ],
  );

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _A.border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  Widget _notice(String message) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _A.mint,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _A.border),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline, color: _A.teal, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(message,
          style: const TextStyle(color: _A.ink, fontSize: 11, height: 1.45))),
    ]),
  );

  Widget _errorPanel(String message, VoidCallback retry) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: _panel(Row(children: [
      const Icon(Icons.error_outline, color: _A.red),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(color: _A.red, fontSize: 12))),
      IconButton(onPressed: retry, icon: const Icon(Icons.refresh)),
    ])),
  );

  Widget _empty(String title, String subtitle) => _panel(Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
    child: Column(children: [
      const Icon(Icons.event_note_outlined, color: _A.blue, size: 37),
      const SizedBox(height: 9),
      Text(title, textAlign: TextAlign.center,
          style: const TextStyle(color: _A.ink, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(subtitle, textAlign: TextAlign.center,
          style: const TextStyle(color: _A.muted, fontSize: 12, height: 1.4)),
    ]),
  ));

  Widget _spinner() => const Padding(
    padding: EdgeInsets.all(31),
    child: Center(child: CircularProgressIndicator(color: _A.green)),
  );

  Widget _miniCount(String label, int? value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _A.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 7),
          Text('${value?.toString() ?? '—'} $label',
              style: const TextStyle(color: _A.ink, fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
      );

  Widget _sectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(color: _A.ink, fontSize: 17, fontWeight: FontWeight.w900)),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: _A.muted, fontSize: 11)),
    ],
  );

  Widget _detail(String label, dynamic value) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: _A.muted, fontSize: 11)),
      const SizedBox(height: 3),
      Text(_txt(value).isEmpty ? 'Not provided' : _txt(value),
          style: const TextStyle(color: _A.ink, fontWeight: FontWeight.w700, fontSize: 12)),
    ]),
  );

  Widget _hero() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF166B6E), Color(0xFF2A9884), Color(0xFF6AB7A7)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(children: [
      Container(
        width: 54, height: 54,
        decoration: BoxDecoration(color: const Color(0x44FFFFFF), borderRadius: BorderRadius.circular(17)),
        child: const Icon(Icons.calendar_month_outlined, color: Colors.white, size: 29),
      ),
      const SizedBox(width: 13),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Appointments', style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
        SizedBox(height: 5),
        Text('Bookings • Weekly schedule • Consultations',
            style: TextStyle(color: Colors.white, fontSize: 11, height: 1.4)),
      ])),
    ]),
  );

  Widget _tabs() => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: [
      for (final info in const [
        ('bookings', 'Bookings', Icons.event_available_outlined),
        ('schedule', 'Weekly Schedule', Icons.date_range_outlined),
        ('requests', 'Consultation Requests', Icons.medical_services_outlined),
        ('slots', 'Single Slots', Icons.schedule_outlined),
      ])
        Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(info.$3, size: 16, color: _tab == info.$1 ? Colors.white : _A.green),
            const SizedBox(width: 6),
            Text(info.$2),
          ]),
          selected: _tab == info.$1,
          selectedColor: _A.green,
          backgroundColor: Colors.white,
          side: BorderSide(color: _tab == info.$1 ? _A.green : _A.border),
          labelStyle: TextStyle(
            color: _tab == info.$1 ? Colors.white : _A.ink,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
          onSelected: (_) => setState(() => _tab = info.$1),
        )),
    ]),
  );

  Widget _blocked() => Center(child: Padding(
    padding: const EdgeInsets.all(25),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.lock_person_outlined, size: 48, color: _A.blue),
      const SizedBox(height: 12),
      const Text('Approved Doctor Required',
          style: TextStyle(fontSize: 18, color: _A.ink, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(_authError ?? 'Sign in using an approved, active doctor account.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _A.muted, height: 1.5)),
      const SizedBox(height: 14),
      FilledButton.icon(
        onPressed: _verify,
        icon: const Icon(Icons.refresh), label: const Text('Retry'),
        style: FilledButton.styleFrom(backgroundColor: _A.green),
      ),
    ]),
  ));

  void _back() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _A.bg,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _A.ink,
      leading: IconButton(onPressed: _back, icon: const Icon(Icons.arrow_back_rounded)),
      title: const Text('Appointments',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      actions: [
        IconButton(
          tooltip: 'Refresh current section',
          onPressed: !_authorized || _saving ? null : _refresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _verifying
        ? const Center(child: CircularProgressIndicator(color: _A.green))
        : !_authorized
        ? _blocked()
        : RefreshIndicator(
      color: _A.green,
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 15, 14, 32),
        children: [
          Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _hero(),
              const SizedBox(height: 14),
              _tabs(),
              const SizedBox(height: 15),
              if (_tab == 'bookings') _bookingsView(),
              if (_tab == 'schedule') _scheduleView(),
              if (_tab == 'requests') _requestsView(),
              if (_tab == 'slots') _slotsView(),
            ]),
          )),
        ],
      ),
    ),
  );
}

// Only used by the LEGACY consultation and single-slot workflows.
class _LegacyTimeSheet extends StatefulWidget {
  const _LegacyTimeSheet({
    required this.heading,
    this.initial,
    this.initialDuration = 30,
    this.availableSlots = const [],
    this.requireSelection = false,
  });

  final String heading;
  final DateTime? initial;
  final int initialDuration;
  final List<Map<String, dynamic>> availableSlots;
  final bool requireSelection;

  @override
  State<_LegacyTimeSheet> createState() => _LegacyTimeSheetState();
}

class _LegacyTimeSheetState extends State<_LegacyTimeSheet> {
  late DateTime _start;
  late TextEditingController _duration;
  String _selectedSlot = 'custom';
  bool _explicit = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final minimum = DateTime.now().add(const Duration(minutes: 10));
    _start = widget.initial != null && widget.initial!.isAfter(minimum)
        ? widget.initial!.toLocal()
        : minimum;
    final n = widget.initialDuration;
    _duration = TextEditingController(text: '${n >= 5 && n <= 240 ? n : 30}');
  }

  @override
  void dispose() {
    _duration.dispose();
    super.dispose();
  }

  Future<void> _chooseTime() async {
    final now = DateTime.now();
    final maximum = DateTime(now.year + 2, 12, 31);
    final chosenDate = await showDatePicker(
      context: context,
      initialDate: _start.isAfter(maximum) ? now : _start,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: maximum,
      helpText: 'Choose consultation date',
    );
    if (!mounted || chosenDate == null) return;
    final chosenClock = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_start),
      helpText: 'Choose consultation time',
    );
    if (!mounted || chosenClock == null) return;
    setState(() {
      _start = DateTime(chosenDate.year, chosenDate.month, chosenDate.day,
          chosenClock.hour, chosenClock.minute);
      _selectedSlot = 'custom';
      _explicit = true;
      _error = null;
    });
  }

  void _submit() {
    final n = int.tryParse(_duration.text.trim());
    if (widget.requireSelection && !_explicit) {
      setState(() => _error = 'Choose a date and time.');
    } else if (!_start.isAfter(DateTime.now())) {
      setState(() => _error = 'Choose a future date and time.');
    } else if (n == null || n < 5 || n > 240) {
      setState(() => _error = 'Duration must be between 5 and 240 minutes.');
    } else {
      Navigator.pop(context, _TimeChoice(_start, n));
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.availableSlots.where((s) {
      final when = _localTime(s['starts_at']);
      return when != null && when.isAfter(DateTime.now()) && _txt(s['id']).isNotEmpty;
    }).toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 8, 18, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.heading, style: const TextStyle(
              color: _A.ink, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Legacy consultation times use your device timezone. UTC is sent to the backend.',
              style: TextStyle(color: _A.muted, fontSize: 12)),
          const SizedBox(height: 15),
          if (available.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              key: ValueKey(_selectedSlot),
              initialValue: _selectedSlot,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Single available slot (optional)',
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(value: 'custom', child: Text('Custom date and time')),
                for (final s in available)
                  DropdownMenuItem<String>(
                    value: _txt(s['id']),
                    child: Text('${_dateTimeLabel(_localTime(s['starts_at']))} • '
                        '${_integer(s['duration_minutes']) ?? '—'} min',
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedSlot = value;
                  if (value != 'custom') {
                    final selected = available.firstWhere((s) => _txt(s['id']) == value);
                    _start = _localTime(selected['starts_at'])!;
                    _duration.text = '${_integer(selected['duration_minutes']) ?? 30}';
                    _explicit = true;
                  }
                  _error = null;
                });
              },
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _chooseTime,
            icon: const Icon(Icons.event),
            label: Text(_dateTimeLabel(_start), textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _duration,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 3,
            decoration: const InputDecoration(
              labelText: 'Duration in minutes (5–240)',
              counterText: '', filled: true, fillColor: Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(_error!, style: const TextStyle(color: _A.red, fontSize: 12)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check),
            label: Text(widget.heading),
            style: FilledButton.styleFrom(
              backgroundColor: _A.green,
              minimumSize: const Size.fromHeight(46),
            ),
          ),
        ],
      )),
    );
  }
}