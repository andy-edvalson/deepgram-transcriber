import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
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
  
  // App links instance for deep linking
  final AppLinks _appLinks = AppLinks();
  
  // Flag to track if we're running on web
  final bool _isWeb = kIsWeb;

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
      if (!_isWeb) {
        // Mobile platform: Use app_links for deep linking
        
        // Handle initial URI if the app was opened from a deep link
        final initialUri = await _appLinks.getInitialLink();
        if (initialUri != null) {
          await _handleDeepLink(initialUri);
        }

        // Set up listener for deep link events
        _deepLinkSubscription = _appLinks.uriLinkStream.listen((Uri uri) async {
          await _handleDeepLink(uri);
        }, onError: (error) {
          logger.error('Deep link error', error: error);
        });
        
        logger.info('Mobile deep linking initialized with app_links');
      } else {
        // Web platform: We'll handle authentication differently
        logger.info('Running on web platform - using web-specific auth handling');
        
        // For web, we'll rely on the JavaScript in index.html to handle auth tokens
        // and we'll check for URL parameters directly
        
        // Check the current URL for auth parameters
        try {
          final uri = Uri.base;
          if (uri.queryParameters.containsKey('session_cookie') || 
              uri.queryParameters.containsKey('id_token')) {
            await _handleDeepLink(uri);
          }
        } catch (e) {
          logger.error('Error checking URL parameters', error: e);
        }
      }

      _isInitialized = true;
      logger.info('AuthService initialized for ${_isWeb ? 'web' : 'mobile'} platform');
    } on PlatformException catch (e) {
      logger.error('Failed to initialize AuthService', error: e);
    }
  }

  /// Handle incoming deep link URI
  Future<void> _handleDeepLink(Uri uri) async {
    logger.info('Received deep link: $uri');

    // For web platform, we handle any URI
    // For mobile, we specifically look for the callback host
    bool isValidCallback = _isWeb || uri.host == 'callback';

    if (isValidCallback) {
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
    
    // Default backend redirect URL
    String backendRedirectUrl = 'https://$tenantDomain/mobile-redirect';
    
    // For web platform, we need a different approach to handle redirects
    if (_isWeb && redirectUrl != null) {
      try {
        // For web, we want the backend to redirect back to our web app
        // We'll use the current URL as the post_login_redirect_url
        backendRedirectUrl = redirectUrl;
        logger.info('Using web redirect flow with URL: $backendRedirectUrl');
      } catch (e) {
        logger.warning('Failed to parse web redirect URL: $redirectUrl', error: e);
      }
    } else {
      // Log the redirect URL being used for mobile
      logger.info('Using mobile app redirect URL from config: $redirectUrl');
      
      // Parse the redirect URL to extract the scheme and host for deep link handling
      if (redirectUrl != null) {
        try {
          final redirectUri = Uri.parse(redirectUrl);
          logger.info('Parsed redirect URI - scheme: ${redirectUri.scheme}, host: ${redirectUri.host}');
        } catch (e) {
          logger.warning('Failed to parse redirect URL: $redirectUrl', error: e);
        }
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
      
      // Launch the URL based on platform
      final uri = Uri.parse(authUrl);
      
      if (_isWeb) {
        // For web, we use a different launch mode that works better with web auth flows
        // This will navigate in the current tab, which is more appropriate for web auth
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, webOnlyWindowName: '_self');
          return true;
        }
      } else {
        // For mobile, launch in external browser as before
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return true;
        }
      }
      
      logger.error('Cannot launch URL: $authUrl');
      return false;
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
    if (!_isWeb) {
      _deepLinkSubscription?.cancel();
    }
    _isInitialized = false;
  }
}
