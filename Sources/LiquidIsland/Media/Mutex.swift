import Foundation

/// Простой замок вокруг значения — нужен там, где к состоянию обращаются
/// с фоновой очереди, а заводить актор ради одного поля излишне.
final class Mutex<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
