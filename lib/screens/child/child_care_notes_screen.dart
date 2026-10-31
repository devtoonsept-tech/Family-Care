
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

// ============================================================
// FAMILYCARE+ - CHILD CARE & NOTES SCREEN
// ============================================================
//
// CURRENT BACKEND:
//
// GET    /api/v1/children/{childId}/care-notes
// POST   /api/v1/children/{childId}/care-notes
// PATCH  /api/v1/children/{childId}/care-notes/{noteId}
// DELETE /api/v1/children/{childId}/care-notes/{noteId}
//
// FEATURES:
//
// - Child-specific care diary
// - Daily care observations
// - Sleep tracking notes
// - Activities and playtime
// - Developmental milestones
// - Behaviour observations
// - Hygiene and routines
// - Health observations
// - Mood selection
// - Custom tags
// - Pin and unpin
// - Search and filters
// - Date-wise timeline
// - Four summary cards
// - Authenticated Flask CRUD
// - Dashboard callback synchronization
// - Network loading and error handling
//
// Backend currently supports:
// title, date, category, notes
//
// Mood, tags, pin and observation time are stored
// inside a versioned structured notes value.
//
// Backend notes limit: 2000 characters.
// ============================================================

// ============================================================
// COLORS
// ============================================================

class ChildCareNotesColors {
  static const navy = Color(0xFF143C60);
  static const text = Color(0xFF263F45);
  static const muted = Color(0xFF81918C);

  static const background = Color(0xFFF2F7FD);
  static const white = Colors.white;
  static const border = Color(0xFFE4E9E6);
  static const cream = Color(0xFFFFFDF8);

  static const green = Color(0xFF347D61);
  static const blue = Color(0xFF2381F4);
  static const purple = Color(0xFF8963C4);
  static const orange = Color(0xFFCB955C);
  static const pink = Color(0xFFD68788);
  static const red = Color(0xFFB7434E);

  static const lightGreen = Color(0xFFEAF5ED);
  static const lightBlue = Color(0xFFEAF5FF);
  static const lightOrange = Color(0xFFFFF4E7);
  static const lightPink = Color(0xFFFFF0F4);
}

// ============================================================
// NOTE CATEGORIES
// ============================================================

enum ChildCareNoteCategory {
  dailyCare,
  sleep,
  activity,
  milestone,
  behaviour,
  hygiene,
  healthObservation,
  other,
}

extension ChildCareNoteCategoryDetails
on ChildCareNoteCategory {
  String get label {
    switch (this) {
      case ChildCareNoteCategory.dailyCare:
        return 'Daily Care';
      case ChildCareNoteCategory.sleep:
        return 'Sleep';
      case ChildCareNoteCategory.activity:
        return 'Activities & Play';
      case ChildCareNoteCategory.milestone:
        return 'Milestones';
      case ChildCareNoteCategory.behaviour:
        return 'Behaviour';
      case ChildCareNoteCategory.hygiene:
        return 'Hygiene';
      case ChildCareNoteCategory.healthObservation:
        return 'Health Observation';
      case ChildCareNoteCategory.other:
        return 'Other';
    }
  }

  IconData get icon {
    switch (this) {
      case ChildCareNoteCategory.dailyCare:
        return Icons.favorite_border_rounded;
      case ChildCareNoteCategory.sleep:
        return Icons.bedtime_outlined;
      case ChildCareNoteCategory.activity:
        return Icons.sports_soccer_outlined;
      case ChildCareNoteCategory.milestone:
        return Icons.emoji_events_outlined;
      case ChildCareNoteCategory.behaviour:
        return Icons.psychology_outlined;
      case ChildCareNoteCategory.hygiene:
        return Icons.clean_hands_outlined;
      case ChildCareNoteCategory.healthObservation:
        return Icons.monitor_heart_outlined;
      case ChildCareNoteCategory.other:
        return Icons.notes_rounded;
    }
  }

  Color get color {
    switch (this) {
      case ChildCareNoteCategory.dailyCare:
        return ChildCareNotesColors.pink;
      case ChildCareNoteCategory.sleep:
        return ChildCareNotesColors.purple;
      case ChildCareNoteCategory.activity:
        return ChildCareNotesColors.orange;
      case ChildCareNoteCategory.milestone:
        return ChildCareNotesColors.green;
      case ChildCareNoteCategory.behaviour:
        return ChildCareNotesColors.blue;
      case ChildCareNoteCategory.hygiene:
        return ChildCareNotesColors.green;
      case ChildCareNoteCategory.healthObservation:
        return ChildCareNotesColors.red;
      case ChildCareNoteCategory.other:
        return ChildCareNotesColors.navy;
    }
  }
}

// ============================================================
// CHILD MOOD
// ============================================================

enum ChildCareMood {
  happy,
  calm,
  tired,
  fussy,
}

extension ChildCareMoodDetails on ChildCareMood {
  String get label {
    switch (this) {
      case ChildCareMood.happy:
        return 'Happy';
      case ChildCareMood.calm:
        return 'Calm';
      case ChildCareMood.tired:
        return 'Tired';
      case ChildCareMood.fussy:
        return 'Fussy';
    }
  }

  IconData get icon {
    switch (this) {
      case ChildCareMood.happy:
        return Icons.sentiment_very_satisfied_outlined;
      case ChildCareMood.calm:
        return Icons.sentiment_satisfied_outlined;
      case ChildCareMood.tired:
        return Icons.bedtime_outlined;
      case ChildCareMood.fussy:
        return Icons.sentiment_dissatisfied_outlined;
    }
  }
}

// ============================================================
// DATE FILTERS
// ============================================================

enum ChildCareNotesDateFilter {
  all,
  today,
  last7Days,
  last30Days,
  pinned,
}

extension ChildCareNotesDateFilterDetails
on ChildCareNotesDateFilter {
  String get label {
    switch (this) {
      case ChildCareNotesDateFilter.all:
        return 'All Time';
      case ChildCareNotesDateFilter.today:
        return 'Today';
      case ChildCareNotesDateFilter.last7Days:
        return 'Last 7 Days';
      case ChildCareNotesDateFilter.last30Days:
        return 'Last 30 Days';
      case ChildCareNotesDateFilter.pinned:
        return 'Pinned Notes';
    }
  }
}

// ============================================================
// DATE HELPERS
// ============================================================

class ChildCareNotesDate {
  static const months = [
    'Jan', 'Feb', 'Mar', 'Apr',
    'May', 'Jun', 'Jul', 'Aug',
    'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String format(DateTime date) {
    return '${date.day} '
        '${months[date.month - 1]} '
        '${date.year}';
  }

