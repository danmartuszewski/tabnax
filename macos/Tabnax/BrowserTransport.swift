import Foundation
import Darwin

final class BrowserPeer: @unchecked Sendable {
    let id = UUID()
    private let descriptor: Int32
    private let lock = NSLock()
    private let writes = DispatchQueue(label:"pl.tabnax.browser-write",qos:.userInitiated)
    private var closed = false
    private var pendingWrites = 0
    init(_ fd:Int32) {
        descriptor = fd
        var noSignal: Int32 = 1
        setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&noSignal,socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec:0,tv_usec:500_000)
        setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout<timeval>.size))
    }
    func send(_ object:[String:Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject:object) else { return }
        send(data)
    }
    /// Accepts already-encoded JSON `Data` directly, skipping the
    /// encode/decode/re-encode round trip a `[String:Any]` payload would need.
    func send(_ data:Data) {
        guard data.count <= 1_048_576 else { return }
        lock.lock()
        guard !closed else { lock.unlock(); return }
        // A stalled browser cannot block the main thread or accumulate an
        // unbounded queue. Disconnecting forces a fresh, observed handshake.
        guard pendingWrites < 8 else { lock.unlock(); close(); return }
        pendingWrites += 1
        writes.async { [self] in
            lock.lock(); let canWrite = !closed; lock.unlock()
            if canWrite && !BrowserWire.write(data,to:descriptor) { close() }
            lock.lock(); pendingWrites -= 1; lock.unlock()
        }
        lock.unlock()
    }
    func read() -> Data? { BrowserWire.read(from:descriptor) }
    func close() {
        lock.lock(); defer { lock.unlock() }; guard !closed else { return }
        closed = true; shutdown(descriptor,SHUT_RDWR)
        // Keep the descriptor allocated until the last in-flight write exits.
        writes.async { [self] in Darwin.close(descriptor) }
    }
}
/// Length-prefixed JSON over a same-user Unix socket. No TCP listener, browser
/// debugging port, page content, or persistent tab database is involved.
enum BrowserWire {
    static var socketPath:String { "/private/tmp/pl.tabnax/\(getuid())/bridge.sock" }
    static func address() -> sockaddr_un {
        var addr = sockaddr_un(); addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(socketPath.utf8) + [0]
        withUnsafeMutableBytes(of:&addr.sun_path) { raw in raw.copyBytes(from:bytes) }
        return addr
    }
    static func connectSocket() -> Int32? {
        let fd = socket(AF_UNIX,SOCK_STREAM,0); guard fd >= 0 else { return nil }
        var address = address()
        let result = withUnsafePointer(to:&address) { pointer in pointer.withMemoryRebound(to:sockaddr.self,capacity:1) { connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0 else { Darwin.close(fd); return nil }; return fd
    }
    static func read(from fd:Int32) -> Data? {
        func exact(_ count:Int) -> Data? {
            var data = Data(count:count)
            let okay = data.withUnsafeMutableBytes { buffer in
                var offset = 0
                while offset < count {
                    let read = Darwin.read(fd,buffer.baseAddress!.advanced(by:offset),count-offset)
                    if read < 0 && errno == EINTR { continue }; guard read > 0 else { return false }; offset += read
                }
                return true
            }
            return okay ? data : nil
        }
        guard let header = exact(4) else { return nil }
        let count = header.enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset*8) }
        guard count > 0,count <= 1_048_576 else { return nil }; return exact(count)
    }
    static func write(_ data:Data,to fd:Int32) -> Bool {
        var size = UInt32(data.count).littleEndian
        var framed = withUnsafeBytes(of:&size) { Data($0) }; framed.append(data)
        return framed.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(fd,bytes.baseAddress!.advanced(by:offset),bytes.count-offset)
                if n < 0 && errno == EINTR { continue }; guard n > 0 else { return false }; offset += n
            }
            return true
        }
    }
    static func processPath(_ pid:pid_t) -> String {
        var bytes = [CChar](repeating:0,count:4096)
        let result = proc_pidpath(pid,&bytes,UInt32(bytes.count))
        return result > 0 ? String(cString:bytes) : ""
    }
}
