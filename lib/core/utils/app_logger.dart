import 'dart:developer' as developer;

/// Small logging abstraction so call sites don't scatter `print()` and so
/// logging can be silenced/redirected in one place. Never log payload
/// contents that could be considered sensitive (not a concern for this demo,
/// but kept as a documented rule per the task's requirements).
class AppLogger {
  AppLogger._();

  static const String _name = 'InventorySync';

  static void mqtt(String message) => _log('MQTT', message);

  static void udp(String message) => _log('UDP', message);

  static void sync(String message) => _log('SYNC', message);

  static void queue(String message) => _log('QUEUE', message);

  static void network(String message) => _log('NETWORK', message);

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(
      message,
      name: _name,
      error: error,
      stackTrace: stackTrace,
      level: 1000,
    );
  }

  static void _log(String tag, String message) {
    developer.log('[$tag] $message', name: _name);
  }
}
