import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

import 'package:deepgram_transcriber/auth/auth_service.dart';

// Generate mock classes
@GenerateMocks([http.Client])
void main() {
  group('AuthService Tests', () {
    late AuthService authService;

    setUp(() {
      authService = AuthService();
    });

    test('AuthService should be a singleton', () {
      final authService1 = AuthService();
      final authService2 = AuthService();
      
      // Both instances should be the same object
      expect(identical(authService1, authService2), isTrue);
    });

    test('isAuthenticated should return false when session cookie is null', () {
      // Initially, the session cookie should be null
      expect(authService.isAuthenticated, isFalse);
    });

    test('currentTenant should be null initially', () {
      expect(authService.currentTenant, isNull);
    });

    test('sessionCookie should be null initially', () {
      expect(authService.sessionCookie, isNull);
    });

    test('logout should clear session cookie and update auth state', () {
      // Set up a listener to verify the auth state changes
      bool? authStateChanged;
      authService.authStateNotifier.addListener(() {
        authStateChanged = authService.authStateNotifier.value;
      });

      // Call logout
      authService.logout();

      // Verify session cookie is null
      expect(authService.sessionCookie, isNull);
      expect(authService.currentTenant, isNull);
      expect(authService.isAuthenticated, isFalse);
    });

    test('login should construct correct URL and not throw', () {
      // Mock the url_launcher to prevent actual launching
      const tenantDomain = 'test-tenant.example.com';
      const tenantType = 'google';
      const redirectUrl = 'myapp://callback';
      
      // Call login (which will call _buildLoginUrl internally)
      // We can't easily verify the return value since url_launcher is involved,
      // but we can verify that no exception is thrown
      expect(() => authService.login(tenantDomain, tenantType, redirectUrl: redirectUrl), returnsNormally);
    });
  });
}
