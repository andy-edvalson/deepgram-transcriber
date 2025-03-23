import 'package:flutter_test/flutter_test.dart';
import 'package:deepgram_transcriber/services/deepgram_service.dart';

void main() {
  group('DeepgramService Tests', () {
    late DeepgramService deepgramService;

    setUp(() {
      deepgramService = DeepgramService();
    });

    test('DeepgramService should be a singleton', () {
      final service1 = DeepgramService();
      final service2 = DeepgramService();
      
      // Both instances should be the same object
      expect(identical(service1, service2), isTrue);
    });

    test('DeepgramToken should correctly parse JSON', () {
      // Test data
      final json = {
        'token': 'test_token',
        'url': 'https://api.deepgram.com',
        'expiry': '2025-01-01T00:00:00Z',
        'isSuccess': true,
        'message': 'Success'
      };
      
      // Create token from JSON
      final token = DeepgramToken.fromJson(json);
      
      // Verify properties
      expect(token.token, 'test_token');
      expect(token.url, 'https://api.deepgram.com');
      expect(token.expiry, DateTime.parse('2025-01-01T00:00:00Z'));
      expect(token.isSuccess, true);
      expect(token.message, 'Success');
    });

    test('DeepgramToken.isExpired should return true for expired tokens', () {
      // Create a token that expired 10 minutes ago
      final expiredToken = DeepgramToken(
        token: 'test_token',
        url: 'https://api.deepgram.com',
        expiry: DateTime.now().subtract(const Duration(minutes: 10)),
        isSuccess: true,
        message: 'Success'
      );
      
      // Verify it's expired
      expect(expiredToken.isExpired, isTrue);
    });

    test('DeepgramToken.isExpired should return false for valid tokens', () {
      // Create a token that expires 1 hour from now
      final validToken = DeepgramToken(
        token: 'test_token',
        url: 'https://api.deepgram.com',
        expiry: DateTime.now().add(const Duration(hours: 1)),
        isSuccess: true,
        message: 'Success'
      );
      
      // Verify it's not expired
      expect(validToken.isExpired, isFalse);
    });

    test('DeepgramToken.isExpired should consider the 5-minute safety margin', () {
      // Create a token that expires 3 minutes from now (within the 5-minute safety margin)
      final almostExpiredToken = DeepgramToken(
        token: 'test_token',
        url: 'https://api.deepgram.com',
        expiry: DateTime.now().add(const Duration(minutes: 3)),
        isSuccess: true,
        message: 'Success'
      );
      
      // Verify it's considered expired due to the safety margin
      expect(almostExpiredToken.isExpired, isTrue);
    });

    test('clearCache should clear the cached token', () {
      // Call clearCache
      deepgramService.clearCache();
      
      // We can't directly verify the private _cachedToken field,
      // but we can verify that the method doesn't throw an exception
      expect(() => deepgramService.clearCache(), returnsNormally);
    });
  });
}
