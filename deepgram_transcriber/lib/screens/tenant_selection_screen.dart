import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../auth/auth_service.dart';
import '../app_logger.dart';

class TenantSelectionScreen extends StatefulWidget {
  const TenantSelectionScreen({super.key});

  @override
  State<TenantSelectionScreen> createState() => _TenantSelectionScreenState();
}

class _TenantSelectionScreenState extends State<TenantSelectionScreen> {
  final AuthService _authService = AuthService();
  Map<String, dynamic> _tenantConfig = {};
  bool _isLoading = true;
  String? _errorMessage;
  
  // Controllers for manual tenant entry
  final TextEditingController _tenantDomainController = TextEditingController();
  final TextEditingController _tenantHostnameController = TextEditingController();
  final TextEditingController _tenantTypeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTenantConfig();
  }
  
  @override
  void dispose() {
    _tenantDomainController.dispose();
    _tenantHostnameController.dispose();
    _tenantTypeController.dispose();
    super.dispose();
  }

  Future<void> _loadTenantConfig() async {
    try {
      // Load tenant configuration from the JSON file
      final String jsonString = await rootBundle.loadString('assets/tenant_config.json');
      if (jsonString.isEmpty) {
        throw Exception('Tenant configuration file is empty');
      }
      
      final Map<String, dynamic> jsonData = json.decode(jsonString);
      if (jsonData.isEmpty) {
        throw Exception('No tenants found in configuration');
      }
      
      setState(() {
        _tenantConfig = jsonData;
        _isLoading = false;
      });
      
      logger.info('Loaded tenant configuration with ${_tenantConfig.length} tenants');
    } catch (e) {
      logger.error('Error loading tenant configuration', error: e);
      
      // Provide a more user-friendly error message
      String errorMsg;
      if (e.toString().contains('Unable to load asset')) {
        errorMsg = 'Could not find tenant configuration file. Please make sure assets/tenant_config.json exists.';
      } else if (e.toString().contains('empty')) {
        errorMsg = 'Tenant configuration file is empty. Please add tenant information to assets/tenant_config.json.';
      } else {
        errorMsg = 'Failed to load tenant configuration: $e';
      }
      
      setState(() {
        _errorMessage = errorMsg;
        _isLoading = false;
      });
    }
  }

  Future<void> _loginWithTenant(String tenantDomain, Map<String, dynamic> tenantData) async {
    try {
      // Extract the authentication type from tenant data
      final String authType = tenantData['type'] as String;
      
      // Get the hostname from tenant data
      final String? hostname = tenantData['hostname'] as String?;
      if (hostname == null) {
        throw Exception('Hostname is missing in tenant configuration');
      }
      
      // Extract hostname without protocol
      String cleanHostname = hostname;
      if (hostname.startsWith('https://')) {
        cleanHostname = hostname.substring(8); // Remove 'https://'
      } else if (hostname.startsWith('http://')) {
        cleanHostname = hostname.substring(7); // Remove 'http://'
      }
      
      // Get the redirectUrl from tenant data
      final String? redirectUrl = tenantData['redirectUrl'] as String?;
      
      // Log the hostname and redirect URL being used
      logger.info('Using hostname: $cleanHostname and redirect URL: $redirectUrl for tenant: $tenantDomain');
      
      // Map the tenant config auth type to EasyAuth provider
      String easyAuthProvider;
      switch (authType) {
        case 'google':
          easyAuthProvider = 'google';
          break;
        case 'openid':
          easyAuthProvider = 'okta';
          break;
        default:
          easyAuthProvider = authType;
      }
      
      // Launch the login flow with the hostname
      final success = await _authService.login(
        cleanHostname, 
        easyAuthProvider,
        redirectUrl: redirectUrl,
      );
      
      if (!mounted) return;
      
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to launch login. Please try again.')),
        );
      } else {
        // Show a message that the browser has been launched
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Login page opened in browser. Please complete authentication.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
      logger.error('Error during login', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Select Tenant'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Tenant Configuration'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Error message
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 32),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadTenantConfig,
                          child: const Text('Retry Loading Configuration'),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Tenant'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView.builder(
        itemCount: _tenantConfig.length,
        itemBuilder: (context, index) {
          final String tenantDomain = _tenantConfig.keys.elementAt(index);
          final Map<String, dynamic> tenantData = _tenantConfig[tenantDomain];
          
          final String hostname = tenantData['hostname'] as String? ?? '';
          
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              title: Text(tenantDomain),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Auth Type: ${tenantData['type']}'),
                  Text('Hostname: ${hostname.replaceAll('https://', '')}'),
                ],
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.login),
              onTap: () => _loginWithTenant(tenantDomain, tenantData),
            ),
          );
        },
      ),
    );
  }
}
