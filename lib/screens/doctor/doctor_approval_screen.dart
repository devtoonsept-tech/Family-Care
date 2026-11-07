
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../auth/login_screen.dart';

/// FamilyCare+ • Doctor Approval • Backend v10.
///
/// This is a doctor-facing STATUS screen, not an admin approval screen.
/// POST /api/v1/doctors/approval-status accepts doctor credentials and returns
/// the current decision. It does NOT issue clinical or profile-setup tokens.
class DoctorApprovalScreen extends StatefulWidget {
  const DoctorApprovalScreen({
    super.key,
    this.apiBaseUrl = const String.fromEnvironment(
      'FAMILY_CARE_API_URL',
      defaultValue: '',
    ),
    this.initialUser,
    this.doctorName = '',
    this.email = '',
    this.approvalStatus = 'UNKNOWN',
    this.accountStatus = 'UNKNOWN',
    this.emailVerified = false,
    this.rejectionReason,
    this.setupToken,
    this.onOpenProfile,
    this.onGoToLogin,
    this.onBack,
    this.onStatusChanged,
  });

  final String apiBaseUrl;
  final Map<String, dynamic>? initialUser;
  final String doctorName;
  final String email;
  final String approvalStatus;
  final String accountStatus;
  final bool emailVerified;
  final String? rejectionReason;
  final String? setupToken;

  final VoidCallback? onOpenProfile;
  final VoidCallback? onGoToLogin;
  final VoidCallback? onBack;
  final ValueChanged<Map<String, dynamic>>? onStatusChanged;

  @override
  State<DoctorApprovalScreen> createState() =>
      _DoctorApprovalScreenState();
}

class _AC {
  static const page = Color(0xFFF4FAF9);
  static const ink = Color(0xFF214C52);
  static const green = Color(0xFF217C6D);
  static const blue = Color(0xFF4D84AA);
  static const teal = Color(0xFF138B82);
  static const mint = Color(0xFFE7F6EF);
  static const ice = Color(0xFFEAF4F9);
  static const border = Color(0xFFDCEBE7);
  static const muted = Color(0xFF70888A);
  static const amber = Color(0xFFAB7C2E);
  static const red = Color(0xFFB4535B);
}

