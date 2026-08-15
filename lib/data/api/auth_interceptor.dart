import 'package:dio/dio.dart';

typedef AuthExpiredCallback = void Function();

class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.tokenProvider, this.onUnauthorized});

  final Future<String?> Function() tokenProvider;
  final AuthExpiredCallback? onUnauthorized;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await tokenProvider();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      onUnauthorized?.call();
    }
    handler.next(err);
  }
}
