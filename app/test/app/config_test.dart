import 'package:ailearn/app/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an absolute http URL and drops the trailing slash', () {
    final config = AppConfig.parse('http://localhost:8000/');

    expect(config.apiBaseUrl.toString(), 'http://localhost:8000');
  });

  test('throws when API_BASE_URL is empty', () {
    expect(() => AppConfig.parse(''), throwsStateError);
  });

  test('throws when API_BASE_URL is not an absolute http(s) URL', () {
    expect(() => AppConfig.parse('localhost:8000'), throwsFormatException);
    expect(() => AppConfig.parse('ftp://example.com'), throwsFormatException);
  });
}
