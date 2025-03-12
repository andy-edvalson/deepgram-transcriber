// Andy's App Logger

import 'package:flutter/foundation.dart';

enum LogLevel {
  spam,    // why....
  debug,   // Most verbose, used for detailed diagnostic information
  info,    // General information about app flow
  warning, // Potential issues that don't prevent app from functioning
  error,   // Significant problems that might impact functionality
  critical // Severe errors that could crash the app
}

class AppLogger {
  static final AppLogger _singleton = AppLogger._internal();
  factory AppLogger() => _singleton;
  AppLogger._internal() {
    // Automatically adjust logging level based on platform and build mode
    _currentLevel = _determineDefaultLogLevel();
  }

  LogLevel _currentLevel = LogLevel.debug;
  final List<String> _logHistory = [];
  static const int _maxLogHistorySize = 500;

  // Determine default log level based on platform and build mode
  LogLevel _determineDefaultLogLevel() {
    if (kDebugMode) return LogLevel.debug;
    if (kProfileMode) return LogLevel.info;
    
    // In release mode, only log warnings and above
    return LogLevel.warning;
  }

  void setLogLevel(LogLevel level) {
    _currentLevel = level;
  }

  LogLevel get currentLevel => _currentLevel;

  void log(
    dynamic message, {
    LogLevel level = LogLevel.debug,
    Object? error,
    StackTrace? stackTrace,
    int stackFrameOffset = 0,
  }) {
    // Only log if the message's level is at or above the current level
    if (level.index >= _currentLevel.index) {
      // Get stack trace and try to extract the caller class
      stackTrace ??= StackTrace.current;
      String callerClass = _extractCallerFromStackTrace(stackTrace, stackFrameOffset + 1);
      
      String logMessage = _formatLogMessage(message, level, callerClass, error, stackTrace);
      debugPrint(logMessage);
      
      _storeLogEntry(logMessage);
    }
  }

  // Logs an exception and returns a Result
  Future<void> logException(
    dynamic exception, 
    StackTrace stackTrace, {
    String? message,
    Map<String, dynamic>? additionalData,
    LogLevel level = LogLevel.error,
    int stackFrameOffset = 0,
  }) async {
    // Log the exception through the normal log system
    log(
      message ?? exception.toString(),
      level: level,
      error: exception,
      stackTrace: stackTrace,
      stackFrameOffset: stackFrameOffset + 1 // Account for this method call
    );

    try {
      // Maybe firebase crashlytics here?
      
    } catch (e) {
      debugPrint('Failed to log exception to remote: $e');
    }
  }

String _extractCallerFromStackTrace(StackTrace stackTrace, int frameOffset) {
  try {
    List<String> stackTraceLines = stackTrace.toString().split('\n');
    
    if (stackTraceLines.length <= frameOffset) {
      return 'unknown';
    }
    
    // Try to get the target frame
    String frame = stackTraceLines[frameOffset];
    
    // Print frame for debugging (temporarily)
    // print('Stack frame: $frame');
    
    // There's a few different ways we can determine the caller class
    // 1. Standard pattern: ClassName.methodName (file:line:column)
    RegExp classPattern1 = RegExp(r'([A-Za-z0-9_$]+)\.([A-Za-z0-9_$]+)');
    
    // 2. Anonymous closure pattern: ClassName.<anonymous closure> (file:line:column)
    RegExp classPattern2 = RegExp(r'([A-Za-z0-9_$]+)\.<anonymous closure>');
    
    // 3. Package pattern: package:your_package/path/ClassName.dart
    RegExp classPattern3 = RegExp(r'package:[^/]+/[^/]+/([A-Za-z0-9_$]+)\.dart');
    
    // Try each pattern
    for (var pattern in [classPattern1, classPattern2, classPattern3]) {
      Match? match = pattern.firstMatch(frame);
      if (match != null && match.groupCount >= 1) {
        return match.group(1) ?? 'unknown';
      }
    }
    
    // Fallback to looking for file name
    RegExp filePattern = RegExp(r'([A-Za-z0-9_$]+)\.dart');
    Match? fileMatch = filePattern.firstMatch(frame);
    if (fileMatch != null) {
      return fileMatch.group(1) ?? 'unknown';
    }
    
    return 'unknown';
  } catch (e) {
    return 'parse_error';
  }
}
  String _formatLogMessage(
    dynamic message, 
    LogLevel level, 
    String className, 
    Object? error, 
    StackTrace? stackTrace
  ) {
    String timestamp = DateTime.now().toIso8601String();
    String levelPrefix = level.toString().split('.').last.toUpperCase();
    String classPrefix = '[$className] ';
    String messageString = message.toString();
    
    String logEntry = '$timestamp [$levelPrefix] $classPrefix$messageString';
    
    if (error != null) {
      logEntry += '\nERROR: $error';
    }
    
    if (stackTrace != null && level.index >= LogLevel.error.index) {
      logEntry += '\nSTACK TRACE:\n$stackTrace';
    }
    
    return logEntry;
  }

  // Maybe use these if we want to buffer and send to kinesis
  void _storeLogEntry(String logEntry) {
    _logHistory.add(logEntry);
    
    // Trim log history if it exceeds max size
    if (_logHistory.length > _maxLogHistorySize) {
      _logHistory.removeRange(0, _logHistory.length - _maxLogHistorySize);
    }
  }

  List<String> getLogHistory() {
    return List.unmodifiable(_logHistory);
  }

  void clearLogHistory() {
    _logHistory.clear();
  }

  // Convenience methods for different log levels with additional stackFrameOffset
  // to account for these wrapper methods
  void spam(dynamic message) => 
    log(message, level: LogLevel.spam, stackFrameOffset: 1);

  void debug(dynamic message) => 
    log(message, level: LogLevel.debug, stackFrameOffset: 1);
  
  void info(dynamic message) => 
    log(message, level: LogLevel.info, stackFrameOffset: 1);
  
  void warning(dynamic message, {Object? error, StackTrace? stackTrace}) => 
    log(message, level: LogLevel.warning, error: error, stackTrace: stackTrace, stackFrameOffset: 1);
  
  void error(dynamic message, {Object? error, StackTrace? stackTrace}) => 
    log(message, level: LogLevel.error, error: error, stackTrace: stackTrace, stackFrameOffset: 1);
  
  void critical(dynamic message, {Object? error, StackTrace? stackTrace}) => 
    log(message, level: LogLevel.critical, error: error, stackTrace: stackTrace, stackFrameOffset: 1);

}

// Global convenience accessor
AppLogger get logger => AppLogger();
