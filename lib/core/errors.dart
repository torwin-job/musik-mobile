import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

ApiException mapDioError(DioException e, {String? baseUrl}) {
  final data = e.response?.data;
  if (data is Map) {
    final msg =
        (data['error'] ?? data['message'] ?? e.message ?? 'request failed')
            .toString();
    final code = data['code']?.toString();
    return ApiException(msg, code: code, statusCode: e.response?.statusCode);
  }

  final origin = baseUrl ?? e.requestOptions.baseUrl;
  switch (e.type) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
      return ApiException(
        'Нет связи с $origin — запусти player '
        '(./player/bin/musik-player) и проверь Base URL.',
        statusCode: e.response?.statusCode,
      );
    case DioExceptionType.receiveTimeout:
      return ApiException(
        'Сервер не ответил вовремя ($origin).',
        statusCode: e.response?.statusCode,
      );
    default:
      return ApiException(
        e.message ?? 'network error',
        statusCode: e.response?.statusCode,
      );
  }
}
