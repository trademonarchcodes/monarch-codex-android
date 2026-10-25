import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monarch_codex/main.dart';

void main() {
  test('Monarch Codex mobile API uses HTTPS', () {
    expect(apiRoot, startsWith('https://'));
    expect(apiRoot, contains('/api/mobile'));
  });

  test('API errors show backend validation messages instead of Dio dumps', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/admin/academy/lessons'),
      response: Response(
        requestOptions: RequestOptions(path: '/admin/academy/lessons'),
        statusCode: 400,
        data: {'error': 'invalid_lesson', 'message': 'Title and lesson content are required.'},
      ),
      type: DioExceptionType.badResponse,
    );
    expect(apiErrorMessage(error), 'Title and lesson content are required.');
    expect(apiErrorMessage(error), isNot(contains('DioException')));
  });

  test('API errors map common statuses to actionable messages', () {
    DioException responseError(int status) => DioException(
      requestOptions: RequestOptions(path: '/admin/academy'),
      response: Response(requestOptions: RequestOptions(path: '/admin/academy'), statusCode: status, data: {}),
      type: DioExceptionType.badResponse,
    );
    expect(apiErrorMessage(responseError(401)), contains('session has expired'));
    expect(apiErrorMessage(responseError(403)), contains('permission'));
    expect(apiErrorMessage(responseError(429)), contains('Too many requests'));
    expect(apiErrorMessage(responseError(500)), contains('HTTP 500'));
  });
}
