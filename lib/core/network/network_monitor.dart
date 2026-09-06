import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../../domain/services/connectivity_monitor.dart';
import '../utils/app_logger.dart';
import 'local_connectivity.dart';

/// Reports the *type* of network interface currently available (Wi-Fi,
/// mobile data, ethernet, or none). This answers "is there a LAN to fall
/// back to?" - it deliberately does NOT answer "is there internet?", because
/// those are different questions (see README). Internet/broker reachability
/// is answered separately by [MqttService]'s connection state.
class NetworkMonitor implements ConnectivityMonitor {
  NetworkMonitor({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final _controller = StreamController<LocalConnectivity>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  LocalConnectivity _current = LocalConnectivity.none;

  @override
  LocalConnectivity get current => _current;

  @override
  Stream<LocalConnectivity> get onChange => _controller.stream;

  @override
  Future<void> start() async {
    final initial = await _connectivity.checkConnectivity();
    _emit(_map(initial));

    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _emit(_map(results));
    });
  }

  void _emit(LocalConnectivity value) {
    if (value == _current) return;
    _current = value;
    AppLogger.network('Connectivity changed -> $value');
    _controller.add(value);
  }

  LocalConnectivity _map(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) return LocalConnectivity.wifi;
    if (results.contains(ConnectivityResult.ethernet)) return LocalConnectivity.ethernet;
    if (results.contains(ConnectivityResult.mobile)) return LocalConnectivity.mobile;
    return LocalConnectivity.none;
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    await _controller.close();
  }
}
