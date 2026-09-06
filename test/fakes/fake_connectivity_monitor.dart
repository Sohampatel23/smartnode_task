import 'dart:async';

import 'package:smartnode_task/core/network/local_connectivity.dart';
import 'package:smartnode_task/domain/services/connectivity_monitor.dart';

class FakeConnectivityMonitor implements ConnectivityMonitor {
  FakeConnectivityMonitor([this._current = LocalConnectivity.wifi]);

  LocalConnectivity _current;
  final _controller = StreamController<LocalConnectivity>.broadcast();

  @override
  LocalConnectivity get current => _current;

  @override
  Stream<LocalConnectivity> get onChange => _controller.stream;

  @override
  Future<void> start() async {}

  void set(LocalConnectivity value) {
    _current = value;
    _controller.add(value);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
