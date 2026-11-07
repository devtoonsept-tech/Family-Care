
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

/// FamilyCare+ Doctor Profile - Backend v9.
///
/// PROFILE_REQUIRED / REJECTED: limited setup token can submit details and
/// upload optional profile / degree images.
/// PENDING_APPROVAL: read only. v9 does not expose /setup-details and does
/// not accept pending editing via /setup-profile or /setup-images.
/// APPROVED: professional fields and degree image are read-only. An approved,
/// authenticated doctor may GET / POST / PUT / DELETE their profile photo.
class DoctorProfileSetupScreen extends StatefulWidget {
  const DoctorProfileSetupScreen({
    super.key,
    this.setupToken,
    this.initialUser,
    this.initialDoctor,
    this.approvalStatus = 'UNKNOWN',
    this.rejectionReason,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.onSubmitted,
    this.onBackToDashboard,
  });

  final String? setupToken;
  final Map<String, dynamic>? initialUser;
  final Map<String, dynamic>? initialDoctor;
  final String approvalStatus;
  final String? rejectionReason;
  final String apiBaseUrl;
  final ValueChanged<Map<String, dynamic>>? onSubmitted;
  final VoidCallback? onBackToDashboard;

  @override
  State<DoctorProfileSetupScreen> createState() =>
      _DoctorProfileSetupScreenState();
}

class _ProfileTheme {
  static const ink = Color(0xFF264A51);
  static const green = Color(0xFF367D69);
  static const blue = Color(0xFF477F99);
  static const mint = Color(0xFFE8F7EF);
  static const ice = Color(0xFFECF5FA);
  static const page = Color(0xFFF6FAF9);
  static const line = Color(0xFFDCEAE7);
  static const muted = Color(0xFF70848A);
  static const danger = Color(0xFFAE555B);
  static const warning = Color(0xFF97752F);
}

class _ProfileApiError implements Exception {
  const _ProfileApiError(this.message, this.status, [this.code = '']);
  final String message;
  final int status;
  final String code;
  @override
  String toString() => message;
}

