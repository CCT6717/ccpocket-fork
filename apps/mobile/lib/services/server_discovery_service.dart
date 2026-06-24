import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/logger.dart';

import 'server_discovery_impl_stub.dart'
    if (dart.library.io) 'server_discovery_impl_io.dart'
    as impl;

class DiscoveredServer {
  final String name;
  final String host;
  final int port;
  final bool authRequired;

  const DiscoveredServer({
    required this.name,
    required this.host,
    required this.port,
    required this.authRequired,
  });

  String get wsUrl => 'ws://$host:$port';

  @override
  bool operator ==(Object other) =>
      other is DiscoveredServer && host == other.host && port == other.port;

  @override
  int get hashCode => Object.hash(host, port);
}

class ServerDiscoveryService with WidgetsBindingObserver {
  final _serversController =
      StreamController<List<DiscoveredServer>>.broadcast();
  final Map<String, DiscoveredServer> _servers = {};
  Object? _discovery;
  bool _isInForeground = true;
  bool _isDiscoveryActive = false;

  ServerDiscoveryService() {
    _tryAddObserver();
  }

  void _tryAddObserver() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // Binding not yet initialized (e.g. in tests).
    }
  }

  Stream<List<DiscoveredServer>> get servers => _serversController.stream;

  Future<void> startDiscovery() async {
    _isDiscoveryActive = true;
    if (!_isInForeground) return;
    try {
      await stopDiscovery();
      _discovery = await impl.startDiscovery(
        onResolved: (name, host, port, authRequired) {
          final server = DiscoveredServer(
            name: name,
            host: host,
            port: port,
            authRequired: authRequired,
          );
          _servers['$host:$port'] = server;
          _emit();
        },
        onLost: (host, port) {
          _servers.remove('$host:$port');
          _emit();
        },
      );
    } catch (e) {
      logger.error('[discovery] Failed to start', e);
    }
  }

  Future<void> stopDiscovery() async {
    _isDiscoveryActive = false;
    if (_discovery != null) {
      await impl.stopDiscovery(_discovery);
      _discovery = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _isInForeground = true;
        if (_isDiscoveryActive && _discovery == null) {
          startDiscovery();
        }
        break;
      case AppLifecycleState.paused:
        _isInForeground = false;
        if (_discovery != null) {
          impl.stopDiscovery(_discovery);
          _discovery = null;
        }
        break;
      default:
        break;
    }
  }

  void dispose() {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // Binding not available (e.g. in tests).
    }
    stopDiscovery();
    _servers.clear();
    _serversController.close();
  }

  void _emit() {
    if (!_serversController.isClosed) {
      _serversController.add(_servers.values.toList());
    }
  }
}
