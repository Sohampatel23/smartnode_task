import 'dart:async';
import 'dart:convert';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/inventory_item.dart';
import '../../domain/entities/inventory_operation.dart';
import '../../domain/entities/item_state_snapshot.dart';
import '../../domain/services/mqtt_service.dart';

/// Real MQTT implementation backed by `mqtt_client`, talking to the public
/// `test.mosquitto.org` broker. Handles connect/disconnect/reconnect,
/// subscription, publish, and payload parsing - all failure modes are
/// caught here and never thrown into UI/controller code.
class MqttServiceImpl implements MqttService {
  MqttServiceImpl({required String deviceId}) : _deviceId = deviceId;

  final String _deviceId;

  MqttServerClient? _client;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _connecting = false;

  final _connectionController = StreamController<bool>.broadcast();
  final _incomingController = StreamController<InventoryOperation>.broadcast();
  final _incomingStateController = StreamController<ItemStateSnapshot>.broadcast();

  @override
  Stream<bool> get connectionState => _connectionController.stream;

  @override
  Stream<InventoryOperation> get incomingOperations => _incomingController.stream;

  @override
  Stream<ItemStateSnapshot> get incomingItemStates => _incomingStateController.stream;

  @override
  bool get isConnected =>
      _client?.connectionStatus?.state == MqttConnectionState.connected;

  @override
  Future<void> connect() async {
    if (_connecting || isConnected || _disposed) return;
    _connecting = true;

    // A fresh, unique client id per attempt avoids the broker kicking a
    // previous session that shares the same id (common on shared public
    // brokers when an app reconnects quickly after a crash).
    final clientId = 'smartnode-inv-${_deviceId.substring(0, 8)}-'
        '${DateTime.now().millisecondsSinceEpoch}';

    final client = MqttServerClient.withPort(
      AppConstants.mqttBroker,
      clientId,
      AppConstants.mqttPort,
    );
    client.logging(on: false);
    client.keepAlivePeriod = AppConstants.mqttKeepAlive.inSeconds;
    client.connectTimeoutPeriod = AppConstants.mqttConnectTimeout.inMilliseconds;
    client.autoReconnect = false; // we manage reconnection ourselves for clarity/testability.
    client.onDisconnected = _handleDisconnected;
    client.onConnected = _handleConnected;
    client.setProtocolV311();
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atMostOnce);

    _client = client;

    try {
      AppLogger.mqtt('Connecting to ${AppConstants.mqttBroker}:${AppConstants.mqttPort}...');
      await client.connect();
    } catch (e, st) {
      AppLogger.error('MQTT connect threw', e, st);
      client.disconnect();
      _connecting = false;
      _handleDisconnected();
      return;
    }

    if (client.connectionStatus?.state != MqttConnectionState.connected) {
      AppLogger.mqtt('Connect failed: ${client.connectionStatus?.state}');
      client.disconnect();
      _connecting = false;
      _handleDisconnected();
      return;
    }

    client.subscribe(AppConstants.mqttTopic, MqttQos.values[AppConstants.mqttQos]);
    // Retained state topics: subscribing here is what lets a device that
    // was offline while other devices changed things catch up immediately -
    // the broker delivers the last-retained message per item on subscribe.
    client.subscribe(AppConstants.mqttStateTopicWildcard, MqttQos.values[AppConstants.mqttQos]);
    client.updates?.listen(_handleIncoming, onError: (Object e) {
      AppLogger.error('MQTT updates stream error', e);
    });

    _connecting = false;
  }

  void _handleConnected() {
    AppLogger.mqtt('Connected + subscribed to ${AppConstants.mqttTopic}');
    _connectionController.add(true);
  }

  void _handleDisconnected() {
    AppLogger.mqtt('Disconnected');
    if (!_connectionController.isClosed) _connectionController.add(false);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(AppConstants.mqttReconnectDelay, () {
      if (!_disposed && !isConnected) connect();
    });
  }

  void _handleIncoming(List<MqttReceivedMessage<MqttMessage>> events) {
    for (final event in events) {
      try {
        final payload = event.payload as MqttPublishMessage;
        final raw = MqttPublishPayload.bytesToStringAsString(payload.payload.message);
        final decoded = jsonDecode(raw) as Map<String, dynamic>;

        if (event.topic.startsWith(AppConstants.mqttStateTopicPrefix)) {
          final snapshot = ItemStateSnapshot.fromJsonMap(decoded);
          AppLogger.mqtt(
            'Received retained state for ${snapshot.item.id}: '
            'qty=${snapshot.item.quantity} (op=${snapshot.lastOperationId})',
          );
          _incomingStateController.add(snapshot);
          continue;
        }

        final operation = InventoryOperation.fromJsonMap(decoded);

        // Ignore our own publishes echoed back (test.mosquitto.org does not
        // echo to the publisher by default, but this stays defensive).
        if (operation.deviceId == _deviceId) continue;

        AppLogger.mqtt('Received $operation');
        _incomingController.add(operation);
      } on InvalidPayloadException catch (e) {
        AppLogger.mqtt('Dropped malformed payload: $e');
      } catch (e, st) {
        AppLogger.error('Unexpected error parsing MQTT payload', e, st);
      }
    }
  }

  @override
  Future<bool> publish(InventoryOperation operation) async {
    if (!isConnected) return false;
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(operation.toJsonMap()));
      _client!.publishMessage(
        AppConstants.mqttTopic,
        MqttQos.values[AppConstants.mqttQos],
        builder.payload!,
      );
      AppLogger.mqtt('Published $operation');
      return true;
    } catch (e, st) {
      AppLogger.error('Publish failed', e, st);
      return false;
    }
  }

  @override
  Future<bool> publishItemState(InventoryItem item, String causeOperationId) async {
    if (!isConnected) return false;
    try {
      final snapshot = ItemStateSnapshot(item: item, lastOperationId: causeOperationId);
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(snapshot.toJsonMap()));
      _client!.publishMessage(
        AppConstants.mqttStateTopicFor(item.id),
        MqttQos.values[AppConstants.mqttQos],
        builder.payload!,
        retain: true,
      );
      AppLogger.mqtt('Published retained state for ${item.id}: qty=${item.quantity}');
      return true;
    } catch (e, st) {
      AppLogger.error('Publish state failed', e, st);
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _client?.disconnect();
    await _connectionController.close();
    await _incomingController.close();
    await _incomingStateController.close();
  }
}
