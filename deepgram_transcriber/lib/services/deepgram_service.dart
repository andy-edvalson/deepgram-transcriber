import 'dart:convert';
import 'package:http/http.dart' as http;
import '../app_logger.dart';
import '../auth/auth_service.dart';

/// Model class for Deepgram token response
class DeepgramToken {
  final String token;
  final String url;
  final DateTime expiry;
  final bool isSuccess;
  final String message;

  DeepgramToken({
    required this.token,
    required this.url,
    required this.expiry,
    required this.isSuccess,
    required this.message,
  });

  factory DeepgramToken.fromJson(Map<String, dynamic> json) {
    return DeepgramToken(
      token: json['token'] as String,
      url: json['url'] as String,
      expiry: DateTime.parse(json['expiry'] as String),
      isSuccess: json['isSuccess'] as bool,
      message: json['message'] as String,
    );
  }

  /// Check if the token is expired
  bool get isExpired {
    // Consider token expired 5 minutes before actual expiry to be safe
    final safeExpiry = expiry.subtract(const Duration(minutes: 5));
    return DateTime.now().isAfter(safeExpiry);
  }
}

/// Service for interacting with Deepgram API
class DeepgramService {
  // Singleton pattern
  static final DeepgramService _instance = DeepgramService._internal();
  factory DeepgramService() => _instance;
  DeepgramService._internal();

  // Dependencies
  final AuthService _authService = AuthService();
  
  // Cache the token to avoid unnecessary API calls
  DeepgramToken? _cachedToken;

  /// Get a valid Deepgram token, fetching a new one if necessary
  Future<DeepgramToken?> getToken() async {
    // Return cached token if it's still valid
    if (_cachedToken != null && !_cachedToken!.isExpired) {
      logger.info('Using cached Deepgram token (expires: ${_cachedToken!.expiry})');
      return _cachedToken;
    }

    // Fetch a new token
    try {
      final token = await _fetchToken();
      _cachedToken = token;
      return token;
    } catch (e) {
      logger.error('Failed to fetch Deepgram token', error: e);
      return null;
    }
  }

  /// Fetch a new Deepgram token from the API
  Future<DeepgramToken> _fetchToken() async {
    // Ensure we have a tenant and session cookie
    final tenant = _authService.currentTenant;
    final sessionCookie = _authService.sessionCookie;
    
    if (tenant == null || sessionCookie == null) {
      throw Exception('Not authenticated. Please log in first.');
    }
    
    // Extract hostname without protocol if needed
    String hostname = tenant;
    if (!hostname.startsWith('http')) {
      hostname = 'https://$hostname';
    }
    
    // Build the API URL
    final url = '$hostname/speech_token/dg';
    logger.info('Fetching Deepgram token from: $url');
    
    // Make the authenticated API request with session cookie
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Cookie': sessionCookie,
        'Content-Type': 'application/json',
      },
    );
    
    // Handle the response
    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      final token = DeepgramToken.fromJson(jsonData);
      
      logger.info('Successfully fetched Deepgram token (expires: ${token.expiry})');
      return token;
    } else {
      logger.error('Failed to fetch Deepgram token: ${response.statusCode} ${response.body}');
      throw Exception('Failed to fetch Deepgram token: ${response.statusCode}');
    }
  }

  /// Clear the cached token
  void clearCache() {
    _cachedToken = null;
  }
}
