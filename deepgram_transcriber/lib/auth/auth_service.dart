import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uni_links/uni_links.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../app_logger.dart';

/// AuthService handles authentication with EasyAuth for different tenants
class AuthService {
  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  // Auth state
  String? _currentTenant;
  String? _sessionCookie;
  String? _idToken;
  String? _accessToken;
  bool _isInitialized = false;
  StreamSubscription? _deepLinkSubscription;

  // Getters
  bool get isAuthenticated => _sessionCookie != null;
  String? get sessionCookie => _sessionCookie;
  String? get idToken => _idToken;
  String? get accessToken => _accessToken;
  String? get currentTenant => _currentTenant;

  // Auth state change notifier
  final ValueNotifier<bool> authStateNotifier = ValueNotifier<bool>(false);

  /// Initialize the auth service and set up deep link handling
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Handle initial URI if the app was opened from a deep link
      final initialUri = await getInitialUri();
      if (initialUri != null) {
        await _handleDeepLink(initialUri);
      }

      // Set up listener for deep link events
      _deepLinkSubscription = uriLinkStream.listen((Uri? uri) async {
        if (uri != null) {
          await _handleDeepLink(uri);
        }
      }, onError: (error) {
        logger.error('Deep link error', error: error);
      });

      _isInitialized = true;
      logger.info('AuthService initialized');
    } on PlatformException catch (e) {
      logger.error('Failed to initialize AuthService', error: e);
    }
  }

  /// Handle incoming deep link URI
  Future<void> _handleDeepLink(Uri uri) async {
    logger.info('Received deep link: $uri');

    // Check if this is a callback URI
    // The redirectUrl in tenant_config.json is in the format "com.sayvant.vox://callback"
    if (uri.host == 'callback') {
      // Check if we have a session cookie parameter
      final sessionCookie = uri.queryParameters['session_cookie'];
      
      if (sessionCookie != null) {
        // Store the session cookie
        _sessionCookie = sessionCookie;
        logger.info('Received and stored session cookie');
        
        // Optionally fetch tokens for informational purposes
        if (_currentTenant != null) {
          await _fetchTokensFromAuthMe();
        }
        
        // Update auth state
        authStateNotifier.value = true;
        logger.info('Authentication successful (session cookie)');
      } else {
        // Check for direct tokens in the URI (fallback)
        final idToken = uri.queryParameters['id_token'];
        final accessToken = uri.queryParameters['access_token'];
        
        if (idToken != null && accessToken != null) {
          // Old flow: Direct tokens in the URI
          logger.info('Received tokens directly in URI');
          _idToken = idToken;
          _accessToken = accessToken;
          
          // Update auth state
          authStateNotifier.value = true;
          
          logger.info('Authentication successful (direct tokens)');
        } else {
          logger.warning('Deep link missing session_cookie or tokens: $uri');
        }
      }
    }
  }

  /// Fetch tokens from the /.auth/me endpoint (for informational purposes)
  Future<void> _fetchTokensFromAuthMe() async {
    try {
      if (_currentTenant == null || _sessionCookie == null) {
        throw Exception('Current tenant or session cookie is not set');
      }

      // Build the URL to fetch tokens
      final url = 'https://$_currentTenant/.auth/me';
      logger.info('Fetching tokens from: $url');

      // Make the request with the session cookie
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Cookie': _sessionCookie!,
        },
      );

      if (response.statusCode == 200) {
        // Parse the response
        final List<dynamic> authData = json.decode(response.body);
        
        if (authData.isNotEmpty) {
          final userData = authData[0];
          
          // Extract tokens based on the provider (for informational purposes only)
          // For Google
          if (userData.containsKey('id_token')) {
            _idToken = userData['id_token'];
          }
          
          if (userData.containsKey('access_token')) {
            _accessToken = userData['access_token'];
          }
          
          // For AAD/OpenID
          if (userData.containsKey('id_token_aad')) {
            _idToken = userData['id_token_aad'];
          }
          
          if (userData.containsKey('access_token_aad')) {
            _accessToken = userData['access_token_aad'];
          }
          
          logger.info('Successfully fetched auth info from /.auth/me');
        } else {
          logger.error('Empty response from /.auth/me');
        }
      } else {
        // Handle error
        logger.error('Failed to fetch tokens: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      logger.error('Error fetching tokens from /.auth/me', error: e);
    }
  }

  /// Build the EasyAuth login URL for a specific tenant
  String _buildLoginUrl(String tenantDomain, String tenantType, String? redirectUrl) {
    // Generate a random state parameter for CSRF protection
    final state = base64Encode(List<int>.generate(32, (_) => DateTime.now().microsecondsSinceEpoch % 256));
    
    // Build the EasyAuth URL
    final baseUrl = 'https://$tenantDomain/.auth/login/$tenantType';
    
    // Use the provided redirectUrl or fall back to the default
    final backendRedirectUrl = 'https://$tenantDomain/mobile-redirect';
    
    // Log the redirect URL being used
    logger.info('Using app redirect URL from config: $redirectUrl');
    
    // Parse the redirect URL to extract the scheme and host for deep link handling
    if (redirectUrl != null) {
      try {
        final redirectUri = Uri.parse(redirectUrl);
        logger.info('Parsed redirect URI - scheme: ${redirectUri.scheme}, host: ${redirectUri.host}');
      } catch (e) {
        logger.warning('Failed to parse redirect URL: $redirectUrl', error: e);
      }
    }
    
    return '$baseUrl?post_login_redirect_url=${Uri.encodeComponent(backendRedirectUrl)}&state=$state';
  }

  /// Launch the login flow for a specific tenant
  Future<bool> login(String tenantDomain, String tenantType, {String? redirectUrl}) async {
    try {
      _currentTenant = tenantDomain;
      
      // Build the auth URL
      final authUrl = _buildLoginUrl(tenantDomain, tenantType, redirectUrl);
      logger.info('Launching auth URL: $authUrl');
      
      // Launch the URL in an external browser
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      } else {
        logger.error('Cannot launch URL: $authUrl');
        return false;
      }
    } catch (e) {
      logger.error('Error launching login URL', error: e);
      return false;
    }
  }

  /// Log out the current user
  void logout() {
    _sessionCookie = null;
    _idToken = null;
    _accessToken = null;
    _currentTenant = null;
    authStateNotifier.value = false;
    logger.info('User logged out');
  }

  /// Clean up resources
  void dispose() {
    _deepLinkSubscription?.cancel();
    _isInitialized = false;
  }
}
