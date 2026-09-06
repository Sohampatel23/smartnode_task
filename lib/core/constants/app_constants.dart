/// Centralized configuration for broker, topics, ports and sync tuning.
///
/// Kept in one place per the assignment's requirement to avoid scattering
/// magic strings/numbers across the codebase.
class AppConstants {
  AppConstants._();

  // ---------------------------------------------------------------------
  // MQTT (Phase 1 - Cloud Sync)
  // ---------------------------------------------------------------------

  /// Free public broker used for the demo. NOT secure and NOT suitable for
  /// production use - anyone can publish/subscribe to a known topic. See
  /// README "Known Limitations" for details.
  static const String mqttBroker = 'test.mosquitto.org';
  static const int mqttPort = 1883;

  /// A demo "warehouse" id used to namespace the MQTT topic so that this
  /// app's traffic doesn't collide with other test.mosquitto.org users.
  /// Change this if you want an isolated topic for your own test run.
  static const String warehouseId = 'smartnode-inventory-demo-v1';

  /// Topic structure: inventory/{environment}/{warehouseId}
  /// A single topic carries every item's operations - the payload itself
  /// identifies which item/operation it refers to. This keeps the topic
  /// design simple while still allowing multiple independent demo runs to
  /// avoid colliding with each other (change [warehouseId] to isolate).
  static const String mqttTopic = 'inventory/demo/$warehouseId';

  /// Retained "current state" topic, one sub-topic per item:
  /// inventory/demo/{warehouseId}/state/{itemId}.
  ///
  /// [mqttTopic] alone only reaches devices that are *currently subscribed*
  /// when an operation is published - a device that was offline while
  /// another device made a change never sees that operation once it comes
  /// back, because MQTT (without a persistent session) does not replay
  /// missed messages. Publishing the item's converged quantity here with
  /// the `retain` flag set means the broker keeps the latest value and
  /// delivers it immediately to any device that (re)subscribes later,
  /// closing that gap. See README "Catching a reconnecting device up".
  static const String mqttStateTopicPrefix = 'inventory/demo/$warehouseId/state';

  static String mqttStateTopicFor(String itemId) => '$mqttStateTopicPrefix/$itemId';

  static const String mqttStateTopicWildcard = '$mqttStateTopicPrefix/#';

  /// QoS 1 (at least once): guarantees delivery on reconnect without the
  /// broker round-trip overhead of QoS 2. Because every operation carries a
  /// unique [operationId] and the app de-duplicates on receipt, "at least
  /// once" delivery is safe and cheaper than exactly-once.
  static const int mqttQos = 1;

  static const Duration mqttConnectTimeout = Duration(seconds: 8);
  static const Duration mqttReconnectDelay = Duration(seconds: 5);
  static const Duration mqttKeepAlive = Duration(seconds: 20);

  // ---------------------------------------------------------------------
  // UDP (Phase 3 - Local Fallback)
  // ---------------------------------------------------------------------

  /// Fixed broadcast port both devices listen on when on the same LAN.
  static const int udpPort = 45677;
  static const String udpBroadcastAddress = '255.255.255.255';

  // ---------------------------------------------------------------------
  // Sync tuning
  // ---------------------------------------------------------------------

  /// How often the network monitor re-checks connectivity type.
  static const Duration connectivityPollInterval = Duration(seconds: 5);

  /// How often the sync manager retries flushing the pending queue while
  /// online but a previous flush attempt failed.
  static const Duration queueRetryInterval = Duration(seconds: 10);

  /// How long an item is protected from being overwritten by an incoming
  /// retained-state snapshot after *this device* makes its own edit to it.
  ///
  /// The offline-queue check alone isn't enough: the moment this device's
  /// own flush publishes and removes an operation from the queue, a
  /// concurrent peer's retained snapshot (computed from *its* local view,
  /// which doesn't yet know about this device's edit) can arrive and look
  /// "safe to adopt" by the queue-based check even though blindly adopting
  /// it would discard this device's just-published contribution. This
  /// grace window closes that race for the realistic case of two devices
  /// reconnecting and flushing at roughly the same time over a public
  /// broker; see README "Known Limitations" for what it does not cover.
  static const Duration retainedStateGracePeriod = Duration(seconds: 10);

  // ---------------------------------------------------------------------
  // Local storage box names
  // ---------------------------------------------------------------------

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  /// Quantity at or below which an item is flagged "Low stock" in the UI.
  static const int lowStockThreshold = 5;

  static const String inventoryBoxName = 'inventory_items';
  static const String pendingQueueBoxName = 'pending_operations';
  static const String processedOpsBoxName = 'processed_operation_ids';
  static const String metaBoxName = 'app_meta';
  static const String deviceIdKey = 'device_id';
}
