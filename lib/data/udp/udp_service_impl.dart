import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/inventory_operation.dart';
import '../../domain/services/udp_service.dart';

/// Local-network fallback transport (Phase 3) using a plain UDP broadcast
/// socket - no discovery/pairing protocol, just "shout on the LAN and
/// listen". Sufficient for the "same Wi-Fi router" scope of this challenge;
/// see README limitations for what this does not handle (e.g. networks that
/// block broadcast traffic between clients, "AP isolation").
class UdpServiceImpl implements UdpService {
  UdpServiceImpl({required String deviceId}) : _deviceId = deviceId;

  final String _deviceId;
  RawDatagramSocket? _socket;
  final _incomingController = StreamController<InventoryOperation>.broadcast();

  @override
  Stream<InventoryOperation> get incomingOperations => _incomingController.stream;

  @override
  Future<void> start() async {
    if (_socket != null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        AppConstants.udpPort,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      socket.listen(
        _handleEvent,
        onError: (Object e) => AppLogger.error('UDP socket error', e),
        onDone: () => AppLogger.udp('Socket closed'),
      );
      _socket = socket;
      AppLogger.udp('Listening on port ${AppConstants.udpPort}');
    } catch (e, st) {
      AppLogger.error('Failed to start UDP socket', e, st);
      throw const UdpException('Could not start local network listener.');
    }
  }

  void _handleEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final datagram = _socket?.receive();
    if (datagram == null) return;

    try {
      final raw = utf8.decode(datagram.data);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final operation = InventoryOperation.fromJsonMap(decoded);

      if (operation.deviceId == _deviceId) return; // drop our own broadcast

      AppLogger.udp('Received $operation from ${datagram.address.address}');
      _incomingController.add(operation);
    } on InvalidPayloadException catch (e) {
      AppLogger.udp('Dropped malformed packet: $e');
    } catch (e, st) {
      AppLogger.error('Unexpected error parsing UDP packet', e, st);
    }
  }

  @override
  Future<bool> broadcast(InventoryOperation operation) async {
    final socket = _socket;
    if (socket == null) return false;
    try {
      final data = utf8.encode(jsonEncode(operation.toJsonMap()));
      final sent = socket.send(
        data,
        InternetAddress(AppConstants.udpBroadcastAddress),
        AppConstants.udpPort,
      );
      AppLogger.udp('Broadcast $operation');
      return sent > 0;
    } catch (e, st) {
      AppLogger.error('UDP broadcast failed', e, st);
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _socket?.close();
    _socket = null;
    if (!_incomingController.isClosed) await _incomingController.close();
  }
}