  static String api(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime parse(dynamic value) {
    final date = DateTime.tryParse(
      (value ?? '').toString(),
    );

    if (date == null) {
      throw const FormatException(
        'Invalid note date received from server.',
      );
    }

    return date;
  }

  static String heading(DateTime date) {
    final today = DateUtils.dateOnly(DateTime.now());
    final target = DateUtils.dateOnly(date);

    if (DateUtils.isSameDay(target, today)) {
      return 'Today';
    }

    if (DateUtils.isSameDay(
      target,
      today.subtract(const Duration(days: 1)),
    )) {
      return 'Yesterday';
    }

    return format(target);
  }

  static String time(
      BuildContext context,
      DateTime date,
      ) {
    return TimeOfDay.fromDateTime(date).format(context);
  }

  static String apiTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  static DateTime combine(
      DateTime date,
      String? rawTime,
      ) {
    final parts = (rawTime ?? '').split(':');

    if (parts.length == 2) {
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);

      if (hour != null &&
          minute != null &&
          hour >= 0 &&
          hour <= 23 &&
          minute >= 0 &&
          minute <= 59) {
        return DateTime(
          date.year,
          date.month,
          date.day,
          hour,
          minute,
        );
      }
    }

    return DateTime(
      date.year,
      date.month,
      date.day,
      12,
    );
  }
}

// ============================================================
// CHILD CARE NOTE MODEL
// ============================================================

class ChildCareNote {
  final String id;
  final String profileId;

  final String title;
  final String details;

  final ChildCareNoteCategory category;
  final ChildCareMood? mood;

  final DateTime occurredAt;
  final List<String> tags;

  final bool isPinned;

  // Kept for compatibility with existing dashboard.
  // Current API does not expose audit timestamps.
  final DateTime createdAt;
  final DateTime updatedAt;

  // True when exact note time is available.
  final bool hasRecordedTime;

  const ChildCareNote({
    required this.id,
    required this.profileId,
    required this.title,
    required this.details,
    required this.category,
    required this.occurredAt,
    this.mood,
    this.tags = const [],
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
    this.hasRecordedTime = true,
  });

  ChildCareNote copyWithPinned(bool pinned) {
    return ChildCareNote(
      id: id,
      profileId: profileId,
      title: title,
      details: details,
      category: category,
      mood: mood,
      occurredAt: occurredAt,
      tags: List<String>.from(tags),
      isPinned: pinned,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      hasRecordedTime: hasRecordedTime,
    );
  }
}

// ============================================================
// BACKEND DATA MAPPER
// ============================================================
//
// We use the existing notes field to preserve:
// - Full note details
// - Mood
// - Tags
// - Pin status
// - Exact observation time
//
// Format:
// FC_CARE_V1:{...}
//
// This is NOT encrypted data or a new backend schema.
// It is JSON encoded inside an existing text field.
//
// ============================================================

class ChildCareNotesMapper {
  static const String prefix = 'FC_CARE_V1:';

  static ChildCareNoteCategory categoryFromValue(
      dynamic raw,
      ) {
    final value = (raw ?? '')
        .toString()
        .trim()
        .toLowerCase();

    for (final category in ChildCareNoteCategory.values) {
      if (category.label.toLowerCase() == value ||
          category.name.toLowerCase() == value) {
        return category;
      }
    }

    return ChildCareNoteCategory.other;
  }

  static ChildCareMood? moodFromValue(dynamic raw) {
    final value = (raw ?? '')
        .toString()
        .trim()
        .toLowerCase();

    for (final mood in ChildCareMood.values) {
      if (mood.name.toLowerCase() == value ||
          mood.label.toLowerCase() == value) {
        return mood;
      }
    }

    return null;
  }

  static String encodeDetails(ChildCareNote note) {
    final encoded = jsonEncode({
      'd': note.details.trim(),
      't': note.hasRecordedTime
          ? ChildCareNotesDate.apiTime(note.occurredAt)
          : '',
      'm': note.mood?.name ?? '',
      'g': note.tags,
      'p': note.isPinned,
    });

    return '$prefix$encoded';
  }

  static Map<String, dynamic> toApi(
      ChildCareNote note,
      ) {
    if (note.title.trim().isEmpty ||
        note.title.trim().length > 160) {
      throw const ChildCareNotesApiException(
        'Note title must be between 1 and 160 characters.',
      );
    }

    if (note.details.trim().isEmpty) {
      throw const ChildCareNotesApiException(
        'Please enter note details.',
      );
    }

    final encoded = encodeDetails(note);

    if (encoded.length > 2000) {
      throw const ChildCareNotesApiException(
        'The note and its metadata exceed the '
            '2000-character backend limit. '
            'Shorten the details or remove some tags.',
      );
    }

    return {
      'title': note.title.trim(),
      'date': ChildCareNotesDate.api(note.occurredAt),
      'category': note.category.label,
      'notes': encoded,
    };
  }

  static ChildCareNote fromApi(
      Map<String, dynamic> json,
      String profileId,
      ) {
    final rawNotes = (json['notes'] ?? '').toString();

    String details = rawNotes;
    String recordedTime = '';

    ChildCareMood? mood;
    List<String> tags = [];
    bool pinned = false;

    if (rawNotes.startsWith(prefix)) {
      try {
        final parsed = jsonDecode(
          rawNotes.substring(prefix.length),
        );

        if (parsed is Map) {
          details = (parsed['d'] ?? '').toString();
          recordedTime = (parsed['t'] ?? '').toString();

          mood = moodFromValue(parsed['m']);
          pinned = parsed['p'] == true;

          final rawTags = parsed['g'];

          if (rawTags is List) {
            tags = rawTags
                .whereType<String>()
                .where((tag) => tag.trim().isNotEmpty)
                .toList();
          }
        }
      } catch (_) {
        // A malformed structured value is shown as
        // original text rather than discarded.
        details = rawNotes;
        recordedTime = '';
        mood = null;
        tags = [];
        pinned = false;
      }
    }

    final date = ChildCareNotesDate.parse(json['date']);

    final occurredAt = ChildCareNotesDate.combine(
      date,
      recordedTime,
    );

    // The backend record response has no createdAt or
    // updatedAt audit fields. These compatibility values
    // must not be displayed as actual server timestamps.
    return ChildCareNote(
      id: (json['id'] ?? '').toString(),
      profileId: profileId,
      title: (json['title'] ?? '').toString(),
      details: details,
      category: categoryFromValue(json['category']),
      mood: mood,
      occurredAt: occurredAt,
      tags: tags,
      isPinned: pinned,
      createdAt: occurredAt,
      updatedAt: occurredAt,
      hasRecordedTime: recordedTime.isNotEmpty,
    );
  }
}

// ============================================================
// API EXCEPTION
// ============================================================

class ChildCareNotesApiException implements Exception {
  final String message;
  final int statusCode;

  const ChildCareNotesApiException(
      this.message, {
        this.statusCode = 0,
      });

  @override
  String toString() => message;
}

// ============================================================
// FLASK API CLIENT
// ============================================================

class _ChildCareNotesApi {
  final String baseUrl;
  final String profileId;

  final http.Client _client = http.Client();

  _ChildCareNotesApi({
    required this.baseUrl,
    required this.profileId,
  });

  String get notesPath {
    return '/api/v1/children/'
        '${Uri.encodeComponent(profileId)}/care-notes';
  }

  String notePath(String noteId) {
    return '$notesPath/${Uri.encodeComponent(noteId)}';
  }

  void dispose() {
    _client.close();
  }