String _pText(dynamic v) => (v ?? '').toString().trim();
Map<String, dynamic> _pMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class _DoctorProfileSetupScreenState extends State<DoctorProfileSetupScreen> {
  static const int _maxImageBytes = 5 * 1024 * 1024;

  final _client = http.Client();
  final _form = GlobalKey<FormState>();
  final _qualification = TextEditingController();
  final _registration = TextEditingController();
  final _council = TextEditingController();
  final _specialization = TextEditingController();
  final _nmr = TextEditingController();
  final _experience = TextEditingController();
  final _address = TextEditingController();
  final _clinic = TextEditingController();

  late final _controllers = <TextEditingController>[
    _qualification,
    _registration,
    _council,
    _specialization,
    _nmr,
    _experience,
    _address,
    _clinic,
  ];

  Map<String, dynamic> _user = {};
  Map<String, dynamic> _doctor = {};
  Map<String, dynamic> _images = {};
  Uint8List? _photoBytes;
  Uint8List? _degreeBytes;

  String _status = 'UNKNOWN';
  String _setupToken = '';
  String _reason = '';
  String? _error;
  String? _uploadingKind;

  bool _dirty = false;
  bool _filling = false;
  bool _loading = false;
  bool _saving = false;
  bool _checkingStatus = false;
  bool _approvedSession = false;
  bool _removingPhoto = false;

  int _revision = 0;

  bool get _approved => _status == 'APPROVED';
  bool get _pending => _status == 'PENDING_APPROVAL';
  bool get _setupEditable =>
      _setupToken.isNotEmpty &&
          const {'PROFILE_REQUIRED', 'REJECTED'}.contains(_status);
  bool get _canUploadPhoto => _setupEditable || (_approved && _approvedSession);
  bool get _busy => _loading || _saving || _checkingStatus ||
      _uploadingKind != null || _removingPhoto;

  String get _root {
    var value = widget.apiBaseUrl.trim();
    if (value.isEmpty) {
      value = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:5001'
          : 'http://127.0.0.1:5001';
    }
    value = value.replaceFirst(RegExp(r'/+$'), '');
    for (final suffix in ['/api/v1/doctors', '/api/v1']) {
      if (value.endsWith(suffix)) {
        return value.substring(0, value.length - suffix.length);
      }
    }
    return value;
  }

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_onChanged);
    }
    _applyInitial();
    if (_approved) {
      _refreshApproved();
    }
  }

  @override
  void didUpdateWidget(covariant DoctorProfileSetupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.setupToken != widget.setupToken ||
        oldWidget.initialUser != widget.initialUser ||
        oldWidget.initialDoctor != widget.initialDoctor ||
        oldWidget.approvalStatus != widget.approvalStatus ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      ++_revision;
      final oldId = _pText(_user['id']);
      _applyInitial();
      if (oldId != _pText(_user['id'])) {
        _photoBytes = null;
        _degreeBytes = null;
      }
      if (_approved) _refreshApproved();
    }
  }

  @override
  void dispose() {
    ++_revision;
    for (final controller in _controllers) {
      controller.removeListener(_onChanged);
      controller.dispose();
    }
    _client.close();
    super.dispose();
  }

  void _onChanged() {
    if (!_filling && _setupEditable && !_dirty && mounted) {
      setState(() => _dirty = true);
    }
  }

  void _applyInitial() {
    _user = _pMap(widget.initialUser);
    _doctor = _pMap(widget.initialDoctor);
    if (_doctor.isEmpty) _doctor = _pMap(_user['doctor']);
    _images = _pMap(_doctor['images']);
    _status = _pText(_user['approval_status']).isNotEmpty
        ? _pText(_user['approval_status']).toUpperCase()
        : widget.approvalStatus.toUpperCase();
    _setupToken = widget.setupToken?.trim() ?? '';
    _reason = widget.rejectionReason?.trim() ?? '';
    _error = null;
    _approvedSession = false;
    _fillForm();
  }

  void _fillForm() {
    _filling = true;
    _qualification.text = _pText(_doctor['qualification']);
    _registration.text = _pText(_doctor['medical_registration_number']);
    _council.text = _pText(_doctor['registering_council']);
    _specialization.text = _pText(_doctor['specialization']);
    _nmr.text = _pText(_doctor['nmr_id']);
    _experience.text = _pText(_doctor['years_of_experience']);
    _address.text = _pText(_doctor['address']);
    _clinic.text = _pText(_doctor['clinic_address']);
    _dirty = false;
    _filling = false;
  }

  String _friendly(Object error) {
    if (error is _ProfileApiError) return error.message;
    if (error is TimeoutException) {
      return 'Request timed out. Check whether the change saved before retrying.';
    }
    if (error is http.ClientException) {
      return 'Cannot connect to FamilyCare+. Check the backend connection.';
    }
    if (error is FormatException) return 'Unexpected response from server.';
    if (error is StateError) return error.message.toString();
    return 'Unable to complete this action. Please retry.';
  }

  void _notice(String value, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? _ProfileTheme.danger : _ProfileTheme.ink,
        content: Text(value),
      ));
  }

  Map<String, dynamic> _decode(http.Response response) {
    Map<String, dynamic> result = {};
    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) {
          result = Map<String, dynamic>.from(decoded);
        } else if (response.statusCode < 300) {
          throw const FormatException('Expected JSON object.');
        }
      } on FormatException {
        if (response.statusCode >= 200 && response.statusCode < 300) rethrow;
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final issue = result['error'];
      final details = _pMap(issue);
      final code = _pText(details['code']);
      final fromApi = _pText(details['message']).isNotEmpty
          ? _pText(details['message'])
          : issue is String ? issue : '';
      final fallback = switch (response.statusCode) {
        401 => 'Your session or setup token expired. Sign in again.',
        403 => 'This action is not permitted for your doctor account.',
        404 => 'This endpoint or profile is not available.',
        409 => 'Profile status has changed. Sign in again to refresh.',
        413 => 'Image is too large. Choose an image up to 5 MB.',
        422 => 'Please review the submitted information.',
        429 => 'Too many requests. Try again later.',
        _ => 'Request failed (HTTP ${response.statusCode}).',
      };
      throw _ProfileApiError(
        fromApi.isNotEmpty ? fromApi : fallback,
        response.statusCode,
        code,
      );
    }
    return result;
  }

  void _handleSetupFailure(Object error) {
    if (error is _ProfileApiError &&
        (error.status == 401 || error.code == 'invalid_token' ||
            error.code == 'expired_token' || error.code == 'invalid_state')) {
      setState(() => _setupToken = '');
    }
  }

  Future<String> _doctorToken() async {
    final role = await FamilyCareSession.role();
    final token = await FamilyCareSession.accessToken();
    final expires = await FamilyCareSession.accessTokenExpiresAt();
    if (_pText(role).toUpperCase() != 'DOCTOR' ||
        token == null || token.isEmpty || expires == null ||
        !expires.isAfter(DateTime.now().toUtc())) {
      throw const _ProfileApiError(
          'Approved doctor login required. Sign in again.', 401);
    }
    return token;
  }

  Future<Map<String, dynamic>> _authRequest(String method, String path) async {
    final token = await _doctorToken();
    final url = Uri.parse('$_root$path');
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'X-Auth-Transport': 'bearer',
      'Accept': 'application/json',
    };
    final response = method == 'DELETE'
        ? await _client.delete(url, headers: headers)
        .timeout(const Duration(seconds: 30))
        : await _client.get(url, headers: headers)
        .timeout(const Duration(seconds: 30));
    return _decode(response);
  }

  Future<void> _refreshApproved() async {
    if (_loading || _saving || !_approved) return;
    final revision = ++_revision;
    setState(() {
      _loading = true;
      _error = null;
      _approvedSession = false;
    });
    try {
      final result = await _authRequest('GET', '/api/v1/doctors/me');
      final user = _pMap(result['user']);
      if (_pText(user['role']).toUpperCase() != 'DOCTOR' ||
          _pText(user['approval_status']).toUpperCase() != 'APPROVED' ||
          _pText(user['account_status']).toUpperCase() != 'ACTIVE') {
        throw const _ProfileApiError(
            'Your approved doctor session is not active. Sign in again.', 403);
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        _user = user;
        _doctor = _pMap(user['doctor']);
        _images = _pMap(_doctor['images']);
        _status = 'APPROVED';
        _approvedSession = true;
        _photoBytes = null;
        _degreeBytes = null;
        _fillForm();
      });
      // GET /profile-photo returns the newest signed private photo URL.
      // The /me response also supplies images, so a failure is non-fatal.
      try {
        final photo = await _authRequest(
            'GET', '/api/v1/doctors/profile-photo');
        if (!mounted || revision != _revision) return;
        setState(() {
          if (photo['photo'] is Map) {
            _images = {..._images, 'profile_photo': _pMap(photo['photo'])};
          } else if (photo.containsKey('photo')) {
            _images.remove('profile_photo');
          }
        });
      } catch (_) {
        // /me has already supplied the approved doctor's image details.
      }
    } catch (error) {
      if (!mounted || revision != _revision) return;
      setState(() {
        _approvedSession = false;
        _error = _friendly(error);
      });
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _confirm(String title, String message,
      {String action = 'Continue', bool dangerous = false}) async {
    if (!mounted) return false;
    return await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: dangerous
                  ? _ProfileTheme.danger : _ProfileTheme.green,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(action),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<String?> _askPassword() async {
    var entered = '';
    return showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Check approval status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter your doctor password to securely check the current '
                  'approval status. Your password is not saved.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 13),
            TextField(
              obscureText: true,
              enableSuggestions: false,
              autocorrect: false,
              onChanged: (value) => entered = value,
              decoration: const InputDecoration(
                labelText: 'Password', border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.pop(dialog, entered),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, entered),
            child: const Text('Check'),
          ),
        ],
      ),
    );
  }

  Future<void> _checkApproval() async {
    if (_busy || _approved) return;
    final email = _pText(_user['email']);
    if (email.isEmpty) {
      _notice('Sign in again to check approval status.', error: true);
      return;
    }
    if (_dirty) {
      final discard = await _confirm(
        'Discard unsaved details?',
        'Checking status may switch the form to read-only. Save or copy '
            'your unsaved information first.',
        action: 'Discard & Check',
      );
      if (!discard) return;
    }
    final password = await _askPassword();
    if (!mounted || password == null || password.isEmpty) return;
    final version = ++_revision;
    setState(() {
      _checkingStatus = true;
      _error = null;
    });
    try {
      final response = await _client.post(
        Uri.parse('$_root/api/v1/doctors/approval-status'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'email': email, 'password': password}),
      ).timeout(const Duration(seconds: 30));
      final result = _decode(response);
      if (!mounted || version != _revision) return;
      final nextStatus = _pText(result['approval_status']).toUpperCase();
      if (nextStatus.isEmpty) throw const FormatException('Missing status.');
      setState(() {
        _status = nextStatus;
        _reason = _pText(result['rejection_reason']);
        // A status check cannot issue or renew a limited setup token.
        // Login again after rejection to get a fresh setup token.
        if (nextStatus != 'PROFILE_REQUIRED' && nextStatus != 'REJECTED') {
          _setupToken = '';
        }
        _approvedSession = false;
        if (!_setupEditable) _dirty = false;
      });
      _notice('Status: ${_statusLabel(nextStatus)}. '
          'Sign in again if your status or permissions changed.');
    } catch (error) {
      if (!mounted || version != _revision) return;
      setState(() => _error = _friendly(error));
      _notice(_friendly(error), error: true);
    } finally {
      if (mounted && version == _revision) {
        setState(() => _checkingStatus = false);
      }
    }
  }

  String _statusLabel(String value) => switch (value) {
    'PROFILE_REQUIRED' => 'Profile required',
    'REJECTED' => 'Changes requested',
    'PENDING_APPROVAL' => 'Pending admin review',
    'APPROVED' => 'Approved',
    _ => value.replaceAll('_', ' '),
  };

  Future<bool> _canLeave() async {
    if (_busy) return false;
    if (!_dirty) return true;
    return _confirm(
      'Leave without saving?',
      'Professional details you typed have not been submitted. '
          'Successfully uploaded images are already saved.',
      action: 'Leave',
    );
  }

  Future<void> _back() async {
    if (!await _canLeave() || !mounted) return;
    if (widget.onBackToDashboard != null) {
      widget.onBackToDashboard!();
    } else {
      Navigator.of(context).pop();
    }
  }

  String? _required(String? raw, {int min = 2, int max = 200}) {
    final text = (raw ?? '').trim();
    if (text.length < min) return 'At least $min characters required';
    if (text.length > max) return 'Maximum $max characters allowed';
    return null;
  }

  String? _optional(String? raw, int max) =>
      (raw ?? '').trim().length > max ? 'Maximum $max characters' : null;

  Future<void> _saveProfile() async {
    if (!_setupEditable || _busy || !(_form.currentState?.validate() ?? false)) {
      return;
    }
    final years = int.tryParse(_experience.text.trim());
    if (years == null || years < 0 || years > 80) {
      _notice('Experience must be between 0 and 80 years.', error: true);
      return;
    }
    final details = <String, dynamic>{
      'qualification': _qualification.text.trim(),
      'medical_registration_number': _registration.text.trim(),
      'registering_council': _council.text.trim(),
      'specialization': _specialization.text.trim().isEmpty
          ? null : _specialization.text.trim(),
      'nmr_id': _nmr.text.trim().isEmpty ? null : _nmr.text.trim(),
      'years_of_experience': years,
      'address': _address.text.trim(),
      'clinic_address': _clinic.text.trim(),
    };
    final revision = _revision;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await _client.post(
        Uri.parse('$_root/api/v1/doctors/setup-profile'),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'setup_token': _setupToken, ...details}),
      ).timeout(const Duration(seconds: 40));
      final result = _decode(response);
      final user = _pMap(result['user']);
      if (_pText(user['approval_status']).toUpperCase() != 'PENDING_APPROVAL') {
        throw const FormatException('Profile submission not confirmed.');
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        _user = user;
        // Backend v9 returns user, not an updated doctor object.
        _doctor = {..._doctor, ...details, 'images': _images};
        _status = 'PENDING_APPROVAL';
        _reason = '';
        _dirty = false;
        _setupToken = ''; // A pending application cannot submit again in v9.
        _fillForm();
      });
      _notice('Application submitted for admin review.');
      widget.onSubmitted?.call({...result, 'doctor': _doctor});
    } catch (error) {
      if (!mounted || revision != _revision) return;
      _handleSetupFailure(error);
      setState(() => _error = _friendly(error));
      _notice(_friendly(error), error: true);
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _saving = false);
      }
    }
  }

  bool _validImage(Uint8List b, String name) {
    final lower = name.toLowerCase();
    final jpeg = b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 &&
        b[2] == 0xff && (lower.endsWith('.jpg') || lower.endsWith('.jpeg'));
    final png = b.length >= 8 && b[0] == 0x89 && b[1] == 0x50 &&
        b[2] == 0x4e && b[3] == 0x47 && b[4] == 0x0d && b[5] == 0x0a &&
        b[6] == 0x1a && b[7] == 0x0a && lower.endsWith('.png');
    final webp = b.length >= 12 && b[0] == 0x52 && b[1] == 0x49 &&
        b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 &&
        b[10] == 0x42 && b[11] == 0x50 && lower.endsWith('.webp');
    return jpeg || png || webp;
  }

  /// Compatible with file_picker 11 and 12/13's different return types.
  /// Do not call deprecated FilePicker.platform on newer versions.
  Future<PlatformFile?> _pickImage() async {
    final dynamic result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    if (result == null) return null;
    if (result is List) {
      return result.isNotEmpty && result.first is PlatformFile
          ? result.first as PlatformFile : null;
    }
    final dynamic files = result.files; // file_picker 11
    if (files is List && files.isNotEmpty && files.first is PlatformFile) {
      return files.first as PlatformFile;
    }
    return null;
  }

  Future<Uint8List> _readImage(PlatformFile file) async {
    final dynamic p = file;
    Stream<List<int>> stream;
    try {
      stream = (p.readAsByteStream() as Stream).cast<List<int>>();
    } on NoSuchMethodError {
      // file_picker v11 exposes the cross_file XFile.
      stream = (p.xFile.openRead() as Stream).cast<List<int>>();
    }
    final builder = BytesBuilder(copy: false);
    var count = 0;
    await for (final chunk in stream) {
      count += chunk.length;
      if (count > _maxImageBytes) {
        throw StateError('Images must be 5 MB or smaller.');
      }
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) throw StateError('The selected image was empty.');
    if (!_validImage(bytes, file.name)) {
      throw StateError('Choose a valid JPG, PNG or WebP image.');
    }
    return bytes;
  }

  Future<void> _uploadImage(String kind) async {
    if (_busy || (kind == 'degree_photo' ? !_setupEditable : !_canUploadPhoto)) {
      return;
    }
    final revision = _revision;
    try {
      final selected = await _pickImage();
      if (selected == null || !mounted || revision != _revision) return;
      if (_busy || (kind == 'degree_photo' ? !_setupEditable : !_canUploadPhoto)) {
        return;
      }
      setState(() => _uploadingKind = kind);
      final bytes = await _readImage(selected);
      if (!mounted || revision != _revision) return;

      final approved = _approved;
      final request = http.MultipartRequest(
        approved && _pMap(_images['profile_photo']).isNotEmpty ? 'PUT' : 'POST',
        Uri.parse('$_root/api/v1/doctors/'
            '${approved ? 'profile-photo' : 'setup-images'}'),
      );
      request.headers['Accept'] = 'application/json';
      if (approved) {
        final token = await _doctorToken();
        request.headers['Authorization'] = 'Bearer $token';
        request.headers['X-Auth-Transport'] = 'bearer';
      } else {
        request.fields['setup_token'] = _setupToken;
        request.fields['kind'] = kind;
      }
      request.files.add(http.MultipartFile.fromBytes(
        'file', bytes, filename: selected.name,
      ));
      final streamed = await _client.send(request)
          .timeout(const Duration(seconds: 90));
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 30));
      final result = _decode(response);
      final received = _pMap(result['images']);
      final uploaded = _pMap(received[kind]);
      if (_pText(uploaded['name']).isEmpty ||
          _pText(uploaded['url']).isEmpty) {
        throw const FormatException('Upload was not confirmed by the server.');
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        _images = {..._images, ...received};
        if (kind == 'profile_photo') {
          _photoBytes = bytes;
        } else {
          _degreeBytes = bytes;
        }
      });
      _notice(kind == 'profile_photo'
          ? 'Doctor photo uploaded.' : 'Degree image uploaded.');
    } catch (error) {
      if (mounted && revision == _revision) {
        if (!_approved) _handleSetupFailure(error);
        _notice(_friendly(error), error: true);
      }
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _uploadingKind = null);
      }
    }
  }

  Future<void> _removePhoto() async {
    if (!_approved || !_approvedSession || _busy ||
        _pMap(_images['profile_photo']).isEmpty) return;
    final yes = await _confirm(
      'Remove profile photo?',
      'Your approved doctor profile will keep its verification details. '
          'Only your optional photo will be removed.',
      action: 'Remove Photo', dangerous: true,
    );
    if (!yes || !mounted) return;
    final revision = _revision;
    setState(() => _removingPhoto = true);
    try {
      await _authRequest('DELETE', '/api/v1/doctors/profile-photo');
      if (!mounted || revision != _revision) return;
      setState(() {
        _images.remove('profile_photo');
        _photoBytes = null;
      });
      _notice('Profile photo removed.');
    } catch (error) {
      _notice(_friendly(error), error: true);
    } finally {
      if (mounted && revision == _revision) {
        setState(() => _removingPhoto = false);
      }
    }
  }

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: _ProfileTheme.line),
      borderRadius: BorderRadius.circular(17),
    ),
    child: child,
  );

  Widget _heading(String title, IconData icon) => Row(children: [
    Icon(icon, color: _ProfileTheme.green, size: 21),
    const SizedBox(width: 9),
    Expanded(child: Text(title, style: const TextStyle(
      color: _ProfileTheme.ink, fontSize: 16,
      fontWeight: FontWeight.w800,
    ))),
  ]);

  Widget _pair(Widget a, Widget b) => LayoutBuilder(
    builder: (_, constraints) => constraints.maxWidth >= 650
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(child: a), const SizedBox(width: 12), Expanded(child: b),
    ])
        : Column(children: [a, b]),
  );

  Widget _detail(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 105, child: Text(label,
          style: const TextStyle(color: _ProfileTheme.muted, fontSize: 12))),
      const SizedBox(width: 10),
      Expanded(child: SelectableText(
        _pText(value).isEmpty ? 'Not provided' : _pText(value),
        style: const TextStyle(color: _ProfileTheme.ink,
            fontWeight: FontWeight.w600, fontSize: 12),
      )),
    ]),
  );

  Widget _field(
      TextEditingController controller,
      String title, {
        required int max,
        int min = 2,
        bool optional = false,
        int lines = 1,
        TextInputType? keyboard,
        String? Function(String?)? validator,
      }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      readOnly: !_setupEditable || _busy,
      maxLength: _setupEditable ? max : null,
      maxLengthEnforcement: MaxLengthEnforcement.enforced,
      maxLines: lines,
      keyboardType: keyboard,
      style: const TextStyle(color: _ProfileTheme.ink, fontSize: 13),
      decoration: InputDecoration(
        labelText: title,
        counterText: '',
        filled: true,
        fillColor: _setupEditable ? Colors.white : _ProfileTheme.page,
        suffixIcon: _setupEditable ? null : const Icon(
            Icons.lock_outline, color: _ProfileTheme.muted, size: 17),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: _ProfileTheme.line),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: _ProfileTheme.green),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      validator: !_setupEditable ? null : (validator ??
              (value) => optional ? _optional(value, max)
              : _required(value, min: min, max: max)),
    ),
  );

  Widget _banner() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [_ProfileTheme.mint, _ProfileTheme.ice],
      ),
      border: Border.all(color: _ProfileTheme.line),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(children: [
      const Icon(Icons.medical_services_outlined,
          color: _ProfileTheme.green, size: 30),
      const SizedBox(width: 12),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('FAMILYCARE+ / DOCTOR', style: TextStyle(
            fontSize: 10, color: _ProfileTheme.green,
            fontWeight: FontWeight.w800, letterSpacing: 1,
          )),
          const SizedBox(height: 4),
          Text(_approved ? 'My Professional Profile' : 'Doctor Profile Setup',
              style: const TextStyle(fontSize: 20,
                  fontWeight: FontWeight.w900, color: _ProfileTheme.ink)),
          const SizedBox(height: 4),
          Text(_pText(_user['full_name']).isEmpty
              ? 'Professional details and verification'
              : _pText(_user['full_name']),
              style: const TextStyle(color: _ProfileTheme.muted, fontSize: 12)),
        ],
      )),
    ]),
  );

  Widget _statusCard() {
    String note;
    if (_approved) {
      note = _approvedSession
          ? 'Professional details are read-only. You can replace or remove '
          'your optional doctor photo. Degree image replacement is not '
          'supported after approval in Backend v9.'
          : 'Doctor approved. Sign in again with your approved doctor account '
          'to refresh your profile and manage the optional photo.';
    } else if (_pending) {
      note = 'Your application is under admin review. Backend v9 keeps '
          'professional details and setup images read-only while pending. '
          'If rejected, sign in again to edit and resubmit.';
    } else if (_setupEditable) {
      note = 'Fill your details and submit for review. Optional photos can '
          'be uploaded separately and are saved immediately. The setup token '
          'is short-lived; sign in again if it expires.';
    } else {
      note = 'A fresh doctor setup token is required. Sign in again to '
          'complete or correct the application.';
    }
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(_approved ? Icons.verified_outlined :
        _pending ? Icons.hourglass_top_rounded : Icons.info_outline,
            color: _approved ? _ProfileTheme.green : _ProfileTheme.warning),
        const SizedBox(width: 9),
        Expanded(child: Text(_statusLabel(_status), style: const TextStyle(
          color: _ProfileTheme.ink, fontSize: 15,
          fontWeight: FontWeight.w800,
        ))),
        if (_dirty) const Text('Unsaved', style: TextStyle(
          color: _ProfileTheme.warning, fontSize: 11,
          fontWeight: FontWeight.w700,
        )),
      ]),
      const SizedBox(height: 9),
      Text(note, style: const TextStyle(
          color: _ProfileTheme.muted, fontSize: 12, height: 1.45)),
      if (_reason.isNotEmpty) ...[
        const SizedBox(height: 9),
        Text('Admin feedback: $_reason', style: const TextStyle(
          color: _ProfileTheme.danger, fontSize: 12,
        )),
      ],
      if (_error != null) ...[
        const SizedBox(height: 9),
        Text(_error!, style: const TextStyle(
          color: _ProfileTheme.danger, fontSize: 12,
        )),
      ],
      if (_busy) ...[
        const SizedBox(height: 10),
        const LinearProgressIndicator(color: _ProfileTheme.green),
      ],
    ]));
  }

  Widget _accountCard() => _card(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('Account Details', Icons.person_outline),
      const SizedBox(height: 9),
      _detail('Full name', _user['full_name']),
      const Divider(height: 1, color: _ProfileTheme.line),
      _detail('Email', _user['email']),
      const Divider(height: 1, color: _ProfileTheme.line),
      _detail('Mobile', _user['phone_number'] ?? _user['mobile_number']),
      const SizedBox(height: 5),
      const Text('Account identity is read-only on this screen.',
          style: TextStyle(color: _ProfileTheme.muted, fontSize: 11)),
    ],
  ));

  Widget _imageTile(String kind, String title, IconData icon) {
    final info = _pMap(_images[kind]);
    final url = _pText(info['url']);
    final name = _pText(info['name']);
    final bytes = kind == 'profile_photo' ? _photoBytes : _degreeBytes;
    final exists = info.isNotEmpty || bytes != null;
    final uri = Uri.tryParse(url);
    final online = uri != null && uri.scheme == 'https' &&
        uri.host.toLowerCase() == 'res.cloudinary.com';
    final canUpload = kind == 'profile_photo'
        ? _canUploadPhoto : _setupEditable;
    final uploading = _uploadingKind == kind;

    Widget preview;
    if (bytes != null) {
      preview = Image.memory(bytes, fit: BoxFit.contain);
    } else if (online) {
      preview = Image.network(
        url,
        key: ValueKey(url),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Center(
          child: Text('Preview expired or unavailable. Refresh to try again.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: _ProfileTheme.muted)),
        ),
      );
    } else {
      preview = Icon(icon, size: 36, color: _ProfileTheme.muted);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _ProfileTheme.page,
        border: Border.all(color: _ProfileTheme.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: _ProfileTheme.green, size: 18),
          const SizedBox(width: 7),
          Expanded(child: Text(title, style: const TextStyle(
            color: _ProfileTheme.ink, fontSize: 13,
            fontWeight: FontWeight.w800,
          ))),
          if (exists) const Icon(Icons.check_circle,
              color: _ProfileTheme.green, size: 17),
        ]),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 145,
            color: Colors.white,
            alignment: Alignment.center,
            child: preview,
          ),
        ),
        const SizedBox(height: 7),
        Text(exists ? (name.isNotEmpty ? name : 'Saved image') : 'Not uploaded',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: _ProfileTheme.muted)),
        const SizedBox(height: 9),
        OutlinedButton.icon(
          onPressed: canUpload && !_busy ? () => _uploadImage(kind) : null,
          icon: uploading
              ? const SizedBox(width: 17, height: 17,
              child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(exists ? Icons.edit_outlined : Icons.upload_outlined,
              size: 17),
          label: Text(uploading ? 'Uploading...' :
          exists ? 'Replace Image' : 'Upload Image'),
        ),
        if (kind == 'profile_photo' && exists && _approved && _approvedSession)
          TextButton.icon(
            onPressed: _busy ? null : _removePhoto,
            icon: const Icon(Icons.delete_outline, size: 17),
            label: const Text('Remove Photo'),
            style: TextButton.styleFrom(foregroundColor: _ProfileTheme.danger),
          ),
      ]),
    );
  }

  Widget _documentsCard() => _card(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('Documents & Photos', Icons.image_outlined),
      const SizedBox(height: 7),
      const Text('Both optional • JPG, PNG, WebP • Up to 5 MB each',
          style: TextStyle(color: _ProfileTheme.muted, fontSize: 12)),
      const SizedBox(height: 12),
      _pair(
        _imageTile('profile_photo', 'Doctor Photo', Icons.person_outline),
        _imageTile('degree_photo', 'Degree Certificate', Icons.school_outlined),
      ),
      const SizedBox(height: 8),
      Text(_approved
          ? 'Photo can be changed or removed after approval; degree image '
          'is read-only. Private image preview links expire after about '
          '5 minutes; use Refresh to get new links.'
          : _pending
          ? 'Images are read-only while an application is under review.'
          : 'Uploaded images save immediately. They are optional and '
          'do not need to be attached to submit your details.',
          style: const TextStyle(
              color: _ProfileTheme.muted, fontSize: 11, height: 1.4)),
    ],
  ));

  Widget _professionalCard() => _card(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('Professional Details', Icons.workspace_premium_outlined),
      const SizedBox(height: 9),
      Text(_setupEditable
          ? 'Complete the required fields to submit for verification.'
          : 'Professional information is read-only in the current status.',
          style: const TextStyle(color: _ProfileTheme.muted, fontSize: 12)),
      const SizedBox(height: 13),
      _pair(
        _field(_qualification, 'Qualification', max: 200),
        _field(_specialization, 'Specialization (optional)', max: 200,
            optional: true),
      ),
      _pair(
        _field(_registration, 'Medical Registration Number', max: 100,
            validator: (value) => RegExp(
              r'^[A-Za-z0-9][A-Za-z0-9/ ._-]{1,99}$',
            ).hasMatch((value ?? '').trim()) ? null : 'Invalid registration number'),
        _field(_council, 'Registering Medical Council', max: 200),
      ),
      _pair(
        _field(_nmr, 'NMR ID (optional)', max: 100, optional: true),
        _field(_experience, 'Years of Experience (0–80)',
            max: 2, min: 1, keyboard: TextInputType.number,
            validator: (value) {
              final n = int.tryParse((value ?? '').trim());
              return n != null && n >= 0 && n <= 80
                  ? null : 'Enter whole years from 0 to 80';
            }),
      ),
      _field(_address, 'Personal Address', max: 1000, min: 5, lines: 2),
      _field(_clinic, 'Clinic / Practice Address', max: 1000,
          min: 5, lines: 2),
    ],
  ));

  Widget _actions() => _card(Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_setupEditable) ...[
        const Text('Your submitted application will go to admin review.',
            style: TextStyle(color: _ProfileTheme.muted, fontSize: 12)),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _busy ? null : _saveProfile,
          style: FilledButton.styleFrom(
            backgroundColor: _ProfileTheme.green,
            minimumSize: const Size.fromHeight(47),
          ),
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Submitting...' :
          _status == 'REJECTED' ? 'Resubmit for Approval' : 'Submit for Approval'),
        ),
      ] else ...[
        Text(_approved
            ? 'Professional details are approved. Optional photo can '
            'still be managed with an active doctor session.'
            : _pending
            ? 'Application under review. Editing becomes available '
            'again if admin requests changes.'
            : 'Sign in again to obtain a fresh profile setup token.',
            style: const TextStyle(color: _ProfileTheme.muted, fontSize: 12)),
        if (!_approved) ...[
          const SizedBox(height: 9),
          OutlinedButton.icon(
            onPressed: _busy ? null : _checkApproval,
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Check Approval Status'),
          ),
        ],
      ],
      const SizedBox(height: 10),
      OutlinedButton.icon(
        onPressed: _busy ? null : _back,
        icon: const Icon(Icons.arrow_back_outlined),
        label: const Text('Back to Dashboard'),
      ),
    ],
  ));

  @override
  Widget build(BuildContext context) => WillPopScope(
    onWillPop: _canLeave,
    child: Scaffold(
      backgroundColor: _ProfileTheme.page,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _ProfileTheme.ink,
        title: const Text('Doctor Profile', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w800)),
        leading: IconButton(
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh profile or check approval',
            onPressed: _busy ? null :
            _approved ? _refreshApproved : _checkApproval,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
          child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _banner(),
                  const SizedBox(height: 13),
                  _statusCard(),
                  const SizedBox(height: 13),
                  _accountCard(),
                  const SizedBox(height: 13),
                  _documentsCard(),
                  const SizedBox(height: 13),
                  _professionalCard(),
                  const SizedBox(height: 13),
                  _actions(),
                ],
              ),
            ),
          )),
        ),
      ),
    ),
  );
}
