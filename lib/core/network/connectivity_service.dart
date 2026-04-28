import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityService {
  ConnectivityService(this._connectivity);

  final Connectivity _connectivity;

  Stream<bool> get isOnlineStream async* {
    yield await isOnline();

    await for (final results in _connectivity.onConnectivityChanged) {
      yield _isOnlineFromResults(results);
    }
  }

  Future<bool> isOnline() async {
    final results = await _connectivity.checkConnectivity();
    return _isOnlineFromResults(results);
  }

  bool _isOnlineFromResults(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }
}

