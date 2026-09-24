import Foundation
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock(); private var value: Value
    init(_ value:Value) { self.value = value }
    func withValue<T>(_ body:(inout Value)->T) -> T { lock.lock();defer{lock.unlock()};return body(&value) }
}
