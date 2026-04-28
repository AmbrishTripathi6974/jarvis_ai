abstract class Failure implements Exception {
  const Failure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ServerFailure extends Failure {
  const ServerFailure(super.message);
}

class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

class TimeoutFailure extends Failure {
  const TimeoutFailure(super.message);
}

class StreamingFailure extends Failure {
  const StreamingFailure(super.message);
}

class RateLimitFailure extends Failure {
  const RateLimitFailure(super.message, {this.retryAfter});

  final Duration? retryAfter;
}
