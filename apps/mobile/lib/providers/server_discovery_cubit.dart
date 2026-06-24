import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../services/server_discovery_service.dart';

class ServerDiscoveryCubit extends Cubit<List<DiscoveredServer>> {
  final ServerDiscoveryService _service;
  StreamSubscription<List<DiscoveredServer>>? _sub;

  ServerDiscoveryCubit()
    : _service = ServerDiscoveryService(),
      super(const []) {
    _sub = _service.servers.listen(emit);
  }

  /// Start mDNS discovery. Call from UI when the screen is first visible.
  void startDiscovery() => _service.startDiscovery();

  /// Stop mDNS discovery (e.g. when connected to a bridge).
  void stopDiscovery() => _service.stopDiscovery();

  @override
  Future<void> close() {
    _sub?.cancel();
    _service.dispose();
    return super.close();
  }
}