  Future<Map<String, String>> _headers() async {
    final token = await FamilyCareSession.accessToken();

    if (token == null || token.trim().isEmpty) {
      throw const ChildCareNotesApiException(
        'Your login session is missing. '
            'Please sign in again.',
        statusCode: 401,
      );
    }

    return {
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  Future<Map<String, dynamic>> request(
      String method,
      String path, {
        Map<String, dynamic>? payload,
      }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = await _headers();

    late http.Response response;

    switch (method) {
      case 'GET':
        response = await _client
            .get(
          uri,
          headers: headers,
        )
            .timeout(const Duration(seconds: 35));
        break;

      case 'POST':
        response = await _client
            .post(
          uri,
          headers: headers,
          body: jsonEncode(payload ?? {}),
        )
            .timeout(const Duration(seconds: 35));
        break;

      case 'PATCH':
        response = await _client
            .patch(
          uri,
          headers: headers,
          body: jsonEncode(payload ?? {}),
        )
            .timeout(const Duration(seconds: 35));
        break;

      case 'DELETE':
        response = await _client
            .delete(
          uri,
          headers: headers,
        )
            .timeout(const Duration(seconds: 35));
        break;

      default:
        throw const ChildCareNotesApiException(
          'Unsupported request method.',
        );
    }

    Map<String, dynamic> data = {};

    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(
          utf8.decode(response.bodyBytes),
        );

        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        } else {
          throw const FormatException();
        }
      } catch (_) {
        if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          throw const ChildCareNotesApiException(
            'Server returned an invalid response.',
          );
        }

        throw ChildCareNotesApiException(
          'Server error (${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      String message =
          'Request failed (${response.statusCode}).';

      final error = data['error'];

      if (error is Map &&
          error['message'] is String) {
        message = error['message'] as String;
      } else if (error is String && error.isNotEmpty) {
        message = error;
      }

      if (response.statusCode == 401) {
        message =
        'Session expired. Please log in again.';
      }

      if (response.statusCode == 403) {
        message =
        'You do not have access to this child profile.';
      }

      if (response.statusCode == 404) {
        message =
        'Care note not found. Refresh and try again.';
      }

      throw ChildCareNotesApiException(
        message,
        statusCode: response.statusCode,
      );
    }

    return data;
  }

  // ==========================================================
  // FETCH ALL CARE NOTES
  // ==========================================================

  Future<List<ChildCareNote>> getNotes() async {
    final result = <ChildCareNote>[];

    // Fetch paginated records.
    for (int page = 1; page <= 100; page++) {
      final data = await request(
        'GET',
        '$notesPath?page=$page&per_page=100',
      );

      final rawItems = data['items'];

      if (rawItems is! List) {
        throw const ChildCareNotesApiException(
          'Invalid care notes response from server.',
        );
      }

      for (final item in rawItems) {
        if (item is Map) {
          result.add(
            ChildCareNotesMapper.fromApi(
              Map<String, dynamic>.from(item),
              profileId,
            ),
          );
        }
      }

      final total = data['total'];

      if (rawItems.length < 100 ||
          (total is num &&
              result.length >= total.toInt())) {
        break;
      }
    }

    return result;
  }

  // ==========================================================
  // CREATE CARE NOTE
  // ==========================================================

  Future<void> createNote(ChildCareNote note) async {
    await request(
      'POST',
      notesPath,
      payload: ChildCareNotesMapper.toApi(note),
    );
  }

  // ==========================================================
  // UPDATE CARE NOTE
  // ==========================================================

  Future<void> updateNote(ChildCareNote note) async {
    await request(
      'PATCH',
      notePath(note.id),
      payload: ChildCareNotesMapper.toApi(note),
    );
  }

  // ==========================================================
  // DELETE CARE NOTE
  // ==========================================================

  Future<void> deleteNote(String noteId) async {
    await request(
      'DELETE',
      notePath(noteId),
    );
  }
}

// ============================================================
// MAIN SCREEN
// ============================================================

class ChildCareNotesScreen extends StatefulWidget {
  final String profileId;
  final String childName;
  final DateTime? childDateOfBirth;

  final String apiBaseUrl;

  // Preserved for dashboard compatibility.
  final List<ChildCareNote> initialNotes;

  final ValueChanged<List<ChildCareNote>>? onNotesChanged;

  const ChildCareNotesScreen({
    super.key,
    required this.profileId,
    this.childName = 'Child',
    this.childDateOfBirth,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.initialNotes = const [],
    this.onNotesChanged,
  });

  @override
  State<ChildCareNotesScreen> createState() =>
      _ChildCareNotesScreenState();
}

// ============================================================
// MAIN SCREEN STATE
// ============================================================

