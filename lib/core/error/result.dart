import 'package:drais/core/error/failure.dart';

/// The return type of every repository method.
///
/// Repositories do not throw. A caller that has a `Result` in hand cannot
/// forget the failure case — the compiler refuses an incomplete `switch`.
/// That is the point: in LongTerm the equivalent guarantee is enforced by
/// convention (`docs/guides/API_ERROR_HANDLING_GUIDE.md`); here it is enforced
/// by the type system.
///
/// ```dart
/// final Result<AuthUser> result = await repo.login(email, password);
/// switch (result) {
///   case Ok<AuthUser>(:final value):  _onUser(value);
///   case Err<AuthUser>(:final failure): _onError(failure);
/// }
/// ```
sealed class Result<T> {
  /// Creates a result.
  const Result();

  /// Whether this is an [Ok].
  bool get isOk => this is Ok<T>;

  /// Whether this is an [Err].
  bool get isErr => this is Err<T>;

  /// The value, or null when this is an [Err].
  T? get valueOrNull => switch (this) {
    Ok<T>(:final T value) => value,
    Err<T>() => null,
  };

  /// The failure, or null when this is an [Ok].
  Failure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final Failure failure) => failure,
  };

  /// Transforms the success value, leaving a failure untouched.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T>(:final T value) => Ok<R>(transform(value)),
    Err<T>(:final Failure failure) => Err<R>(failure),
  };

  /// Chains another fallible operation onto a success.
  Future<Result<R>> flatMap<R>(
    Future<Result<R>> Function(T value) next,
  ) async => switch (this) {
    Ok<T>(:final T value) => await next(value),
    Err<T>(:final Failure failure) => Err<R>(failure),
  };

  /// Collapses both cases into one value.
  R fold<R>({
    required R Function(T value) onOk,
    required R Function(Failure failure) onErr,
  }) => switch (this) {
    Ok<T>(:final T value) => onOk(value),
    Err<T>(:final Failure failure) => onErr(failure),
  };
}

/// A successful result carrying [value].
final class Ok<T> extends Result<T> {
  /// Creates a successful result.
  const Ok(this.value);

  /// The value produced by the operation.
  final T value;

  @override
  String toString() => 'Ok<$T>($value)';
}

/// A failed result carrying [failure].
final class Err<T> extends Result<T> {
  /// Creates a failed result.
  const Err(this.failure);

  /// Why the operation failed.
  final Failure failure;

  @override
  String toString() => 'Err<$T>($failure)';
}
