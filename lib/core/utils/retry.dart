import 'dart:async';
import 'dart:math';

typedef RetryPredicate = bool Function(Object error);

Future<T> withRetry<T>({
  required Future<T> Function() action,
  int maxAttempts = 3,
  Duration baseDelay = const Duration(milliseconds: 350),
  RetryPredicate? shouldRetry,
}) async {
  Object? last;
  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await action();
    } catch (error) {
      last = error;
      final retry = shouldRetry?.call(error) ?? true;
      if (!retry || attempt == maxAttempts) rethrow;
      final jitter = Random().nextInt(150);
      final delay = Duration(
        milliseconds:
            baseDelay.inMilliseconds * pow(2, attempt - 1).toInt() + jitter,
      );
      await Future<void>.delayed(delay);
    }
  }
  throw StateError('Retry failed: $last');
}
