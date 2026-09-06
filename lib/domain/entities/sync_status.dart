/// User-facing synchronization state. Deliberately small and free of any
/// networking vocabulary - the UI maps each value to plain language
/// ("Offline - changes will sync automatically") rather than exposing
/// transport internals.
enum SyncStatus {
  /// Still determining connectivity / establishing the MQTT connection.
  connecting,

  /// MQTT broker reachable - real-time cloud sync active.
  online,

  /// Broker unreachable, but a local Wi-Fi network is present - falling
  /// back to UDP broadcast for peer-to-peer sync on this LAN.
  localNetworkOnly,

  /// No usable network at all - changes are queued locally.
  offline,
}

extension SyncStatusDisplay on SyncStatus {
  String get label => switch (this) {
        SyncStatus.connecting => 'Connecting',
        SyncStatus.online => 'Online',
        SyncStatus.localNetworkOnly => 'Local Network Only',
        SyncStatus.offline => 'Offline',
      };

  String get description => switch (this) {
        SyncStatus.connecting => 'Checking connection...',
        SyncStatus.online => 'Changes sync instantly with the cloud.',
        SyncStatus.localNetworkOnly =>
          'No internet - syncing with nearby devices on this Wi-Fi. Cloud sync will resume automatically.',
        SyncStatus.offline => 'No connection - changes will sync automatically when it returns.',
      };
}
