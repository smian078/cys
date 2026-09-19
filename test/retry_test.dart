import 'package:flutter_test/flutter_test.dart';
import 'package:cystem/core/utils/retry.dart';

void main() {
  test('retries transient failures and succeeds', () async {
    var tries = 0;
    final value = await withRetry(action: () async {
      tries++;
      if (tries < 3) throw StateError('temporary');
      return 42;
    }, baseDelay: Duration.zero);
    expect(value, 42);
    expect(tries, 3);
  });

  test('does not retry when predicate rejects', () async {
    var tries = 0;
    expect(() => withRetry(action: () async { tries++; throw ArgumentError('bad'); }, baseDelay: Duration.zero, shouldRetry: (_) => false), throwsArgumentError);
    expect(tries, 1);
  });
}
