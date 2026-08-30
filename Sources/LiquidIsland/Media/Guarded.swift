import Foundation

/// Простой замок вокруг значения — нужен там, где к состоянию обращаются
/// с фоновой очереди, а заводить актор ради одного поля излишне.
///
/// Имя намеренно не `Mutex`: так называется тип из стандартной библиотеки
/// Swift 6, и совпадение ломает рантайму поиск конформансов.
final class Guarded<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
