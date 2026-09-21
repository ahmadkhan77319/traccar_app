import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../utills/custom_snackbar.dart';
import 'exception.dart';
import 'shared_pref_repo.dart';

enum RequestType { post, get, delete, put, patch }

class RequestClient {
  final SharedPrefsRepository _sharedPrefsRepository;
  final Dio dio;

  RequestClient({
    required SharedPrefsRepository sharedPrefsRepository,
    Dio? dioInstance,
  })  : _sharedPrefsRepository = sharedPrefsRepository,
        dio = dioInstance ?? Dio() {
    _setupInterceptors();
  }

  void _setupInterceptors() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.headers.addAll(await _getHeaders(options));
          options.sendTimeout = const Duration(minutes: 1);
          options.receiveTimeout = const Duration(seconds: 45);
          handler.next(options);
        },
        onResponse: (response, handler) async {
          await _persistCookies(response);
          handler.next(response);
        },
        onError: (DioException e, handler) {
          final networkError = NetworkException(
            type: _parseErrorType(e),
            message: e.message ?? 'An unknown error occurred',
            statusCode: e.response?.statusCode,
            errorBody: e.response?.data,
          );
          if (kDebugMode) {
            print('Network Error: $networkError');
          }
          handler.reject(
            DioException(
              requestOptions: e.requestOptions,
              response: e.response,
              type: e.type,
              error: networkError,
            ),
          );

          if (e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout) {
            snackBarCustom(
              title: 'Network Error',
              message: 'Please ensure you have a stable internet connection.',
              type: SnackBarType.error,
            );
          }
        },
      ),
    );
  }

  Future<Map<String, String>> _getHeaders(RequestOptions options) async {
    final headers = <String, String>{
      'Accept': 'application/json',
    };

    final cookie = _sharedPrefsRepository.sessionCookie;
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }

    final email = _sharedPrefsRepository.email;
    final password = _sharedPrefsRepository.password;
    if (email != null &&
        email.isNotEmpty &&
        password != null &&
        password.isNotEmpty) {
      final basic = base64Encode(utf8.encode('$email:$password'));
      headers['Authorization'] = 'Basic $basic';
    }

    // Don't override content-type for form login
    if (options.contentType == null &&
        options.headers['Content-Type'] == null) {
      headers['Content-Type'] = 'application/json';
    }

    return headers;
  }

  Future<void> _persistCookies(Response response) async {
    final cookies = response.headers['set-cookie'];
    if (cookies == null || cookies.isEmpty) return;

    final cookieParts = cookies
        .map((cookie) => cookie.split(';').first.trim())
        .where((cookie) => cookie.isNotEmpty)
        .toList();

    if (cookieParts.isEmpty) return;

    final existing = _sharedPrefsRepository.sessionCookie;
    final merged = <String, String>{};

    void ingest(String raw) {
      for (final part in raw.split(';')) {
        final trimmed = part.trim();
        if (trimmed.isEmpty || !trimmed.contains('=')) continue;
        final index = trimmed.indexOf('=');
        final key = trimmed.substring(0, index);
        final value = trimmed.substring(index + 1);
        if (key.toLowerCase() == 'path' ||
            key.toLowerCase() == 'httponly' ||
            key.toLowerCase() == 'secure' ||
            key.toLowerCase().startsWith('max-age') ||
            key.toLowerCase() == 'expires' ||
            key.toLowerCase() == 'samesite') {
          continue;
        }
        merged[key] = value;
      }
    }

    if (existing != null && existing.isNotEmpty) {
      ingest(existing);
    }
    for (final part in cookieParts) {
      ingest(part);
    }

    final cookieHeader =
        merged.entries.map((e) => '${e.key}=${e.value}').join('; ');
    if (cookieHeader.isNotEmpty) {
      await _sharedPrefsRepository.setSessionCookie(cookieHeader);
    }
  }

  NetworkErrorType _parseErrorType(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return NetworkErrorType.timeout;
      case DioExceptionType.badResponse:
        switch (e.response?.statusCode) {
          case 400:
            return NetworkErrorType.badRequest;
          case 401:
            return NetworkErrorType.unauthorized;
          case 403:
            return NetworkErrorType.forbidden;
          case 404:
            return NetworkErrorType.notFound;
          case 500:
            return NetworkErrorType.serverError;
          default:
            return NetworkErrorType.unknown;
        }
      case DioExceptionType.cancel:
        return NetworkErrorType.cancelled;
      case DioExceptionType.unknown:
        return e.error is SocketException
            ? NetworkErrorType.noInternet
            : NetworkErrorType.unknown;
      default:
        return NetworkErrorType.unknown;
    }
  }

  Future<T> request<T>({
    required String url,
    required RequestType method,
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Options? options,
    T Function(dynamic data)? parser,
  }) async {
    try {
      final requestOptions = options ?? Options();
      Response response;

      switch (method) {
        case RequestType.get:
          response = await dio.get(
            url,
            options: requestOptions,
            queryParameters: queryParameters,
          );
          break;
        case RequestType.post:
          response = await dio.post(
            url,
            data: body,
            options: requestOptions,
            queryParameters: queryParameters,
          );
          break;
        case RequestType.put:
          response = await dio.put(
            url,
            data: body,
            options: requestOptions,
            queryParameters: queryParameters,
          );
          break;
        case RequestType.delete:
          response = await dio.delete(
            url,
            data: body,
            options: requestOptions,
            queryParameters: queryParameters,
          );
          break;
        case RequestType.patch:
          response = await dio.patch(
            url,
            data: body,
            options: requestOptions,
            queryParameters: queryParameters,
          );
          break;
      }

      if (parser != null) {
        return parser(response.data);
      }
      return response as T;
    } on DioException {
      rethrow;
    } catch (e) {
      throw NetworkException(
        type: NetworkErrorType.unknown,
        message: 'Unexpected error: ${e.toString()}',
      );
    }
  }
}
