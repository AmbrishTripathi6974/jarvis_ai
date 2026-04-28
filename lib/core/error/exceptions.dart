class ServerException implements Exception {
  const ServerException(this.message);

  final String message;
}

class NetworkException implements Exception {
  const NetworkException(this.message);

  final String message;
}

class RequestTimeoutException implements Exception {
  const RequestTimeoutException(this.message);

  final String message;
}

class StreamingException implements Exception {
  const StreamingException(this.message);

  final String message;
}

class RateLimitException implements Exception {
  const RateLimitException(this.message, {this.retryAfter});

  final String message;
  final Duration? retryAfter;
}