class _ChildCareNotesScreenState
    extends State<ChildCareNotesScreen> {
  final TextEditingController _searchController =
  TextEditingController();

  late _ChildCareNotesApi _api;

  List<ChildCareNote> _notes = [];

  ChildCareNoteCategory? _selectedCategory;

  ChildCareNotesDateFilter _dateFilter =
      ChildCareNotesDateFilter.all;

  bool _loading = true;
  bool _saving = false;

  String? _loadError;

  int _generation = 0;

  // ==========================================================
  // BACKEND URL
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
  // INITIALIZATION
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _api = _ChildCareNotesApi(
      baseUrl: _baseUrl,
      profileId: widget.profileId,
    );

    _searchController.addListener(
      _onSearchChanged,
    );

    _loadNotes();
  }

  // ==========================================================
  // CHILD SWITCHING
  // ==========================================================

  @override
  void didUpdateWidget(
      covariant ChildCareNotesScreen oldWidget,
      ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.profileId != widget.profileId ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      _generation++;

      _api.dispose();

      _api = _ChildCareNotesApi(
        baseUrl: _baseUrl,
        profileId: widget.profileId,
      );

      _notes = [];

      _selectedCategory = null;
      _dateFilter = ChildCareNotesDateFilter.all;

      _searchController.clear();

      _loading = true;
      _saving = false;
      _loadError = null;

      _loadNotes();
    }
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _generation++;

    _api.dispose();

    _searchController.removeListener(
      _onSearchChanged,
    );

    _searchController.dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ==========================================================
  // API ERROR TEXT
  // ==========================================================

  String _friendlyError(Object error) {
    if (error is ChildCareNotesApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'Server response timed out. Please retry.';
    }

    if (error is http.ClientException) {
      return 'Unable to connect to the FamilyCare+ server.';
    }

    if (error is FormatException) {
      return 'Invalid care note data received from server.';
    }

    return 'Something went wrong. Please retry.';
  }

  // ==========================================================
  // SNACKBAR
  // ==========================================================

  void _showMessage(
      String message, {
        bool error = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: error
              ? ChildCareNotesColors.red
              : ChildCareNotesColors.navy,
          duration: const Duration(seconds: 4),
          content: Text(message),
        ),
      );
  }

  // ==========================================================
  // FETCH NOTES
  // ==========================================================

  Future<bool> _loadNotes({
    bool showLoader = true,
  }) async {
    final generation = ++_generation;
    final profileId = widget.profileId;
    final api = _api;

    if (showLoader && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final records = await api.getNotes();

      if (!mounted ||
          generation != _generation ||
          profileId != widget.profileId) {
        return false;
      }

      setState(() {
        _notes = records;
        _loading = false;
        _loadError = null;
      });

      widget.onNotesChanged?.call(
        List<ChildCareNote>.unmodifiable(
          records,
        ),
      );

      return true;
    } catch (error) {
      if (!mounted ||
          generation != _generation ||
          profileId != widget.profileId) {
        return false;
      }

      setState(() {
        _loading = false;
        _loadError = _friendlyError(error);
      });

      return false;
    }
  }

  // ==========================================================
  // CREATE / EDIT NOTE
  // ==========================================================

  Future<void> _openNoteEditor({
    ChildCareNote? existing,
  }) async {
    if (_saving || _loading || _loadError != null) {
      return;
    }

    final profileId = widget.profileId;
    final api = _api;

    final edited =
    await showModalBottomSheet<ChildCareNote>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ChildCareNoteEditor(
          profileId: profileId,
          childName: widget.childName,
          childDateOfBirth: widget.childDateOfBirth,
          existing: existing,
        );
      },
    );

    if (!mounted ||
        edited == null ||
        widget.profileId != profileId) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      if (existing == null) {
        await api.createNote(edited);
      } else {
        await api.updateNote(edited);
      }

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      final refreshed = await _loadNotes(
        showLoader: false,
      );

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      if (refreshed) {
        _showMessage(
          existing == null
              ? 'Care note saved successfully.'
              : 'Care note updated successfully.',
        );
      } else {
        _showMessage(
          'Server accepted the note, but the list '
              'could not be refreshed. Please retry refresh.',
        );
      }
    } catch (error) {
      if (mounted && widget.profileId == profileId) {
        _showMessage(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted && widget.profileId == profileId) {
        setState(() => _saving = false);
      }
    }
  }

  // ==========================================================
  // PIN / UNPIN
  // ==========================================================

  Future<void> _togglePin(ChildCareNote note) async {
    if (_saving || _loading || _loadError != null) {
      return;
    }

    final profileId = widget.profileId;
    final api = _api;

    setState(() {
      _saving = true;
    });

    try {
      final updated = note.copyWithPinned(
        !note.isPinned,
      );

      await api.updateNote(updated);

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      final refreshed = await _loadNotes(
        showLoader: false,
      );

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      _showMessage(
        refreshed
            ? updated.isPinned
            ? 'Care note pinned successfully.'
            : 'Care note unpinned successfully.'
            : 'Pin update submitted. Refresh to verify.',
      );
    } catch (error) {
      if (mounted && widget.profileId == profileId) {
        _showMessage(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted && widget.profileId == profileId) {
        setState(() => _saving = false);
      }
    }
  }

  // ==========================================================
  // DELETE NOTE
  // ==========================================================

  Future<void> _deleteNote(ChildCareNote note) async {
    if (_saving || _loading || _loadError != null) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Care Note?'),
          content: Text(
            'Are you sure you want to remove '
                '"${note.title}" from the saved care diary?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: TextButton.styleFrom(
                foregroundColor:
                ChildCareNotesColors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) return;

    final profileId = widget.profileId;
    final api = _api;

    setState(() {
      _saving = true;
    });

    try {
      await api.deleteNote(note.id);

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      final refreshed = await _loadNotes(
        showLoader: false,
      );

      if (!mounted || widget.profileId != profileId) {
        return;
      }

      _showMessage(
        refreshed
            ? 'Care note deleted successfully.'
            : 'Deletion submitted. Refresh to verify.',
      );
    } catch (error) {
      if (mounted && widget.profileId == profileId) {
        _showMessage(
          _friendlyError(error),
          error: true,
        );
      }
    } finally {
      if (mounted && widget.profileId == profileId) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ==========================================================
  // SUMMARY COUNTS
  // ==========================================================

  int get _totalNotes => _notes.length;

  int get _todayNotes {
    final today = DateTime.now();

    return _notes.where((note) {
      return DateUtils.isSameDay(
        note.occurredAt,
        today,
      );
    }).length;
  }

  int get _pinnedNotes {
    return _notes.where(
          (note) => note.isPinned,
    ).length;
  }

  int get _milestoneNotes {
    return _notes.where(
          (note) =>
      note.category == ChildCareNoteCategory.milestone,
    ).length;
  }

  // ==========================================================
  // DATE FILTERING
  // ==========================================================

  bool _matchesDateFilter(ChildCareNote note) {
    final today =
    DateUtils.dateOnly(DateTime.now());

    final date =
    DateUtils.dateOnly(note.occurredAt);

    switch (_dateFilter) {
      case ChildCareNotesDateFilter.all:
        return true;

      case ChildCareNotesDateFilter.today:
        return DateUtils.isSameDay(date, today);

      case ChildCareNotesDateFilter.last7Days:
        return !date.isBefore(
          today.subtract(
            const Duration(days: 6),
          ),
        ) && !date.isAfter(today);

      case ChildCareNotesDateFilter.last30Days:
        return !date.isBefore(
          today.subtract(
            const Duration(days: 29),
          ),
        ) && !date.isAfter(today);

      case ChildCareNotesDateFilter.pinned:
        return note.isPinned;
    }
  }

  // ==========================================================
  // FILTERED NOTES
  // ==========================================================

  List<ChildCareNote> get _filteredNotes {
    final query = _searchController.text
        .trim()
        .toLowerCase();

    final result = _notes.where((note) {
      if (_selectedCategory != null &&
          note.category != _selectedCategory) {
        return false;
      }

      if (!_matchesDateFilter(note)) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final searchable = [
        note.title,
        note.details,
        note.category.label,
        note.mood?.label ?? '',
        ...note.tags,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList();

    result.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }

      final dateCompare =
      b.occurredAt.compareTo(a.occurredAt);

      if (dateCompare != 0) {
        return dateCompare;
      }

      return a.title.compareTo(b.title);
    });

    return result;
  }

  // ==========================================================
  // BUILD
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChildCareNotesColors.background,

      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: ChildCareNotesColors.navy,
        elevation: 0,

        title: const Text(
          'Child Care & Notes',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),

        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(
            Icons.arrow_back_rounded,
          ),
        ),

        actions: [
          IconButton(
            tooltip: 'Refresh Notes',
            onPressed: _loading || _saving
                ? null
                : () => _loadNotes(),
            icon: const Icon(
              Icons.refresh_rounded,
            ),
          ),
        ],
      ),

      floatingActionButton:
      _loading || _saving || _loadError != null
          ? null
          : FloatingActionButton.extended(
        onPressed: () => _openNoteEditor(),
        backgroundColor:
        ChildCareNotesColors.blue,
        foregroundColor: Colors.white,
        icon: const Icon(
          Icons.add_rounded,
        ),
        label: const Text('Add Note'),
      ),

      body: SafeArea(
        child: _loading
            ? const Center(
          child: CircularProgressIndicator(
            color: ChildCareNotesColors.blue,
          ),
        )
            : RefreshIndicator(
          onRefresh: () async {
            await _loadNotes();
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              16,
              20,
              16,
              105,
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1120,
                  ),
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      _buildBreadcrumb(),

                      const SizedBox(height: 18),

                      _buildHero(),

                      const SizedBox(height: 16),

                      _buildStorageNotice(),

                      const SizedBox(height: 20),

                      if (_loadError != null)
                        _buildErrorCard()
                      else ...[
                        _buildSummaryCards(),

                        const SizedBox(height: 22),

                        _buildQuickEntryCard(),

                        const SizedBox(height: 20),

                        _buildNotesSection(),
                      ],

                      const SizedBox(height: 22),

                      _buildPrivacyNotice(),

                      const SizedBox(height: 25),

                      const Center(
                        child: Text(
                          'FamilyCare+ • Your family. '
                              'Your care.',
                          style: TextStyle(
                            color: ChildCareNotesColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ),
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

  // ==========================================================
  // BREADCRUMB
  // ==========================================================

  Widget _buildBreadcrumb() {
    return const Row(
      children: [
        Text(
          'Child Care',
          style: TextStyle(
            color: ChildCareNotesColors.muted,
            fontSize: 12,
          ),
        ),
        SizedBox(width: 7),
        Icon(
          Icons.chevron_right_rounded,
          color: ChildCareNotesColors.muted,
          size: 17,
        ),
        SizedBox(width: 7),
        Text(
          'Child Care & Notes',
          style: TextStyle(
            color: ChildCareNotesColors.green,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // HERO
  // ==========================================================

  Widget _buildHero() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF4FF),
            Color(0xFFF7F0F7),
            Color(0xFFF0F8F3),
          ],
        ),
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                const Text(
                  'LITTLE MOMENTS. LOVING CARE.',
                  style: TextStyle(
                    color: ChildCareNotesColors.green,
                    fontSize: 10,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Care Diary & Notes',
                  style: TextStyle(
                    color: ChildCareNotesColors.navy,
                    fontFamily: 'serif',
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'Capture ${widget.childName}\'s '
                      'everyday care and special moments.',
                  style: const TextStyle(
                    color: ChildCareNotesColors.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          const CircleAvatar(
            radius: 34,
            backgroundColor: Color(0xFFF5E4E9),
            child: Icon(
              Icons.favorite_border_rounded,
              color: ChildCareNotesColors.pink,
              size: 36,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // STORAGE NOTICE
  // ==========================================================

  Widget _buildStorageNotice() {
    return _notice(
      'Care notes are loaded and saved through '
          'the FamilyCare+ backend. Mood, tags, pin '
          'status and observation time are stored '
          'inside the current notes field until '
          'dedicated database fields are available.',
      ChildCareNotesColors.lightBlue,
      ChildCareNotesColors.blue,
    );
  }

  // ==========================================================
  // ERROR CARD
  // ==========================================================

  Widget _buildErrorCard() {
    return _sectionCard(
      title: 'Unable to Load Care Notes',
      subtitle: 'Could not retrieve saved diary entries',
      icon: Icons.cloud_off_outlined,
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: ChildCareNotesColors.red,
            size: 38,
          ),

          const SizedBox(height: 12),

          Text(
            _loadError ?? 'Unknown error',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ChildCareNotesColors.red,
              fontSize: 12,
            ),
          ),

          const SizedBox(height: 16),

          OutlinedButton.icon(
            onPressed: () => _loadNotes(),
            icon: const Icon(
              Icons.refresh_rounded,
            ),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // SUMMARY
  // ==========================================================

  Widget _buildSummaryCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;

        const spacing = 11.0;

        final cardWidth = wide
            ? (constraints.maxWidth - spacing * 3) / 4
            : (constraints.maxWidth - spacing) / 2;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            _summaryCard(
              cardWidth,
              'Total Notes',
              _totalNotes,
              Icons.auto_stories_outlined,
              ChildCareNotesColors.blue,
            ),
            _summaryCard(
              cardWidth,
              'Today',
              _todayNotes,
              Icons.today_outlined,
              ChildCareNotesColors.green,
            ),
            _summaryCard(
              cardWidth,
              'Pinned Notes',
              _pinnedNotes,
              Icons.push_pin_outlined,
              ChildCareNotesColors.orange,
            ),
            _summaryCard(
              cardWidth,
              'Milestones',
              _milestoneNotes,
              Icons.emoji_events_outlined,
              ChildCareNotesColors.purple,
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCard(
      double width,
      String title,
      int count,
      IconData icon,
      Color color,
      ) {
    return Container(
      width: width,
      constraints: const BoxConstraints(
        minHeight: 125,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ChildCareNotesColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 21,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            '$count',
            style: const TextStyle(
              color: ChildCareNotesColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 26,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ChildCareNotesColors.muted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // QUICK ENTRY CARD
  // ==========================================================

  Widget _buildQuickEntryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: ChildCareNotesColors.cream,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: ChildCareNotesColors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ChildCareNotesColors.lightGreen,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              color: ChildCareNotesColors.green,
              size: 28,
            ),
          ),

          const SizedBox(width: 13),

          const Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'How was today?',
                  style: TextStyle(
                    color: ChildCareNotesColors.navy,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                SizedBox(height: 5),

                Text(
                  'Record a little moment, routine '
                      'or observation.',
                  style: TextStyle(
                    color: ChildCareNotesColors.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            tooltip: 'Write a Note',
            onPressed: _saving
                ? null
                : () => _openNoteEditor(),
            style: IconButton.styleFrom(
              backgroundColor:
              ChildCareNotesColors.blue,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(
              Icons.add_rounded,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // CARE DIARY SECTION
  // ==========================================================

  Widget _buildNotesSection() {
    final notes = _filteredNotes;

    return _sectionCard(
      title: 'Care Diary',
      subtitle: 'Everyday moments and observations',
      icon: Icons.menu_book_outlined,
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText:
              'Search notes, tags or categories...',
              hintStyle: const TextStyle(
                color: ChildCareNotesColors.muted,
                fontSize: 12,
              ),
              prefixIcon: const Icon(
                Icons.search_rounded,
                color: ChildCareNotesColors.green,
              ),
              suffixIcon:
              _searchController.text.isEmpty
                  ? null
                  : IconButton(
                tooltip: 'Clear search',
                onPressed:
                _searchController.clear,
                icon: const Icon(
                  Icons.close_rounded,
                ),
              ),
              filled: true,
              fillColor: ChildCareNotesColors.cream,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'Filter by date',
                  style: TextStyle(
                    color: ChildCareNotesColors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              DropdownButton<ChildCareNotesDateFilter>(
                value: _dateFilter,
                isDense: true,
                underline: const SizedBox.shrink(),
                items: ChildCareNotesDateFilter.values
                    .map((filter) {
                  return DropdownMenuItem(
                    value: filter,
                    child: Text(
                      filter.label,
                      style: const TextStyle(
                        fontSize: 11,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (filter) {
                  if (filter == null) return;

                  setState(() {
                    _dateFilter = filter;
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _categoryChip('All Notes', null),
                for (final category
                in ChildCareNoteCategory.values)
                  _categoryChip(
                    category.label,
                    category,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (notes.isEmpty)
            _buildEmptyState()
          else
            _buildTimeline(notes),
        ],
      ),
    );
  }

  // ==========================================================
  // CATEGORY FILTER CHIP
  // ==========================================================

  Widget _categoryChip(
      String label,
      ChildCareNoteCategory? category,
      ) {
    final selected = _selectedCategory == category;

    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        selectedColor: ChildCareNotesColors.blue,
        backgroundColor: const Color(0xFFF1F4F0),
        side: BorderSide.none,
        labelStyle: TextStyle(
          fontSize: 11,
          color: selected
              ? Colors.white
              : ChildCareNotesColors.text,
        ),
        onSelected: (_) {
          setState(() {
            _selectedCategory = category;
          });
        },
      ),
    );
  }

  // ==========================================================
  // NOTES TIMELINE
  // ==========================================================

  Widget _buildTimeline(List<ChildCareNote> notes) {
    final widgets = <Widget>[];

    DateTime? previousDate;
    bool? previousPinState;

    for (final note in notes) {
      final noteDay =
      DateUtils.dateOnly(note.occurredAt);

      final dateChanged = previousDate == null ||
          !DateUtils.isSameDay(
            previousDate,
            noteDay,
          );

      final pinStateChanged =
          previousPinState != note.isPinned;

      if (dateChanged || pinStateChanged) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              2, 8, 2, 12,
            ),
            child: Row(
              children: [
                Icon(
                  note.isPinned
                      ? Icons.push_pin_outlined
                      : Icons.calendar_today_outlined,
                  color: ChildCareNotesColors.green,
                  size: 16,
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    note.isPinned
                        ? 'Pinned • '
                        '${ChildCareNotesDate.heading(noteDay)}'
                        : ChildCareNotesDate.heading(
                      noteDay,
                    ),
                    style: const TextStyle(
                      color: ChildCareNotesColors.navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      widgets.add(
        _buildNoteCard(note),
      );

      widgets.add(
        const SizedBox(height: 12),
      );

      previousDate = noteDay;
      previousPinState = note.isPinned;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  // ==========================================================
  // SINGLE NOTE CARD
  // ==========================================================

  Widget _buildNoteCard(ChildCareNote note) {
    final category = note.category;

    return Container(
      key: ValueKey(note.id),
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: ChildCareNotesColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: note.isPinned
              ? ChildCareNotesColors.orange
              .withValues(alpha: 0.45)
              : ChildCareNotesColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: category.color.withValues(
                    alpha: 0.10,
                  ),
                  borderRadius:
                  BorderRadius.circular(11),
                ),
                child: Icon(
                  category.icon,
                  color: category.color,
                  size: 23,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      note.title,
                      style: const TextStyle(
                        color: ChildCareNotesColors.navy,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      category.label,
                      style: const TextStyle(
                        color: ChildCareNotesColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              PopupMenuButton<String>(
                tooltip: 'Note Actions',
                enabled: !_saving,
                onSelected: (action) {
                  if (action == 'edit') {
                    _openNoteEditor(existing: note);
                  } else if (action == 'pin') {
                    _togglePin(note);
                  } else if (action == 'delete') {
                    _deleteNote(note);
                  }
                },
                itemBuilder: (context) {
                  return [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit Note'),
                    ),
                    PopupMenuItem(
                      value: 'pin',
                      child: Text(
                        note.isPinned
                            ? 'Unpin Note'
                            : 'Pin Note',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete Note'),
                    ),
                  ];
                },
                icon: const Icon(
                  Icons.more_vert_rounded,
                  color: ChildCareNotesColors.muted,
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (note.hasRecordedTime)
                _noteTag(
                  ChildCareNotesDate.time(
                    context,
                    note.occurredAt,
                  ),
                  ChildCareNotesColors.blue,
                ),

              if (note.mood != null)
                _noteTag(
                  note.mood!.label,
                  ChildCareNotesColors.purple,
                ),

              if (note.isPinned)
                _noteTag(
                  'Pinned',
                  ChildCareNotesColors.orange,
                ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            note.details,
            style: const TextStyle(
              color: ChildCareNotesColors.text,
              fontSize: 12,
              height: 1.6,
            ),
          ),

          if (note.tags.isNotEmpty) ...[
            const SizedBox(height: 14),

            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: note.tags.map((tag) {
                return Container(
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                    ChildCareNotesColors.lightGreen,
                    borderRadius:
                    BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$tag',
                    style: const TextStyle(
                      color: ChildCareNotesColors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 15),

          const Divider(
            color: ChildCareNotesColors.border,
          ),

          Row(
            children: [
              IconButton(
                tooltip: note.isPinned
                    ? 'Unpin note'
                    : 'Pin note',
                onPressed: _saving
                    ? null
                    : () => _togglePin(note),
                icon: Icon(
                  note.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  color: note.isPinned
                      ? ChildCareNotesColors.orange
                      : ChildCareNotesColors.muted,
                ),
              ),

              const Spacer(),

              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => _openNoteEditor(
                  existing: note,
                ),
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 17,
                ),
                label: const Text('Edit'),
              ),

              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => _deleteNote(note),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                ),
                label: const Text('Delete'),
                style: TextButton.styleFrom(
                  foregroundColor:
                  ChildCareNotesColors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // NOTE TAG
  // ==========================================================

  Widget _noteTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ==========================================================
  // EMPTY STATE
  // ==========================================================

  Widget _buildEmptyState() {
    final hasFilters =
        _selectedCategory != null ||
            _dateFilter != ChildCareNotesDateFilter.all ||
            _searchController.text.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 19,
        vertical: 35,
      ),
      decoration: BoxDecoration(
        color: ChildCareNotesColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: ChildCareNotesColors.border,
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.menu_book_outlined,
            color: ChildCareNotesColors.green,
            size: 45,
          ),

          const SizedBox(height: 14),

          Text(
            hasFilters
                ? 'No matching care notes'
                : 'Your care diary starts here',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ChildCareNotesColors.navy,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 9),

          Text(
            hasFilters
                ? 'Try another category, date or search.'
                : 'Capture your child\'s daily '
                'activities, sleep, milestones '
                'and special moments.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ChildCareNotesColors.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 20),

          if (!hasFilters)
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () => _openNoteEditor(),
              icon: const Icon(
                Icons.add_rounded,
              ),
              label: const Text('Write First Note'),
              style: FilledButton.styleFrom(
                backgroundColor:
                ChildCareNotesColors.blue,
                foregroundColor: Colors.white,
              ),
            )
          else
            OutlinedButton(
              onPressed: () {
                _searchController.clear();

                setState(() {
                  _selectedCategory = null;
                  _dateFilter =
                      ChildCareNotesDateFilter.all;
                });
              },
              child: const Text('Clear Filters'),
            ),
        ],
      ),
    );
  }

  // ==========================================================
  // SECTION CARD
  // ==========================================================

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: ChildCareNotesColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ChildCareNotesColors.lightGreen,
                  borderRadius:
                  BorderRadius.circular(11),
                ),
                child: Icon(
                  icon,
                  color: ChildCareNotesColors.green,
                  size: 23,
                ),
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: ChildCareNotesColors.navy,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: ChildCareNotesColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 19),

          child,
        ],
      ),
    );
  }

  // ==========================================================
  // NOTICE
  // ==========================================================

  Widget _notice(
      String message,
      Color background,
      Color iconColor,
      ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: iconColor,
            size: 20,
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: ChildCareNotesColors.text,
                fontSize: 11,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // PRIVACY NOTICE
  // ==========================================================

  Widget _buildPrivacyNotice() {
    return _notice(
      'Care diary entries are parent-entered '
          'observations, not verified medical records '
          'or diagnoses. Do not use them to decide '
          'medication or treatment. For medical '
          'concerns, consult a qualified healthcare '
          'professional.',
      ChildCareNotesColors.lightGreen,
      ChildCareNotesColors.green,
    );
  }
}

// ============================================================
// ADD / EDIT NOTE FORM
// ============================================================

class _ChildCareNoteEditor extends StatefulWidget {
  final String profileId;
  final String childName;
  final DateTime? childDateOfBirth;
  final ChildCareNote? existing;

  const _ChildCareNoteEditor({
    required this.profileId,
    required this.childName,
    this.childDateOfBirth,
    this.existing,
  });

  @override
  State<_ChildCareNoteEditor> createState() =>
      _ChildCareNoteEditorState();
}

// ============================================================
// EDITOR STATE
// ============================================================

class _ChildCareNoteEditorState
    extends State<_ChildCareNoteEditor> {
  final GlobalKey<FormState> _formKey =
  GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _detailsController;
  late final TextEditingController _tagsController;

  late ChildCareNoteCategory _category;

  ChildCareMood? _mood;

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;

  late bool _isPinned;

  bool _submitted = false;

  // ==========================================================
  // INITIALIZATION
  // ==========================================================

  @override
  void initState() {
    super.initState();

    final existing = widget.existing;

    _titleController = TextEditingController(
      text: existing?.title ?? '',
    );

    _detailsController = TextEditingController(
      text: existing?.details ?? '',
    );

    _tagsController = TextEditingController(
      text: existing?.tags.join(', ') ?? '',
    );

    _category = existing?.category ??
        ChildCareNoteCategory.dailyCare;

    _mood = existing?.mood;

    final now = DateTime.now();

    final occurredAt = existing?.occurredAt ?? now;

    _selectedDate =
        DateUtils.dateOnly(occurredAt);

    _selectedTime =
    existing != null && existing.hasRecordedTime
        ? TimeOfDay.fromDateTime(occurredAt)
        : TimeOfDay.fromDateTime(now);

    _isPinned = existing?.isPinned ?? false;
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    _tagsController.dispose();

    super.dispose();
  }

  // ==========================================================
  // DATE PICKER
  // ==========================================================

  Future<void> _pickDate() async {
    final today =
    DateUtils.dateOnly(DateTime.now());

    final dob = widget.childDateOfBirth;

    final earliest = dob != null &&
        !DateUtils.dateOnly(dob).isAfter(today)
        ? DateUtils.dateOnly(dob)
        : DateTime(1900);

    var initial = _selectedDate;

    if (initial.isBefore(earliest)) {
      initial = earliest;
    }

    if (initial.isAfter(today)) {
      initial = today;
    }

    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: today,
      helpText: 'SELECT CARE NOTE DATE',
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _selectedDate = selected;
    });
  }

  // ==========================================================
  // TIME PICKER
  // ==========================================================

  Future<void> _pickTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      helpText: 'SELECT NOTE TIME',
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _selectedTime = selected;
    });
  }

  // ==========================================================
  // TITLE VALIDATION
  // ==========================================================

  String? _validateTitle(String? value) {
    final title = (value ?? '').trim();

    if (title.isEmpty) {
      return 'Note title is required.';
    }

    if (title.length < 3) {
      return 'Enter at least 3 characters.';
    }

    if (title.length > 160) {
      return 'Maximum 160 characters allowed.';
    }

    return null;
  }

  // ==========================================================
  // DETAILS VALIDATION
  // ==========================================================

  String? _validateDetails(String? value) {
    final details = (value ?? '').trim();

    if (details.isEmpty) {
      return 'Note details are required.';
    }

    if (details.length < 5) {
      return 'Enter at least 5 characters.';
    }

    return null;
  }

  // ==========================================================
  // PARSE TAGS
  // ==========================================================

  List<String> _parseTags(String raw) {
    final tags = <String>[];
    final seen = <String>{};

    for (final item in raw.split(',')) {
      final cleaned = item.trim().replaceFirst(
        RegExp(r'^#+'),
        '',
      );

      if (cleaned.isEmpty) continue;

      final key = cleaned.toLowerCase();

      if (seen.contains(key)) continue;

      seen.add(key);
      tags.add(cleaned);
    }

    return tags;
  }

  // ==========================================================
  // VALIDATE TAGS
  // ==========================================================

  String? _validateTags(String? value) {
    final tags = _parseTags(value ?? '');

    if (tags.length > 8) {
      return 'Maximum 8 tags allowed.';
    }

    if (tags.any((tag) => tag.length > 25)) {
      return 'Each tag must be 25 characters or less.';
    }

    return null;
  }

  // ==========================================================
  // SAVE NOTE
  // ==========================================================

  void _saveNote() {
    setState(() {
      _submitted = true;
    });

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final occurredAt = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final now = DateTime.now();

    if (occurredAt.isAfter(now)) {
      _showError(
        'Care note date and time cannot be in the future.',
      );
      return;
    }

    if (widget.childDateOfBirth != null &&
        DateUtils.dateOnly(occurredAt).isBefore(
          DateUtils.dateOnly(
            widget.childDateOfBirth!,
          ),
        )) {
      _showError(
        'Note date cannot be before the '
            'child\'s date of birth.',
      );
      return;
    }

    final note = ChildCareNote(
      id: widget.existing?.id ?? '',
      profileId: widget.profileId,
      title: _titleController.text.trim(),
      details: _detailsController.text.trim(),
      category: _category,
      mood: _mood,
      occurredAt: occurredAt,
      tags: _parseTags(
        _tagsController.text,
      ),
      isPinned: _isPinned,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      hasRecordedTime: true,
    );

    // Validate the actual encoded backend payload.
    try {
      ChildCareNotesMapper.toApi(note);
    } catch (error) {
      _showError(error.toString());
      return;
    }

    FocusScope.of(context).unfocus();

    Navigator.of(context).pop(note);
  }

  // ==========================================================
  // ERROR MESSAGE
  // ==========================================================

  void _showError(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ChildCareNotesColors.red,
        content: Text(message),
      ),
    );
  }

  // ==========================================================
  // EDITOR UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight:
          MediaQuery.sizeOf(context).height * 0.90,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(25),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              20, 23, 20, 30,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 650,
                ),
                child: Form(
                  key: _formKey,
                  autovalidateMode: _submitted
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      // --------------------------------------
                      // HEADING
                      // --------------------------------------

                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.existing == null
                                  ? 'Add Care Note'
                                  : 'Edit Care Note',
                              style: const TextStyle(
                                color:
                                ChildCareNotesColors.navy,
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),

                          IconButton(
                            tooltip: 'Close',
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(
                              Icons.close_rounded,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      Text(
                        'Care diary for ${widget.childName}',
                        style: const TextStyle(
                          color: ChildCareNotesColors.muted,
                          fontSize: 12,
                        ),
                      ),

                      const SizedBox(height: 23),

                      // --------------------------------------
                      // CATEGORY
                      // --------------------------------------

                      _buildCategoryField(),

                      const SizedBox(height: 18),

                      // --------------------------------------
                      // TITLE
                      // --------------------------------------

                      _buildTextField(
                        label: 'Note Title',
                        hint: 'Enter a short title',
                        controller: _titleController,
                        icon: Icons.title_rounded,
                        validator: _validateTitle,
                        maxLength: 120,
                      ),

                      const SizedBox(height: 18),

                      // --------------------------------------
                      // DATE AND TIME
                      // --------------------------------------

                      _buildDateTimeFields(),

                      const SizedBox(height: 20),

                      // --------------------------------------
                      // MOOD
                      // --------------------------------------

                      _buildMoodSelector(),

                      const SizedBox(height: 20),

                      // --------------------------------------
                      // DETAILS
                      // --------------------------------------

                      _buildTextField(
                        label: 'Care Note Details',
                        hint: 'Write about care, daily '
                            'routines or observations...',
                        controller: _detailsController,
                        icon: Icons.edit_note_rounded,
                        validator: _validateDetails,
                        maxLength: 1900,
                        maxLines: 6,
                      ),

                      const SizedBox(height: 18),

                      // --------------------------------------
                      // TAGS
                      // --------------------------------------

                      _buildTextField(
                        label: 'Tags (Optional)',
                        hint: 'e.g. bedtime, school, play',
                        controller: _tagsController,
                        icon: Icons.sell_outlined,
                        validator: _validateTags,
                        maxLength: 300,
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        'Separate tags with commas. '
                            'Maximum 8 tags.',
                        style: TextStyle(
                          color: ChildCareNotesColors.muted,
                          fontSize: 10,
                        ),
                      ),

                      const SizedBox(height: 19),

                      // --------------------------------------
                      // PIN
                      // --------------------------------------

                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Pin Important Note',
                          style: TextStyle(
                            color: ChildCareNotesColors.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: const Text(
                          'Pinned notes appear first.',
                          style: TextStyle(
                            color: ChildCareNotesColors.muted,
                            fontSize: 11,
                          ),
                        ),
                        secondary: const Icon(
                          Icons.push_pin_outlined,
                          color: ChildCareNotesColors.orange,
                        ),
                        value: _isPinned,
                        activeThumbColor:
                        ChildCareNotesColors.green,
                        onChanged: (value) {
                          setState(() {
                            _isPinned = value;
                          });
                        },
                      ),

                      const SizedBox(height: 16),

                      // --------------------------------------
                      // INFORMATION BOX
                      // --------------------------------------

                      _buildFormNotice(),

                      const SizedBox(height: 24),

                      // --------------------------------------
                      // SAVE
                      // --------------------------------------

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _saveNote,
                          icon: const Icon(
                            Icons.save_outlined,
                          ),
                          label: Text(
                            widget.existing == null
                                ? 'Save Care Note'
                                : 'Save Changes',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize:
                            const Size(0, 54),
                            backgroundColor:
                            ChildCareNotesColors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                              BorderRadius.circular(13),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          child: const Text('Cancel'),
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

  // ==========================================================
  // CATEGORY FIELD
  // ==========================================================

  Widget _buildCategoryField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Note Category'),

        const SizedBox(height: 9),

        DropdownButtonFormField<ChildCareNoteCategory>(
          initialValue: _category,
          isExpanded: true,
          decoration: _fieldDecoration(
            'Select note category',
            Icons.category_outlined,
          ),
          items: ChildCareNoteCategory.values.map(
                (category) {
              return DropdownMenuItem(
                value: category,
                child: Row(
                  children: [
                    Icon(
                      category.icon,
                      color: category.color,
                      size: 19,
                    ),

                    const SizedBox(width: 9),

                    Flexible(
                      child: Text(
                        category.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ).toList(),
          onChanged: (value) {
            if (value == null) return;

            setState(() {
              _category = value;
            });
          },
        ),
      ],
    );
  }

  // ==========================================================
  // DATE / TIME FIELDS
  // ==========================================================

  Widget _buildDateTimeFields() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 500;

        final dateField = _dateField();
        final timeField = _timeField();

        if (wide) {
          return Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Expanded(child: dateField),
              const SizedBox(width: 15),
              Expanded(child: timeField),
            ],
          );
        }

        return Column(
          children: [
            dateField,
            const SizedBox(height: 17),
            timeField,
          ],
        );
      },
    );
  }

  Widget _dateField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Note Date'),

        const SizedBox(height: 9),

        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(13),
          child: InputDecorator(
            decoration: _fieldDecoration(
              'Select date',
              Icons.calendar_month_outlined,
            ),
            child: Text(
              ChildCareNotesDate.format(
                _selectedDate,
              ),
              style: const TextStyle(
                color: ChildCareNotesColors.text,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _timeField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Note Time'),

        const SizedBox(height: 9),

        InkWell(
          onTap: _pickTime,
          borderRadius: BorderRadius.circular(13),
          child: InputDecorator(
            decoration: _fieldDecoration(
              'Select time',
              Icons.access_time_outlined,
            ),
            child: Text(
              _selectedTime.format(context),
              style: const TextStyle(
                color: ChildCareNotesColors.text,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // MOOD SELECTOR
  // ==========================================================

  Widget _buildMoodSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Child Mood (Optional)'),

        const SizedBox(height: 9),

        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ChildCareMood.values.map((mood) {
            final selected = _mood == mood;

            return ChoiceChip(
              avatar: Icon(
                mood.icon,
                color: selected
                    ? Colors.white
                    : ChildCareNotesColors.green,
                size: 19,
              ),
              label: Text(mood.label),
              selected: selected,
              showCheckmark: false,
              selectedColor: ChildCareNotesColors.green,
              backgroundColor:
              ChildCareNotesColors.lightGreen,
              side: BorderSide.none,
              labelStyle: TextStyle(
                fontSize: 11,
                color: selected
                    ? Colors.white
                    : ChildCareNotesColors.text,
              ),
              onSelected: (_) {
                setState(() {
                  _mood = selected ? null : mood;
                });
              },
            );
          }).toList(),
        ),

        const SizedBox(height: 8),

        const Text(
          'Mood is a personal observation, '
              'not a medical assessment.',
          style: TextStyle(
            color: ChildCareNotesColors.muted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // FORM NOTICE
  // ==========================================================

  Widget _buildFormNotice() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: ChildCareNotesColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        crossAxisAlignment:
        CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: ChildCareNotesColors.green,
            size: 20,
          ),

          SizedBox(width: 10),

          Expanded(
            child: Text(
              'Care notes are parent-entered diary '
                  'records. Saving sends the note to the '
                  'FamilyCare+ backend. Notes are not '
                  'verified medical records. The current '
                  'server has a 2000-character limit '
                  'for encoded note details.',
              style: TextStyle(
                color: ChildCareNotesColors.text,
                fontSize: 11,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // TEXT FIELD
  // ==========================================================

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLength = 120,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),

        const SizedBox(height: 9),

        TextFormField(
          controller: controller,
          validator: validator,
          maxLines: maxLines,
          textCapitalization:
          TextCapitalization.sentences,
          inputFormatters: [
            LengthLimitingTextInputFormatter(
              maxLength,
            ),
          ],
          decoration: _fieldDecoration(
            hint,
            icon,
          ),
        ),
      ],
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: ChildCareNotesColors.text,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  InputDecoration _fieldDecoration(
      String hint,
      IconData icon,
      ) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: ChildCareNotesColors.muted,
        fontSize: 12,
      ),
      prefixIcon: Icon(
        icon,
        color: ChildCareNotesColors.green,
        size: 21,
      ),
      filled: true,
      fillColor: ChildCareNotesColors.cream,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: ChildCareNotesColors.border,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: ChildCareNotesColors.green,
          width: 1.7,
        ),
      ),
      errorMaxLines: 2,
    );
  }
}
