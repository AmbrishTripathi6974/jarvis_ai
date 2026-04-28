import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:jarvis/core/network/connectivity_service.dart';

class ConnectivityCubit extends Cubit<bool> {
  ConnectivityCubit(ConnectivityService service) : super(true) {
    _subscription = service.isOnlineStream.listen(emit);
  }

  ConnectivityCubit.fromStream(Stream<bool> stream) : super(true) {
    _subscription = stream.listen(emit);
  }

  StreamSubscription<bool>? _subscription;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}

