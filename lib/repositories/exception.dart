enum NetworkErrorType {
  timeout,
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  serverError,
  noInternet,
  cancelled,
  unknown,
}

class NetworkException implements Exception {
  final NetworkErrorType type;
  final String? message;
  final int? statusCode;
  final dynamic errorBody;

  NetworkException({
    required this.type,
    this.message,
    this.statusCode,
    this.errorBody,
  });

  @override
  String toString() {
    return 'NetworkException: type=$type, message=$message, statusCode=$statusCode';
  }
}
