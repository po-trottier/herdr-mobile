// Canonical `Result<T>`/`Ok<T>`/`Err<T>` per `docs/41-code-standards.md` R-41-103.
//
// Single shared type, repository-wide. Every fallible operation crossing layer boundary
// returns this, never throws. `docs/20-mobile-framework.md` section 7.2 names this exact
// path (`app/lib/core/result/`) as the canonical home; `docs/90-implementation-plan.md`
// assigns ownership to Phase 13/WP-13-a (`Paths.` line, `Owns.` line).

/// The outcome of an operation that can fail for a known reason.
sealed class Result<T> {
  const Result();
}

/// The operation succeeded and produced [value].
final class Ok<T> extends Result<T> {
  const Ok(this.value);
  final T value;
}

/// The operation failed. [message] names the operation and the entity (R-41-028). [cause]
/// keeps the root error (R-41-027).
final class Err<T> extends Result<T> {
  const Err(this.message, {this.cause});
  final String message;
  final Object? cause;
}
