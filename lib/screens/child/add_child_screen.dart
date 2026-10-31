
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

// ============================================================
// FAMILYCARE+ - ADD CHILD SCREEN
// ============================================================
//
// Flask API endpoints:
//
// POST /api/v1/patients/profiles
// GET  /api/v1/patients/profiles
// GET  /api/v1/children
// GET  /api/v1/children/{child_id}
//
// Features:
// - Add child
// - List registered children
// - Automatically calculate age
// - View child details
// - Parent profile linking
// - Guardian contact
// - Up to five emergency contacts
// - Doctor referral
// - Edit/Delete API placeholders
//
// ============================================================

class AddChildColors {
  static const Color navy = Color(0xFF143C60);
  static const Color text = Color(0xFF263F45);
  static const Color muted = Color(0xFF81918C);
  static const Color background = Color(0xFFF2F7FD);
  static const Color white = Colors.white;
  static const Color border = Color(0xFFE4E9E6);
  static const Color green = Color(0xFF347D61);
  static const Color blue = Color(0xFF2381F4);
  static const Color lightBlue = Color(0xFFEAF5FF);
  static const Color lightGreen = Color(0xFFEAF5ED);
  static const Color cream = Color(0xFFFFFDF8);
  static const Color error = Color(0xFFB7434E);
}

// ============================================================
// API EXCEPTION
// ============================================================

class AddChildApiException implements Exception {
  final int statusCode;
  final String code;
  final String message;

  const AddChildApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  @override
  String toString() => message;
}

// ============================================================
// PARENT PROFILE MODEL
// ============================================================

class _ParentProfile {
  final String id;
  final String name;
  final String module;
  final DateTime dateOfBirth;

  const _ParentProfile({
    required this.id,
    required this.name,
    required this.module,
    required this.dateOfBirth,
  });

  static _ParentProfile? fromJson(dynamic value) {
    if (value is! Map) return null;

    final id = value['id'];
    final name = value['full_name'];
    final module = value['module'];
    final dob = value['date_of_birth'];

    if (id is! String ||
        name is! String ||
        module is! String ||
        dob is! String) {
      return null;
    }

    if (module != 'adult' && module != 'women') {
      return null;
    }

    final parsedDate = DateTime.tryParse(dob);

    if (parsedDate == null) return null;

    return _ParentProfile(
      id: id,
      name: name,
      module: module,
      dateOfBirth: parsedDate,
    );
  }
}

// ============================================================
// CHILD PROFILE MODEL
// ============================================================

class _ChildProfile {
  final String id;
  final String fullName;
  final DateTime dateOfBirth;
  final Map<String, dynamic> age;
  final Map<String, dynamic> raw;

  const _ChildProfile({
    required this.id,
    required this.fullName,
    required this.dateOfBirth,
    required this.age,
    required this.raw,
  });

  static _ChildProfile? fromJson(dynamic value) {
    if (value is! Map) return null;

    final id = value['id'];
    final name = value['full_name'];
    final dob = value['date_of_birth'];

    if (id is! String ||
        name is! String ||
        dob is! String) {
      return null;
    }

    final parsedDob = DateTime.tryParse(dob);

    if (parsedDob == null) return null;

    final rawAge = value['age'];

    return _ChildProfile(
      id: id,
      fullName: name,
      dateOfBirth: parsedDob,
      age: rawAge is Map
          ? Map<String, dynamic>.from(rawAge)
          : <String, dynamic>{},
      raw: Map<String, dynamic>.from(value),
    );
  }

  // ==========================================================
  // AGE CALCULATION - CORRECTED
  // ==========================================================

  String get ageText {
    final serverYears = age['completed_years'];
    final serverMonths = age['remaining_months'];
    final serverDays = age['remaining_days'];

    // First preference: backend-calculated age.

    if (serverYears is num && serverMonths is num) {
      if (serverYears == 0 &&
          serverMonths == 0 &&
          serverDays is num) {
        return '${serverDays.toInt()} days';
      }

      if (serverYears == 0) {
        return '${serverMonths.toInt()} months';
      }

      return '${serverYears.toInt()} years, '
          '${serverMonths.toInt()} months';
    }

    // Second preference: backend display string.

    final display = age['display'];

    if (display is String && display.isNotEmpty) {
      return display;
    }

    // Fallback: calculate age from DOB.

    final today = DateTime.now();

    int calculatedYears =
        today.year - dateOfBirth.year;

    int calculatedMonths =
        today.month - dateOfBirth.month;

    if (today.day < dateOfBirth.day) {
      calculatedMonths--;
    }

    if (calculatedMonths < 0) {
      calculatedYears--;
      calculatedMonths += 12;
    }

    if (calculatedYears < 0) {
      return 'Age unavailable';
    }

    if (calculatedYears == 0 &&
        calculatedMonths == 0) {
      final start = DateTime(
        dateOfBirth.year,
        dateOfBirth.month,
        dateOfBirth.day,
      );

      final end = DateTime(
        today.year,
        today.month,
        today.day,
      );

      final days = end.difference(start).inDays;

      return '$days days';
    }

    if (calculatedYears == 0) {
      return '$calculatedMonths months';
    }

    return '$calculatedYears years, '
        '$calculatedMonths months';
  }
}

// ============================================================
// EMERGENCY CONTACT MODEL
// ============================================================

class _EmergencyContactInput {
  final TextEditingController nameController =
  TextEditingController();

  final TextEditingController mobileController =
  TextEditingController();

  final TextEditingController relationshipController =
  TextEditingController();

