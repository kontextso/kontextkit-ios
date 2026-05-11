import Foundation

/// Wraps a value so it can cross `@Sendable` boundaries when the compiler
/// can't prove it's safe but the caller can. Use it only where the value
/// is built on one actor and consumed on the same actor (or a single
/// other actor) — never for genuinely shared mutable state.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
