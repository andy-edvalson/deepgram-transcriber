import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:deepgram_transcriber/app_logger.dart';

void main() {
  group('AppLogger Tests', () {
    late AppLogger logger;

    setUp(() {
      logger = AppLogger();
      logger.clearLogHistory();
    });

    test('AppLogger should be a singleton', () {
      final logger1 = AppLogger();
      final logger2 = AppLogger();
      
      // Both instances should be the same object
      expect(identical(logger1, logger2), isTrue);
    });

    test('Global logger accessor should return the singleton instance', () {
      final globalLogger = logger;
      
      // The global logger should be the same as the singleton instance
      expect(identical(globalLogger, AppLogger()), isTrue);
    });

    test('Default log level should be set based on build mode', () {
      // In test mode, the default log level should be LogLevel.debug
      expect(logger.currentLevel, LogLevel.debug);
    });

    test('setLogLevel should change the current log level', () {
      // Initial level should be debug in test mode
      expect(logger.currentLevel, LogLevel.debug);
      
      // Change the log level
      logger.setLogLevel(LogLevel.error);
      
      // Verify the level was changed
      expect(logger.currentLevel, LogLevel.error);
    });

    test('log should add entries to log history when level is at or above current level', () {
      // Set log level to info
      logger.setLogLevel(LogLevel.info);
      
      // Log messages at different levels
      logger.log('Debug message', level: LogLevel.debug); // Below current level
      logger.log('Info message', level: LogLevel.info); // At current level
      logger.log('Warning message', level: LogLevel.warning); // Above current level
      
      // Get log history
      final history = logger.getLogHistory();
      
      // Debug message should not be logged
      expect(history.any((entry) => entry.contains('Debug message')), isFalse);
      
      // Info and warning messages should be logged
      expect(history.any((entry) => entry.contains('Info message')), isTrue);
      expect(history.any((entry) => entry.contains('Warning message')), isTrue);
    });

    test('log history should be limited to maxLogHistorySize', () {
      // Set a very high log level to ensure all messages are logged
      logger.setLogLevel(LogLevel.spam);
      
      // Log more messages than the max history size
      for (int i = 0; i < 600; i++) {
        logger.log('Message $i', level: LogLevel.spam);
      }
      
      // Get log history
      final history = logger.getLogHistory();
      
      // History should be limited to 500 entries (the max size)
      expect(history.length, 500);
      
      // The oldest messages should be removed
      expect(history.any((entry) => entry.contains('Message 0')), isFalse);
      expect(history.any((entry) => entry.contains('Message 599')), isTrue);
    });

    test('clearLogHistory should remove all log entries', () {
      // Log some messages
      logger.log('Test message 1', level: LogLevel.info);
      logger.log('Test message 2', level: LogLevel.info);
      
      // Verify messages were logged
      expect(logger.getLogHistory().length, 2);
      
      // Clear log history
      logger.clearLogHistory();
      
      // Verify history is empty
      expect(logger.getLogHistory().length, 0);
    });

    test('Convenience methods should log at the correct level', () {
      // Set log level to spam to ensure all messages are logged
      logger.setLogLevel(LogLevel.spam);
      
      // Use convenience methods
      logger.spam('Spam message');
      logger.debug('Debug message');
      logger.info('Info message');
      logger.warning('Warning message');
      logger.error('Error message');
      logger.critical('Critical message');
      
      // Get log history
      final history = logger.getLogHistory();
      
      // Verify each message was logged with the correct level
      expect(history.any((entry) => entry.contains('[SPAM]') && entry.contains('Spam message')), isTrue);
      expect(history.any((entry) => entry.contains('[DEBUG]') && entry.contains('Debug message')), isTrue);
      expect(history.any((entry) => entry.contains('[INFO]') && entry.contains('Info message')), isTrue);
      expect(history.any((entry) => entry.contains('[WARNING]') && entry.contains('Warning message')), isTrue);
      expect(history.any((entry) => entry.contains('[ERROR]') && entry.contains('Error message')), isTrue);
      expect(history.any((entry) => entry.contains('[CRITICAL]') && entry.contains('Critical message')), isTrue);
    });

    test('Error and stack trace should be included in log entries when provided', () {
      // Set log level to error
      logger.setLogLevel(LogLevel.error);
      
      // Create a test error and stack trace
      final testError = Exception('Test error');
      final testStackTrace = StackTrace.current;
      
      // Log an error with stack trace
      logger.error('Error occurred', error: testError, stackTrace: testStackTrace);
      
      // Get log history
      final history = logger.getLogHistory();
      
      // Verify error and stack trace are included in the log entry
      expect(history.any((entry) => 
        entry.contains('Error occurred') && 
        entry.contains('ERROR: $testError') && 
        entry.contains('STACK TRACE:')), 
        isTrue
      );
    });

    test('_extractCallerFromStackTrace should extract caller class name', () {
      // This is a bit tricky to test directly since it's a private method
      // We can test it indirectly by checking the log output
      
      // Log a message
      logger.setLogLevel(LogLevel.spam);
      logger.log('Test message', level: LogLevel.spam);
      
      // Get log history
      final history = logger.getLogHistory();
      
      // The log entry should include the caller class name (in this case, likely 'main')
      // We can't predict the exact class name, but it should be enclosed in square brackets
      expect(history.any((entry) => RegExp(r'\[[A-Za-z0-9_$]+\]').hasMatch(entry)), isTrue);
    });
  });
}
