/// Application-level error types. Low-level exceptions (SocketException,
/// FormatException, etc.) are caught at the networking boundary and
/// translated into these so the UI never has to interpret raw platform
/// errors.
sealed class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MqttConnectionException extends AppException {
  const MqttConnectionException([super.message = 'Could not reach the cloud broker.']);
}

class MqttPublishException extends AppException {
  const MqttPublishException([super.message = 'Could not publish update to the cloud.']);
}

class UdpException extends AppException {
  const UdpException([super.message = 'Local network sync failed.']);
}

class StorageException extends AppException {
  const StorageException([super.message = 'Could not save data locally.']);
}

class InvalidPayloadException extends AppException {
  const InvalidPayloadException([super.message = 'Received a malformed message.']);
}

class SyncException extends AppException {
  const SyncException([super.message = 'Could not sync changes.']);
}