  Map<String, dynamic> toJson() {
    return {
      'name': nameController.text.trim(),
      'mobile_number':
      '+91${mobileController.text.trim()}',
      'relationship':
      relationshipController.text.trim(),
    };
  }

  void dispose() {
    nameController.dispose();
    mobileController.dispose();
    relationshipController.dispose();
  }
}

// ============================================================
// MAIN SCREEN
// ============================================================

class AddChildScreen extends StatefulWidget {
  final String apiBaseUrl;

  final ValueChanged<Map<String, dynamic>>?
  onChildCreated;

  const AddChildScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.onChildCreated,
  });

  @override
  State<AddChildScreen> createState() =>
      _AddChildScreenState();
}

// ============================================================
// STATE
// ============================================================

class _AddChildScreenState extends State<AddChildScreen> {
  GlobalKey<FormState> _formKey =
  GlobalKey<FormState>();

  final ScrollController _scrollController =
  ScrollController();

  final http.Client _httpClient = http.Client();

  // ----------------------------------------------------------
  // TEXT CONTROLLERS
  // ----------------------------------------------------------

  final TextEditingController _nameController =
  TextEditingController();

  final TextEditingController _guardianController =
  TextEditingController();

  final TextEditingController _referralController =
  TextEditingController();

  // ----------------------------------------------------------
  // CHILDREN AND PARENTS
  // ----------------------------------------------------------

  final List<_ChildProfile> _children = [];

  final List<_ParentProfile> _parentProfiles = [];

  final List<_EmergencyContactInput> _contacts = [];

  // ----------------------------------------------------------
  // SELECTED VALUES
  // ----------------------------------------------------------

  DateTime? _dateOfBirth;

  String? _selectedParentId;

  String? _childrenError;

  // ----------------------------------------------------------
  // STATE VARIABLES
  // ----------------------------------------------------------

  bool _loadingChildren = false;
  bool _loadingParents = false;
  bool _parentsLoadFailed = false;