class _ApprovalFailure implements Exception {
  const _ApprovalFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DoctorApprovalScreenState extends State<DoctorApprovalScreen> {
  final http.Client _client = http.Client();

  late String _name;
  late String _email;
  late String _status;
  late String _accountStatus;
  late String _reason;
  late String _publicId;
  late String _setupToken;
  late bool _emailVerified;

  bool _checking = false;
  bool _leaving = false;
  int _requestVersion = 0;
  String? _error;
  DateTime? _lastChecked;

  static String _s(dynamic value) =>
      (value ?? '').toString().trim();

  static Map<String, dynamic> _m(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  String get _baseUrl {
    var base = widget.apiBaseUrl.trim();

    if (base.isEmpty) {
      base = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? 'http://10.0.2.2:5001'
          : 'http://127.0.0.1:5001';
    }

    base = base.replaceFirst(RegExp(r'/+$'), '');

    for (final suffix in const ['/api/v1/doctors', '/api/v1']) {
      if (base.endsWith(suffix)) {
        return base.substring(0, base.length - suffix.length);
      }
    }

    return base;
  }

  bool get _approved => _status == 'APPROVED';
  bool get _pending => _status == 'PENDING_APPROVAL';
  bool get _rejected => _status == 'REJECTED';
  bool get _profileRequired => _status == 'PROFILE_REQUIRED';
  bool get _accountActive => _accountStatus == 'ACTIVE';
  bool get _restricted => _accountStatus == 'SUSPENDED';
  bool get _profileNeedsEditing => _profileRequired || _rejected;

  bool get _canOpenProfile =>
      _accountActive &&
          _emailVerified &&
          _profileNeedsEditing &&
          _setupToken.isNotEmpty &&
          widget.onOpenProfile != null;

  bool get _busy => _checking || _leaving;

  @override
  void initState() {
    super.initState();
    _setInitial();
  }

  @override
  void didUpdateWidget(covariant DoctorApprovalScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialUser != widget.initialUser ||
        oldWidget.doctorName != widget.doctorName ||
        oldWidget.email != widget.email ||
        oldWidget.approvalStatus != widget.approvalStatus ||
        oldWidget.accountStatus != widget.accountStatus ||
        oldWidget.emailVerified != widget.emailVerified ||
        oldWidget.rejectionReason != widget.rejectionReason ||
        oldWidget.setupToken != widget.setupToken ||
        oldWidget.apiBaseUrl != widget.apiBaseUrl) {
      ++_requestVersion;
      _setInitial();
    }
  }

  void _setInitial() {
    final wrapper = _m(widget.initialUser);
    final nested = _m(wrapper['user']);
    final user = nested.isNotEmpty ? nested : wrapper;

    _name = _s(user['full_name']).isNotEmpty
        ? _s(user['full_name'])
        : widget.doctorName.trim();

    _email = _s(user['email']).isNotEmpty
        ? _s(user['email'])
        : widget.email.trim();

    _status = (_s(user['approval_status']).isNotEmpty
        ? _s(user['approval_status'])
        : widget.approvalStatus)
        .trim()
        .toUpperCase();

    _accountStatus = (_s(user['account_status']).isNotEmpty
        ? _s(user['account_status'])
        : widget.accountStatus)
        .trim()
        .toUpperCase();

    _emailVerified = user['email_verified'] is bool
        ? user['email_verified'] as bool
        : widget.emailVerified;

    _reason = widget.rejectionReason != null
        ? widget.rejectionReason!.trim()
        : _s(wrapper['rejection_reason']).isNotEmpty
        ? _s(wrapper['rejection_reason'])
        : _s(user['rejection_reason']);

    _publicId = _s(user['public_id']);

    // Setup tokens come from doctor login/onboarding.
    // The approval-status endpoint does not issue them.
    _setupToken = _s(widget.setupToken).isNotEmpty
        ? _s(widget.setupToken)
        : _s(wrapper['setup_token']);

    _error = null;
    _lastChecked = null;
    _checking = false;
    _leaving = false;
  }

  @override
  void dispose() {
    ++_requestVersion;
    _client.close();
    super.dispose();
  }

  String _friendly(Object error) {
    if (error is _ApprovalFailure) return error.message;

    if (error is TimeoutException) {
      return 'Request timed out. Please retry.';
    }

    if (error is http.ClientException) {
      return 'Could not reach FamilyCare+. Check the backend address and network.';
    }

    if (error is FormatException) {
      return 'Invalid response from the server.';
    }

    return 'Unable to check approval status. Please retry.';
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? _AC.red : _AC.ink,
        ),
      );
  }

  Future<String?> _requestPassword() => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordDialog(email: _email),
  );

  // ============================================================
  // BACKEND V10 APPROVAL STATUS
  // ============================================================

  Future<void> _checkStatus() async {
    if (_busy) return;

    if (_email.isEmpty) {
      _toast(
        'Doctor email unavailable. Please sign in again.',
        error: true,
      );
      return;
    }

    final password = await _requestPassword();

    if (!mounted ||
        password == null ||
        password.isEmpty ||
        _busy) {
      return;
    }

    final version = ++_requestVersion;

    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      // Password check, NOT a clinical login.
      final response = await _client
          .post(
        Uri.parse('$_baseUrl/api/v1/doctors/approval-status'),
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': _email,
          'password': password,
        }),
      )
          .timeout(const Duration(seconds: 25));

      Map<String, dynamic> data = {};

      if (response.bodyBytes.isNotEmpty) {
        final decoded = jsonDecode(
          utf8.decode(response.bodyBytes),
        );

        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        } else if (response.statusCode >= 200 &&
            response.statusCode < 300) {
          throw const FormatException('Expected a JSON object.');
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final server = data['error'];

        final detail = server is Map
            ? _s(server['message'])
            : _s(server);

        final fallback = switch (response.statusCode) {
          401 => 'Incorrect doctor email or password.',
          403 => 'Doctor account is restricted.',
          429 => 'Too many attempts. Please try again later.',
          _ => 'Approval check failed (HTTP ${response.statusCode}).',
        };

        throw _ApprovalFailure(
          detail.isNotEmpty ? detail : fallback,
        );
      }

      final newStatus = _s(
        data['approval_status'],
      ).toUpperCase();

      if (!const {
        'PROFILE_REQUIRED',
        'PENDING_APPROVAL',
        'APPROVED',
        'REJECTED',
      }.contains(newStatus) ||
          _s(data['account_status']).isEmpty ||
          data['email_verified'] is! bool) {
        throw const FormatException(
          'Incomplete doctor approval response.',
        );
      }

      if (!mounted || version != _requestVersion) return;

      final changed = newStatus != _status;

      setState(() {
        _status = newStatus;
        _accountStatus = _s(
          data['account_status'],
        ).toUpperCase();

        _emailVerified = data['email_verified'] as bool;

        if (_s(data['public_id']).isNotEmpty) {
          _publicId = _s(data['public_id']);
        }

        _reason = _s(data['rejection_reason']);
        _lastChecked = DateTime.now();

        // A status check cannot renew login/setup tokens.
        // Invalidate old setup token when the decision changes.
        if (changed) {
          _setupToken = '';
        }
      });

      try {
        widget.onStatusChanged?.call(
          Map<String, dynamic>.from(data),
        );
      } catch (_) {
        // Status was still obtained successfully from the server.
      }

      _toast('Current status: ${_statusName(newStatus)}.');
    } catch (error) {
      if (mounted && version == _requestVersion) {
        setState(() {
          _error = _friendly(error);
        });
      }
    } finally {
      if (mounted && version == _requestVersion) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  // ============================================================
  // FRESH LOGIN
  // ============================================================

  Future<void> _goToLogin() async {
    if (_busy) return;

    setState(() {
      _leaving = true;
    });

    try {
      // Admin approval/rejection revokes previous sessions.
      await FamilyCareSession.clear();

      if (!mounted) return;

      if (widget.onGoToLogin != null) {
        widget.onGoToLogin!();
      } else {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute<void>(
            builder: (_) => LoginScreen(
              apiBaseUrl: _baseUrl,
            ),
          ),
              (_) => false,
        );
      }
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _leaving = false;
      });

      _toast(
        'Could not clear the local session. Please retry.',
        error: true,
      );
    }
  }

  void _openProfile() {
    if (!_canOpenProfile || _busy) return;
    widget.onOpenProfile!();
  }

  void _back() {
    if (_busy) return;

    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  // ============================================================
  // STATUS HELPERS
  // ============================================================

  String _statusName(String status) => switch (status) {
    'PROFILE_REQUIRED' => 'Profile required',
    'PENDING_APPROVAL' => 'Pending admin review',
    'APPROVED' => 'Approved',
    'REJECTED' => 'Changes requested',
    _ => 'Status unavailable',
  };

  Color get _accent => _restricted || _rejected
      ? _AC.red
      : _approved
      ? _AC.green
      : _pending
      ? _AC.amber
      : _AC.blue;

  IconData get _statusIcon => _restricted
      ? Icons.block_rounded
      : _approved
      ? Icons.verified_rounded
      : _rejected
      ? Icons.report_gmailerrorred_outlined
      : _pending
      ? Icons.hourglass_top_rounded
      : Icons.assignment_ind_outlined;

  String get _description {
    if (_restricted) {
      return 'Your doctor account is suspended. Contact FamilyCare+ support.';
    }

    if (!_emailVerified) {
      return 'Email verification is required before doctor onboarding can continue.';
    }

    if (_approved) {
      return 'Your application is approved. Sign in again to get a valid doctor session and access the clinical dashboard.';
    }

    if (_rejected) {
      return 'The admin requested corrections. Sign in again for a fresh setup token, update your professional profile, and resubmit.';
    }

    if (_profileRequired) {
      return 'Complete the required professional information and submit it for review. Doctor profile photo and degree image are optional.';
    }

    if (_pending) {
      return 'Your professional profile has been submitted. An admin must review it before clinical access becomes available.';
    }

    return 'Check your approval status, or sign in again to continue onboarding.';
  }

  // ============================================================
  // COMMON UI
  // ============================================================

  Widget _card(Widget content) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: _AC.border),
    ),
    child: content,
  );

  Widget _header() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF176B6F),
          Color(0xFF288F82),
          Color(0xFF62B2A3),
        ],
      ),
    ),
    child: Row(
      children: [
        Container(
          height: 55,
          width: 55,
          decoration: BoxDecoration(
            color: const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(
            Icons.medical_services_outlined,
            color: Colors.white,
            size: 29,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'FAMILYCARE+ • DOCTOR',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Doctor Approval',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _name.isEmpty ? 'Application status' : _name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  // ============================================================
  // APPROVAL STATUS CARD
  // ============================================================

  Widget _statusCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _accent.withAlpha(22),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                _statusIcon,
                color: _accent,
                size: 25,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _restricted
                        ? 'Account restricted'
                        : _statusName(_status),
                    style: TextStyle(
                      color: _accent,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _email.isEmpty ? 'Email unavailable' : _email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _AC.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _description,
          style: const TextStyle(
            color: _AC.muted,
            fontSize: 12,
            height: 1.5,
          ),
        ),
        if (_rejected && _reason.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF2F1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Admin feedback: $_reason',
              style: const TextStyle(
                color: _AC.red,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(
              color: _AC.red,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
        if (_checking) ...[
          const SizedBox(height: 13),
          const LinearProgressIndicator(color: _AC.green),
        ],
      ],
    ),
  );

  // ============================================================
  // APPLICATION PROGRESS
  // ============================================================

  Widget _progressStep({
    required String title,
    required String detail,
    required IconData icon,
    required bool done,
    bool needsAction = false,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: needsAction
                  ? _AC.red.withAlpha(20)
                  : done
                  ? _AC.mint
                  : _AC.ice,
            ),
            child: Icon(
              needsAction
                  ? Icons.priority_high_rounded
                  : done
                  ? Icons.check_rounded
                  : icon,
              size: 17,
              color: needsAction
                  ? _AC.red
                  : done
                  ? _AC.green
                  : _AC.blue,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _AC.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: const TextStyle(
                    color: _AC.muted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _steps() {
    final submitted = _pending || _approved || _rejected;

    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Application Progress',
            style: TextStyle(
              color: _AC.ink,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 17),
          _progressStep(
            title: 'Email verification',
            detail: _emailVerified
                ? 'Verified'
                : 'Verification required',
            icon: Icons.alternate_email_rounded,
            done: _emailVerified,
          ),
          const SizedBox(height: 18),
          _progressStep(
            title: 'Professional profile',
            detail: _rejected
                ? 'Submitted previously • corrections requested'
                : submitted
                ? 'Submitted for admin review'
                : 'Professional information must be completed',
            icon: Icons.badge_outlined,
            done: submitted && !_rejected,
            needsAction: _rejected,
          ),
          const SizedBox(height: 18),
          _progressStep(
            title: 'Admin review',
            detail: _approved
                ? 'Approved'
                : _rejected
                ? 'Rejected • review corrections and resubmit'
                : _pending
                ? 'Awaiting admin decision'
                : 'Starts after profile submission',
            icon: Icons.verified_user_outlined,
            done: _approved,
            needsAction: _rejected,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // NEXT ACTIONS
  // ============================================================

  Widget _actions() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Next Step',
          style: TextStyle(
            color: _AC.ink,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _restricted
              ? 'Account access is restricted. Contact support or return to login.'
              : _approved
              ? 'The status check cannot log you in. Use a fresh approved doctor login.'
              : _pending
              ? 'You can recheck the decision using your password at any time.'
              : _profileNeedsEditing && !_canOpenProfile
              ? 'Sign in to get a fresh profile-setup token, then continue.'
              : 'Continue your doctor onboarding.',
          style: const TextStyle(
            color: _AC.muted,
            fontSize: 12,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 15),

        if (!_restricted &&
            _accountActive &&
            _emailVerified &&
            _profileNeedsEditing) ...[
          FilledButton.icon(
            onPressed: _busy
                ? null
                : _canOpenProfile
                ? _openProfile
                : _goToLogin,
            icon: const Icon(Icons.edit_note_outlined),
            label: Text(
              _canOpenProfile
                  ? 'Open Profile Setup'
                  : 'Sign In to Edit Profile',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _AC.green,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 9),
        ],

        if (!_restricted && _approved && _accountActive) ...[
          FilledButton.icon(
            onPressed: _busy ? null : _goToLogin,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Sign In to Doctor Dashboard'),
            style: FilledButton.styleFrom(
              backgroundColor: _AC.green,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 9),
        ],

        if (_pending) ...[
          const Text(
            'Patient records and appointments remain locked until approval and a new doctor login.',
            style: TextStyle(
              color: _AC.muted,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
        ],

        OutlinedButton.icon(
          onPressed: _busy ? null : _checkStatus,
          icon: _checking
              ? const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Icon(Icons.refresh_rounded),
          label: Text(
            _checking
                ? 'Checking Status...'
                : 'Check Approval Status',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: _AC.green,
            side: const BorderSide(color: _AC.border),
            minimumSize: const Size.fromHeight(48),
          ),
        ),

        if (_lastChecked != null) ...[
          const SizedBox(height: 8),
          Text(
            'Last checked: ${_checkedLabel(_lastChecked!)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _AC.muted,
              fontSize: 11,
            ),
          ),
        ],

        const SizedBox(height: 4),
        TextButton(
          onPressed: _busy ? null : _goToLogin,
          child: const Text('Return to Login'),
        ),
      ],
    ),
  );

  String _checkedLabel(DateTime value) {
    final local = value.toLocal();

    String pad(int n) => n.toString().padLeft(2, '0');

    return '${pad(local.day)}/${pad(local.month)}/${local.year} '
        '${pad(local.hour)}:${pad(local.minute)}';
  }

  // ============================================================
  // MAIN SCREEN
  // ============================================================

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _AC.page,
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _AC.ink,
      elevation: 0,
      title: const Text(
        'Doctor Approval',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
        ),
      ),
      leading: IconButton(
        tooltip: 'Back',
        onPressed: _busy ? null : _back,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      actions: [
        IconButton(
          tooltip: 'Check approval status',
          onPressed: _busy ? null : _checkStatus,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  const SizedBox(height: 13),
                  _statusCard(),
                  const SizedBox(height: 13),
                  _steps(),
                  const SizedBox(height: 13),
                  _actions(),

                  if (_publicId.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(
                      'Doctor ID: $_publicId',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _AC.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],

                  const SizedBox(height: 17),
                  const Text(
                    'FamilyCare+ • Doctor approval is managed by admins.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _AC.muted,
                      fontSize: 11,
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

// ============================================================
// PASSWORD DIALOG
// ============================================================

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.email});

  final String email;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();

  bool _visible = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState?.validate() != true) return;

    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Check Doctor Status'),
    scrollable: true,
    content: SizedBox(
      width: 380,
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.email,
              style: const TextStyle(
                color: _AC.muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 13),
            TextFormField(
              controller: _password,
              autofocus: true,
              obscureText: !_visible,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Doctor account password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _visible
                      ? 'Hide password'
                      : 'Show password',
                  onPressed: () {
                    setState(() {
                      _visible = !_visible;
                    });
                  },
                  icon: Icon(
                    _visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (value) => (value ?? '').isEmpty
                  ? 'Enter your password'
                  : null,
            ),
            const SizedBox(height: 10),
            const Text(
              'Password is sent only for this status check. This does not sign you in.',
              style: TextStyle(
                color: _AC.muted,
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        style: FilledButton.styleFrom(
          backgroundColor: _AC.green,
        ),
        child: const Text('Check Status'),
      ),
    ],
  );
}
