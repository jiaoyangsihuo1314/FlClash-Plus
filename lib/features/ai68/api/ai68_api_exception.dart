final class Ai68ApiException implements Exception {
  const Ai68ApiException({required this.message, this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  bool get isAuthenticationFailure => statusCode == 401 || statusCode == 403;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' ($statusCode)';
    return 'Ai68ApiException$status: $message';
  }
}