  bool _isSaving = false;
  bool _submitted = false;
  bool _showDobError = false;
  bool _showForm = true;

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

    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5001';
    }

    return 'http://127.0.0.1:5001';
  }

  // ==========================================================
  // DATE HELPERS
  // ==========================================================

  DateTime get _today {
    final now = DateTime.now();

    return DateTime(
      now.year,
      now.month,
      now.day,
    );
  }

  DateTime get _earliestBirthDate {
    final today = _today;

    return DateTime(
      today.year - 13,
      today.month,
      today.day,
    ).add(const Duration(days: 1));
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  String _apiDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  // ==========================================================
  // FORM AGE CALCULATION
  // ==========================================================

  String _calculateFormAge(DateTime birthDate) {
    final today = _today;

    int calculatedYears =
        today.year - birthDate.year;

    int calculatedMonths =
        today.month - birthDate.month;

    if (today.day < birthDate.day) {
      calculatedMonths--;
    }

    if (calculatedMonths < 0) {
      calculatedYears--;
      calculatedMonths += 12;
    }

    if (calculatedYears == 0 &&
        calculatedMonths == 0) {
      return '${today.difference(birthDate).inDays} days';
    }

    if (calculatedYears == 0) {
      return '$calculatedMonths months';
    }

    return '$calculatedYears years, '
        '$calculatedMonths months';
  }

  // ==========================================================
  // INITIALIZATION
  // ==========================================================

  @override
  void initState() {
    super.initState();

    _loadChildren();
    _loadParentProfiles();
  }

  // ==========================================================
  // DISPOSE
  // ==========================================================

  @override
  void dispose() {
    _nameController.dispose();
    _guardianController.dispose();
    _referralController.dispose();

    for (final contact in _contacts) {
      contact.dispose();
    }

    _scrollController.dispose();
    _httpClient.close();

    super.dispose();
  }

  // ==========================================================
  // AUTHENTICATED API REQUEST
  // ==========================================================

  Future<Map<String, dynamic>> _apiRequest(
      String method,
      String endpoint, {
        Map<String, dynamic>? body,
      }) async {
    final token = await FamilyCareSession.accessToken();

    if (token == null || token.trim().isEmpty) {
      throw const AddChildApiException(
        statusCode: 401,
        code: 'not_authenticated',
        message: 'Please log in to continue.',
      );
    }

    final uri = Uri.parse('$_baseUrl$endpoint');

    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
    };

    late http.Response response;

    if (method == 'GET') {
      response = await _httpClient
          .get(
        uri,
        headers: headers,
      )
          .timeout(
        const Duration(seconds: 30),
      );
    } else if (method == 'POST') {
      response = await _httpClient
          .post(
        uri,
        headers: headers,
        body: jsonEncode(body ?? {}),
      )
          .timeout(
        const Duration(seconds: 30),
      );
    } else {
      throw const AddChildApiException(
        statusCode: 0,
        code: 'unsupported_method',
        message: 'Unsupported request method.',
      );
    }

    Map<String, dynamic> result;

    try {
      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (decoded is! Map) {
        throw const FormatException();
      }

      result = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const AddChildApiException(
        statusCode: 0,
        code: 'invalid_response',
        message: 'Invalid response from server.',
      );
    } on TypeError {
      throw const AddChildApiException(
        statusCode: 0,
        code: 'invalid_response',
        message: 'Invalid response from server.',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final errorData = result['error'];

      String code = 'request_failed';

      String message =
          'Request failed. Please try again.';

      if (errorData is Map) {
        if (errorData['code'] is String) {
          code = errorData['code'] as String;
        }

        if (errorData['message'] is String) {
          message = errorData['message'] as String;
        }
      }

      if (response.statusCode == 401) {
        message =
        'Your session has expired. Please log in again.';
      }

      throw AddChildApiException(
        statusCode: response.statusCode,
        code: code,
        message: message,
      );
    }

    return result;
  }

  // ==========================================================
  // ERROR HANDLING
  // ==========================================================

  String _errorText(Object error) {
    if (error is AddChildApiException) {
      return error.message;
    }

    if (error is TimeoutException) {
      return 'Server response timed out. Please retry.';
    }

    if (error is http.ClientException) {
      return 'Could not connect to the server.';
    }

    if (error is PlatformException) {
      return 'Unable to read the login session.';
    }

    return 'Something went wrong. Please try again.';
  }

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
              ? AddChildColors.error
              : AddChildColors.navy,
          content: Text(message),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  // ==========================================================
  // LOAD EXISTING CHILDREN
  // GET /api/v1/children
  // ==========================================================

  Future<bool> _loadChildren() async {
    if (_loadingChildren) return false;

    setState(() {
      _loadingChildren = true;
      _childrenError = null;
    });

    try {
      final loadedChildren = <_ChildProfile>[];

      int page = 1;

      while (page <= 100) {
        final response = await _apiRequest(
          'GET',
          '/api/v1/children?page=$page&per_page=100',
        );

        final rawItems = response['items'];

        if (rawItems is! List) {
          throw const AddChildApiException(
            statusCode: 0,
            code: 'invalid_children',
            message: 'Invalid child list from server.',
          );
        }

        for (final item in rawItems) {
          final child = _ChildProfile.fromJson(item);

          if (child != null) {
            loadedChildren.add(child);
          }
        }

        final total = response['total'];

        if (rawItems.isEmpty ||
            rawItems.length < 100 ||
            (total is num &&
                page * 100 >= total)) {
          break;
        }

        page++;
      }

      if (!mounted) return false;

      setState(() {
        _children
          ..clear()
          ..addAll(loadedChildren);
      });

      return true;
    } catch (error) {
      if (!mounted) return false;

      setState(() {
        _childrenError = _errorText(error);
      });

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _loadingChildren = false;
        });
      }
    }
  }

  // ==========================================================
  // LOAD PARENT PROFILES
  // ==========================================================

  Future<void> _loadParentProfiles() async {
    if (_loadingParents) return;

    setState(() {
      _loadingParents = true;
      _parentsLoadFailed = false;
    });

    try {
      final parents = <_ParentProfile>[];

      int page = 1;

      while (page <= 100) {
        final response = await _apiRequest(
          'GET',
          '/api/v1/patients/profiles'
              '?page=$page&per_page=100',
        );

        final rawItems = response['items'];

        if (rawItems is! List) {
          throw const FormatException();
        }

        for (final item in rawItems) {
          final parent = _ParentProfile.fromJson(item);

          if (parent != null) {
            parents.add(parent);
          }
        }

        final total = response['total'];

        if (rawItems.isEmpty ||
            rawItems.length < 100 ||
            (total is num &&
                page * 100 >= total)) {
          break;
        }

        page++;
      }

      if (!mounted) return;

      setState(() {
        _parentProfiles
          ..clear()
          ..addAll(parents);
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _parentsLoadFailed = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingParents = false;
        });
      }
    }
  }

  // ==========================================================
  // SELECT DATE OF BIRTH
  // ==========================================================

  Future<void> _selectDateOfBirth() async {
    if (_isSaving) return;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? _today,
      firstDate: _earliestBirthDate,
      lastDate: _today,
      helpText: 'SELECT CHILD DATE OF BIRTH',
      cancelText: 'CANCEL',
      confirmText: 'SELECT',
    );

    if (pickedDate == null || !mounted) {
      return;
    }

    setState(() {
      _dateOfBirth = pickedDate;
      _showDobError = false;

      for (final parent in _parentProfiles) {
        if (parent.id == _selectedParentId &&
            !parent.dateOfBirth.isBefore(pickedDate)) {
          _selectedParentId = null;
          break;
        }
      }
    });
  }

  // ==========================================================
  // FIELD VALIDATION
  // ==========================================================

  String? _validateName(String? value) {
    final name = (value ?? '').trim();

    if (name.isEmpty) {
      return 'Child name is required';
    }

    if (name.length > 120) {
      return 'Maximum 120 characters allowed';
    }

    return null;
  }

  String? _validateMobile(
      String? value, {
        bool isRequired = false,
      }) {
    final mobile = (value ?? '').trim();

    if (mobile.isEmpty && !isRequired) {
      return null;
    }

    if (!RegExp(r'^\d{10}$').hasMatch(mobile)) {
      return 'Enter a valid 10-digit mobile number';
    }

    return null;
  }

  String? _validateContactName(String? value) {
    final name = (value ?? '').trim();

    if (name.isEmpty) {
      return 'Contact name is required';
    }

    if (name.length > 120) {
      return 'Maximum 120 characters allowed';
    }

    return null;
  }

  String? _validateRelationship(String? value) {
    final relationship = (value ?? '').trim();

    if (relationship.isEmpty) {
      return 'Relationship is required';
    }

    if (relationship.length > 50) {
      return 'Maximum 50 characters allowed';
    }

    return null;
  }

  String? _validateReferral(String? value) {
    final referral = (value ?? '').trim();

    if (referral.isEmpty) {
      return null;
    }

    if (!RegExp(r'^[A-Za-z0-9]{1,160}$')
        .hasMatch(referral)) {
      return 'Use only letters and numbers';
    }

    return null;
  }

  // ==========================================================
  // EMERGENCY CONTACT ACTIONS
  // ==========================================================

  void _addEmergencyContact() {
    if (_isSaving || _contacts.length >= 5) {
      return;
    }

    setState(() {
      _contacts.add(_EmergencyContactInput());
    });
  }

  void _removeEmergencyContact(int index) {
    if (_isSaving ||
        index < 0 ||
        index >= _contacts.length) {
      return;
    }

    final removedContact = _contacts[index];

    setState(() {
      _contacts.removeAt(index);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      removedContact.dispose();
    });
  }

  // ==========================================================
  // RESET CHILD FORM
  // ==========================================================

  void _resetForm() {
    if (_isSaving) return;

    _clearFormValues();
  }

  void _clearFormValues() {
    final oldContacts =
    List<_EmergencyContactInput>.from(_contacts);

    _nameController.clear();
    _guardianController.clear();
    _referralController.clear();

    setState(() {
      _formKey = GlobalKey<FormState>();

      _dateOfBirth = null;
      _selectedParentId = null;

      _submitted = false;
      _showDobError = false;

      _contacts.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final contact in oldContacts) {
        contact.dispose();
      }
    });
  }

  // ==========================================================
  // SAVE CHILD PROFILE
  // POST /api/v1/patients/profiles
  // ==========================================================

  Future<void> _saveChild() async {
    if (_isSaving) return;

    setState(() {
      _submitted = true;
      _showDobError = _dateOfBirth == null;
    });

    final valid =
        _formKey.currentState?.validate() ?? false;

    if (!valid || _dateOfBirth == null) {
      _showMessage(
        'Please complete the required details.',
        error: true,
      );
      return;
    }

    final dob = _dateOfBirth!;

    if (dob.isAfter(_today) ||
        dob.isBefore(_earliestBirthDate)) {
      _showMessage(
        'Child age must be between 0 and 12 years.',
        error: true,
      );
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _isSaving = true;
    });

    try {
      final guardianMobile =
      _guardianController.text.trim();

      final referralId =
      _referralController.text.trim();

      // Backend-compatible payload.

      final payload = <String, dynamic>{
        'profile_type': 'member',
        'module': 'child',
        'full_name': _nameController.text.trim(),
        'date_of_birth': _apiDate(dob),
        'parent_profile_id': _selectedParentId,
        'guardian_contact': guardianMobile.isEmpty
            ? ''
            : '+91$guardianMobile',
        'emergency_contacts': _contacts
            .map(
              (contact) => contact.toJson(),
        )
            .toList(),
        'referral_id': referralId.isEmpty
            ? null
            : referralId,
      };

      final response = await _apiRequest(
        'POST',
        '/api/v1/patients/profiles',
        body: payload,
      );

      final rawProfile = response['profile'];

      if (rawProfile is! Map) {
        throw const AddChildApiException(
          statusCode: 0,
          code: 'invalid_profile',
          message:
          'The server did not return a valid profile. '
              'Refresh the child list before retrying.',
        );
      }

      final createdProfile =
      Map<String, dynamic>.from(rawProfile);

      if (!mounted) return;

      // Reset after successful creation.
      _clearFormValues();

      // Reload cards from Flask.
      final refreshed = await _loadChildren();

      if (!mounted) return;

      _showMessage(
        refreshed
            ? 'Child profile created successfully!'
            : 'Child saved. Refresh the list to see it.',
      );

      // Preserve the existing dashboard callback.
      try {
        widget.onChildCreated?.call(createdProfile);
      } catch (_) {
        // The server-side save has already succeeded.
      }

      if (!mounted) return;

      if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          0,
          duration: const Duration(
            milliseconds: 350,
          ),
          curve: Curves.easeOut,
        );
      }
    } catch (error) {
      _showMessage(
        _errorText(error),
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ==========================================================
  // EDIT / DELETE API PLACEHOLDERS
  // ==========================================================

  void _editChild(_ChildProfile child) {
    _showPendingAction(
      child: child,
      isDelete: false,
    );
  }

  void _deleteChild(_ChildProfile child) {
    _showPendingAction(
      child: child,
      isDelete: true,
    );
  }

  void _showPendingAction({
    required _ChildProfile child,
    required bool isDelete,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            isDelete ? 'Delete Child' : 'Edit Child',
          ),
          content: Text(
            '${child.fullName}\n\n'
                '${isDelete ? 'Deletion' : 'Editing'} '
                'will be available when the corresponding '
                'backend API is added.\n\n'
                'No child information has been changed.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // ==========================================================
  // VIEW CHILD DETAILS
  // GET /api/v1/children/{child_id}
  // ==========================================================

  Future<void> _viewChildDetails(
      _ChildProfile selectedChild,
      ) async {
    try {
      final response = await _apiRequest(
        'GET',
        '/api/v1/children/${selectedChild.id}',
      );

      if (!mounted) return;

      final rawChild = response['child'];

      if (rawChild is! Map) {
        throw const AddChildApiException(
          statusCode: 0,
          code: 'invalid_child',
          message: 'Unable to load child details.',
        );
      }

      final data =
      Map<String, dynamic>.from(rawChild);

      final child =
          _ChildProfile.fromJson(data) ?? selectedChild;

      final rawContacts = data['emergency_contacts'];

      final contacts = rawContacts is List
          ? rawContacts.whereType<Map>().toList()
          : <Map>[];

      final guardian =
      (data['guardian_contact'] ?? '').toString();

      String parentText = 'Not linked';

      final parentId = data['parent_profile_id'];

      if (parentId is String && parentId.isNotEmpty) {
        parentText = 'Linked parent profile';

        for (final parent in _parentProfiles) {
          if (parent.id == parentId) {
            parentText = parent.name;
            break;
          }
        }
      }

      final isDoctorLinked = data['doctor'] is Map;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        builder: (sheetContext) {
          return FractionallySizedBox(
            heightFactor: 0.75,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _avatar(56),

                      const SizedBox(width: 14),

                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            Text(
                              child.fullName,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                color: AddChildColors.navy,
                              ),
                            ),

                            const SizedBox(height: 5),

                            Text(
                              child.ageText,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AddChildColors.green,
                              ),
                            ),
                          ],
                        ),
                      ),

                      IconButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  _detailRow(
                    'Full Name',
                    child.fullName,
                  ),

                  _detailRow(
                    'Date of Birth',
                    _formatDate(child.dateOfBirth),
                  ),

                  _detailRow(
                    'Age',
                    child.ageText,
                  ),

                  _detailRow(
                    'Parent Profile',
                    parentText,
                  ),

                  _detailRow(
                    'Guardian Mobile',
                    guardian.isEmpty
                        ? 'Not provided'
                        : guardian,
                  ),

                  _detailRow(
                    'Doctor Connection',
                    isDoctorLinked
                        ? 'Connected'
                        : 'Not connected',
                  ),

                  const SizedBox(height: 14),

                  const Text(
                    'Emergency Contacts',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AddChildColors.navy,
                    ),
                  ),

                  const SizedBox(height: 12),

                  if (contacts.isEmpty)
                    const Text(
                      'No emergency contacts added.',
                      style: TextStyle(
                        color: AddChildColors.muted,
                        fontSize: 13,
                      ),
                    ),

                  for (final contact in contacts)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(
                        bottom: 10,
                      ),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: AddChildColors.cream,
                        borderRadius:
                        BorderRadius.circular(12),
                        border: Border.all(
                          color: AddChildColors.border,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${contact['name'] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AddChildColors.navy,
                            ),
                          ),

                          const SizedBox(height: 5),

                          Text(
                            '${contact['relationship'] ?? ''}',
                          ),

                          const SizedBox(height: 5),

                          Text(
                            '${contact['mobile_number'] ?? ''}',
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                      },
                      child: const Text('Close Details'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (error) {
      _showMessage(
        _errorText(error),
        error: true,
      );
    }
  }

  // ==========================================================
  // DETAILS ROW
  // ==========================================================

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AddChildColors.muted,
            ),
          ),

          const SizedBox(height: 5),

          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AddChildColors.text,
            ),
          ),

          const SizedBox(height: 8),

          const Divider(
            color: AddChildColors.border,
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // AVATAR
  // ==========================================================

  Widget _avatar(double size) {
    return Container(
      height: size,
      width: size,
      decoration: const BoxDecoration(
        color: AddChildColors.lightGreen,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.child_care_rounded,
        color: AddChildColors.green,
        size: size * 0.55,
      ),
    );
  }

  // ==========================================================
  // REUSABLE SECTION CARD
  // ==========================================================

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: AddChildColors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: AddChildColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AddChildColors.lightGreen,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: AddChildColors.green,
                  size: 23,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AddChildColors.navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AddChildColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          child,
        ],
      ),
    );
  }

  // ==========================================================
  // RESPONSIVE ROW
  // ==========================================================

  Widget _responsiveRow(
      Widget first,
      Widget second,
      ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return Row(
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Expanded(child: first),

              const SizedBox(width: 16),

              Expanded(child: second),
            ],
          );
        }

        return Column(
          children: [
            first,

            const SizedBox(height: 17),

            second,
          ],
        );
      },
    );
  }

  // ==========================================================
  // INPUT DECORATION
  // ==========================================================

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    String? prefix,
  }) {
    return InputDecoration(
      hintText: hint,

      prefixIcon: Icon(
        icon,
        color: AddChildColors.green,
        size: 21,
      ),

      prefixText: prefix,

      filled: true,
      fillColor: AddChildColors.cream,

      contentPadding: const EdgeInsets.symmetric(
        horizontal: 15,
        vertical: 17,
      ),

      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
      ),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: AddChildColors.border,
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: AddChildColors.green,
          width: 1.7,
        ),
      ),

      errorMaxLines: 2,
    );
  }

  // ==========================================================
  // REUSABLE TEXT FIELD
  // ==========================================================

  Widget _textField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    String? prefix,
    bool optional = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          optional ? '$label (Optional)' : label,
          style: const TextStyle(
            color: AddChildColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 9),

        TextFormField(
          controller: controller,
          enabled: !_isSaving,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
          textInputAction: TextInputAction.next,
          textCapitalization:
          keyboardType == TextInputType.text
              ? TextCapitalization.words
              : TextCapitalization.none,
          decoration: _fieldDecoration(
            hint: hint,
            icon: icon,
            prefix: prefix,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // MAIN UI
  // ==========================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isSaving,
      child: Scaffold(
        backgroundColor: AddChildColors.background,

        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AddChildColors.navy,
          elevation: 0,

          title: const Text(
            'Manage Children',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AddChildColors.navy,
            ),
          ),

          actions: [
            IconButton(
              tooltip: 'Refresh Children',
              onPressed: _loadingChildren
                  ? null
                  : () {
                _loadChildren();
              },
              icon: const Icon(
                Icons.refresh_rounded,
              ),
            ),
          ],
        ),

        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: 950,
              ),

              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 22,
                ),

                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),

                    const SizedBox(height: 22),

                    _buildChildrenSection(),

                    const SizedBox(height: 24),

                    _buildAddChildSection(),

                    const SizedBox(height: 28),

                    const Center(
                      child: Text(
                        'FamilyCare+ • Healthier Families. '
                            'Brighter Tomorrows.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: AddChildColors.muted,
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),
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
  // HEADER
  // ==========================================================

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(23),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFEAF4FF),
            Color(0xFFEFF7F0),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
      ),

      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'YOUR FAMILY. YOUR CARE.',
                  style: TextStyle(
                    color: AddChildColors.green,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                SizedBox(height: 12),

                Text(
                  'Little ones, big care',
                  style: TextStyle(
                    color: AddChildColors.navy,
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                SizedBox(height: 9),

                Text(
                  'Keep every child profile organized '
                      'in one secure place.',
                  style: TextStyle(
                    color: AddChildColors.muted,
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          _avatar(70),
        ],
      ),
    );
  }

  // ==========================================================
  // EXISTING CHILDREN SECTION
  // ==========================================================

  Widget _buildChildrenSection() {
    return _sectionCard(
      title: 'Your Children',
      subtitle: 'All registered child profiles',
      icon: Icons.family_restroom_rounded,

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: AddChildColors.lightBlue,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_children.length} Children',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AddChildColors.navy,
                  ),
                ),
              ),

              const Spacer(),

              TextButton.icon(
                onPressed: _loadingChildren
                    ? null
                    : () {
                  _loadChildren();
                },
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 17,
                ),
                label: const Text('Refresh'),
              ),
            ],
          ),

          const SizedBox(height: 17),

          if (_loadingChildren)
            const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 25,
              ),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_childrenError != null)
            _buildChildrenError()
          else if (_children.isEmpty)
              _buildEmptyChildren()
            else
              for (final child in _children) ...[
                _buildChildCard(child),
                const SizedBox(height: 12),
              ],
        ],
      ),
    );
  }

  // ==========================================================
  // CHILDREN ERROR STATE
  // ==========================================================

  Widget _buildChildrenError() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2F2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AddChildColors.error,
            size: 32,
          ),

          const SizedBox(height: 10),

          Text(
            _childrenError ?? 'Unable to load children.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: AddChildColors.error,
            ),
          ),

          const SizedBox(height: 12),

          TextButton(
            onPressed: () {
              _loadChildren();
            },
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // EMPTY CHILDREN STATE
  // ==========================================================

  Widget _buildEmptyChildren() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        vertical: 28,
        horizontal: 18,
      ),
      decoration: BoxDecoration(
        color: AddChildColors.cream,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AddChildColors.border,
        ),
      ),

      child: const Column(
        children: [
          Icon(
            Icons.child_care_outlined,
            size: 45,
            color: AddChildColors.green,
          ),

          SizedBox(height: 13),

          Text(
            'No child profiles yet',
            style: TextStyle(
              color: AddChildColors.navy,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),

          SizedBox(height: 8),

          Text(
            'Add your first child using the form below.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AddChildColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // INDIVIDUAL CHILD CARD
  // ==========================================================

  Widget _buildChildCard(_ChildProfile child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AddChildColors.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AddChildColors.border,
        ),
      ),

      child: Column(
        children: [
          Row(
            children: [
              _avatar(54),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.fullName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AddChildColors.navy,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      child.ageText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AddChildColors.green,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      'DOB: ${_formatDate(child.dateOfBirth)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AddChildColors.muted,
                      ),
                    ),
                  ],
                ),
              ),

              // Edit placeholder.
              IconButton(
                tooltip: 'Edit Child',
                onPressed: () {
                  _editChild(child);
                },
                icon: const Icon(
                  Icons.edit_outlined,
                  color: AddChildColors.blue,
                ),
              ),

              // Delete placeholder.
              IconButton(
                tooltip: 'Delete Child',
                onPressed: () {
                  _deleteChild(child);
                },
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AddChildColors.error,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          const Divider(
            height: 1,
            color: AddChildColors.border,
          ),

          const SizedBox(height: 10),

          Row(
            children: [
              const Icon(
                Icons.verified_user_outlined,
                size: 15,
                color: AddChildColors.muted,
              ),

              const SizedBox(width: 6),

              const Expanded(
                child: Text(
                  'Child Profile',
                  style: TextStyle(
                    fontSize: 11,
                    color: AddChildColors.muted,
                  ),
                ),
              ),

              TextButton.icon(
                onPressed: () {
                  _viewChildDetails(child);
                },
                icon: const Icon(
                  Icons.visibility_outlined,
                  size: 18,
                ),
                label: const Text('View Details'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // ADD CHILD SECTION
  // ==========================================================

  Widget _buildAddChildSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 15,
          ),
          decoration: BoxDecoration(
            color: AddChildColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AddChildColors.border,
            ),
          ),

          child: Row(
            children: [
              const Icon(
                Icons.person_add_alt_1_rounded,
                color: AddChildColors.green,
                size: 24,
              ),

              const SizedBox(width: 12),

              const Expanded(
                child: Text(
                  'Add New Child',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AddChildColors.navy,
                  ),
                ),
              ),

              IconButton(
                onPressed: _isSaving
                    ? null
                    : () {
                  setState(() {
                    _showForm = !_showForm;
                  });
                },
                icon: Icon(
                  _showForm
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: AddChildColors.navy,
                ),
              ),
            ],
          ),
        ),

        if (_showForm) ...[
          const SizedBox(height: 16),

          Form(
            key: _formKey,
            autovalidateMode: _submitted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,

            child: Column(
              children: [
                _buildBasicDetailsCard(),

                const SizedBox(height: 17),

                _buildGuardianCard(),

                const SizedBox(height: 17),

                _buildEmergencyContactsCard(),

                const SizedBox(height: 17),

                _buildDoctorConnectionCard(),

                const SizedBox(height: 23),

                _buildBottomActions(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ==========================================================
  // BASIC CHILD DETAILS
  // ==========================================================

  Widget _buildBasicDetailsCard() {
    return _sectionCard(
      title: 'Child Information',
      subtitle: 'Basic details about your child',
      icon: Icons.child_care_rounded,

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _responsiveRow(
            _textField(
              label: 'Full Name',
              hint: "Enter child's full name",
              controller: _nameController,
              icon: Icons.person_outline_rounded,
              validator: _validateName,
              inputFormatters: [
                LengthLimitingTextInputFormatter(120),
              ],
            ),

            _buildDateOfBirthField(),
          ),

          if (_dateOfBirth != null) ...[
            const SizedBox(height: 15),

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                color: AddChildColors.lightGreen,
                borderRadius: BorderRadius.circular(12),
              ),

              child: Text(
                'Age: ${_calculateFormAge(_dateOfBirth!)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AddChildColors.green,
                  fontSize: 12,
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),

          _buildParentSelector(),
        ],
      ),
    );
  }

  // ==========================================================
  // DATE OF BIRTH FIELD
  // ==========================================================

  Widget _buildDateOfBirthField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Date of Birth',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AddChildColors.text,
          ),
        ),

        const SizedBox(height: 9),

        InkWell(
          onTap: _isSaving
              ? null
              : _selectDateOfBirth,
          borderRadius: BorderRadius.circular(13),

          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: const Icon(
                Icons.calendar_month_outlined,
                color: AddChildColors.green,
              ),

              filled: true,
              fillColor: AddChildColors.cream,

              errorText: _showDobError
                  ? 'Please select date of birth'
                  : null,

              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
              ),

              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
                borderSide: const BorderSide(
                  color: AddChildColors.border,
                ),
              ),

              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 16,
              ),
            ),

            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _dateOfBirth == null
                        ? 'Select date of birth'
                        : _formatDate(_dateOfBirth!),
                    style: TextStyle(
                      fontSize: 13,
                      color: _dateOfBirth == null
                          ? AddChildColors.muted
                          : AddChildColors.text,
                    ),
                  ),
                ),

                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AddChildColors.muted,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 7),

        const Text(
          'Child Care supports ages 0–12 years.',
          style: TextStyle(
            color: AddChildColors.muted,
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // PARENT PROFILE SELECTOR
  // ==========================================================

  Widget _buildParentSelector() {
    final eligibleParents = _parentProfiles.where(
          (parent) {
        if (_dateOfBirth == null) {
          return true;
        }

        return parent.dateOfBirth.isBefore(
          _dateOfBirth!,
        );
      },
    ).toList();

    final selectedIsEligible = eligibleParents.any(
          (parent) => parent.id == _selectedParentId,
    );

    final selectedValue = selectedIsEligible
        ? _selectedParentId
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Link Parent Profile (Optional)',
          style: TextStyle(
            color: AddChildColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),

        const SizedBox(height: 10),

        if (_loadingParents)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),

                SizedBox(width: 10),

                Text('Loading parent profiles...'),
              ],
            ),
          )
        else if (_parentsLoadFailed)
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Could not load parent profiles. '
                      'You can still add your child.',
                  style: TextStyle(
                    color: AddChildColors.muted,
                    fontSize: 11,
                  ),
                ),
              ),

              TextButton(
                onPressed: _loadParentProfiles,
                child: const Text('Retry'),
              ),
            ],
          )
        else if (eligibleParents.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AddChildColors.cream,
                border: Border.all(
                  color: AddChildColors.border,
                ),
                borderRadius: BorderRadius.circular(12),
              ),

              child: const Text(
                'No eligible Adult/Women profile found. '
                    'This field is optional.',
                style: TextStyle(
                  fontSize: 11,
                  color: AddChildColors.muted,
                ),
              ),
            )
          else
            DropdownButtonFormField<String>(
              key: ValueKey(selectedValue),
              initialValue: selectedValue ?? '',
              isExpanded: true,

              decoration: _fieldDecoration(
                hint: 'Select parent profile',
                icon: Icons.family_restroom_outlined,
              ),

              items: [
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('No parent linked'),
                ),

                ...eligibleParents.map(
                      (parent) {
                    return DropdownMenuItem<String>(
                      value: parent.id,
                      child: Text(
                        '${parent.name} (${parent.module})',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
              ],

              onChanged: _isSaving
                  ? null
                  : (value) {
                setState(() {
                  _selectedParentId =
                  value == null || value.isEmpty
                      ? null
                      : value;
                });
              },
            ),

        const SizedBox(height: 9),

        const Text(
          'Parent profiles must already exist '
              'in your FamilyCare+ account.',
          style: TextStyle(
            fontSize: 10,
            color: AddChildColors.muted,
          ),
        ),
      ],
    );
  }

  // ==========================================================
  // GUARDIAN DETAILS
  // ==========================================================

  Widget _buildGuardianCard() {
    return _sectionCard(
      title: 'Guardian Information',
      subtitle: 'Contact information for the child',
      icon: Icons.family_restroom_outlined,

      child: Column(
        children: [
          _textField(
            label: 'Guardian Mobile Number',
            optional: true,
            hint: 'Enter 10-digit mobile number',
            controller: _guardianController,
            icon: Icons.phone_android_outlined,
            prefix: '+91  ',
            keyboardType: TextInputType.phone,
            validator: (value) {
              return _validateMobile(value);
            },
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
          ),

          const SizedBox(height: 12),

          _buildInfoBox(
            'The mobile number is used as a contact '
                'detail. No mobile OTP verification is '
                'required for this child profile.',
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // EMERGENCY CONTACTS CARD
  // ==========================================================

  Widget _buildEmergencyContactsCard() {
    return _sectionCard(
      title: 'Emergency Contacts',
      subtitle: 'Add up to 5 emergency contacts',
      icon: Icons.contact_emergency_outlined,

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_contacts.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AddChildColors.cream,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AddChildColors.border,
                ),
              ),

              child: const Column(
                children: [
                  Icon(
                    Icons.contact_phone_outlined,
                    size: 30,
                    color: AddChildColors.green,
                  ),

                  SizedBox(height: 10),

                  Text(
                    'No emergency contacts added',
                    style: TextStyle(
                      color: AddChildColors.navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  SizedBox(height: 6),

                  Text(
                    'Emergency contacts are optional.',
                    style: TextStyle(
                      color: AddChildColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

          for (int index = 0;
          index < _contacts.length;
          index++) ...[
            _buildEmergencyContactForm(
              index,
              _contacts[index],
            ),

            const SizedBox(height: 12),
          ],

          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed: _isSaving || _contacts.length >= 5
                ? null
                : _addEmergencyContact,

            icon: const Icon(
              Icons.add_circle_outline_rounded,
              size: 19,
            ),

            label: Text(
              _contacts.length >= 5
                  ? 'Maximum 5 contacts'
                  : 'Add Emergency Contact',
            ),

            style: OutlinedButton.styleFrom(
              foregroundColor: AddChildColors.green,
              side: const BorderSide(
                color: AddChildColors.border,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // EMERGENCY CONTACT FORM
  // ==========================================================

  Widget _buildEmergencyContactForm(
      int index,
      _EmergencyContactInput contact,
      ) {
    return Container(
      key: ObjectKey(contact),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AddChildColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AddChildColors.border,
        ),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Emergency Contact ${index + 1}',
                  style: const TextStyle(
                    color: AddChildColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              IconButton(
                tooltip: 'Remove Contact',
                onPressed: _isSaving
                    ? null
                    : () {
                  _removeEmergencyContact(index);
                },
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: AddChildColors.error,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _responsiveRow(
            _textField(
              label: 'Contact Name',
              hint: 'Enter contact name',
              controller: contact.nameController,
              icon: Icons.person_outline_rounded,
              validator: _validateContactName,
              inputFormatters: [
                LengthLimitingTextInputFormatter(120),
              ],
            ),

            _textField(
              label: 'Relationship',
              hint: 'Mother, Father, Guardian...',
              controller: contact.relationshipController,
              icon: Icons.people_outline_rounded,
              validator: _validateRelationship,
              inputFormatters: [
                LengthLimitingTextInputFormatter(50),
              ],
            ),
          ),

          const SizedBox(height: 17),

          _textField(
            label: 'Mobile Number',
            hint: 'Enter 10-digit number',
            controller: contact.mobileController,
            icon: Icons.phone_outlined,
            prefix: '+91  ',
            keyboardType: TextInputType.phone,
            validator: (value) {
              return _validateMobile(
                value,
                isRequired: true,
              );
            },
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // DOCTOR CONNECTION CARD
  // ==========================================================

  Widget _buildDoctorConnectionCard() {
    return _sectionCard(
      title: 'Connect Doctor',
      subtitle: 'Optional doctor referral connection',
      icon: Icons.medical_services_outlined,

      child: Column(
        children: [
          _textField(
            label: 'Doctor Referral ID',
            optional: true,
            hint: 'Enter referral ID',
            controller: _referralController,
            icon: Icons.verified_user_outlined,
            validator: _validateReferral,
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                RegExp(r'[A-Za-z0-9]'),
              ),
              LengthLimitingTextInputFormatter(160),
            ],
          ),

          const SizedBox(height: 13),

          _buildInfoBox(
            'Enter a valid doctor referral ID if '
                'you want to connect the child with '
                'that doctor. You can connect a doctor later.',
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // INFORMATION BOX
  // ==========================================================

  Widget _buildInfoBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AddChildColors.lightGreen,
        borderRadius: BorderRadius.circular(12),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AddChildColors.green,
            size: 19,
          ),

          const SizedBox(width: 9),

          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AddChildColors.text,
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
  // BOTTOM ACTION BUTTONS
  // ==========================================================

  Widget _buildBottomActions() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 440;

        final clearButton = OutlinedButton(
          onPressed: _isSaving
              ? null
              : _resetForm,

          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 54),
            foregroundColor: AddChildColors.navy,
            side: const BorderSide(
              color: AddChildColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),

          child: const Text('Clear Form'),
        );

        final saveButton = FilledButton.icon(
          onPressed: _isSaving
              ? null
              : _saveChild,

          icon: _isSaving
              ? const SizedBox(
            height: 19,
            width: 19,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
              : const Icon(
            Icons.check_circle_outline_rounded,
          ),

          label: Text(
            _isSaving
                ? 'Saving Child...'
                : 'Save Child Profile',
          ),

          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 54),
            backgroundColor: AddChildColors.blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
          ),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              saveButton,

              const SizedBox(height: 12),

              clearButton,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: clearButton),

            const SizedBox(width: 14),

            Expanded(
              flex: 2,
              child: saveButton,
            ),
          ],
        );
      },
    );
  }
}
