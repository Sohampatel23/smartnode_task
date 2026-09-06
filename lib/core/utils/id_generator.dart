import 'package:uuid/uuid.dart';

/// Thin wrapper around uuid generation so the rest of the app depends on an
/// abstraction rather than the `uuid` package directly.
class IdGenerator {
  IdGenerator() : _uuid = const Uuid();

  final Uuid _uuid;

  /// Unique id for a single mutation (used for idempotency + de-duplication).
  String newOperationId() => _uuid.v4();

  /// Stable per-install id for this device (used to ignore self-originated
  /// UDP broadcasts and for diagnostics).
  String newDeviceId() => _uuid.v4();
}
