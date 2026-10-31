
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:family_care/main.dart';
import 'package:family_care/screens/auth/signup_screen.dart';

// =====================================================
// FAMILY CARE - SIGN-UP WIDGET TESTS
// =====================================================

// Helper: Tap widgets inside scrollable pages.
Future<void> tapVisible(
    WidgetTester tester,
    Finder finder,
    ) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

// Helper: Enter text into a signup field.
Future<void> enterField(
    WidgetTester tester,
    String fieldName,
    String value,
    ) async {
  final field = find.byKey(ValueKey(fieldName));

  await tester.ensureVisible(field);
  await tester.pumpAndSettle();

  await tester.enterText(field, value);
  await tester.pump();
}

// Helper: Fill common registration fields.
Future<void> fillCommonFields(
    WidgetTester tester,
    ) async {
  await enterField(
    tester,
    'Full Name',
    'Test User',
  );

  await enterField(
    tester,
    'Mobile Number',
    '9876543210',
  );

  await enterField(
    tester,
    'Email Address',
    'test@example.com',
  );
}

void main() {

  // ===================================================
  // TEST 1 - APP LAUNCH
  // ===================================================

  testWidgets(
    'Family Care signup page launches successfully',
        (WidgetTester tester) async {

      await tester.pumpWidget(
        const FamilyCareApp(),
      );

      // Check branding.
      expect(
        find.text('FAMILY CARE'),
        findsOneWidget,
      );

      // Check signup heading.
      expect(
        find.text('Create your account'),
        findsOneWidget,
      );

      // Check role selection.
      expect(
        find.text('Choose Account Type'),
        findsOneWidget,
      );

      expect(
        find.text('Patient'),
        findsOneWidget,
      );

      expect(
        find.text('Doctor'),
        findsOneWidget,
      );

      // Patient registration is default.
      expect(
        find.text('Patient Registration'),
        findsOneWidget,
      );

      // Verify patient fields.
      expect(
        find.text('Full Name'),
        findsOneWidget,
      );

      expect(
        find.text('Mobile Number'),
        findsOneWidget,
      );

      expect(
        find.text('Email Address'),
        findsOneWidget,
      );

      expect(
        find.text('Password'),
        findsOneWidget,
      );

      expect(
        find.text('Confirm Password'),
        findsOneWidget,
      );

      // Registration number must not appear.
      expect(
        find.text('Medical Registration No.'),
        findsNothing,
      );
    },
  );

  // ===================================================
  // TEST 2 - ROLE SWITCHING
  // ===================================================

  testWidgets(
    'Doctor and Patient roles switch correctly',
        (WidgetTester tester) async {

      await tester.pumpWidget(
        const FamilyCareApp(),
      );

      // Select Doctor.
      await tapVisible(
        tester,
        find.text('Doctor'),
      );

      expect(
        find.text('Doctor Registration'),
        findsOneWidget,
      );

      expect(
        find.text('Medical Registration No.'),
        findsOneWidget,
      );

      expect(
        find.text('Password'),
        findsOneWidget,
      );

      expect(
        find.text('Confirm Password'),
        findsOneWidget,
      );

      // Switch back to Patient.
      await tapVisible(
        tester,
        find.text('Patient'),
      );

      expect(
        find.text('Patient Registration'),
        findsOneWidget,
      );

      expect(
        find.text('Medical Registration No.'),
        findsNothing,
      );
    },
  );

  // ===================================================
  // TEST 3 - PASSWORD MATCHING
  // ===================================================

  testWidgets(
    'Signup rejects mismatched passwords',
        (WidgetTester tester) async {

      SignupData? submittedData;

      await tester.pumpWidget(
        MaterialApp(
          home: SignupScreen(
            onContinue: (data) {
              submittedData = data;
            },
          ),
        ),
      );

      await fillCommonFields(tester);

      await enterField(
        tester,
        'Password',
        'SecurePass123!',
      );

      await enterField(
        tester,
        'Confirm Password',
        'WrongPassword123',
      );

      // Submit the form.
      await tapVisible(
        tester,
        find.text('Continue to Verification'),
      );

      // Confirm mismatch validation.
      expect(
        find.text('Passwords do not match'),
        findsOneWidget,
      );

      // Invalid form must not continue.
      expect(submittedData, isNull);
    },
  );

  // ===================================================
  // TEST 4 - PATIENT REGISTRATION
  // ===================================================

  testWidgets(
    'Patient signup passes valid details',
        (WidgetTester tester) async {

      SignupData? submittedData;

      await tester.pumpWidget(
        MaterialApp(
          home: SignupScreen(
            onContinue: (data) {
              submittedData = data;
            },
          ),
        ),
      );

      await fillCommonFields(tester);

      await enterField(
        tester,
        'Password',
        'SecurePass123!',
      );

      await enterField(
        tester,
        'Confirm Password',
        'SecurePass123!',
      );

      await tapVisible(
        tester,
        find.text('Continue to Verification'),
      );

      expect(
        submittedData,
        isNotNull,
      );

      expect(
        submittedData!.role,
        SignupRole.patient,
      );

      expect(
        submittedData!.name,
        'Test User',
      );

      expect(
        submittedData!.mobile,
        '+919876543210',
      );

      expect(
        submittedData!.email,
        'test@example.com',
      );

      expect(
        submittedData!.password,
        'SecurePass123!',
      );

      expect(
        submittedData!.registrationNumber,
        isNull,
      );
    },
  );

  // ===================================================
  // TEST 5 - DOCTOR REGISTRATION
  // ===================================================

  testWidgets(
    'Doctor signup passes valid professional details',
        (WidgetTester tester) async {

      SignupData? submittedData;

      await tester.pumpWidget(
        MaterialApp(
          home: SignupScreen(
            onContinue: (data) {
              submittedData = data;
            },
          ),
        ),
      );

      // Switch to Doctor.
      await tapVisible(
        tester,
        find.text('Doctor'),
      );

      await enterField(
        tester,
        'Full Name',
        'Dr Test User',
      );

      await enterField(
        tester,
        'Mobile Number',
        '9876543210',
      );

      await enterField(
        tester,
        'Email Address',
        'doctor@example.com',
      );

      await enterField(
        tester,
        'Medical Registration No.',
        'DL-123456',
      );

      await enterField(
        tester,
        'Password',
        'DoctorPass123!',
      );

      await enterField(
        tester,
        'Confirm Password',
        'DoctorPass123!',
      );

      await tapVisible(
        tester,
        find.text('Continue to Verification'),
      );

      expect(
        submittedData,
        isNotNull,
      );

      expect(
        submittedData!.role,
        SignupRole.doctor,
      );

      expect(
        submittedData!.name,
        'Dr Test User',
      );

      expect(
        submittedData!.email,
        'doctor@example.com',
      );

      expect(
        submittedData!.registrationNumber,
        'DL-123456',
      );

      expect(
        submittedData!.password,
        'DoctorPass123!',
      );
    },
  );
}
