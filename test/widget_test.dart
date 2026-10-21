import 'package:flutter_test/flutter_test.dart';
import 'package:monarch_codex/main.dart';

void main() {
  test('Monarch Codex mobile API uses HTTPS', () {
    expect(apiRoot, startsWith('https://'));
    expect(apiRoot, contains('/api/mobile'));
  });
}
