// This is a stub file for web platform to provide compatibility with app_links
// It provides empty implementations of the functions used from app_links

import 'dart:async';

// Empty class to match AppLinks API
class AppLinks {
  // Stub for getInitialAppLink from app_links
  Future<Uri?> getInitialAppLink() async {
    // Not implemented for web in this way
    // Web implementation uses Uri.base directly in the auth_service.dart
    return null;
  }

  // Stub for uriLinkStream from app_links
  // Returns an empty stream that will never emit any values
  Stream<Uri> get uriLinkStream => const Stream<Uri>.empty();
}
